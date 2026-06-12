"""
Servico central de plano de corte (nesting) — Gaus Woods.

Porta o motor MAXRECTS (Best Short Side Fit) de cnc_packing.py para a API,
em formato estruturado (Pydantic). E a fonte oficial do calculo de plano de
corte: o MaxScript chama este endpoint via apiCalcularNesting, sem fallback
local. cnc_packing.py permanece apenas como referencia historica do
algoritmo original e nao e mais chamado pelo MaxScript.
"""

from typing import List, Dict, Tuple

from pydantic import BaseModel


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class NestingPeca(BaseModel):
    id:   int
    nome: str = ""
    w:    float   # largura/comprimento (mm)
    h:    float   # altura/largura (mm)


class NestingInput(BaseModel):
    bin_w:     float          # largura da chapa (mm)
    bin_h:     float          # altura/comprimento da chapa (mm)
    gap:       float = 0.0    # espacamento entre pecas / serra (mm)
    allow_rot: bool  = True
    pecas:     List[NestingPeca] = []


class NestingPlacement(BaseModel):
    id:      int
    nome:    str
    board:   int     # 1-based; 0 = nao coube em nenhuma chapa
    x:       float
    y:       float
    w:       float
    h:       float
    rotated: bool


class NestingResult(BaseModel):
    boards_used:        int
    aproveitamento_pct: float
    placements:         List[NestingPlacement]


# ---------------------------------------------------------------------------
# MAXRECTS  (Best Short Side Fit — BSSF)
# ---------------------------------------------------------------------------

class _Rect:
    __slots__ = ("x", "y", "w", "h")

    def __init__(self, x, y, w, h):
        self.x, self.y, self.w, self.h = float(x), float(y), float(w), float(h)

    def fits(self, pw, ph, tol=1e-5):
        return pw <= self.w + tol and ph <= self.h + tol

    def intersects(self, o):
        return not (self.x + self.w <= o.x + 1e-9 or o.x + o.w <= self.x + 1e-9 or
                    self.y + self.h <= o.y + 1e-9 or o.y + o.h <= self.y + 1e-9)


class _MaxRectsBin:
    def __init__(self, w, h):
        self.w = float(w)
        self.h = float(h)
        self.free = [_Rect(0.0, 0.0, w, h)]
        self.used = []

    def insert(self, pw, ph, allow_rot):
        """Returns (x, y, rotated) or None."""
        best = None  # (score_short, score_long, rect, pw, ph, rot)

        for rot in ([False, True] if allow_rot and abs(pw - ph) > 1e-5 else [False]):
            tw, th = (ph, pw) if rot else (pw, ph)
            for r in self.free:
                if not r.fits(tw, th):
                    continue
                ss = min(r.w - tw, r.h - th)
                sl = max(r.w - tw, r.h - th)
                if best is None or (ss, sl) < (best[0], best[1]):
                    best = (ss, sl, r, tw, th, rot)

        if best is None:
            return None

        _, _, r, tw, th, rot = best
        placed = _Rect(r.x, r.y, tw, th)
        self.used.append(placed)
        self._split(placed)
        self._prune()
        return (placed.x, placed.y, rot)

    def _split(self, placed):
        new_free = []
        for r in self.free:
            if not placed.intersects(r):
                new_free.append(r)
                continue
            if placed.x + placed.w < r.x + r.w - 1e-9:
                nw = r.x + r.w - (placed.x + placed.w)
                if nw > 1e-6:
                    new_free.append(_Rect(placed.x + placed.w, r.y, nw, r.h))
            if placed.x > r.x + 1e-9:
                nw = placed.x - r.x
                if nw > 1e-6:
                    new_free.append(_Rect(r.x, r.y, nw, r.h))
            if placed.y + placed.h < r.y + r.h - 1e-9:
                nh = r.y + r.h - (placed.y + placed.h)
                if nh > 1e-6:
                    new_free.append(_Rect(r.x, placed.y + placed.h, r.w, nh))
            if placed.y > r.y + 1e-9:
                nh = placed.y - r.y
                if nh > 1e-6:
                    new_free.append(_Rect(r.x, r.y, r.w, nh))
        self.free = new_free

    def _prune(self):
        pruned = []
        n = len(self.free)
        for i in range(n):
            a = self.free[i]
            skip = False
            for j in range(n):
                if i == j:
                    continue
                b = self.free[j]
                if (b.x <= a.x + 1e-9 and b.y <= a.y + 1e-9 and
                        b.x + b.w >= a.x + a.w - 1e-9 and
                        b.y + b.h >= a.y + a.h - 1e-9):
                    skip = True
                    break
            if not skip:
                pruned.append(a)
        self.free = pruned

    def utilization(self):
        area = sum(r.w * r.h for r in self.used)
        total = self.w * self.h
        return area / total if total > 0 else 0.0


