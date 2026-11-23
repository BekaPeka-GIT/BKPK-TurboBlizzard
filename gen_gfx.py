#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_gfx.py - generuje logo_data.inc dla loadera kasetowego (MADS).

Z pliku PNG z logo robi czarno-zlota bitmape 320x128 (1 bit/piksel,
tryb ANTIC $F = GR.8), kompresuje ja RLE (pary: ile, wartosc; 0 = koniec)
(po delcie pionowej: linia XOR poprzednia) i zapisuje razem z szablonami linii statusu
w kodach ekranowych Atari (internal).

Wymaga Pillow (pip install pillow). Wynik (logo_data.inc) jest dolaczony
do repozytorium, wiec Pillow potrzebny tylko przy zmianie logo.

Uzycie:
  python gen_gfx.py bekapeka_logo.png logo_data.inc [--preview podglad.png]
"""
import argparse
import sys

from PIL import Image

W, H, BPL = 320, 128, 40          # rozmiar bitmapy logo w pikselach i bajtach/linie
MAXW, MAXH = 300, 124             # maksymalny rozmiar samego logo (z marginesem)


def logo_bitmap(png, thresh):
    """Zwraca liste H wierszy po W wartosci 0/1 (1 = zloty piksel)."""
    im = Image.open(png).convert("RGBA")
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))   # przezroczystosc -> biale tlo
    g = Image.alpha_composite(bg, im).convert("L")
    ink = g.point(lambda v: 255 if v < 200 else 0)      # ciemniejsze od bialego tla = tusz
    box = ink.getbbox()
    if not box:
        sys.exit("BLAD: w obrazie nie znaleziono logo")
    ink = ink.crop(box)
    w, h = ink.size
    k = min(MAXW / w, MAXH / h)
    nw, nh = max(1, round(w * k)), max(1, round(h * k))
    small = ink.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("L", (W, H), 0)
    canvas.paste(small, ((W - nw) // 2, (H - nh) // 2))
    px = canvas.load()
    rows = [[1 if px[x, y] >= thresh else 0 for x in range(W)] for y in range(H)]
    return rows, (nw, nh)


def pack(rows):
    out = bytearray()
    for r in rows:
        for b in range(BPL):
            v = 0
            for i in range(8):
                v = (v << 1) | r[b * 8 + i]
            out.append(v)
    return bytes(out)


def vdelta(raw):
    """Delta pionowa: kazda linia XOR poprzednia (powtarzajace sie linie -> zera)."""
    d = bytearray(raw)
    for i in range(len(raw) - 1, BPL - 1, -1):
        d[i] = raw[i] ^ raw[i - BPL]
    return bytes(d)


def undelta(d):
    out = bytearray(d)
    for i in range(BPL, len(out)):
        out[i] ^= out[i - BPL]
    return bytes(out)


def rle(data):
    """Pary (n, v), n = 1..255; na koncu bajt 0."""
    out, i = bytearray(), 0
    while i < len(data):
        v, n = data[i], 1
        while i + n < len(data) and data[i + n] == v and n < 255:
            n += 1
        out += bytes([n, v])
        i += n
    out.append(0)
    return bytes(out)


def unrle(blob):
    out, i = bytearray(), 0
    while blob[i]:
        out += bytes([blob[i + 1]]) * blob[i]
        i += 2
    return bytes(out)


def icode(ch, color=0):
    """Kod ekranowy Atari (internal) znaku ASCII 32..95 plus bity koloru (tryby 6/7)."""
    o = ord(ch)
    if not 32 <= o <= 95:
        raise ValueError("znak poza zakresem: %r" % ch)
    return (o - 32) | (color << 6)


def text40(s):
    assert len(s) == 40, (len(s), s)
    return [icode(c) for c in s]


def dta(name, data, per=16):
    lines = ["%s" % name]
    for i in range(0, len(data), per):
        lines.append("        dta " + ",".join("$%02X" % b for b in data[i:i + per]))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("png")
    ap.add_argument("inc")
    ap.add_argument("--thresh", type=int, default=110, help="prog bieli 0..255 (domyslnie 110)")
    ap.add_argument("--preview", help="zapisz podglad bitmapy do PNG")
    a = ap.parse_args()

    rows, size = logo_bitmap(a.png, a.thresh)
    raw = pack(rows)
    blob = rle(vdelta(raw))
    assert undelta(unrle(blob)) == raw
    print("logo %dx%d px, surowo %d B, RLE %d B" % (size[0], size[1], len(raw), len(blob)))

    if a.preview:
        im = Image.new("RGB", (W, H), (0, 0, 0))
        for y, r in enumerate(rows):
            for x, v in enumerate(r):
                if v:
                    im.putpixel((x, y), (221, 160, 0))
        im.resize((W * 3, H * 3), Image.NEAREST).save(a.preview)

    # --- linie statusu (tryb 2, 40 znakow) ---
    tmpl = "  LADOWANIE ###%  ###/### ZOSTALO ###   "
    ofs_pct = tmpl.index("###")
    ofs_blk = tmpl.index("###", ofs_pct + 3)
    ofs_tot = tmpl.index("###", ofs_blk + 3)
    ofs_rem = tmpl.index("###", ofs_tot + 3)
    tmpl_show = tmpl.replace("#", " ")
    msg_open = "OTWIERANIE KASETY - POCZEKAJ CHWILE...".center(40)
    msg_err = "BLAD KASETY $XX  ETAP X".center(40)
    ofs_ehex = msg_err.index("XX")
    ofs_estg = msg_err.rindex("X")
    msg_err = msg_err.replace("X", " ")

    out = []
    out.append("; logo_data.inc - plik generowany przez gen_gfx.py, nie edytowac recznie")
    out.append("OFS_PCT  = %d" % ofs_pct)
    out.append("OFS_BLK  = %d" % ofs_blk)
    out.append("OFS_TOT  = %d" % ofs_tot)
    out.append("OFS_REM  = %d" % ofs_rem)
    out.append("OFS_EHEX = %d" % ofs_ehex)
    out.append("OFS_ESTG = %d" % ofs_estg)
    out.append("")
    out.append(dta("tmpl", text40(tmpl_show)))
    out.append(dta("msg_open", text40(msg_open)))
    out.append(dta("msg_err", text40(msg_err)))
    out.append(dta("logo_rle", blob))
    open(a.inc, "w", newline="\r\n").write("\n".join(out) + "\n")
    print("zapisano", a.inc)


if __name__ == "__main__":
    main()
