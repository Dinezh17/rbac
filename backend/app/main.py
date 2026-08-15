from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.routers import auth, employees, leave, payroll

app = FastAPI(title="HRMS RBAC + Data Scope Demo", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(employees.router)
app.include_router(payroll.router)
app.include_router(leave.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
