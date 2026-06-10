from time import perf_counter
from typing import Generator

import psycopg2
import psycopg2.extras
import psycopg2.pool

from .logging_utils import log_db, log_error

_pool: psycopg2.pool.ThreadedConnectionPool | None = None
_dsn: str = ""


def init_pool(dsn: str, minconn: int = 2, maxconn: int = 10):
    """Inicializa o pool de conexões.
    keepalives: envia pings TCP ao servidor para manter conexões ociosas vivas
    e evitar OperationalError 'server closed the connection unexpectedly'
    após períodos de inatividade.
    """
    global _pool, _dsn
    _dsn = dsn
    _pool = psycopg2.pool.ThreadedConnectionPool(
        minconn, maxconn, dsn=dsn,
        keepalives=1,
        keepalives_idle=30,       # inicia keepalive após 30s de ociosidade
        keepalives_interval=10,   # reenvia a cada 10s sem resposta
        keepalives_count=5,       # descarta após 5 falhas consecutivas
    )


def close_pool():
    if _pool:
        _pool.closeall()


def _validate_conn(conn) -> bool:
    """Verifica se a conexão ainda está viva com um ping leve."""
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        return True
    except psycopg2.Error:
        return False


def get_db() -> Generator:
    start = perf_counter()
    try:
        conn = _pool.getconn()
        # Valida a conexão antes de usar — conexões ociosas podem ter sido
        # encerradas pelo servidor PostgreSQL remoto. Se morta, descarta e
        # solicita nova ao pool (o pool criará uma conexão fresca).
        if not _validate_conn(conn):
            log_db("pool_reconnect", "POOL RECONNECT (conexao morta descartada)", None,
                   (perf_counter() - start) * 1000, None, True)
            _pool.putconn(conn, close=True)
            conn = _pool.getconn()
        if not conn.autocommit:
            conn.autocommit = True
        log_db("pool_getconn", "POOL GETCONN", None, (perf_counter() - start) * 1000, None, True)
    except Exception as exc:
        elapsed_ms = (perf_counter() - start) * 1000
        log_db("pool_getconn", "POOL GETCONN", None, elapsed_ms, None, False)
        log_error("database.get_db", "Erro obtendo conexao do pool", exc, elapsed_ms=f"{elapsed_ms:.2f}")
        raise
    try:
        yield conn
    finally:
        start = perf_counter()
        _pool.putconn(conn)
        log_db("pool_putconn", "POOL PUTCONN", None, (perf_counter() - start) * 1000, None, True)


def query(conn, sql: str, params=None) -> list[dict]:
    start = perf_counter()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params or ())
            rows = [dict(r) for r in cur.fetchall()]
        log_db("query", sql, params or (), (perf_counter() - start) * 1000, len(rows), True)
        return rows
    except Exception as exc:
        elapsed_ms = (perf_counter() - start) * 1000
        log_db("query", sql, params or (), elapsed_ms, None, False)
        log_error("database.query", "Erro executando query", exc, elapsed_ms=f"{elapsed_ms:.2f}")
        raise


def query_one(conn, sql: str, params=None) -> dict | None:
    start = perf_counter()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params or ())
            row = cur.fetchone()
        log_db("query_one", sql, params or (), (perf_counter() - start) * 1000, 1 if row else 0, True)
        return dict(row) if row else None
    except Exception as exc:
        elapsed_ms = (perf_counter() - start) * 1000
        log_db("query_one", sql, params or (), elapsed_ms, None, False)
        log_error("database.query_one", "Erro executando query_one", exc, elapsed_ms=f"{elapsed_ms:.2f}")
        raise


def count(conn, sql: str, params=None) -> int:
    start = perf_counter()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            value = cur.fetchone()[0]
        log_db("count", sql, params or (), (perf_counter() - start) * 1000, 1, True)
        return value
    except Exception as exc:
        elapsed_ms = (perf_counter() - start) * 1000
        log_db("count", sql, params or (), elapsed_ms, None, False)
        log_error("database.count", "Erro executando count", exc, elapsed_ms=f"{elapsed_ms:.2f}")
        raise


def execute(conn, sql: str, params=None, *, commit: bool = False, returning: bool = False):
    start = perf_counter()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            row = cur.fetchone() if returning else None
            rowcount = cur.rowcount
        if commit:
            conn.commit()
        log_db("execute", sql, params or (), (perf_counter() - start) * 1000, rowcount, True)
        return row
    except Exception as exc:
        elapsed_ms = (perf_counter() - start) * 1000
        log_db("execute", sql, params or (), elapsed_ms, None, False)
        log_error("database.execute", "Erro executando execute", exc, elapsed_ms=f"{elapsed_ms:.2f}")
        raise
