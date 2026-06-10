"""
Clientes — CRUD
GET  /clientes          → listar/buscar clientes
POST /clientes          → criar cliente
PUT  /clientes/{id}     → atualizar cliente
GET  /clientes/{id}     → detalhe
"""

from datetime import datetime
from threading import Lock
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel

from ..database import get_db, query, query_one, count, execute
from ..deps import pagination, build_page

router = APIRouter()
_TABLE_READY = False
_TABLE_LOCK = Lock()


# ---------------------------------------------------------------------------
# DDL
# ---------------------------------------------------------------------------

DDL_CLIENTES = """
CREATE TABLE IF NOT EXISTS clientes (
    id            SERIAL PRIMARY KEY,
    nome          VARCHAR(200) NOT NULL,
    documento     VARCHAR(20),
    telefone      VARCHAR(20),
    email         VARCHAR(150),
    endereco      TEXT,
    cidade        VARCHAR(100),
    estado        CHAR(2),
    observacoes   TEXT,
    criado_em     TIMESTAMP DEFAULT NOW(),
    atualizado_em TIMESTAMP DEFAULT NOW()
);
"""


def ensure_table(conn):
    global _TABLE_READY
    if _TABLE_READY:
        return
    with _TABLE_LOCK:
        if _TABLE_READY:
            return
        execute(conn, DDL_CLIENTES, commit=True)
        _TABLE_READY = True


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class ClienteIn(BaseModel):
    nome:        str
    documento:   Optional[str] = None
    telefone:    Optional[str] = None
    email:       Optional[str] = None
    endereco:    Optional[str] = None
    cidade:      Optional[str] = None
    estado:      Optional[str] = None
    observacoes: Optional[str] = None


class ClienteOut(ClienteIn):
    id:            int
    criado_em:     datetime
    atualizado_em: datetime

    class Config:
        from_attributes = True


class ClienteSummary(BaseModel):
    id:        int
    nome:      str
    documento: Optional[str]
    cidade:    Optional[str]
    estado:    Optional[str]
    telefone:  Optional[str]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _row_to_out(row: dict) -> ClienteOut:
    return ClienteOut(
        id=row["id"],
        nome=row["nome"],
        documento=row.get("documento"),
        telefone=row.get("telefone"),
        email=row.get("email"),
        endereco=row.get("endereco"),
        cidade=row.get("cidade"),
        estado=row.get("estado"),
        observacoes=row.get("observacoes"),
        criado_em=row.get("criado_em") or datetime.now(),
        atualizado_em=row.get("atualizado_em") or datetime.now(),
    )


def _row_to_summary(row: dict) -> ClienteSummary:
    return ClienteSummary(
        id=row["id"],
        nome=row["nome"],
        documento=row.get("documento"),
        cidade=row.get("cidade"),
        estado=row.get("estado"),
        telefone=row.get("telefone"),
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("", summary="Listar/buscar clientes")
def listar_clientes(
    nome:      Optional[str]   = Query(None),
    documento: Optional[str]   = Query(None),
    pg=Depends(pagination),
    conn=Depends(get_db),
):
    conds, params = [], []
    if nome:
        conds.append("nome ILIKE %s");      params.append(f"%{nome}%")
    if documento:
        # busca sem formatação (remove pontos, barras, hífens)
        doc_clean = "".join(c for c in documento if c.isdigit())
        conds.append("regexp_replace(documento, '[^0-9]', '', 'g') ILIKE %s")
        params.append(f"%{doc_clean}%")

    where = ("WHERE " + " AND ".join(conds)) if conds else ""
    rows  = query(conn,
        f"SELECT id, nome, documento, cidade, estado, telefone, COUNT(*) OVER() AS total_count "
        f"FROM clientes {where} ORDER BY nome LIMIT %s OFFSET %s",
        params + [pg["limit"], pg["offset"]]
    )
    total = int(rows[0].pop("total_count", 0)) if rows else 0
    for r in rows:
        r.pop("total_count", None)
    data = [_row_to_summary(r) for r in rows]
    return build_page(data, total, pg["page"], pg["limit"])


@router.post("", response_model=ClienteOut, status_code=201,
             summary="Criar novo cliente")
def criar_cliente(payload: ClienteIn, conn=Depends(get_db)):
    # NOW() explícito garante que criado_em/atualizado_em nunca são NULL
    # (evita ValidationError do Pydantic que ocorria quando DEFAULT NOW()
    # retornava None em edge cases de conexão recém-criada).
    row = execute(conn, """
        INSERT INTO clientes
          (nome, documento, telefone, email, endereco, cidade, estado, observacoes,
           criado_em, atualizado_em)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s, NOW(), NOW())
        RETURNING id, criado_em, atualizado_em
    """, (
        payload.nome, payload.documento, payload.telefone,
        payload.email, payload.endereco, payload.cidade,
        payload.estado, payload.observacoes,
    ), commit=True, returning=True)

    full = query_one(conn, "SELECT * FROM clientes WHERE id = %s", (row[0],))
    return _row_to_out(full)


@router.put("/{cliente_id}", response_model=ClienteOut,
            summary="Atualizar cliente")
def atualizar_cliente(cliente_id: int, payload: ClienteIn, conn=Depends(get_db)):
    existing = query_one(conn, "SELECT id FROM clientes WHERE id = %s", (cliente_id,))
    if not existing:
        raise HTTPException(404, f"Cliente {cliente_id} nao encontrado")

    execute(conn, """
        UPDATE clientes SET
            nome=%(nome)s, documento=%(doc)s, telefone=%(tel)s,
            email=%(email)s, endereco=%(end)s, cidade=%(cid)s,
            estado=%(est)s, observacoes=%(obs)s,
            atualizado_em=NOW()
        WHERE id=%(id)s
    """, {
        "nome": payload.nome, "doc": payload.documento,
        "tel": payload.telefone, "email": payload.email,
        "end": payload.endereco, "cid": payload.cidade,
        "est": payload.estado, "obs": payload.observacoes,
        "id": cliente_id,
    }, commit=True)

    full = query_one(conn, "SELECT * FROM clientes WHERE id = %s", (cliente_id,))
    return _row_to_out(full)


@router.get("/{cliente_id}", response_model=ClienteOut,
            summary="Detalhe de um cliente")
def detalhe_cliente(cliente_id: int, conn=Depends(get_db)):
    row = query_one(conn, "SELECT * FROM clientes WHERE id = %s", (cliente_id,))
    if not row:
        raise HTTPException(404, f"Cliente {cliente_id} nao encontrado")
    return _row_to_out(row)
