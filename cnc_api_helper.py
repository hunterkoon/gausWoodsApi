"""
cnc_api_helper.py — Bridge MaxScript ↔ API GausWoods
Lê cnc_api_cmd.txt no temp dir, executa a chamada REST e
escreve o resultado em cnc_api_result.txt.

Comandos suportados:
  health_check
  search_chapas   [nome=X] [espessura_min=X] [espessura_max=X] [limit=X]
  search_fitas    [nome=X] [limit=X]
  start_api       script_dir=X
  create_cotacao  (lê cnc_cotacao_data.txt do temp dir)
"""

import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta

API_BASE     = "https://gauswoods.com.br/api"
API_USER     = ""
API_PASSWORD = ""
TMP          = tempfile.gettempdir()
CMD_FILE     = os.path.join(TMP, "cnc_api_cmd.txt")
RESULT_FILE  = os.path.join(TMP, "cnc_api_result.txt")
COTACAO_FILE = os.path.join(TMP, "cnc_cotacao_data.txt")
PRICING_FILE = os.path.join(TMP, "cnc_pricing_data.txt")
CLIENT_FILE  = os.path.join(TMP, "cnc_cliente_data.txt")
DEBUG_FILE   = os.path.join(TMP, "cnc_api_debug.txt")
LOG_DIR      = os.path.join(os.path.dirname(__file__), "DADOS", "logs")
PERF_FILE    = os.path.join(LOG_DIR, "maxscript_api_requests.log")
ERROR_FILE   = os.path.join(LOG_DIR, "maxscript_api_errors.log")
LAST_RESULT_STATUS = "?"


def _load_brand_logo_svg() -> str:
    """Return the Gaus Woods logo as clean inline SVG, or an empty string."""
    here = os.path.dirname(os.path.abspath(__file__))
    for name in ("GAUSWOOD.svg", "Group 1 (1).svg"):
        svg_path = os.path.join(here, name)
        if not os.path.exists(svg_path):
            continue
        try:
            with open(svg_path, encoding="utf-8") as f:
                raw = f.read()
            raw = re.sub(r'<\?xml[^>]+\?>', '', raw)
            raw = re.sub(r'<sodipodi:namedview[^>]*/>', '', raw)
            raw = re.sub(r'<sodipodi:namedview.*?</sodipodi:namedview>', '', raw, flags=re.S)
            return raw.strip()
        except Exception:
            return ""
    return ""


def _brand_logo_block(svg_logo_inline=None) -> str:
    svg_logo_inline = svg_logo_inline if svg_logo_inline is not None else _load_brand_logo_svg()
    if svg_logo_inline:
        return f"""
        <div class="logo-wrap">
          <div class="logo-svg">{svg_logo_inline}</div>
        </div>"""
    return """
        <div class="logo-wrap">
          <div class="logo-text-fallback">
            <span class="logo-gw">GAUS WOODS</span><br>
            <span class="logo-sub">MARCENARIA MINIMALISTA</span>
          </div>
        </div>"""

# ---------------------------------------------------------------------------
# Módulo-level cache de nomes de clientes — persiste entre chamadas no mesmo
# processo do helper, evitando N+1 GETs a /clientes/{id} ao listar cotações.
# ---------------------------------------------------------------------------
_CLIENTE_NAME_CACHE: dict = {}


def _append_log(path: str, msg: str):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(f"{datetime.now().isoformat(timespec='seconds')} | {msg}\n")
    except Exception:
        pass


def _write_perf(msg: str):
    _append_log(PERF_FILE, msg)


def _write_error(msg: str):
    _append_log(ERROR_FILE, msg)


def _write_debug(msg: str):
    """Grava log de debug no temp dir para diagnóstico."""
    try:
        with open(DEBUG_FILE, "a", encoding="utf-8") as f:
            import datetime
            f.write(f"\n[{datetime.datetime.now().strftime('%H:%M:%S')}] {msg}\n")
    except Exception:
        pass


def _extract_items(r, *keys):
    """BUG-A-FIX: Extrai lista de items de resposta em múltiplos formatos.

    Aceita:
      - lista direta:            [{...}, ...]
      - {"data": [...]}          (padrão esperado)
      - {"items": [...]}
      - {"results": [...]}
      - {"chapas": [...]}
      - {"fitas": [...]}
      - qualquer chave extra passada em *keys
    """
    if isinstance(r, list):
        return r
    if isinstance(r, dict):
        for k in ("data", "items", "results", "chapas", "fitas") + keys:
            if k in r and isinstance(r[k], list):
                return r[k]
        # último recurso: primeiro valor que for lista
        for v in r.values():
            if isinstance(v, list):
                return v
    return []


# ---------------------------------------------------------------------------
# helpers HTTP
# ---------------------------------------------------------------------------

def _auth_header() -> str:
    """Gera o valor do header Authorization para Basic Auth."""
    token = base64.b64encode(f"{API_USER}:{API_PASSWORD}".encode()).decode()
    return f"Basic {token}"


def _get(path: str, params: dict = None):
    url = API_BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    start = time.perf_counter()
    try:
        req  = urllib.request.Request(
            url,
            headers={"Accept": "application/json", "Authorization": _auth_header()},
        )
        resp = urllib.request.urlopen(req, timeout=10)
        raw  = resp.read().decode()
        elapsed_ms = (time.perf_counter() - start) * 1000
        _write_perf(f"HTTP method=GET url={url} status={resp.status} elapsed_ms={elapsed_ms:.2f} bytes={len(raw)}")
        # BUG-B-FIX: loga resposta bruta para debug (primeiros 400 chars)
        _write_debug(f"GET {url}\nStatus: {resp.status}\nBody: {raw[:400]}")
        return json.loads(raw)
    except Exception as e:
        elapsed_ms = (time.perf_counter() - start) * 1000
        _write_perf(f"HTTP method=GET url={url} status=ERROR elapsed_ms={elapsed_ms:.2f}")
        _write_error(f"HTTP GET url={url} elapsed_ms={elapsed_ms:.2f} error={repr(e)}\n{traceback.format_exc()}")
        _write_debug(f"GET {url}\nERROR: {e}")
        return None


def _put(path: str, body: dict):
    url  = API_BASE + path
    data = json.dumps(body).encode()
    start = time.perf_counter()
    try:
        req  = urllib.request.Request(
            url, data=data,
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Authorization": _auth_header(),
            },
            method="PUT"
        )
        resp = urllib.request.urlopen(req, timeout=15)
        raw = resp.read().decode()
        elapsed_ms = (time.perf_counter() - start) * 1000
        _write_perf(f"HTTP method=PUT url={url} status={resp.status} elapsed_ms={elapsed_ms:.2f} bytes={len(raw)}")
        return json.loads(raw)
    except Exception as e:
        elapsed_ms = (time.perf_counter() - start) * 1000
        _write_perf(f"HTTP method=PUT url={url} status=ERROR elapsed_ms={elapsed_ms:.2f}")
        _write_error(f"HTTP PUT url={url} elapsed_ms={elapsed_ms:.2f} error={repr(e)}\n{traceback.format_exc()}")
        _write_debug(f"PUT {url}\nERROR: {e}")
        return None


def _post(path: str, body: dict):
    url  = API_BASE + path
    data = json.dumps(body).encode()
    start = time.perf_counter()
    try:
        req  = urllib.request.Request(
            url, data=data,
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Authorization": _auth_header(),
            },
            method="POST"
        )
        resp = urllib.request.urlopen(req, timeout=15)
        raw = resp.read().decode()
        elapsed_ms = (time.perf_counter() - start) * 1000
        _write_perf(f"HTTP method=POST url={url} status={resp.status} elapsed_ms={elapsed_ms:.2f} bytes={len(raw)}")
        return json.loads(raw)
    except Exception as e:
        elapsed_ms = (time.perf_counter() - start) * 1000
        _write_perf(f"HTTP method=POST url={url} status=ERROR elapsed_ms={elapsed_ms:.2f}")
        _write_error(f"HTTP POST url={url} elapsed_ms={elapsed_ms:.2f} error={repr(e)}\n{traceback.format_exc()}")
        _write_debug(f"POST {url}\nERROR: {e}")
        return None


# ---------------------------------------------------------------------------
# leitura do arquivo de comando
# ---------------------------------------------------------------------------

def read_cmd():
    if not os.path.exists(CMD_FILE):
        return None, []
    # MAXScript escreve em Windows-1252 — tenta UTF-8 primeiro, cai para cp1252
    try:
        with open(CMD_FILE, "r", encoding="utf-8") as f:
            lines = [l.rstrip("\n") for l in f.readlines()]
    except UnicodeDecodeError:
        with open(CMD_FILE, "r", encoding="cp1252") as f:
            lines = [l.rstrip("\n") for l in f.readlines()]
    if not lines:
        return None, []
    return lines[0].strip(), lines[1:]


def write_result(lines: list):
    global LAST_RESULT_STATUS
    LAST_RESULT_STATUS = str(lines[0]) if lines else "EMPTY"
    if LAST_RESULT_STATUS != "OK":
        _write_error(f"RESULT status={LAST_RESULT_STATUS} lines={lines!r}")
    # Escreve em cp1252 (Windows ANSI) para compatibilidade com openFile "rt" do MAXScript.
    # MAXScript 2022+ lê UTF-8, mas versões anteriores lêem como ANSI.
    # Caracteres fora do cp1252 são substituídos por '?' em vez de gerar erro.
    with open(RESULT_FILE, "w", encoding="cp1252", errors="replace") as f:
        for l in lines:
            f.write(str(l) + "\n")


# ---------------------------------------------------------------------------
# helpers de ordenação e cache
# ---------------------------------------------------------------------------

def _sort_by_relevance_price(
    items: list,
    query: str,
    nome_key: str = "nome",
    price_key: str = "valor",
) -> list:
    """
    Ordena resultados de busca por:
      0 — nome começa com a query  (mais relevante)
      1 — nome contém a query      (média relevância)
      2 — demais                   (menor relevância)
    Dentro de cada tier, ordena por preço crescente.
    Sem query: ordena só por preço.
    """
    q = (query or "").strip().lower()

    def rank(item):
        name  = (item.get(nome_key, "") or "").lower()
        price = float(item.get(price_key, 0) or 0)
        if not q:
            return (0, price)
        if name.startswith(q):
            return (0, price)
        if q in name:
            return (1, price)
        return (2, price)

    return sorted(items, key=rank)


def _get_cli_nome_cached(cli_id) -> str:
    """GET /clientes/{id} com cache módulo-level para evitar N+1."""
    if not cli_id:
        return ""
    try:
        cid = int(cli_id)
    except Exception:
        return ""
    if cid in _CLIENTE_NAME_CACHE:
        return _CLIENTE_NAME_CACHE[cid]
    rc = _get(f"/clientes/{cid}")
    nome = rc.get("nome", "") if rc and "id" in rc else ""
    _CLIENTE_NAME_CACHE[cid] = nome
    return nome


# ---------------------------------------------------------------------------
# handlers
# ---------------------------------------------------------------------------

def handle_health_check():
    r = _get("/health")
    if r and r.get("status") == "ok":
        write_result(["OK", r.get("version", "?")])
    else:
        write_result(["FAIL", "API indisponível"])


