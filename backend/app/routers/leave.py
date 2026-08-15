from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.deps import get_scoped_db, require_permission
from app.schemas.auth import CurrentUser
from app.schemas.hrms import LeaveRequestCreate, LeaveRequestOut

router = APIRouter(prefix="/leave", tags=["leave"])

_LEAVE_SELECT_SQL = """
    SELECT
        lr.LeaveRequestId AS leave_request_id,
        lr.EmployeeId      AS employee_id,
        e.FullName          AS employee_name,
        lr.StartDate       AS start_date,
        lr.EndDate         AS end_date,
        lr.LeaveType       AS leave_type,
        lr.Status          AS status,
        lr.RequestedAt     AS requested_at
    FROM dbo.LeaveRequests lr
    JOIN dbo.Employees e ON e.EmployeeId = lr.EmployeeId
"""


@router.get("", response_model=list[LeaveRequestOut])
def list_leave_requests(
    _user=Depends(require_permission("leave.view")),
    db: Session = Depends(get_scoped_db),
) -> list[LeaveRequestOut]:
    rows = db.execute(text(_LEAVE_SELECT_SQL + " ORDER BY lr.RequestedAt DESC")).mappings().all()
    return [LeaveRequestOut(**row) for row in rows]


@router.post("", response_model=LeaveRequestOut, status_code=status.HTTP_201_CREATED)
def create_leave_request(
    payload: LeaveRequestCreate,
    user: CurrentUser = Depends(require_permission("leave.add")),
    db: Session = Depends(get_scoped_db),
) -> LeaveRequestOut:
    if user.employee_id is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "This account is not linked to an employee record")

    # EmployeeId comes from the authenticated user's own token, never from
    # the request body - a client cannot file leave on someone else's
    # behalf this way. The RLS BLOCK PREDICATE on LeaveRequests would also
    # reject an attempt to insert a row for an EmployeeId outside the
    # caller's own scope, as a second line of defense.
    inserted_id = db.execute(
        text(
            """
            INSERT INTO dbo.LeaveRequests (EmployeeId, StartDate, EndDate, LeaveType, Status)
            OUTPUT INSERTED.LeaveRequestId
            VALUES (:employee_id, :start_date, :end_date, :leave_type, 'PENDING')
            """
        ),
        {
            "employee_id": user.employee_id,
            "start_date": payload.start_date,
            "end_date": payload.end_date,
            "leave_type": payload.leave_type,
        },
    ).scalar_one()
    db.commit()

    row = db.execute(
        text(_LEAVE_SELECT_SQL + " WHERE lr.LeaveRequestId = :id"), {"id": inserted_id}
    ).mappings().first()
    return LeaveRequestOut(**row)


@router.patch("/{leave_request_id}/approve", response_model=LeaveRequestOut)
def approve_leave_request(
    leave_request_id: int,
    _user=Depends(require_permission("leave.approve")),
    db: Session = Depends(get_scoped_db),
) -> LeaveRequestOut:
    # No explicit "is this requester within my scope" check here - the RLS
    # FILTER PREDICATE on LeaveRequests already restricts which rows this
    # UPDATE can even see/match. An approver outside their scope gets 0
    # rows affected, indistinguishable from a nonexistent id.
    updated_id = db.execute(
        text(
            """
            UPDATE dbo.LeaveRequests
            SET Status = 'APPROVED'
            OUTPUT INSERTED.LeaveRequestId
            WHERE LeaveRequestId = :id AND Status = 'PENDING'
            """
        ),
        {"id": leave_request_id},
    ).scalar_one_or_none()

    if updated_id is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Leave request not found, already actioned, or outside your data scope",
        )
    db.commit()

    row = db.execute(
        text(_LEAVE_SELECT_SQL + " WHERE lr.LeaveRequestId = :id"), {"id": updated_id}
    ).mappings().first()
    return LeaveRequestOut(**row)
