import math
import secrets
from functools import lru_cache
from typing import Annotated

from fastapi import Depends, HTTPException, Query, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials

from .config import Settings

# ── Configuração ─────────────────────────────────────────────────────────────

@lru_cache
def get_settings() -> Settings:
    return Settings()

# ── Paginação ─────────────────────────────────────────────────────────────────

def pagination(
    page:  Annotated[int, Query(ge=1, description="Página (começa em 1)")] = 1,
    limit: Annotated[int, Query(ge=1, le=100, description="Itens por página (máx 100)")] = 20,
):
    return {"page": page, "limit": limit, "offset": (page - 1) * limit}


def build_page(data: list, total: int, page: int, limit: int) -> dict:
    return {
        "data":  data,
        "total": total,
        "page":  page,
        "pages": max(1, math.ceil(total / limit)),
        "limit": limit,
    }

# ── Basic Auth ────────────────────────────────────────────────────────────────

_http_basic = HTTPBasic()


def verify_credentials(
    credentials: HTTPBasicCredentials = Depends(_http_basic),
    settings: Settings = Depends(get_settings),
) -> str:
    """Valida usuário e senha via HTTP Basic Auth.
    Use secrets.compare_digest para evitar timing attacks.
    """
    ok_user = secrets.compare_digest(
        credentials.username.encode("utf-8"),
        settings.api_user.encode("utf-8"),
    )
    ok_pass = secrets.compare_digest(
        credentials.password.encode("utf-8"),
        settings.api_password.encode("utf-8"),
    )
    if not (ok_user and ok_pass):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenciais inválidas",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username
