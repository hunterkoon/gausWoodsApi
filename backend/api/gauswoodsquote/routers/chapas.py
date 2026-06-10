from typing import Annotated, Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from ..database import get_db, query, query_one, count
from ..deps import pagination, build_page
from ..schemas import ChapaOut, Page

router = APIRouter()

_SELECT = """
    SELECT
        c.id, c.nome,
        cat.nome  AS subcategoria,
        m.nome    AS marca,
        c.largura_mm, c.comprimento_mm, c.espessura_mm,
        c.acabamento, c.valor, c.valor_m2,
        f.nome    AS fornecedor,
        c.criado_em, c.atualizado_em
    FROM chapas c
    LEFT JOIN marcas       m   ON m.id   = c.marca_id
    LEFT JOIN categorias   cat ON cat.id = c.categoria_id
    LEFT JOIN fornecedores f   ON f.id   = c.fornecedor_id
"""

_FROM_COUNT = """
    FROM chapas c
    LEFT JOIN marcas       m   ON m.id   = c.marca_id
    LEFT JOIN categorias   cat ON cat.id = c.categoria_id
    LEFT JOIN fornecedores f   ON f.id   = c.fornecedor_id
"""


def _build_where(nome, marca, subcategoria, espessura_min, espessura_max,
                 valor_min, valor_max, fornecedor) -> tuple[str, list]:
    conds, params = [], []

    if nome:
        conds.append("c.nome ILIKE %s");       params.append(f"%{nome}%")
    if marca:
        conds.append("m.nome ILIKE %s");       params.append(f"%{marca}%")
    if subcategoria:
        conds.append("cat.nome ILIKE %s");     params.append(f"%{subcategoria}%")
    if fornecedor:
        conds.append("f.nome ILIKE %s");       params.append(f"%{fornecedor}%")
    if espessura_min is not None:
        conds.append("c.espessura_mm >= %s");  params.append(espessura_min)
    if espessura_max is not None:
        conds.append("c.espessura_mm <= %s");  params.append(espessura_max)
    if valor_min is not None:
        conds.append("c.valor >= %s");         params.append(valor_min)
    if valor_max is not None:
        conds.append("c.valor <= %s");         params.append(valor_max)

    where = ("WHERE " + " AND ".join(conds)) if conds else ""
    return where, params


@router.get("", response_model=Page[ChapaOut], summary="Listar chapas com filtros")
def listar_chapas(
    nome:          Optional[str]   = Query(None, description="Busca parcial pelo nome"),
    marca:         Optional[str]   = Query(None, description="Filtrar por marca"),
    subcategoria:  Optional[str]   = Query(None, description="MDF | MDP | Compensado"),
    fornecedor:    Optional[str]   = Query(None, description="Filtrar por fornecedor"),
    espessura_min: Optional[float] = Query(None, description="Espessura mínima (mm)"),
    espessura_max: Optional[float] = Query(None, description="Espessura máxima (mm)"),
    valor_min:     Optional[float] = Query(None, description="Preço mínimo (R$)"),
    valor_max:     Optional[float] = Query(None, description="Preço máximo (R$)"),
    pg=Depends(pagination),
    conn=Depends(get_db),
):
    where, params = _build_where(nome, marca, subcategoria,
                                 espessura_min, espessura_max, valor_min, valor_max,
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

    return build_page([ChapaOut(**r) for r in rows], total, pg["page"], pg["limit"])


@router.get("/{chapa_id}", response_model=ChapaOut, summary="Detalhe de uma chapa por ID")
def detalhe_chapa(chapa_id: int, conn=Depends(get_db)):
    row = query_one(conn, f"{_SELECT} WHERE c.id = %s", (chapa_id,))
    if not row:
        raise HTTPException(404, f"Chapa {chapa_id} não encontrada")
    return ChapaOut(**row)
