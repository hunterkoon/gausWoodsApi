from fastapi import APIRouter, Depends

from ..database import get_db, query
from ..schemas import CategoriaOut

router = APIRouter()


@router.get("", response_model=list[CategoriaOut], summary="Listar todas as categorias")
def listar_categorias(conn=Depends(get_db)):
    return [CategoriaOut(**r) for r in query(conn, "SELECT id, nome FROM categorias ORDER BY nome")]
