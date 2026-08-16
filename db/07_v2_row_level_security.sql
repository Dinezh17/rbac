/* ============================================================================
   07_v2_row_level_security.sql
   Extends the RLS predicate to understand 'SELECTED' scope (Department
   and/or Section, per role ScopeCombinator), and adds the two functions
   that answer the EDITABILITY question for scoped foreign keys:
   fn_AssignableDepartments / fn_AssignableSections.

   ----------------------------------------------------------------------
   WHY TWO SEPARATE THINGS ("visible" vs "assignable") FOR THE SAME DATA
   ----------------------------------------------------------------------
   Row-VISIBILITY (fn_DataScopePredicate, below) answers "can this user see
   this Employee row at all" - enforced by the RLS policy on every SELECT/
   UPDATE/DELETE against Employees/Payroll/LeaveRequests, exactly as in v1.

   Field-EDITABILITY (fn_AssignableDepartments / fn_AssignableSections)
   answers a narrower, different question: "of all Department/Section
   values that exist, which ones is this user allowed to WRITE into a
   DepartmentId/SectionId column" - used to build edit-form dropdowns
   (see backend/app/routers/departments.py, .../sections.py) and to
   server-side-validate a submitted change before it's written.

   These are not the same question and can have different answers for the
   same user - see Bob Singh in 06_v2_seed_data.sql: his Department scope
   (HR + Finance) makes every HR/Finance employee VISIBLE to him, but his
   narrower Section scope (Core HR + Core Finance only) means he cannot
   ASSIGN someone to "Talent Acquisition", even though he can see and edit
   other fields on a Talent Acquisition employee's record (Priya Nair).
   That gap is exactly the "editor can't see the value the creator picked"
   case this file exists to handle - see README.md's "RBAC v2" section for
   the full edge-case analysis and how the API/frontend use these
   functions together to keep an out-of-scope field visible-but-locked
   instead of blank or silently overwritten.
   ============================================================================ */

USE hrms;
GO

-- A security policy's predicate functions can't be ALTERed while the
-- policy still references them, even disabled (STATE = OFF keeps the
-- reference, it just stops enforcing it) - SQL Server rejects the ALTER
-- FUNCTION outright. Dropping and recreating the policy is the correct,
-- if blunt, way to change a bound predicate function's body. In
-- production this is a brief window with RLS off entirely on these
-- tables - do it in a maintenance window or wrap the app-facing impact
-- with a maintenance-mode flag, the same as any other online-schema-change
-- caveat.
DROP SECURITY POLICY dbo.EmployeeDataScopePolicy;
GO

/* ----------------------------------------------------------------------
   fn_AssignableDepartments / fn_AssignableSections
   "Which values of this dimension can @AppUserId write into a scoped FK
   column", aggregated (unioned) across every role the user holds:
     - ALL scope        -> every department/section (org-wide)
     - SELECTED scope    -> exactly their UserScopeDepartments/Sections rows
     - TEAM / OWN scope  -> only their own employee record's current value
                            (a manager can't reassign someone to a
                            department/section they don't themselves
                            belong to, unless also given a SELECTED role)

   Hidden dependency, confirmed by testing rather than just reasoned about:
   the TEAM/OWN branch reads dbo.Employees, which is itself RLS-protected.
   That inner read only returns a row if SESSION_CONTEXT('app_user_id') is
   already set to someone who can see @AppUserId's own employee record.
   Calling fn_AssignableDepartments(@uid) from a plain admin session with
   no context set - e.g. an ad-hoc query in SSMS - silently returns EMPTY
   for TEAM/OWN users even though the ALL/SELECTED branches still work
   (they never touch Employees). This is a non-issue for real requests:
   backend/app/deps.py's get_scoped_db always sets session_context to the
   CALLER's own user id before any query runs, and every scope type always
   includes the caller's own row (OWN trivially; TEAM via the closure
   table's self-at-depth-0 anchor; ALL/SELECTED by definition) - so
   "what's assignable to me" always has a matching context by
   construction. The rule to preserve if this code changes: never call
   these functions for a user other than whoever session_context is
   currently set to.
   ---------------------------------------------------------------------- */