def handle_search_chapas(params_raw: list):
    params = {}
    for p in params_raw:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.strip()] = v.strip()

    page      = params.get("page", "1")
    limit_req = int(params.get("limit", "30"))
    api_params = {"limit": str(limit_req), "page": page}
    if "nome" in params and params["nome"]:
        api_params["nome"] = params["nome"]
    if "espessura_min" in params:  api_params["espessura_min"] = params["espessura_min"]
    if "espessura_max" in params:  api_params["espessura_max"] = params["espessura_max"]
    if "fornecedor" in params:     api_params["fornecedor"]    = params["fornecedor"]
    if "subcategoria" in params and params["subcategoria"]:
        api_params["subcategoria"] = params["subcategoria"]
        _write_debug(f"subcategoria enviada: '{params['subcategoria']}'")

    # Filtrar apenas chapas com preço real (valor > 0)
    # Sem esse filtro, ~68% dos resultados têm valor=0 e poluem a grid
    api_params["valor_min"] = "0.01"

    r = _get("/chapas", api_params)
    if r is None:
        write_result(["FAIL", "Erro na busca (sem resposta da API)"]); return

    # BUG-A-FIX: suporta múltiplos formatos de resposta
    items = _extract_items(r, "chapas")
    total_api = r.get("total", len(items)) if isinstance(r, dict) else len(items)
    # Ordena: prefixo exato → contém → outros; dentro de cada tier por preço crescente
    items = _sort_by_relevance_price(items, params.get("nome", ""), "nome", "valor")
    _write_debug(f"search_chapas params={api_params} → {len(items)} items (total API: {total_api})")
    # Linha 2: total no banco (para exibir "mostrando X de Y" no MAXScript)
    lines = ["OK", str(total_api)]
    for it in items:
        lines.append("|".join(str(x or "") for x in [
            it.get("id", ""),
            it.get("nome", ""),
            it.get("subcategoria", ""),
            it.get("marca", ""),
            it.get("largura_mm", ""),
            it.get("comprimento_mm", ""),
            it.get("espessura_mm", ""),
            it.get("acabamento", ""),
            it.get("valor", ""),
            it.get("valor_m2", ""),
            it.get("fornecedor", ""),
        ]))
    write_result(lines)


def handle_search_fitas(params_raw: list):
    params = {}
    for p in params_raw:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.strip()] = v.strip()

    page      = params.get("page", "1")
    limit_req = int(params.get("limit", "20"))
    # Busca mais do que o limite para compensar o filtro local por valor_m_linear
    api_params = {"limit": str(min(limit_req * 5, 200)), "page": page}
    if "nome" in params and params["nome"]:
        api_params["nome"] = params["nome"]

    # Filtrar apenas rolos reais (rolo_min=1m) — exclui acessórios como aplicadores
    api_params["rolo_min"] = "1"
    api_params["valor_min"] = "0.01"

    r = _get("/fitas", api_params)
    if r is None:
        write_result(["FAIL", "Erro na busca (sem resposta da API)"]); return

    # BUG-A-FIX: suporta múltiplos formatos de resposta
    all_items = _extract_items(r, "fitas")

    # Filtra em Python: só fitas com valor_m_linear preenchido (dados completos)
    items = [it for it in all_items if it.get("valor_m_linear") and it["valor_m_linear"] > 0]

    # Se o filtro for muito restrito, cai de volta pra todos com rolo
    if len(items) == 0:
        items = [it for it in all_items if it.get("valor") and it["valor"] > 0]

    # Ordena: relevância do nome + menor preço/m
    items = _sort_by_relevance_price(items, params.get("nome", ""), "nome", "valor_m_linear")

    # Limita à página pedida
    items = items[:limit_req]

    _write_debug(f"search_fitas params={api_params} → {len(all_items)} brutos, {len(items)} filtrados")
    lines = ["OK", str(len(items))]
    for it in items:
        lines.append("|".join(str(x or "") for x in [
            it.get("id", ""),
            it.get("nome", ""),
            it.get("marca", ""),
            it.get("tamanho_rolo_m", ""),
            it.get("valor", ""),
            it.get("valor_m_linear", ""),
            it.get("fornecedor", ""),
        ]))
    write_result(lines)


def handle_search_ferragens(params_raw: list):
    """
    GET /ferragens com filtro por nome, ordenado por relevância + menor valor.
    Suporta paginação (page, limit).
    Resultado: OK | total | id|nome|marca|valor|fornecedor  (1 por item)
    """
    params = {}
    for p in params_raw:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.strip()] = v.strip()

    api_params = {
        "limit":     params.get("limit", "20"),
        "page":      params.get("page",  "1"),
        "valor_min": "0.01",
    }
    if "nome" in params and params["nome"]:
        api_params["nome"] = params["nome"]

    r = _get("/ferragens", api_params)
    if r is None:
        write_result(["FAIL", "Erro na busca de ferragens (sem resposta da API)"]); return

    items     = _extract_items(r, "ferragens")
    total_api = r.get("total", len(items)) if isinstance(r, dict) else len(items)

    # Ordena: relevância do nome → menor preço
    items = _sort_by_relevance_price(items, params.get("nome", ""), "nome", "valor")

    _write_debug(f"search_ferragens params={api_params} → {len(items)} items (total: {total_api})")
    lines = ["OK", str(total_api)]
    for it in items:
        lines.append("|".join(str(x or "") for x in [
            it.get("id",         ""),
            it.get("nome",       ""),
            it.get("marca",      ""),
            it.get("valor",      ""),
            it.get("fornecedor", ""),
        ]))
    write_result(lines)


def handle_search_clientes(params_raw: list):
    params = {}
    for p in params_raw:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.strip()] = v.strip()

    api_params = {"limit": params.get("limit", "50")}
    if "nome" in params and params["nome"]:
        api_params["nome"] = params["nome"]
    if "documento" in params and params["documento"]:
        api_params["documento"] = params["documento"]

    r = _get("/clientes", api_params)
    if r is None:
        write_result(["FAIL", "Erro na busca de clientes"]); return

    items = _extract_items(r, "clientes")
    total = r.get("total", len(items)) if isinstance(r, dict) else len(items)
    _write_debug(f"search_clientes params={api_params} → {len(items)} clientes")
    lines = ["OK", str(total)]
    for it in items:
        lines.append("|".join(str(x or "") for x in [
            it.get("id", ""),
            it.get("nome", ""),
            it.get("documento", ""),
            it.get("telefone", ""),
            it.get("email", ""),
            it.get("endereco", ""),
            it.get("cidade", ""),
            it.get("estado", ""),
            it.get("observacoes", ""),
        ]))
    write_result(lines)


def _read_client_file() -> dict | None:
    """Lê cnc_cliente_data.txt escrito pelo MAXScript (cp1252)."""
    if not os.path.exists(CLIENT_FILE):
        return None
    try:
        with open(CLIENT_FILE, "r", encoding="utf-8") as f:
            raw = f.read()
    except UnicodeDecodeError:
        with open(CLIENT_FILE, "r", encoding="cp1252") as f:
            raw = f.read()
    try:
        return json.loads(raw)
    except Exception as e:
        _write_debug(f"JSON invalido em CLIENT_FILE: {e}")
        return None


def handle_create_cliente():
    payload = _read_client_file()
    if payload is None:
        write_result(["FAIL", "Arquivo de dados do cliente nao encontrado ou invalido"]); return

    r = _post("/clientes", payload)
    if not r or "id" not in r:
        write_result(["FAIL", "Erro ao criar cliente na API"]); return
    write_result(["OK", str(r["id"]), r.get("nome", "")])


def handle_update_cliente(params_raw: list):
    cliente_id = ""
    for p in params_raw:
        if p.startswith("id="):
            cliente_id = p[3:]
    if not cliente_id:
        write_result(["FAIL", "ID do cliente nao informado"]); return

    payload = _read_client_file()
    if payload is None:
        write_result(["FAIL", "Arquivo de dados do cliente nao encontrado ou invalido"]); return

    r = _put(f"/clientes/{cliente_id}", payload)
    if not r or "id" not in r:
        write_result(["FAIL", "Erro ao atualizar cliente na API"]); return
    write_result(["OK", str(r["id"]), r.get("nome", "")])


def _find_python_with_uvicorn(dados_dir: str) -> str:
    """
    Retorna o executável Python que consegue importar uvicorn.
    Testa candidatos em ordem; exclui o Python embutido do 3ds Max
    (que nunca tem uvicorn instalado).
    """
    import shutil

    # Candidatos em ordem de preferência
    candidates = []

    # py.exe (Python Launcher do Windows) → seleciona a versão certa automaticamente
    py_launcher = shutil.which("py")
    if py_launcher:
        candidates.append(py_launcher)

    # python3 / python explícitos no PATH
    for name in ("python3", "python"):
        found = shutil.which(name)
        if found and found not in candidates:
            candidates.append(found)

    _write_debug(f"_find_python_with_uvicorn: candidatos={candidates}")

    for exe in candidates:
        try:
            r = subprocess.run(
                [exe, "-c", "import uvicorn; print('ok')"],
                capture_output=True, text=True, timeout=8,
                cwd=dados_dir,
            )
            if r.stdout.strip() == "ok":
                _write_debug(f"  -> uvicorn ok em: {exe}")
                return exe
            else:
                _write_debug(f"  -> sem uvicorn em {exe}: stdout={r.stdout!r} stderr={r.stderr[:120]!r}")
        except Exception as e:
            _write_debug(f"  -> erro testando {exe}: {e}")

    # Fallback: sys.executable (embutido) — provavelmente vai falhar, mas melhor que nada
    _write_debug(f"  -> fallback sys.executable: {sys.executable}")
    return sys.executable


def handle_start_api(params_raw: list):
    import time

    script_dir = ""
    for p in params_raw:
        if p.startswith("script_dir="):
            script_dir = p[len("script_dir="):]

    # DADOS/ está DENTRO de script_dir (MaxScript/), não um nível acima
    dados_dir = os.path.normpath(os.path.join(script_dir, "DADOS"))
    run_api   = os.path.join(dados_dir, "run_api.py")

    _write_debug(f"start_api: dados_dir={dados_dir!r}  run_api={run_api!r}")

    if not os.path.exists(run_api):
        write_result(["FAIL", f"run_api.py nao encontrado: {run_api}"]); return

    # Encontra o Python que tem uvicorn (ignora o Python embutido do 3ds Max)
    python_exe = _find_python_with_uvicorn(dados_dir)
    _write_debug(f"start_api: usando python_exe={python_exe!r}")

    try:
        flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        # cwd=dados_dir é obrigatório: uvicorn importa "api.main:app" relativo ao cwd
        proc = subprocess.Popen(
            [python_exe, run_api],
            creationflags=flags,
            cwd=dados_dir,
        )
        _write_debug(f"start_api: servidor iniciado pid={proc.pid}, aguardando 6s...")
        time.sleep(6)   # aguarda uvicorn subir
        r = _get("/health")
        if r and r.get("status") == "ok":
            write_result(["OK", "API iniciada"])
        else:
            write_result(["FAIL", "API nao respondeu apos inicializacao (verifique PostgreSQL)"])
    except Exception as e:
        _write_debug(f"start_api exception: {e}")
        write_result(["FAIL", str(e)])


def handle_get_cliente(params_raw: list):
    """GET /clientes/{id} — retorna campos do cliente em linhas."""
    cliente_id = ""
    for p in params_raw:
        if p.startswith("id="):
            cliente_id = p[3:]
    if not cliente_id:
        write_result(["FAIL", "ID do cliente nao informado"]); return
    r = _get(f"/clientes/{cliente_id}")
    if not r or "id" not in r:
        write_result(["FAIL", f"Cliente {cliente_id} nao encontrado"]); return
    write_result([
        "OK",
        r.get("nome", ""),
        r.get("documento", "") or "",
        r.get("telefone", "") or "",
        r.get("email", "") or "",
        r.get("cidade", "") or "",
        r.get("estado", "") or "",
    ])


