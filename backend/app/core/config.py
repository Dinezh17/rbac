from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # SQL Server connection
    db_server: str = "localhost,1433"
    db_name: str = "hrms"
    db_user: str = "sa"
    db_password: str = "YourStrong!Passw0rd"
    db_driver: str = "ODBC Driver 17 for SQL Server"
    db_pool_size: int = 10
    db_max_overflow: int = 20

    # JWT
    jwt_secret: str = "dev-secret-change-me"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60

    # CORS
    cors_origins: list[str] = ["http://localhost:5173"]

    @property
    def sqlalchemy_database_uri(self) -> str:
        driver = self.db_driver.replace(" ", "+")
        return (
            f"mssql+pyodbc://{self.db_user}:{self.db_password}"
            f"@{self.db_server}/{self.db_name}?driver={driver}"
            f"&TrustServerCertificate=yes"
        )


settings = Settings()
