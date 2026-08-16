"""
Assignable-scope resolution: "which Department/Section VALUES is this user
allowed to write into a scoped foreign key column" - a different question
from row visibility (answered by RLS), used to build safe edit-form LOVs
and to server-side-validate a submitted change.

Both helpers here call the SQL functions in
db/07_v2_row_level_security.sql, which must be invoked with the SAME
app_user_id the caller's DB session was opened under (see get_scoped_db in
deps.py) - the functions internally read dbo.Employees, which is itself
RLS-protected, so they only resolve correctly for "what's assignable to
whoever session_context is currently set to". Never call these for a user
other than the request's own current_user.
"""

from sqlalchemy import text
from sqlalchemy.orm import Session


def get_assignable_department_ids(db: Session, app_user_id: int) -> set[int]:
    rows = db.execute(
        text("SELECT DepartmentId FROM dbo.fn_AssignableDepartments(:uid)"), {"uid": app_user_id}
    ).scalars().all()
    return set(rows)


def get_assignable_section_ids(db: Session, app_user_id: int) -> set[int]:
    rows = db.execute(
        text("SELECT SectionId FROM dbo.fn_AssignableSections(:uid)"), {"uid": app_user_id}
    ).scalars().all()
    return set(rows)