def handle_search_cotacoes(params_raw: list):
    """
    GET /cotacoes (lista completa) com filtro local por texto e data.
    Para cada cotação com cliente_id, busca o nome do cliente.
    Resultado: OK | count | id|data|cliente_nome|nome_projeto|total_geral|desconto_global
    """
    params = {}
    for p in params_raw:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.strip()] = v.strip()

    busca      = params.get("busca", "").strip().lower()
    data_ini   = params.get("data_ini", "").strip()
    data_fim   = params.get("data_fim", "").strip()
    limit      = min(int(params.get("limit", "100")), 100)
    cliente_id = 0
    try:
        cliente_id = int(params.get("cliente_id", "0") or "0")
    except Exception:
        cliente_id = 0

    if cliente_id > 0:
        r = _get(f"/cotacoes/cliente/{cliente_id}", {"page": "1", "limit": str(limit)})
        if r is None:
            r = _get("/cotacoes", {"page": "1", "limit": str(limit)})
    else:
        r = _get("/cotacoes", {"page": "1", "limit": str(limit)})
    if r is None:
        write_result(["FAIL", "Erro ao buscar cotacoes"]); return

    items = _extract_items(r, "cotacoes")
    _write_debug(f"search_cotacoes: {len(items)} itens brutos, busca={busca!r}")

    lines = ["OK"]
    count = 0
    for it in items:
        cid       = it.get("cliente_id") or ""
        # Usa cache módulo-level: evita N+1 entre chamadas sucessivas
        # Usa nome_cliente incluído via JOIN no endpoint — sem request extra.
        # Fallback para cache/GET apenas se a API não retornou o campo (compatibilidade).
        cli_nome  = it.get("nome_cliente") or _get_cli_nome_cached(cid)
        proj      = it.get("nome_projeto", "") or ""
        criado_em = str(it.get("criado_em", ""))[:10]
        total     = float(it.get("total_geral", 0) or 0)
        desc      = float(it.get("desconto_global", 0) or 0)
        cot_id    = it.get("id", 0)

        # Filtro por cliente_id (seleção via modal) — prioritário sobre texto
        if cliente_id > 0:
            try:
                if int(cid or 0) != cliente_id:
                    continue
            except Exception:
                continue
        # Fallback: filtro texto livre (busca em nome_projeto e nome do cliente)
        elif busca:
            haystack = (proj + " " + cli_nome).lower()
            if busca not in haystack:
                continue

        # Filtro de data (formato YYYY-MM-DD ou DD/MM/YYYY)
        if data_ini or data_fim:
            # Normaliza criado_em para YYYY-MM-DD
            data_cot = criado_em[:10]
            if data_ini:
                di = data_ini.replace("/", "-")
                if len(di) == 10 and di[2] == "-":  # DD-MM-YYYY
                    di = f"{di[6:]}-{di[3:5]}-{di[:2]}"
                if data_cot < di:
                    continue
            if data_fim:
                df = data_fim.replace("/", "-")
                if len(df) == 10 and df[2] == "-":
                    df = f"{df[6:]}-{df[3:5]}-{df[:2]}"
                if data_cot > df:
                    continue

        lines.append("|".join(str(x) for x in [
            cot_id, criado_em, cli_nome, proj,
            f"{total:.2f}", f"{desc:.2f}"
        ]))
        count += 1

    lines.insert(1, str(count))
    write_result(lines)


def handle_get_cotacao(params_raw: list):
    """
    GET /cotacoes/{id} — retorna campos escalares da cotação.
    Resultado (indices 1-based):
      [1]  cliente_id
      [2]  nome_projeto
      [3]  previsao_entrega
      [4]  desconto_global
      [5]  total_chapas
      [6]  total_fitas
      [7]  total_outros
      [8]  total_geral
      [9]  observacoes
      [10] aproveitamento_pct
      [11] custo_efetivo_geral   (CA legacy — o que se paga, sem MO)
      [12] custo_efetivo_chapas
      [13] custo_efetivo_fitas
      [14] custo_efetivo_outros
      [15] desperdicio_pct
      [16] custo_produto_geral   (CMC legacy — insumos consumidos)
      [17] custo_produto_chapas
      [18] custo_produto_fitas
      [19] custo_produto_outros
      [20] mao_obra
      [21] mao_obra_manual       (true/false)
      --- modelo CMC+Markup v9 ---
      [22] custo_aquisicao_total    (CA v9)
      [23] custo_material_consumido (CMC v9)
      [24] custo_operacional_base   (COB v9)
      [25] margem_lucro_pct         (% por dentro do preco — markup divisor v10)
      [26] preco_venda_final        (PV apos desconto)
      --- modelo v10 (imposto/comissao por dentro do preco) ---
      [27] imposto_pct
      [28] comissao_pct
    """
    cotacao_id = ""
    for p in params_raw:
        if p.startswith("id="):
            cotacao_id = p[3:]
    if not cotacao_id:
        write_result(["FAIL", "ID da cotacao nao informado"]); return
    r = _get(f"/cotacoes/{cotacao_id}")
    if not r or "id" not in r:
        write_result(["FAIL", f"Cotacao {cotacao_id} nao encontrada"]); return
    write_result([
        "OK",
        str(r.get("cliente_id") or 0),                          # [1]
        r.get("nome_projeto", "") or "",                         # [2]
        r.get("previsao_entrega", "") or "",                     # [3]
        str(r.get("desconto_global", 0) or 0),                  # [4]
        str(r.get("total_chapas", 0) or 0),                     # [5]
        str(r.get("total_fitas", 0) or 0),                      # [6]
        str(r.get("total_outros", 0) or 0),                     # [7]
        str(r.get("total_geral", 0) or 0),                      # [8]
        (r.get("observacoes", "") or "").replace("\n", " "),    # [9]
        str(r.get("aproveitamento_pct", 0) or 0),               # [10]
        str(r.get("custo_efetivo_geral", 0) or 0),              # [11]
        str(r.get("custo_efetivo_chapas", 0) or 0),             # [12]
        str(r.get("custo_efetivo_fitas", 0) or 0),              # [13]
        str(r.get("custo_efetivo_outros", 0) or 0),             # [14]
        str(r.get("desperdicio_pct", 0) or 0),                  # [15]
        str(r.get("custo_produto_geral", 0) or 0),              # [16]
        str(r.get("custo_produto_chapas", 0) or 0),             # [17]
        str(r.get("custo_produto_fitas", 0) or 0),              # [18]
        str(r.get("custo_produto_outros", 0) or 0),             # [19]
        str(r.get("mao_obra", 0) or 0),                         # [20]
        "true" if r.get("mao_obra_manual", False) else "false", # [21]
        str(r.get("custo_aquisicao_total",    0) or 0),         # [22]
        str(r.get("custo_material_consumido", 0) or 0),         # [23]
        str(r.get("custo_operacional_base",   0) or 0),         # [24]
        str(r.get("margem_lucro_pct",         0) or 0),         # [25]
        str(r.get("preco_venda_final",        0) or 0),         # [26]
        str(r.get("imposto_pct",              0) or 0),         # [27]
        str(r.get("comissao_pct",             0) or 0),         # [28]
    ])


def handle_update_desconto_cotacao(params_raw: list):
    """PUT /cotacoes/{id}/desconto — atualiza o desconto global."""
    cotacao_id = ""
    desconto   = ""
    for p in params_raw:
        if p.startswith("id="):
            cotacao_id = p[3:]
        elif p.startswith("desconto="):
            desconto = p[9:]
    if not cotacao_id or not desconto:
        write_result(["FAIL", "id e desconto sao obrigatorios"]); return
    try:
        desc_val = float(desconto)
    except ValueError:
        write_result(["FAIL", "Desconto invalido"]); return
    r = _put(f"/cotacoes/{cotacao_id}/desconto", {"desconto_global": desc_val})
    if not r or "id" not in r:
        write_result(["FAIL", "Erro ao atualizar desconto"]); return
    write_result(["OK", str(r["id"]), f"desconto={r.get('desconto_global', desc_val)}"])


def handle_get_cotacao_items(params_raw: list):
    """
    GET /cotacoes/{id} e devolve os itens em linhas pipe-delimited.

    Formato de saída:
      OK
      <n_chapas>
      esp_mm|produto|quantidade|valor_unit|subtotal         (1 por chapa)
      <n_fitas>
      produto|metros_total|valor_m|subtotal                 (1 por fita)
      ferragem|cola|mao_obra|frete                          (1 linha outros)
      <n_ferragens>
      id|nome|valor_unit|fornecedor|qtd|subtotal            (1 por ferragem)
    """
    cotacao_id = ""
    for p in params_raw:
        if p.startswith("id="):
            cotacao_id = p[3:]
    if not cotacao_id:
        write_result(["FAIL", "ID da cotacao nao informado"]); return

    r = _get(f"/cotacoes/{cotacao_id}")
    if not r or "id" not in r:
        write_result(["FAIL", f"Cotacao {cotacao_id} nao encontrada"]); return

    chapas    = r.get("chapas")    or []
    fitas     = r.get("fitas")     or []
    outros    = r.get("outros")    or {}
    ferragens = r.get("ferragens") or []

    lines = ["OK"]

    # Chapas
    lines.append(str(len(chapas)))
    for c in chapas:
        lines.append("|".join(str(x) for x in [
            c.get("espessura_mm", ""),
            c.get("produto", ""),
            c.get("quantidade", ""),
            c.get("valor_unit", ""),
            c.get("subtotal", ""),
        ]))

    # Fitas
    lines.append(str(len(fitas)))
    for f in fitas:
        lines.append("|".join(str(x) for x in [
            f.get("produto", ""),
            f.get("metros_total", ""),
            f.get("valor_m", ""),
            f.get("subtotal", ""),
        ]))

    # Outros (sempre 1 linha)
    lines.append("|".join(str(outros.get(k, 0)) for k in ["ferragem", "cola", "mao_obra", "frete"]))

    # Ferragens
    lines.append(str(len(ferragens)))
    for fe in ferragens:
        lines.append("|".join(str(x) for x in [
            fe.get("id", 0),
            fe.get("nome", ""),
            fe.get("valor_unit", 0),
            fe.get("fornecedor", ""),
            fe.get("qtd", 1),
            fe.get("subtotal", 0),
        ]))

    # Pecas planejadas (do plano de corte, salvas em pecas_json)
    pecas_raw = r.get("pecas_json") or "[]"
    try:
        pecas_list = json.loads(pecas_raw) if isinstance(pecas_raw, str) else (pecas_raw or [])
        if not isinstance(pecas_list, list):
            pecas_list = []
    except Exception:
        pecas_list = []
    lines.append(str(len(pecas_list)))
    for p in pecas_list:
        lines.append("|".join(str(x) for x in [
            p.get("nome", ""),
            p.get("comp_mm", 0),
            p.get("larg_mm", 0),
            p.get("esp_mm", 0),
            p.get("qtd", 1),
            p.get("area_m2", 0),
            p.get("fita_m", 0),
            p.get("preco_m2", 0),
            p.get("custo_unit", 0),
            p.get("custo_total", 0),
            1 if p.get("fita_c1", False) else 0,   # [11]
            1 if p.get("fita_c2", False) else 0,   # [12]
            1 if p.get("fita_l1", False) else 0,   # [13]
            1 if p.get("fita_l2", False) else 0,   # [14]
        ]))

    write_result(lines)


