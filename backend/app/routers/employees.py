from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.deps import get_scoped_db, require_permission
from app.schemas.hrms import EmployeeOut

router = APIRouter(prefix="/employees", tags=["employees"])

# Deliberately a 4-way join (Employees x2 via self-join for the manager,
# Departments, Locations) with NO scope-related WHERE clause anywhere in
# this statement. Whoever is calling only ever sees rows their role's data
# scope allows - enforced by the RLS policy on dbo.Employees, applied
# transparently to both the primary Employees reference and the self-joined
# manager reference. This is the "one line per query, or zero" promise from
# CLAUDE.md: the "one line" here is the get_scoped_db dependency, not
# anything inside the SQL itself.
_EMPLOYEE_LIST_SQL = """
    SELECT
        e.EmployeeId       AS employee_id,
        e.FullName         AS full_name,
        e.JobTitle         AS job_title,
        e.Email            AS email,
        e.HireDate         AS hire_date,
        d.DepartmentName   AS department_name,
        l.LocationName     AS location_name,
        m.FullName         AS manager_name
    FROM dbo.Employees e
    JOIN dbo.Departments d ON d.DepartmentId = e.DepartmentId
    JOIN dbo.Locations l ON l.LocationId = e.LocationId
    LEFT JOIN dbo.Employees m ON m.EmployeeId = e.ManagerId
    WHERE e.IsActive = 1
    ORDER BY e.EmployeeId
"""


@router.get("", response_model=list[EmployeeOut])
def list_employees(
    _user=Depends(require_permission("employee:read")),
    db: Session = Depends(get_scoped_db),
) -> list[EmployeeOut]:
    rows = db.execute(text(_EMPLOYEE_LIST_SQL)).mappings().all()
    return [EmployeeOut(**row) for row in rows]
