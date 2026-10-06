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
    # chaque engin devient une semi-remorque dediee, pas un objet pose
    meshes = flatten([o for o in load if o.type == "MESH"])
    delete([o for o in load if alive(o) and o.type != "MESH"])
    BUILDERS[vehicle](meshes, trailer)
    for o in meshes:
        reparent_keep(o, trailer)
    return trailer


# Plateau de remorque.blend (repere Blender : avant +Y, haut +Z).
DECK_TOP = 2.22
DECK_FRONT = -0.2     # la caisse commence derriere la sellette (z Godot 0,48)
DECK_REAR = -15.5
DECK_HALF_W = 1.57
# Les caisses de porteur etaient posees sur un chassis a z = 1,1.
PORTEUR_FLOOR = 1.1


def flatten(meshes):
    """Detache les maillages et applique leurs transformations (repere monde)."""
    for o in meshes:
        reparent_keep(o, None)
        if o.data.users > 1:
            o.data = o.data.copy()
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    if meshes:
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return meshes


def transform(meshes, m):
    for o in meshes:
        o.data.transform(m)
        o.data.update()


def stretch_on_deck(meshes, floor_z):
    """Etire le groupe sur toute la longueur du plateau, plancher sur le plateau."""
    mn, mx = world_bbox(meshes)
    k = (DECK_FRONT - DECK_REAR) / (mx.y - mn.y)
    m = (Matrix.Translation((-(mn.x + mx.x) / 2, DECK_FRONT, DECK_TOP))
         @ Matrix.Diagonal((1.0, k, 1.0, 1.0))
         @ Matrix.Translation((0.0, -mx.y, -floor_z)))
    transform(meshes, m)


def material(name, color, metallic=0.0, roughness=0.6):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        mat.diffuse_color = (*color, 1.0)
    return mat


def box(name, center, size, mat, rot_x=0.0):
    """Pave, origine au monde (transformations appliquees)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    o.data.transform(Matrix.Rotation(rot_x, 4, "X") @ Matrix.Diagonal((*size, 1.0)))
    o.data.transform(Matrix.Translation(center))
    o.data.materials.append(mat)
    return o


def build_pompier(meshes, trailer):
    """Fourgon pompier sur toute la longueur, echelle allongee sur le toit.

    Fourgon et echelle sont etires chacun sur leur propre longueur : l'echelle,
    plus longue que le fourgon, deborderait sinon sur le tracteur.
    """
    ladder = [o for o in meshes if o.name.startswith("Echelle")]
    stretch_on_deck([o for o in meshes if o not in ladder], PORTEUR_FLOOR)
    stretch_on_deck(ladder, PORTEUR_FLOOR)


def build_saleuse(meshes, trailer):
    """Tremie a sel sur toute la longueur, epandeur a l'arriere."""
    stretch_on_deck(meshes, PORTEUR_FLOOR)


def build_grue(meshes, trailer):
    """Porte-grue : grue a l'arriere sur bequilles, poutres d'acier sanglees."""
    s = 1.5
    mn, mx = world_bbox([o for o in meshes if o.name == "Grue_Tourelle"])
    base = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    crane_y = DECK_REAR + 1.9
    # sur son socle (0,4 m) : la tourelle ne traverse pas le plateau
    transform(meshes, Matrix.Translation((0.0, crane_y, DECK_TOP + 0.4)) @ Matrix.Scale(s, 4)
              @ Matrix.Translation(-base))
    jaune = material("Peinture_Cabine_Jaune", (0.95, 0.75, 0.05))
    danger = material("Danger_Jaune", (0.95, 0.75, 0.05))
    noir = material("Chassis", (0.05, 0.05, 0.05), 0.4, 0.5)
    acier = material("Acier_Poutre", (0.45, 0.16, 0.08), 0.3, 0.55)
    bois = material("Bois", (0.45, 0.3, 0.15))
    sangle = material("Sangle", (0.9, 0.35, 0.05), 0.0, 0.8)
    parts = []
    # socle de la grue et bequilles stabilisatrices (repliees le long du flanc)
    parts.append(box("Grue_Socle", (0.0, crane_y, DECK_TOP + 0.2), (2.6, 2.4, 0.4), noir))
    for side in (-1.0, 1.0):
        for dy in (-0.9, 0.9):
            y = crane_y + dy
            parts.append(box("Grue_Bequille_Bras", (side * 1.75, y, 1.75), (0.5, 0.35, 0.3), danger))
            parts.append(box("Grue_Bequille_Pied", (side * 1.95, y, 1.0), (0.22, 0.22, 1.4), jaune))
            parts.append(box("Grue_Bequille_Patin", (side * 1.95, y, 0.3), (0.5, 0.5, 0.08), noir))
    # chargement : trois rangs de poutres sur cales, sangles
    y0, y1 = DECK_FRONT - 0.5, crane_y + 1.8
    length = y0 - y1
    yc = (y0 + y1) / 2
    for layer in range(3):
        z = DECK_TOP + 0.12 + layer * 0.5
        for y in (y0 - 0.8, yc, y1 + 0.8):
            parts.append(box("Grue_Cale", (0.0, y, z), (2.8, 0.25, 0.12), bois))
        for i in range(4 - layer % 2):
            x = (i - (3 - layer % 2) / 2) * 0.7
            parts.append(box("Grue_Poutre", (x, yc, z + 0.27), (0.3, length, 0.4), acier))
    top = DECK_TOP + 0.12 + 2 * 0.5 + 0.5
    for y in (y0 - 2.5, yc, y1 + 2.5):
        parts.append(box("Grue_Sangle", (0.0, y, top), (2.9, 0.08, 0.03), sangle))
        for side in (-1.0, 1.0):
            parts.append(box("Grue_Sangle", (side * 1.45, y, (top + DECK_TOP) / 2),
                             (0.03, 0.08, top - DECK_TOP), sangle))
    meshes.append(join(parts, "Grue_Chargement"))