def handle_update_cotacao_full():
    """
    PUT /cotacoes/{id} — edição completa (lê cnc_cotacao_update.txt).
    Suporta chapas, fitas, ferragens, outros, custo_efetivo_*, proj, entrega, obs, desconto.
    Após o PUT faz UPDATE direto no DB para garantir persistência dos campos novos.
    """
    update_file = os.path.join(tempfile.gettempdir(), "cnc_cotacao_update.txt")
    if not os.path.exists(update_file):
        write_result(["FAIL", "Arquivo de edicao nao encontrado"]); return

    try:
        with open(update_file, "r", encoding="utf-8") as f:
            raw = f.read()
    except UnicodeDecodeError:
        with open(update_file, "r", encoding="cp1252") as f:
            raw = f.read()

    try:
        data = json.loads(raw)
    except Exception as e:
        write_result(["FAIL", f"JSON invalido: {e}"]); return

    cotacao_id = data.pop("cotacao_id", None)
    if not cotacao_id:
        write_result(["FAIL", "cotacao_id nao informado"]); return

    # Normaliza: pecas_json pode vir como lista
    if "pecas_json" in data and isinstance(data["pecas_json"], list):
        data["pecas_json"] = json.dumps(data["pecas_json"], ensure_ascii=False)

    r = _put(f"/cotacoes/{cotacao_id}", data)
    if not r or "id" not in r:
        write_result(["FAIL", f"Erro ao atualizar cotacao {cotacao_id}"]); return

    # Patch direto para campos que o endpoint pode não cobrir ainda
    try:
        import psycopg2
        conn = psycopg2.connect(
            "host=2.25.180.127 port=5432 dbname=postgres user=postgres password=hunter123"
        )
        conn.autocommit = False
        cur = conn.cursor()
        patch = {}
        # Custo efetivo — sempre atualiza quando presente
        for col in ["custo_efetivo_chapas","custo_efetivo_fitas","custo_efetivo_outros","custo_efetivo_geral"]:
            if col in data:
                patch[col] = float(data[col] or 0)
        # Custo produto — atualiza sempre (inclui 0 para refletir remoções de itens)
        # Sem a restricao > 0 do codigo anterior, que impedia zerar apos remover ferragens
        for col in ["custo_produto_fitas","custo_produto_outros","custo_produto_geral"]:
            if col in data:
                patch[col] = float(data[col] or 0)
        # custo_produto_chapas: so atualiza se vier positivo (nao muda na edicao de fitas/outros)
        if "custo_produto_chapas" in data and float(data["custo_produto_chapas"] or 0) > 0:
            patch["custo_produto_chapas"] = float(data["custo_produto_chapas"])
        # mao_obra — atualiza sempre quando presente (pode ser zerado)
        if "mao_obra" in data:
            patch["mao_obra"] = float(data["mao_obra"] or 0)
        if "mao_obra_manual" in data:
            patch["mao_obra_manual"] = bool(data["mao_obra_manual"])
        # Modelo CMC+Markup v9 — recalculados pelo MaxScript na edicao
        # Todos os campos sao atualizados inclusive quando zerados (ex: frete removido)
        for col in ["custo_aquisicao_total", "custo_material_consumido",
                    "custo_operacional_base", "margem_lucro_pct", "preco_venda_final",
                    "imposto_pct", "comissao_pct"]:
            if col in data:
                patch[col] = float(data[col] or 0)
        if "ferragens" in data:
            ferr_raw = data["ferragens"]
            patch["ferragens_json"] = json.dumps(ferr_raw, ensure_ascii=False) \
                if isinstance(ferr_raw, list) else ferr_raw
        if "pecas_json" in data:
            patch["pecas_json"] = data["pecas_json"]
        if patch:
            sets = ", ".join(f"{k} = %s" for k in patch)
            vals = list(patch.values()) + [int(cotacao_id)]
            cur.execute(f"UPDATE cotacoes SET {sets} WHERE id = %s", vals)
            conn.commit()
    except Exception as e_db:
        _write_debug(f"handle_update_cotacao_full: DB patch falhou — {e_db}")
    finally:
        try: cur.close()
        except: pass
        try: conn.close()
        except: pass

    write_result(["OK", str(r["id"]), f"total={r.get('total_geral', 0)}"])


def handle_update_cotacao(params_raw: list):
    """
    PUT /cotacoes/{id} — atualiza projeto, obs, entrega, desconto, cliente.
    Parametros (um por linha): id=X  proj=X  entrega=X  obs=X  desconto=X  cliente_id=X
    """
    cotacao_id = ""
    payload    = {}
    for p in params_raw:
        if p.startswith("id="):
            cotacao_id = p[3:]
        elif p.startswith("proj="):
            payload["nome_projeto"] = p[5:]
        elif p.startswith("entrega="):
            payload["previsao_entrega"] = p[8:]
        elif p.startswith("obs="):
            payload["observacoes"] = p[4:]
        elif p.startswith("desconto="):
            try:    payload["desconto_global"] = float(p[9:])
            except: pass
        elif p.startswith("cliente_id="):
            try:    payload["cliente_id"] = int(p[11:])
            except: pass

    if not cotacao_id:
        write_result(["FAIL", "id obrigatorio"]); return
    if not payload:
        write_result(["FAIL", "nenhum campo para atualizar"]); return

    r = _put(f"/cotacoes/{cotacao_id}", payload)
    if not r or "id" not in r:
        write_result(["FAIL", "Erro ao atualizar cotacao"]); return
    write_result(["OK", str(r["id"]),
                  r.get("nome_projeto", "") or "",
                  str(r.get("desconto_global", 0))])


try:
    _api_path = os.path.join(os.path.dirname(__file__), "DADOS", "api")
    if _api_path not in sys.path:
        sys.path.insert(0, _api_path)
    from gauswoodsquote.pricing import pv_divisor as _pv_divisor, pv_com_desconto, abaixo_custo
except ImportError:
    def _pv_divisor(cob, margem_pct, imposto_pct=0.0, comissao_pct=0.0):
        if cob <= 0:
            return 0.0
        soma = min(margem_pct + imposto_pct + comissao_pct, 95.0)
        return cob / (1.0 - soma / 100.0)
    def pv_com_desconto(pv_bruto, desconto_pct):
        if pv_bruto <= 0 or desconto_pct <= 0:
            return pv_bruto
        return pv_bruto * (1.0 - desconto_pct / 100.0)
    def abaixo_custo(pv_final, cob, tolerancia=0.005):
        return pv_final < cob - tolerancia


def _pricing_from_row(r, cob_val, margem_pct, imposto_pct, comissao_pct, desc_pct):
    """Preco de venda bruto/final + flag abaixo_custo para uma cotacao.

    Preferencia: pricing_snapshot_json — congelado pela API (pricing_service)
    no momento da criacao/edicao da cotacao, e a fonte oficial do calculo
    monetario (PV nao deve ser recalculado com formulas que podem ter mudado
    desde entao). Fallback: recalcula via _pv_divisor/pv_com_desconto para
    cotacoes antigas sem snapshot.
    """
    raw = r.get("pricing_snapshot_json")
    if raw:
        try:
            snap = json.loads(raw) if isinstance(raw, str) else raw
            pv_bruto = float(snap.get("preco_venda_bruto", 0) or 0)
            if pv_bruto > 0:
                pv_final = float(snap.get("preco_venda_final", 0) or 0)
                abaixo   = bool(snap.get("abaixo_custo", False))
                return pv_bruto, pv_final, abaixo
        except Exception:
            pass
    pv_bruto = _pv_divisor(cob_val, margem_pct, imposto_pct, comissao_pct)
    pv_final = pv_com_desconto(pv_bruto, desc_pct) if pv_bruto > 0 else 0.0
    abaixo   = abaixo_custo(pv_final, cob_val) if cob_val > 0 else False
    return pv_bruto, pv_final, abaixo


def _html_analise_custo(cmc, cob, margem_pct, pv_final, ca, mo, custo_aq_legacy, custo_pr_legacy, brl,
                        desc_pct=0.0, imposto_pct=0.0, comissao_pct=0.0,
                        pv_bruto=None, pv_cliente=None):
    """Gera o bloco HTML de Análise de Custo para o modelo CMC + Markup divisor (v10).
    Fallback automático para cotações antigas (sem os campos v9/v10).

    - pv_bruto/pv_cliente: valores oficiais (de pricing_snapshot_json via
      _pricing_from_row); se nao informados, recalculados aqui a partir do
      COB e percentuais atuais.
    - COB = CMC + MO + custos diretos adicionais (ferragens, cola, frete).
      Quando há delta significativo, mostramos o breakdown para transparência.
    - desc_pct: desconto global da cotação, aplicado ao PV calculado.
    - ca: passado como soma dos itens exibidos (chapas+fitas+ferr+outros s/MO).
    """
    is_v9 = cmc > 0 or cob > 0

    if is_v9:
        if pv_bruto is None:
            pv_bruto = _pv_divisor(cob, margem_pct, imposto_pct, comissao_pct)
        if pv_cliente is None:
            pv_cliente = pv_bruto * (1 - desc_pct / 100) if desc_pct > 0 else pv_bruto

        # Breakdown do COB: delta entre COB e CMC+MO = custos diretos (ferragens, frete, cola…)
        custos_diretos = cob - cmc - mo
        cob_detail = ""
        if custos_diretos > 0.50:
            cob_detail = (
                f"<tr><td style='padding:1px 0 4px 14px;color:#666;font-size:10px'>"
                f"= CMC {brl(cmc)} + MO {brl(mo)} + Custos Diretos {brl(custos_diretos)}"
                f"</td><td></td></tr>"
            )

        # Linha de desconto (só aparece quando há desconto)
        desc_row = ""
        if desc_pct > 0:
            desc_row = (
                f"<tr><td style='padding:3px 0'>Desconto ({desc_pct:.1f}%):</td>"
                f"<td style='text-align:right'>- {brl(pv_bruto - pv_cliente)}</td></tr>"
            )
            label_pv = "Preço ao Cliente (c/ desconto)"
        else:
            label_pv = "Preço de Venda Final"

        rows = f"""
        <tr><td style="padding:3px 0">CMC — Material Consumido (c/ perda CNC):</td>
            <td style="text-align:right;font-weight:bold">{brl(cmc)}</td></tr>
        <tr><td style="padding:3px 0">Mão de Obra:</td>
            <td style="text-align:right">{brl(mo)}</td></tr>
        <tr style="background:#e8f5e9"><td style="padding:3px 0"><strong>COB — Custo Operacional Base:</strong></td>
            <td style="text-align:right;font-weight:bold">{brl(cob)}</td></tr>
        {cob_detail}
        <tr><td style="padding:3px 0">Margem {margem_pct:.1f}%{f" + Imposto {imposto_pct:.1f}%" if imposto_pct > 0 else ""}{f" + Comissão {comissao_pct:.1f}%" if comissao_pct > 0 else ""} (por dentro do preço):</td>
            <td style="text-align:right">+ {brl(pv_bruto - cob)}</td></tr>
        {desc_row}
        <tr style="background:#1a4e3c;color:#fff"><td style="padding:5px 3px"><strong>{label_pv}:</strong></td>
            <td style="text-align:right;font-weight:bold">{brl(pv_cliente)}</td></tr>
        <tr><td style="padding:3px 0;color:#666;font-size:10px">CA — Custo de Aquisição s/ MO (referência interna):</td>
            <td style="text-align:right;color:#666;font-size:10px">{brl(ca)}</td></tr>
        """
        title = "Análise de Custo — Modelo CMC + Markup"
    else:
        if custo_aq_legacy <= 0:
            return ""
        rows = f"""
        <tr><td style="padding:3px 0">Custo de Aquisição (chapas+fitas+cola+ferragens+frete, s/ MO):</td>
            <td style="text-align:right;font-weight:bold">{brl(custo_aq_legacy)}</td></tr>
        <tr><td style="padding:3px 0">Custo do Produto (material consumido):</td>
            <td style="text-align:right;font-weight:bold">{brl(custo_pr_legacy)}</td></tr>
        """ + (f"<tr style='background:#fff8e1'><td style='padding:3px 0'>Mão de Obra:</td><td style='text-align:right;font-weight:bold'>{brl(mo)}</td></tr>" if mo > 0 else "")
        title = "Análise de Custo"

    return f"""
<div style='margin-top:14px;padding:10px 16px;background:#f0f4f8;border-radius:4px;font-size:11px;'>
  <strong>{title}</strong>
  <table style="width:100%;margin-top:6px;border-collapse:collapse">
    {rows}
  </table>
</div>"""


