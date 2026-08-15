/* ============================================================================
   03_seed_data.sql
   Demo data for Lakshmi Corp: locations, departments, an employee org chart,
   payroll/leave records, RBAC roles+permissions, and one demo AppUser per
   data-scope type so the four enforcement paths can each be exercised.

   IMPORTANT: this script must run BEFORE 04_row_level_security.sql. Once the
   security policy is ON, the BLOCK PREDICATE on Employees/Payroll/
   LeaveRequests rejects any INSERT made without a matching, active
   session_context('app_user_id') - which plain sqlcmd/seed sessions won't
   have. Loading data first, then turning on enforcement, mirrors how you'd
   roll this out against an existing production table too.

   All four demo users share the password: Passw0rd!
   ============================================================================ */

USE hrms;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ---- Locations & Departments ------------------------------------------ */

INSERT INTO dbo.Locations (LocationName, Country) VALUES
    (N'Bengaluru', N'India'),
    (N'Mumbai', N'India');
GO

INSERT INTO dbo.Departments (DepartmentName, LocationId) VALUES
    (N'Executive',   (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Bengaluru')),
    (N'Engineering', (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Bengaluru')),
    (N'HR',          (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Mumbai')),
    (N'Finance',     (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Mumbai')),
    (N'Sales',       (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Mumbai'));
GO

/* ---- Employees (inserted top-down so ManagerId can be looked up by email) */

INSERT INTO dbo.Employees (FullName, JobTitle, DepartmentId, LocationId, ManagerId, HireDate, Email) VALUES
(N'Alice Chen', N'Chief Executive Officer',
    (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Executive'),
    (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Bengaluru'),
    NULL, '2015-01-12', N'alice.chen@lakshmicorp.co.in');

INSERT INTO dbo.Employees (FullName, JobTitle, DepartmentId, LocationId, ManagerId, HireDate, Email) VALUES
(N'Frank Nolan', N'VP Engineering',
    (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Engineering'),
    (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Bengaluru'),
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'alice.chen@lakshmicorp.co.in'),
    '2016-03-01', N'frank.nolan@lakshmicorp.co.in');

INSERT INTO dbo.Employees (FullName, JobTitle, DepartmentId, LocationId, ManagerId, HireDate, Email) VALUES
(N'Bob Singh', N'HR Director',
    (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'HR'),
    (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Mumbai'),
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'alice.chen@lakshmicorp.co.in'),
    '2016-06-15', N'bob.singh@lakshmicorp.co.in');

INSERT INTO dbo.Employees (FullName, JobTitle, DepartmentId, LocationId, ManagerId, HireDate, Email) VALUES
(N'Rahul Verma', N'Finance Manager',
    (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Finance'),
    (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Mumbai'),
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'alice.chen@lakshmicorp.co.in'),
    '2017-02-20', N'rahul.verma@lakshmicorp.co.in');

INSERT INTO dbo.Employees (FullName, JobTitle, DepartmentId, LocationId, ManagerId, HireDate, Email) VALUES
(N'Tom Fischer', N'Sales Manager',
    (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Sales'),
    (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Mumbai'),
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'alice.chen@lakshmicorp.co.in'),
    '2017-05-10', N'tom.fischer@lakshmicorp.co.in');

INSERT INTO dbo.Employees (FullName, JobTitle, DepartmentId, LocationId, ManagerId, HireDate, Email) VALUES
(N'Carol Mehta', N'Engineering Manager',
    (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Engineering'),
    (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Bengaluru'),
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'frank.nolan@lakshmicorp.co.in'),
    '2018-01-08', N'carol.mehta@lakshmicorp.co.in');

INSERT INTO dbo.Employees (FullName, JobTitle, DepartmentId, LocationId, ManagerId, HireDate, Email) VALUES
(N'David Kim', N'Software Engineer',
    (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Engineering'),
    (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Bengaluru'),
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'carol.mehta@lakshmicorp.co.in'),
    '2019-07-22', N'david.kim@lakshmicorp.co.in');

INSERT INTO dbo.Employees (FullName, JobTitle, DepartmentId, LocationId, ManagerId, HireDate, Email) VALUES
(N'Grace Lee', N'Software Engineer',
    (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Engineering'),
    (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Bengaluru'),
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'carol.mehta@lakshmicorp.co.in'),
    '2020-02-17', N'grace.lee@lakshmicorp.co.in');

INSERT INTO dbo.Employees (FullName, JobTitle, DepartmentId, LocationId, ManagerId, HireDate, Email) VALUES
(N'Priya Nair', N'HR Business Partner',
    (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'HR'),
    (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Mumbai'),
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'bob.singh@lakshmicorp.co.in'),
    '2019-09-01', N'priya.nair@lakshmicorp.co.in');

INSERT INTO dbo.Employees (FullName, JobTitle, DepartmentId, LocationId, ManagerId, HireDate, Email) VALUES
(N'Sara Iyer', N'Financial Analyst',
    (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Finance'),
    (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Mumbai'),
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'rahul.verma@lakshmicorp.co.in'),
    '2021-04-05', N'sara.iyer@lakshmicorp.co.in');

INSERT INTO dbo.Employees (FullName, JobTitle, DepartmentId, LocationId, ManagerId, HireDate, Email) VALUES
(N'Uma Pillai', N'Account Executive',
    (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = N'Sales'),
    (SELECT LocationId FROM dbo.Locations WHERE LocationName = N'Mumbai'),
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'tom.fischer@lakshmicorp.co.in'),
    '2021-11-19', N'uma.pillai@lakshmicorp.co.in');
GO

-- Trigger fires per statement above and keeps the closure table in sync;
-- one explicit call here guarantees it's fresh before we move on.
EXEC dbo.sp_RebuildEmployeeHierarchyClosure;
GO

/* ---- Payroll (current pay period) -------------------------------------- */

INSERT INTO dbo.Payroll (EmployeeId, PayPeriod, BaseSalary, Bonus, Deductions)
SELECT EmployeeId, '2026-07',
    CASE JobTitle
        WHEN N'Chief Executive Officer' THEN 4500000
        WHEN N'VP Engineering'          THEN 3200000
        WHEN N'HR Director'             THEN 2400000
        WHEN N'Finance Manager'         THEN 2200000
        WHEN N'Sales Manager'           THEN 2100000
        WHEN N'Engineering Manager'     THEN 1900000
        WHEN N'HR Business Partner'     THEN 1200000
        WHEN N'Financial Analyst'       THEN 1000000
        WHEN N'Account Executive'       THEN 950000
        ELSE 1100000
    END / 12.0,
    25000, 4500
FROM dbo.Employees;
GO

/* ---- Leave requests ------------------------------------------------------ */

INSERT INTO dbo.LeaveRequests (EmployeeId, StartDate, EndDate, LeaveType, Status)
SELECT EmployeeId, '2026-08-20', '2026-08-22', N'ANNUAL', N'PENDING'
FROM dbo.Employees WHERE Email IN (N'david.kim@lakshmicorp.co.in', N'grace.lee@lakshmicorp.co.in');

INSERT INTO dbo.LeaveRequests (EmployeeId, StartDate, EndDate, LeaveType, Status)
SELECT EmployeeId, '2026-08-10', '2026-08-11', N'SICK', N'APPROVED'
FROM dbo.Employees WHERE Email = N'sara.iyer@lakshmicorp.co.in';
GO

/* ---- RBAC: Permissions -------------------------------------------------- */

INSERT INTO dbo.Permissions (Code, Description) VALUES
    ('employee:read',    'View employee profiles'),
    ('employee:write',   'Create/edit employee profiles'),
    ('employee:delete',  'Deactivate employee profiles'),
    ('payroll:read',     'View payroll records'),
    ('payroll:write',    'Create/edit payroll records'),
    ('payroll:approve',  'Approve payroll runs'),
    ('leave:read',       'View leave requests'),
    ('leave:write',      'Submit leave requests'),
    ('leave:approve',    'Approve/reject leave requests');
GO

/* ---- RBAC: Roles (RoleName, ScopeType) ----------------------------------
   ScopeType is the DATA-SCOPE dimension (enforced by SQL Server RLS).
   Permissions below are the ACTION dimension (enforced by FastAPI). ------ */

INSERT INTO dbo.Roles (RoleName, ScopeType, Description) VALUES
    ('Executive',            'ALL',        'Org-wide visibility, e.g. CEO/CHRO'),
    ('HR Business Partner',  'DEPARTMENT', 'Visibility into assigned department(s)'),
    ('Engineering Manager',  'TEAM',       'Visibility into own reporting subtree'),
    ('Employee',             'OWN',        'Self-service access only');
GO

INSERT INTO dbo.RolePermissions (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM dbo.Roles r CROSS JOIN dbo.Permissions p
WHERE r.RoleName = 'Executive';

INSERT INTO dbo.RolePermissions (RoleId, PermissionId)
SELECT (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'HR Business Partner'), PermissionId
FROM dbo.Permissions WHERE Code IN ('employee:read', 'employee:write', 'payroll:read', 'leave:read', 'leave:approve');

INSERT INTO dbo.RolePermissions (RoleId, PermissionId)
SELECT (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Engineering Manager'), PermissionId
FROM dbo.Permissions WHERE Code IN ('employee:read', 'leave:read', 'leave:approve');

INSERT INTO dbo.RolePermissions (RoleId, PermissionId)
SELECT (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Employee'), PermissionId
FROM dbo.Permissions WHERE Code IN ('employee:read', 'payroll:read', 'leave:read', 'leave:write');
GO

/* ---- Demo application users (password for all: Passw0rd!) -------------- */

INSERT INTO dbo.AppUsers (Username, PasswordHash, EmployeeId) VALUES
('alice.chen', '$2b$12$8wxk7rwkPP36vGKBKrz/vuyIFvnwkwHsVl6lQWzlClnU4I4hk2x4O',
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'alice.chen@lakshmicorp.co.in')),
('bob.singh', '$2b$12$8wxk7rwkPP36vGKBKrz/vuyIFvnwkwHsVl6lQWzlClnU4I4hk2x4O',
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'bob.singh@lakshmicorp.co.in')),
('carol.mehta', '$2b$12$8wxk7rwkPP36vGKBKrz/vuyIFvnwkwHsVl6lQWzlClnU4I4hk2x4O',
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'carol.mehta@lakshmicorp.co.in')),
('david.kim', '$2b$12$8wxk7rwkPP36vGKBKrz/vuyIFvnwkwHsVl6lQWzlClnU4I4hk2x4O',
    (SELECT EmployeeId FROM dbo.Employees WHERE Email = N'david.kim@lakshmicorp.co.in'));
GO

INSERT INTO dbo.UserRoles (UserId, RoleId) VALUES
    ((SELECT UserId FROM dbo.AppUsers WHERE Username = 'alice.chen'),
     (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Executive')),
    ((SELECT UserId FROM dbo.AppUsers WHERE Username = 'bob.singh'),
     (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'HR Business Partner')),
    ((SELECT UserId FROM dbo.AppUsers WHERE Username = 'carol.mehta'),
     (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Engineering Manager')),
    ((SELECT UserId FROM dbo.AppUsers WHERE Username = 'david.kim'),
     (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Employee'));
GO

-- Bob (HR Business Partner) covers both HR and Finance departments.
INSERT INTO dbo.UserScopeDepartments (UserId, DepartmentId) VALUES
    ((SELECT UserId FROM dbo.AppUsers WHERE Username = 'bob.singh'),
     (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = 'HR')),
    ((SELECT UserId FROM dbo.AppUsers WHERE Username = 'bob.singh'),
     (SELECT DepartmentId FROM dbo.Departments WHERE DepartmentName = 'Finance'));
GO
