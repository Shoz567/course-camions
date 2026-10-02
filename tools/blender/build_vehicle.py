"""Genere un vehicule du catalogue en .glb.

    blender -b --factory-startup -P tools/blender/build_vehicle.py -- \
        --variant=citerne --out=game/assets/generated/vehicules/citerne.glb

Variantes : voir CATALOG. Contrat des objets exportes (docs/ART_PIPELINE.md
§4 et §4 ter) : `Body` + `Wheel_FL/FR/RL/RR` (pivot au moyeu), vide
`Remorque` a la sellette pour les semi-remorques, vides `Socket_*` pour les
armes, pieces mobiles nommees (Grue_*, Echelle*, Lame_Neige, Mat, Fourche,
Conteneur_Porte_*, Voiture_Chargee_*).
"""

import argparse
import sys
from pathlib import Path

import bpy

sys.path.append(str(Path(__file__).parent))
from lib import export, items, kit, mesh, vehicles as V  # noqa: E402


def _tractor_with(trailer, color, number, style="flat"):
    liv = kit.livery(color)
    body = V.tractor(liv, number, style=style).finish()
    obs = [body] + V.make_wheels() + V.tractor_sockets(
        body, top=V.CAB_TOP + (0.6 if style == "sleeper" else 0.0))
    _, tobs = trailer(liv, number)
    return obs + tobs


def _rigid(extra, color, number, style="flat", sockets=None):
    liv = kit.livery(color)
    body = V.tractor_rigid(liv, number, style=style).finish()
    obs = [body] + V.make_wheels() + V.tractor_sockets(body)
    for o in extra(liv):
        if o.parent is None:
            o.parent = body
        obs.append(o)
    for name, pos in (sockets or {}).items():
        obs.append(kit.empty(name, pos, body))
    return obs


CATALOG = {
    # Semi-remorques (tracteur + remorque articulee).
    "citerne": lambda: _tractor_with(V.trailer_tanker, "Orange", "3"),
    "betaillere": lambda: _tractor_with(V.trailer_livestock, "Vert", "5", style="hood"),
    "remorque": lambda: _tractor_with(V.trailer_container, "Rouge", "8", style="sleeper"),
    "porte_voitures": lambda: _tractor_with(
        lambda liv, n: V.trailer_car_carrier(liv, n, items.car), "Violet", "9", style="sleeper"),
    # Porteurs.
    "grue": lambda: _rigid(V.crane_body, "Jaune", "4", sockets={
        "Socket_Arriere": (0, -3.55, 2.70), "Socket_Conteneur": (0, -3.50, 1.40)}),
    "chasse_neige": lambda: _rigid(V.plow_body, "Orange", "6", sockets={
        "Socket_Arriere": (0, -3.40, 3.45), "Socket_Conteneur": (0, -3.70, 1.20)}),
    "pompier": lambda: _rigid(V.fire_body, "Pompier", "18", sockets={
        "Socket_Arriere": (0, -4.0, 3.55), "Socket_Conteneur": (0, -4.0, 1.20)}),
    # Engin.
    "chariot_elevateur": lambda: V.forklift(kit.livery("Jaune")),
}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--variant", required=True, choices=sorted(CATALOG))
    p.add_argument("--out", required=True)
    return p.parse_args(argv)


def check(objects, variant):
    names = {o.name for o in objects}
    missing = [n for n in ["Body"] + V.TRUCK_WHEELS if n not in names]
    if missing:
        raise SystemExit("%s : objets manquants %s" % (variant, missing))
    for n in V.TRUCK_WHEELS:
        w = bpy.data.objects[n]
        if abs(w.location.z - w.dimensions.z / 2) > 0.02:
            raise SystemExit("%s : pivot de %s hors du moyeu (z=%.3f, rayon=%.3f)"
                             % (variant, n, w.location.z, w.dimensions.z / 2))
    body = mesh.tri_count(bpy.data.objects["Body"])
    if body > mesh.TRI_BUDGET_TRUCK:
        raise SystemExit("%s : Body %d triangles > budget %d" % (variant, body, mesh.TRI_BUDGET_TRUCK))
    for n in V.TRUCK_WHEELS:
        t = mesh.tri_count(bpy.data.objects[n])
        if t > mesh.TRI_BUDGET_WHEEL:
            raise SystemExit("%s : %s %d triangles > budget %d" % (variant, n, t, mesh.TRI_BUDGET_WHEEL))
    total = kit.tris(objects)
    if total > mesh.TRI_BUDGET_VEHICLE_TOTAL:
        raise SystemExit("%s : %d triangles > budget %d" % (variant, total, mesh.TRI_BUDGET_VEHICLE_TOTAL))


def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = CATALOG[args.variant]()
    check(objects, args.variant)
    export.apply_transforms(objects)
    out = export.to_glb(args.out, objects)
    print("OK %s tris=%d" % (out, kit.tris(objects)))


if __name__ == "__main__":
    main()
