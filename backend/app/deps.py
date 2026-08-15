from collections.abc import Generator

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.core.security import decode_access_token
from app.db.session import get_scoped_db_for_user
from app.schemas.auth import CurrentUser

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def get_current_user(token: str = Depends(oauth2_scheme)) -> CurrentUser:
    payload = decode_access_token(token)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return CurrentUser(
        user_id=payload["user_id"],
        username=payload["username"],
        employee_id=payload.get("employee_id"),
        roles=payload.get("roles", []),
        scope_types=payload.get("scope_types", []),
        permissions=payload.get("permissions", []),
    )


def require_permission(code: str):
    """FastAPI dependency factory: the ACTION-level (RBAC) half of authorization.

    This is checked from JWT claims set at login, so it costs no DB
    round-trip. It answers "can this user perform this action at all".
    It does NOT answer "which rows" - that's answered by the database's
    Row-Level Security policy once the request reaches get_scoped_db, so
    an endpoint is only fully protected once it depends on BOTH.
    """

    def checker(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if not user.has_permission(code):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Missing required permission: {code}",
            )
        return user

    return checker


def get_scoped_db(user: CurrentUser = Depends(get_current_user)) -> Generator[Session, None, None]:
    """DATA-scope half of authorization: binds this request's DB session to
    the caller's identity via SESSION_CONTEXT, so every query it runs is
    filtered by the RLS policy - see db/04_row_level_security.sql."""
    yield from get_scoped_db_for_user(user.user_id)
