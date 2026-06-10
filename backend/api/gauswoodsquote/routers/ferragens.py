from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from ..database import get_db, query, query_one, count
from ..deps import pagination, build_page
from ..schemas import FerragemOut, Page

router = APIRouter()

_SELECT = """
    SELECT
        f.id, f.nome,
        m.nome  AS marca,
        f.valor,
        fo.nome AS fornecedor,
        f.criado_em, f.atualizado_em
    FROM ferragens f
    LEFT JOIN marcas       m  ON m.id  = f.marca_id
    LEFT JOIN fornecedores fo ON fo.id = f.fornecedor_id
"""

_FROM_COUNT = """
    FROM ferragens f
    LEFT JOIN marcas       m  ON m.id  = f.marca_id
    LEFT JOIN fornecedores fo ON fo.id = f.fornecedor_id
"""


def _build_where(nome, marca, valor_min, valor_max, fornecedor) -> tuple[str, list]:
    conds, params = [], []
    if nome:
        conds.append("f.nome ILIKE %s");  params.append(f"%{nome}%")
    if marca:
        conds.append("m.nome ILIKE %s");  params.append(f"%{marca}%")
    if fornecedor:
        conds.append("fo.nome ILIKE %s"); params.append(f"%{fornecedor}%")
    if valor_min is not None:
        conds.append("f.valor >= %s");    params.append(valor_min)
    if valor_max is not None:
        conds.append("f.valor <= %s");    params.append(valor_max)
    where = ("WHERE " + " AND ".join(conds)) if conds else ""
    return where, params


@router.get("", response_model=Page[FerragemOut], summary="Listar ferragens com filtros")
def listar_ferragens(
    nome:       Optional[str]   = Query(None, description="Busca parcial pelo nome"),
    marca:      Optional[str]   = Query(None, description="Filtrar por marca"),
    fornecedor: Optional[str]   = Query(None, description="Filtrar por fornecedor"),
    valor_min:  Optional[float] = Query(None, description="Preço mínimo (R$)"),
    valor_max:  Optional[float] = Query(None, description="Preço máximo (R$)"),
    pg=Depends(pagination),
    conn=Depends(get_db),
):
    where, params = _build_where(nome, marca, valor_min, valor_max, fornecedor)
    rows = query(conn, f"""
        SELECT q.*, COUNT(*) OVER() AS total_count
        FROM ({_SELECT} {where}) q
        ORDER BY q.nome
        LIMIT %s OFFSET %s
    """, params + [pg["limit"], pg["offset"]])
    total = int(rows[0].pop("total_count", 0)) if rows else 0
    for r in rows:
        r.pop("total_count", None)
    return build_page([FerragemOut(**r) for r in rows], total, pg["page"], pg["limit"])


@router.get("/{ferragem_id}", response_model=FerragemOut, summary="Detalhe de uma ferragem por ID")
def detalhe_ferragem(ferragem_id: int, conn=Depends(get_db)):
    row = query_one(conn, f"{_SELECT} WHERE f.id = %s", (ferragem_id,))
    if not row:
        raise HTTPException(404, f"Ferragem {ferragem_id} não encontrada")
    return FerragemOut(**row)
