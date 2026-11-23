#!/usr/bin/env python3
"""Generator plików CAS w formacie Turbo Blizzard (Atari XL/XE).

Format odtworzony z działających plików w TurboBlizzardCas/:
  - CAS z blokami PWM Altirry (pwms/pwmc/pwml/pwmd), 44100 Hz
  - bit 0 = impuls 8 próbek, bit 1 = 12 próbek, pilot = 22 próbki, sync = pwml(4,4) x2
  - blok 0: pauza 3000 ms, pilot 3072, bajt 00
  - nagłówek: pauza 300 ms, pilot 302, nazwa 76 znaków + suma + 00
  - dane: pauza 4000 ms (pierwszy) / 200 ms, pilot 302,
          [dł. lo, dł. hi] + 1024 B XEX + 00 + suma (mod 256 z 1027 B) + 00
  - koniec: blok krótszy niż 1024 B (gdy XEX jest wielokrotnością 1024 -> blok o dł. 0)

Użycie:
  python make_blizzard.py Gra.xex --title "NAZWA GRY" [-o wynik.cas]
  python make_blizzard.py Gra.xex --title "NAZWA" --loader   # + loader 600 bodów na początku
  python make_blizzard.py --extract plik.cas [-o wynik.xex]   # odwrotnie: CAS -> XEX
"""
import argparse
import os
import re
import struct
import sys

RATE = 44100
PWMS_AUX = 5          # tryb impulsów + kolejność bitów (jak w oryginałach)
BIT0, BIT1 = 8, 12    # szerokość impulsu dla bitu 0 / 1 (próbki)
PILOT_W = 22          # szerokość impulsu pilota
SYNC = (4, 4)         # impuls synchronizacji (pwml)
NAME_LEN = 76
BLOCK = 1024
DEFAULT_LOADER = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              'TurboBlizzardCas', 'Blizzard Turbo Loader 1.0.cas')


def chunk(cid, aux, data=b''):
    return cid.encode('ascii') + struct.pack('<HH', len(data), aux) + data


def block(pause_ms, pilot_count, payload):
    out = chunk('pwmc', pause_ms, struct.pack('<BH', PILOT_W, pilot_count))
    sync = struct.pack('<HH', *SYNC)
    out += chunk('pwml', 0, sync) * 2
    out += chunk('pwmd', BIT0 | (BIT1 << 8), payload)
    return out


def csum(data):
    return sum(data) & 0xFF


def build(xex, title, loader=None):
    """loader: zawartość CAS z loaderem Blizzarda (600 bodów) doklejana na początek taśmy."""
    name = title.upper().encode('ascii', 'replace')[:NAME_LEN].ljust(NAME_LEN, b' ')
    if loader:
        if loader[:4] != b'FUJI':
            raise ValueError('plik loadera nie jest CAS-em (brak FUJI)')
        out = loader                            # FUJI + baud + bloki data loadera
    else:
        out = b'FUJI' + struct.pack('<HH', 0, 0)
    out += chunk('pwms', PWMS_AUX, struct.pack('<H', RATE))
    out += block(3000, 3072, b'\x00')
    out += block(300, 302, name + bytes([csum(name), 0]))

    parts = [xex[i:i + BLOCK] for i in range(0, len(xex), BLOCK)]
    if not parts or len(parts[-1]) == BLOCK:
        parts.append(b'')                       # blok końcowy o długości 0
    for n, part in enumerate(parts):
        # dł. + 1024 B danych (dopełnione zerami) + bajt 00 przed sumą
        body = struct.pack('<H', len(part)) + part.ljust(BLOCK + 1, b'\x00')
        out += block(4000 if n == 0 else 200, 302, body + bytes([csum(body), 0]))
    out += chunk('pwml', 200)                   # cisza na końcu taśmy
    return out


def parse(cas):
    """Zwraca listę (nazwa, [bloki danych]) z CAS Blizzarda, sprawdzając sumy."""
    if cas[:4] != b'FUJI':
        raise ValueError('to nie jest plik CAS (brak FUJI)')
    p, datas = 0, []
    while p < len(cas):
        cid = cas[p:p + 4]
        ln, _aux = struct.unpack('<HH', cas[p + 4:p + 8])
        if cid == b'pwmd':
            datas.append(cas[p + 8:p + 8 + ln])
        p += 8 + ln
    if len(datas) < 3:
        raise ValueError('za mało bloków pwmd — to nie Turbo Blizzard?')
    hdr = datas[1]
    if csum(hdr[:-2]) != hdr[-2]:
        raise ValueError('zła suma kontrolna nagłówka')
    name = hdr[:-2].decode('ascii', 'replace').rstrip()
    xex = b''
    for i, b in enumerate(datas[2:]):
        if csum(b[:-2]) != b[-2]:
            raise ValueError(f'zła suma kontrolna bloku danych {i}')
        n = b[0] | b[1] << 8
        xex += b[2:2 + n]
        if n < BLOCK:
            break
    return name, xex


def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

    ap = argparse.ArgumentParser(description='XEX -> CAS Turbo Blizzard (i odwrotnie)')
    ap.add_argument('input')
    ap.add_argument('--title', help='nazwa gry w nagłówku (domyślnie z nazwy pliku)')
    ap.add_argument('--extract', action='store_true', help='wyciągnij XEX z CAS Blizzarda')
    ap.add_argument('--loader', nargs='?', const=DEFAULT_LOADER, metavar='CAS',
                    help='dołącz loader Blizzarda (600 bodów) na początek taśmy; '
                         'bez ścieżki = TurboBlizzardCas/Blizzard Turbo Loader 1.0.cas')
    ap.add_argument('-o', '--output')
    a = ap.parse_args()

    data = open(a.input, 'rb').read()
    base = os.path.splitext(os.path.basename(a.input))[0]

    if a.extract:
        name, xex = parse(data)
        out = a.output or base + '.xex'
        open(out, 'wb').write(xex)
        print(f'{a.input}: "{name}", XEX {len(xex)} B -> {out}')
        return

    if data[:2] != b'\xff\xff':
        print('UWAGA: plik nie zaczyna się od $FFFF — czy to na pewno XEX?', file=sys.stderr)
    title = a.title or base
    out = a.output
    if not out:
        stem = re.sub(r'[^a-z0-9_]+', '_', base.lower()).strip('_')   # jak make_tape.py
        d = os.path.join('tape', stem)
        os.makedirs(d, exist_ok=True)
        out = os.path.join(d, stem + ('_blizzard_ldr.cas' if a.loader else '_blizzard.cas'))
    loader = open(a.loader, 'rb').read() if a.loader else None
    cas = build(data, title, loader)
    open(out, 'wb').write(cas)
    nblk = len(data) // BLOCK + 1
    if loader:
        print(f'Loader: {os.path.basename(a.loader)} ({len(loader)} B, 600 bodów, ~45 s)')
    secs = len(data) * 8 * ((BIT0 + BIT1) / 2) / RATE + 3 + 4 + nblk * 0.35
    print(f'{out}: {len(cas)} B, {nblk} bloków danych, ~{secs:.0f} s ładowania')

    # weryfikacja: odczyt z powrotem
    name, back = parse(cas)
    assert back == data and name == title.upper()[:NAME_LEN].strip(), 'weryfikacja nie przeszła!'
    print(f'Weryfikacja OK: "{name}"')


if __name__ == '__main__':
    main()
