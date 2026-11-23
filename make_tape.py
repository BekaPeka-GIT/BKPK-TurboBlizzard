#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_tape.py - robi plik CAS (kaseta Atari, 600 bodow) z dowolnej gry XEX:
uniwersalny loader BEKAPEKA (tape_loader.asm) + plik gry.

Kroki:
  1. czyta segmenty XEX, liczy stale paska postepu,
  2. sprawdza kolizje segmentow z pamiecia uzywana przez loader i system,
  3. wybiera miejsce na ekran loadera (blok ~6,7 KB wokol granicy 4 KB),
  4. generuje tape/<nazwa>/tape_cfg.inc i tape_title.inc,
  5. kompiluje tape_loader.asm (MADS) i sklada CAS (build_cas.py).

Wynik: tape/<nazwa>/<nazwa>.cas (+ .bin, .lst, .lab loadera).

Uzycie:
  python make_tape.py Ninja.xex --title "NINJA"
  python make_tape.py RiverRaid.xex --title "RIVER RAID" --word-colors 0,1 --color 9C
  python make_tape.py KeystoneKapers.xex --title "KEYSTONE KAPERS" --anim
  python make_tape.py RiverRaid.xex --title "RIVER RAID" --turbo   # gra w Turbo Blizzard

--turbo: loader (600 bodow) jak zwykle, ale gra jest nagrana w formacie Turbo
Blizzard (make_blizzard.py) i loader czyta ja sam, z logo i paskiem postepu.
Kaseta zostaje zgodna z Blizzardem na kartridzu (on pominie loader).
Wynik: tape/<nazwa>/<nazwa>_turbo.cas.
"""
import argparse
import os
import re
import subprocess
import sys

from build_cas import boot_cas, build, checksum, verify, xex_segments, CTRL_EOF, CTRL_FULL
from xex_info import progress_consts, progress_inc
import make_blizzard

HERE = os.path.dirname(os.path.abspath(__file__))
MADS = os.path.join(HERE, "mads.exe")
LOADER = os.path.join(HERE, "tape_loader.asm")

# blok ekranu wzgledem granicy 4 KB (SCR4K), zgodnie z tape_loader.asm:
# STAT = SCR4K-$1200 ... koniec paska BAR+320 = SCR4K+$640
SCR_LO, SCR_HI = -0x1200, 0x640
# z animacja (--anim) dochodza dwa okna ikony: SCR4K+$1000 i SCR4K+$2000 (po 4080 B)
SCR_HI_ANIM = 0x2FF0
# z --turbo dochodza bufor bloku BUF = SCR4K+$640 (1028 B) i bitmapy linii
# tekstu STATBM/WWWBM = SCR4K+$A50..$CCF
SCR_HI_TURBO = 0x0CD0
TURBO_BLOCK = 1024
RUNAD, INITAD = 0x02E0, 0x02E2

# obszary, ktorych gra nie moze nadpisac w trakcie ladowania
FORBIDDEN = [
    (0x00CE, 0x00EA, "zmienne loadera na stronie zerowej"),
    (0x0100, 0x01FF, "stos"),
    (0x0300, 0x047F, "DCB/IOCB/bufor kasety systemu"),
    (0xC000, 0xFFFF, "ROM systemu / rejestry sprzetu"),
]


def overlaps(a0, a1, b0, b1):
    return a0 <= b1 and b0 <= a1


def icode(ch, color):
    o = ord(ch)
    if not 32 <= o <= 95:
        sys.exit("BLAD: znak %r niedozwolony w tytule (tryb 7: A-Z, 0-9, spacja, znaki)" % ch)
    return (o - 32) | (color << 6)


def title_bytes(title, word_colors):
    """Nazwa gry wysrodkowana w 20 znakach trybu 7; kazde slowo w swoim kolorze."""
    title = title.upper()
    if len(title) > 20:
        sys.exit("BLAD: tytul ma %d znakow, max 20 (tryb 7)" % len(title))
    pad = (20 - len(title)) // 2
    out, word = [], 0
    for i, ch in enumerate(title):
        if ch == " ":
            if i and title[i - 1] != " ":
                word += 1
            out.append(0)
        else:
            out.append(icode(ch, word_colors[min(word, len(word_colors) - 1)]))
    return [0] * pad + out + [0] * (20 - pad - len(out))


def pick_screen(segs, forced):
    """Najnizsza granica 4 KB (od $3000), przy ktorej ekran nie nachodzi na gre."""
    cands = [forced] if forced is not None else range(0x3000, 0xC000, 0x1000)
    for k in cands:
        lo, hi = k + SCR_LO, k + SCR_HI - 1
        if hi >= 0xC000:
            continue
        hit = [s for s in segs if overlaps(s[0], s[1], lo, hi)]
        if not hit:
            return k
        if forced is not None:
            sys.exit("BLAD: ekran $%04X-$%04X nachodzi na segment $%04X-$%04X"
                     % (lo, hi, hit[0][0], hit[0][1]))
    sys.exit("BLAD: brak wolnych %d B na ekran loadera (gra zajmuje za duzo pamieci)"
             % (SCR_HI - SCR_LO))


def check_segments(segs, xex):
    errors, warns = [], []
    for s0, s1 in segs:
        if (s0, s1) in ((RUNAD, RUNAD + 1), (INITAD, INITAD + 1), (RUNAD, INITAD + 1)):
            continue
        for f0, f1, what in FORBIDDEN:
            if overlaps(s0, s1, f0, f1):
                errors.append("segment $%04X-$%04X nachodzi na %s ($%04X-$%04X)"
                              % (s0, s1, what, f0, f1))
        if s1 < 0x0100:
            warns.append("segment $%04X-$%04X na stronie zerowej" % (s0, s1))
        elif overlaps(s0, s1, 0x0200, 0x02FF):
            warns.append("segment $%04X-$%04X zmienia zmienne systemu (strona 2)" % (s0, s1))
    return errors, warns


def vectors(xex):
    """Adresy INITAD (w kolejnosci) i RUNAD z segmentow XEX."""
    inits, run, i = [], None, 0
    segs, end = xex_segments(xex)
    for s0, s1 in segs:
        while xex[i] == 0xFF and xex[i + 1] == 0xFF:
            i += 2
        data = xex[i + 4:i + 4 + s1 - s0 + 1]
        i += 4 + s1 - s0 + 1
        for addr, lst in ((INITAD, "init"), (RUNAD, "run")):
            if s0 <= addr and addr + 1 <= s1:
                v = data[addr - s0] | data[addr + 1 - s0] << 8
                if lst == "init":
                    inits.append(v)
                else:
                    run = v
    return inits, run


def turbo_consts(stream):
    """Stale postepu dla --turbo: TOTALB = dlugosc strumienia XEX (z naglowkami
    segmentow - tyle odda getbyte), bloki po 1 KB."""
    total = len(stream)
    blocks = (total + TURBO_BLOCK - 1) // TURBO_BLOCK
    shift = 4
    while (total >> shift) * 100 > 65535:
        shift += 1
    units = total >> shift
    if total > 0xFC00 or units == 0:
        sys.exit("BLAD: plik poza zakresem loadera turbo (%d B)" % total)
    return total, blocks, shift, units


def turbo_cas(loader, stream, title, desc, outdir, name):
    """Kaseta --turbo: rekordy boot loadera (600 bodow) + gra w Turbo Blizzard."""
    boot, nboot = boot_cas(loader, 20000, 250, desc)
    cas = make_blizzard.build(stream, title, loader=boot)

    # weryfikacja: rekordy boot jak w systemie, czesc turbo jak w Blizzardzie
    i, recs = 0, []
    while i < len(cas):
        ln = cas[i + 4] | cas[i + 5] << 8
        if cas[i:i + 4] == b"data":
            recs.append(cas[i + 8:i + 8 + ln])
        i += 8 + ln
    assert len(recs) == nboot + 1, "liczba rekordow boot"
    for k, r in enumerate(recs):
        assert len(r) == 132 and checksum(r[:131]) == r[131], "rekord %d: zla suma" % k
        assert r[2] == (CTRL_EOF if k == nboot else CTRL_FULL), "rekord %d: bajt kontrolny" % k
    assert b"".join(r[3:131] for r in recs[:nboot])[:len(loader)] == loader, "loader na tasmie"
    got_name, got = make_blizzard.parse(cas)
    assert got == stream, "dane turbo rozne od XEX"

    path = os.path.join(outdir, name + "_turbo.cas")
    open(path, "wb").write(cas)
    n_blk = len(stream) // TURBO_BLOCK + 1
    t_boot = 20 + (nboot + 1) * (0.25 + 132 * 10 / 600)
    t_turbo = 3 + 0.3 + 4 + n_blk * 0.35 + len(stream) * 8 * 10 / 44100
    print("CAS:    %s (%d B, %d rekordow boot + %d blokow turbo \"%s\", weryfikacja OK)"
          % (os.path.relpath(path, HERE), len(cas), nboot, n_blk, got_name))
    print("Czas:   loader ok. %d s (600 bodow), gra ok. %d s (turbo)" % (t_boot, t_turbo))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("xex", help="plik XEX z gra")
    ap.add_argument("--title", help="nazwa gry na ekranie (max 20 znakow; domyslnie z nazwy pliku)")
    ap.add_argument("--name", help="nazwa katalogu/pliku wyniku (domyslnie z nazwy pliku XEX)")
    ap.add_argument("--color", default="36",
                    help="kolor nazwy gry, hex bajt Atari (domyslnie 36 = czerwony)")
    ap.add_argument("--word-colors", default="0",
                    help="kolory kolejnych slow tytulu: 0 = --color, 1 = zloty, 3 = bialy "
                         "(np. 0,1; ostatni dotyczy reszty slow)")
    ap.add_argument("--screen", help="wymus granice 4 KB ekranu (hex, np. 6000)")
    ap.add_argument("--desc", help="opis kasety w CAS (domyslnie tytul)")
    ap.add_argument("--anim", action="store_true",
                    help="animacja logo (skok ikony + odblask); ekran zajmuje ok. 16,8 KB")
    ap.add_argument("--turbo", action="store_true",
                    help="gra w formacie Turbo Blizzard (loader czyta ja z logo i paskiem)")
    a = ap.parse_args()
    global SCR_HI
    if a.anim and a.turbo:
        sys.exit("BLAD: --anim i --turbo naraz nie dzialaja (animacja wymaga VBI, "
                 "a odczyt turbo wylacza przerwania)")
    if a.anim:
        SCR_HI = SCR_HI_ANIM
    if a.turbo:
        SCR_HI = SCR_HI_TURBO
        FORBIDDEN[0] = (0x00CE, 0x00F0, "zmienne loadera na stronie zerowej")

    stem = os.path.splitext(os.path.basename(a.xex))[0]
    name = a.name or re.sub(r"[^a-z0-9_]+", "_", stem.lower()).strip("_")
    title = (a.title or stem).upper()
    wc = [int(c) for c in a.word_colors.split(",")]
    if any(c not in (0, 1, 3) for c in wc):
        sys.exit("BLAD: --word-colors: dozwolone 0, 1, 3")
    color = int(a.color, 16)
    outdir = os.path.join(HERE, "tape", name)
    os.makedirs(outdir, exist_ok=True)

    xex = open(a.xex, "rb").read()
    segs, end = xex_segments(xex)
    if not segs:
        sys.exit("BLAD: w pliku XEX nie znaleziono segmentow")
    if a.turbo:
        total, blocks, shift, units = turbo_consts(xex[:end])
    else:
        total, blocks, shift, units = progress_consts(segs)
    errors, warns = check_segments(segs, xex)
    inits, run = vectors(xex)
    k = pick_screen(segs, int(a.screen, 16) if a.screen else None)

    # --- pliki konfiguracyjne loadera ---
    with open(os.path.join(outdir, "tape_cfg.inc"), "w", newline="\r\n") as f:
        f.write("; tape_cfg.inc - plik generowany przez make_tape.py (%s), nie edytowac recznie\n"
                % os.path.basename(a.xex))
        f.write(progress_inc(total, blocks, shift, units))
        f.write("SCR4K   = $%04X     ; ekran $%04X-$%04X\n" % (k, k + SCR_LO, k + SCR_HI - 1))
        f.write("TCOLOR  = $%02X       ; kolor nazwy gry (COLOR0)\n" % color)
        f.write("ANIM    = %d         ; animacja logo (--anim)\n" % int(a.anim))
        f.write("TURBO   = %d         ; gra w formacie Turbo Blizzard (--turbo)\n" % int(a.turbo))
    tb = title_bytes(title, wc)
    with open(os.path.join(outdir, "tape_title.inc"), "w", newline="\r\n") as f:
        f.write("; tape_title.inc - plik generowany przez make_tape.py, nie edytowac recznie\n")
        f.write("; \"%s\" w trybie 7 (20 znakow)\n" % title)
        f.write("gtitle  dta " + ",".join("$%02X" % b for b in tb) + "\n")

    # --- kompilacja loadera ---
    base = os.path.join(outdir, name + ("_turbo_ldr" if a.turbo else "_tape"))
    r = subprocess.run([MADS, LOADER, "-i:" + outdir, "-o:" + base + ".bin",
                        "-l:" + base + ".lst", "-t:" + base + ".lab", "-s"],
                       cwd=HERE, capture_output=True, text=True, errors="replace")
    if r.returncode != 0:
        sys.exit("BLAD kompilacji MADS:\n" + r.stdout + r.stderr)
    lab = open(base + ".lab", errors="replace").read()
    m = re.search(r"^\S+\s+([0-9A-F]{4})\s+LDR_END\s*$", lab, re.M)
    ldr_end = int(m.group(1), 16)
    for s0, s1 in segs:
        if overlaps(s0, s1, 0x0600, ldr_end - 1):
            errors.append("segment $%04X-$%04X nachodzi na loader ($0600-$%04X)"
                          % (s0, s1, ldr_end - 1))
    if ldr_end > k + SCR_LO:
        errors.append("loader ($0600-$%04X) nachodzi na ekran ($%04X)" % (ldr_end - 1, k + SCR_LO))

    print("Gra:    %s -> \"%s\", %d segmentow, %d B danych, %d blokow"
          % (os.path.basename(a.xex), title, len(segs), total, blocks))
    print("INIT:   %s" % (", ".join("$%04X" % v for v in inits) or "brak"))
    print("RUN:    %s" % ("$%04X" % run if run is not None else "brak"))
    print("Loader: $0600-$%04X, ekran $%04X-$%04X" % (ldr_end - 1, k + SCR_LO, k + SCR_HI - 1))
    if run is None:
        warns.append("brak RUNAD - gra musi wystartowac z ostatniego INIT (ktory nie wraca)")
    if inits:
        warns.append("gra ma INIT - sprawdz, czy nie czyszcza pamieci ekranu $%04X-$%04X "
                     "(loader przywraca tylko Display List i kolory)" % (k + SCR_LO, k + SCR_HI - 1))
    for w in warns:
        print("UWAGA:  " + w)
    if errors:
        for e in errors:
            print("BLAD:   " + e)
        sys.exit(1)

    # --- plik CAS ---
    loader = open(base + ".bin", "rb").read()
    if a.turbo:
        return turbo_cas(loader, xex[:end], title, a.desc or title.title(), outdir, name)
    cas, info = build(loader, xex, 20000, 250, a.desc or title.title(), 20000)
    n = verify(cas, info)
    cas_path = os.path.join(outdir, name + ".cas")
    open(cas_path, "wb").write(cas)
    print("CAS:    %s (%d B, %d rekordow, weryfikacja OK, odczyt ok. %d min %02d s)"
          % (os.path.relpath(cas_path, HERE), len(cas), n, *divmod(int(info["seconds"]), 60)))


if __name__ == "__main__":
    main()
