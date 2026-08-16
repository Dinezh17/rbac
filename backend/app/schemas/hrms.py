from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel


class EmployeeOut(BaseModel):
    employee_id: int
    full_name: str
    job_title: str
    email: str
    hire_date: date
    department_id: int
    department_name: str
    section_id: int | None
    section_name: str | None
    location_id: int
    location_name: str
    manager_id: int | None
    manager_name: str | None
    is_active: bool


class EmployeeCreate(BaseModel):
    full_name: str
    job_title: str
    email: str
    hire_date: date
    department_id: int
    location_id: int
    section_id: int | None = None
    manager_id: int | None = None


class EmployeeUpdate(BaseModel):
    """All fields optional - only what the client actually sends is
    written. See routers/employees.py::update_employee for why this
    matters: a field the caller's scope doesn't let them see a value for
    must never be silently overwritten just because it was left out of
    the payload."""

    full_name: str | None = None
    job_title: str | None = None
    email: str | None = None
    department_id: int | None = None
    section_id: int | None = None
    manager_id: int | None = None
    is_active: bool | None = None


class DepartmentOut(BaseModel):
    department_id: int
    department_name: str
    location_id: int
    location_name: str


class DepartmentCreate(BaseModel):
    department_name: str
    location_id: int


class DepartmentUpdate(BaseModel):
    department_name: str | None = None
    location_id: int | None = None


class SectionOut(BaseModel):
    section_id: int
    section_name: str
    department_id: int
    department_name: str


class SectionCreate(BaseModel):
    section_name: str
    department_id: int


class SectionUpdate(BaseModel):
    section_name: str | None = None
    department_id: int | None = None


class AssignableOption(BaseModel):
    id: int
    name: str


class LocationOut(BaseModel):
    location_id: int
    location_name: str


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
