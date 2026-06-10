"""
CNC Cut Plan - MAXRECTS Bin Packing Engine
Output: plain text, one line per piece, easier to parse in MAXScript.

Input  file: %TEMP%/cnc_input.txt
Output file: %TEMP%/cnc_output.txt

Input format  (one token per line):
  binW
  binD
  gap
  allowRot   (0 or 1)
  count
  id w h     (one line per piece)

Output format:
  OK
  boards_used=N
  id,board,x,y,rotated   (one line per piece, rotated=0 or 1)

On error:
  ERROR
  <message>
"""

import os
import sys

TEMP_DIR    = os.environ.get("TEMP", os.environ.get("TMP", "/tmp"))
INPUT_FILE  = os.path.join(TEMP_DIR, "cnc_input.txt")
OUTPUT_FILE = os.path.join(TEMP_DIR, "cnc_output.txt")


# ──────────────────────────────────────────────────────────────
# MAXRECTS  (Best Short Side Fit — BSSF)
# ──────────────────────────────────────────────────────────────

class Rect:
    __slots__ = ("x", "y", "w", "h")
    def __init__(self, x, y, w, h):
        self.x, self.y, self.w, self.h = float(x), float(y), float(w), float(h)

    def fits(self, pw, ph, tol=1e-5):
        return pw <= self.w + tol and ph <= self.h + tol

    def intersects(self, o):
        return not (self.x + self.w <= o.x + 1e-9 or o.x + o.w <= self.x + 1e-9 or
                    self.y + self.h <= o.y + 1e-9 or o.y + o.h <= self.y + 1e-9)


class MaxRectsBin:
    def __init__(self, w, h):
        self.w = float(w)
        self.h = float(h)
        self.free  = [Rect(0.0, 0.0, w, h)]
        self.used  = []

    def insert(self, pw, ph, allow_rot):
        """Returns (x, y, rotated) or None."""
        best = None   # (score_short, score_long, rect, pw, ph, rot)

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
        placed = Rect(r.x, r.y, tw, th)
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
                    new_free.append(Rect(placed.x + placed.w, r.y, nw, r.h))
            if placed.x > r.x + 1e-9:
                nw = placed.x - r.x
                if nw > 1e-6:
                    new_free.append(Rect(r.x, r.y, nw, r.h))
            if placed.y + placed.h < r.y + r.h - 1e-9:
                nh = r.y + r.h - (placed.y + placed.h)
                if nh > 1e-6:
                    new_free.append(Rect(r.x, placed.y + placed.h, r.w, nh))
            if placed.y > r.y + 1e-9:
                nh = placed.y - r.y
                if nh > 1e-6:
                    new_free.append(Rect(r.x, r.y, r.w, nh))
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


# ──────────────────────────────────────────────────────────────
# Multi-heuristic solver
# ──────────────────────────────────────────────────────────────

def _pack(pieces_sorted, bin_w, bin_h, gap, allow_rot):
    """Pack pieces (already sorted) into bins. Returns (placements_dict, bins)."""
    bins   = [MaxRectsBin(bin_w, bin_h)]
    placed = {}

    for pid, pw, ph in pieces_sorted:
        # Pad piece with gap so gap space is reserved automatically
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
            new_bin = MaxRectsBin(bin_w, bin_h)
            result = new_bin.insert(tw, th, allow_rot)
            if result is not None:
                x, y, rot = result
                bins.append(new_bin)
                placed[pid] = (len(bins), x, y, rot)

    return placed, bins


def solve(pieces, bin_w, bin_h, gap, allow_rot):
    """Try multiple sort heuristics, return best result."""
    sort_keys = [
        lambda p: -(p[1] * p[2]),              # area desc
        lambda p: -max(p[1], p[2]),             # max side desc
        lambda p: -(p[1] + p[2]),               # perimeter desc
        lambda p: -min(p[1], p[2]),             # min side desc
    ]

    best_placed  = None
    best_n_bins  = 10 ** 9
    best_util    = 0.0

    for key in sort_keys:
        sorted_pieces = sorted(pieces, key=key)
        placed, bins  = _pack(sorted_pieces, bin_w, bin_h, gap, allow_rot)
        n = len(bins)
        u = sum(b.utilization() for b in bins) / n if n else 0.0
        if n < best_n_bins or (n == best_n_bins and u > best_util):
            best_n_bins  = n
            best_util    = u
            best_placed  = placed

    return best_placed, best_n_bins, best_util


# ──────────────────────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────────────────────

def main():
    try:
        with open(INPUT_FILE, "r") as f:
            lines = [l.strip() for l in f if l.strip()]

        bin_w     = float(lines[0])
        bin_h     = float(lines[1])
        gap       = float(lines[2])
        allow_rot = lines[3] == "1"
        count     = int(lines[4])

        pieces = []
        for k in range(count):
            parts = lines[5 + k].split()
            pid   = int(parts[0])
            pw    = float(parts[1])
            ph    = float(parts[2])
            pieces.append((pid, pw, ph))

        placed, boards_used, util = solve(pieces, bin_w, bin_h, gap, allow_rot)

        with open(OUTPUT_FILE, "w") as f:
            f.write("OK\n")
            f.write("boards_used={}\n".format(boards_used))
            for pid, pw, ph in pieces:
                if pid in placed:
                    board, x, y, rot = placed[pid]
                    f.write("{},{},{:.10f},{:.10f},{}\n".format(
                        pid, board, x, y, 1 if rot else 0))
                else:
                    f.write("{},0,0.0,0.0,0\n".format(pid))

    except Exception as e:
        with open(OUTPUT_FILE, "w") as f:
            f.write("ERROR\n")
            f.write(str(e) + "\n")


main()
