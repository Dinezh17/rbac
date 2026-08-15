/* ============================================================================
   03_row_level_security.sql
   The zero-invasion data-scope enforcement layer.

   Mechanism: SQL Server Row-Level Security (2016+).
     1. An inline, schema-bound table-valued function ("the predicate")
        decides, for a given owning EmployeeId, whether the CURRENT session
        is allowed to see that row.
     2. A SECURITY POLICY binds that predicate to every sensitive table as
        both a FILTER predicate (SELECT/UPDATE/DELETE silently drop rows
        outside scope) and a BLOCK predicate (INSERT/UPDATE cannot create
        or move a row outside the caller's own scope).
     3. The predicate reads WHO is asking from SESSION_CONTEXT(N'app_user_id'),
        which the FastAPI data layer sets once per request (see
        backend/app/db/session.py).

   Why this satisfies "additive, low-invasion, works on complex joins":
     - The policy is bound to the TABLE, not to any specific query. Every
       existing query that touches Employees/Payroll/LeaveRequests -
       however many joins deep, however it's written, ORM or raw SQL -
       gets the filter applied automatically by the query optimizer. There
       is no WHERE clause to add anywhere in the 200k LOC query layer.
     - The only integration point application code needs is "set who is
       asking" once at the start of each request/connection use. That's
       the "one line" (really: one dependency) called out in CLAUDE.md.
     - It is enforced by the database engine itself, so it also protects
       against a forgotten scope check in some future ad-hoc report query,
       a BI tool connecting directly, or a bug in application code -
       defense in depth beyond the FastAPI-level RBAC permission checks.

   Critical operational detail (connection pooling):
     SESSION_CONTEXT is scoped to the physical SQL Server session, i.e. the
     pooled connection - NOT to a request. Because connections are reused
     across requests, the application MUST call sp_set_session_context
     with @read_only = 0 (NOT 1) as the very first statement on every
     borrowed connection, on every request, before running any other
     query. If @read_only were set to 1, the value would be locked for the
     lifetime of that physical connection and the NEXT request to reuse it
     from the pool would silently inherit the WRONG user's scope. See
     backend/app/db/session.py for where this is enforced.
   ============================================================================ */

USE hrms;
GO

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
                        SELECT 1
                        FROM dbo.EmployeeHierarchyClosure AS c
                        WHERE c.ManagerEmployeeId = u.EmployeeId
                          AND c.SubordinateEmployeeId = @OwnerEmployeeId
                 ))

             OR (r.ScopeType = 'DEPARTMENT'
                 AND EXISTS (
                        SELECT 1
                        FROM dbo.UserScopeDepartments AS usd
                        JOIN dbo.Employees AS owner ON owner.EmployeeId = @OwnerEmployeeId
                        WHERE usd.UserId = u.UserId
                          AND usd.DepartmentId = owner.DepartmentId
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

/* ----------------------------------------------------------------------
   Bringing a new table under scope enforcement later, e.g. dbo.Documents
   with an EmployeeId owner column, is a single ALTER SECURITY POLICY
   statement - not a rewrite of every query that touches it:

     ALTER SECURITY POLICY dbo.EmployeeDataScopePolicy
         ADD FILTER PREDICATE dbo.fn_DataScopePredicate(EmployeeId) ON dbo.Documents,
         ADD BLOCK PREDICATE  dbo.fn_DataScopePredicate(EmployeeId) ON dbo.Documents AFTER INSERT,
         ADD BLOCK PREDICATE  dbo.fn_DataScopePredicate(EmployeeId) ON dbo.Documents AFTER UPDATE;
   ---------------------------------------------------------------------- */
