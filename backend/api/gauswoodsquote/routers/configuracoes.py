"""
Configurações Gerais — custos fixos parametrizáveis (chave/valor)
GET /configuracoes              -> listar todas as chaves/valores
PUT /configuracoes/{chave}      -> atualizar valor (e opcionalmente descricao/unidade)
POST /configuracoes             -> criar nova chave customizada
"""

from threading import Lock
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..database import get_db, query, query_one, execute

router = APIRouter()
_TABLE_READY = False
_TABLE_LOCK = Lock()


DDL_CONFIGURACOES = """
CREATE TABLE IF NOT EXISTS configuracoes_gerais (
    id            SERIAL PRIMARY KEY,
    chave         TEXT UNIQUE NOT NULL,
    descricao     TEXT,
    valor         NUMERIC NOT NULL DEFAULT 0,
    unidade       TEXT,
    categoria     TEXT,
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""

_SEEDS = [
    # (chave, descricao, valor, unidade, categoria)
    ("aluguel_mensal",                  "Aluguel mensal",                        0, "R$/mes", "custo_fixo"),
    ("energia_mensal",                  "Energia eletrica mensal",               0, "R$/mes", "custo_fixo"),
    ("depreciacao_maquina_mensal",      "Depreciacao de maquina mensal",         0, "R$/mes", "custo_fixo"),
    ("manutencao_mensal",               "Manutencao mensal",                     0, "R$/mes", "custo_fixo"),
    ("administrativo_mensal",           "Custos administrativos mensais",        0, "R$/mes", "custo_fixo"),
    ("ferramentas_consumiveis_mensal",  "Ferramentas e consumiveis mensais",     0, "R$/mes", "custo_fixo"),
    ("horas_produtivas_mes",            "Horas produtivas por mes",              0, "h/mes",  "custo_fixo"),
]

# Chaves mensais que compoem o custo_hora_operacional (handoff §3.4)
CHAVES_CUSTO_MENSAL = [
    "aluguel_mensal", "energia_mensal", "depreciacao_maquina_mensal",
    "manutencao_mensal", "administrativo_mensal", "ferramentas_consumiveis_mensal",
]


def custo_hora_operacional(conn) -> float:
    """custo_hora = soma(custos fixos mensais) / horas_produtivas_mes.

    Retorna 0.0 quando horas_produtivas_mes nao esta configurado — nesse
    caso o COB permanece identico ao modelo atual (sem custos indiretos).
    """
    ensure_table(conn)
    rows = query(conn, "SELECT chave, valor FROM configuracoes_gerais")
    vals = {r["chave"]: float(r["valor"] or 0) for r in rows}
    horas = vals.get("horas_produtivas_mes", 0.0)
    if horas <= 0:
        return 0.0
    total_mensal = sum(vals.get(k, 0.0) for k in CHAVES_CUSTO_MENSAL)
    return round(total_mensal / horas, 4)


def ensure_table(conn):
    global _TABLE_READY
    if _TABLE_READY:
        return
    with _TABLE_LOCK:
        if _TABLE_READY:
            return
        execute(conn, DDL_CONFIGURACOES, commit=True)
        for chave, descricao, valor, unidade, categoria in _SEEDS:
            execute(conn, """
                INSERT INTO configuracoes_gerais (chave, descricao, valor, unidade, categoria)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (chave) DO NOTHING
            """, (chave, descricao, valor, unidade, categoria), commit=True)
        _TABLE_READY = True


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class ConfiguracaoOut(BaseModel):
    id:            int
    chave:         str
    descricao:     Optional[str] = None
    valor:         float
    unidade:       Optional[str] = None
    categoria:     Optional[str] = None

    class Config:
        from_attributes = True


class ConfiguracaoUpdate(BaseModel):
    valor:     float
    descricao: Optional[str] = None
    unidade:   Optional[str] = None


class ConfiguracaoIn(BaseModel):
    chave:     str
    descricao: Optional[str] = None
    valor:     float = 0
    unidade:   Optional[str] = None
    categoria: Optional[str] = None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("", response_model=list[ConfiguracaoOut], summary="Listar configuracoes gerais")
def listar_configuracoes(conn=Depends(get_db)):
    ensure_table(conn)
    rows = query(conn, "SELECT id, chave, descricao, valor, unidade, categoria FROM configuracoes_gerais ORDER BY chave")
    return [ConfiguracaoOut(**r) for r in rows]


@router.put("/{chave}", response_model=ConfiguracaoOut, summary="Atualizar valor de uma configuracao")
def atualizar_configuracao(chave: str, payload: ConfiguracaoUpdate, conn=Depends(get_db)):
    ensure_table(conn)
    existing = query_one(conn, "SELECT id FROM configuracoes_gerais WHERE chave = %s", (chave,))
    if not existing:
        raise HTTPException(404, f"Configuracao '{chave}' nao encontrada")

    execute(conn, """
        UPDATE configuracoes_gerais SET
            valor = %(valor)s,
            descricao = COALESCE(%(descricao)s, descricao),
            unidade = COALESCE(%(unidade)s, unidade),
            atualizado_em = now()
        WHERE chave = %(chave)s
    """, {
        "valor": payload.valor, "descricao": payload.descricao,
        "unidade": payload.unidade, "chave": chave,
    }, commit=True)

    full = query_one(conn, "SELECT id, chave, descricao, valor, unidade, categoria FROM configuracoes_gerais WHERE chave = %s", (chave,))
    return ConfiguracaoOut(**full)


@router.post("", response_model=ConfiguracaoOut, status_code=201, summary="Criar nova chave de configuracao")
def criar_configuracao(payload: ConfiguracaoIn, conn=Depends(get_db)):
    ensure_table(conn)
    existing = query_one(conn, "SELECT id FROM configuracoes_gerais WHERE chave = %s", (payload.chave,))
    if existing:
        raise HTTPException(409, f"Configuracao '{payload.chave}' ja existe")

    row = execute(conn, """
        INSERT INTO configuracoes_gerais (chave, descricao, valor, unidade, categoria)
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id
    """, (payload.chave, payload.descricao, payload.valor, payload.unidade, payload.categoria),
        commit=True, returning=True)

    full = query_one(conn, "SELECT id, chave, descricao, valor, unidade, categoria FROM configuracoes_gerais WHERE id = %s", (row[0],))
    return ConfiguracaoOut(**full)
