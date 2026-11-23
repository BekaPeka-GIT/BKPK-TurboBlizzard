#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_cas.py - składa plik CAS (kaseta Atari 8-bit, normalna prędkość 600 bodów)
z loadera boot (surowy plik z MADS) i pliku XEX.

Układ taśmy:
  [rekordy boot = loader]    system ładuje sam (START przy włączaniu)
  [długa przerwa ~20 s]      czas na wyświetlenie tytułu i otwarcie C:
  [rekordy pliku XEX]        czyta loader przez C: (ostatni częściowy = $FA)
  [rekord EOF = $FE]

Użycie:
  python build_cas.py riverraid_tape.bin RiverRaid.xex riverraid.cas
"""
import argparse
import struct
import sys

REC = 128
CTRL_FULL, CTRL_PARTIAL, CTRL_EOF = 0xFC, 0xFA, 0xFE
BOOT_LOAD = 0x0600


def checksum(data):
    """Suma 8-bitowa z przeniesieniem (end-around carry) po sync+control+dane."""
    s = 0
    for b in data:
        s += b
        if s > 255:
            s = (s & 255) + 1
    return s


def record(ctrl, payload):
    assert len(payload) == REC
    r = bytes([0x55, 0x55, ctrl]) + payload
    return r + bytes([checksum(r)])


def chunk(tag, aux, data=b""):
    return tag + struct.pack("<HH", len(data), aux) + data


def xex_segments(xex):
    """Zwraca (lista segmentów, offset końca poprawnych danych).
    Zerowy 'segment' $0000-$0000 oraz niekompletne dane na końcu to śmieci."""
    i, segs, end = 0, [], 0
    while i + 2 <= len(xex):
        start = xex[i] | xex[i + 1] << 8
        if start == 0xFFFF:
            i += 2
            continue
        if i + 4 > len(xex):
            break
        last = xex[i + 2] | xex[i + 3] << 8
        if last < start or (start == 0 and last == 0):
            break
        n = last - start + 1
        if i + 4 + n > len(xex):
            break
        segs.append((start, last))
        i += 4 + n
        end = i
    return segs, end


def split_records(stream):
    """Dzieli strumień pliku na rekordy: pełne $FC, ostatni częściowy $FA."""
    recs = []
    for off in range(0, len(stream), REC):
        part = stream[off:off + REC]
        if len(part) == REC:
            recs.append((CTRL_FULL, part))
        else:
            pad = part + bytes(REC - len(part))
            pad = pad[:REC - 1] + bytes([len(part)])  # liczba ważnych bajtów w ostatnim bajcie
            recs.append((CTRL_PARTIAL, pad))
    recs.append((CTRL_EOF, bytes(REC)))
    return recs


def boot_cas(loader, irg_first, irg, desc, load_expect=BOOT_LOAD):
    """Początek taśmy: FUJI + baud + rekordy boot loadera + EOF.
    Zwraca (bajty CAS, liczba rekordów boot)."""
    if loader[0] != 0:
        sys.exit("BLAD: pierwszy bajt naglowka boot powinien byc 0")
    nboot = loader[1]
    load = loader[2] | loader[3] << 8
    padded = loader + bytes(-len(loader) % REC)
    if nboot != len(padded) // REC:
        sys.exit("BLAD: licznik rekordow boot (%d) != rozmiar loadera (%d rek.)"
                 % (nboot, len(padded) // REC))
    if load != load_expect:
        sys.exit("BLAD: adres ladowania $%04X (oczekiwano $%04X)" % (load, load_expect))
    out = chunk(b"FUJI", 0, desc.encode("ascii", "replace"))
    out += chunk(b"baud", 600)
    for k in range(nboot):
        out += chunk(b"data", irg_first if k == 0 else irg,
                     record(CTRL_FULL, padded[k * REC:(k + 1) * REC]))
    out += chunk(b"data", irg, record(CTRL_EOF, bytes(REC)))   # EOF konczacy plik boot
    return out, nboot


def build(loader, xex, irg_first, irg, desc, irg_file=None, load=BOOT_LOAD):
    if irg_file is None:
        irg_file = irg_first
    segs, end = xex_segments(xex)
    if not segs:
        sys.exit("BLAD: w pliku XEX nie znaleziono segmentow")
    stream = xex[:end]

    # --- loader: sprawdź nagłówek boot i dopełnij do pełnych rekordów ---
    if loader[0] != 0:
        sys.exit("BLAD: pierwszy bajt naglowka boot powinien byc 0")
    nboot = loader[1]
    load_addr = loader[2] | loader[3] << 8
    padded = loader + bytes(-len(loader) % REC)
    if nboot != len(padded) // REC:
        sys.exit("BLAD: licznik rekordow boot (%d) != rozmiar loadera (%d rek.)"
                 % (nboot, len(padded) // REC))
    if load_addr != load:
        sys.exit("BLAD: adres ladowania $%04X (oczekiwano $%04X)" % (load_addr, load))

    out = chunk(b"FUJI", 0, desc.encode("ascii", "replace"))
    out += chunk(b"baud", 600)
    boot_recs = [(CTRL_FULL, padded[o:o + REC]) for o in range(0, len(padded), REC)]
    file_recs = split_records(stream)

    first = True
    for ctrl, payload in boot_recs:
        out += chunk(b"data", irg_first if first else irg, record(ctrl, payload))
        first = False
    out += chunk(b"data", irg, record(CTRL_EOF, bytes(REC)))   # EOF konczacy plik boot
    first = True
    for ctrl, payload in file_recs:
        out += chunk(b"data", irg_file if first else irg, record(ctrl, payload))
        first = False

    n_rec = len(boot_recs) + len(file_recs)
    secs = 2 * irg_first / 1000 + (n_rec - 2) * irg / 1000 + n_rec * 132 * 10 / 600
    return out, dict(segs=segs, xex_len=len(xex), stream_len=len(stream),
                     nboot=len(boot_recs), nfile=len(file_recs), seconds=secs,
                     stream=stream, loader_len=len(loader))


def verify(cas, info):
    """Czyta plik CAS jak system: boot (nboot rekordów), potem plik do rekordu EOF."""
    i, data = 0, []
    first = True
    while i + 8 <= len(cas):
        tag = cas[i:i + 4]
        ln, aux = struct.unpack("<HH", cas[i + 4:i + 8])
        body = cas[i + 8:i + 8 + ln]
        i += 8 + ln
        if first:
            assert tag == b"FUJI", "pierwszy chunk musi byc FUJI"
            first = False
        if tag == b"data":
            data.append(body)
    assert i == len(cas), "smieci na koncu pliku CAS"
    for k, r in enumerate(data):
        assert len(r) == 132 and r[:2] == b"\x55\x55", "rekord %d: zly format" % k
        assert checksum(r[:131]) == r[131], "rekord %d: zla suma kontrolna" % k
    nboot = info["nboot"]
    boot = b"".join(r[3:131] for r in data[:nboot])
    assert boot[1] == nboot, "licznik rekordow boot w naglowku"
    assert all(r[2] == CTRL_FULL for r in data[:nboot]), "rekordy boot musza byc pelne"
    got = b""
    assert data[nboot][2] == CTRL_EOF, "po rekordach boot brak rekordu EOF"
    for k, r in enumerate(data[nboot + 1:]):
        ctrl = r[2]
        if ctrl == CTRL_EOF:
            assert k == len(data) - nboot - 2, "EOF nie na koncu"
            break
        if ctrl == CTRL_FULL:
            got += r[3:131]
        elif ctrl == CTRL_PARTIAL:
            got += r[3:3 + r[130]]
        else:
            raise AssertionError("nieznany bajt kontrolny %02X" % ctrl)
    else:
        raise AssertionError("brak rekordu EOF")
    assert got == info["stream"], "dane z tasmy rozni sie od XEX"
    return len(data)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("loader", help="surowy loader boot (z MADS, opt h-)")
    ap.add_argument("xex", help="plik XEX z gra")
    ap.add_argument("cas", help="wyjsciowy plik CAS")
    ap.add_argument("--irg-first", type=int, default=20000,
                    help="przerwa przed pierwszym rekordem bloku w ms (domyslnie 20000)")
    ap.add_argument("--irg", type=int, default=250,
                    help="przerwa miedzy rekordami w ms (domyslnie 250)")
    ap.add_argument("--irg-file", type=int, default=20000,
                    help="przerwa przed pierwszym rekordem pliku XEX w ms (domyslnie 20000)")
    ap.add_argument("--desc", default="River Raid", help="opis kasety (chunk FUJI)")
    a = ap.parse_args()

    loader = open(a.loader, "rb").read()
    xex = open(a.xex, "rb").read()
    cas, info = build(loader, xex, a.irg_first, a.irg, a.desc, a.irg_file)
    n = verify(cas, info)
    open(a.cas, "wb").write(cas)

    print("loader: %d B -> %d rekord(y) boot" % (info["loader_len"], info["nboot"]))
    print("XEX: %d B, uzyte %d B (obcieto %d B), segmenty: %s"
          % (info["xex_len"], info["stream_len"], info["xex_len"] - info["stream_len"],
             ", ".join("$%04X-$%04X" % s for s in info["segs"])))
    print("rekordy: %d (w tym plik: %d z EOF), CAS: %d B" % (n, info["nfile"], len(cas)))
    print("weryfikacja OK, czas odczytu ok. %d min %02d s" % divmod(int(info["seconds"]), 60))


if __name__ == "__main__":
    main()
