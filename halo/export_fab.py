#!/usr/bin/env python3
"""Dossier de fabrication du Halo : Gerbers, percage, CPL, controle de la BOM.

Sorties dans halo/GERBER_HALO/ plus halo/Halo_GERBER.zip (a envoyer a JLCPCB) :
  - Gerbers RS-274X des 9 couches utiles + carte de percage, meme jeu que la V3
  - Halo.drl : percage Excellon, memes coordonnees absolues que les Gerbers
  - Halo_CPL.csv : positions au format JLCPCB (Designator, Mid X, Mid Y, Layer,
    Rotation), DNP exclus (Q1, J2, TP1-TP4)
  - Halo_BOM_JLCPCB.csv : la BOM telle que JLCPCB l'attend, c'est CE fichier qu'on
    televerse. Les plages de references y sont developpees (C10-C33 devient
    C10,C11,...,C33) : l'outil de JLCPCB ne les comprend pas et refuse le lot
    (« designators don't exist in the BOM file »). Les DNP en sont retires, sinon
    il les cherche en vain dans le CPL.
La BOM de travail (halo/Halo_BOM.csv) est ecrite a la main, avec les references
LCSC et les notes ; c'est la source. Le script en derive la version JLCPCB et
verifie qu'elle couvre exactement les composants du schema, avec les bonnes
quantites et les bonnes empreintes.

Usage : python3 halo/export_fab.py   (a lancer apres build.sh, code retour 1 si erreur)
"""
import csv
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

HALO = Path(__file__).resolve().parent
sys.path.insert(0, str(HALO))
from gen_kicad_sch import parts  # noqa: E402

PCB = HALO / "Halo.kicad_pcb"
OUT = HALO / "GERBER_HALO"
ZIP = HALO / "Halo_GERBER.zip"
BOM = HALO / "Halo_BOM.csv"
CPL = OUT / "Halo_CPL.csv"
BOM_JLC = OUT / "Halo_BOM_JLCPCB.csv"
CLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"
LAYERS = "F.Cu,B.Cu,F.Paste,B.Paste,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts"


def run(*args):
    r = subprocess.run([CLI if Path(CLI).exists() else "kicad-cli", *args],
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"kicad-cli {' '.join(args[:2])} : {r.stderr.strip()}")
    return r.stdout


def expand(field):
    """"C10-C33" ou "SW1,SW2" -> liste de references."""
    out = []
    for part in field.split(","):
        part = part.strip()
        m = re.fullmatch(r"([A-Za-z]+)(\d+)-[A-Za-z]*(\d+)", part)
        out += [f"{m.group(1)}{i}" for i in range(int(m.group(2)), int(m.group(3)) + 1)] if m else [part]
    return out


# ---------------------------------------------------------------- Gerbers et percage
if OUT.exists():
    shutil.rmtree(OUT)
OUT.mkdir()
run("pcb", "export", "gerbers", "--layers", LAYERS, "--subtract-soldermask", "--no-x2",
    "--no-netlist", "--use-drill-file-origin", "-o", f"{OUT}/", str(PCB))
run("pcb", "export", "drill", "--format", "excellon", "--excellon-units", "mm",
    "--excellon-zeros-format", "decimal", "--drill-origin", "absolute",
    "--generate-map", "--map-format", "gerberx2", "-o", f"{OUT}/", str(PCB))

# ---------------------------------------------------------------- CPL au format JLCPCB
tmp = OUT / "pos.csv"
run("pcb", "export", "pos", "--format", "csv", "--units", "mm", "--side", "front",
    "--use-drill-file-origin", "--exclude-dnp", "-o", str(tmp), str(PCB))
