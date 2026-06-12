"""
Cotações — CRUD
POST /cotacoes           → cria nova cotação
GET  /cotacoes           → lista com filtros e paginação
GET  /cotacoes/{id}      → detalhe completo
PUT  /cotacoes/{id}      → edição completa (projeto, fitas, ferragens, custos, etc.)
PUT  /cotacoes/{id}/desconto → atalho para desconto
"""

import json
from datetime import datetime
from threading import Lock
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from ..database import get_db, query, query_one, count, execute
from ..deps import pagination, build_page

from ..pricing import pv_divisor, pv_com_desconto, abaixo_custo
from ..pricing_service import PricingInput, PricingResult, calcular_pricing
from ..nesting_service import NestingInput, NestingResult, calcular_nesting

router = APIRouter()
_TABLE_READY = False
_TABLE_LOCK = Lock()


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class ItemChapa(BaseModel):
    espessura_mm:  float
    produto:       str
    quantidade:    int
    valor_unit:    float
    subtotal:      float


class ItemFita(BaseModel):
    produto:       str
    metros_total:  float
    valor_m:       float
    subtotal:      float


class ItemFerragem(BaseModel):
    id:         int   = 0
    nome:       str
    valor_unit: float = 0.0
    fornecedor: str   = ""
    qtd:        int   = 1
    subtotal:   float = 0.0


class OutrosCustos(BaseModel):
    ferragem:  float = 0.0
    cola:      float = 0.0
    mao_obra:  float = 0.0
    frete:     float = 0.0


class CotacaoIn(BaseModel):
    chapas:             List[ItemChapa]
    fitas:              List[ItemFita]
    outros:             OutrosCustos
    ferragens:          List[ItemFerragem] = []
    pecas_json:         Optional[List[Any]] = None   # array de peças do plano de corte
    desperdicio_pct:    float = Field(0.0)
    aproveitamento_pct: float = Field(0.0)
    total_chapas:       float
    total_fitas:        float
    total_outros:       float
    total_geral:        float
    # Custo efetivo de AQUISIÇÃO (o que se paga para comprar — chapas c/ desp, cola, MO, frete)
    custo_efetivo_chapas: float = 0.0
    custo_efetivo_fitas:  float = 0.0
    custo_efetivo_outros: float = 0.0   # ferragens + cola + frete (SEM mao_obra)
    custo_efetivo_geral:  float = 0.0   # chapas + fitas + outros (SEM mao_obra)
    # Custo do PRODUTO (apenas insumos consumidos — area × preco/m², fitas, ferragens, frete)
    custo_produto_chapas: float = 0.0
    custo_produto_fitas:  float = 0.0
    custo_produto_outros: float = 0.0   # ferragens + frete (sem cola/MO)
    custo_produto_geral:  float = 0.0
    # Mão de obra — custo interno, separado do custo de aquisição
    mao_obra:        float = 0.0
    mao_obra_manual: bool  = False      # true = valor foi substituído manualmente
    # Modelo CMC + Markup (v9)
    custo_aquisicao_total:    float = 0.0   # CA = chapas(c/desp) + fitas + ferragens + cola + frete
    custo_material_consumido:  float = 0.0  # CMC = área×preço×(1+k_perda) + fitas
    custo_operacional_base:    float = 0.0  # COB = CMC + ferragens + cola + frete + MO
    margem_lucro_pct:          float = 0.0  # % de margem por dentro do preço (markup divisor)
    preco_venda_final:         float = 0.0  # PV = COB/(1−(margem+imposto+comissão)/100)×(1−desconto/100)
    imposto_pct:               float = 0.0  # % de imposto efetivo por dentro do preço (v10)
    comissao_pct:              float = 0.0  # % de comissão de venda por dentro do preço (v10)
    observacoes:        Optional[str] = None
    cliente_id:         Optional[int] = None
    nome_projeto:       Optional[str] = None
    previsao_entrega:   Optional[str] = None
    desconto_global:    float = 0.0


