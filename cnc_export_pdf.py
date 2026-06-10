"""
CNC Cut Plan - PDF Export  (zero external dependencies)
Gera PDF puro usando apenas Python built-in.

Input:  %TEMP%/cnc_pdf_data.txt
Output: caminho definido em pdf_path= no arquivo de dados
"""

import os
import sys

TEMP_DIR  = os.environ.get("TEMP", os.environ.get("TMP", "/tmp"))
DATA_FILE = os.path.join(TEMP_DIR, "cnc_pdf_data.txt")

# ── Constantes ────────────────────────────────────────────────
MM  = 72.0 / 25.4          # mm → pontos PDF
A4W = 210.0 * MM           # 595.28 pt
A4H = 297.0 * MM           # 841.89 pt

MARGIN   = 12.0 * MM
HEADER_H = 18.0 * MM
FOOTER_H = 10.0 * MM

# Cores RGB 0-1
C_BOARD_BG    = (0.961, 0.941, 0.910)   # bege
C_BOARD_EDGE  = (0.800, 0.133, 0.000)   # vermelho
C_PIECE_BG    = (0.169, 0.102, 0.102)   # marrom escuro MDF
C_PIECE_EDGE  = (0.000, 0.667, 0.267)   # verde
C_TEXT_LIGHT  = (1.0,   1.0,   1.0)     # branco
C_HEADER_BG   = (0.102, 0.102, 0.180)   # azul escuro
C_FOOTER_TEXT = (0.267, 0.267, 0.267)   # cinza


# ── Gerador de PDF puro ───────────────────────────────────────

