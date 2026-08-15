/* ============================================================================
   06_v2_seed_data.sql
   Sections master data + employee assignments, permission grants for the
   new module.action codes, and one new employee/user/role that exercises
   pure cross-department SECTION scoping (no department assignment at all).

   Also sets up the exact scenario CLAUDE.md's v2 follow-up describes: Alice
   (ALL scope) assigns Priya Nair to the "Talent Acquisition" section. Bob
   (HR Business Partner) can see Priya - she's in his Department scope (HR)
   - but his OWN Section scope only covers "Core HR" + "Core Finance", not
   "Talent Acquisition". Editing Priya as Bob is the reproduction case for
   the locked-field behavior described in README's v2 section.
   ============================================================================ */

USE hrms;
GO

-- v1's RLS policy (04_row_level_security.sql) is already ON by this point
-- in the migration sequence, and this script both INSERTs and UPDATEs
-- dbo.Employees. Same reason as 03_seed_data.sql running before RLS
-- existed at all: with no session_context set, the FILTER predicate
-- would silently match 0 rows on the UPDATEs and the BLOCK predicate
-- would reject the INSERT outright. Disable for the duration of this
-- script, exactly as an offline batch/migration job would.
ALTER SECURITY POLICY dbo.EmployeeDataScopePolicy WITH (STATE = OFF);
GO

