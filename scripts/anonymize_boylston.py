#!/usr/bin/env python3
"""Pseudonymize the Boylston SwissSys 2C packages and their US Chess rated records.

usage: anonymize_boylston.py SOURCE_DIR USCF_JSON OUT_DIR

SOURCE_DIR holds one folder per event with thexport/tsexport/tdexport.dbf as
SwissSys wrote them (and US Chess MUIR accepted them). USCF_JSON is the cached
rated record keyed by the same folder names. For each event this writes
OUT_DIR/<slug>/{THEXPORT,TSEXPORT,TDEXPORT}.DBF and OUT_DIR/<slug>/uscf.json.

The DBFs are patched in place, so every byte is identical to the source except:
  * every US Chess member ID (D_MEM_ID and the TD ID fields) -> a synthetic
    9xxxxxxx ID from ONE mapping shared by all events and the rated record;
  * D_NAME -> a synthetic name that keeps the original's format quirks
    (case style, 'LAST,FIRST' vs 'Last, First' vs 'First Last', a TAB after the
    comma, multi-word surnames, a middle name);
  * H_AFF_ID -> A9999999.
Header garbage, descriptors, the year byte, record order and EOF are untouched.

Standard library only. Deterministic: the same input always yields the same output.
"""
import json
from pathlib import Path
import re
import struct
import sys

EVENTS = ('April Ladder', 'Fall Equinox Swiss', 'March Quads', 'May Ladder',
          'Rated Friday Night Blitz', 'SpringFestival', 'Tornado #147')
TD_FIELDS = ('H_CTD_ID', 'H_ATD_ID', 'H_OTHER_TD', 'S_CTD_ID', 'S_ATD_ID')
MEMBER = re.compile(rb'\d{8}')


def slug(name):
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


class Table:
    """A DBF file as raw bytes plus the byte span of every cell."""

    def __init__(self, path):
        self.raw = bytearray(Path(path).read_bytes())
        count, self.header, self.size = struct.unpack_from('<IHH', self.raw, 4)
        self.fields, at, offset = [], 32, 1
        while self.raw[at] != 0x0D:
            name = bytes(self.raw[at:at + 11]).split(b'\0')[0].decode('ascii')
            width = self.raw[at + 16]
            self.fields.append((name, offset, width))
            offset += width
            at += 32
        self.count = count

    def spans(self, row):
        base = self.header + row * self.size
        return {name: (base + off, width) for name, off, width in self.fields}

    def get(self, row, field):
        at, width = self.spans(row)[field]
        return bytes(self.raw[at:at + width])

    def put(self, row, field, value):
        at, width = self.spans(row)[field]
        if len(value) > width:
            raise ValueError(f'{field}: {value!r} wider than {width}')
        self.raw[at:at + width] = value.ljust(width, b' ')


class Identities:
    """One global real-ID -> synthetic-ID mapping, assigned in first-seen order."""

    def __init__(self):
        self.ids = {}

    def member(self, real):
        real = real.strip()
        if not real:
            return real
        if real not in self.ids:
            self.ids[real] = f'9{len(self.ids) + 1:07d}'
        return self.ids[real]

    def token(self, real):
        return f'Given{int(self.member(real)[1:]):04d}'


def styled(template, original):
    """Copy the original word's per-position letter case onto the template."""
    letters = [c for c in original if c.isalpha()] or ['A']
    out = []
    for i, ch in enumerate(template):
        model = letters[min(i, len(letters) - 1)]
        out.append(ch.upper() if model.isupper() else ch.lower())
    return ''.join(out)


def synthetic_name(original, token):
    """Same shape as `original`, none of its content."""
    def word(template, model):
        text = styled(template, model)
        return text + '.' if model.endswith('.') else text

    def surname(words):
        return ' '.join(word('Player' if i == 0 else 'Extra', w) for i, w in enumerate(words))

    if ',' in original:
        last, rest = original.split(',', 1)
        sep = rest[:len(rest) - len(rest.lstrip())]
        given = rest.split()
        out = surname(last.split()) + ',' + sep
        if given:
            out += word(token, given[0])
        out += ''.join(' ' + word('M', w) for w in given[1:])
        return out
    words = original.split()
    if not words:
        return original
    if len(words) == 1:
        return word('Player', words[0])
    middles = ''.join(' ' + word('M', w) for w in words[1:-1])
    return word(token, words[0]) + middles + ' ' + word('Player', words[-1])


