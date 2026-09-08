#!/bin/sh
# Regenere tout le projet Halo : schema, PCB place, routage du centre, DRC, coque et pied.
# Dependances : python3, shapely, numpy, scipy, cadquery. Environ 4 minutes.
set -e
cd "$(dirname "$0")/.."
python3 halo/gen_kicad_sch.py
python3 halo/gen_kicad_pcb.py
python3 halo/route_center.py
python3 halo/drc.py
python3 halo/gen_coque_pied.py
