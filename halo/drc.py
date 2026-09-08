#!/usr/bin/env python3
"""DRC programmatique de halo/Halo.kicad_pcb (pas de kicad-cli >= 8 sous la main).

Reproduit les regles par defaut de KiCad (aucune regle n'est definie dans le setup) :
  - isolation cuivre/cuivre entre nets differents : 0.2 mm
  - largeur de piste mini : 0.2 mm
  - cuivre -> bord de carte : 0.5 mm
  - trou -> cuivre d'un autre net : 0.25 mm
  - courtyards qui se chevauchent
  - connectivite : chaque net doit former un seul ilot (pistes + zones GND remplies)
  - zone antenne (Cmts) : pas de cuivre sous l'antenne du module

Le remplissage des zones GND est recalcule ici (zone - cuivre des autres nets
dilate de 0.25) pour savoir quels pads GND sont reellement relies sur F.Cu.

Usage : python3 halo/drc.py [--verbose]   (code retour 1 s'il y a des erreurs)
"""
import math
import sys
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union
from shapely.strtree import STRtree
from shapely import affinity

PCB = Path(__file__).resolve().parent / "Halo.kicad_pcb"
CLEARANCE, MIN_TRACK, EDGE_CL, HOLE_CL = 0.2, 0.2, 0.5, 0.25
ZONE_CL, ZONE_MIN_W = 0.25, 0.2
ANT = box(150 - 8, 105 - 35, 150 + 8, 105 - 26.9)     # encoche antenne, = ANT_NOTCH de gen_kicad_pcb.py
EPS = 1e-3

# ---------------------------------------------------------------- S-expressions
def parse(text):
    i, n = 0, len(text)
    def node():
        nonlocal i
        i += 1
        out = []
        while True:
            while text[i].isspace():
                i += 1
            c = text[i]
            if c == ")":
                i += 1
                return out
            if c == "(":
                out.append(node())
            elif c == '"':
                j = text.index('"', i + 1)
                out.append(text[i + 1:j]); i = j + 1
            else:
                j = i
                while not text[j].isspace() and text[j] not in "()":
                    j += 1
                out.append(text[i:j]); i = j
    while text[i] != "(":
        i += 1
    return node()

def kids(node, key):
    return [k for k in node if isinstance(k, list) and k and k[0] == key]

def kid(node, key, default=None):
    k = kids(node, key)
    return k[0] if k else default

def f(x):
    return float(x)

# ---------------------------------------------------------------- geometrie
def rot(x, y, a):          # convention KiCad, y vers le bas
    a = math.radians(a)
    return x * math.cos(a) + y * math.sin(a), -x * math.sin(a) + y * math.cos(a)

def pad_shape(shape, sx, sy, rratio=0.25):
    if shape == "circle":
        return Point(0, 0).buffer(sx / 2, 16)
    if shape == "oval":
        L, w = max(sx, sy), min(sx, sy)
        seg = LineString([(-(L - w) / 2, 0), ((L - w) / 2, 0)]) if sx >= sy else LineString([(0, -(L - w) / 2), (0, (L - w) / 2)])
        return seg.buffer(w / 2, 16)
    if shape == "roundrect":
        r = rratio * min(sx, sy)
        return box(-sx / 2 + r, -sy / 2 + r, sx / 2 - r, sy / 2 - r).buffer(r, 8)
    return box(-sx / 2, -sy / 2, sx / 2, sy / 2)

def place(geom, x, y, a):
    g = affinity.rotate(geom, -a, origin=(0, 0)) if a else geom     # y vers le bas : angle KiCad = -angle shapely
    return affinity.translate(g, x, y)

def arc_points(p1, pm, p2, n=24):
    (x1, y1), (x2, y2), (x3, y3) = p1, pm, p2
    d = 2 * (x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2))
    if abs(d) < 1e-9:
        return [p1, p2]
    ux = ((x1**2 + y1**2) * (y2 - y3) + (x2**2 + y2**2) * (y3 - y1) + (x3**2 + y3**2) * (y1 - y2)) / d
    uy = ((x1**2 + y1**2) * (x3 - x2) + (x2**2 + y2**2) * (x1 - x3) + (x3**2 + y3**2) * (x2 - x1)) / d
    r = math.hypot(x1 - ux, y1 - uy)
    a1, am, a2 = (math.atan2(y - uy, x - ux) for x, y in (p1, pm, p2))
    # sens : celui qui passe par am
    def sweep(a, b, ccw):
        d = (b - a) % (2 * math.pi)
        return d if ccw else d - 2 * math.pi
    ccw = abs(sweep(a1, am, True)) < abs(sweep(a1, a2, True)) if sweep(a1, a2, True) else True
    s = sweep(a1, a2, ccw)
    if not (abs(sweep(a1, am, ccw)) <= abs(s) + 1e-9):
        ccw = not ccw; s = sweep(a1, a2, ccw)
    n = max(n, int(abs(s) * r / 0.5))
    return [(ux + r * math.cos(a1 + s * k / n), uy + r * math.sin(a1 + s * k / n)) for k in range(n + 1)]

