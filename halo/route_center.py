#!/usr/bin/env python3
"""Routeur du centre de halo/Halo.kicad_pcb : lit le PCB genere par gen_kicad_pcb.py,
route tous les nets encore en chevelu (Dijkstra sur grille 0.1 mm, F.Cu + B.Cu, vias),
relie les ilots GND isoles par des vias vers le plan de masse B.Cu, et reecrit le fichier.

Regles suivies (memes valeurs que drc.py) : isolation 0.2 mm (+0.02 de marge de grille),
cuivre-bord 0.5, trou-cuivre 0.25, via 0.6/0.3. B.Cu (plan de masse, face avant) coute
le double et un via coute 3 mm de piste : les pistes restent sur F.Cu tant que possible.

Usage : python3 halo/gen_kicad_pcb.py && python3 halo/route_center.py && python3 halo/drc.py && python3 halo/gen_kicad_libs.py
"""
import math
import sys
import uuid
from pathlib import Path

import numpy as np
import shapely
from scipy import ndimage
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra
from shapely.geometry import LineString, Point, box
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).resolve().parent))
import drc  # noqa: E402

PCB = drc.PCB
G = 0.1                                    # pas de grille (mm)
CLEAR = drc.CLEARANCE + 0.025              # marge : un pas diagonal peut couper un coin rentrant
VIA_D, VIA_DRILL, VIA_COST, BCU_COST = 0.6, 0.3, 30.0, 2.0
WIDTH = {"5V": 0.5, "VBUS": 0.5, "3V3": 0.35, "GND": 0.3,
         "USB_DP": 0.2, "USB_DM": 0.2, "CC1": 0.2, "CC2": 0.2}
DEFAULT_W = 0.25
ANT = drc.ANT                                             # encoche antenne (cf. ANT_NOTCH)
THERMAL_VIAS = ("49",)                                    # un via dans chacune des 9 pastilles de la masse centrale de U1
KEEP_U1 = box(150 - 5.4, 105 - 24 - 1.7, 150 + 5.4, 105 - 24 + 7.1)   # sous U1, a l'interieur de la couronne de broches (F.Cu) : rien d'autre que GND

NS = uuid.UUID("7a1d2c3b-4e5f-4a6b-8c7d-9e0f1a2b3c4d")
_n = [0]
def uid():
    _n[0] += 1
    return str(uuid.uuid5(NS, f"route-{_n[0]}"))

def fmt(v):
    v = round(float(v), 3)
    return str(int(v)) if v == int(v) else repr(v)

# ---------------------------------------------------------------- grille
items, courtyards, edge, zones_def, npth = drc.load(PCB)
board = drc.board_polygon(edge)
bx0, by0, bx1, by1 = board.bounds
X0, Y0 = math.floor((bx0 - 1) / G) * G + 0.05, math.floor((by0 - 1) / G) * G + 0.05   # centres de cellule sur .x5 : pads USB a 149.75/150.25
W = int((bx1 + 1 - X0) / G) + 1
H = int((by1 + 1 - Y0) / G) + 1
XS = X0 + G * np.arange(W)
YS = Y0 + G * np.arange(H)
LAYERS = ("F.Cu", "B.Cu")
print(f"grille {W} x {H} cellules de {G} mm")

def raster(geom):
    """Masque booleen (H, W) des cellules dont le centre est dans geom (calcule sur sa bbox)."""
    mask = np.zeros((H, W), dtype=bool)
    if geom.is_empty:
        return mask
    gx0, gy0, gx1, gy1 = geom.bounds
    ix0, ix1 = max(0, int((gx0 - X0) / G)), min(W - 1, int((gx1 - X0) / G) + 1)
    iy0, iy1 = max(0, int((gy0 - Y0) / G)), min(H - 1, int((gy1 - Y0) / G) + 1)
    if ix1 < ix0 or iy1 < iy0:
        return mask
    xx, yy = np.meshgrid(XS[ix0:ix1 + 1], YS[iy0:iy1 + 1])
    mask[iy0:iy1 + 1, ix0:ix1 + 1] = shapely.contains_xy(geom, xx.ravel(), yy.ravel()).reshape(xx.shape)
    return mask

def disk(r_mm):
    r = int(math.ceil(r_mm / G))
    yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
    return (xx * G) ** 2 + (yy * G) ** 2 <= r_mm ** 2 + 1e-9

def dilate(mask, r_mm):
    return ndimage.binary_dilation(mask, structure=disk(r_mm)) if r_mm > 0 else mask

