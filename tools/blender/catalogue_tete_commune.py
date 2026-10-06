"""Catalogue de vehicules : meme tete de camion partout, seule la remorque change.

    blender -b -P tools/blender/catalogue_tete_commune.py
    blender -b -P tools/blender/catalogue_tete_commune.py -- --only grue

Pour chaque vehicule de Assets_Visuels/Armes_et_camions/vehicules/ :
  1. la tete (Body + Wheel_FL/FR/RL/RR) est remplacee par le tracteur du camion
     de course de l'equipe (Camion_Bleu.glb), ajuste a VEHICLE_SPEC comme le
     fait TruckVisual en jeu : demi-tour (avant en -Z Godot), echelle uniforme
     pour une longueur de tracteur de 6,96 m, centre, pneus au sol ;
  2. la semi-remorque `Remorque` (pivot a la sellette) est conservee. Les
     porteurs sans remorque (grue, pompier, chasse-neige) et le chariot
     elevateur recoivent une semi-remorque plateau (celle de remorque.blend)
     qui porte leur equipement ;
  3. les points d'accroche des armes sont reposes : Socket_Avant,
     Socket_Lateral_G/D et Socket_Toit sur la tete (donc aux MEMES coordonnees
     sur tous les vehicules), Socket_Arriere et Socket_Conteneur sur la remorque.

Le .blend et le .glb de chaque vehicule sont reecrits. Idempotent : relance,
le script retrouve la remorque deja posee et ne refait que la tete.
"""

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.append(str(Path(__file__).parent))
from lib import export  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOGUE = REPO_ROOT / "Assets_Visuels" / "Armes_et_camions" / "vehicules"
TRACTOR_GLB = REPO_ROOT / "Assets_Visuels" / "Camion" / "Camions_Course_Export" / "Camion_Bleu.glb"
TRAILER_TEMPLATE = CATALOGUE / "remorque.blend"

# VEHICLE_SPEC §2 : longueur du tracteur (5,8 m x 1,2).
TRACTOR_LENGTH = 6.96
TRAILER = "Remorque"
TEMPLATE_PARTS = ["Remorque_Chassis", "Remorque_Plateau", "Remorque_Roues"]
TRACTOR_SOCKETS = ["Socket_Avant", "Socket_Lateral_G", "Socket_Lateral_D", "Socket_Toit"]
TRAILER_SOCKETS = ["Socket_Arriere", "Socket_Conteneur"]
# Decor de presentation des .blend : conserve, jamais exporte.
SCENE_PROPS = {"Sol", "Camera", "Soleil"}
# Sur les caisses de porteur (Porteur_*), ce qui est devant y = 1,0 m est pose sur l'ancienne cabine
# (supports de gyrophares de la saleuse) : abandonne avec elle.
CAB_LIMIT_Y = 1.0

# Porteurs et engins sans semi-remorque : objets poses sur le plateau.
# Ce qui n'est pas liste disparait avec l'ancienne tete (Porteur_Plateau de la
# grue : le plateau de la remorque le remplace ; Lame_Neige : lame avant).
EQUIPMENT = {
    "grue": ["Grue_Tourelle", "Grue_Fleche", "Grue_Crochet"],
    "pompier": ["Porteur_Pompier", "Echelle_Tourelle", "Echelle"],
    "chasse_neige": ["Porteur_Saleuse"],
    "chariot_elevateur": None,   # None = tout l'engin
}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--only", nargs="*", default=None)
    return p.parse_args(argv)


def world_bbox(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, w))
            mx = Vector(map(max, mx, w))
    return mn, mx


def world_verts(obj):
    m = obj.matrix_world
    return [m @ v.co for v in obj.data.vertices]


def alive(o):
    try:
        return o.name in bpy.data.objects
    except ReferenceError:   # deja supprime (fusionne, efface)
        return False


def delete(objs):
    for o in list(objs):
        if alive(o):
            bpy.data.objects.remove(o, do_unlink=True)


def reparent_keep(obj, parent):
    mw = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = mw


def join(objs, name):
    """Fusionne des meshes en un seul objet, transformations appliquees."""
    objs = [o for o in objs if o.type == "MESH"]
    for o in objs:
        reparent_keep(o, None)
        if o.data.users > 1:
            o.data = o.data.copy()
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs):
        bpy.ops.object.join()
    out = objs[0]
    out.name = name
    out.data.name = name
    return out


