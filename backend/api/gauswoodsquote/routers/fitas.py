from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from ..database import get_db, query, query_one, count
from ..deps import pagination, build_page
from ..schemas import FitaOut, Page
from ._search_utils import build_nome_condition

router = APIRouter()

_SELECT = """
    SELECT
        f.id, f.nome,
        m.nome  AS marca,
        f.tamanho_rolo_m, f.valor, f.valor_m_linear,
        fo.nome AS fornecedor,
        f.criado_em, f.atualizado_em
    FROM fitas_borda f
    LEFT JOIN marcas       m  ON m.id  = f.marca_id
    LEFT JOIN fornecedores fo ON fo.id = f.fornecedor_id
"""

_FROM_COUNT = """
    FROM fitas_borda f
    LEFT JOIN marcas       m  ON m.id  = f.marca_id
    LEFT JOIN fornecedores fo ON fo.id = f.fornecedor_id
"""


def _build_where(nome, marca, rolo_min, rolo_max, valor_min, valor_max,
                 fornecedor) -> tuple[str, list]:
    conds, params = [], []
    if nome:
        cond, p = build_nome_condition("f.nome", nome)
        if cond:
            conds.append(cond); params.extend(p)
    if marca:
        conds.append("m.nome ILIKE %s");           params.append(f"%{marca}%")
    if fornecedor:
        conds.append("fo.nome ILIKE %s");          params.append(f"%{fornecedor}%")
    if rolo_min is not None:
        conds.append("f.tamanho_rolo_m >= %s");    params.append(rolo_min)
    if rolo_max is not None:
        conds.append("f.tamanho_rolo_m <= %s");    params.append(rolo_max)
    if valor_min is not None:
        conds.append("f.valor >= %s");             params.append(valor_min)
    if valor_max is not None:
        conds.append("f.valor <= %s");             params.append(valor_max)
    where = ("WHERE " + " AND ".join(conds)) if conds else ""
    return where, params


@router.get("", response_model=Page[FitaOut], summary="Listar fitas de borda com filtros")
def listar_fitas(
    nome:       Optional[str]   = Query(None, description="Busca parcial pelo nome"),
    marca:      Optional[str]   = Query(None, description="Filtrar por marca"),
    fornecedor: Optional[str]   = Query(None, description="Filtrar por fornecedor"),
    rolo_min:   Optional[float] = Query(None, description="Tamanho mínimo do rolo (m)"),
    rolo_max:   Optional[float] = Query(None, description="Tamanho máximo do rolo (m)"),
    valor_min:  Optional[float] = Query(None, description="Preço mínimo (R$)"),
    valor_max:  Optional[float] = Query(None, description="Preço máximo (R$)"),
    pg=Depends(pagination),
    conn=Depends(get_db),
):
    where, params = _build_where(nome, marca, rolo_min, rolo_max, valor_min, valor_max,
                                 fornecedor)
    rows = query(conn, f"""
        SELECT q.*, COUNT(*) OVER() AS total_count
        FROM ({_SELECT} {where}) q
        ORDER BY q.nome
        LIMIT %s OFFSET %s
    """, params + [pg["limit"], pg["offset"]])
    total = int(rows[0].pop("total_count", 0)) if rows else 0
    for r in rows:
        r.pop("total_count", None)
    return build_page([FitaOut(**r) for r in rows], total, pg["page"], pg["limit"])


@router.get("/{fita_id}", response_model=FitaOut, summary="Detalhe de uma fita por ID")
def detalhe_fita(fita_id: int, conn=Depends(get_db)):
    row = query_one(conn, f"{_SELECT} WHERE f.id = %s", (fita_id,))
    if not row:
        raise HTTPException(404, f"Fita {fita_id} não encontrada")
    return FitaOut(**row)