def mark_within(mask, geom, d):
    """Marque dans mask les cellules dont le centre est a moins de d de geom (test exact, pas de rasterisation)."""
    if geom.is_empty:
        return
    gx0, gy0, gx1, gy1 = geom.bounds
    ix0, ix1 = max(0, int((gx0 - d - X0) / G)), min(W - 1, int((gx1 + d - X0) / G) + 1)
    iy0, iy1 = max(0, int((gy0 - d - Y0) / G)), min(H - 1, int((gy1 + d - Y0) / G) + 1)
    if ix1 < ix0 or iy1 < iy0:
        return
    xx, yy = np.meshgrid(XS[ix0:ix1 + 1], YS[iy0:iy1 + 1])
    pts = shapely.points(xx.ravel(), yy.ravel())
    mask[iy0:iy1 + 1, ix0:ix1 + 1] |= shapely.dwithin(geom, pts, d).reshape(xx.shape)

holes = unary_union([h.geom for h in npth])

def obstacles(net, w):
    """Cellules interdites au centre d'une piste de largeur w du net : tout cuivre etranger a moins de CLEAR + w/2,
    bord de carte, trous non plaques, encoche antenne."""
    out = {}
    for l in LAYERS:
        m = ~raster(board.buffer(-(drc.EDGE_CL + w / 2)))
        mark_within(m, holes, drc.HOLE_CL + w / 2)
        mark_within(m, ANT, w / 2)
        if l == "F.Cu" and net != "GND":
            mark_within(m, KEEP_U1, w / 2)
        for it in items:
            if it.net != net and l in it.layers:
                mark_within(m, it.geom, CLEAR + w / 2)
        out[l] = m
    return out

def via_forbidden(net):
    m = ~raster(board.buffer(-(drc.EDGE_CL + VIA_D / 2)))
    mark_within(m, holes, drc.HOLE_CL + VIA_D / 2)
    mark_within(m, ANT, VIA_D / 2)
    if net != "GND":
        mark_within(m, KEEP_U1, VIA_D / 2)
    for it in items:
        if it.net != net:
            mark_within(m, it.geom, CLEAR + VIA_D / 2)
    return m

# ---------------------------------------------------------------- Dijkstra sur une fenetre
DIRS = [(1, 0, 1.0), (0, 1, 1.0), (1, 1, math.sqrt(2)), (1, -1, math.sqrt(2))]

def route(obst, via_no, src, dst, margin=6.0):
    """src/dst : dict layer -> masque bool. Retourne la liste de (layer, x, y) du chemin ou None."""
    pts = np.argwhere(src["F.Cu"] | src["B.Cu"] | dst["F.Cu"] | dst["B.Cu"])
    m = int(margin / G)
    y0, x0 = np.maximum(pts.min(0) - m, 0)
    y1, x1 = np.minimum(pts.max(0) + m, (H - 1, W - 1))
    h, w = y1 - y0 + 1, x1 - x0 + 1
    n = h * w
    free = {l: ~obst[l][y0:y1 + 1, x0:x1 + 1] for l in LAYERS}
    rows, cols, vals = [], [], []
    for li, l in enumerate(LAYERS):
        fl = free[l]
        base = li * n
        idx = np.arange(n).reshape(h, w) + base
        mult = BCU_COST if l == "B.Cu" else 1.0
        for dx, dy, c in DIRS:
            ys = slice(max(0, -dy), h - max(0, dy)); xs = slice(max(0, -dx), w - max(0, dx))
            ys2 = slice(max(0, dy), h - max(0, -dy)); xs2 = slice(max(0, dx), w - max(0, -dx))
            ok = fl[ys, xs] & fl[ys2, xs2]
            a, b = idx[ys, xs][ok], idx[ys2, xs2][ok]
            rows += [a, b]; cols += [b, a]; vals += [np.full(a.size, c * mult), np.full(a.size, c * mult)]
    vok = (~via_no[y0:y1 + 1, x0:x1 + 1]) & free["F.Cu"] & free["B.Cu"]
    a = np.arange(n).reshape(h, w)[vok]
    rows += [a, a + n]; cols += [a + n, a]; vals += [np.full(a.size, VIA_COST)] * 2
    S = 2 * n
    s_nodes = np.concatenate([np.argwhere((src[l][y0:y1 + 1, x0:x1 + 1] & free[l]).ravel()).ravel() + li * n for li, l in enumerate(LAYERS)])
    t_nodes = np.concatenate([np.argwhere((dst[l][y0:y1 + 1, x0:x1 + 1] & free[l]).ravel()).ravel() + li * n for li, l in enumerate(LAYERS)])
    if s_nodes.size == 0 or t_nodes.size == 0:
        return None
    rows.append(np.full(s_nodes.size, S)); cols.append(s_nodes); vals.append(np.full(s_nodes.size, 1e-6))
    Gm = coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(S + 1, S + 1)).tocsr()
    dist, pred = dijkstra(Gm, directed=True, indices=S, return_predecessors=True)
    d = dist[t_nodes]
    if not np.isfinite(d).any():
        return None
    node = int(t_nodes[int(np.argmin(d))])
    path = []
    while node != S and node >= 0:
        li, r = divmod(node, n)
        iy, ix = divmod(r, w)
        path.append((LAYERS[li], X0 + (x0 + ix) * G, Y0 + (y0 + iy) * G))
        node = int(pred[node])
    return path[::-1]

