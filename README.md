# HRMS RBAC + Data Scope — reference implementation

This repo answers the brief in [CLAUDE.md](CLAUDE.md): design and demonstrate
role-based access control with **data scope** (row-level access) for an HRMS
whose real backend is ~200k LOC of complex, multi-table-join queries that
cannot be rewritten. It's a working FastAPI + SQL Server + React app, sized
down for demonstration, but the enforcement mechanism is the exact pattern
you'd point at the real system.

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
| `alice.chen` | Executive | ALL | All 11 employees |
| `bob.singh` | HR Business Partner | DEPARTMENT (HR + Finance) | 4 employees |
| `carol.mehta` | Engineering Manager | TEAM | Herself + 2 direct reports = 3 |
| `david.kim` | Employee | OWN | Herself/himself only = 1 |

Log in as each and compare the Employees table — same query, four different
result sets, no client-side filtering involved.

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
