#!/usr/bin/env python3
"""Librairies KiCad du projet Halo, extraites des fichiers generes.

Lit halo/Halo.kicad_sch et halo/Halo.kicad_pcb et ecrit :
  - halo/Halo.kicad_sym : les symboles "Halo:*" embarques dans le schema
  - halo/Halo.pretty/*.kicad_mod : les empreintes "Halo:*" embarquees dans le PCB
  - halo/sym-lib-table et halo/fp-lib-table : tables de librairies du projet (${KIPRJMOD})
Sans ces fichiers, l'ERC et le DRC de kicad-cli signalent chaque symbole/empreinte
"Halo:*" comme introuvable (lib_symbol_issues, footprint_link_issues).

Usage : python3 halo/gen_kicad_sch.py && python3 halo/gen_kicad_pcb.py && python3 halo/gen_kicad_libs.py
"""
import re
from pathlib import Path

HALO = Path(__file__).resolve().parent
SCH, PCB = HALO / "Halo.kicad_sch", HALO / "Halo.kicad_pcb"
SYM_OUT, PRETTY = HALO / "Halo.kicad_sym", HALO / "Halo.pretty"
SYM_VERSION, FP_VERSION = "20251024", "20260206"     # formats des .kicad_sym et .kicad_mod de KiCad 10


def block(text, start):
    """Bloc S-expression complet a partir de la parenthese ouvrante en `start`."""
    depth, i, in_str = 0, start, False
    while True:
        c = text[i]
        if in_str:
            if c == "\\":
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1


def blocks(text, head):
    return [block(text, m.start()) for m in re.finditer(re.escape(head), text)]


# ---------------------------------------------------------------- symboles
sch = SCH.read_text()
symbols = []
for blk in blocks(sch, '(symbol "Halo:'):
    name = re.match(r'\(symbol "Halo:([^"]+)"', blk).group(1)
    symbols.append((name, blk.replace(f'(symbol "Halo:{name}"', f'(symbol "{name}"', 1)))
symbols.sort()
SYM_OUT.write_text("(kicad_symbol_lib\n\t(version %s)\n\t(generator \"gen_kicad_libs\")\n\t(generator_version \"10.0\")\n%s\n)\n"
                   % (SYM_VERSION, "\n".join(b for _, b in symbols)))

# ---------------------------------------------------------------- empreintes
pcb = PCB.read_text()
PRETTY.mkdir(exist_ok=True)
footprints = {}
for blk in blocks(pcb, '(footprint "Halo:'):
    name = re.match(r'\(footprint "Halo:([^"]+)"', blk).group(1)
    if name in footprints:
        continue
    lines = blk.split("\n")
    m = re.match(r'\s*\(at [-\d.]+ [-\d.]+(?: ([-\d.]+))?\)$', lines[3])
    rot = float(m.group(1) or 0) if m else 0.0
    out = [f'(footprint "{name}"', f"\t(version {FP_VERSION})", '\t(generator "gen_kicad_libs")', '\t(generator_version "10.0")']
    for ln in lines[1:-1]:
        s = ln.strip()
        if s.startswith("(at ") and ln is lines[3] or s.startswith("(net ") or (s.startswith("(uuid ") and ln is lines[2]):
            continue
        if s.startswith("(at "):                        # angle des pads et textes : retirer la rotation de l'instance
            a = re.match(r"\(at ([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?\)", s)
            if a and rot:
                ang = (float(a.group(3) or 0) - rot) % 360
                ln = ln[:ln.index("(at")] + f"(at {a.group(1)} {a.group(2)}" + (f" {ang:g}" if ang else "") + ")"
        ln = re.sub(r'\(property "Reference" "[^"]*"', '(property "Reference" "REF**"', ln)
        out.append(ln[1:] if ln.startswith("\t") else ln)
    out.append(")")
    footprints[name] = "\n".join(out) + "\n"
for old in PRETTY.glob("*.kicad_mod"):
    if old.stem not in footprints:
        old.unlink()
for name, txt in footprints.items():
    (PRETTY / f"{name}.kicad_mod").write_text(txt)

# ---------------------------------------------------------------- tables du projet
(HALO / "sym-lib-table").write_text('(sym_lib_table\n\t(version 7)\n\t(lib (name "Halo")(type "KiCad")(uri "${KIPRJMOD}/Halo.kicad_sym")(options "")(descr "Symboles du Halo, extraits du schema genere"))\n)\n')
(HALO / "fp-lib-table").write_text('(fp_lib_table\n\t(version 7)\n\t(lib (name "Halo")(type "KiCad")(uri "${KIPRJMOD}/Halo.pretty")(options "")(descr "Empreintes du Halo, extraites du PCB genere"))\n)\n')
print(f"{SYM_OUT.name} : {len(symbols)} symboles ; {PRETTY.name} : {len(footprints)} empreintes ; sym-lib-table, fp-lib-table")