class PurePDF:
    """Gerador mínimo de PDF 1.4 sem dependências."""

    def __init__(self):
        self._pages = []          # lista de listas de ops (strings latin-1)
        self._cur   = None        # página corrente

    # -- Gestão de páginas --
    def new_page(self):
        self._cur = []
        self._pages.append(self._cur)

    # -- Primitivas de desenho --
    def _op(self, s):
        self._cur.append(s)

    def save(self):    self._op("q")
    def restore(self): self._op("Q")

    def line_width(self, w):
        self._op("{:.3f} w".format(w))

    def fill_color(self, r, g, b):
        self._op("{:.4f} {:.4f} {:.4f} rg".format(r, g, b))

    def stroke_color(self, r, g, b):
        self._op("{:.4f} {:.4f} {:.4f} RG".format(r, g, b))

    def rect(self, x, y, w, h, fill=True, stroke=True):
        self._op("{:.3f} {:.3f} {:.3f} {:.3f} re".format(x, y, w, h))
        if fill and stroke: self._op("B")
        elif fill:          self._op("f")
        else:               self._op("S")

    def clip_rect(self, x, y, w, h):
        """Define clipping region."""
        self._op("{:.3f} {:.3f} {:.3f} {:.3f} re W n".format(x, y, w, h))

    def text(self, x, y, s, size=9, bold=False):
        font = "/FB" if bold else "/F1"
        safe = s.replace("\\","\\\\").replace("(","\\(").replace(")","\\)")
        # Encode to latin-1 para PDF
        try:
            safe = safe.encode("latin-1","replace").decode("latin-1")
        except Exception:
            safe = safe
        self._op("BT {} {:.2f} Tf {:.3f} {:.3f} Td ({}) Tj ET".format(
            font, size, x, y, safe))

    def text_centered(self, cx, cy, s, size=9, bold=False):
        """Centraliza texto horizontalmente (estimativa)."""
        approx_w = len(s) * size * 0.50
        self.text(cx - approx_w / 2, cy, s, size, bold)

    def text_rotated_90ccw(self, cx, cy, s, size=9, bold=False):
        """Texto rotacionado 90° CCW (de baixo para cima), centralizado em (cx,cy)."""
        font = "/FB" if bold else "/F1"
        safe = s.replace("\\","\\\\").replace("(","\\(").replace(")","\\)")
        try:
            safe = safe.encode("latin-1","replace").decode("latin-1")
        except Exception:
            pass
        # Após 90° CCW: "comprimento" do texto fica na direção Y
        approx_w = len(s) * size * 0.50
        self._op("q")
        # [cos90 sin90 -sin90 cos90 tx ty] = [0 1 -1 0 cx cy]
        self._op("0 1 -1 0 {:.3f} {:.3f} cm".format(cx, cy))
        self._op("BT {} {:.2f} Tf {:.3f} {:.3f} Td ({}) Tj ET".format(
            font, size, -approx_w / 2, -size * 0.3, safe))
        self._op("Q")

    # -- Serialização --
    def write(self, path):
        raw = []          # lista de bytes
        offsets = []      # offset de cada objeto

        def emit(b):
            if isinstance(b, str):
                b = b.encode("latin-1", "replace")
            raw.append(b)

        def cur_offset():
            return sum(len(x) for x in raw)

        emit(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")   # header + comentário binário

        obj_idx = [0]   # contador mutável

        def write_obj(content):
            obj_idx[0] += 1
            n = obj_idx[0]
            offsets.append(cur_offset())
            emit("{} 0 obj\n".format(n))
            if isinstance(content, (bytes, bytearray)):
                raw.append(content)
            else:
                emit(content)
            emit("\nendobj\n")
            return n

        n_pages = len(self._pages)
        # IDs pré-calculados
        # 1=catalog  2=pages  3=F1  4=FB
        # Escrita: content primeiro (→ obj ímpar 5,7,9…), page depois (→ obj par 6,8,10…)
        content_ids = [5 + i*2 for i in range(n_pages)]  # 5,7,9…
        page_ids    = [6 + i*2 for i in range(n_pages)]  # 6,8,10…

        # Obj 1 – Catalog
        write_obj("<< /Type /Catalog /Pages 2 0 R >>")

        # Obj 2 – Pages
        kids = " ".join("{} 0 R".format(p) for p in page_ids)
        write_obj("<< /Type /Pages /Kids [{}] /Count {} >>".format(kids, n_pages))

        # Obj 3 – Fonte normal
        write_obj("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
                  "/Encoding /WinAnsiEncoding >>")

        # Obj 4 – Fonte bold
        write_obj("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold "
                  "/Encoding /WinAnsiEncoding >>")

        # Páginas
        for i, ops in enumerate(self._pages):
            stream = "\n".join(ops).encode("latin-1", "replace")
            # Obj content
            write_obj(
                b"<< /Length " + str(len(stream)).encode() + b" >>\n"
                b"stream\n" + stream + b"\nendstream"
            )
            # Obj page
            write_obj(
                "<< /Type /Page /Parent 2 0 R "
                "/MediaBox [0 0 {:.2f} {:.2f}] "
                "/Contents {} 0 R "
                "/Resources << /Font << /F1 3 0 R /FB 4 0 R >> >> "
                ">>".format(A4W, A4H, content_ids[i])
            )

        # XRef
        xref_pos = cur_offset()
        total = obj_idx[0] + 1
        emit("xref\n0 {}\n".format(total))
        emit("0000000000 65535 f \n")
        for off in offsets:
            emit("{:010d} 00000 n \n".format(off))
        emit("trailer\n<< /Size {} /Root 1 0 R >>\n".format(total))
        emit("startxref\n{}\n%%EOF\n".format(xref_pos))

        with open(path, "wb") as f:
            for chunk in raw:
                f.write(chunk)


# ── Leitura dos dados ─────────────────────────────────────────

def parse_data(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = [l.rstrip("\n\r") for l in f]

    meta   = {}
    chapas = []
    pecas  = []

    for ln in lines:
        if ln.startswith("chapa,"):
            p = ln.split(",")
            chapas.append({
                "idx":   int(float(p[1])),
                "esp":   float(p[2]),
                "w":     float(p[3]),   # mm
                "d":     float(p[4]),   # mm
                "off_x": float(p[5]),   # mm
                "off_y": float(p[6]),   # mm
            })
        elif ln.startswith("peca,"):
            p = ln.split(",")
            pecas.append({
                "nome":  p[1],
                "w":     float(p[2]),   # mm
                "d":     float(p[3]),   # mm
                "board": int(float(p[4])),
                "px":    float(p[5]),   # mm absoluto
                "py":    float(p[6]),   # mm absoluto
                "off_x": float(p[7]),   # mm (identifica grupo de espessura)
                "esp":   float(p[8]),   # mm
            })
        elif "=" in ln:
            k, v = ln.split("=", 1)
            meta[k.strip()] = v.strip()

    return meta, chapas, pecas


# ── Layout de uma página (uma chapa) ─────────────────────────

def draw_page(pdf, chapa, pecas_chapa, aproveitamento, page_num, total_pages):
    pdf.new_page()

    bw_mm = chapa["w"]   # mm
    bd_mm = chapa["d"]   # mm

    # Área útil para o desenho
    draw_w = A4W - 2 * MARGIN
    draw_h = A4H - HEADER_H - FOOTER_H - 2 * MARGIN

    sx = draw_w / (bw_mm * MM)    # escala x (sem unidade)
    sy = draw_h / (bd_mm * MM)    # escala y
    sc = min(sx, sy)               # escala uniforme

    bw_pt = bw_mm * MM * sc
    bd_pt = bd_mm * MM * sc

    # Centraliza horizontalmente
    ox = MARGIN + (draw_w - bw_pt) / 2.0
    oy = FOOTER_H + MARGIN

    # ── Cabeçalho ──
    pdf.fill_color(*C_HEADER_BG)
    pdf.rect(0, A4H - HEADER_H, A4W, HEADER_H, fill=True, stroke=False)

    pdf.fill_color(*C_TEXT_LIGHT)
    pdf.text(MARGIN, A4H - HEADER_H + 6 * MM,
             "Plano de Corte CNC", size=11, bold=True)

    info = "Chapa {}/{}  |  {:.0f} x {:.0f} mm  esp. {:.0f} mm  |  Aproveitamento: {:.1f}%".format(
        page_num, total_pages,
        bw_mm, bd_mm, chapa["esp"], aproveitamento)
    pdf.text(MARGIN, A4H - HEADER_H + 2 * MM, info, size=7.5)

    # ── Chapa (fundo) ──
    pdf.line_width(1.0)
    pdf.fill_color(*C_BOARD_BG)
    pdf.stroke_color(*C_BOARD_EDGE)
    pdf.rect(ox, oy, bw_pt, bd_pt, fill=True, stroke=True)

    # Label chapa (fora, acima)
    pdf.fill_color(*C_BOARD_EDGE)
    pdf.text(ox, oy + bd_pt + 2 * MM,
             "{:.0f} x {:.0f} mm".format(bw_mm, bd_mm), size=7, bold=True)

    # ── Peças ──
    for peca in pecas_chapa:
        px_rel = peca["px"] - chapa["off_x"]   # mm relativo à chapa
        py_rel = peca["py"] - chapa["off_y"]   # mm relativo à chapa
        pw_mm  = peca["w"]
        pd_mm  = peca["d"]

        px_pt = ox + px_rel * MM * sc
        py_pt = oy + py_rel * MM * sc
        pw_pt = pw_mm * MM * sc
        pd_pt = pd_mm * MM * sc

        # Fundo da peça
        pdf.save()
        pdf.clip_rect(px_pt, py_pt, pw_pt, pd_pt)
        pdf.line_width(0.5)
        pdf.fill_color(*C_PIECE_BG)
        pdf.stroke_color(*C_PIECE_EDGE)
        pdf.rect(px_pt, py_pt, pw_pt, pd_pt, fill=True, stroke=True)
        pdf.restore()

        # Texto: nome + dimensões — adapta orientação à peça
        min_dim = min(pw_pt, pd_pt)
        max_dim = max(pw_pt, pd_pt)
        if min_dim > 4 * MM and max_dim > 8 * MM:
            fs  = max(4.5, min(7.5, min_dim * 0.11))
            cx  = px_pt + pw_pt / 2.0
            cy  = py_pt + pd_pt / 2.0

            pdf.fill_color(*C_TEXT_LIGHT)
            nome = peca["nome"]
            dim  = "{:.0f} x {:.0f}".format(pw_mm, pd_mm)

            if pw_pt >= pd_pt:
                # Peça horizontal: texto normal
                pdf.text_centered(cx, cy + fs * 0.4,  nome, size=fs,        bold=True)
                pdf.text_centered(cx, cy - fs * 1.0,  dim,  size=fs * 0.85)
            else:
                # BUG5-FIX: Peça vertical → texto rotacionado 90° CCW
                pdf.text_rotated_90ccw(cx, cy + fs * 0.4,  nome, size=fs,        bold=True)
                pdf.text_rotated_90ccw(cx, cy - fs * 1.0,  dim,  size=fs * 0.85)

    # ── Rodapé com lista de peças ──
    pdf.fill_color(*C_FOOTER_TEXT)
    partes = ["{}: {:.0f}x{:.0f}mm".format(p["nome"], p["w"], p["d"])
              for p in pecas_chapa]
    linha = "  |  ".join(partes)
    # Trunca
    max_chars = int((A4W - 2 * MARGIN) / (6.0 * 0.5))
    if len(linha) > max_chars:
        linha = linha[:max_chars] + "..."
    pdf.text(MARGIN, 3 * MM, linha, size=6)


# ── Entry point ───────────────────────────────────────────────

def main():
    meta, chapas, pecas = parse_data(DATA_FILE)
    pdf_path    = meta.get("pdf_path", "cnc_plano_corte.pdf")
    aproveit    = float(meta.get("aproveitamento", 0))
    total_pages = len(chapas)

    pdf = PurePDF()

    for idx, chapa in enumerate(chapas):
        # Peças desta chapa: mesmo board index E mesmo grupo off_x
        board_pecas = [
            p for p in pecas
            if p["board"] == chapa["idx"]
            and abs(p["off_x"] - chapa["off_x"]) < 10.0
        ]
        draw_page(pdf, chapa, board_pecas, aproveit,
                  idx + 1, total_pages)

    pdf.write(pdf_path)


main()
