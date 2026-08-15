from pydantic import BaseModel


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class CurrentUser(BaseModel):
    user_id: int
    username: str
    employee_id: int | None
    roles: list[str]
    scope_types: list[str]
    permissions: list[str]

    def has_permission(self, code: str) -> bool:
        return code in self.permissions
