from fastapi import APIRouter, Depends

from ..database import get_db, query_one
from ..schemas import HealthOut

router = APIRouter()


@router.get("/health", response_model=HealthOut, summary="Status do serviço")
def health(conn=Depends(get_db)):
    try:
        row = query_one(conn, "SELECT version() AS v")
        db_status = "ok"
        version   = row["v"].split(",")[0] if row else "?"
    except Exception as e:
        db_status = f"erro: {e}"
        version   = "?"

    return HealthOut(status="ok", database=db_status, version=version)
