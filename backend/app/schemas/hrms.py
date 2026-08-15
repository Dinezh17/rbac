from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel


class EmployeeOut(BaseModel):
    employee_id: int
    full_name: str
    job_title: str
    email: str
    hire_date: date
    department_name: str
    location_name: str
    manager_name: str | None


class PayrollOut(BaseModel):
    payroll_id: int
    employee_id: int
    employee_name: str
    department_name: str
    pay_period: str
    base_salary: Decimal
    bonus: Decimal
    deductions: Decimal
    net_pay: Decimal


class LeaveRequestOut(BaseModel):
    leave_request_id: int
    employee_id: int
    employee_name: str
    start_date: date
    end_date: date
    leave_type: str
    status: str
    requested_at: datetime


class LeaveRequestCreate(BaseModel):
    start_date: date
    end_date: date
    leave_type: str