def handle_export_cotacao_html(params_raw: list):
    """
    Gera arquivo HTML da cotação e abre no browser (usuário pode imprimir como PDF).
    Parametros: id=X
    """
    import webbrowser

    cotacao_id = ""
    for p in params_raw:
        if p.startswith("id="):
            cotacao_id = p[3:]
    if not cotacao_id:
        write_result(["FAIL", "ID da cotacao nao informado"]); return

    r = _get(f"/cotacoes/{cotacao_id}")
    if not r or "id" not in r:
        write_result(["FAIL", f"Cotacao {cotacao_id} nao encontrada"]); return

    # Dados do cliente
    cli_nome = "—"
    cli_id   = r.get("cliente_id") or 0
    if cli_id:
        cli = _get(f"/clientes/{cli_id}")
        if cli:
            cli_nome = cli.get("nome", "—")
            cidade   = cli.get("cidade", "") or ""
            uf       = cli.get("estado", "") or ""
            cli_loc  = f"{cidade}/{uf}" if cidade else "—"
            # FIX: detectar dados fictícios/placeholder e substituir por "—"
            def _limpa_contato(v):
                s = str(v or "").strip()
                if (not s or s == "—"
                        or "999999" in s
                        or s.upper() in ("TESTE@TESTE.COM","TESTE","N/A","NA","—")):
                    return "—"
                return s
            cli_tel  = _limpa_contato(cli.get("telefone"))
            cli_email= _limpa_contato(cli.get("email"))
        else:
            cli_loc = cli_tel = cli_email = "—"
    else:
        cli_loc = cli_tel = cli_email = "—"

    proj     = r.get("nome_projeto",    "—") or "—"
    entrega  = r.get("previsao_entrega","—") or "—"
    obs      = (r.get("observacoes",    "")  or "").replace("\n", "<br>")
    desc_pct = float(r.get("desconto_global", 0) or 0)
    tot_ch   = float(r.get("total_chapas",  0) or 0)
    tot_ft   = float(r.get("total_fitas",   0) or 0)
    tot_ou   = float(r.get("total_outros",  0) or 0)
    subtotal = tot_ch + tot_ft + tot_ou
    desc_val = subtotal * desc_pct / 100.0
    total    = subtotal - desc_val
    # FIX: DB armazena timestamp em UTC; Brasil = UTC-3.
    # Cortar [:10] devolve a data UTC que pode ser +1 dia em relação ao horário local.
    # Parsear timestamp completo e subtrair 3h antes de formatar.
    _data_raw = str(r.get("criado_em", ""))
    try:
        _ts = datetime.fromisoformat(
            _data_raw.replace("Z", "+00:00").replace(" ", "T")
        )
        # Remove tzinfo (naive) e aplica offset -3h (UTC→Brasil)
        _ts_local = _ts.replace(tzinfo=None) - timedelta(hours=3)
        data_cot  = _ts_local.strftime("%d/%m/%Y")
    except Exception:
        # Fallback: só a parte da data sem conversão
        data_cot = _data_raw[:10]
    aprov    = float(r.get("aproveitamento_pct", 0) or 0)

    chapas    = r.get("chapas")    or []
    fitas     = r.get("fitas")    or []
    outros    = r.get("outros")   or {}
    ferragens = r.get("ferragens") or []
    # v9: campos do modelo CMC+Markup (0 em cotacoes antigas)
    ca_total  = float(r.get("custo_aquisicao_total",    0) or 0)
    cmc_val   = float(r.get("custo_material_consumido", 0) or 0)
    cob_val   = float(r.get("custo_operacional_base",   0) or 0)
    margem_pct= float(r.get("margem_lucro_pct",         0) or 0)
    pv_final  = float(r.get("preco_venda_final",        0) or 0)
    imposto_pct  = float(r.get("imposto_pct",  0) or 0)
    comissao_pct = float(r.get("comissao_pct", 0) or 0)
    # PV v10 — usado no total-box e na análise de custo. Vem do snapshot
    # oficial (pricing_snapshot_json) quando disponível; senão recalculado.
    pv_bruto_v10, pv_final_v10, abaixo_custo_flag = _pricing_from_row(
        r, cob_val, margem_pct, imposto_pct, comissao_pct, desc_pct)
    # fallback para campos legacy quando ainda nao migrado
    custo_aq  = ca_total  if ca_total  > 0 else float(r.get("custo_efetivo_geral", 0) or 0)
    custo_pr  = cmc_val   if cmc_val   > 0 else float(r.get("custo_produto_geral",  0) or 0)
    # MO: preferir coluna dedicada; fallback para outros.mao_obra (cotacoes antigas)
    mao_obra_val = float(r.get("mao_obra", 0) or 0)
    if mao_obra_val == 0:
        mao_obra_val = float((r.get("outros") or {}).get("mao_obra", 0) or 0)

    # Parse pecas_json
    pecas_list = []
    try:
        raw_pj = r.get("pecas_json") or "[]"
        pecas_list = json.loads(raw_pj) if isinstance(raw_pj, str) else (raw_pj or [])
        if not isinstance(pecas_list, list):
            pecas_list = []
    except Exception:
        pecas_list = []

    def brl(v): return f"R$ {float(v):,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    logo_block = _brand_logo_block()

    # Linhas de chapas
    rows_ch = ""
    for c in chapas:
        esp_str = str(float(c.get('espessura_mm', 0) or 0)).rstrip('0').rstrip('.').replace('.', ',') + " mm"
        rows_ch += (
            f"<tr><td>{esp_str}</td>"
            f"<td>{c.get('produto','')}</td>"
            f"<td style='text-align:center'>{c.get('quantidade','')}</td>"
            f"<td style='text-align:right'>{brl(c.get('valor_unit',0))}</td>"
            f"<td style='text-align:right'>{brl(c.get('subtotal',0))}</td></tr>"
        )

    rows_ft = ""
    tot_ft_calc = 0.0
    for f in fitas:
        # FIX: recalcular subtotal da fita a partir de metros × valor_m
        # O subtotal armazenado no DB pode divergir por arredondamento da metragem interna.
        metros_ft = float(f.get('metros_total', 0) or 0)
        valor_m_ft = float(f.get('valor_m', 0) or 0)
        sub_ft = round(metros_ft * valor_m_ft, 2)
        tot_ft_calc += sub_ft
        rows_ft += (
            f"<tr><td colspan='2'>{f.get('produto','')}</td>"
            f"<td style='text-align:center'>{metros_ft:.1f} m</td>"
            f"<td style='text-align:right'>{brl(valor_m_ft)}/m</td>"
            f"<td style='text-align:right'>{brl(sub_ft)}</td></tr>"
        )
    # Usar total recalculado quando há itens; fallback para total do DB em cotações sem detalhe
    if fitas:
        tot_ft = tot_ft_calc

    # Outros custos diretos: apenas os itens exibidos na seção (cola + frete).
    # FIX: tot_ou = total_outros do DB inclui MO + ferragens + cola + frete (total de "outros" geral).
    # Calcular subtotal somente dos itens que aparecem na seção para evitar valor inflado.
    outros_rows = ""
    tot_outros_display = 0.0
    for k, label in [("cola","Cola/Fixadores"),("frete","Frete")]:
        v = float(outros.get(k, 0) or 0)
        if v > 0:
            outros_rows += (f"<tr><td colspan='4'>{label}</td>"
                           f"<td style='text-align:right'>{brl(v)}</td></tr>")
            tot_outros_display += v
    # MO como linha própria (custo interno de fabricação)
    mo_row = ""
    if mao_obra_val > 0:
        mo_manual = bool(r.get("mao_obra_manual", False))
        mo_label  = "Mão de Obra (manual)" if mo_manual else "Mão de Obra (estimada)"
        mo_row    = (f"<tr style='background:#fff8e1'><td colspan='4'>{mo_label}</td>"
                     f"<td style='text-align:right'>{brl(mao_obra_val)}</td></tr>")

    # Ferragens individuais
    rows_ferr = ""
    for fe in ferragens:
        rows_ferr += (
            f"<tr><td colspan='2'>{fe.get('nome','')}</td>"
            f"<td style='text-align:center'>{fe.get('qtd',1)}×</td>"
            f"<td style='text-align:right'>{brl(fe.get('valor_unit',0))}</td>"
            f"<td style='text-align:right'>{brl(fe.get('subtotal',0))}</td></tr>"
        )
    tot_ferr = sum(float(fe.get("subtotal", 0) or 0) for fe in ferragens)

    # CA display = soma de todos os itens exibidos sem MO (o que o leitor verificaria somando)
    ca_display = tot_ch + tot_ft + tot_ferr + tot_outros_display

    # Detectar acréscimo aplicado nas chapas (markup ou perda CNC embutida)
    chapas_nota = ""
    if chapas:
        _raw_sum = sum(float(c.get("quantidade", 1)) * float(c.get("valor_unit", 0)) for c in chapas)
        if _raw_sum > 0.5 and abs(tot_ch - _raw_sum) > 0.5:
            _markup_pct = round((tot_ch / _raw_sum - 1) * 100, 1)
            chapas_nota = (
                f"<p style='font-size:10px;color:#888;margin:-6px 0 8px'>"
                f"¹ Subtotais incluem acréscimo de {str(_markup_pct).replace('.', ',')}% "
                f"sobre o preço de tabela (perda CNC + markup comercial).</p>"
            )

    # Pecas planejadas
    rows_pecas = ""
    for p in pecas_list:
        dim = f"{int(p.get('comp_mm',0))}×{int(p.get('larg_mm',0))}×{int(p.get('esp_mm',0))} mm"
        rows_pecas += (
            f"<tr><td>{p.get('nome','')}</td>"
            f"<td>{dim}</td>"
            f"<td style='text-align:center'>{p.get('qtd',1)}</td>"
            f"<td style='text-align:right'>{float(p.get('area_m2',0)):.4f} m²</td>"
            f"<td style='text-align:right'>{brl(p.get('custo_unit',0))}</td>"
            f"<td style='text-align:right'>{brl(p.get('custo_total',0))}</td></tr>"
        )

    html = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Cotação #{cotacao_id}</title>
