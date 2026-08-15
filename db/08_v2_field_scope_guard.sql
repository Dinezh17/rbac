/* ============================================================================
   08_v2_field_scope_guard.sql
   Closes a real gap left by RLS alone: fn_DataScopePredicate's BLOCK
   PREDICATE protects ROW visibility (can this session touch an employee
   whose department/section makes them visible at all), but Bob's
   Department scope (HR+Finance) already makes every HR/Finance employee's
   row pass that check regardless of what SectionId gets written - RLS has
   no concept of "this specific column value must also be one of my
   assignable Sections". That narrower rule needs its own enforcement.

   This trigger is the DB-level backstop for exactly that rule, mirroring
   the same "don't rely on the application to remember" philosophy as the
   RLS policy itself, applied to a case RLS's row-level granularity can't
   reach on its own.

   Deliberately does NOT fire when SESSION_CONTEXT('app_user_id') is unset
   - that's true for migrations, seed scripts, and any offline/admin data
   load, which are governed by the security policy's BLOCK PREDICATE
   (fail-closed there) rather than by this narrower rule. This trigger only
   adds a restriction on top of an already-identified interactive session;
   it is not the mechanism that decides whether a write is allowed at all.

   Only validates DepartmentId/SectionId when they actually change (or on a
   brand-new row) - editing an unrelated field like JobTitle must not
   re-validate an unchanged value against a narrower assignable-set rule
   than the one that made the row visible in the first place.
   ============================================================================ */

USE hrms;
GO

CREATE OR ALTER TRIGGER dbo.trg_Employees_GuardScopedFieldWrites
ON dbo.Employees
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @uid INT = TRY_CAST(SESSION_CONTEXT(N'app_user_id') AS INT);
    IF @uid IS NULL RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        LEFT JOIN deleted d ON d.EmployeeId = i.EmployeeId
        WHERE (d.EmployeeId IS NULL OR i.DepartmentId <> d.DepartmentId)
          AND NOT EXISTS (
                SELECT 1 FROM dbo.fn_AssignableDepartments(@uid) ad
                WHERE ad.DepartmentId = i.DepartmentId
          )
    )
    BEGIN
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW 51000, 'DepartmentId is outside your assignable scope.', 1;
    END

    IF EXISTS (
        SELECT 1
        FROM inserted i
        LEFT JOIN deleted d ON d.EmployeeId = i.EmployeeId
        WHERE i.SectionId IS NOT NULL
          AND (d.EmployeeId IS NULL OR d.SectionId IS NULL OR i.SectionId <> d.SectionId)
          AND NOT EXISTS (
                SELECT 1 FROM dbo.fn_AssignableSections(@uid) asec
                WHERE asec.SectionId = i.SectionId
          )
    )
    BEGIN
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW 51001, 'SectionId is outside your assignable scope.', 1;
    END
END
GO
