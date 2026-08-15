from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.deps import get_scoped_db, require_permission
from app.schemas.hrms import PayrollOut

router = APIRouter(prefix="/payroll", tags=["payroll"])

# Same story as employees.py: a 3-table join against a completely different
# protected table (Payroll instead of Employees), again with zero scope
# logic in the SQL. The same RLS policy (bound to Payroll.EmployeeId in
# db/04_row_level_security.sql) does the filtering.
_PAYROLL_LIST_SQL = """
    SELECT
        p.PayrollId       AS payroll_id,
        p.EmployeeId       AS employee_id,
        e.FullName         AS employee_name,
        d.DepartmentName   AS department_name,
        p.PayPeriod        AS pay_period,
        p.BaseSalary       AS base_salary,
        p.Bonus            AS bonus,
        p.Deductions       AS deductions,
        p.NetPay           AS net_pay
    FROM dbo.Payroll p
    JOIN dbo.Employees e ON e.EmployeeId = p.EmployeeId
    JOIN dbo.Departments d ON d.DepartmentId = e.DepartmentId
    ORDER BY p.PayPeriod DESC, e.EmployeeId
"""


@router.get("", response_model=list[PayrollOut])
def list_payroll(
    _user=Depends(require_permission("payroll:read")),
    db: Session = Depends(get_scoped_db),
) -> list[PayrollOut]:
    rows = db.execute(text(_PAYROLL_LIST_SQL)).mappings().all()
    return [PayrollOut(**row) for row in rows]