# ---------------------------------------------------------------- lecture du PCB
class Item:
    __slots__ = ("kind", "ref", "pad", "net", "layers", "geom", "width", "hole", "desc")
    def __init__(self, kind, ref, pad, net, layers, geom, width=None, hole=None):
        self.kind, self.ref, self.pad, self.net, self.layers, self.geom, self.width, self.hole = kind, ref, pad, net, layers, geom, width, hole
        self.desc = f"{kind} {ref}{'.' + pad if pad else ''} [{net or 'sans net'}]"

def layers_of(names):
    out = set()
    for l in names:
        if l in ("*.Cu", "F&B.Cu"):
            out |= {"F.Cu", "B.Cu"}
        elif l.endswith(".Cu"):
            out.add(l)
    return out

def load(path):
    doc = parse(path.read_text())
    items, courtyards, edge, zones_def, npth = [], {}, [], [], []
    anon = [0]
    for fp in kids(doc, "footprint"):
        at = kid(fp, "at"); fx, fy = f(at[1]), f(at[2]); fr = f(at[3]) if len(at) > 3 else 0.0
        ref = next((p[2] for p in kids(fp, "property") if p[1] == "Reference"), "?")
        cy = []
        for g in fp:
            if not isinstance(g, list):
                continue
            lay = kid(g, "layer")
            if not lay or lay[1] != "F.CrtYd":
                continue
            if g[0] == "fp_rect":
                s, e = kid(g, "start"), kid(g, "end")
                pts = [(f(s[1]), f(s[2])), (f(e[1]), f(s[2])), (f(e[1]), f(e[2])), (f(s[1]), f(e[2]))]
                cy.append(Polygon([rot(x, y, fr) for x, y in pts]))
            elif g[0] == "fp_line":
                s, e = kid(g, "start"), kid(g, "end")
                cy.append(LineString([rot(f(s[1]), f(s[2]), fr), rot(f(e[1]), f(e[2]), fr)]).buffer(0.01))
            elif g[0] == "fp_circle":
                c, e = kid(g, "center"), kid(g, "end")
                r = math.hypot(f(e[1]) - f(c[1]), f(e[2]) - f(c[2]))
                cy.append(Point(rot(f(c[1]), f(c[2]), fr)).buffer(r, 16))
            elif g[0] == "fp_poly":
                pts = [(f(p[1]), f(p[2])) for p in kids(kid(g, "pts"), "xy")]
                cy.append(Polygon([rot(x, y, fr) for x, y in pts]))
        if cy:
            courtyards[ref] = affinity.translate(unary_union(cy).convex_hull, fx, fy)
        for pad in kids(fp, "pad"):
            num, ptype, shape = pad[1], pad[2], pad[3]
            at = kid(pad, "at"); px, py = f(at[1]), f(at[2]); pa = f(at[3]) if len(at) > 3 else 0.0
            sz = kid(pad, "size"); sx, sy = f(sz[1]), f(sz[2])
            rr = kid(pad, "roundrect_rratio"); rr = f(rr[1]) if rr else 0.25
            dx, dy = rot(px, py, fr)
            ax, ay = fx + dx, fy + dy
            geom = place(pad_shape(shape, sx, sy, rr), ax, ay, pa)
            net = kid(pad, "net"); net = net[1] if net else None
            drill = kid(pad, "drill")
            hole = None
            if drill:
                if drill[1] == "oval":
                    hole = place(pad_shape("oval", f(drill[2]), f(drill[3])), ax, ay, pa)
                else:
                    hole = Point(ax, ay).buffer(f(drill[1]) / 2, 16)
            if ptype == "np_thru_hole":
                npth.append(Item("trou", ref, num, None, set(), hole, hole=hole))
                continue
            if not net:
                anon[0] += 1; net = f"__nc{anon[0]}"
            lays = layers_of(kid(pad, "layers")[1:])
            items.append(Item("pad", ref, num, net, lays, geom, hole=hole))
    for seg in kids(doc, "segment"):
        s, e = kid(seg, "start"), kid(seg, "end"); w = f(kid(seg, "width")[1])
        g = LineString([(f(s[1]), f(s[2])), (f(e[1]), f(e[2]))]).buffer(w / 2, 16)
        items.append(Item("piste", "", None, kid(seg, "net")[1], {kid(seg, "layer")[1]}, g, width=w))
    for arc in kids(doc, "arc"):
        s, m, e = (kid(arc, k) for k in ("start", "mid", "end")); w = f(kid(arc, "width")[1])
        pts = arc_points((f(s[1]), f(s[2])), (f(m[1]), f(m[2])), (f(e[1]), f(e[2])))
        items.append(Item("arc", "", None, kid(arc, "net")[1], {kid(arc, "layer")[1]}, LineString(pts).buffer(w / 2, 16), width=w))
    for via in kids(doc, "via"):
        at = kid(via, "at"); sz = f(kid(via, "size")[1]); d = f(kid(via, "drill")[1])
        g = Point(f(at[1]), f(at[2])).buffer(sz / 2, 16)
        items.append(Item("via", "", None, kid(via, "net")[1], {"F.Cu", "B.Cu"}, g, hole=Point(f(at[1]), f(at[2])).buffer(d / 2, 16)))
    for z in kids(doc, "zone"):
        pts = [(f(p[1]), f(p[2])) for p in kids(kid(kid(z, "polygon"), "pts"), "xy")]
        zones_def.append((kid(z, "net")[1], kid(z, "layer")[1], Polygon(pts)))
    for g in kids(doc, "gr_line") + kids(doc, "gr_arc"):
        if kid(g, "layer")[1] != "Edge.Cuts":
            continue
        s, e = kid(g, "start"), kid(g, "end")
        if g[0] == "gr_line":
            edge.append([(f(s[1]), f(s[2])), (f(e[1]), f(e[2]))])
        else:
            m = kid(g, "mid")
            edge.append(arc_points((f(s[1]), f(s[2])), (f(m[1]), f(m[2])), (f(e[1]), f(e[2]))))
    return items, courtyards, edge, zones_def, npth