def dump_window(net, obst, via_no, src, dst, margin=3.0):
    """Carte ASCII autour des terminaux (debug) : # obstacle, s source, t cible, v via possible, . libre."""
    pts = np.argwhere(src["F.Cu"] | src["B.Cu"] | dst["F.Cu"] | dst["B.Cu"])
    m = int(margin / G)
    y0, x0 = np.maximum(pts.min(0) - m, 0); y1, x1 = np.minimum(pts.max(0) + m, (H - 1, W - 1))
    out = []
    for l in LAYERS:
        out.append(f"== {net} {l}  x {X0 + x0 * G - 150:.2f}..{X0 + x1 * G - 150:.2f}  y {Y0 + y0 * G - 105:.2f}..{Y0 + y1 * G - 105:.2f}")
        for iy in range(y0, y1 + 1, 2):
            row = ""
            for ix in range(x0, x1 + 1):
                if src[l][iy, ix]: row += "s"
                elif dst[l][iy, ix]: row += "t"
                elif obst[l][iy, ix]: row += "#"
                elif not via_no[iy, ix]: row += "v"
                else: row += "."
            out.append(f"{Y0 + iy * G - 105:7.2f} {row}")
    Path(f"halo/route_fail_{net}.txt").write_text("\n".join(out))

def to_tracks(path, w, net):
    """Chemin de cellules -> segments fusionnes + vias. Retourne (segments, vias, geoms par couche)."""
    segs, vias = [], []
    i = 0
    while i < len(path) - 1:
        l, x, y = path[i]
        if path[i + 1][0] != l:                      # changement de couche
            vias.append((x, y)); i += 1; continue
        j = i + 1
        dx, dy = path[j][1] - x, path[j][2] - y
        while j + 1 < len(path) and path[j + 1][0] == l and abs((path[j + 1][1] - path[j][1]) - dx) < 1e-6 and abs((path[j + 1][2] - path[j][2]) - dy) < 1e-6:
            j += 1
        segs.append((l, (x, y), (path[j][1], path[j][2])))
        i = j
    return segs, vias

def emit(segs, vias, w, net):
    out = []
    for l, p1, p2 in segs:
        out.append(f'\t(segment\n\t\t(start {fmt(p1[0])} {fmt(p1[1])})\n\t\t(end {fmt(p2[0])} {fmt(p2[1])})\n\t\t(width {w})'
                   f'\n\t\t(layer "{l}")\n\t\t(net "{net}")\n\t\t(uuid "{uid()}")\n\t)')
    for x, y in vias:
        out.append(f'\t(via\n\t\t(at {fmt(x)} {fmt(y)})\n\t\t(size {VIA_D})\n\t\t(drill {VIA_DRILL})\n\t\t(layers "F.Cu" "B.Cu")'
                   f'\n\t\t(net "{net}")\n\t\t(uuid "{uid()}")\n\t)')
    return out

def commit(segs, vias, w, net):
    """Ajoute le cuivre route aux masques et a la liste d'items ; retourne les geometries (layer -> geom)."""
    geoms = {l: [] for l in LAYERS}
    for l, p1, p2 in segs:
        g = LineString([p1, p2]).buffer(w / 2, 16)
        geoms[l].append(g)
        items.append(drc.Item("piste", "", None, net, {l}, g, width=w))
    for x, y in vias:
        g = Point(x, y).buffer(VIA_D / 2, 16)
        for l in LAYERS:
            geoms[l].append(g)
        items.append(drc.Item("via", "", None, net, set(LAYERS), g, hole=Point(x, y).buffer(VIA_DRILL / 2, 16)))
    return geoms