class CotacaoOut(BaseModel):
    id:                 int
    chapas:             List[ItemChapa]
    fitas:              List[ItemFita]
    outros:             OutrosCustos
    ferragens:          List[ItemFerragem] = []
    pecas_json:         Optional[str]      = None
    desperdicio_pct:    float
    aproveitamento_pct: float
    total_chapas:       float
    total_fitas:        float
    total_outros:       float
    total_geral:        float
    custo_efetivo_chapas: float = 0.0
    custo_efetivo_fitas:  float = 0.0
    custo_efetivo_outros: float = 0.0
    custo_efetivo_geral:  float = 0.0
    custo_produto_chapas: float = 0.0
    custo_produto_fitas:  float = 0.0
    custo_produto_outros: float = 0.0
    custo_produto_geral:  float = 0.0
    mao_obra:        float = 0.0
    mao_obra_manual: bool  = False
    # Modelo CMC + Markup (v9)
    custo_aquisicao_total:    float = 0.0
    custo_material_consumido:  float = 0.0
    custo_operacional_base:    float = 0.0
    margem_lucro_pct:          float = 0.0
    preco_venda_final:         float = 0.0
    imposto_pct:               float = 0.0
    comissao_pct:              float = 0.0
    pricing_snapshot_json:     Optional[str] = None
    pricing_version:           int = 1
    observacoes:        Optional[str]
    cliente_id:         Optional[int]
    nome_projeto:       Optional[str]
    previsao_entrega:   Optional[str]
    desconto_global:    float
    criado_em:          datetime

    class Config:
        from_attributes = True


class CotacaoSummary(BaseModel):
    id:          int
    total_geral: float
    total_chapas: float
    total_fitas:  float
    total_outros: float
    aproveitamento_pct: float
    desconto_global: float
    cliente_id:   Optional[int]
    nome_cliente: Optional[str] = None   # incluído via JOIN — elimina N+1 em search_cotacoes
    nome_projeto: Optional[str]
    criado_em:   datetime


class DescontoUpdate(BaseModel):
    desconto_global: float = Field(..., ge=0, le=100)


class CotacaoUpdate(BaseModel):
    """Edição completa de uma cotação existente. Todos os campos são opcionais.
    Se chapas/fitas/ferragens forem fornecidos, os totais são recomputados."""
    nome_projeto:     Optional[str]   = None
    previsao_entrega: Optional[str]   = None
    observacoes:      Optional[str]   = None
    cliente_id:       Optional[int]   = None
    desconto_global:  Optional[float] = Field(None, ge=0, le=100)
    desperdicio_pct:  Optional[float] = None
    # Substituição completa dos arrays de itens
    chapas:           Optional[List[ItemChapa]]    = None
    fitas:            Optional[List[ItemFita]]     = None
    ferragens:        Optional[List[ItemFerragem]] = None
    outros:           Optional[OutrosCustos]       = None
    # Custo de aquisição (recalculado pelo cliente)
    custo_efetivo_chapas: Optional[float] = None
    custo_efetivo_fitas:  Optional[float] = None
    custo_efetivo_outros: Optional[float] = None
    custo_efetivo_geral:  Optional[float] = None
    # Custo do produto (recalculado pelo cliente)
    custo_produto_chapas: Optional[float] = None
    custo_produto_fitas:  Optional[float] = None
    custo_produto_outros: Optional[float] = None
    custo_produto_geral:  Optional[float] = None
    mao_obra:             Optional[float] = None
    mao_obra_manual:      Optional[bool]  = None
    # Peças do plano de corte (fita_c1/c2/l1/l2 por peça)
    pecas_json:           Optional[Any]   = None
    # Modelo CMC + Markup v9 — recalculados pelo MaxScript na edição
    # Antes ficavam de fora do CotacaoUpdate e só eram salvos via psycopg2
    # direto no cnc_api_helper (que falha quando psycopg2 não está disponível).
    custo_aquisicao_total:    Optional[float] = None
    custo_material_consumido:  Optional[float] = None
    custo_operacional_base:    Optional[float] = None
    margem_lucro_pct:          Optional[float] = None
    preco_venda_final:         Optional[float] = None
    imposto_pct:               Optional[float] = None
    comissao_pct:              Optional[float] = None


# ---------------------------------------------------------------------------
# DDL — idempotente (ADD COLUMN IF NOT EXISTS)
# ---------------------------------------------------------------------------

