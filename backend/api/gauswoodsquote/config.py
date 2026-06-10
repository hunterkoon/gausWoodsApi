from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    db_host: str
    db_port: int = 5432
    db_name: str
    db_user: str
    db_password: str
    pool_min: int = 2
    pool_max: int = 10

    # Credenciais da API (Basic Auth)
    api_user: str = "admin"
    api_password: str = "changeme"

    @property
    def dsn(self) -> str:
        return (
            f"host={self.db_host} port={self.db_port} "
            f"dbname={self.db_name} user={self.db_user} "
            f"password={self.db_password}"
        )

    class Config:
        env_file = ".env"