INSERT INTO dbo.Sections (SectionName, DepartmentId) VALUES
    (N'Leadership',         (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Executive')),
    (N'Platform',            (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Engineering')),
    (N'Product Engineering', (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Engineering')),
    (N'Core HR',             (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'HR')),
    (N'Talent Acquisition',  (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'HR')),
    (N'Core Finance',        (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Finance')),
    (N'FP&A',                (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Finance')),
    (N'Enterprise',          (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Sales')),
    (N'SMB',                 (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Sales'));
GO

UPDATE dbo.Employees SET SectionId = (SELECT SectionId FROM dbo.Sections WHERE SectionName = N'Leadership')          WHERE Email = N'alice.chen@lakshmicorp.co.in';
UPDATE dbo.Employees SET SectionId = (SELECT SectionId FROM dbo.Sections WHERE SectionName = N'Platform')            WHERE Email = N'frank.nolan@lakshmicorp.co.in';
UPDATE dbo.Employees SET SectionId = (SELECT SectionId FROM dbo.Sections WHERE SectionName = N'Platform')            WHERE Email = N'carol.mehta@lakshmicorp.co.in';
UPDATE dbo.Employees SET SectionId = (SELECT SectionId FROM dbo.Sections WHERE SectionName = N'Platform')            WHERE Email = N'david.kim@lakshmicorp.co.in';
UPDATE dbo.Employees SET SectionId = (SELECT SectionId FROM dbo.Sections WHERE SectionName = N'Product Engineering') WHERE Email = N'grace.lee@lakshmicorp.co.in';
UPDATE dbo.Employees SET SectionId = (SELECT SectionId FROM dbo.Sections WHERE SectionName = N'Core HR')             WHERE Email = N'bob.singh@lakshmicorp.co.in';
UPDATE dbo.Employees SET SectionId = (SELECT SectionId FROM dbo.Sections WHERE SectionName = N'Talent Acquisition')  WHERE Email = N'priya.nair@lakshmicorp.co.in';
UPDATE dbo.Employees SET SectionId = (SELECT SectionId FROM dbo.Sections WHERE SectionName = N'Core Finance')        WHERE Email = N'rahul.verma@lakshmicorp.co.in';
UPDATE dbo.Employees SET SectionId = (SELECT SectionId FROM dbo.Sections WHERE SectionName = N'FP&A')                WHERE Email = N'sara.iyer@lakshmicorp.co.in';
UPDATE dbo.Employees SET SectionId = (SELECT SectionId FROM dbo.Sections WHERE SectionName = N'Enterprise')          WHERE Email = N'tom.fischer@lakshmicorp.co.in';
UPDATE dbo.Employees SET SectionId = (SELECT SectionId FROM dbo.Sections WHERE SectionName = N'Enterprise')          WHERE Email = N'uma.pillai@lakshmicorp.co.in';
GO

/* ---- New employee + user demonstrating pure cross-department SECTION scope ---- */

INSERT INTO dbo.Employees (FullName, JobTitle, DepartmentId, LocationId, ManagerId, HireDate, Email, SectionId) VALUES
(N'Nina Rao', N'People Analytics Lead',
    (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'HR'),
    (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Mumbai'),
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'alice.chen@lakshmicorp.co.in'),
    '2022-01-10', N'nina.rao@lakshmicorp.co.in',
    (SELECT SectionId FROM dbo.Sections WHERE SectionName = N'Core HR'));
GO

EXEC dbo.sp_RebuildEmployeeHierarchyClosure;
GO

INSERT INTO dbo.Roles (RoleName, ScopeType, ScopeCombinator, Description) VALUES
    ('Talent & Enterprise Analyst', 'SELECTED', 'ANY',
     'Cross-department read access via Section only - no Department assignment at all');
GO

INSERT INTO dbo.RolePermissions (RoleId, PermissionId)
SELECT (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Talent & Enterprise Analyst'), PermissionId
FROM dbo.Permissions WHERE Code = 'employee.view';
GO

INSERT INTO dbo.AppUsers (Username, PasswordHash, EmployeeId) VALUES
('nina.rao', '$2b$12$8wxk7rwkPP36vGKBKrz/vuyIFvnwkwHsVl6lQWzlClnU4I4hk2x4O',
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'nina.rao@lakshmicorp.co.in'));
GO

INSERT INTO dbo.UserRoles (UserId, RoleId) VALUES
    ((SELECT UserId FROM dbo.AppUsers WHERE Username = 'nina.rao'),
     (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Talent & Enterprise Analyst'));
GO

-- Note: no UserScopeDepartments rows for Nina at all - her access comes
-- entirely through the Section dimension, spanning HR and Sales.
INSERT INTO dbo.UserScopeSections (UserId, SectionId) VALUES
    ((SELECT UserId FROM dbo.AppUsers WHERE Username = 'nina.rao'),
     (SELECT SectionId FROM dbo.Sections WHERE SectionName = 'Talent Acquisition')),
    ((SELECT UserId FROM dbo.AppUsers WHERE Username = 'nina.rao'),
     (SELECT SectionId FROM dbo.Sections WHERE SectionName = 'Enterprise'));
GO

/* ---- Bob (HR Business Partner): narrower Section scope than Department scope.
   Department scope (from v1, unchanged) = HR + Finance -> drives which EMPLOYEE
   ROWS he can see. Section scope here is deliberately narrower - only the
   two "Core" sections, not Talent Acquisition or FP&A -> drives which
   Section VALUES he's allowed to assign on an edit form. See
   fn_AssignableSections in 07_v2_row_level_security.sql. ---- */

INSERT INTO dbo.UserScopeSections (UserId, SectionId) VALUES
    ((SELECT UserId FROM dbo.AppUsers WHERE Username = 'bob.singh'),
     (SELECT SectionId FROM dbo.Sections WHERE SectionName = 'Core HR')),
    ((SELECT UserId FROM dbo.AppUsers WHERE Username = 'bob.singh'),
     (SELECT SectionId FROM dbo.Sections WHERE SectionName = 'Core Finance'));
GO

-- Bob already holds employee.edit (granted as employee:write back in v1's
-- seed, renamed in place by 05_v2_schema.sql) - nothing to add here. Kept
-- as a guarded statement rather than deleted outright so this script stays
-- idempotent/self-documenting about the requirement, in case a future
-- role reuses this pattern without already having the permission.
INSERT INTO dbo.RolePermissions (RoleId, PermissionId)
SELECT (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'HR Business Partner'), p.PermissionId
FROM dbo.Permissions p
WHERE p.Code = 'employee.edit'
AND NOT EXISTS (
    SELECT 1 FROM dbo.RolePermissions rp
    WHERE rp.RoleId = (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'HR Business Partner')
      AND rp.PermissionId = p.PermissionId
);
GO

/* ---- Executive (Alice): grant the new v2 permission codes too. The v1 seed's
   CROSS JOIN only covered permissions that existed at that time. ---- */

INSERT INTO dbo.RolePermissions (RoleId, PermissionId)
SELECT (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Executive'), p.PermissionId
FROM dbo.Permissions p
WHERE p.Code IN (
    'employee.add', 'department.view', 'department.add', 'department.edit', 'department.delete',
    'section.view', 'section.add', 'section.edit', 'section.delete'
)
AND NOT EXISTS (
    SELECT 1 FROM dbo.RolePermissions rp
    WHERE rp.RoleId = (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Executive')
      AND rp.PermissionId = p.PermissionId
);
GO

ALTER SECURITY POLICY dbo.EmployeeDataScopePolicy WITH (STATE = ON);
GO