DDL_COTACOES = """
CREATE TABLE IF NOT EXISTS cotacoes (
    id                  SERIAL PRIMARY KEY,
    chapas_json         TEXT NOT NULL DEFAULT '[]',
    fitas_json          TEXT NOT NULL DEFAULT '[]',
    outros_json         TEXT NOT NULL DEFAULT '{}',
    desperdicio_pct     NUMERIC(6,2)  DEFAULT 0,
    aproveitamento_pct  NUMERIC(6,2)  DEFAULT 0,
    total_chapas        NUMERIC(12,2) DEFAULT 0,
    total_fitas         NUMERIC(12,2) DEFAULT 0,
    total_outros        NUMERIC(12,2) DEFAULT 0,
    total_geral         NUMERIC(12,2) DEFAULT 0,
    observacoes         TEXT,
    cliente_id          INTEGER,
    nome_projeto        VARCHAR(200),
    previsao_entrega    VARCHAR(20),
    desconto_global     NUMERIC(6,2)  DEFAULT 0,
    criado_em           TIMESTAMP     DEFAULT NOW()
);
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS cliente_id          INTEGER;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS nome_projeto        VARCHAR(200);
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS previsao_entrega    VARCHAR(20);
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS desconto_global     NUMERIC(6,2)  DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS custo_efetivo_chapas NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS custo_efetivo_fitas  NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS custo_efetivo_outros NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS custo_efetivo_geral  NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS ferragens_json      TEXT;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS pecas_json          TEXT;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS custo_produto_chapas NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS custo_produto_fitas  NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS custo_produto_outros NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS custo_produto_geral  NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS mao_obra             NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS mao_obra_manual      BOOLEAN       DEFAULT false;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS criado_em            TIMESTAMP     DEFAULT NOW();
ALTER TABLE cotacoes ALTER COLUMN criado_em SET DEFAULT NOW();
UPDATE cotacoes SET criado_em = NOW() WHERE criado_em IS NULL;
-- v9: modelo CMC + Markup
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS custo_aquisicao_total    NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS custo_material_consumido  NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS custo_operacional_base    NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS margem_lucro_pct          NUMERIC(6,2)  DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS preco_venda_final         NUMERIC(12,2) DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS imposto_pct               NUMERIC(6,2)  DEFAULT 0;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS comissao_pct              NUMERIC(6,2)  DEFAULT 0;
-- v10: snapshot do calculo de precificacao (markup divisor)
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS pricing_snapshot_json     TEXT;
ALTER TABLE cotacoes ADD COLUMN IF NOT EXISTS pricing_version           INTEGER DEFAULT 1;

CREATE TABLE IF NOT EXISTS preco_historico (
    id              SERIAL PRIMARY KEY,
    cotacao_id      INTEGER NOT NULL,
    tipo            VARCHAR(20) NOT NULL,
    produto         VARCHAR(200) NOT NULL,
    valor_unit      NUMERIC(12,4) NOT NULL,
    unidade         VARCHAR(20) DEFAULT 'un',
    registrado_em   TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_preco_hist_cotacao ON preco_historico(cotacao_id);
CREATE INDEX IF NOT EXISTS idx_preco_hist_produto ON preco_historico(produto);
"""


def ensure_table(conn):
    global _TABLE_READY
    if _TABLE_READY:
        return
    with _TABLE_LOCK:
        if _TABLE_READY:
            return
        execute(conn, DDL_COTACOES, commit=True)
        _TABLE_READY = True


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _registrar_precos(conn, cotacao_id: int, payload: "CotacaoIn"):
    """Registra snapshot dos precos dos insumos usados na cotacao para historico."""
    rows = []
    for c in payload.chapas:
        rows.append((cotacao_id, "chapa", c.produto, c.valor_unit, "un"))
    for f in payload.fitas:
        rows.append((cotacao_id, "fita", f.produto, f.valor_m, "m"))
    for f in payload.ferragens:
        rows.append((cotacao_id, "ferragem", f.nome, f.valor_unit, "un"))
    if not rows:
        return
    placeholders = ",".join(["(%s,%s,%s,%s,%s)"] * len(rows))
    flat_values = [v for row in rows for v in row]
    execute(conn,
        f"INSERT INTO preco_historico (cotacao_id, tipo, produto, valor_unit, unidade) VALUES {placeholders}",
        flat_values, commit=True)

def _build_pricing_snapshot(cob: float, margem: float, imposto: float, comissao: float,
                             desconto: float, pv_final_fallback: float = 0.0) -> dict:
    """Monta o snapshot do calculo de precificacao (markup divisor v10)."""
    pv_bruto = _pv_divisor(cob, margem, imposto, comissao)
    pv_final = pv_com_desconto(pv_bruto, desconto) if pv_bruto > 0 else pv_final_fallback
    return {
        "custo_operacional_base": round(cob, 2),
        "margem_lucro_pct": margem,
        "imposto_pct": imposto,
        "comissao_pct": comissao,
        "desconto_global": desconto,
        "preco_venda_bruto": round(pv_bruto, 2),
        "preco_venda_final": round(pv_final, 2),
        "abaixo_custo": abaixo_custo(pv_final, cob) if cob > 0 else False,
    }


def _parse_ferragens(raw: Optional[str]) -> List[ItemFerragem]:
    if not raw:
        return []
    try:
        items = json.loads(raw)
        if not isinstance(items, list):
            return []
        result = []
        for it in items:
            if isinstance(it, dict):
                result.append(ItemFerragem(
                    id=int(it.get("id", 0)),
                    nome=str(it.get("nome", "")),
                    valor_unit=float(it.get("valor_unit", it.get("valor", 0)) or 0),
                    fornecedor=str(it.get("fornecedor", "")),
                    qtd=int(it.get("qtd", 1)),
                    subtotal=float(it.get("subtotal", 0) or 0),
                ))
        return result
    except Exception:
        return []