# ---------------------------------------------------------------- terminaux d'un net
def groups_of(net):
    """Composantes connexes des elements du net (pads + pistes existantes), par recouvrement."""
    idx = [i for i, it in enumerate(items) if it.net == net]
    parent = {i: i for i in idx}
    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]; a = parent[a]
        return a
    for a in range(len(idx)):
        for b in range(a + 1, len(idx)):
            i, j = idx[a], idx[b]
            if items[i].layers & items[j].layers and items[i].geom.intersects(items[j].geom):
                parent[find(i)] = find(j)
    comps = {}
    for i in idx:
        comps.setdefault(find(i), []).append(i)
    return list(comps.values())

def cells_of(idx_list):
    m = {l: np.zeros((H, W), dtype=bool) for l in LAYERS}
    for i in idx_list:
        r = raster(items[i].geom)
        for l in items[i].layers:
            m[l] |= r
    return m

def merge_cells(a, b):
    return {l: a[l] | b[l] for l in LAYERS}

def label(idx_list):
    return ", ".join(sorted({items[i].desc.split(" [")[0] for i in idx_list}))[:60]

# ---------------------------------------------------------------- 1. vias thermiques GND sous U1 (poses en premier : obstacles pour la suite)
new_tracks = []
failures = []
u1_gnd = [i for i, it in enumerate(items) if it.ref == "U1" and it.pad in THERMAL_VIAS]
tv = [(it.geom.centroid.x, it.geom.centroid.y) for it in (items[i] for i in u1_gnd)]
new_tracks += emit([], tv, 0.3, "GND")
commit([], tv, 0.3, "GND")

# ---------------------------------------------------------------- 1b. nets de signal / alimentation
nets = sorted({it.net for it in items if not it.net.startswith("__nc") and it.net != "GND"})
# les nets a pistes fines / difficiles d'abord (USB), puis par nombre de pads decroissant
def priority(net):
    order = {"USB_DP": 0, "USB_DM": 0, "CC1": 1, "CC2": 1, "VBUS": 2, "5V": 2, "3V3": 3, "LED_DATA_3V3": 3, "STRAP_IO2": 3, "STRAP_IO8": 3}
    return (order.get(net, 4), -sum(1 for it in items if it.net == net))
nets.sort(key=priority)

for net in nets:
    comps = groups_of(net)
    if len(comps) <= 1:
        continue
    w0 = WIDTH.get(net, DEFAULT_W)
    widths = sorted({w0, min(w0, 0.3), min(w0, 0.25), 0.2}, reverse=True)
    comps.sort(key=lambda c: -len(c))
    connected = comps[0]
    conn_cells = cells_of(connected)
    todo = comps[1:]
    print(f"net {net:14s} {len(comps)} ilots, largeur {w0}")
    cache = {}
    via_no = via_forbidden(net)
    while todo:
        done = False
        for w in widths:
            if w not in cache:
                cache[w] = obstacles(net, w)
            obst = cache[w]
            dst = {l: np.zeros((H, W), dtype=bool) for l in LAYERS}
            tcells = [cells_of(c) for c in todo]
            for tc in tcells:
                dst = merge_cells(dst, tc)
            path = None
            for margin in (6.0, 15.0, 60.0):
                path = route(obst, via_no, conn_cells, dst, margin)
                if path:
                    break
            if not path:
                continue
            segs, vias = to_tracks(path, w, net)
            new_tracks += emit(segs, vias, w, net)
            geoms = commit(segs, vias, w, net)
            # quel ilot a ete atteint ? (celui dont les cellules contiennent la fin du chemin)
            l_end, xe, ye = path[-1]
            ie = (int(round((ye - Y0) / G)), int(round((xe - X0) / G)))
            hit = next((k for k, tc in enumerate(tcells) if tc[l_end][ie]), 0)
            reached = todo.pop(hit)
            connected += reached
            conn_cells = merge_cells(conn_cells, tcells[hit])
            for l in LAYERS:
                for g in geoms[l]:
                    conn_cells[l] |= raster(g)
            print(f"   -> {label(reached):60s} {len(segs)} seg, {len(vias)} via, w={w}")
            done = True
            break
        if not done:
            failures.append(f"{net} : impossible d'atteindre {label(todo[0])}")
            print(f"   !! {failures[-1]}")
            dump_window(net, cache[widths[-1]], via_no, conn_cells, dst)
            break

# ---------------------------------------------------------------- 2. GND : ilots de zone isoles

