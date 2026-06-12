"""
Utilitarios de busca compartilhados pelos routers de catalogo
(chapas, fitas, ferragens).

build_nome_condition: busca "contem" tolerante a acentuacao e por palavras.
Ex.: termo="Mad" casa com "Madeira Bege Ultra" (via immutable_unaccent +
ILIKE no token). Quando o usuario digita varias palavras (ex.: "Bege
Ultra"), cada palavra precisa aparecer em algum lugar do nome (AND entre os
tokens) — um unico token ja basta para casar, conforme o exemplo do
enunciado.

Depende da extensao `unaccent` e da funcao `immutable_unaccent` criadas pela
migration_v12_busca_unaccent.py.
"""

from typing import List, Optional, Tuple


def build_nome_condition(coluna: str, termo: Optional[str]) -> Tuple[str, List[str]]:
    """Retorna (condicao_sql, params) para casar `coluna` contra `termo`.

    Se `termo` for vazio/None, retorna ("", []) — caller nao deve adicionar
    a condicao nesse caso.
    """
    if not termo or not termo.strip():
        return "", []

    tokens = termo.strip().split()
    conds = []
    params: List[str] = []
    for tok in tokens:
        conds.append(f"immutable_unaccent(lower({coluna})) ILIKE immutable_unaccent(lower(%s))")
        params.append(f"%{tok}%")

    return "(" + " AND ".join(conds) + ")", params