def _row_to_out(row: dict) -> CotacaoOut:
    return CotacaoOut(
        id=row["id"],
        chapas=[ItemChapa(**c) for c in json.loads(row["chapas_json"] or "[]")],
        fitas=[ItemFita(**f) for f in json.loads(row["fitas_json"] or "[]")],
        outros=OutrosCustos(**json.loads(row["outros_json"] or "{}")),
        ferragens=_parse_ferragens(row.get("ferragens_json")),
        pecas_json=row.get("pecas_json"),
        desperdicio_pct=float(row["desperdicio_pct"] or 0),
        aproveitamento_pct=float(row["aproveitamento_pct"] or 0),
        total_chapas=float(row["total_chapas"] or 0),
        total_fitas=float(row["total_fitas"] or 0),
        total_outros=float(row["total_outros"] or 0),
        total_geral=float(row["total_geral"] or 0),
        custo_efetivo_chapas=float(row.get("custo_efetivo_chapas") or 0),
        custo_efetivo_fitas=float(row.get("custo_efetivo_fitas") or 0),
        custo_efetivo_outros=float(row.get("custo_efetivo_outros") or 0),
        custo_efetivo_geral=float(row.get("custo_efetivo_geral") or 0),
        custo_produto_chapas=float(row.get("custo_produto_chapas") or 0),
        custo_produto_fitas=float(row.get("custo_produto_fitas") or 0),
        custo_produto_outros=float(row.get("custo_produto_outros") or 0),
        custo_produto_geral=float(row.get("custo_produto_geral") or 0),
        mao_obra=float(row.get("mao_obra") or 0),
        mao_obra_manual=bool(row.get("mao_obra_manual") or False),
        custo_aquisicao_total=float(row.get("custo_aquisicao_total") or 0),
        custo_material_consumido=float(row.get("custo_material_consumido") or 0),
        custo_operacional_base=float(row.get("custo_operacional_base") or 0),
        margem_lucro_pct=float(row.get("margem_lucro_pct") or 0),
        preco_venda_final=float(row.get("preco_venda_final") or 0),
        imposto_pct=float(row.get("imposto_pct") or 0),
        comissao_pct=float(row.get("comissao_pct") or 0),
        pricing_snapshot_json=row.get("pricing_snapshot_json"),
        pricing_version=int(row.get("pricing_version") or 1),
        observacoes=row.get("observacoes"),
        cliente_id=row.get("cliente_id"),
        nome_projeto=row.get("nome_projeto"),
        previsao_entrega=row.get("previsao_entrega"),
        desconto_global=float(row.get("desconto_global") or 0),
        criado_em=row.get("criado_em") or datetime.now(),
    )


def _row_to_summary(row: dict) -> CotacaoSummary:
    return CotacaoSummary(
        id=row["id"],
        total_geral=float(row.get("total_geral") or 0),
        total_chapas=float(row.get("total_chapas") or 0),
        total_fitas=float(row.get("total_fitas") or 0),
        total_outros=float(row.get("total_outros") or 0),
        aproveitamento_pct=float(row.get("aproveitamento_pct") or 0),
        desconto_global=float(row.get("desconto_global") or 0),
        cliente_id=row.get("cliente_id"),
        nome_cliente=row.get("nome_cliente"),
        nome_projeto=row.get("nome_projeto"),
        criado_em=row.get("criado_em") or datetime.now(),
    )


_pv_divisor = pv_divisor


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.post("/pricing/calcular", response_model=PricingResult,
             summary="Calcular precificacao (CA/CMC/COB/PV) sem persistir")
def calcular_precificacao(payload: PricingInput, conn=Depends(get_db)):
    """Motor de calculo central de precificacao.

    Recebe chapas, pecas e parametros comerciais brutos e retorna o
    detalhamento completo (CA, CMC, COB, PV bruto/final, alertas).
    Nao persiste nada — uso para preview/validacao e para futura migracao
    do calculo do MaxScript/planilha para esta API.

    Fase 4 (custos indiretos): quando o payload informa horas_* mas nao traz
    custo_hora_operacional, o valor e derivado de configuracoes_gerais
    (custos fixos mensais / horas_produtivas_mes).
    """
    horas_totais = payload.horas_projeto + payload.horas_fabricacao + payload.horas_instalacao
    if horas_totais > 0 and payload.custo_hora_operacional <= 0:
        try:
            from .configuracoes import custo_hora_operacional as _cho
            payload.custo_hora_operacional = _cho(conn)
        except Exception:
            pass  # sem configuracao -> custo indireto zero (modelo atual)
    return calcular_pricing(payload)


