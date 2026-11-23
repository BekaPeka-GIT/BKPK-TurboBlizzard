#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
xex_info.py - liczy rozmiar danych pliku XEX i zapisuje stale dla loadera
(procenty i liczniki blokow na ekranie ladowania).

Uzycie:
  python xex_info.py RiverRaid.xex xex_info.inc
"""
import sys

from build_cas import xex_segments


def progress_consts(segs):
    """Zwraca (total, blocks, shift, units) albo konczy z bledem."""
    total = sum(last - start + 1 for start, last in segs)   # bajty danych (bez naglowkow)
    blocks = (total + 127) // 128                           # bloki po 128 B
    shift = 4
    while (total >> shift) * 100 > 65535:                   # q*100 musi miescic sie w 16 bitach
        shift += 1
    units = total >> shift
    if blocks > 255 or units == 0:
        sys.exit("BLAD: plik poza zakresem loadera (blokow: %d, max 255)" % blocks)
    return total, blocks, shift, units


def progress_inc(total, blocks, shift, units):
    return ("TOTALB  = %d      ; bajty danych segmentow\n" % total
            + "TOTBLK  = %d        ; liczba blokow po 128 B\n" % blocks
            + "SHIFT   = %d         ; przesuniecie przy liczeniu procentu\n" % shift
            + "UNITS   = %d       ; TOTALB >> SHIFT\n" % units)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    xex = open(sys.argv[1], "rb").read()
    segs, _ = xex_segments(xex)
    if not segs:
        sys.exit("BLAD: w pliku XEX nie znaleziono segmentow")
    total, blocks, shift, units = progress_consts(segs)
    with open(sys.argv[2], "w", newline="\r\n") as f:
        f.write("; xex_info.inc - plik generowany przez xex_info.py, nie edytowac recznie\n")
        f.write(progress_inc(total, blocks, shift, units))
    print("XEX: %d B danych w %d segmentach, %d blokow, SHIFT=%d, UNITS=%d"
          % (total, len(segs), blocks, shift, units))


if __name__ == "__main__":
    main()
