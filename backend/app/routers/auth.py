from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.security import create_access_token, verify_password
from app.db.session import get_db
from app.deps import get_current_user
from app.schemas.auth import CurrentUser, TokenResponse

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse)
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)) -> TokenResponse:
    user_row = db.execute(
        text(
            """
            SELECT UserId, Username, PasswordHash, EmployeeId, IsActive
            FROM dbo.AppUsers
            WHERE Username = :username
            """
        ),
        {"username": form.username},
    ).mappings().first()

    if user_row is None or not user_row["IsActive"] or not verify_password(form.password, user_row["PasswordHash"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid username or password")

    role_rows = db.execute(
        text(
            """
            SELECT r.RoleName, r.ScopeType
            FROM dbo.UserRoles ur
            JOIN dbo.Roles r ON r.RoleId = ur.RoleId
            WHERE ur.UserId = :uid
            """
        ),
        {"uid": user_row["UserId"]},
    ).mappings().all()

    permission_rows = db.execute(
        text(
            """
            SELECT DISTINCT p.Code
            FROM dbo.UserRoles ur
            JOIN dbo.RolePermissions rp ON rp.RoleId = ur.RoleId
            JOIN dbo.Permissions p ON p.PermissionId = rp.PermissionId
            WHERE ur.UserId = :uid
            """
        ),
        {"uid": user_row["UserId"]},
    ).scalars().all()

    token = create_access_token(
        {
            "sub": str(user_row["UserId"]),
            "user_id": user_row["UserId"],
            "username": user_row["Username"],
            "employee_id": user_row["EmployeeId"],
            "roles": [r["RoleName"] for r in role_rows],
            "scope_types": sorted({r["ScopeType"] for r in role_rows}),
            "permissions": sorted(permission_rows),
        }
    )
    return TokenResponse(access_token=token)


@router.get("/me", response_model=CurrentUser)
def me(current_user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    return current_user
