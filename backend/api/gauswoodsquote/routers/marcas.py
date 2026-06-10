from fastapi import APIRouter, Depends

from ..database import get_db, query
from ..schemas import MarcaOut

router = APIRouter()


@router.get("", response_model=list[MarcaOut], summary="Listar todas as marcas")
def listar_marcas(conn=Depends(get_db)):
    return [MarcaOut(**r) for r in query(conn, "SELECT id, nome FROM marcas ORDER BY nome")]