# ---------------------------------------------------------------------------
# Multi-heuristic solver
# ---------------------------------------------------------------------------

def _pack(pieces_sorted, bin_w, bin_h, gap, allow_rot):
    """Empacota pecas (ja ordenadas) nas chapas. Retorna (placements, bins)."""
    bins: List[_MaxRectsBin] = [_MaxRectsBin(bin_w, bin_h)]
    placed: Dict[int, Tuple[int, float, float, bool]] = {}

    for pid, pw, ph in pieces_sorted:
        # Adiciona o gap a peca para reservar o espaco automaticamente.
        tw, th = pw + gap, ph + gap
        done = False
        for bi, b in enumerate(bins):
            result = b.insert(tw, th, allow_rot)
            if result is not None:
                x, y, rot = result
                placed[pid] = (bi + 1, x, y, rot)
                done = True
                break
        if not done:
            new_bin = _MaxRectsBin(bin_w, bin_h)
            result = new_bin.insert(tw, th, allow_rot)
            if result is not None:
                x, y, rot = result
                bins.append(new_bin)
                placed[pid] = (len(bins), x, y, rot)

    return placed, bins


def _solve(pieces, bin_w, bin_h, gap, allow_rot):
    """Tenta varias heuristicas de ordenacao, retorna o melhor resultado."""
    sort_keys = [
        lambda p: -(p[1] * p[2]),   # area desc
        lambda p: -max(p[1], p[2]),  # maior lado desc
        lambda p: -(p[1] + p[2]),   # perimetro desc
        lambda p: -min(p[1], p[2]),  # menor lado desc
    ]

    best_placed = None
    best_n_bins = 10 ** 9
    best_util = 0.0

    for key in sort_keys:
        sorted_pieces = sorted(pieces, key=key)
        placed, bins = _pack(sorted_pieces, bin_w, bin_h, gap, allow_rot)
        n = len(bins)
        u = sum(b.utilization() for b in bins) / n if n else 0.0
        if n < best_n_bins or (n == best_n_bins and u > best_util):
            best_n_bins = n
            best_util = u
            best_placed = placed

    return best_placed, best_n_bins, best_util


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def calcular_nesting(payload: NestingInput) -> NestingResult:
    """Calcula o plano de corte (posicao de cada peca em cada chapa).

    Fonte oficial do algoritmo MAXRECTS; cnc_packing.py e mantido apenas
    como referencia historica e nao e mais chamado pelo MaxScript.
    """
    pieces = [(p.id, p.w, p.h) for p in payload.pecas]
    pecas_by_id = {p.id: p for p in payload.pecas}

    if not pieces:
        return NestingResult(boards_used=0, aproveitamento_pct=0.0, placements=[])

    placed, boards_used, util = _solve(pieces, payload.bin_w, payload.bin_h, payload.gap, payload.allow_rot)

    placements = []
    for pid, pw, ph in pieces:
        peca = pecas_by_id[pid]
        if pid in placed:
            board, x, y, rot = placed[pid]
            placements.append(NestingPlacement(
                id=pid, nome=peca.nome, board=board, x=round(x, 4), y=round(y, 4),
                w=(ph if rot else pw), h=(pw if rot else ph), rotated=rot,
            ))
        else:
            placements.append(NestingPlacement(
                id=pid, nome=peca.nome, board=0, x=0.0, y=0.0, w=pw, h=ph, rotated=False,
            ))

    return NestingResult(
        boards_used=boards_used,
        aproveitamento_pct=round(util * 100.0, 2),
        placements=placements,
    )
