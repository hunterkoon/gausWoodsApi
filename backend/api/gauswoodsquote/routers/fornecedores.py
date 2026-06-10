from fastapi import APIRouter, Depends, HTTPException

from ..database import get_db, query, query_one
from ..schemas import FornecedorOut

router = APIRouter()


@router.get("", response_model=list[FornecedorOut], summary="Listar todos os fornecedores")
def listar_fornecedores(conn=Depends(get_db)):
    return [FornecedorOut(**r) for r in query(
        conn,
        "SELECT id, nome, url, observacoes, criado_em FROM fornecedores ORDER BY nome"
    )]


@router.get("/{fornecedor_id}", response_model=FornecedorOut, summary="Detalhe de um fornecedor")
def detalhe_fornecedor(fornecedor_id: int, conn=Depends(get_db)):
    row = query_one(
        conn,
        "SELECT id, nome, url, observacoes, criado_em FROM fornecedores WHERE id = %s",
        (fornecedor_id,)
    )
    if not row:
        raise HTTPException(404, f"Fornecedor {fornecedor_id} não encontrado")
    return FornecedorOut(**row)
