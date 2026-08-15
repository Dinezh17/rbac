from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import bindparam, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.deps import get_scoped_db, require_permission
from app.schemas.auth import CurrentUser
from app.schemas.hrms import AssignableOption, DepartmentCreate, DepartmentOut, DepartmentUpdate
from app.scope import get_assignable_department_ids

router = APIRouter(prefix="/departments", tags=["departments"])

# Departments is master/reference data, not row-level-secured (see the file
# header in db/05_v2_schema.sql for why): department NAMES aren't
# sensitive, so department.view returns the full list unfiltered. What IS
# access-controlled is which of these values a caller may ASSIGN to an
# Employee - that's the separate /departments/assignable endpoint below.
_SELECT_SQL = """
    SELECT d.DepartmentId AS department_id, d.DepartmentName AS department_name,
           d.LocationId AS location_id, l.LocationName AS location_name
    FROM dbo.Departments d
    JOIN dbo.Locations l ON l.LocationId = d.LocationId
"""


@router.get("", response_model=list[DepartmentOut])
def list_departments(
    _user=Depends(require_permission("department.view")),
    db: Session = Depends(get_scoped_db),
) -> list[DepartmentOut]:
    rows = db.execute(text(_SELECT_SQL + " ORDER BY d.DepartmentName")).mappings().all()
    return [DepartmentOut(**row) for row in rows]


@router.get("/assignable", response_model=list[AssignableOption])
def assignable_departments(
    # Gated on employee.edit rather than department.view: this answers
    # "what can I put on an employee record", a distinct permission from
    # "can I administer the department master list". Bob has the former,
    # not the latter.
    user: CurrentUser = Depends(require_permission("employee.edit")),
    db: Session = Depends(get_scoped_db),
) -> list[AssignableOption]:
    ids = get_assignable_department_ids(db, user.user_id)
    if not ids:
        return []
    stmt = text(
        "SELECT DepartmentId AS id, DepartmentName AS name FROM dbo.Departments "
        "WHERE DepartmentId IN :ids ORDER BY DepartmentName"
    ).bindparams(bindparam("ids", expanding=True))
    rows = db.execute(stmt, {"ids": list(ids)}).mappings().all()
    return [AssignableOption(**row) for row in rows]


@router.post("", response_model=DepartmentOut, status_code=status.HTTP_201_CREATED)
def create_department(
    payload: DepartmentCreate,
    _user=Depends(require_permission("department.add")),
    db: Session = Depends(get_scoped_db),
) -> DepartmentOut:
    new_id = db.execute(
        text(
            "INSERT INTO dbo.Departments (DepartmentName, LocationId) OUTPUT INSERTED.DepartmentId "
            "VALUES (:department_name, :location_id)"
        ),
        payload.model_dump(),
    ).scalar_one()
    db.commit()
    row = db.execute(text(_SELECT_SQL + " WHERE d.DepartmentId = :id"), {"id": new_id}).mappings().first()
    return DepartmentOut(**row)


@router.patch("/{department_id}", response_model=DepartmentOut)
def update_department(
    department_id: int,
    payload: DepartmentUpdate,
    _user=Depends(require_permission("department.edit")),
    db: Session = Depends(get_scoped_db),
) -> DepartmentOut:
    changes = payload.model_dump(exclude_unset=True)
    if not changes:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "No fields provided to update")
    column_map = {"department_name": "DepartmentName", "location_id": "LocationId"}
    set_clause = ", ".join(f"{column_map[f]} = :{f}" for f in changes)
    updated_id = db.execute(
        text(f"UPDATE dbo.Departments SET {set_clause} OUTPUT INSERTED.DepartmentId WHERE DepartmentId = :id"),
        {**changes, "id": department_id},
    ).scalar_one_or_none()
    if updated_id is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Department not found")
    db.commit()
    row = db.execute(text(_SELECT_SQL + " WHERE d.DepartmentId = :id"), {"id": updated_id}).mappings().first()
    return DepartmentOut(**row)


@router.delete("/{department_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_department(
    department_id: int,
    _user=Depends(require_permission("department.delete")),
    db: Session = Depends(get_scoped_db),
) -> None:
    try:
        deleted = db.execute(
            text("DELETE FROM dbo.Departments OUTPUT DELETED.DepartmentId WHERE DepartmentId = :id"),
            {"id": department_id},
        ).scalar_one_or_none()
        if deleted is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Department not found")
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "Cannot delete: employees or sections still reference this department",
        ) from exc
