"""
GausWoods — API REST
FastAPI · porta 8080 · PostgreSQL
Swagger UI: http://localhost:8080/docs
"""

from contextlib import asynccontextmanager
from time import perf_counter
from typing import Optional

import psycopg2
import psycopg2.pool
from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.security import HTTPBasic
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings
from .database import get_db, init_pool, close_pool
from .deps import verify_credentials
from .logging_utils import log_error, log_request
from .routers import chapas, ferragens, fitas, marcas, categorias, health, cotacoes, fornecedores, clientes, configuracoes

settings = Settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_pool(settings.dsn)
    # Executa o DDL de criação/migração de tabelas uma única vez no startup.
    # Remove o overhead de ~360ms por request que existia quando ensure_table()
    # era chamado dentro de cada endpoint handler.
    import logging
    from .database import _pool as _db_pool
    try:
        _conn = _db_pool.getconn()
        try:
            _conn.autocommit = True
            clientes.ensure_table(_conn)
            cotacoes.ensure_table(_conn)
            configuracoes.ensure_table(_conn)
            logging.getLogger("startup").info("DDL startup concluído: tabelas clientes, cotacoes e configuracoes_gerais prontas.")
        finally:
            _db_pool.putconn(_conn)
    except Exception as exc:
        logging.getLogger("startup").error(f"Erro no DDL de startup: {exc}")
    yield
    close_pool()


app = FastAPI(
    root_path="/api",
    title="GausWoods — API",
    description=(
        "API de consulta de produtos: Chapas (MDF/MDP/Compensado), "
        "Fitas de Borda e Ferragens.\n\n"
        "**Autenticação:** HTTP Basic Auth — envie usuário e senha em todas as requisições."
    ),
    version="1.0.0",
    contact={"name": "Gabriel", "email": "contato@exemplo.com"},
    license_info={"name": "MIT"},
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


@app.middleware("http")
async def performance_logging_middleware(request, call_next):
    start = perf_counter()
    try:
        response = await call_next(request)
    except Exception as exc:
        elapsed_ms = (perf_counter() - start) * 1000
        log_request(request.method, request.url.path, request.url.query, 500, elapsed_ms)
        log_error(
            "api.unhandled",
            "Erro nao tratado na request",
            exc,
            method=request.method,
            path=request.url.path,
            query=request.url.query,
            elapsed_ms=f"{elapsed_ms:.2f}",
        )
        raise

    elapsed_ms = (perf_counter() - start) * 1000
    log_request(request.method, request.url.path, request.url.query, response.status_code, elapsed_ms)
    response.headers["X-Response-Time-ms"] = f"{elapsed_ms:.2f}"

    if response.status_code >= 400:
        log_error(
            "api.response",
            "Resposta com erro",
            None,
            method=request.method,
            path=request.url.path,
            query=request.url.query,
            status=response.status_code,
            elapsed_ms=f"{elapsed_ms:.2f}",
        )

    return response

_auth = [Depends(verify_credentials)]

# /health permanece público (monitoramento externo não precisa de auth)
app.include_router(health.router,       tags=["Health"])

# Todos os demais endpoints exigem Basic Auth
app.include_router(chapas.router,       prefix="/chapas",       tags=["Chapas"],          dependencies=_auth)
app.include_router(ferragens.router,    prefix="/ferragens",    tags=["Ferragens"],        dependencies=_auth)
app.include_router(fitas.router,        prefix="/fitas",        tags=["Fitas de Borda"],   dependencies=_auth)
app.include_router(marcas.router,       prefix="/marcas",       tags=["Marcas"],           dependencies=_auth)
app.include_router(categorias.router,   prefix="/categorias",   tags=["Categorias"],       dependencies=_auth)
app.include_router(cotacoes.router,     prefix="/cotacoes",     tags=["Cotações"],         dependencies=_auth)
app.include_router(fornecedores.router, prefix="/fornecedores", tags=["Fornecedores"],     dependencies=_auth)
app.include_router(clientes.router,     prefix="/clientes",     tags=["Clientes"],         dependencies=_auth)
app.include_router(configuracoes.router, prefix="/configuracoes", tags=["Configurações Gerais"], dependencies=_auth)
