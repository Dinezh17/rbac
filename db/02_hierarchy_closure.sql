/* ============================================================================
   02_hierarchy_closure.sql
   Maintains dbo.EmployeeHierarchyClosure, the materialized "manager -> all
   transitive reports" table used by TEAM-scoped roles.

   Design choice: full rebuild on every Employees change, driven by a
   recursive CTE, wrapped in a stored procedure and fired from a trigger.

   Why a materialized closure table instead of evaluating the recursive CTE
   live inside the RLS predicate function?
     - A security predicate function runs (conceptually) per row touched by
       any query against a protected table. A recursive CTE evaluated
       there would multiply the cost of every employee/payroll/leave query
       by the depth of the org chart.
     - A closure table turns "is EmployeeId X in Manager Y's reporting
       tree" into a single indexed point lookup (see IX_Closure_Subordinate).
     - Org-chart changes (hires, transfers, re-orgs) are low frequency
       compared to read traffic on employee/payroll data, so paying the
       rebuild cost on write is the right trade for an HRMS.

   Scale note: a full rebuild is O(N) and is fine into the tens of
   thousands of employees (this pattern is proven at that scale in
   production HR systems). Past that, switch this procedure to an
   incremental update (only recompute the affected employee's old and new
   ancestor chains) or move to SQL Server's native HIERARCHYID type. The
   trigger/predicate contract does not change either way.
   ============================================================================ */

USE hrms;
GO

CREATE OR ALTER PROCEDURE dbo.sp_RebuildEmployeeHierarchyClosure
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE dbo.EmployeeHierarchyClosure;

    ;WITH Chain AS (
        -- Anchor: every employee manages themself at depth 0
        SELECT
            EmployeeId AS ManagerEmployeeId,
            EmployeeId AS SubordinateEmployeeId,
            0 AS Depth
        FROM dbo.Employees

        UNION ALL

        -- Recursive step: walk up from each employee to their manager
        SELECT
            e.ManagerId AS ManagerEmployeeId,
            c.SubordinateEmployeeId,
            c.Depth + 1
        FROM Chain c
        JOIN dbo.Employees e ON e.EmployeeId = c.ManagerEmployeeId
        WHERE e.ManagerId IS NOT NULL
    )
    INSERT INTO dbo.EmployeeHierarchyClosure (ManagerEmployeeId, SubordinateEmployeeId, Depth)
    SELECT ManagerEmployeeId, SubordinateEmployeeId, MIN(Depth)
    FROM Chain
    GROUP BY ManagerEmployeeId, SubordinateEmployeeId
    OPTION (MAXRECURSION 100);
END
GO

CREATE OR ALTER TRIGGER dbo.trg_Employees_RebuildClosure
ON dbo.Employees
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    -- Only rebuild when hierarchy-relevant columns actually changed, or on
    -- insert/delete. Avoids unnecessary rebuilds on e.g. a JobTitle edit.
    IF EXISTS (SELECT 1 FROM inserted) OR EXISTS (SELECT 1 FROM deleted)
    BEGIN
        IF UPDATE(ManagerId) OR NOT EXISTS (SELECT 1 FROM deleted) OR NOT EXISTS (SELECT 1 FROM inserted)
        BEGIN
            EXEC dbo.sp_RebuildEmployeeHierarchyClosure;
        END
    END
END
GO
