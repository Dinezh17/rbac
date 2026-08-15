"""
Database session management.

Two flavors of session are exposed:

  - get_db(): a plain session, for endpoints that only touch RBAC metadata
    tables (AppUsers, Roles, Permissions, ...) which are NOT under row-level
    security. Login/`/me` use this.

  - get_scoped_db(): a session that has first told SQL Server WHO is asking,
    via sp_set_session_context, so every subsequent query against a
    scope-protected table (Employees, Payroll, LeaveRequests) is
    transparently filtered by the RLS security policy defined in
    db/04_row_level_security.sql. This is the ONE integration point
    application code needs per request - no per-query changes.

See db/04_row_level_security.sql for why @read_only MUST be 0: pooled
connections are reused across requests/users, so the context has to be
overwritten on every single request, not locked on the first one.
"""

from collections.abc import Generator

from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings

engine = create_engine(
    settings.sqlalchemy_database_uri,
    pool_size=settings.db_pool_size,
    max_overflow=settings.db_max_overflow,
    pool_pre_ping=True,
    fast_executemany=True,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def set_session_context(db: Session, app_user_id: int) -> None:
    db.execute(
        text("EXEC sp_set_session_context @key = N'app_user_id', @value = :uid, @read_only = 0"),
        {"uid": app_user_id},
    )


def get_scoped_db_for_user(app_user_id: int) -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        set_session_context(db, app_user_id)
        yield db
    finally:
        db.close()