def anonymize_event(folder, ids):
    tables = {name: Table(folder / f'{name.lower()}.dbf') for name in ('THEXPORT', 'TSEXPORT', 'TDEXPORT')}
    th, ts, td = tables['THEXPORT'], tables['TSEXPORT'], tables['TDEXPORT']
    for table in (th, ts):
        names = {f[0] for f in table.fields}
        for row in range(table.count):
            for field in TD_FIELDS:
                if field in names:
                    value = table.get(row, field)
                    table.put(row, field, MEMBER.sub(lambda m: ids.member(m[0].decode()).encode(), value).rstrip(b' '))
    th.put(0, 'H_AFF_ID', b'A9999999')
    for row in range(td.count):
        real = td.get(row, 'D_MEM_ID').decode('ascii')
        if real.strip() and not re.fullmatch(r'\d{8}', real.strip()):
            raise ValueError(f'{folder.name}: unexpected member ID {real!r}')
        name = td.get(row, 'D_NAME').decode('latin-1').rstrip(' ')
        key = real.strip() or f'{folder.name}/{td.get(row, "D_SEC_NUM")}/{td.get(row, "D_PAIR_NUM")}'
        td.put(row, 'D_MEM_ID', ids.member(real).encode('ascii') if real.strip() else b'')
        td.put(row, 'D_NAME', synthetic_name(name, ids.token(key)).encode('latin-1'))
    return {name: bytes(t.raw) for name, t in tables.items()}


def reduce_uscf(event, ids):
    sections = []
    for entry in event['sections']:
        meta, standings = entry['section'], entry['standings']
        if standings.get('hasNextPage') or standings.get('hasPreviousPage'):
            raise ValueError(f"{meta['name']}: paged standings not supported")
        players = []
        for item in sorted(standings['items'], key=lambda i: i['pairingNumber']):
            players.append({
                'memberId': ids.member(item['memberId']),
                'pairingNumber': item['pairingNumber'],
                'score': item['score'],
                'rounds': [{'round': o['roundNumber'], 'outcome': o['outcome'], 'color': o.get('color'),
                            'opponentMemberId': ids.member(o['opponentMemberId']) if o.get('opponentMemberId') else None}
                           for o in sorted(item['roundOutcomes'], key=lambda o: o['roundNumber'])],
            })
        sections.append({key: meta[key] for key in ('number', 'name', 'roundCount', 'playerCount',
                                                      'ratingSystem', 'format', 'timeControl')} | {'players': players})
    officials = [{'memberId': ids.member(o['memberId']), 'office': o['office'], 'officeType': o['officeType'],
                  'sectionNumber': o.get('sectionNumber')} for o in event['officials']]
    ev = event['event']
    return {'event': {'name': ev['name'], 'startDate': ev['startDate'], 'endDate': ev['endDate'],
                      'status': ev.get('status')},
            'sections': sections, 'officials': officials}


def main(argv):
    if len(argv) != 4:
        sys.exit(__doc__)
    source, uscf_path, out = Path(argv[1]), Path(argv[2]), Path(argv[3])
    uscf = json.loads(uscf_path.read_text())
    ids = Identities()
    packages = {}
    # DBFs first (all events), then the rated record, so mapping order is stable.
    for name in EVENTS:
        packages[name] = anonymize_event(source / name, ids)
    for name in EVENTS:
        target = out / slug(name)
        target.mkdir(parents=True, exist_ok=True)
        for table, raw in packages[name].items():
            (target / f'{table}.DBF').write_bytes(raw)
        reduced = reduce_uscf(uscf[name], ids)
        (target / 'uscf.json').write_text(json.dumps(reduced, indent=1) + '\n')
    print(f'{len(EVENTS)} events, {len(ids.ids)} member IDs mapped -> {out}')


if __name__ == '__main__':
    main(sys.argv)
