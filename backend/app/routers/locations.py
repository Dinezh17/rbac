from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.deps import get_scoped_db, require_permission
from app.schemas.hrms import LocationOut

router = APIRouter(prefix="/locations", tags=["locations"])


@router.get("", response_model=list[LocationOut])
def list_locations(
    _user=Depends(require_permission("department.view")),
    db: Session = Depends(get_scoped_db),
) -> list[LocationOut]:
    rows = db.execute(
        text("SELECT LocationId AS location_id, LocationName AS location_name FROM dbo.Locations ORDER BY LocationName")
    ).mappings().all()
    return [LocationOut(**row) for row in rows]