CREATE OR ALTER FUNCTION dbo.fn_AssignableDepartments(@AppUserId INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT DISTINCT d.DepartmentId
    FROM dbo.Departments d
    WHERE EXISTS (
        SELECT 1
        FROM dbo.AppUsers u
        JOIN dbo.UserRoles ur ON ur.UserId = u.UserId
        JOIN dbo.Roles r ON r.RoleId = ur.RoleId
        WHERE u.UserId = @AppUserId
          AND u.IsActive = 1
          AND (
                r.ScopeType = 'ALL'
             OR (r.ScopeType = 'SELECTED' AND EXISTS (
                    SELECT 1 FROM dbo.UserScopeDepartments usd
                    WHERE usd.UserId = u.UserId AND usd.DepartmentId = d.DepartmentId
                ))
             OR (r.ScopeType IN ('TEAM', 'OWN') AND EXISTS (
                    SELECT 1 FROM dbo.Employees e
                    WHERE e.EmployeeId = u.EmployeeId AND e.DepartmentId = d.DepartmentId
                ))
          )
    );
GO

CREATE OR ALTER FUNCTION dbo.fn_AssignableSections(@AppUserId INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT DISTINCT s.SectionId
    FROM dbo.Sections s
    WHERE EXISTS (
        SELECT 1
        FROM dbo.AppUsers u
        JOIN dbo.UserRoles ur ON ur.UserId = u.UserId
        JOIN dbo.Roles r ON r.RoleId = ur.RoleId
        WHERE u.UserId = @AppUserId
          AND u.IsActive = 1
          AND (
                r.ScopeType = 'ALL'
             OR (r.ScopeType = 'SELECTED' AND EXISTS (
                    SELECT 1 FROM dbo.UserScopeSections uss
                    WHERE uss.UserId = u.UserId AND uss.SectionId = s.SectionId
                ))
             OR (r.ScopeType IN ('TEAM', 'OWN') AND EXISTS (
                    SELECT 1 FROM dbo.Employees e
                    WHERE e.EmployeeId = u.EmployeeId AND e.SectionId = s.SectionId
                ))
          )
    );
GO

/* ----------------------------------------------------------------------
   fn_DataScopePredicate - same ALL/OWN/TEAM branches as v1, SELECTED
   branch rewritten for two dimensions + combinator. Written with direct
   EXISTS checks against UserScopeDepartments/UserScopeSections (not via
   the assignable-set functions above) to keep the security-critical path
   simple, flat, and independently verifiable - see the file header for
   why "visible" and "assignable" are intentionally two code paths sharing
   the same underlying tables rather than one shared function.
   ---------------------------------------------------------------------- */

CREATE OR ALTER FUNCTION dbo.fn_DataScopePredicate(@OwnerEmployeeId INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS fn_accesspredicate_result
    WHERE EXISTS (
        SELECT 1
        FROM dbo.AppUsers AS u
        JOIN dbo.UserRoles AS ur ON ur.UserId = u.UserId
        JOIN dbo.Roles AS r ON r.RoleId = ur.RoleId
        WHERE u.UserId = TRY_CAST(SESSION_CONTEXT(N'app_user_id') AS INT)
          AND u.IsActive = 1
          AND (
                r.ScopeType = 'ALL'

             OR (r.ScopeType = 'OWN'
                 AND u.EmployeeId = @OwnerEmployeeId)

             OR (r.ScopeType = 'TEAM'
                 AND EXISTS (
                        SELECT 1 FROM dbo.EmployeeHierarchyClosure AS c
                        WHERE c.ManagerEmployeeId = u.EmployeeId
                          AND c.SubordinateEmployeeId = @OwnerEmployeeId
                 ))

             OR (r.ScopeType = 'SELECTED' AND (

                    -- ANY (union, default): owner's department OR section
                    -- matches one of this user's assigned values.
                    (r.ScopeCombinator = 'ANY' AND (
                        EXISTS (
                            SELECT 1 FROM dbo.UserScopeDepartments usd
                            JOIN dbo.Employees owner ON owner.DepartmentId = usd.DepartmentId
                            WHERE usd.UserId = u.UserId AND owner.EmployeeId = @OwnerEmployeeId
                        )
                        OR EXISTS (
                            SELECT 1 FROM dbo.UserScopeSections uss
                            JOIN dbo.Employees owner ON owner.SectionId = uss.SectionId
                            WHERE uss.UserId = u.UserId AND owner.EmployeeId = @OwnerEmployeeId
                        )
                    ))

                    -- ALL (intersection): every dimension the user has at
                    -- least one assignment in must independently match; a
                    -- dimension with zero assignments doesn't restrict on
                    -- its own, but at least one dimension must be
                    -- populated (fail closed on a SELECTED role with no
                    -- assignments anywhere, rather than vacuously TRUE).
                    OR (r.ScopeCombinator = 'ALL'
                        AND (
                            EXISTS (SELECT 1 FROM dbo.UserScopeDepartments usd WHERE usd.UserId = u.UserId)
                            OR EXISTS (SELECT 1 FROM dbo.UserScopeSections uss WHERE uss.UserId = u.UserId)
                        )
                        AND (
                            NOT EXISTS (SELECT 1 FROM dbo.UserScopeDepartments usd WHERE usd.UserId = u.UserId)
                            OR EXISTS (
                                SELECT 1 FROM dbo.UserScopeDepartments usd
                                JOIN dbo.Employees owner ON owner.DepartmentId = usd.DepartmentId
                                WHERE usd.UserId = u.UserId AND owner.EmployeeId = @OwnerEmployeeId
                            )
                        )
                        AND (
                            NOT EXISTS (SELECT 1 FROM dbo.UserScopeSections uss WHERE uss.UserId = u.UserId)
                            OR EXISTS (
                                SELECT 1 FROM dbo.UserScopeSections uss
                                JOIN dbo.Employees owner ON owner.SectionId = uss.SectionId
                                WHERE uss.UserId = u.UserId AND owner.EmployeeId = @OwnerEmployeeId
                            )
                        )
                    )
             ))
          )
    );
GO

CREATE SECURITY POLICY dbo.EmployeeDataScopePolicy
    ADD FILTER PREDICATE dbo.fn_DataScopePredicate(EmployeeId) ON dbo.Employees,
    ADD BLOCK PREDICATE  dbo.fn_DataScopePredicate(EmployeeId) ON dbo.Employees AFTER INSERT,
    ADD BLOCK PREDICATE  dbo.fn_DataScopePredicate(EmployeeId) ON dbo.Employees AFTER UPDATE,

    ADD FILTER PREDICATE dbo.fn_DataScopePredicate(EmployeeId) ON dbo.Payroll,
    ADD BLOCK PREDICATE  dbo.fn_DataScopePredicate(EmployeeId) ON dbo.Payroll AFTER INSERT,
    ADD BLOCK PREDICATE  dbo.fn_DataScopePredicate(EmployeeId) ON dbo.Payroll AFTER UPDATE,

    ADD FILTER PREDICATE dbo.fn_DataScopePredicate(EmployeeId) ON dbo.LeaveRequests,
    ADD BLOCK PREDICATE  dbo.fn_DataScopePredicate(EmployeeId) ON dbo.LeaveRequests AFTER INSERT,
    ADD BLOCK PREDICATE  dbo.fn_DataScopePredicate(EmployeeId) ON dbo.LeaveRequests AFTER UPDATE
WITH (STATE = ON);
GO