def build_chariot(meshes, trailer):
    """Remorque palettes, ridelles, chariot embarque accroche a l'arriere."""
    bois = material("Bois", (0.45, 0.3, 0.15))
    film = material("Film_Palette", (0.72, 0.8, 0.86), 0.0, 0.25)
    carton = material("Carton", (0.62, 0.45, 0.25), 0.0, 0.85)
    noir = material("Chassis", (0.05, 0.05, 0.05), 0.4, 0.5)
    danger = material("Danger_Jaune", (0.95, 0.75, 0.05))
    parts = []
    # palettes filmees : 2 colonnes, hauteurs variees (fixes : idempotent)
    heights = [1.3, 1.1, 1.4, 1.2, 1.35, 1.0, 1.25, 1.4, 1.15, 1.3, 1.2, 1.4, 1.1, 1.3, 1.25, 1.35, 1.2, 1.1]
    for row in range(9):
        y = DECK_FRONT - 0.85 - row * 1.55
        for col, x in enumerate((-0.68, 0.68)):
            h = heights[row * 2 + col]
            parts.append(box("Chariot_Palette", (x, y, DECK_TOP + 0.07), (1.2, 1.4, 0.14), bois))
            mat = film if (row + col) % 3 else carton
            parts.append(box("Chariot_Colis", (x, y, DECK_TOP + 0.14 + h / 2), (1.15, 1.35, h), mat))
    # ridelles : poteaux et lisses
    for y in [DECK_FRONT - 0.1 - i * 1.925 for i in range(9)]:
        for side in (-1.0, 1.0):
            parts.append(box("Chariot_Poteau", (side * (DECK_HALF_W - 0.04), y, DECK_TOP + 0.9),
                             (0.08, 0.1, 1.8), noir))
    for z in (DECK_TOP + 0.9, DECK_TOP + 1.75):
        for side in (-1.0, 1.0):
            parts.append(box("Chariot_Lisse", (side * (DECK_HALF_W - 0.04), (DECK_FRONT + DECK_REAR) / 2, z),
                             (0.06, DECK_FRONT - DECK_REAR, 0.08), danger))
    # chariot embarque : fourches engagees sous l'arriere du plateau, souleve
    lift = [o for o in meshes if not o.name.startswith("Chariot_Palette")]
    mn, mx = world_bbox(lift)
    rear = DECK_REAR - 0.45
    transform(lift, Matrix.Translation((0.0, rear + 1.0 - mx.y, 0.35)))
    for side in (-1.0, 1.0):
        parts.append(box("Chariot_Fourreau", (side * 0.5, rear + 0.6, 1.0), (0.3, 1.4, 0.25), noir))
    meshes.append(join(parts, "Chariot_Chargement"))


BUILDERS = {
    "pompier": build_pompier,
    "chasse_neige": build_saleuse,
    "grue": build_grue,
    "chariot_elevateur": build_chariot,
}


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
