/* ============================================================================
   01_schema.sql
   Core HRMS domain tables + RBAC / data-scope tables.

   This stands in for the "200,000+ LOC, already in production" schema
   described in CLAUDE.md. The domain tables (Locations, Departments,
   Employees, Payroll, LeaveRequests) represent the kind of pre-existing,
   heavily-joined tables you cannot rewrite. The RBAC_* / Scope_* tables are
   the ADDITIVE layer: nothing here modifies an existing table's columns or
   existing queries.
   ============================================================================ */

IF DB_ID(N'hrms') IS NULL
BEGIN
    CREATE DATABASE hrms;
END
GO

USE hrms;
GO

-- Required for the persisted computed column on dbo.Payroll below.
SET QUOTED_IDENTIFIER ON;
GO

/* ----------------------------------------------------------------------
   Domain tables (stand-in for the pre-existing production schema)
   ---------------------------------------------------------------------- */

CREATE TABLE dbo.Locations (
    LocationId      INT IDENTITY(1,1) PRIMARY KEY,
    LocationName    NVARCHAR(100)   NOT NULL,
    Country         NVARCHAR(100)   NOT NULL
);
GO

CREATE TABLE dbo.Departments (
    DepartmentId    INT IDENTITY(1,1) PRIMARY KEY,
    DepartmentName  NVARCHAR(100)   NOT NULL,
    LocationId      INT             NOT NULL REFERENCES dbo.Locations(LocationId)
);
GO

CREATE TABLE dbo.Employees (
    EmployeeId      INT IDENTITY(1,1) PRIMARY KEY,
    FullName        NVARCHAR(200)   NOT NULL,
    JobTitle        NVARCHAR(150)   NOT NULL,
    DepartmentId    INT             NOT NULL REFERENCES dbo.Departments(DepartmentId),
    LocationId      INT             NOT NULL REFERENCES dbo.Locations(LocationId),
    ManagerId       INT             NULL REFERENCES dbo.Employees(EmployeeId),
    HireDate        DATE            NOT NULL,
    Email           NVARCHAR(200)   NOT NULL UNIQUE,
    IsActive        BIT             NOT NULL DEFAULT 1
);
GO

CREATE INDEX IX_Employees_ManagerId ON dbo.Employees(ManagerId);
CREATE INDEX IX_Employees_DepartmentId ON dbo.Employees(DepartmentId);
GO

CREATE TABLE dbo.Payroll (
    PayrollId       INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeId      INT             NOT NULL REFERENCES dbo.Employees(EmployeeId),
    PayPeriod       CHAR(7)         NOT NULL,      -- 'YYYY-MM'
    BaseSalary      DECIMAL(12,2)   NOT NULL,
    Bonus           DECIMAL(12,2)   NOT NULL DEFAULT 0,
    Deductions      DECIMAL(12,2)   NOT NULL DEFAULT 0,
    NetPay          AS (BaseSalary + Bonus - Deductions) PERSISTED
);
GO

CREATE INDEX IX_Payroll_EmployeeId ON dbo.Payroll(EmployeeId);
GO

CREATE TABLE dbo.LeaveRequests (
    LeaveRequestId  INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeId      INT             NOT NULL REFERENCES dbo.Employees(EmployeeId),
    StartDate       DATE            NOT NULL,
    EndDate         DATE            NOT NULL,
    LeaveType       NVARCHAR(50)    NOT NULL,
    Status          NVARCHAR(20)    NOT NULL DEFAULT 'PENDING',
    RequestedAt     DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE INDEX IX_LeaveRequests_EmployeeId ON dbo.LeaveRequests(EmployeeId);
GO

/* ----------------------------------------------------------------------
   RBAC + Data-Scope tables (the additive layer)
   ---------------------------------------------------------------------- */

-- Action-level permissions, e.g. 'employee:read', 'payroll:approve'
CREATE TABLE dbo.Permissions (
    PermissionId    INT IDENTITY(1,1) PRIMARY KEY,
    Code            VARCHAR(80)     NOT NULL UNIQUE,
    Description     NVARCHAR(300)   NOT NULL
);
GO

-- Roles carry both a name AND a data-scope type. Scope type governs which
-- ROWS a member of the role can see; permissions govern which ACTIONS.
CREATE TABLE dbo.Roles (
    RoleId          INT IDENTITY(1,1) PRIMARY KEY,
    RoleName        VARCHAR(80)     NOT NULL UNIQUE,
    ScopeType       VARCHAR(20)     NOT NULL
        CHECK (ScopeType IN ('ALL', 'DEPARTMENT', 'TEAM', 'OWN')),
    Description     NVARCHAR(300)   NOT NULL
);
GO

CREATE TABLE dbo.RolePermissions (
    RoleId          INT NOT NULL REFERENCES dbo.Roles(RoleId),
    PermissionId    INT NOT NULL REFERENCES dbo.Permissions(PermissionId),
    PRIMARY KEY (RoleId, PermissionId)
);
GO

-- Application login identities. Distinct from Employees (an admin/system
-- account may have no EmployeeId), but usually 1:1 with an employee.
CREATE TABLE dbo.AppUsers (
    UserId          INT IDENTITY(1,1) PRIMARY KEY,
    Username        VARCHAR(100)    NOT NULL UNIQUE,
    PasswordHash    VARCHAR(200)    NOT NULL,
    EmployeeId      INT             NULL REFERENCES dbo.Employees(EmployeeId),
    IsActive        BIT             NOT NULL DEFAULT 1
);
GO

CREATE TABLE dbo.UserRoles (
    UserId          INT NOT NULL REFERENCES dbo.AppUsers(UserId),
    RoleId          INT NOT NULL REFERENCES dbo.Roles(RoleId),
    PRIMARY KEY (UserId, RoleId)
);
GO

-- For DEPARTMENT-scoped roles: which department(s) a given user covers.
-- (An HR Business Partner might cover 2-3 departments, not just 1.)
CREATE TABLE dbo.UserScopeDepartments (
    UserId          INT NOT NULL REFERENCES dbo.AppUsers(UserId),
    DepartmentId    INT NOT NULL REFERENCES dbo.Departments(DepartmentId),
    PRIMARY KEY (UserId, DepartmentId)
);
GO

-- Materialized "who manages whom, transitively" closure table, used by
-- TEAM-scoped roles (a manager sees their entire reporting subtree, not
-- just direct reports). Maintained by trigger in 03_hierarchy_closure.sql.
-- Includes self-rows (Depth = 0) to simplify predicate logic.
CREATE TABLE dbo.EmployeeHierarchyClosure (
    ManagerEmployeeId      INT NOT NULL REFERENCES dbo.Employees(EmployeeId),
    SubordinateEmployeeId  INT NOT NULL REFERENCES dbo.Employees(EmployeeId),
    Depth                  INT NOT NULL,
    PRIMARY KEY (ManagerEmployeeId, SubordinateEmployeeId)
);
GO

CREATE INDEX IX_Closure_Subordinate ON dbo.EmployeeHierarchyClosure(SubordinateEmployeeId);
GO