@router.post("/nesting/calcular", response_model=NestingResult,
             summary="Calcular plano de corte (nesting) sem persistir")
def calcular_plano_corte(payload: NestingInput):
    """Motor de calculo central de plano de corte (MAXRECTS BSSF).

    Recebe as dimensoes da chapa e a lista de pecas e retorna a posicao
    (x, y, rotacao) de cada peca em cada chapa, o numero de chapas usadas
    e o aproveitamento. Nao persiste nada.
    """
    return calcular_nesting(payload)


@router.post("", response_model=CotacaoOut, status_code=201,
             summary="Criar nova cotação de plano de corte")
def criar_cotacao(payload: CotacaoIn, conn=Depends(get_db)):
    total_outros = (payload.outros.ferragem + payload.outros.cola +
                    payload.outros.mao_obra + payload.outros.frete)

    ferragens_json = json.dumps(
        [f.model_dump() for f in payload.ferragens], ensure_ascii=False
    ) if payload.ferragens else None

    pecas_json = json.dumps(payload.pecas_json, ensure_ascii=False) \
        if payload.pecas_json else None

    pricing_snapshot = _build_pricing_snapshot(
        payload.custo_operacional_base, payload.margem_lucro_pct,
        payload.imposto_pct, payload.comissao_pct, payload.desconto_global,
        pv_final_fallback=payload.preco_venda_final,
    )
    pricing_snapshot_json = json.dumps(pricing_snapshot, ensure_ascii=False)

    row = execute(conn, """
        INSERT INTO cotacoes
          (chapas_json, fitas_json, outros_json,
           desperdicio_pct, aproveitamento_pct,
           total_chapas, total_fitas, total_outros, total_geral,
           observacoes, cliente_id, nome_projeto, previsao_entrega, desconto_global,
           custo_efetivo_chapas, custo_efetivo_fitas, custo_efetivo_outros, custo_efetivo_geral,
           ferragens_json, pecas_json,
           custo_produto_chapas, custo_produto_fitas, custo_produto_outros, custo_produto_geral,
           mao_obra, mao_obra_manual,
           custo_aquisicao_total, custo_material_consumido, custo_operacional_base,
           margem_lucro_pct, preco_venda_final, imposto_pct, comissao_pct,
           pricing_snapshot_json, pricing_version,
           criado_em)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,1,NOW())
        RETURNING id, criado_em
    """, (
        json.dumps([c.model_dump() for c in payload.chapas]),
        json.dumps([f.model_dump() for f in payload.fitas]),
        json.dumps(payload.outros.model_dump()),
        payload.desperdicio_pct,
        payload.aproveitamento_pct,
        payload.total_chapas,
        payload.total_fitas,
        total_outros,
        payload.total_geral,
        payload.observacoes,
        payload.cliente_id,
        payload.nome_projeto,
        payload.previsao_entrega,
        payload.desconto_global,
        payload.custo_efetivo_chapas,
        payload.custo_efetivo_fitas,
        payload.custo_efetivo_outros,
        payload.custo_efetivo_geral,
        ferragens_json,
        pecas_json,
        payload.custo_produto_chapas,
        payload.custo_produto_fitas,
        payload.custo_produto_outros,
        payload.custo_produto_geral,
        payload.mao_obra,
        payload.mao_obra_manual,
        payload.custo_aquisicao_total,
        payload.custo_material_consumido,
        payload.custo_operacional_base,
        payload.margem_lucro_pct,
        payload.preco_venda_final,
        payload.imposto_pct,
        payload.comissao_pct,
        pricing_snapshot_json,
    ), commit=True, returning=True)

    cotacao_id = row[0]
    _registrar_precos(conn, cotacao_id, payload)

    row_full = query_one(conn, "SELECT * FROM cotacoes WHERE id = %s", (cotacao_id,))
    return _row_to_out(row_full)


@router.get("", summary="Listar cotações")
def listar_cotacoes(
    valor_min:  Optional[float] = Query(None),
    valor_max:  Optional[float] = Query(None),
    cliente_id: Optional[int]   = Query(None),
    pg=Depends(pagination),
    conn=Depends(get_db),
):
    conds, params = [], []
    if cliente_id is not None:
        conds.append("cliente_id = %s"); params.append(cliente_id)
    if valor_min is not None:
        conds.append("total_geral >= %s"); params.append(valor_min)
    if valor_max is not None:
        conds.append("total_geral <= %s"); params.append(valor_max)
    where = ("WHERE " + " AND ".join(conds)) if conds else ""

    rows = query(conn,
        f"""SELECT c.id, c.total_geral, c.total_chapas, c.total_fitas, c.total_outros,
                   c.aproveitamento_pct, c.desconto_global, c.cliente_id, c.nome_projeto, c.criado_em,
                   cl.nome AS nome_cliente,
                   COUNT(*) OVER() AS total_count
            FROM cotacoes c
            LEFT JOIN clientes cl ON cl.id = c.cliente_id
            {where}
            ORDER BY c.criado_em DESC
            LIMIT %s OFFSET %s""",
        params + [pg["limit"], pg["offset"]]
    )
    total = int(rows[0].pop("total_count", 0)) if rows else 0
    for r in rows:
        r.pop("total_count", None)
    return build_page([_row_to_summary(r) for r in rows], total, pg["page"], pg["limit"])


