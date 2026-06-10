from datetime import datetime
from typing import Generic, List, Optional, TypeVar

from pydantic import BaseModel, Field

T = TypeVar("T")


# ---------------------------------------------------------------------------
# Envelope de resposta paginada
# ---------------------------------------------------------------------------
class Page(BaseModel, Generic[T]):
    data:   List[T]
    total:  int = Field(description="Total de registros encontrados")
    page:   int = Field(description="Página atual (começa em 1)")
    pages:  int = Field(description="Total de páginas")
    limit:  int = Field(description="Registros por página")


# ---------------------------------------------------------------------------
# Marca / Categoria
# ---------------------------------------------------------------------------
class MarcaOut(BaseModel):
    id:   int
    nome: str

    class Config:
        from_attributes = True


class CategoriaOut(BaseModel):
    id:   int
    nome: str

    class Config:
        from_attributes = True


class FornecedorOut(BaseModel):
    id:          int
    nome:        str
    url:         Optional[str] = None
    observacoes: Optional[str] = None
    criado_em:   Optional[datetime] = None

    class Config:
        from_attributes = True


# ---------------------------------------------------------------------------
# Chapas
# ---------------------------------------------------------------------------
class ChapaOut(BaseModel):
    id:             int
    nome:           str
    subcategoria:   Optional[str] = Field(None, description="MDF | MDP | Compensado | Outros")
    marca:          Optional[str] = None
    largura_mm:     Optional[float] = Field(None, description="Largura em milímetros")
    comprimento_mm: Optional[float] = Field(None, description="Comprimento em milímetros")
    espessura_mm:   Optional[float] = Field(None, description="Espessura em milímetros")
    acabamento:     Optional[str]  = None
    valor:          Optional[float] = Field(None, description="Preço em R$")
    valor_m2:       Optional[float] = Field(None, description="Preço por m² em R$")
    fornecedor:     Optional[str]  = Field(None, description="Nome do fornecedor")
    criado_em:      Optional[datetime] = None
    atualizado_em:  Optional[datetime] = None

    class Config:
        from_attributes = True


# ---------------------------------------------------------------------------
# Fitas de Borda
# ---------------------------------------------------------------------------
class FitaOut(BaseModel):
    id:             int
    nome:           str
    marca:          Optional[str]  = None
    tamanho_rolo_m: Optional[float] = Field(None, description="Tamanho do rolo em metros")
    valor:          Optional[float] = Field(None, description="Preço do rolo em R$")
    valor_m_linear: Optional[float] = Field(None, description="Preço por metro linear em R$")
    fornecedor:     Optional[str]  = Field(None, description="Nome do fornecedor")
    criado_em:      Optional[datetime] = None
    atualizado_em:  Optional[datetime] = None

    class Config:
        from_attributes = True


# ---------------------------------------------------------------------------
# Ferragens
# ---------------------------------------------------------------------------
class FerragemOut(BaseModel):
    id:            int
    nome:          str
    marca:         Optional[str]  = None
    valor:         Optional[float] = Field(None, description="Preço em R$")
    fornecedor:    Optional[str]  = Field(None, description="Nome do fornecedor")
    criado_em:     Optional[datetime] = None
    atualizado_em: Optional[datetime] = None

    class Config:
        from_attributes = True


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------
class HealthOut(BaseModel):
    status:   str
    database: str
    version:  str