<style>
  body {{ font-family: Arial, sans-serif; font-size: 12px; margin: 20px; color: #222; }}
  h1   {{ font-size: 18px; color: #1a4e3c; margin-bottom: 4px; }}
  h2   {{ font-size: 14px; color: #1a4e3c; margin: 18px 0 6px; border-bottom: 1px solid #ccc; }}
  .report-header {{ display:flex; align-items:center; justify-content:space-between; gap:24px; margin-bottom:16px; border-bottom:2px solid #1a4e3c; padding-bottom:12px; }}
  .report-title {{ flex:1; text-align:right; }}
  .report-title h1 {{ margin:0 0 4px; }}
  .logo-wrap {{ flex-shrink:0; }}
  .logo-svg {{ width:92px; height:auto; display:block; }}
  .logo-svg svg {{ width:100%; height:auto; display:block; }}
  .logo-text-fallback {{ color:#1a4e3c; line-height:1.1; text-align:left; }}
  .logo-gw {{ font-size:18px; font-weight:bold; letter-spacing:2px; }}
  .logo-sub {{ font-size:8px; letter-spacing:1px; text-transform:uppercase; }}
  table  {{ width: 100%; border-collapse: collapse; margin-bottom: 10px; }}
  th   {{ background: #1a4e3c; color: #fff; padding: 5px 8px; text-align: left; }}
  td   {{ padding: 4px 8px; border-bottom: 1px solid #eee; }}
  tr:nth-child(even) td {{ background: #f5f5f5; }}
  .info-grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 4px 20px; margin-bottom: 10px; }}
  .lbl  {{ font-weight: bold; }}
  .total-box {{ background: #1a4e3c; color: #fff; padding: 10px 16px;
                font-size: 15px; font-weight: bold; text-align: right;
                border-radius: 4px; margin-top: 10px; }}
  .subtotal-row td {{ font-weight: bold; border-top: 2px solid #1a4e3c; }}
  @media print {{ body {{ margin: 10px; }} }}
</style>
</head>
<body>
<div class="report-header">
  {logo_block}
  <div class="report-title">
    <h1>Cotação #{cotacao_id} &nbsp;·&nbsp; {proj}</h1>
    <div style="color:#666">Emitida em: {data_cot} &nbsp;|&nbsp; Aproveitamento: {f"{aprov:.1f}".replace(".", ",")}%</div>
  </div>
</div>

<h2>Cliente</h2>
<div class="info-grid">
  <div><span class="lbl">Nome:</span> {cli_nome}</div>
  <div><span class="lbl">Localidade:</span> {cli_loc}</div>
  <div><span class="lbl">Telefone:</span> {cli_tel}</div>
  <div><span class="lbl">E-mail:</span> {cli_email}</div>
</div>

<h2>Projeto</h2>
<div class="info-grid">
  <div><span class="lbl">Projeto:</span> {proj}</div>
  <div><span class="lbl">Entrega:</span> {entrega}</div>
  <div style="grid-column:1/-1"><span class="lbl">Obs:</span> {obs}</div>
</div>

<h2>Chapas</h2>
<table>
  <tr><th>Espessura</th><th>Produto</th><th>Qtd</th><th>Valor Unit.</th><th>Subtotal</th></tr>
  {rows_ch}
  <tr class="subtotal-row"><td colspan="4">Subtotal Chapas</td><td style="text-align:right">{brl(tot_ch)}</td></tr>
</table>
{chapas_nota}

<h2>Fitas de Borda</h2>
<table>
  <tr><th colspan="2">Produto</th><th>Metragem</th><th>Valor/m</th><th>Subtotal</th></tr>
  {rows_ft}
  <tr class="subtotal-row"><td colspan="4">Subtotal Fitas</td><td style="text-align:right">{brl(tot_ft)}</td></tr>
</table>

{"<h2>Ferragens</h2><table><tr><th colspan='2'>Produto</th><th>Qtd</th><th>Valor Unit.</th><th>Subtotal</th></tr>" + rows_ferr + f"<tr class='subtotal-row'><td colspan='4'>Subtotal Ferragens</td><td style='text-align:right'>{brl(tot_ferr)}</td></tr></table>" if rows_ferr else ""}

<h2>Outros Custos (Aquisição)</h2>
<table>
  <tr><th colspan="4">Descrição</th><th>Valor</th></tr>
  {outros_rows}
  <tr class="subtotal-row"><td colspan="4">Subtotal Outros</td><td style="text-align:right">{brl(tot_outros_display)}</td></tr>
</table>

{"<h2>Mão de Obra</h2><table><tr><th colspan='4'>Descrição</th><th>Valor</th></tr>" + mo_row + "</table>" if mo_row else ""}

{"<h2>Peças Planejadas</h2><table><tr><th>Nome</th><th>L×A×P</th><th>Qtd</th><th>Área m²</th><th>Custo Unit.</th><th>Custo Total</th></tr>" + rows_pecas + "</table>" if rows_pecas else ""}

<div class="total-box">
  {(lambda: (
      # Modelo v10: PV do snapshot oficial (pricing_snapshot_json), nunca recalculado
      "PREÇO DE VENDA FINAL: " + brl(pv_final_v10)
      if desc_pct == 0 else
      "Preço bruto: " + brl(pv_bruto_v10) + "<br>"
      + "Desconto " + f"{desc_pct:.1f}%: -" + brl(pv_bruto_v10 - pv_final_v10) + "<br>"
      + "PREÇO AO CLIENTE: " + brl(pv_final_v10)
  ) if cob_val > 0 else (
      # Cotações antigas: usar subtotal itemizado
      ("Subtotal: " + brl(subtotal) + "<br>")
      + ("Desconto " + f"{desc_pct:.1f}%: -" + brl(desc_val) + "<br>" if desc_pct > 0 else "")
      + "TOTAL GERAL: " + brl(total)
  ))()}
</div>
{"<p style='color:#b00020;font-weight:bold;font-size:11px;margin-top:6px'>ATENÇÃO: o preço final está abaixo do custo operacional (COB).</p>" if abaixo_custo_flag else ""}

{_html_analise_custo(cmc_val, cob_val, margem_pct, pv_final, ca_display, mao_obra_val, custo_aq, custo_pr, brl, desc_pct=desc_pct, imposto_pct=imposto_pct, comissao_pct=comissao_pct, pv_bruto=pv_bruto_v10 if cob_val > 0 else None, pv_cliente=pv_final_v10 if cob_val > 0 else None)}

<p style="color:#999; font-size:10px; margin-top:20px">
  Gerado automaticamente pelo CNC Cut Plan Optimizer Gaus Woods · {datetime.now().strftime('%d/%m/%Y %H:%M')}
</p>
</body></html>"""

    out_path = os.path.join(TMP, f"cotacao_{cotacao_id}.html")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)

    try:
        webbrowser.open(f"file:///{out_path.replace(os.sep, '/')}")
    except Exception:
        pass

    write_result(["OK", out_path, f"total={brl(total)}"])


# ──────────────────────────────────────────────────────────────────────────────
def handle_export_proposta_cliente_html(params_raw: list):
    """
    Gera proposta comercial premium para o cliente, seguindo o Brandbook
    Gaus Woods v1.0:
      - Paleta: Grafite #1F211F | Madeira #4B2E1B | Carvalho #EFE3D1 |
                Areia #D4BEA2 | Marfim #F8F3EA
      - Tipografia: Montserrat (Google Fonts)
      - Logo GAUSWOOD.svg embarcado inline
      - Conteúdo gerado automaticamente a partir dos dados da cotação
    """
    import webbrowser, re

    cotacao_id = ""
    for p in params_raw:
        if p.startswith("id="):
            cotacao_id = p[3:]
    if not cotacao_id:
        write_result(["FAIL", "ID da cotacao nao informado"]); return

    r = _get(f"/cotacoes/{cotacao_id}")
    if not r or "id" not in r:
        write_result(["FAIL", f"Cotacao {cotacao_id} nao encontrada"]); return

    # ── Dados do cliente ────────────────────────────────────────────────────
    cli_nome = "—"; cli_loc = "—"; cli_tel = "—"; cli_email = "—"
    cli_id = r.get("cliente_id") or 0
    if cli_id:
        cli = _get(f"/clientes/{cli_id}")
        if cli:
            cli_nome  = cli.get("nome", "—") or "—"
            cidade    = cli.get("cidade", "") or ""
            uf        = cli.get("estado", "") or ""
            cli_loc   = f"{cidade}/{uf}" if cidade else "—"
            def _lc(v):
                s = str(v or "").strip()
                if not s or "999999" in s or s.upper() in ("TESTE@TESTE.COM","N/A","NA","—"):
                    return "—"
                return s
            cli_tel   = _lc(cli.get("telefone"))
            cli_email = _lc(cli.get("email"))

    # ── Dados da cotação ────────────────────────────────────────────────────
    proj         = (r.get("nome_projeto", "") or "").strip() or "Projeto"
    entrega      = r.get("previsao_entrega", "") or ""
    obs          = (r.get("observacoes", "") or "").strip()
    desc_pct     = float(r.get("desconto_global", 0) or 0)
    chapas       = r.get("chapas")    or []
    fitas        = r.get("fitas")     or []
    ferragens    = r.get("ferragens") or []
    outros       = r.get("outros")    or {}
    cob_val      = float(r.get("custo_operacional_base", 0) or 0)
    margem_pct   = float(r.get("margem_lucro_pct",       0) or 0)
    imposto_pct  = float(r.get("imposto_pct",  0) or 0)
    comissao_pct = float(r.get("comissao_pct", 0) or 0)
    mao_obra_val = float(r.get("mao_obra", 0) or 0)
    if mao_obra_val == 0:
        mao_obra_val = float((r.get("outros") or {}).get("mao_obra", 0) or 0)
    frete_val = float(outros.get("frete", 0) or 0)

    # ── Data (UTC-3) ────────────────────────────────────────────────────────
    _data_raw = str(r.get("criado_em", ""))
    try:
        _ts = datetime.fromisoformat(
            _data_raw.replace("Z", "+00:00").replace(" ", "T"))
        data_cot = (_ts.replace(tzinfo=None) - timedelta(hours=3)).strftime("%d/%m/%Y")
    except Exception:
        data_cot = _data_raw[:10]

    # ── Preço ───────────────────────────────────────────────────────────────
    def brl(v): return f"R$ {float(v):,.2f}".replace(",","X").replace(".",",").replace("X",".")
    if cob_val > 0 and margem_pct > 0:
        pv_bruto, pv_cliente, _ = _pricing_from_row(
            r, cob_val, margem_pct, imposto_pct, comissao_pct, desc_pct)
    else:
        tot_ch  = float(r.get("total_chapas", 0) or 0)
        tot_ft  = sum(round(float(f.get("metros_total",0))*float(f.get("valor_m",0)),2) for f in fitas) if fitas else float(r.get("total_fitas",0) or 0)
        tot_ferr= sum(float(fe.get("subtotal",0) or 0) for fe in ferragens)
        tot_ou  = sum(float(outros.get(k,0) or 0) for k in ["cola","frete"])
        pv_bruto   = tot_ch + tot_ft + tot_ferr + tot_ou + mao_obra_val
        pv_cliente = pv_bruto * (1 - desc_pct / 100) if desc_pct > 0 else pv_bruto

    # ── Helpers de nomenclatura ──────────────────────────────────────────────
    def _nome_curto(nome):
        """Remove dimensões e fabricante do final do nome do produto."""
        s = re.sub(r'\s+\d+[\.,]?\d*\s*[xX×]\s*\d+.*', '', str(nome or ""))
        s = re.sub(r'\s+\d+[,.]?\d*\s*mm\b.*', '', s)
        s = re.sub(r'\s+(Guararapes|Berneck|Rehau|FGVTN|Grandes\s+Marcas)\s*$', '', s, flags=re.I)
        return s.strip()

    svg_logo_inline = _load_brand_logo_svg()

    # ── Tipo do projeto (para textos automáticos) ────────────────────────────
    proj_l = proj.lower()
    if any(w in proj_l for w in ("estante","rack","prateleira")):
        tipo = "estante sob medida"
        verbo = "A estante foi pensada para oferecer"
    elif any(w in proj_l for w in ("armario","armário","guarda-roupa","guarda roupa","roupeiro")):
        tipo = "móvel planejado sob medida"
        verbo = "O armário foi desenvolvido para oferecer"
    elif "cozinha" in proj_l:
        tipo = "cozinha planejada"
        verbo = "A cozinha foi projetada para oferecer"
    elif "nicho" in proj_l:
        tipo = "nicho decorativo sob medida"
        verbo = "O nicho foi pensado para oferecer"
    elif any(w in proj_l for w in ("mesa","bancada")):
        tipo = "bancada sob medida"
        verbo = "A peça foi desenvolvida para oferecer"
    else:
        tipo = "móvel planejado sob medida"
        verbo = "O projeto foi desenvolvido para oferecer"

    # ── Materiais distintos por espessura ───────────────────────────────────
    chapas_15 = [c for c in chapas if float(c.get("espessura_mm", 0) or 0) >= 12]
    chapas_6  = [c for c in chapas if float(c.get("espessura_mm", 0) or 0) <  12]

    # ── APRESENTAÇÃO ────────────────────────────────────────────────────────
    apresentacao = (
        f"Esta proposta contempla a produção de {tipo}, "
        f"desenvolvida para integrar funcionalidade, aproveitamento inteligente "
        f"do espaço e acabamento alinhado ao ambiente."
        f"<br><br>"
        f"O projeto considera materiais selecionados, corte técnico, preparação das "
        f"peças, acabamento de bordas, ferragens e mão de obra especializada."
    )
    if obs:
        apresentacao += f'<br><br><em style="color:#6B3F24">Observação do projeto: {obs}</em>'

    # ── CONCEITO ────────────────────────────────────────────────────────────
    conceito_items = [
        "Melhor aproveitamento do vão disponível",
        "Visual integrado ao ambiente",
    ]
    for c in chapas_15[:1]:
        conceito_items.append(f"Acabamento em {_nome_curto(c.get('produto',''))}")
    for c in chapas_6[:1]:
        conceito_items.append(f"Fundo em {_nome_curto(c.get('produto',''))}")
    conceito_items.append("Composição sob medida para uso funcional e decorativo")

    # ── ESCOPO ───────────────────────────────────────────────────────────────
    escopo_items = ["Desenvolvimento técnico para produção"]
    seen_esp = set()
    for c in chapas_15:
        esp = f"{float(c.get('espessura_mm', 15) or 15):.0f}mm"
        nm  = _nome_curto(c.get("produto",""))
        key = f"{esp}-{nm}"
        if key not in seen_esp:
            escopo_items.append(f"MDF principal {esp} com acabamento {nm}")
            seen_esp.add(key)
    for c in chapas_6:
        esp = f"{float(c.get('espessura_mm', 6) or 6):.0f}mm"
        nm  = _nome_curto(c.get("produto",""))
        key = f"{esp}-{nm}"
        if key not in seen_esp:
            escopo_items.append(f"Fundo em MDF {nm}")
            seen_esp.add(key)
    if fitas:
        escopo_items.append("Fitas de borda compatíveis com o acabamento")
    if ferragens:
        escopo_items.append("Ferragens e fixadores necessários")
    escopo_items.append("Corte, preparação e montagem das peças")
    if mao_obra_val > 0:
        escopo_items.append("Mão de obra especializada")
    if frete_val > 0:
        escopo_items.append("Frete dentro da condição considerada")

    # ── ACABAMENTOS ──────────────────────────────────────────────────────────
    acab_rows = ""
    for c in chapas_15[:1]:
        acab_rows += f"<tr><td class='acab-label'>Material principal</td><td>{_nome_curto(c.get('produto',''))}</td></tr>"
    for c in chapas_6[:1]:
        acab_rows += f"<tr><td class='acab-label'>Fundo</td><td>{_nome_curto(c.get('produto',''))}</td></tr>"
    for ft in fitas[:1]:
        acab_rows += f"<tr><td class='acab-label'>Bordas</td><td>{_nome_curto(ft.get('produto',''))}</td></tr>"
    if ferragens:
        acab_rows += "<tr><td class='acab-label'>Ferragens</td><td>Dobradiças e fixadores compatíveis com o projeto</td></tr>"

    # ── Bloco de investimento ────────────────────────────────────────────────
    if desc_pct > 0:
        inv_desc_row = f"""
        <tr>
          <td style="padding:6px 0;color:#EFE3D1;opacity:0.85">Condição especial aplicada ({desc_pct:.1f}%)</td>
          <td style="text-align:right;color:#EFE3D1;opacity:0.85">- {brl(pv_bruto - pv_cliente)}</td>
        </tr>"""
        inv_label = "INVESTIMENTO FINAL"
    else:
        inv_desc_row = ""
        inv_label    = "INVESTIMENTO"

    # ── Listas HTML ──────────────────────────────────────────────────────────
    def _ul(items):
        return "<ul>" + "".join(f"<li>{i}</li>" for i in items) + "</ul>"

    logo_block = _brand_logo_block(svg_logo_inline)

    # ════════════════════════════════════════════════════════════════════════
    html = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Proposta Comercial — {proj} — Gaus Woods</title>
<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<style>
  /* ── Variáveis de cor — Brandbook Gaus Woods v1.0 ─────────────────────── */
  :root {{
    --grafite:   #1F211F;
    --madeira:   #4B2E1B;
    --castanho:  #6B3F24;
    --carvalho:  #EFE3D1;
    --areia:     #D4BEA2;
    --marfim:    #F8F3EA;
  }}

  * {{ box-sizing: border-box; margin: 0; padding: 0; }}

  body {{
    font-family: 'Montserrat', Arial, sans-serif;
    font-size: 11px;
    color: var(--grafite);
    background: #fff;
    max-width: 800px;
    margin: 0 auto;
    padding: 0;
  }}

  /* ── Cabeçalho ─────────────────────────────────────────────────────────── */
  .header {{
    background: var(--grafite);
    color: var(--carvalho);
    padding: 28px 36px 22px;
    display: flex;
    align-items: center;
    gap: 28px;
  }}
  .logo-wrap {{ flex-shrink: 0; }}
  .logo-svg {{
    width: 220px;
    height: auto;
    display: block;
  }}
  .logo-svg svg {{
    width: 100%;
    height: auto;
  }}
  /* SVG original é dark-on-white; inverter para funcionar no fundo escuro */
  /* Suporte a fill como atributo direto (ex: fill="#231F20") e como style */
  .logo-svg path[fill="#231F20"],
  .logo-svg path[fill="#231f20"],
  .logo-svg path[fill="#040606"],
  .logo-svg path[style*="fill:#231f20"],
  .logo-svg path[style*="fill:#040606"] {{
    fill: var(--carvalho) !important;
  }}
  .logo-svg path[fill="#ffffff"],
  .logo-svg path[style*="fill:#ffffff"] {{
    fill: var(--grafite) !important;
  }}
  .logo-svg text tspan {{ fill: var(--carvalho) !important; }}
  .logo-svg path[stroke="#040606"],
  .logo-svg path[style*="stroke:#040606"] {{ stroke: var(--carvalho) !important; }}

  .logo-text-fallback {{ text-align: left; }}
  .logo-gw {{
    font-size: 22px; font-weight: 300; letter-spacing: 6px;
    color: var(--carvalho); text-transform: uppercase;
  }}
  .logo-sub {{
    font-size: 8px; font-weight: 600; letter-spacing: 3px;
    color: var(--areia); text-transform: uppercase;
  }}
  .header-right {{ flex: 1; text-align: right; }}
  .header-tipo {{
    font-size: 10px; font-weight: 500; letter-spacing: 3px;
    color: var(--areia); text-transform: uppercase; margin-bottom: 4px;
  }}
  .header-proposta {{
    font-size: 20px; font-weight: 300; letter-spacing: 2px;
    color: var(--carvalho); text-transform: uppercase; line-height: 1.1;
  }}
  .header-projeto {{
    font-size: 13px; font-weight: 600;
    color: var(--carvalho); margin-top: 6px;
  }}
  .header-num {{
    font-size: 9px; color: var(--areia); margin-top: 4px; letter-spacing: 1px;
  }}

  /* ── Faixa de meta ─────────────────────────────────────────────────────── */
  .meta-bar {{
    background: var(--carvalho);
    padding: 12px 36px;
    display: flex;
    gap: 40px;
    border-bottom: 2px solid var(--areia);
  }}
  .meta-item {{ display: flex; flex-direction: column; gap: 2px; }}
  .meta-label {{ font-size: 8px; font-weight: 600; letter-spacing: 2px;
                 text-transform: uppercase; color: var(--castanho); }}
  .meta-value {{ font-size: 11px; font-weight: 500; color: var(--grafite); }}

  /* ── Seções ────────────────────────────────────────────────────────────── */
  .section {{
    padding: 22px 36px;
    border-bottom: 1px solid var(--areia);
  }}
  .section:nth-child(even) {{ background: var(--marfim); }}
  .section:nth-child(odd)  {{ background: #fff; }}

  .section-title {{
    font-size: 9px; font-weight: 700; letter-spacing: 3px;
    text-transform: uppercase; color: var(--madeira);
    margin-bottom: 12px;
    display: flex; align-items: center; gap: 10px;
  }}
  .section-title::after {{
    content: ''; flex: 1;
    height: 1px; background: var(--areia);
  }}
  .section-body {{
    font-size: 11px; line-height: 1.75; color: var(--grafite);
  }}
  .section-body ul {{
    padding-left: 18px; margin: 0;
  }}
  .section-body ul li {{
    margin-bottom: 4px;
  }}
  .section-body ul li::marker {{
    color: var(--castanho);
  }}

  /* ── Acabamentos ───────────────────────────────────────────────────────── */
  .acab-table {{ width: 100%; border-collapse: collapse; }}
  .acab-table tr {{ border-bottom: 1px solid var(--areia); }}
  .acab-table tr:last-child {{ border-bottom: none; }}
  .acab-label {{
    font-size: 9px; font-weight: 700; letter-spacing: 1.5px;
    text-transform: uppercase; color: var(--castanho);
    width: 180px; padding: 7px 0;
  }}
  .acab-table td:last-child {{
    font-size: 11px; color: var(--grafite); padding: 7px 0 7px 12px;
  }}

  /* ── Bloco de investimento ─────────────────────────────────────────────── */
  .inv-section {{
    background: var(--madeira);
    padding: 28px 36px;
    border-bottom: 1px solid var(--areia);
  }}
  .inv-title {{
    font-size: 9px; font-weight: 700; letter-spacing: 3px;
    text-transform: uppercase; color: var(--areia);
    margin-bottom: 16px;
  }}
  .inv-table {{ width: 100%; border-collapse: collapse; }}
  .inv-table td {{
    padding: 5px 0; font-size: 12px; color: var(--carvalho);
  }}
  .inv-table td:last-child {{ text-align: right; font-weight: 600; }}
  .inv-total-row {{
    background: var(--carvalho);
    border-radius: 3px;
    margin-top: 12px;
    padding: 14px 16px;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }}
  .inv-total-label {{
    font-size: 11px; font-weight: 700; letter-spacing: 2px;
    text-transform: uppercase; color: var(--madeira);
  }}
  .inv-total-value {{
    font-size: 22px; font-weight: 700; color: var(--madeira);
    letter-spacing: 1px;
  }}

  /* ── Condições ─────────────────────────────────────────────────────────── */
  .cond-grid {{
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 12px 24px;
    margin-bottom: 12px;
  }}
  .cond-item {{ display: flex; flex-direction: column; gap: 3px; }}
  .cond-label {{
    font-size: 8px; font-weight: 700; letter-spacing: 2px;
    text-transform: uppercase; color: var(--castanho);
  }}
  .cond-value {{ font-size: 11px; color: var(--grafite); }}
  .cond-nota {{
    font-size: 10px; color: #666; font-style: italic;
    line-height: 1.5; border-top: 1px solid var(--areia); padding-top: 10px;
  }}

  /* ── Observações ───────────────────────────────────────────────────────── */
  .obs-box {{
    background: var(--carvalho);
    border-left: 3px solid var(--castanho);
    padding: 12px 16px;
    font-size: 10px;
    line-height: 1.7;
    color: #444;
    border-radius: 0 3px 3px 0;
  }}

  /* ── Rodapé ────────────────────────────────────────────────────────────── */
  .footer {{
    background: var(--grafite);
    padding: 14px 36px;
    display: flex;
    align-items: center;
    justify-content: space-between;
  }}
  .footer-brand {{
    font-size: 9px; font-weight: 600; letter-spacing: 3px;
    color: var(--areia); text-transform: uppercase;
  }}
  .footer-tagline {{
    font-size: 8px; color: #666; letter-spacing: 1px; font-style: italic;
  }}
  .footer-data {{
    font-size: 8px; color: #666; text-align: right;
  }}

  @media print {{
    body {{ max-width: 100%; margin: 0; }}
    .header {{ -webkit-print-color-adjust: exact; print-color-adjust: exact; }}
    .meta-bar, .inv-section, .footer {{
      -webkit-print-color-adjust: exact; print-color-adjust: exact;
    }}
    .btn-print {{ display: none !important; }}
  }}

  .btn-print {{
    position: fixed;
    bottom: 28px;
    right: 28px;
    z-index: 999;
    background: var(--madeira);
    color: #fff;
    border: none;
    border-radius: 6px;
    padding: 12px 22px;
    font-family: 'Montserrat', sans-serif;
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 1px;
    cursor: pointer;
    box-shadow: 0 4px 16px rgba(0,0,0,.35);
    display: flex;
    align-items: center;
    gap: 8px;
    transition: background .2s;
  }}
  .btn-print:hover {{ background: var(--castanho); }}
</style>
</head>
<body>

<button class="btn-print" onclick="window.print()">
  <svg width="15" height="15" viewBox="0 0 24 24" fill="none"
       stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <polyline points="6 9 6 2 18 2 18 9"/><rect x="6" y="17" width="12" height="5"/>
    <path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/>
  </svg>
  Imprimir / PDF
</button>

<!-- ═══ CABEÇALHO ══════════════════════════════════════════════════════════ -->
<div class="header">
  {logo_block}
  <div class="header-right">
    <div class="header-tipo">Proposta Comercial Premium</div>
    <div class="header-proposta">Proposta<br>Comercial</div>
    <div class="header-projeto">{proj}</div>
    <div class="header-num">Proposta nº {cotacao_id} &nbsp;·&nbsp; {data_cot}</div>
  </div>
</div>

<!-- ═══ META ════════════════════════════════════════════════════════════════ -->
<div class="meta-bar">
  <div class="meta-item">
    <span class="meta-label">Cliente</span>
    <span class="meta-value">{cli_nome}</span>
  </div>
  <div class="meta-item">
    <span class="meta-label">Local</span>
    <span class="meta-value">{cli_loc}</span>
  </div>
  <div class="meta-item">
    <span class="meta-label">Data</span>
    <span class="meta-value">{data_cot}</span>
  </div>
  <div class="meta-item">
    <span class="meta-label">Validade</span>
    <span class="meta-value">7 dias</span>
  </div>
  {"" if cli_tel == "—" else f'<div class="meta-item"><span class="meta-label">Telefone</span><span class="meta-value">{cli_tel}</span></div>'}
</div>

<!-- ═══ APRESENTAÇÃO ════════════════════════════════════════════════════════ -->
<div class="section">
  <div class="section-title">Apresentação</div>
  <div class="section-body">{apresentacao}</div>
</div>

<!-- ═══ CONCEITO ════════════════════════════════════════════════════════════ -->
<div class="section">
  <div class="section-title">Conceito do Projeto</div>
  <div class="section-body">
    <em style="color:var(--castanho); font-size:10px; display:block; margin-bottom:8px">{verbo}:</em>
    {_ul(conceito_items)}
  </div>
</div>

<!-- ═══ ESCOPO ══════════════════════════════════════════════════════════════ -->
<div class="section">
  <div class="section-title">Escopo Incluso</div>
  <div class="section-body">{_ul(escopo_items)}</div>
</div>

<!-- ═══ ACABAMENTOS ════════════════════════════════════════════════════════ -->
<div class="section">
  <div class="section-title">Acabamentos</div>
  <div class="section-body">
    <table class="acab-table">{acab_rows}</table>
  </div>
</div>

<!-- ═══ INVESTIMENTO ════════════════════════════════════════════════════════ -->
<div class="inv-section">
  <div class="inv-title">Investimento</div>
  <table class="inv-table">
    <tr>
      <td>Valor do projeto</td>
      <td>{brl(pv_bruto)}</td>
    </tr>
    {inv_desc_row}
  </table>
  <div class="inv-total-row">
    <span class="inv-total-label">{inv_label}</span>
    <span class="inv-total-value">{brl(pv_cliente)}</span>
  </div>
</div>

<!-- ═══ CONDIÇÕES COMERCIAIS ════════════════════════════════════════════════ -->
<div class="section">
  <div class="section-title">Condições Comerciais</div>
  <div class="section-body">
    <div class="cond-grid">
      <div class="cond-item">
        <span class="cond-label">Validade da proposta</span>
        <span class="cond-value">7 dias</span>
      </div>
      <div class="cond-item">
        <span class="cond-label">Prazo de produção</span>
        <span class="cond-value">{entrega if entrega and entrega != "—" else "A combinar"}</span>
      </div>
      <div class="cond-item">
        <span class="cond-label">Forma de pagamento</span>
        <span class="cond-value">A combinar</span>
      </div>
    </div>
    <div class="cond-nota">
      Início da produção mediante aprovação da proposta e confirmação de pagamento/sinal.
    </div>
  </div>
</div>

<!-- ═══ OBSERVAÇÕES ══════════════════════════════════════════════════════════ -->
<div class="section">
  <div class="section-title">Observações</div>
  <div class="section-body">
    <div class="obs-box">
      Alterações de medidas, layout, materiais, ferragens ou acabamento poderão gerar
      nova análise técnica e atualização do investimento.<br><br>
      Esta proposta considera os materiais, acabamentos e condições descritos acima.
    </div>
  </div>
</div>

<!-- ═══ RODAPÉ ══════════════════════════════════════════════════════════════ -->
<div class="footer">
  <div>
    <div class="footer-brand">Gaus Woods</div>
    <div class="footer-tagline">Marcenaria sob medida com identidade, precisão e estilo.</div>
  </div>
  <div class="footer-data">
    Gerado em {datetime.now().strftime('%d/%m/%Y %H:%M')}<br>
    CNC Cut Plan Optimizer Gaus Woods
  </div>
</div>

</body></html>"""
    # ════════════════════════════════════════════════════════════════════════

    out_path = os.path.join(TMP, f"proposta_{cotacao_id}.html")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)

    try:
        webbrowser.open(f"file:///{out_path.replace(os.sep, '/')}")
    except Exception:
        pass

    write_result(["OK", out_path, f"proposta={brl(pv_cliente)}"])


def handle_create_cotacao():
    """
    Lê cnc_cotacao_data.txt (JSON) e faz POST /cotacoes.
    Após criar o registro, faz UPDATE direto no DB para salvar campos
    que o endpoint FastAPI ainda não conhece:
      custo_efetivo_*, ferragens_json, pecas_json.
    """
    if not os.path.exists(COTACAO_FILE):
        write_result(["FAIL", "Arquivo de dados da cotação não encontrado"]); return

    # MAXScript escreve em Windows-1252 (ANSI) — não UTF-8
    try:
        with open(COTACAO_FILE, "r", encoding="utf-8") as f:
            raw = f.read()
    except UnicodeDecodeError:
        with open(COTACAO_FILE, "r", encoding="cp1252") as f:
            raw = f.read()

    try:
        payload = json.loads(raw)
    except Exception as e:
        write_result(["FAIL", f"JSON inválido: {e}"]); return

    r = _post("/cotacoes", payload)
    if not r or "id" not in r:
        write_result(["FAIL", "Erro ao criar cotação na API"]); return

    cot_id = r["id"]

    # ── Patch direto no DB para campos não cobertos pelo endpoint ──────────
    try:
        import psycopg2
        conn = psycopg2.connect(
            "host=2.25.180.127 port=5432 dbname=postgres user=postgres password=hunter123"
        )
        conn.autocommit = False
        cur = conn.cursor()

        # Serializa arrays como JSON strings para colunas TEXT
        ferragens_raw = payload.get("ferragens", [])
        ferragens_str = json.dumps(ferragens_raw, ensure_ascii=False) if ferragens_raw else None

        pecas_raw = payload.get("pecas_json", [])
        # pecas_json pode vir como lista (JSON array) ou como string já serializada
        if isinstance(pecas_raw, list):
            pecas_str = json.dumps(pecas_raw, ensure_ascii=False) if pecas_raw else None
        elif isinstance(pecas_raw, str) and pecas_raw not in ("", "[]"):
            pecas_str = pecas_raw
        else:
            pecas_str = None

        cur.execute("""
            UPDATE cotacoes
               SET custo_efetivo_chapas      = %s,
                   custo_efetivo_fitas       = %s,
                   custo_efetivo_outros      = %s,
                   custo_efetivo_geral       = %s,
                   ferragens_json            = %s,
                   pecas_json                = %s,
                   custo_produto_chapas      = %s,
                   custo_produto_fitas       = %s,
                   custo_produto_outros      = %s,
                   custo_produto_geral       = %s,
                   mao_obra                  = %s,
                   mao_obra_manual           = %s,
                   custo_aquisicao_total     = %s,
                   custo_material_consumido  = %s,
                   custo_operacional_base    = %s,
                   margem_lucro_pct          = %s,
                   preco_venda_final         = %s,
                   imposto_pct               = %s,
                   comissao_pct              = %s
             WHERE id = %s
        """, (
            float(payload.get("custo_efetivo_chapas", 0) or 0),
            float(payload.get("custo_efetivo_fitas",  0) or 0),
            float(payload.get("custo_efetivo_outros", 0) or 0),
            float(payload.get("custo_efetivo_geral",  0) or 0),
            ferragens_str,
            pecas_str,
            float(payload.get("custo_produto_chapas", 0) or 0),
            float(payload.get("custo_produto_fitas",  0) or 0),
            float(payload.get("custo_produto_outros", 0) or 0),
            float(payload.get("custo_produto_geral",  0) or 0),
            float(payload.get("mao_obra", 0) or 0),
            bool(payload.get("mao_obra_manual", False)),
            float(payload.get("custo_aquisicao_total",    0) or 0),
            float(payload.get("custo_material_consumido", 0) or 0),
            float(payload.get("custo_operacional_base",   0) or 0),
            float(payload.get("margem_lucro_pct",         0) or 0),
            float(payload.get("preco_venda_final",        0) or 0),
            float(payload.get("imposto_pct",              0) or 0),
            float(payload.get("comissao_pct",             0) or 0),
            cot_id,
        ))
        conn.commit()
        _write_debug(f"handle_create_cotacao: patch OK para id={cot_id}")
    except Exception as e_db:
        _write_debug(f"handle_create_cotacao: patch DB falhou — {e_db}")
    finally:
        try: cur.close()
        except: pass
        try: conn.close()
        except: pass
    # ─────────────────────────────────────────────────────────────────────

    write_result([
        "OK",
        str(cot_id),
        f"total={r.get('total_geral', 0)}",
        f"criado_em={r.get('criado_em', '')}",
    ])


def handle_calcular_precificacao():
    """
    Le cnc_pricing_data.txt (JSON, schema PricingInput) e faz POST
    /cotacoes/pricing/calcular. Devolve os totais (CMC/COB/PV/etc.)
    em uma linha pipe-delimited e os warnings nas linhas seguintes.

    Usado pelo MaxScript para que o calculo de precificacao tenha a API
    como fonte oficial; em caso de falha o MaxScript cai para o calculo
    local (mesma formula, replicada de gauswoodsquote.pricing).
    """
    if not os.path.exists(PRICING_FILE):
        write_result(["FAIL", "Arquivo de dados de precificacao nao encontrado"]); return

    try:
        with open(PRICING_FILE, "r", encoding="utf-8") as f:
            raw = f.read()
    except UnicodeDecodeError:
        with open(PRICING_FILE, "r", encoding="cp1252") as f:
            raw = f.read()

    try:
        payload = json.loads(raw)
    except Exception as e:
        write_result(["FAIL", f"JSON invalido: {e}"]); return

    r = _post("/cotacoes/pricing/calcular", payload)
    if not r:
        write_result(["FAIL", "Erro ao calcular precificacao na API"]); return

    lines = ["OK", "|".join(str(r.get(k, "")) for k in [
        "cmc", "cob", "preco_venda", "total_com_desc", "desconto_valor",
        "price_mo", "mo_auto", "abaixo_custo", "total_aquisicao",
        "custo_chapas", "custo_fita", "custo_fita_aq", "nr_rolos",
    ])]
    for w in r.get("warnings", []):
        lines.append(str(w))
    write_result(lines)


# ---------------------------------------------------------------------------
# dispatcher
# ---------------------------------------------------------------------------

def main():
    start = time.perf_counter()
    cmd, params = read_cmd()
    if cmd is None:
        write_result(["FAIL", "Comando não encontrado"])
        _write_perf("COMMAND command=<missing> status=FAIL elapsed_ms=0.00")
        return

    handlers = {
        "health_check":              lambda: handle_health_check(),
        "search_chapas":             lambda: handle_search_chapas(params),
        "search_fitas":              lambda: handle_search_fitas(params),
        "search_ferragens":          lambda: handle_search_ferragens(params),
        "start_api":                 lambda: handle_start_api(params),
        "create_cotacao":            lambda: handle_create_cotacao(),
        "search_clientes":           lambda: handle_search_clientes(params),
        "create_cliente":            lambda: handle_create_cliente(),
        "update_cliente":            lambda: handle_update_cliente(params),
        "get_cliente":               lambda: handle_get_cliente(params),
        "search_cotacoes":           lambda: handle_search_cotacoes(params),
        "get_cotacao":               lambda: handle_get_cotacao(params),
        "get_cotacao_items":         lambda: handle_get_cotacao_items(params),
        "update_cotacao":            lambda: handle_update_cotacao(params),
        "update_cotacao_full":       lambda: handle_update_cotacao_full(),
        "update_desconto_cotacao":   lambda: handle_update_desconto_cotacao(params),
        "calcular_precificacao":     lambda: handle_calcular_precificacao(),
        "export_cotacao_html":            lambda: handle_export_cotacao_html(params),
        "export_proposta_cliente_html":   lambda: handle_export_proposta_cliente_html(params),
    }

    try:
        handler = handlers.get(cmd)
        if handler:
            handler()
        else:
            write_result(["FAIL", f"Comando desconhecido: {cmd}"])
    except Exception as e:
        write_result(["FAIL", f"Erro interno no helper: {e}"])
        _write_error(f"COMMAND command={cmd} params={params!r} error={repr(e)}\n{traceback.format_exc()}")
    finally:
        elapsed_ms = (time.perf_counter() - start) * 1000
        _write_perf(
            f"COMMAND command={cmd} status={LAST_RESULT_STATUS} "
            f"elapsed_ms={elapsed_ms:.2f} params={params!r}"
        )


if __name__ == "__main__":
    main()
