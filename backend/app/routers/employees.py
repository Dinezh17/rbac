from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.orm import Session

from app.deps import get_scoped_db, require_permission
from app.schemas.auth import CurrentUser
from app.schemas.hrms import EmployeeCreate, EmployeeOut, EmployeeUpdate
from app.scope import get_assignable_department_ids, get_assignable_section_ids

router = APIRouter(prefix="/employees", tags=["employees"])

# Deliberately a 5-way join (Employees x2 via self-join for the manager,
# Departments, Sections, Locations) with NO scope-related WHERE clause
# anywhere in this statement. Whoever is calling only ever sees rows their
# role's data scope allows - enforced by the RLS policy on dbo.Employees,
# applied transparently to both the primary Employees reference and the
# self-joined manager reference. This is the "one line per query, or zero"
# promise from CLAUDE.md: the "one line" here is the get_scoped_db
# dependency, not anything inside the SQL itself.
_EMPLOYEE_SELECT_SQL = """
    SELECT
        e.EmployeeId       AS employee_id,
        e.FullName         AS full_name,
        e.JobTitle         AS job_title,
        e.Email            AS email,
        e.HireDate         AS hire_date,
        e.DepartmentId     AS department_id,
        d.DepartmentName   AS department_name,
        e.SectionId        AS section_id,
        s.SectionName      AS section_name,
        e.LocationId       AS location_id,
        l.LocationName     AS location_name,
        e.ManagerId        AS manager_id,
        m.FullName         AS manager_name,
        e.IsActive         AS is_active
    FROM dbo.Employees e
    JOIN dbo.Departments d ON d.DepartmentId = e.DepartmentId
    JOIN dbo.Locations l ON l.LocationId = e.LocationId
    LEFT JOIN dbo.Sections s ON s.SectionId = e.SectionId
    LEFT JOIN dbo.Employees m ON m.EmployeeId = e.ManagerId
"""

_UPDATABLE_COLUMNS = {
    "full_name": "FullName",
    "job_title": "JobTitle",
    "email": "Email",
    "department_id": "DepartmentId",
    "section_id": "SectionId",
    "manager_id": "ManagerId",
    "is_active": "IsActive",
}


@router.get("", response_model=list[EmployeeOut])
def list_employees(
    _user=Depends(require_permission("employee.view")),
    db: Session = Depends(get_scoped_db),
) -> list[EmployeeOut]:
    rows = db.execute(text(_EMPLOYEE_SELECT_SQL + " WHERE e.IsActive = 1 ORDER BY e.EmployeeId")).mappings().all()
    return [EmployeeOut(**row) for row in rows]


@router.post("", response_model=EmployeeOut, status_code=status.HTTP_201_CREATED)
def create_employee(
    payload: EmployeeCreate,
    user: CurrentUser = Depends(require_permission("employee.add")),
    db: Session = Depends(get_scoped_db),
) -> EmployeeOut:
    assignable_departments = get_assignable_department_ids(db, user.user_id)
    if payload.department_id not in assignable_departments:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Department is outside your assignable scope")
    if payload.section_id is not None:
        assignable_sections = get_assignable_section_ids(db, user.user_id)
        if payload.section_id not in assignable_sections:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Section is outside your assignable scope")

    # No OUTPUT clause: SQL Server refuses OUTPUT INSERTED.col (without an
    # INTO) on a table that has enabled triggers, and Employees has two
    # (db/02_hierarchy_closure.sql, db/08_v2_field_scope_guard.sql).
    # SCOPE_IDENTITY() in a follow-up statement on the same connection
    # isn't subject to that restriction.
    db.execute(
        text(
            """
            INSERT INTO dbo.Employees (FullName, JobTitle, Email, HireDate, DepartmentId, SectionId, LocationId, ManagerId)
            VALUES (:full_name, :job_title, :email, :hire_date, :department_id, :section_id, :location_id, :manager_id)
            """
        ),
        payload.model_dump(),
    )
    new_id = db.execute(text("SELECT CAST(SCOPE_IDENTITY() AS INT)")).scalar_one()
    db.commit()

    row = db.execute(text(_EMPLOYEE_SELECT_SQL + " WHERE e.EmployeeId = :id"), {"id": new_id}).mappings().first()
    return EmployeeOut(**row)


@router.patch("/{employee_id}", response_model=EmployeeOut)
def update_employee(
    employee_id: int,
    payload: EmployeeUpdate,
    user: CurrentUser = Depends(require_permission("employee.edit")),
    db: Session = Depends(get_scoped_db),
) -> EmployeeOut:
    # exclude_unset, not exclude_none: a field the client never included in
    # the payload is left untouched. A field explicitly sent as null (where
    # the schema allows it) IS a real instruction to clear it. This is the
    # crux of the "editor can't see the LOV item the creator picked"
    # problem - the frontend is expected to omit department_id/section_id
    # entirely when it renders that field locked/read-only, rather than
    # resubmitting whatever value it displayed.
    changes = payload.model_dump(exclude_unset=True)
    if not changes:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "No fields provided to update")

    if "department_id" in changes:
        assignable = get_assignable_department_ids(db, user.user_id)
        if changes["department_id"] not in assignable:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Department is outside your assignable scope")
    if "section_id" in changes and changes["section_id"] is not None:
        assignable = get_assignable_section_ids(db, user.user_id)
        if changes["section_id"] not in assignable:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Section is outside your assignable scope")

    set_clause = ", ".join(f"{_UPDATABLE_COLUMNS[field]} = :{field}" for field in changes)
    params = {**changes, "id": employee_id}

    # No OUTPUT clause here either (see create_employee) - Employees has
    # enabled triggers. employee_id is already known (it's the path
    # param), so rowcount is all that's needed to tell "matched and
    # updated" (RLS made the row visible to this UPDATE) from "matched
    # nothing" (outside data scope, or truly doesn't exist).
    #
    # The app-layer checks above are the fast path; dbo.trg_Employees_
    # GuardScopedFieldWrites (db/08_v2_field_scope_guard.sql) independently
    # re-validates department_id/section_id in the database itself, and the
    # RLS BLOCK PREDICATE independently re-validates overall row visibility
    # of the post-update row - three layers, none of which trust the others.
    try:
        result = db.execute(text(f"UPDATE dbo.Employees SET {set_clause} WHERE EmployeeId = :id"), params)
    except DBAPIError as exc:
        db.rollback()
        # Matched on message text, not SQL Server error number: pyodbc's
        # string form of a THROW'n error doesn't reliably surface the
        # numeric code in a fixed position, but the message text is ours
        # (db/08_v2_field_scope_guard.sql) and stable.
        if "outside your assignable scope" in str(exc.orig):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Value is outside your assignable scope") from exc
        raise

    if result.rowcount == 0:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Employee not found or outside your data scope")
    db.commit()

    row = db.execute(text(_EMPLOYEE_SELECT_SQL + " WHERE e.EmployeeId = :id"), {"id": employee_id}).mappings().first()
    return EmployeeOut(**row)


@router.delete("/{employee_id}", status_code=status.HTTP_204_NO_CONTENT)
def deactivate_employee(
    employee_id: int,
    _user=Depends(require_permission("employee.delete")),
    db: Session = Depends(get_scoped_db),
) -> None:
    result = db.execute(
        text("UPDATE dbo.Employees SET IsActive = 0 WHERE EmployeeId = :id AND IsActive = 1"),
        {"id": employee_id},
    )
    if result.rowcount == 0:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Employee not found or outside your data scope")
    db.commit()