def board_polygon(edge):
    """Chaine les segments/arcs du contour en un polygone ferme."""
    chains = [list(c) for c in edge]
    out = chains.pop(0)
    while chains:
        for k, c in enumerate(chains):
            if math.dist(out[-1], c[0]) < 0.01:
                out += c[1:]; chains.pop(k); break
            if math.dist(out[-1], c[-1]) < 0.01:
                out += c[-2::-1]; chains.pop(k); break
        else:
            raise ValueError("contour Edge.Cuts non ferme")
    return Polygon(out)

# ---------------------------------------------------------------- controles
def main():
    verbose = "--verbose" in sys.argv
    items, courtyards, edge, zones_def, npth = load(PCB)
    board = board_polygon(edge)
    errors, warnings = [], []

    # 1. isolation cuivre entre nets differents, par couche
    for layer in ("F.Cu", "B.Cu"):
        lay_items = [it for it in items if layer in it.layers]
        tree = STRtree([it.geom for it in lay_items])
        seen = set()
        for i, it in enumerate(lay_items):
            for j in tree.query(it.geom.buffer(CLEARANCE + 0.05)):
                j = int(j)
                if j <= i or lay_items[j].net == it.net:
                    continue
                d = it.geom.distance(lay_items[j].geom)
                if d < CLEARANCE - EPS:
                    key = (i, j)
                    if key not in seen:
                        seen.add(key)
                        errors.append(f"isolation {d:.3f} < {CLEARANCE} mm sur {layer} : {it.desc} <-> {lay_items[j].desc}")

    # 2. largeur de piste
    for it in items:
        if it.width is not None and it.width < MIN_TRACK - EPS:
            errors.append(f"piste {it.width} mm < {MIN_TRACK} mm : {it.desc}")

    # 3. cuivre -> bord
    inner = board.buffer(-EDGE_CL)
    for it in items:
        if not inner.contains(it.geom):
            d = it.geom.distance(board.exterior)
            errors.append(f"cuivre a {d:.3f} mm du bord (< {EDGE_CL}) : {it.desc}")

    # 4. trous -> cuivre d'un autre net (trous non plaques : tout cuivre)
    for h in npth:
        for it in items:
            d = h.geom.distance(it.geom)
            if d < HOLE_CL - EPS:
                errors.append(f"trou {h.ref} a {d:.3f} mm du cuivre (< {HOLE_CL}) : {it.desc}")
    for it in items:
        if it.hole is None:
            continue
        for other in items:
            if other is it or other.net == it.net:
                continue
            d = it.hole.distance(other.geom)
            if d < HOLE_CL - EPS:
                errors.append(f"percage de {it.desc} a {d:.3f} mm de {other.desc} (< {HOLE_CL})")

    # 5. courtyards
    refs = sorted(courtyards)
    for a in range(len(refs)):
        for b in range(a + 1, len(refs)):
            if courtyards[refs[a]].intersects(courtyards[refs[b]]):
                inter = courtyards[refs[a]].intersection(courtyards[refs[b]]).area
                if inter > 1e-4:
                    errors.append(f"courtyards {refs[a]} / {refs[b]} se chevauchent ({inter:.2f} mm2)")
    missing = sorted({it.ref for it in items if it.kind == "pad"} - set(refs))
    if missing:
        warnings.append(f"empreintes sans courtyard : {', '.join(missing)}")

    # 6. contours de zone valides (KiCad refuse les auto-intersections)
    from shapely.validation import explain_validity, make_valid
    fixed = []
    for net, layer, poly in zones_def:
        if not poly.is_valid:
            errors.append(f"contour de zone {net} {layer} invalide : {explain_validity(poly)}")
            poly = make_valid(poly)
        fixed.append((net, layer, poly))
    zones_def = fixed

    # 6b. remplissage des zones (zone - cuivre autres nets dilate de ZONE_CL, ouverture ZONE_MIN_W)
    fills = {}   # (net, layer) -> liste de regions
    for net, layer, poly in zones_def:
        obstacles = [it.geom.buffer(ZONE_CL) for it in items if layer in it.layers and it.net != net]
        obstacles += [h.geom.buffer(HOLE_CL) for h in npth]
        fill = poly.intersection(board.buffer(-EDGE_CL)).difference(unary_union(obstacles))
        fill = fill.buffer(-ZONE_MIN_W / 2).buffer(ZONE_MIN_W / 2)
        regions = list(fill.geoms) if fill.geom_type == "MultiPolygon" else [fill]
        fills[(net, layer)] = [r for r in regions if not r.is_empty]

    # 7. connectivite : union-find sur pads + pistes (+ regions de zone)
    parent = list(range(len(items)))
    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]; a = parent[a]
        return a
    def union(a, b):
        parent[find(a)] = find(b)
    by_net = {}
    for i, it in enumerate(items):
        by_net.setdefault(it.net, []).append(i)
    for net, idx in by_net.items():
        for layer in ("F.Cu", "B.Cu"):
            li = [i for i in idx if layer in items[i].layers]
            tree = STRtree([items[i].geom for i in li])
            for k, i in enumerate(li):
                for j in tree.query(items[i].geom):
                    j = li[int(j)]
                    if j != i and items[i].geom.intersects(items[j].geom):
                        union(i, j)
            for region in fills.get((net, layer), []):
                touching = [i for i in li if items[i].geom.intersects(region)]
                for i in touching[1:]:
                    union(touching[0], i)
    unrouted = []
    for net, idx in sorted(by_net.items()):
        if net.startswith("__nc"):
            continue
        comps = {}
        for i in idx:
            comps.setdefault(find(i), []).append(items[i].desc)
        if len(comps) > 1:
            pads = [c for c in comps.values()]
            pads.sort(key=len, reverse=True)
            unrouted.append((net, len(comps), [", ".join(p for p in c if p.startswith("pad")) or c[0] for c in pads[1:]]))
    for net, n, isolated in unrouted:
        errors.append(f"net {net} en {n} ilots ; non relies : " + " | ".join(isolated))

    # 8. ilots de zone sans connexion (seront supprimes par KiCad, info) et pads GND hors zone
    for (net, layer), regions in fills.items():
        lonely = sum(1 for r in regions if not any(items[i].geom.intersects(r) for i in by_net.get(net, []) if layer in items[i].layers))
        if lonely:
            warnings.append(f"zone {net} {layer} : {lonely} ilot(s) sans connexion (supprimes au remplissage)")

    # 9. antenne : pas de cuivre dans la zone reservee (encoche des zones GND : x -8..8, y -35..-27 autour du centre)
    ant = ANT
    for it in items:
        if it.geom.intersects(ant) and not (it.kind == "pad" and it.ref == "U1"):
            warnings.append(f"cuivre sous l'antenne : {it.desc}")
    for (net, layer), regions in fills.items():
        a = sum(r.intersection(ant).area for r in regions)
        if a > 0.01:
            errors.append(f"zone {net} {layer} remplit {a:.1f} mm2 sous l'antenne")

    # ---------------------------------------------------------------- rapport
    n_pads = sum(1 for it in items if it.kind == "pad")
    n_tracks = sum(1 for it in items if it.kind in ("piste", "arc"))
    print(f"{PCB.name} : {n_pads} pads, {n_tracks} pistes, {len(zones_def)} zones, {len(courtyards)} courtyards, carte {board.area:.0f} mm2")
    for (net, layer), regions in fills.items():
        print(f"  zone {net} {layer} : {len(regions)} region(s), {sum(r.area for r in regions):.0f} mm2")
    print(f"\n{len(errors)} erreur(s), {len(warnings)} avertissement(s)")
    for e in errors:
        print("  ERREUR :", e)
    for w in warnings:
        print("  attention :", w)
    if verbose:
        print("\nnets :")
        for net, idx in sorted(by_net.items()):
            print(f"  {net}: {len(idx)} elements")
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
