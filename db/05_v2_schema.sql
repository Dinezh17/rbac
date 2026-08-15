/* ============================================================================
   05_v2_schema.sql
   RBAC v2: fine-grained module.action permissions + a second, independent
   data-scope dimension (Section, alongside Department), combinable per role
   as ANY (union) or ALL (intersection).

   Everything here is additive to 01-04: new columns, new tables, and
   in-place renames of existing Permission codes (safe - RolePermissions
   keeps pointing at the same PermissionId, only the Code string changes).
   No existing table is dropped or restructured.
   ============================================================================ */

USE hrms;
GO

/* ----------------------------------------------------------------------
   Second scope dimension: Sections (sub-units within a Department).
   Deliberately NOT under row-level security - like Departments, this is
   small, non-sensitive master/reference data. What's access-controlled is
   who can be ASSIGNED to a section (an editability question, handled by
   fn_AssignableSections in 07_v2_row_level_security.sql) and which
   Employee/Payroll/LeaveRequests ROWS a section membership makes visible
   (a row-visibility question, handled by the RLS predicate). The section
   NAME itself is not a secret.
   ---------------------------------------------------------------------- */

CREATE TABLE dbo.Sections (
    SectionId       INT IDENTITY(1,1) PRIMARY KEY,
    SectionName     NVARCHAR(100)   NOT NULL,
    DepartmentId    INT             NOT NULL REFERENCES dbo.Departments(DepartmentId)
);
GO

CREATE INDEX IX_Sections_DepartmentId ON dbo.Sections(DepartmentId);
GO

ALTER TABLE dbo.Employees ADD SectionId INT NULL REFERENCES dbo.Sections(SectionId);
GO

CREATE INDEX IX_Employees_SectionId ON dbo.Employees(SectionId);
GO

/* ----------------------------------------------------------------------
   Per-user, multi-select Section assignments - same shape as the existing
   UserScopeDepartments table from v1.
   ---------------------------------------------------------------------- */

CREATE TABLE dbo.UserScopeSections (
    UserId          INT NOT NULL REFERENCES dbo.AppUsers(UserId),
    SectionId       INT NOT NULL REFERENCES dbo.Sections(SectionId),
    PRIMARY KEY (UserId, SectionId)
);
GO

/* ----------------------------------------------------------------------
   Roles: generalize the old single-dimension 'DEPARTMENT' scope type into
   'SELECTED' (multi-dimension: Department and/or Section), and add a
   combinator that decides how the dimensions combine when a role has
   assignments in more than one:

     ANY  (default) - union. Visible if the row's department OR section
          matches one of the role's assigned values. This is the common
          case: department and section are two alternative ways of
          granting the same access (e.g. "HR dept, OR the cross-functional
          Talent Acquisition section wherever it sits").

     ALL  - intersection. Every dimension the role has at least one
          assignment in must independently match (a dimension with zero
          assignments is not a restriction on its own - see the predicate
          comments in 07_v2_row_level_security.sql for the exact fail-
          closed rule). Use this when department and section are meant to
          both narrow the same grant (e.g. "only Engineering AND only the
          Platform section" - narrower than either alone).

   Convention: a user is expected to hold at most one SELECTED-scope role
   at a time. UserScopeDepartments/UserScopeSections are keyed by user, not
   by role, so two simultaneous SELECTED roles with different combinators
   on the same user would be ambiguous - broaden one role's assignments
   instead of assigning a second.
   ---------------------------------------------------------------------- */

DECLARE @scopeTypeConstraint NVARCHAR(200);
SELECT @scopeTypeConstraint = cc.name
FROM sys.check_constraints cc
JOIN sys.columns col ON col.object_id = cc.parent_object_id AND col.column_id = cc.parent_column_id
WHERE cc.parent_object_id = OBJECT_ID('dbo.Roles') AND col.name = 'ScopeType';

IF @scopeTypeConstraint IS NOT NULL
BEGIN
    DECLARE @dropSql NVARCHAR(400) = N'ALTER TABLE dbo.Roles DROP CONSTRAINT ' + QUOTENAME(@scopeTypeConstraint);
    EXEC(@dropSql);
END
GO

UPDATE dbo.Roles SET ScopeType = 'SELECTED' WHERE ScopeType = 'DEPARTMENT';
GO

ALTER TABLE dbo.Roles ADD CONSTRAINT CK_Roles_ScopeType
    CHECK (ScopeType IN ('ALL', 'SELECTED', 'TEAM', 'OWN'));
GO

ALTER TABLE dbo.Roles ADD ScopeCombinator VARCHAR(3) NOT NULL DEFAULT 'ANY'
    CONSTRAINT CK_Roles_ScopeCombinator CHECK (ScopeCombinator IN ('ANY', 'ALL'));
GO

/* ----------------------------------------------------------------------
   Permissions: rename v1's colon codes to the module.action convention,
   and add the missing module.action rows for Department, Section, and the
   employee write actions v1 only stubbed (employee:write existed as a
   catalog row but no endpoint used it - v2 implements employee.edit for
   real, see backend/app/routers/employees.py).

   Renaming in place (UPDATE, not delete+insert) preserves every existing
   RolePermissions row's linkage automatically - nothing to re-grant for
   permissions that already existed under the old name.
   ---------------------------------------------------------------------- */

UPDATE dbo.Permissions SET Code = 'employee.view'   WHERE Code = 'employee:read';
UPDATE dbo.Permissions SET Code = 'employee.edit'   WHERE Code = 'employee:write';
UPDATE dbo.Permissions SET Code = 'employee.delete' WHERE Code = 'employee:delete';
UPDATE dbo.Permissions SET Code = 'payroll.view'    WHERE Code = 'payroll:read';
UPDATE dbo.Permissions SET Code = 'payroll.edit'    WHERE Code = 'payroll:write';
UPDATE dbo.Permissions SET Code = 'payroll.approve' WHERE Code = 'payroll:approve';
UPDATE dbo.Permissions SET Code = 'leave.view'      WHERE Code = 'leave:read';
UPDATE dbo.Permissions SET Code = 'leave.add'       WHERE Code = 'leave:write';
UPDATE dbo.Permissions SET Code = 'leave.approve'   WHERE Code = 'leave:approve';
GO

INSERT INTO dbo.Permissions (Code, Description) VALUES
    ('employee.add',     'Create new employee records'),
    ('department.view',  'View the department master list'),
    ('department.add',   'Create departments'),
    ('department.edit',  'Edit departments'),
    ('department.delete','Delete departments'),
    ('section.view',     'View the section master list'),
    ('section.add',      'Create sections'),
    ('section.edit',     'Edit sections'),
    ('section.delete',   'Delete sections');
GO
