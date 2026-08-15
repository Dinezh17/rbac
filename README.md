# HRMS RBAC + Data Scope — reference implementation

This repo answers the brief in [CLAUDE.md](CLAUDE.md): design and demonstrate
role-based access control with **data scope** (row-level access) for an HRMS
whose real backend is ~200k LOC of complex, multi-table-join queries that
cannot be rewritten. It's a working FastAPI + SQL Server + React app, sized
down for demonstration, but the enforcement mechanism is the exact pattern
you'd point at the real system.

This document covers the original (v1) design first, then
**[RBAC v2](#rbac-v2-fine-grained-permissions--multi-dimensional-data-scope)**,
which replaces v1's single-dimension department scope with fully granular
`module.action` permissions and multi-select, multi-dimensional data scope
(Department *and/or* Section), and specifically tackles what happens when an
editor's assignable values don't include a value someone else already picked.
v2 is built directly on v1's foundation, not a rewrite.

Two authorization dimensions, deliberately kept separate:

| Dimension | Question it answers | Enforced by | Example |
|---|---|---|---|
| **RBAC** (action scope) | *Can this user perform this action at all?* | FastAPI dependency, checked against JWT claims | "Can view payroll", "Can approve leave" |
| **Data scope** (row scope) | *Which rows can this user's action touch?* | SQL Server Row-Level Security | "Only their department's employees" |

Conflating these is where most homegrown RBAC systems get tangled. Keeping
them orthogonal is what makes the "additive, low-invasion" requirement
achievable at all.

## The core idea, in one paragraph

A `SECURITY POLICY` bound to `Employees`, `Payroll`, and `LeaveRequests`
attaches a predicate function that every query against those tables is
silently filtered through — by the SQL Server query optimizer, not by
application code. It doesn't matter if the query is a simple `SELECT *` or a
six-table join buried in a legacy stored procedure: if it touches a protected
table, the filter applies. The only thing application code has to do is tell
the database *who's asking*, once per request, via
`sp_set_session_context`. That's the "one line" (really: one dependency)
called out in CLAUDE.md. Zero lines change in the existing query layer.

## Why this approach, and what else was considered

**Rejected: intercept/rewrite queries in the app or ORM layer.**
Appending a `WHERE DepartmentId IN (...)` via an ORM hook or query-builder
middleware only works for queries that layer actually mediates. The premise
of this project is hundreds of hand-written, multi-join queries — some
likely in stored procedures, some via raw SQL, possibly some via a reporting
tool that bypasses the app entirely. An interception layer has to cover
every access path or it silently under-protects the ones it misses. That's
the opposite of "low invasion" — it means finding and re-verifying every
query.

**Rejected: per-role SQL views.** Precomputed views (`vw_Employees_HR`,
`vw_Employees_Manager`, ...) don't compose with dynamic, per-user scope
(each manager sees a *different* subtree; each HR partner covers a
*different* department combination) without generating one view per user,
and they still require rewriting every existing query to point at the new
view instead of the base table.

**Chosen: SQL Server native Row-Level Security (2016+).** It attaches to the
table itself, not to any particular query text, so it's automatically
retroactive to the entire existing query layer, including joins and
self-joins. It's also the layer with the fewest ways to accidentally bypass
it — a forgotten scope check in some future ad-hoc report or a BI tool
connecting directly still gets filtered, because the enforcement lives below
the SQL, not above it. See [db/04_row_level_security.sql](db/04_row_level_security.sql)
for the predicate function and policy, with inline rationale.

**RBAC (action permissions) stays in the app**, as a FastAPI dependency
checked against permission codes embedded in the JWT at login — no DB
round-trip per request, and it's the natural place for "can this user hit
this endpoint at all" to live, since it's inherently about the API surface,
not about rows.

## Data-scope types

> **Superseded by v2:** the `DEPARTMENT` type described here was generalized
> into `SELECTED` (Department *and/or* Section, multiple values in each) —
> see [RBAC v2](#rbac-v2-fine-grained-permissions--multi-dimensional-data-scope).
> Left as-is below since the reasoning still applies; `SELECTED` is a strict
> superset of what `DEPARTMENT` did.

Four scope types cover the common HRMS access patterns; a role picks one:

- **ALL** — org-wide (e.g. CEO, CHRO)
- **DEPARTMENT** — one or more assigned departments (e.g. HR Business
  Partner covering HR + Finance)
- **TEAM** — self plus the entire transitive reporting subtree (e.g. an
  Engineering Manager), resolved via a materialized closure table
  (`EmployeeHierarchyClosure`) so it's an indexed lookup, not a recursive
  query evaluated per row — see the rationale in
  [db/02_hierarchy_closure.sql](db/02_hierarchy_closure.sql).
  Notice in the screenshots below that a manager's *own* manager
  disappears from the "Manager" column — the self-join to `Employees` for
  that row is filtered too, because RLS applies to every reference to a
  protected table, not just the "main" one in a query.
- **OWN** — self only (default employee self-service)

A user can hold multiple roles; scope is the union of what each role grants
(see the `OR`-of-role-checks in `fn_DataScopePredicate`).

## Architecture

```
React (TS)  ──JWT──>  FastAPI                         SQL Server
                        │                                 │
                        │ 1. permission check (RBAC)       │
                        │    against JWT claims,           │
                        │    no DB round-trip               │
                        │                                   │
                        │ 2. get_scoped_db(user):           │
                        │    EXEC sp_set_session_context     │
                        │    @key='app_user_id', @value=uid ─┼─> session-scoped
                        │                                   │   context set
                        │ 3. run the query exactly as        │
                        │    the existing codebase would ────┼─> RLS predicate
                        │                                   │   filters rows
                        │                                   │   transparently
```

- [`db/`](db/) — schema, RBAC/scope tables, hierarchy closure maintenance,
  and the RLS policy. Run in numeric order.
- [`backend/`](backend/) — FastAPI app. [`app/deps.py`](backend/app/deps.py)
  has both authorization dependencies; [`app/db/session.py`](backend/app/db/session.py)
  has the session-context plumbing and its pooling caveat;
  [`app/routers/employees.py`](backend/app/routers/employees.py) and
  [`payroll.py`](backend/app/routers/payroll.py) contain the example
  multi-table-join queries with no scope logic in the SQL.
- [`frontend/`](frontend/) — React + TS + Vite. Login, an employees table, a
  payroll table, and a leave request/approval flow, all permission-gated in
  the UI and scope-filtered by the API.

## Running it

Requires Docker, Python 3.11+, Node 18+, and the SQL Server ODBC driver
(17 or 18) installed locally for the backend's `pyodbc` connection.

```bash
# 1. Start SQL Server
docker compose up -d

# 2. Load schema, hierarchy trigger, seed data, then turn RLS on (in this order —
#    see the seed script header for why order matters)
sqlcmd -S localhost,1433 -U sa -P 'YourStrong!Passw0rd' -C -i db/01_schema.sql
sqlcmd -S localhost,1433 -U sa -P 'YourStrong!Passw0rd' -C -i db/02_hierarchy_closure.sql
sqlcmd -S localhost,1433 -U sa -P 'YourStrong!Passw0rd' -C -i db/03_seed_data.sql
sqlcmd -S localhost,1433 -U sa -P 'YourStrong!Passw0rd' -C -i db/04_row_level_security.sql

# v2: fine-grained permissions + Section scope dimension (see RBAC v2 below) - run in order too
sqlcmd -S localhost,1433 -U sa -P 'YourStrong!Passw0rd' -C -i db/05_v2_schema.sql
sqlcmd -S localhost,1433 -U sa -P 'YourStrong!Passw0rd' -C -i db/06_v2_seed_data.sql
sqlcmd -S localhost,1433 -U sa -P 'YourStrong!Passw0rd' -C -i db/07_v2_row_level_security.sql
sqlcmd -S localhost,1433 -U sa -P 'YourStrong!Passw0rd' -C -i db/08_v2_field_scope_guard.sql

# 3. Backend
cd backend
python -m venv .venv && .venv/Scripts/activate   # or source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload

# 4. Frontend
cd frontend
npm install
npm run dev   # http://localhost:5173
```

### Demo accounts (password for all: `Passw0rd!`)

| Username | Role | Scope type | What they see under Employees |
|---|---|---|---|
| `alice.chen` | Executive | ALL | All 12 employees |
| `bob.singh` | HR Business Partner | v2: SELECTED, dept HR + Finance | 5 employees |
| `carol.mehta` | Engineering Manager | TEAM | Herself + 2 direct reports = 3 |
| `david.kim` | Employee | OWN | Herself/himself only = 1 |

Log in as each and compare the Employees table — same query, four different
result sets, no client-side filtering involved. (Counts reflect the v2 seed
data, which adds a 12th employee, Nina Rao, in the HR department - see
[RBAC v2](#rbac-v2-fine-grained-permissions--multi-dimensional-data-scope)
for the fifth demo account, `nina.rao`.)

## What this demonstrates end-to-end (verified, not just asserted)

Every claim above was exercised against a real SQL Server container, not
just described:

- `sqlcmd`, setting `session_context` directly, confirmed the predicate
  filters `Employees` and `Payroll` correctly for all four scope types, and
  that **no session context set → zero rows** (fails closed, not open).
- The FastAPI layer, hit with `curl` while authenticated as each demo user,
  reproduced the same row counts through the actual multi-join endpoints,
  plus: a 403 when a role lacks the RBAC permission for an endpoint, and a
  404 (not a 403) when a request is *structurally* valid but the target row
  is outside the caller's data scope — e.g. `bob.singh` attempting to
  approve `david.kim`'s leave request, who is outside his department scope,
  gets "not found," because the row is genuinely invisible to his session,
  not just action-forbidden.
- The React app, driven headlessly end-to-end, rendered the correct,
  different row counts per logged-in user and showed zero console errors.

## Bringing this into the real 200k-LOC system

1. Add the RBAC/scope tables (`Roles`, `Permissions`, `RolePermissions`,
   `AppUsers`, `UserRoles`, `UserScopeDepartments`,
   `EmployeeHierarchyClosure`) — purely additive, no existing table is
   touched.
2. Write one predicate function per distinct "owner column" shape you have
   (most HRMS tables key off `EmployeeId`; a few might key off
   `DepartmentId` directly — that's a second, simpler predicate function).
3. Roll out with **`FILTER PREDICATE` only** first, in an environment where
   you can compare row counts against the old, application-level ACL logic
   you're replacing. Add `BLOCK PREDICATE` once you trust it — that's the
   write-side enforcement and is the one that would reject a bad insert/update.
4. Wherever the existing codebase opens a DB connection/session per
   request (a base repository class, a middleware, a DI container
   registration — every framework has exactly one or two such places even
   in a 200k-LOC app), add the `sp_set_session_context` call there. That is
   the entire integration surface. No individual query changes.
5. Extend the policy to more tables over time with `ALTER SECURITY POLICY
   ... ADD FILTER PREDICATE ...` — see the commented example at the bottom
   of [db/04_row_level_security.sql](db/04_row_level_security.sql).

## Production notes and honest limitations of this demo

- **Connection pooling correctness is the sharpest edge of this whole
  approach.** `SESSION_CONTEXT` lives on the physical connection, and
  pooled connections are reused across requests/users. `@read_only` must be
  `0` on every call, and the context must be set as the *first* statement
  on every borrowed connection, every request — see the comment block in
  `db/04_row_level_security.sql`. Get this wrong and one user's request can
  silently execute under a stale, previous user's scope. This demo sets it
  in a per-request dependency; a real rollout should add a test that
  specifically hammers this (rapid-fire requests as different users against
  a small pool) before trusting it in production.
- **`sysadmin`/`db_owner` are not exempt from RLS by default.** This
  surprises people the first time an admin's own ad-hoc query in SSMS comes
  back empty. If a service or reporting account genuinely needs unfiltered
  access, give it an explicit bypass branch in the predicate (checking for
  a specific service-account `app_user_id`, not just elevated DB
  permissions), not by relying on any assumed admin exemption.
- **JWT permission claims are a performance/freshness trade-off.**
  Permissions are baked into the token at login (fast: no DB hit per
  request) but a permission revoked mid-session stays valid until the
  token expires (60 min here). Data scope doesn't have this problem —
  it's re-evaluated from the database on every single query, so a scope
  change (e.g. a manager reassignment) takes effect on the very next
  request. If your compliance requirements need instant permission
  revocation too, shorten the token TTL and add refresh tokens, or move
  permission checks to a cached-but-invalidatable store instead of the JWT.
- **The hierarchy closure table does a full rebuild per org-chart change**
  (see rationale in `db/02_hierarchy_closure.sql`). Fine into the tens of
  thousands of employees; a very large org should switch to incremental
  closure maintenance or `HIERARCHYID`.
- **Not included, because they're orthogonal to the access-control
  question this repo answers:** refresh-token rotation, audit logging of
  who-saw-what, rate limiting, multi-tenancy, field-level (as opposed to
  row-level) masking of e.g. salary figures for users who can see the row
  but shouldn't see that column — that's SQL Server Dynamic Data Masking or
  column-level permissions, a separate, complementary feature worth adding
  alongside RLS if the real system needs it.

---

# RBAC v2: fine-grained permissions + multi-dimensional data scope

v1 proved the enforcement mechanism (RLS pushed to the DB, RBAC in the app,
zero query rewrites). v2 answers a sharper, more specific requirement:
permissions expressed as an explicit `module.action` grid
(`department.view` / `.add` / `.edit` / `.delete`, and the same shape for
every module), and data scope that's **multi-select across more than one
dimension at once** — a user can be scoped by department(s) *and/or*
section(s)/function(s) simultaneously, not just one flat list. That richer
scope model immediately surfaces a real, easy-to-miss failure mode, which is
the other half of this section: **what happens when the person editing a
record can't see the value the person who created it originally picked.**

## 1. The permission grid

Every action is now `<module>.<verb>`: `employee.view/.add/.edit/.delete`,
`payroll.view/.edit/.approve`, `leave.view/.add/.approve`,
`department.view/.add/.edit/.delete`, `section.view/.add/.edit/.delete`. Same
mechanism as v1 (`require_permission("department.edit")` as a FastAPI
dependency, checked against JWT claims) - this is a renaming and filling-out
of the matrix, not a new mechanism. See `db/05_v2_schema.sql` for the full
list and the in-place rename from v1's `employee:read`-style codes.

Department and Section became real, admin-managed entities in v2 (full CRUD
via `backend/app/routers/departments.py` / `sections.py`), not just
descriptive columns - that's what makes `department.edit` a meaningful,
independent permission rather than a hypothetical one.

## 2. Multi-dimensional data scope

`Roles.ScopeType = 'SELECTED'` (renamed from v1's `DEPARTMENT`) now draws
from **two** independent, multi-select assignment tables -
`UserScopeDepartments` and `UserScopeSections` (`db/05_v2_schema.sql`) - and
a `Roles.ScopeCombinator` decides how they combine when a role has entries
in both:

- **`ANY`** (default, union) - visible if the row's department **or**
  section matches one of the role's assigned values. Use this when
  department and section are alternative ways of granting the same access.
- **`ALL`** (intersection) - every dimension the role has *any* assignments
  in must independently match; a dimension with zero assignments doesn't
  restrict on its own, but at least one dimension must be populated (fail
  closed on a misconfigured role with no assignments anywhere, rather than
  vacuously granting everything). Use this when department and section are
  both meant to narrow the same grant.

Both branches are implemented as plain `EXISTS`/`AND`/`OR` boolean algebra
inside `fn_DataScopePredicate` (`db/07_v2_row_level_security.sql`) - no
nested function calls in the security-critical path, kept as close to v1's
proven, flat style as possible.

**This is a real, demonstrated capability, not just a config flag:** the
demo seeds a role scoped by Section *alone*, with **zero** Department
assignments (`nina.rao`, "Talent & Enterprise Analyst" - see
`db/06_v2_seed_data.sql`). She sees exactly the people in the "Talent
Acquisition" and "Enterprise" sections - which sit under **HR** and
**Sales** respectively, two entirely different departments - proving scope
can be genuinely cross-department when it's driven by a
Section/function dimension instead of the org chart. Verified with
`sqlcmd`, the API, and confirmed in the running app.

The `ANY` vs `ALL` difference was verified directly against the live
engine, not just reasoned about: temporarily flipping `bob.singh`'s
combinator to `ALL` dropped his visible headcount from 5 to 3, correctly
excluding the two people whose Department matched (HR/Finance) but whose
Section didn't (Talent Acquisition, FP&A) - proof the intersection logic
does what it claims, not just that it compiles.

## 3. The core problem: scoped foreign keys on an edit form

This is the case from the brief: User A creates or edits a record and picks
a value - say, Department - from a dropdown built from *their* access.
Later, User B, whose access is narrower, opens that same record. Two
questions collide:

- **Can User B see the record at all?** That's row visibility - RLS answers
  it, unchanged from v1.
- **Can User B's edit-form dropdown for Department even contain the value
  currently on the record?** Not necessarily - "which rows can I see" and
  "which values can I assign" are different questions that don't have to
  have the same answer for the same user.

### All the ways this goes wrong if unhandled

1. **Silent data corruption.** The dropdown doesn't include the record's
   current value, defaults to the first option in the list, and the user
   saves the form without ever intending to touch that field - the
   department silently changes.
2. **Legitimate work blocked.** The form's validation rejects "the value
   that's already there" as invalid, so the user can't save *any* change,
   even to an unrelated field like a phone number.
3. **Broken/confusing display.** If the referenced value's label lookup is
   itself scope-filtered, the field shows blank or a raw ID instead of a
   name, with no explanation.
4. **Ambiguous intent on partial updates.** If "field omitted from the
   request" and "field explicitly cleared" aren't distinguished, a backend
   that defaults missing fields will blank out exactly the field the
   frontend hid to avoid touching.

### The design decisions that resolve each one

**Master/reference data is not row-level-secured.** `Departments` and
`Sections` hold names, not sensitive per-row facts - everyone in the org can
already see the department list on an org chart. Row-level security is
reserved for *transactional* data (`Employees`, `Payroll`,
`LeaveRequests`) that *references* those lookups. This one decision
eliminates failure mode 3 structurally: a Department/Section name always
resolves, for anyone, regardless of their data scope - see the header
comment in `db/05_v2_schema.sql`. (Contrast with the *manager name* going
blank in the v1 screenshots - that's `Employees` self-referencing
`Employees`, and `Employees` genuinely is scope-protected, so that blank is
correct: you can't see the name of a manager who isn't in your visible set.
Different table, different rule, deliberately.)

**Visibility and assignability are two separate, explicit questions**,
each with its own answer:

| Question | Answered by | Used for |
|---|---|---|
| Which rows can I see/touch? | `fn_DataScopePredicate` (RLS) | Every SELECT/UPDATE against Employees/Payroll/LeaveRequests |
| Which Department/Section values can I assign? | `fn_AssignableDepartments` / `fn_AssignableSections` | Edit-form dropdowns, server-side write validation |

Both live in `db/07_v2_row_level_security.sql`, read from the *same*
`UserScopeDepartments`/`UserScopeSections` tables, but are answered as
distinct queries rather than one being derived from the other - see that
file's header comment for the full "why two functions, not one" rationale,
including a subtlety caught by testing rather than reasoning: the
assignable-set functions internally read `Employees` (for TEAM/OWN roles'
"only my own department" rule), which is itself RLS-protected, so they only
resolve correctly when called with the session already set to the same user
being asked about - exactly what the app always does, never what an ad-hoc
admin query does.

**A scoped field renders in one of two modes, never a silently-wrong
third.** In the edit form (`frontend/src/components/EmployeeEditModal.tsx`):
if the record's current value is in the caller's assignable set, it's a
normal dropdown restricted to that set. If it isn't, the field renders
**disabled**, showing the current value as plain text plus a one-line
explanation - and is then structurally excluded from the submitted payload,
not just visually greyed out. There is no state where the field is editable
but wrong, or blank, or defaults to something the user didn't choose.

**Partial updates use `exclude_unset`, not `exclude_none`.** `EmployeeUpdate`
(`backend/app/schemas/hrms.py`) has every field optional; the PATCH handler
(`backend/app/routers/employees.py::update_employee`) only writes columns
that were actually present in the request body:

```python
changes = payload.model_dump(exclude_unset=True)
```

A field the frontend never sent - because it rendered locked - is never
part of the `UPDATE ... SET` clause at all. This is the mechanism, not the
disabled `<input>`, that actually prevents the corruption in failure mode 1;
the disabled input is what stops the user from *trying*.

### What happens if User B tries anyway (defense in depth, three independent layers)

The UI hides out-of-scope options, but a request can always be crafted by
hand, so the same rule is enforced three times, none trusting the others -
verified independently against the live database, not assumed:

1. **App layer** (`update_employee`): re-checks any submitted
   `department_id`/`section_id` against the caller's assignable set,
   *before* touching the database. Fast path, clearest error message.
2. **Database trigger** (`trg_Employees_GuardScopedFieldWrites`,
   `db/08_v2_field_scope_guard.sql`): re-validates the same rule inside SQL
   Server itself, for any INSERT/UPDATE reaching `Employees` from *any*
   client, not just this API. This is the layer RLS alone can't provide -
   `BLOCK PREDICATE` protects row *visibility*, but a value change that
   keeps the row visible overall (e.g. Department unchanged, only Section
   changed to something the row-visibility check doesn't itself object to)
   sails through RLS untouched. The trigger only fires when a value
   *actually changes* (compares `inserted` against `deleted`), so editing
   an unrelated field never re-validates an untouched one.
3. **RLS `BLOCK PREDICATE`** (unchanged from v1): independently re-validates
   overall row visibility of the post-update row - catches the case where a
   change would move the row somewhere the caller can't see it *at all*
   (verified live: `bob.singh` attempting to move an employee to Engineering
   was rejected by this layer specifically, not the new trigger).

## 4. Reproducing the scenario yourself

1. Log in as `alice.chen` (ALL scope) and open Priya Nair's edit form -
   Department and Section are both live dropdowns; her Section is "Talent
   Acquisition".
2. Log out, log in as `bob.singh` (HR Business Partner: Department scope
   HR+Finance, but a **narrower** Section scope of only "Core HR" +
   "Core Finance" - deliberately seeded this way in
   `db/06_v2_seed_data.sql`). He can see Priya (her department, HR, is in
   his scope) and open her edit form.
3. Her Department field is an editable dropdown (HR is his to assign).
   Her **Section field is disabled**, showing "Talent Acquisition" with the
   out-of-scope note - a value he can see displayed but never chose and
   cannot reassign.
4. Edit her job title and save. The job title changes; the Section stays
   exactly "Talent Acquisition" - confirmed via API response and a
   screenshot showing the unchanged value in the table afterward.
5. Try (via the API directly) to set her Section to "FP&A" - `403`, blocked
   before it reaches the database. Set it to "Core HR" (in Bob's scope) -
   succeeds. Both re-confirmed with `sqlcmd` acting as Bob directly against
   the trigger, independent of the API layer.

## 5. Demo account added in v2

| Username | Role | Scope | What it proves |
|---|---|---|---|
| `nina.rao` | Talent & Enterprise Analyst | `SELECTED`, Section only: Talent Acquisition + Enterprise, **no** Department assignment | Cross-department scope driven purely by function/section, spanning HR and Sales |

(Password `Passw0rd!`, same as every other demo account.)

## 6. v2-specific limitations, stated plainly

- **The assignable-set functions require the caller's own session context.**
  Documented and tested in `db/07_v2_row_level_security.sql` - calling
  `fn_AssignableDepartments` for anyone other than whoever
  `SESSION_CONTEXT('app_user_id')` currently is silently returns an empty
  set for TEAM/OWN-scoped users. Never an issue in the app's own call
  pattern; would be an issue for a future "admin looks up what user X can
  assign" feature, which would need its own, explicit code path.
- **A user is assumed to hold at most one `SELECTED`-type role at a time.**
  `UserScopeDepartments`/`UserScopeSections` are keyed by user, not by
  role, so two simultaneous `SELECTED` roles with different combinators on
  the same person would be ambiguous. Broaden one role's assignments
  instead of layering a second - stated explicitly in
  `db/05_v2_schema.sql` rather than silently assumed.
- **Changing the RLS predicate function's body requires briefly dropping
  and recreating the security policy** (`db/07_v2_row_level_security.sql`)
  - SQL Server refuses to `ALTER` a schema-bound function while any
  security policy still references it, even a disabled one. A production
  rollout of a predicate change should do this in a maintenance window.
- **`OUTPUT INSERTED.col` doesn't work against `Employees` any more.** Once
  a table has any enabled trigger (the v1 hierarchy-closure trigger, now
  joined by the v2 field-scope guard), SQL Server rejects an `OUTPUT`
  clause without an `INTO`. `create_employee`/`update_employee`
  (`backend/app/routers/employees.py`) use `SCOPE_IDENTITY()` and
  `rowcount` instead - worth knowing before adding a third trigger to this
  table and reflexively reaching for `OUTPUT` again.
- **Manager reassignment isn't exposed in the edit UI**, though the API
  supports it. A "who can I set as this person's manager" picker is the
  same class of problem as Department/Section (visible-vs-assignable), just
  keyed on the employee hierarchy instead of a lookup table - a natural
  next extension using the same pattern, not a different one.
