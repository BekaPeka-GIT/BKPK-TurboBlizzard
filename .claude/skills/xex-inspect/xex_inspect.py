#!/usr/bin/env python3
"""Analizator plików Atari XEX: lista segmentów, RUNAD/INITAD, opcjonalny hexdump."""
import argparse
import sys

RUNAD = (0x02E0, 0x02E1)
INITAD = (0x02E2, 0x02E3)


def parse(data):
    """Zwraca (segmenty, liczba nadmiarowych bajtów na końcu pliku)."""
    segs, pos = [], 0
    while pos < len(data):
        if not any(data[pos:]):  # zerowy padding (np. z obrazu dyskietki)
            return segs, len(data) - pos
        start = data[pos] | data[pos + 1] << 8
        if start == 0xFFFF:
            pos += 2
            continue
        if pos + 4 > len(data):
            return segs, len(data) - pos
        end = data[pos + 2] | data[pos + 3] << 8
        if end < start:
            raise ValueError(f"Segment ${start:04X}-${end:04X}: koniec < początek (offset {pos:#x})")
        body = data[pos + 4:pos + 4 + end - start + 1]
        if len(body) != end - start + 1:
            raise ValueError(f"Segment ${start:04X}-${end:04X} obcięty: {len(body)} z {end - start + 1} B")
        segs.append((pos, start, end, body))
        pos += 4 + len(body)
    return segs, 0


def hexdump(addr, body, limit):
    for i in range(0, min(len(body), limit), 16):
        chunk = body[i:i + 16]
        hx = " ".join(f"{b:02X}" for b in chunk)
        print(f"    ${addr + i:04X}: {hx:<47}")
    if len(body) > limit:
        print(f"    ... (+{len(body) - limit} B)")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("file")
    ap.add_argument("-d", "--dump", type=int, nargs="?", const=64, default=0,
                    help="hexdump pierwszych N bajtów każdego segmentu (domyślnie 64)")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    data = open(a.file, "rb").read()
    if data[:2] != b"\xff\xff":
        print("UWAGA: plik nie zaczyna się od $FFFF - to nie jest poprawny XEX", file=sys.stderr)
    try:
        segs, trailing = parse(data)
    except ValueError as e:
        print(f"BŁĄD: {e}", file=sys.stderr)
        sys.exit(1)
    print(f"{a.file}: {len(data)} B, {len(segs)} segmentów")
    covered = []
    for off, s, e, body in segs:
        tag = ""
        if (s, e) == RUNAD:
            tag = f"  RUNAD -> ${body[0] | body[1] << 8:04X}"
        elif (s, e) == INITAD:
            tag = f"  INITAD -> ${body[0] | body[1] << 8:04X}"
        elif s <= 0x02E3 and e >= 0x02E0:
            tag = "  (dotyka wektorów RUNAD/INITAD)"
        print(f"  off {off:#06x}  ${s:04X}-${e:04X}  {e - s + 1:5d} B{tag}")
        for cs, ce in covered:
            if s <= ce and e >= cs and (s, e) not in (RUNAD, INITAD):
                print(f"    ! nakłada się z ${cs:04X}-${ce:04X}")
        if (s, e) not in (RUNAD, INITAD):
            covered.append((s, e))
        if a.dump:
            hexdump(s, body, a.dump)
    if trailing:
        print(f"  UWAGA: {trailing} nadmiarowych bajtów na końcu pliku (padding/śmieci, ignorowane)")
    if not any((s, e) == RUNAD for _, s, e, _ in segs):
        print("  (brak RUNAD - program uruchomi się tylko przez INITAD lub z DOS)")


if __name__ == "__main__":
    main()