rows = list(csv.DictReader(tmp.open()))
tmp.unlink()
with CPL.open("w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
    for r in sorted(rows, key=lambda r: (re.sub(r"\d", "", r["Ref"]), int(re.sub(r"\D", "", r["Ref"]) or 0))):
        w.writerow([r["Ref"], r["PosX"], r["PosY"], r["Side"], r["Rot"]])
placed = {r["Ref"] for r in rows}

# ---------------------------------------------------------------- controle de la BOM
errors, todo = [], []
sch = {p["ref"]: p for p in parts if not p["ref"].startswith("#")}
fp_of = {}   # les empreintes copiees de la V3 ne portent pas la tabulation d'indentation
for blk in re.split(r'\n\t?\(footprint "', PCB.read_text())[1:]:
    fp_of[re.search(r'\(property "Reference" "([^"]*)"', blk).group(1)] = blk[:blk.index('"')]

seen = {}
for row in csv.DictReader(BOM.open()):
    refs = expand(row["Designator"])
    if len(refs) != int(row["Quantity"] or 0) and not row["Comment"].startswith("DNP"):
        errors.append(f"BOM {row['Comment']} : {len(refs)} references pour une quantite de {row['Quantity']}")
    for ref in refs:
        if ref in seen:
            errors.append(f"{ref} apparait deux fois dans la BOM")
        seen[ref] = row

for ref in sorted(sch):
    if ref not in seen:
        errors.append(f"{ref} est au schema mais absent de la BOM")
for ref in sorted(seen):
    if ref not in sch:
        errors.append(f"{ref} est dans la BOM mais absent du schema")
    elif not seen[ref]["LCSC Part #"] and not seen[ref]["Comment"].startswith("DNP"):
        todo.append(f"{ref} ({seen[ref]['Comment']}) : reference LCSC a choisir sur jlcpcb.com/parts")

for ref, row in sorted(seen.items()):
    if ref in sch and row["Footprint"].split(":")[-1] not in fp_of.get(ref, ""):
        errors.append(f"{ref} : BOM dit '{row['Footprint']}', le PCB porte '{fp_of.get(ref, '?')}'")

# ---------------------------------------------------------------- BOM au format JLCPCB
with BOM_JLC.open("w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["Comment", "Designator", "Footprint", "Quantity", "LCSC Part #"])
    n_jlc = 0
    for row in csv.DictReader(BOM.open()):
        refs = [r for r in expand(row["Designator"]) if r in placed]
        if not refs:
            continue                      # ligne entierement DNP : hors du lot d'assemblage
        n_jlc += len(refs)
        w.writerow([row["Comment"], ",".join(refs), row["Footprint"], len(refs), row["LCSC Part #"]])

jlc_refs = {r for row in csv.DictReader(BOM_JLC.open()) for r in row["Designator"].split(",")}
for ref in sorted(placed - jlc_refs):
    errors.append(f"{ref} est dans le CPL mais absent de la BOM JLCPCB")
for ref in sorted(jlc_refs - placed):
    errors.append(f"{ref} est dans la BOM JLCPCB mais absent du CPL")

to_place = {r for r in sch if not sch[r]["dnp"] and not r.startswith("TP")}
for ref in sorted(to_place - placed):
    errors.append(f"{ref} est a poser mais absent du CPL")
for ref in sorted(placed - to_place):
    errors.append(f"{ref} est dans le CPL alors qu'il est DNP")

# ---------------------------------------------------------------- archive et rapport
with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(OUT.iterdir()):
        if f.suffix.lower() in (".gbl", ".gtl", ".gbs", ".gts", ".gbo", ".gto", ".gbp", ".gtp", ".gm1", ".gbr", ".drl"):
            z.write(f, f.name)

print(f"{OUT.relative_to(HALO.parent)} : {len(list(OUT.iterdir()))} fichiers, "
      f"{ZIP.name} {ZIP.stat().st_size // 1024} Ko")
print(f"{CPL.name} : {len(placed)} composants a poser "
      f"({', '.join(sorted(r for r in sch if sch[r]['dnp']))} en DNP, non poses)")
print(f"{BOM.name} : {len(seen)} references ; {BOM_JLC.name} : {n_jlc} references a poser, plages developpees")
if todo:
    print(f"\n{len(todo)} reference(s) LCSC a completer avant de commander l'assemblage :")
    for t in todo:
        print("  ", t)
if errors:
    print(f"\n{len(errors)} probleme(s) :")
    for e in errors:
        print("  ", e)
    sys.exit(1)
print("\nBOM, CPL et PCB concordent." + (" Reste les references LCSC ci-dessus." if todo else ""))