@router.get("/cliente/{cliente_id}", summary="Listar cotacoes por cliente")
def listar_cotacoes_por_cliente(
    cliente_id: int,
    pg=Depends(pagination),
    conn=Depends(get_db),
):
    rows = query(conn,
        """SELECT c.id, c.total_geral, c.total_chapas, c.total_fitas, c.total_outros,
                  c.aproveitamento_pct, c.desconto_global, c.cliente_id, c.nome_projeto, c.criado_em,
                  cl.nome AS nome_cliente,
                  COUNT(*) OVER() AS total_count
           FROM cotacoes c
           LEFT JOIN clientes cl ON cl.id = c.cliente_id
           WHERE c.cliente_id = %s
           ORDER BY c.criado_em DESC
           LIMIT %s OFFSET %s""",
        [cliente_id, pg["limit"], pg["offset"]]
    )
    total = int(rows[0].pop("total_count", 0)) if rows else 0
    for r in rows:
        r.pop("total_count", None)
    return build_page([_row_to_summary(r) for r in rows], total, pg["page"], pg["limit"])


@router.get("/{cotacao_id}", response_model=CotacaoOut,
            summary="Detalhe de uma cotação por ID")
def detalhe_cotacao(cotacao_id: int, conn=Depends(get_db)):
    row = query_one(conn, "SELECT * FROM cotacoes WHERE id = %s", (cotacao_id,))
    if not row:
        raise HTTPException(404, f"Cotação {cotacao_id} não encontrada")
    return _row_to_out(row)


@router.put("/{cotacao_id}/desconto",
            summary="Atualizar desconto global de uma cotação")
def atualizar_desconto(cotacao_id: int, payload: DescontoUpdate, conn=Depends(get_db)):
    existing = query_one(conn, "SELECT * FROM cotacoes WHERE id = %s", (cotacao_id,))
    if not existing:
        raise HTTPException(404, f"Cotação {cotacao_id} não encontrada")
    cob_val = float(existing.get("custo_operacional_base") or 0)
    margem = float(existing.get("margem_lucro_pct") or 0)
    imposto = float(existing.get("imposto_pct") or 0)
    comissao = float(existing.get("comissao_pct") or 0)
    pv_bruto = _pv_divisor(cob_val, margem, imposto, comissao)
    warning = None
    snapshot = _build_pricing_snapshot(cob_val, margem, imposto, comissao,
                                        payload.desconto_global,
                                        pv_final_fallback=float(existing.get("preco_venda_final") or 0))
    snapshot_json = json.dumps(snapshot, ensure_ascii=False)
    nova_versao = int(existing.get("pricing_version") or 1) + 1
    if pv_bruto > 0:
        pv_final = pv_com_desconto(pv_bruto, payload.desconto_global)
        if abaixo_custo(pv_final, cob_val):
            warning = (f"Preço final R$ {pv_final:.2f} está abaixo do custo "
                       f"operacional R$ {cob_val:.2f} — venda com prejuízo.")
        execute(conn, """
            UPDATE cotacoes
               SET desconto_global = %s,
                   preco_venda_final = %s,
                   total_geral = %s,
                   pricing_snapshot_json = %s,
                   pricing_version = %s
             WHERE id = %s
        """, (payload.desconto_global, pv_final, pv_final, snapshot_json, nova_versao, cotacao_id), commit=True)
    else:
        execute(conn, """
            UPDATE cotacoes
               SET desconto_global = %s,
                   pricing_snapshot_json = %s,
                   pricing_version = %s
             WHERE id = %s
        """, (payload.desconto_global, snapshot_json, nova_versao, cotacao_id), commit=True)
    row = query_one(conn, "SELECT * FROM cotacoes WHERE id = %s", (cotacao_id,))
    result = _row_to_out(row).model_dump()
    if warning:
        result["warning"] = warning
    return result


@router.put("/{cotacao_id}", response_model=CotacaoOut,
            summary="Edição completa de uma cotação")