def drop_parts_over_cab(obj):
    """Retire les morceaux detaches du maillage situes sur l'ancienne cabine."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    m = obj.matrix_world
    seen = set()
    doomed = []
    for v in bm.verts:
        if v in seen:
            continue
        part, stack = [], [v]
        seen.add(v)
        while stack:
            x = stack.pop()
            part.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y not in seen:
                    seen.add(y)
                    stack.append(y)
        if min((m @ x.co).y for x in part) > CAB_LIMIT_Y:
            doomed += part
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="VERTS")
        bm.to_mesh(obj.data)
    bm.free()


def set_origin(obj, point):
    """Deplace l'origine de obj (sans bouger la geometrie)."""
    off = point - obj.matrix_world.translation
    obj.data.transform(Matrix.Translation(-off))
    obj.matrix_world.translation = point


def add_socket(name, loc, parent):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "PLAIN_AXES"
    e.empty_display_size = 0.3
    bpy.context.scene.collection.objects.link(e)
    # position monde = loc (matrix_world n'est recalcule qu'au prochain update :
    # on ne peut pas poser location puis lire matrix_world)
    e.parent = parent
    e.matrix_parent_inverse = parent.matrix_world.inverted()
    e.location = loc
    return e


# ---------------------------------------------------------------- remorque


def build_plateau_trailer(vehicle):
    """Semi-remorque plateau de remorque.blend, chargee de l'equipement."""
    with bpy.data.libraries.load(str(TRAILER_TEMPLATE), link=False) as (src, dst):
        dst.objects = [TRAILER] + TEMPLATE_PARTS
    for o in dst.objects:
        bpy.context.scene.collection.objects.link(o)
    trailer = bpy.data.objects[TRAILER]

    names = EQUIPMENT[vehicle]
    if names is None:   # l'engin entier devient le chargement
        roots = [o for o in bpy.context.scene.objects
                 if o.parent is None and o.type == "MESH" and o.name not in SCENE_PROPS
                 and o.name not in dst_names(dst)]
    else:
        missing = [n for n in names if n not in bpy.data.objects]
        if missing:
            raise SystemExit(f"{vehicle} : equipement introuvable {missing}")
        roots = [bpy.data.objects[n] for n in names]
        roots = [o for o in roots if o.parent is None or o.parent.name not in names]
        for o in roots:
            for m in [o] + list(o.children_recursive):
                if m.type == "MESH" and m.name.startswith("Porteur_"):
                    drop_parts_over_cab(m)
    load = []
    for o in roots:
        load += [o] + list(o.children_recursive)
    delete([o for o in load if o.name.startswith("Socket_")])
    load = [o for o in load if alive(o)]
    if names is None:
        for o in load:
            o.name = "Chariot_" + o.name
    # sur le plateau : centre en x et en longueur, pose sur le dessus
    pmn, pmx = world_bbox([bpy.data.objects["Remorque_Plateau"]])
    lmn, lmx = world_bbox(load)
    offset = Vector((-(lmn.x + lmx.x) / 2,
                     (pmn.y + pmx.y) / 2 - (lmn.y + lmx.y) / 2,
                     pmx.z - lmn.z))
    for o in roots:
        reparent_keep(o, trailer)
        o.matrix_world.translation += offset
    return trailer


def dst_names(dst):
    return {o.name for o in dst.objects}


def place_trailer_sockets(trailer):
    """Arriere : haut de l'arriere du chargement. Conteneur : arriere du plateau."""
    parts = [o for o in trailer.children_recursive if o.type == "MESH"]
    tmn, tmx = world_bbox(parts)
    rear = [v for o in parts for v in world_verts(o) if v.y < tmn.y + 1.5 and abs(v.x) < 0.6]
    top = max(v.z for v in rear)
    pmn, pmx = world_bbox([bpy.data.objects["Remorque_Plateau"]])
    add_socket("Socket_Arriere", Vector((0.0, round(tmn.y + 0.15, 2), round(top, 2))), trailer)
    add_socket("Socket_Conteneur", Vector((0.0, round(pmn.y + 0.3, 2), round(pmx.z + 0.1, 2))), trailer)


# ---------------------------------------------------------------- tete