def gnd_components():
    """Union-find GND sur pads/pistes/vias + regions de zone remplies. Retourne (comps, region_geoms, main_key)."""
    fills = {}
    for net, layer, poly in zones_def:
        if net != "GND":
            continue
        obst = [it.geom.buffer(drc.ZONE_CL) for it in items if layer in it.layers and it.net != "GND"]
        obst += [h.geom.buffer(drc.HOLE_CL) for h in npth]
        fill = poly.intersection(board.buffer(-drc.EDGE_CL)).difference(unary_union(obst))
        fill = fill.buffer(-drc.ZONE_MIN_W / 2).buffer(drc.ZONE_MIN_W / 2)
        regs = list(fill.geoms) if fill.geom_type == "MultiPolygon" else [fill]
        fills[layer] = [r for r in regs if not r.is_empty]
    idx = [i for i, it in enumerate(items) if it.net == "GND"]
    nodes = [("item", i) for i in idx] + [("reg", l, k) for l in fills for k in range(len(fills[l]))]
    parent = {n: n for n in nodes}
    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]; a = parent[a]
        return a
    def union(a, b):
        parent[find(a)] = find(b)
    for l in LAYERS:
        li = [i for i in idx if l in items[i].layers]
        tree = shapely.STRtree([items[i].geom for i in li])
        for k, i in enumerate(li):
            for j in tree.query(items[i].geom):
                j = li[int(j)]
                if j != i and items[i].geom.intersects(items[j].geom):
                    union(("item", i), ("item", j))
        for k, r in enumerate(fills.get(l, [])):
            for j in tree.query(r):
                j = li[int(j)]
                if items[j].geom.intersects(r):
                    union(("item", j), ("reg", l, k))
    comps = {}
    for nd in nodes:
        comps.setdefault(find(nd), []).append(nd)
    main = max(comps.values(), key=lambda c: sum(fills[n[1]][n[2]].area for n in c if n[0] == "reg"))
    return list(comps.values()), fills, main

def comp_cells(comp, fills, erode):
    m = {l: np.zeros((H, W), dtype=bool) for l in LAYERS}
    for nd in comp:
        if nd[0] == "item":
            it = items[nd[1]]
            r = raster(it.geom)
            for l in it.layers:
                m[l] |= r
        else:
            m[nd[1]] |= raster(fills[nd[1]][nd[2]].buffer(-erode))
    return m

for round_ in range(4):
    comps, fills, main = gnd_components()
    others = [c for c in comps if c is not main and any(n[0] == "item" and items[n[1]].kind == "pad" for n in c)]
    print(f"GND : {len(comps)} composantes, {len(others)} a relier (tour {round_ + 1})")
    if not others:
        break
    obst = obstacles("GND", WIDTH["GND"])
    via_no = via_forbidden("GND")
    dst = comp_cells(main, fills, 0.15)
    dst["B.Cu"] |= raster(unary_union(fills["B.Cu"]).buffer(-(VIA_D / 2 + 0.05)))   # partout ou un via peut plonger dans le plan
    for comp in others:
        src = comp_cells(comp, fills, 0.05)
        path = None
        for margin in (4.0, 10.0, 30.0):
            path = route(obst, via_no, src, dst, margin)
            if path:
                break
        pads = label([n[1] for n in comp if n[0] == "item"])
        if not path:
            failures.append(f"GND : ilot {pads} impossible a relier")
            print(f"   !! {failures[-1]}")
            continue
        segs, vias = to_tracks(path, WIDTH["GND"], "GND")
        if not segs and not vias:                     # deja adjacent : un via sur place
            vias = [(path[0][1], path[0][2])]
        new_tracks += emit(segs, vias, WIDTH["GND"], "GND")
        commit(segs, vias, WIDTH["GND"], "GND")
        print(f"   -> {pads:60s} {len(segs)} seg, {len(vias)} via")

# ---------------------------------------------------------------- ecriture
text = PCB.read_text()
k = text.rstrip().rfind(")")
text = text[:k] + "\n".join(new_tracks) + "\n)\n"
PCB.write_text(text)
n_seg = sum(1 for t in new_tracks if t.startswith("\t(segment"))
n_via = sum(1 for t in new_tracks if t.startswith("\t(via"))
print(f"\n{PCB.name} : +{n_seg} segments, +{n_via} vias")
if failures:
    print(f"{len(failures)} echec(s) :")
    for f_ in failures:
        print("  ", f_)
    sys.exit(1)