def atualizar_cotacao(cotacao_id: int, payload: CotacaoUpdate, conn=Depends(get_db)):
    existing = query_one(conn, "SELECT * FROM cotacoes WHERE id = %s", (cotacao_id,))
    if not existing:
        raise HTTPException(404, f"Cotação {cotacao_id} não encontrada")

    updates, values = [], []

    # Campos simples
    if payload.nome_projeto is not None:
        updates.append("nome_projeto = %s");     values.append(payload.nome_projeto)
    if payload.previsao_entrega is not None:
        updates.append("previsao_entrega = %s"); values.append(payload.previsao_entrega)
    if payload.observacoes is not None:
        updates.append("observacoes = %s");      values.append(payload.observacoes)
    if payload.cliente_id is not None:
        updates.append("cliente_id = %s");       values.append(payload.cliente_id)
    if payload.desconto_global is not None:
        updates.append("desconto_global = %s");  values.append(payload.desconto_global)
    if payload.desperdicio_pct is not None:
        updates.append("desperdicio_pct = %s");  values.append(payload.desperdicio_pct)

    # Arrays de itens — substitui e recomputa totais
    novo_total_chapas = float(existing["total_chapas"] or 0)
    novo_total_fitas  = float(existing["total_fitas"]  or 0)
    novo_total_outros = float(existing["total_outros"] or 0)

    if payload.chapas is not None:
        updates.append("chapas_json = %s")
        values.append(json.dumps([c.model_dump() for c in payload.chapas]))
        novo_total_chapas = sum(c.subtotal for c in payload.chapas)
        updates.append("total_chapas = %s"); values.append(novo_total_chapas)

    if payload.fitas is not None:
        updates.append("fitas_json = %s")
        values.append(json.dumps([f.model_dump() for f in payload.fitas]))
        novo_total_fitas = sum(f.subtotal for f in payload.fitas)
        updates.append("total_fitas = %s"); values.append(novo_total_fitas)

    if payload.ferragens is not None:
        ferr_json = json.dumps([f.model_dump() for f in payload.ferragens], ensure_ascii=False)
        updates.append("ferragens_json = %s"); values.append(ferr_json)

    if payload.outros is not None:
        novo_total_outros = (payload.outros.ferragem + payload.outros.cola +
                             payload.outros.mao_obra + payload.outros.frete)
        updates.append("outros_json = %s")
        values.append(json.dumps(payload.outros.model_dump()))
        updates.append("total_outros = %s"); values.append(novo_total_outros)

    # total_geral: usar preco_venda_final (v9+) quando disponivel,
    # senao fallback para soma legacy dos componentes.
    if payload.preco_venda_final is None and any(x is not None for x in [payload.chapas, payload.fitas, payload.outros, payload.desconto_global]):
        cob_val = payload.custo_operacional_base if payload.custo_operacional_base is not None \
                  else float(existing.get("custo_operacional_base") or 0)
        margem_val = payload.margem_lucro_pct if payload.margem_lucro_pct is not None \
                     else float(existing.get("margem_lucro_pct") or 0)
        imp_val = payload.imposto_pct if payload.imposto_pct is not None \
                  else float(existing.get("imposto_pct") or 0)
        com_val = payload.comissao_pct if payload.comissao_pct is not None \
                  else float(existing.get("comissao_pct") or 0)
        desc = payload.desconto_global if payload.desconto_global is not None \
               else float(existing.get("desconto_global") or 0)
        if cob_val > 0:
            pv_bruto = _pv_divisor(cob_val, margem_val, imp_val, com_val)
            novo_total = pv_com_desconto(pv_bruto, desc)
        else:
            novo_total = (novo_total_chapas + novo_total_fitas + novo_total_outros) * (1.0 - desc / 100.0)
        updates.append("total_geral = %s"); values.append(novo_total)

    # Custo efetivo
    if payload.custo_efetivo_chapas is not None:
        updates.append("custo_efetivo_chapas = %s"); values.append(payload.custo_efetivo_chapas)
    if payload.custo_efetivo_fitas is not None:
        updates.append("custo_efetivo_fitas = %s");  values.append(payload.custo_efetivo_fitas)
    if payload.custo_efetivo_outros is not None:
        updates.append("custo_efetivo_outros = %s"); values.append(payload.custo_efetivo_outros)
    if payload.custo_efetivo_geral is not None:
        updates.append("custo_efetivo_geral = %s");  values.append(payload.custo_efetivo_geral)

    if payload.custo_produto_chapas is not None:
        updates.append("custo_produto_chapas = %s"); values.append(payload.custo_produto_chapas)
    if payload.custo_produto_fitas is not None:
        updates.append("custo_produto_fitas = %s");  values.append(payload.custo_produto_fitas)
    if payload.custo_produto_outros is not None:
        updates.append("custo_produto_outros = %s"); values.append(payload.custo_produto_outros)
    if payload.custo_produto_geral is not None:
        updates.append("custo_produto_geral = %s");  values.append(payload.custo_produto_geral)

    # Mão de obra separada do custo de aquisição
    if payload.mao_obra is not None:
        updates.append("mao_obra = %s");        values.append(payload.mao_obra)
    if payload.mao_obra_manual is not None:
        updates.append("mao_obra_manual = %s"); values.append(payload.mao_obra_manual)

    # Modelo CMC + Markup v9 — antes só salvos via psycopg2 direto no helper
    # (que falha quando psycopg2 nao esta disponivel no Python embarcado do 3ds Max).
    # Agora persistidos aqui via endpoint padrao.
    if payload.custo_aquisicao_total is not None:
        updates.append("custo_aquisicao_total = %s");    values.append(payload.custo_aquisicao_total)
    if payload.custo_material_consumido is not None:
        updates.append("custo_material_consumido = %s"); values.append(payload.custo_material_consumido)
    if payload.custo_operacional_base is not None:
        updates.append("custo_operacional_base = %s");   values.append(payload.custo_operacional_base)
    if payload.margem_lucro_pct is not None:
        updates.append("margem_lucro_pct = %s");         values.append(payload.margem_lucro_pct)
    if payload.preco_venda_final is not None:
        updates.append("preco_venda_final = %s");        values.append(payload.preco_venda_final)
        updates.append("total_geral = %s");              values.append(payload.preco_venda_final)
    if payload.imposto_pct is not None:
        updates.append("imposto_pct = %s");              values.append(payload.imposto_pct)
    if payload.comissao_pct is not None:
        updates.append("comissao_pct = %s");             values.append(payload.comissao_pct)

    # Snapshot de precificacao (v10) — recomputado sempre que algum parametro
    # de markup ou o desconto mudar, com versao incrementada.
    pricing_fields = [payload.custo_operacional_base, payload.margem_lucro_pct,
                       payload.imposto_pct, payload.comissao_pct,
                       payload.desconto_global, payload.preco_venda_final]
    if any(x is not None for x in pricing_fields):
        cob_val = payload.custo_operacional_base if payload.custo_operacional_base is not None \
                  else float(existing.get("custo_operacional_base") or 0)
        margem_val = payload.margem_lucro_pct if payload.margem_lucro_pct is not None \
                     else float(existing.get("margem_lucro_pct") or 0)
        imp_val = payload.imposto_pct if payload.imposto_pct is not None \
                  else float(existing.get("imposto_pct") or 0)
        com_val = payload.comissao_pct if payload.comissao_pct is not None \
                  else float(existing.get("comissao_pct") or 0)
        desc_val = payload.desconto_global if payload.desconto_global is not None \
                   else float(existing.get("desconto_global") or 0)
        pv_final_val = payload.preco_venda_final if payload.preco_venda_final is not None \
                        else float(existing.get("preco_venda_final") or 0)
        snapshot = _build_pricing_snapshot(cob_val, margem_val, imp_val, com_val, desc_val,
                                            pv_final_fallback=pv_final_val)
        updates.append("pricing_snapshot_json = %s")
        values.append(json.dumps(snapshot, ensure_ascii=False))
        updates.append("pricing_version = %s")
        values.append(int(existing.get("pricing_version") or 1) + 1)

    # Peças do plano de corte — salva fita_c1/c2/l1/l2 por peça
    if payload.pecas_json is not None:
        pj = payload.pecas_json
        if isinstance(pj, list):
            pj = json.dumps(pj, ensure_ascii=False)
        updates.append("pecas_json = %s"); values.append(pj)

    if updates:
        values.append(cotacao_id)
        execute(conn, f"UPDATE cotacoes SET {', '.join(updates)} WHERE id = %s",
                tuple(values), commit=True)

    row = query_one(conn, "SELECT * FROM cotacoes WHERE id = %s", (cotacao_id,))
    return _row_to_out(row)


@router.get("/precos/historico", summary="Historico de precos de insumos")
def historico_precos(
    produto: Optional[str] = Query(None),
    tipo:    Optional[str] = Query(None),
    limit:   int = Query(50, ge=1, le=500),
    conn=Depends(get_db),
):
    """Retorna variacao de precos ao longo das cotacoes."""
    conds, params = [], []
    if produto:
        conds.append("produto ILIKE %s"); params.append(f"%{produto}%")
    if tipo:
        conds.append("tipo = %s"); params.append(tipo)
    where = ("WHERE " + " AND ".join(conds)) if conds else ""
    rows = query(conn,
        f"""SELECT produto, tipo, valor_unit, unidade, cotacao_id, registrado_em
            FROM preco_historico {where}
            ORDER BY registrado_em DESC
            LIMIT %s""",
        params + [limit])
    return rows