def import_tractor():
    """Importe le tracteur de course ajuste a la spec : Body + 4 roues."""
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(TRACTOR_GLB))
    new = [o for o in bpy.context.scene.objects if o not in before]
    root = next(o for o in new if o.parent is None)
    race_trailer = next(o for o in root.children if o.name.startswith(TRAILER))
    gone = {race_trailer} | set(race_trailer.children_recursive)
    new = [o for o in new if o not in gone]
    delete(gone)

    tractor = [o for o in new if o.type == "MESH"]
    mn, mx = world_bbox(tractor)
    s = TRACTOR_LENGTH / (mx.y - mn.y)
    c = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    # demi-tour autour de Z (avant du modele en -Y Blender -> +Y = -Z Godot)
    fit = Matrix.Rotation(3.141592653589793, 4, "Z") @ Matrix.Scale(s, 4) @ Matrix.Translation(-c)
    root.matrix_world = fit @ root.matrix_world
    bpy.context.view_layer.update()

    wheels = {}
    groups = [o for o in root.children if o.type == "EMPTY" and o.name.startswith("Roue")]
    for g in groups:
        meshes = [o for o in g.children_recursive if o.type == "MESH"]
        gmn, gmx = world_bbox(meshes)
        hub = (gmn + gmx) / 2
        name = "Wheel_" + ("F" if hub.y > 0 else "R") + ("L" if hub.x < 0 else "R")
        if name in wheels:
            raise SystemExit(f"deux groupes de roues au meme endroit : {name}")
        w = join(meshes, name)
        set_origin(w, hub)
        wheels[name] = w
    if sorted(wheels) != ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
        raise SystemExit(f"roues du tracteur : {sorted(wheels)}")

    body_meshes = [o for o in root.children_recursive if o.type == "MESH"]
    body = join(body_meshes, "Body")
    set_origin(body, Vector((0.0, 0.0, 0.0)))
    delete([o for o in new if alive(o) and o.type == "EMPTY"])
    return body, wheels, s


def place_tractor_sockets(body):
    v = world_verts(body)
    # avant : nez du camion, a hauteur de pare-chocs
    nose = max(p.y for p in v if abs(p.x) < 0.5 and 1.0 < p.z < 1.4)
    # flancs : entre les essieux, a hauteur de chassis
    side = max(abs(p.x) for p in v if abs(p.y) < 0.5 and 0.9 < p.z < 1.3)
    # toit : point le plus haut de la cabine dans l'axe (hors echappements)
    cab = [p for p in v if abs(p.x) < 0.3 and p.y > 0.5]
    roof = max(cab, key=lambda p: p.z)
    socks = {
        "Socket_Avant": Vector((0.0, nose, 1.2)),
        "Socket_Lateral_G": Vector((-side, 0.0, 1.1)),
        "Socket_Lateral_D": Vector((side, 0.0, 1.1)),
        "Socket_Toit": Vector((0.0, roof.y, roof.z)),
    }
    for name, loc in socks.items():
        add_socket(name, Vector(tuple(round(x, 2) for x in loc)), body)
    return socks


# ---------------------------------------------------------------- vehicule


def process(blend):
    vehicle = blend.stem
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    scene = bpy.context.scene

    trailer = bpy.data.objects.get(TRAILER)
    new_trailer = trailer is None
    if new_trailer:
        if vehicle not in EQUIPMENT:
            raise SystemExit(f"{vehicle} : ni remorque ni equipement connu")
        trailer = build_plateau_trailer(vehicle)

    keep = {trailer} | set(trailer.children_recursive)
    delete([o for o in scene.objects if o not in keep and o.name not in SCENE_PROPS])
    if new_trailer:
        delete([o for o in trailer.children_recursive if o.name.startswith("Socket_")])
        place_trailer_sockets(trailer)
    for n in TRAILER_SOCKETS:
        if n not in bpy.data.objects:
            raise SystemExit(f"{vehicle} : {n} manquant sur la remorque")

    body, wheels, s = import_tractor()
    socks = place_tractor_sockets(body)

    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    objs = [o for o in scene.objects if o.name not in SCENE_PROPS]
    export.to_glb(blend.with_suffix(".glb"), objs)

    names = sorted(o.name for o in objs if o.name.startswith("Socket_"))
    expected = sorted(TRACTOR_SOCKETS + TRAILER_SOCKETS)
    if names != expected:
        raise SystemExit(f"{vehicle} : sockets {names} != {expected}")
    print(f"OK {vehicle} echelle_tete={s:.3f} sockets={len(names)} "
          + " ".join(f"{k[7:]}={tuple(round(x, 2) for x in v)}" for k, v in socks.items()))


def main():
    bpy.context.preferences.filepaths.save_version = 0   # pas de .blend1
    args = parse_args()
    if not TRACTOR_GLB.exists():
        raise SystemExit(f"tete introuvable : {TRACTOR_GLB} (git lfs pull ?)")
    blends = sorted(CATALOGUE.glob("*.blend"))
    if args.only:
        blends = [b for b in blends if b.stem in args.only]
    for b in blends:
        process(b)
    print(f"OK {CATALOGUE} vehicules={len(blends)}")


main()
