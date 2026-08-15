from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import bindparam, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.deps import get_scoped_db, require_permission
from app.schemas.auth import CurrentUser
from app.schemas.hrms import AssignableOption, SectionCreate, SectionOut, SectionUpdate
from app.scope import get_assignable_section_ids

router = APIRouter(prefix="/sections", tags=["sections"])

_SELECT_SQL = """
    SELECT s.SectionId AS section_id, s.SectionName AS section_name,
           s.DepartmentId AS department_id, d.DepartmentName AS department_name
    FROM dbo.Sections s
    JOIN dbo.Departments d ON d.DepartmentId = s.DepartmentId
"""


@router.get("", response_model=list[SectionOut])
def list_sections(
    _user=Depends(require_permission("section.view")),
    db: Session = Depends(get_scoped_db),
) -> list[SectionOut]:
    rows = db.execute(text(_SELECT_SQL + " ORDER BY d.DepartmentName, s.SectionName")).mappings().all()
    return [SectionOut(**row) for row in rows]


@router.get("/assignable", response_model=list[AssignableOption])
def assignable_sections(
    user: CurrentUser = Depends(require_permission("employee.edit")),
    db: Session = Depends(get_scoped_db),
) -> list[AssignableOption]:
    ids = get_assignable_section_ids(db, user.user_id)
    if not ids:
        return []
    stmt = text(
        "SELECT SectionId AS id, SectionName AS name FROM dbo.Sections WHERE SectionId IN :ids ORDER BY SectionName"
    ).bindparams(bindparam("ids", expanding=True))
    rows = db.execute(stmt, {"ids": list(ids)}).mappings().all()
    return [AssignableOption(**row) for row in rows]


@router.post("", response_model=SectionOut, status_code=status.HTTP_201_CREATED)
def create_section(
    payload: SectionCreate,
    _user=Depends(require_permission("section.add")),
    db: Session = Depends(get_scoped_db),
) -> SectionOut:
    new_id = db.execute(
        text(
            "INSERT INTO dbo.Sections (SectionName, DepartmentId) OUTPUT INSERTED.SectionId "
            "VALUES (:section_name, :department_id)"
        ),
        payload.model_dump(),
    ).scalar_one()
    db.commit()
    row = db.execute(text(_SELECT_SQL + " WHERE s.SectionId = :id"), {"id": new_id}).mappings().first()
    return SectionOut(**row)


@router.patch("/{section_id}", response_model=SectionOut)
def update_section(
    section_id: int,
    payload: SectionUpdate,
    _user=Depends(require_permission("section.edit")),
    db: Session = Depends(get_scoped_db),
) -> SectionOut:
    changes = payload.model_dump(exclude_unset=True)
    if not changes:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "No fields provided to update")
    column_map = {"section_name": "SectionName", "department_id": "DepartmentId"}
    set_clause = ", ".join(f"{column_map[f]} = :{f}" for f in changes)
    updated_id = db.execute(
        text(f"UPDATE dbo.Sections SET {set_clause} OUTPUT INSERTED.SectionId WHERE SectionId = :id"),
        {**changes, "id": section_id},
    ).scalar_one_or_none()
    if updated_id is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Section not found")
    db.commit()
    row = db.execute(text(_SELECT_SQL + " WHERE s.SectionId = :id"), {"id": updated_id}).mappings().first()
    return SectionOut(**row)


@router.delete("/{section_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_section(
    section_id: int,
    _user=Depends(require_permission("section.delete")),
    db: Session = Depends(get_scoped_db),
) -> None:
    try:
        deleted = db.execute(
            text("DELETE FROM dbo.Sections OUTPUT DELETED.SectionId WHERE SectionId = :id"),
            {"id": section_id},
        ).scalar_one_or_none()
        if deleted is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Section not found")
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT, "Cannot delete: employees still reference this section"
        ) from exc
