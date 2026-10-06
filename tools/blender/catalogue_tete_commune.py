"""Catalogue de vehicules : meme tete de camion partout, une remorque unique chacun.

    blender -b -P tools/blender/catalogue_tete_commune.py
    blender -b -P tools/blender/catalogue_tete_commune.py -- --only grue

Pour chaque vehicule de Assets_Visuels/Armes_et_camions/vehicules/ :
  1. la tete (Body + Wheel_FL/FR/RL/RR) est remplacee par le tracteur du camion
     de course de l'equipe (Camion_Bleu.glb), ajuste a VEHICLE_SPEC comme le
     fait TruckVisual en jeu : demi-tour (avant en -Z Godot), echelle uniforme
     pour une longueur de tracteur de 6,96 m, centre, pneus au sol ;
  2. la semi-remorque `Remorque` (pivot a la sellette) est UNIQUE : chacune a
     son chassis et son train roulant (nombre, ecartement et taille des
     essieux, roues simples ou jumelees, jantes, garde-boue, bequilles, feux),
     generes ici. Les caisses dessinees par l'equipe (conteneur, citerne,
     betaillere, porte-voitures) sont gardees ; grue, pompier, saleuse et
     porte-engins sont entierement generes ;
  3. les points d'accroche des armes sont reposes : Socket_Avant,
     Socket_Lateral_G/D et Socket_Toit sur la tete (donc aux MEMES coordonnees
     sur tous les vehicules), Socket_Arriere et Socket_Conteneur sur la remorque ;
  4. en virage, la remorque pivote (+-35 deg) et penche (+-6 deg) au-dessus des
     roues arriere du tracteur : rien ne doit y entrer. swing_violations le
     verifie (surfaces echantillonnees, pas seulement les sommets) et refuse la
     remorque sinon ; les caisses de l'equipe y sont adaptees (petites pieces
     retirees, cadre du porte-voitures coupe, ventre de la citerne remonte).

Tout ce qui est genere porte le prefixe GEN : une relance l'efface et le
refait (idempotent). Le .blend et le .glb de chaque vehicule sont reecrits.
Repere Blender : avant +Y, haut +Z ; sellette en (0 ; -1,44 ; 2,16).
"""

import argparse
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.append(str(Path(__file__).parent))
from lib import export  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOGUE = REPO_ROOT / "Assets_Visuels" / "Armes_et_camions" / "vehicules"
TRACTOR_GLB = REPO_ROOT / "Assets_Visuels" / "Camion" / "Camions_Course_Export" / "Camion_Bleu.glb"

# VEHICLE_SPEC §2 : longueur du tracteur (5,8 m x 1,2) ; sellette §5 bis.
TRACTOR_LENGTH = 6.96
KINGPIN = Vector((0.0, -1.44, 2.16))
TRAILER = "Remorque"
GEN = "Gen_"
TRACTOR_SOCKETS = ["Socket_Avant", "Socket_Lateral_G", "Socket_Lateral_D", "Socket_Toit"]
TRAILER_SOCKETS = ["Socket_Arriere", "Socket_Conteneur"]
# Decor de presentation des .blend : conserve, jamais exporte.
SCENE_PROPS = {"Sol", "Camera", "Soleil"}
# Pieces de l'ancien chassis commun, remplacees par un chassis propre.
SHARED_PARTS = ("Remorque_Chassis", "Remorque_Roues", "Remorque_Plateau")
# Chariot elevateur (source du porte-engins), garde d'une execution a l'autre.
FORKLIFT = "Chariot_Elevateur"


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--only", nargs="*", default=None)
    return p.parse_args(argv)


# ---------------------------------------------------------------- utilitaires


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


def material(name, color, metallic=0.0, roughness=0.6, emission=0.0):
    """Materiau du fichier s'il existe (couleurs de l'equipe), sinon cree."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission > 0.0:
            bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission
        mat.diffuse_color = (*color, 1.0)
    return mat


def M():
    """Materiaux communs, regles comme ceux de la tete (Camion_*.glb : couleur
    unie, metal / rugosite, emission des feux), crees a la demande."""
    return {
        "noir": material("Chassis", (0.05, 0.05, 0.05), 0.3, 0.6),
        "acier": material("Acier_Sellette", (0.12, 0.12, 0.13), 0.9, 0.4),
        "chrome": material("Chrome", (0.9, 0.9, 0.9), 1.0, 0.08),
        "alu": material("Aluminium", (0.7, 0.7, 0.72), 1.0, 0.3),
        "pneu": material("Pneu", (0.01, 0.01, 0.01), 0.0, 0.85),
        "plastique": material("Plastique_Noir", (0.02, 0.02, 0.02), 0.0, 0.55),
        "caoutchouc": material("Caoutchouc", (0.015, 0.015, 0.015), 0.0, 0.95),
        "feu": material("Feu_Arriere", (0.6, 0.0, 0.0), 0.0, 0.1, 2.0),
        "orange": material("Clignotant", (1.0, 0.45, 0.0), 0.0, 0.1, 1.5),
        "recul": material("Feu_Recul", (0.95, 0.95, 0.9), 0.0, 0.05, 0.6),
        "catadioptre": material("Catadioptre", (0.75, 0.0, 0.0), 0.2, 0.12, 0.3),
        "plaque": material("Plaque_Fond", (0.85, 0.85, 0.83), 0.0, 0.35),
        "danger": material("Danger_Jaune", (0.95, 0.75, 0.05), 0.0, 0.4),
        "danger_noir": material("Danger_Noir", (0.03, 0.03, 0.03), 0.0, 0.5),
        "bois": material("Bois", (0.45, 0.3, 0.15), 0.0, 0.7),
        "vitre": material("Vitre", (0.04, 0.06, 0.07), 0.0, 0.02),
        "bande_rouge": material("Bande_Reflechissante_Rouge", (0.8, 0.02, 0.02), 0.1, 0.2, 0.2),
        "bande_blanche": material("Bande_Reflechissante_Blanche", (0.95, 0.95, 0.95), 0.1, 0.2, 0.1),
        "bande_jaune": material("Bande_Reflechissante_Jaune", (1.0, 0.72, 0.0), 0.1, 0.2, 0.15),
        "flexible_rouge": material("Flexible_Rouge", (0.7, 0.02, 0.02), 0.0, 0.4),
        "flexible_bleu": material("Flexible_Bleu", (0.02, 0.15, 0.7), 0.0, 0.4),
    }

# ---------------------------------------------------------------- primitives
# Chaque primitive renvoie un objet dont la geometrie est deja au monde, finie
# comme la tete : aretes vives chanfreinees, ombrage lisse, aretes nettes
# au-dela de SHARP_DEG.

SHARP_DEG = 35.0


def finish(o, bevel, segments=2):
    """Chanfrein des aretes vives (largeur `bevel`, 0 = aucun) et ombrage :
    lisse partout, net sur les aretes de plus de SHARP_DEG."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    sharp = math.radians(SHARP_DEG)
    if bevel > 0.0:
        edges = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0.0) > sharp]
        if edges:
            bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=segments,
                            profile=0.5, affect="EDGES", clamp_overlap=True)
    for face in bm.faces:
        face.smooth = True
    for e in bm.edges:
        e.smooth = not (e.is_manifold and e.calc_face_angle(0.0) > sharp) and e.is_manifold
    bm.to_mesh(o.data)
    # sans texture, les UV ne servent a rien (et leur bruit flottant cassait
    # l'idempotence a l'octet)
    for uv in list(o.data.uv_layers):
        o.data.uv_layers.remove(uv)
    bm.free()
    return o


def bevel_for(size):
    """Chanfrein proportionne a la plus petite cote (rien sous 3 cm)."""
    d = min(size)
    if d < 0.03:
        return 0.0, 1
    return min(0.035, d * 0.18), (2 if d > 0.12 else 1)



def box(name, center, size, mat, rot_x=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    o = bpy.context.active_object
    o.name = GEN + name
    o.data.name = GEN + name
    o.data.transform(Matrix.Rotation(rot_x, 4, "X") @ Matrix.Diagonal((*size, 1.0)))
    o.data.transform(Matrix.Translation(center))
    o.data.materials.append(mat)
    w, seg = bevel_for(size)
    return finish(o, w, seg)


def beam(name, p0, p1, width, thick, mat):
    """Pave de largeur `width` (x) et d'epaisseur `thick`, de p0 a p1 (plan YZ)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    angle = math.atan2(d.z, d.y)
    o = box(name, (0, 0, 0), (width, d.length, thick), mat, rot_x=angle)
    o.data.transform(Matrix.Translation((p0 + p1) / 2))
    return o


def cyl(name, center, radius, depth, axis, mat, verts=20):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth)
    o = bpy.context.active_object
    o.name = GEN + name
    o.data.name = GEN + name
    rot = {"X": Matrix.Rotation(math.pi / 2, 4, "Y"), "Y": Matrix.Rotation(math.pi / 2, 4, "X"),
           "Z": Matrix.Identity(4)}[axis]
    o.data.transform(rot)
    o.data.transform(Matrix.Translation(center))
    o.data.materials.append(mat)
    w = min(0.02, radius * 0.15, depth * 0.2)
    return finish(o, w if w >= 0.004 else 0.0, 1)


def tube(name, p0, p1, radius, mat, verts=10):
    """Cylindre de p0 a p1 (verins, tubes, chaines)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=d.length)
    o = bpy.context.active_object
    o.name = GEN + name
    o.data.name = GEN + name
    o.data.transform(Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4())
    o.data.transform(Matrix.Translation((p0 + p1) / 2))
    o.data.materials.append(mat)
    return finish(o, 0.0)


def prism(name, profile, y0, y1, mat):
    """Profil (x, z) extrude de y0 a y1, ferme aux deux bouts."""
    me = bpy.data.meshes.new(GEN + name)
    bm = bmesh.new()
    a = [bm.verts.new((x, y0, z)) for x, z in profile]
    b = [bm.verts.new((x, y1, z)) for x, z in profile]
    n = len(profile)
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(GEN + name, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(mat)
    return finish(o, 0.03, 2)


def lathe(name, profile, segs, mat, center, side, closed=False):
    """Piece de revolution autour de l'axe X : profil (decalage le long de
    l'axe, vers l'exterieur si side > 0 ; rayon). `closed` : le profil boucle
    (pneu). Les rayons nuls se referment au centre."""
    cx, cy, cz = center
    me = bpy.data.meshes.new(GEN + name)
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        a = 2.0 * math.pi * i / segs
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((cx + side * x, cy + ca * r, cz + sa * r)) for x, r in profile])
    n = len(profile)
    last = n if closed else n - 1
    for i in range(segs):
        ra, rb = rings[i], rings[(i + 1) % segs]
        for j in range(last):
            k = (j + 1) % n
            quad = (ra[j], rb[j], rb[k], ra[k])
            if len({v.co.to_tuple(5) for v in quad}) >= 3:
                try:
                    bm.faces.new(quad)
                except ValueError:
                    pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(GEN + name, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(mat)
    return finish(o, 0.0)


# ---------------------------------------------------------------- organes


# Essieux de la remorque en cours : objets separes (origine au centre de
# l'essieu) que TruckVisual anime (suspension par essieu, rotation des roues).
AXLES = []
AXLE_PREFIX = GEN + "Essieu_"


# Segments des pieces de revolution des roues (rond a l'ecran, budget tenu).
WHEEL_SEGS = 28


def tire_profile(r, w):
    """Profil d'un pneu de poids lourd : talons, flancs bombes, epaulements
    arrondis, bande de roulement a deux rainures (x le long de l'axe)."""
    h = w / 2.0
    side = [(-h + 0.02, 0.62 * r), (-h - 0.005, 0.70 * r), (-h - 0.012, 0.82 * r), (-h + 0.0, 0.92 * r),
            (-h + 0.03, 0.975 * r), (-h + 0.075, r)]
    tread = [(-0.30 * h, r), (-0.26 * h, 0.975 * r), (-0.16 * h, 0.975 * r), (-0.12 * h, r),
             (0.12 * h, r), (0.16 * h, 0.975 * r), (0.26 * h, 0.975 * r), (0.30 * h, r)]
    other = [(-x, rr) for x, rr in reversed(side)]
    return side + tread + other


def wheel(pieces, x, y, r, w, side, rim, m, outer=True, nuts=10, vents=0):
    """Une roue : pneu profile, jante (fut + voile emboutie), moyeu, ecrous
    hexagonaux, ajours. `outer` : roue exterieure (voile et ecrous visibles)."""
    c = (x, y, r)
    pieces.append(lathe("Pneu", tire_profile(r, w), WHEEL_SEGS, m["pneu"], c, side, closed=True))
    h = w / 2.0
    if not outer:
        pieces.append(lathe("Jante", [(-h + 0.01, 0.6 * r), (h - 0.01, 0.6 * r), (h - 0.03, 0.3 * r),
                                      (h - 0.03, 0.0)], WHEEL_SEGS, rim, c, side))
        return
    pieces.append(lathe("Jante", [(-h + 0.01, 0.6 * r), (h - 0.03, 0.6 * r), (h - 0.005, 0.63 * r),
                                  (h + 0.005, 0.66 * r), (h - 0.01, 0.6 * r), (h - 0.05, 0.52 * r),
                                  (h - 0.07, 0.36 * r), (h - 0.06, 0.24 * r), (h - 0.05, 0.0)],
                        WHEEL_SEGS, rim, c, side))
    pieces.append(lathe("Moyeu", [(h - 0.05, 0.21 * r), (h - 0.01, 0.2 * r), (h + 0.03, 0.17 * r),
                                  (h + 0.07, 0.12 * r), (h + 0.08, 0.0)], 16, m["chrome"], c, side))
    for k in range(nuts):
        a = 2.0 * math.pi * k / nuts
        pieces.append(cyl("Ecrou", (x + side * (h - 0.03), y + math.cos(a) * 0.29 * r, r + math.sin(a) * 0.29 * r),
                          0.028, 0.06, "X", m["chrome"], 6))
    for k in range(vents):
        a = 2.0 * math.pi * (k + 0.5) / vents
        pieces.append(cyl("Ajour", (x + side * (h - 0.058), y + math.cos(a) * 0.44 * r, r + math.sin(a) * 0.44 * r),
                          0.05 * r + 0.012, 0.012, "X", m["noir"], 10))


def axle(parts, y, r, w, dual, rim, m, track=1.25, nuts=10, vents=0):
    """Essieu : roues (simples larges ou jumelees), essieu et tambours. Un
    objet a part (AXLES), origine au centre de l'essieu ; `parts` n'est pas
    utilise (garde pour l'appel uniforme des remorques)."""
    pieces = []
    for side in (-1.0, 1.0):
        wheel(pieces, side * (track - w / 2), y, r, w, side, rim, m, True, nuts, vents)
        if dual:
            wheel(pieces, side * (track - w * 1.5 - 0.03), y, r, w, side, rim, m, False)
        inner = track - w * (2 if dual else 1) - 0.06
        pieces.append(cyl("Tambour", (side * (inner - 0.06), y, r), 0.28 * r, 0.14, "X", m["acier"], 16))
    pieces.append(cyl("Essieu", (0.0, y, r), 0.07, 2 * track - 0.4, "X", m["noir"], 12))
    o = join(pieces, f"{AXLE_PREFIX}{len(AXLES) + 1}")
    set_origin(o, Vector((0.0, y, r)))
    AXLES.append(o)
    return o

def kingpin_plate(parts, m, y_front=0.0, width=1.6, top=2.3):
    """Plaque d'attelage (dessous a la hauteur de la sellette) et pivot."""
    parts.append(box("Plaque_Attelage", (0.0, (y_front + KINGPIN.y - 1.0) / 2, (KINGPIN.z + top) / 2),
                     (width, y_front - KINGPIN.y + 1.0, top - KINGPIN.z), m["acier"]))
    parts.append(cyl("Pivot_Attelage", (0.0, KINGPIN.y, KINGPIN.z - 0.08), 0.05, 0.16, "Z", m["chrome"], 10))


def landing_gear(parts, y, top, m, x=0.95, leg=0.16):
    """Bequilles avant (deux jambes, patins, manivelle)."""
    for side in (-1.0, 1.0):
        parts.append(box("Bequille", (side * x, y, (0.28 + top) / 2), (leg, leg, top - 0.28), m["noir"]))
        parts.append(box("Bequille_Patin", (side * x, y, 0.15), (0.32, 0.32, 0.06), m["noir"]))
    parts.append(box("Bequille_Traverse", (0.0, y, top - 0.35), (2 * x, 0.08, 0.08), m["noir"]))
    parts.append(box("Manivelle", (x + 0.15, y, top - 0.6), (0.3, 0.04, 0.04), m["acier"]))


def fender(parts, y0, y1, top, width, mat, track=1.25):
    """Garde-boue au-dessus des roues, de y0 a y1, de chaque cote."""
    for side in (-1.0, 1.0):
        parts.append(box("Garde_Boue", (side * (track - width / 2), (y0 + y1) / 2, top),
                         (width + 0.06, abs(y0 - y1), 0.05), mat))


def mud_flaps(parts, y, m, track=1.25):
    for side in (-1.0, 1.0):
        parts.append(box("Bavette", (side * (track - 0.35), y, 0.55), (0.6, 0.02, 0.6), m["caoutchouc"]))


def rear_bar(parts, y, z, m, width=2.4, lights="bloc"):
    """Pare-cycliste arriere avec ses montants, blocs de feux et catadioptres,
    plaque (style de feux propre a chaque remorque)."""
    parts.append(box("Pare_Cycliste", (0.0, y, z), (width, 0.12, 0.16), m["noir"]))
    parts.append(box("Pare_Cycliste_Zebra", (0.0, y - 0.065, z), (width * 0.9, 0.01, 0.1), m["bande_rouge"]))
    for side in (-1.0, 1.0):
        parts.append(box("Pare_Cycliste_Montant", (side * width * 0.35, y + 0.15, z + 0.35),
                         (0.1, 0.1, 0.7), m["noir"]))
        if lights == "colonne":
            parts.append(box("Feux_Boitier", (side * (width / 2 - 0.08), y - 0.04, z + 0.55), (0.14, 0.07, 0.95),
                             m["plastique"]))
            for k, mat in enumerate((m["feu"], m["feu"], m["orange"], m["recul"])):
                parts.append(box("Feu", (side * (width / 2 - 0.08), y - 0.08, z + 0.2 + k * 0.22),
                                 (0.1, 0.02, 0.18), mat))
            tri = prism("Catadioptre", [(-0.09, -0.07), (0.09, -0.07), (0.0, 0.08)], y - 0.012, y + 0.008,
                        m["catadioptre"])
            tri.data.transform(Matrix.Translation((side * (width / 2 - 0.35), 0.0, z + 0.02)))
            parts.append(tri)
        else:
            light_cluster(parts, side * (width / 2 - 0.3), y - 0.07, z + 0.2, m, style=lights)
    parts.append(box("Plaque", (0.0, y - 0.07, z + 0.03), (0.52, 0.02, 0.12), m["plaque"]))
    parts.append(box("Plaque_Eclairage", (0.0, y - 0.07, z + 0.12), (0.12, 0.03, 0.03), m["plastique"]))

def beacon(parts, x, y, z, m):
    parts.append(cyl("Gyrophare_Socle", (x, y, z - 0.1), 0.13, 0.04, "Z", m["plastique"], 16))
    parts.append(cyl("Gyrophare", (x, y, z), 0.11, 0.18, "Z", m["orange"], 16))


# ---------------------------------------------------------------- details
# Ce qui fait une vraie semi-remorque : marquage de contour, feux de gabarit,
# blocs de feux, catadioptres, flexibles d'air, roue de secours, coffre.


def contour_tape(parts, x, y0, y1, z, mats, seg=0.5, height=0.05):
    """Bande retroreflechissante le long d'un flanc (x fixe), de y0 a y1 :
    segments alternes si plusieurs materiaux (marquage de contour)."""
    side = 1.0 if x >= 0 else -1.0
    n = max(1, int(abs(y1 - y0) / seg))
    step = (y1 - y0) / n
    for k in range(n):
        y = y0 + step * (k + 0.5)
        parts.append(box("Bande", (x + side * 0.006, y, z), (0.012, abs(step) * 0.92, height), mats[k % len(mats)]))


def rear_outline(parts, y, x_half, z0, z1, m, mats=None):
    """Marquage de contour arriere : cadre rouge (ou alterne) autour de la caisse."""
    mats = mats or [m["bande_rouge"]]
    parts.append(box("Contour_Bas", (0.0, y - 0.006, z0), (2 * x_half, 0.012, 0.05), mats[0]))
    parts.append(box("Contour_Haut", (0.0, y - 0.006, z1), (2 * x_half, 0.012, 0.05), mats[-1]))
    for side in (-1.0, 1.0):
        n = max(1, int((z1 - z0) / 0.45))
        for k in range(n):
            z = z0 + (z1 - z0) * (k + 0.5) / n
            parts.append(box("Contour_Montant", (side * x_half, y - 0.006, z), (0.05, 0.012, (z1 - z0) / n * 0.9),
                             mats[k % len(mats)]))


def side_markers(parts, x, y0, y1, z, m, spacing=3.0):
    """Feux de gabarit lateraux orange : boitier noir et cabochon."""
    side = 1.0 if x >= 0 else -1.0
    n = max(1, int(abs(y1 - y0) / spacing))
    for k in range(n + 1):
        y = y0 + (y1 - y0) * k / max(n, 1)
        parts.append(box("Gabarit_Boitier", (x + side * 0.02, y, z), (0.04, 0.13, 0.07), m["plastique"]))
        parts.append(box("Gabarit", (x + side * 0.045, y, z), (0.012, 0.1, 0.045), m["orange"]))


def light_cluster(parts, x, y, z, m, width=0.48, style="bloc"):
    """Bloc de feux arriere : boitier, feu rouge, clignotant, recul, et
    catadioptre triangulaire (obligatoire sur une remorque)."""
    parts.append(box("Feux_Boitier", (x, y + 0.03, z), (width + 0.04, 0.07, 0.17), m["plastique"]))
    if style == "rond":
        for k, mat in enumerate((m["feu"], m["orange"], m["recul"])):
            parts.append(cyl("Feu", (x - width / 2 + 0.08 + k * (width - 0.16) / 2, y - 0.01, z), 0.058, 0.03, "Y",
                             mat, 16))
    else:
        parts.append(box("Feu", (x - width * 0.18, y - 0.01, z), (width * 0.5, 0.025, 0.11), m["feu"]))
        parts.append(box("Clignotant", (x + width * 0.2, y - 0.01, z), (width * 0.18, 0.025, 0.11), m["orange"]))
        parts.append(box("Recul", (x + width * 0.4, y - 0.01, z), (width * 0.12, 0.025, 0.11), m["recul"]))
    # catadioptre triangulaire sous le bloc
    tri = prism("Catadioptre", [(-0.09, -0.07), (0.09, -0.07), (0.0, 0.08)], y - 0.012, y + 0.008, m["catadioptre"])
    tri.data.transform(Matrix.Translation((x, 0.0, z - 0.2)))
    parts.append(tri)


def air_couplings(parts, y, z, m, x=0.35, coils=3):
    """Tetes d'accouplement (rouge : alimentation, bleue : frein) sur la face
    avant, et flexibles spirales qui pendent vers l'avant."""
    for side, mat in ((-1.0, m["flexible_rouge"]), (1.0, m["flexible_bleu"])):
        cx = side * x
        parts.append(box("Tete_Accouplement", (cx, y + 0.06, z), (0.12, 0.12, 0.1), mat))
        prev = Vector((cx, y + 0.12, z))
        steps = coils * 10
        for k in range(1, steps + 1):
            t = k / steps
            a = 2.0 * math.pi * coils * t
            p = Vector((cx + math.cos(a) * 0.07, y + 0.12 + 0.38 * t, z - 0.25 * t + math.sin(a) * 0.07))
            parts.append(tube("Flexible", prev, p, 0.014, mat, 6))
            prev = p


def spare_wheel(parts, y, z, r, w, rim, m):
    """Roue de secours couchee sous le chassis, dans son berceau."""
    pieces = []
    wheel(pieces, 0.0, 0.0, r, w, 1.0, rim, m, True, 8, 0)
    o = join(pieces, GEN + "Roue_Secours")
    o.data.transform(Matrix.Translation((0.0, 0.0, -r)))
    o.data.transform(Matrix.Rotation(math.pi / 2, 4, "Y"))
    o.data.transform(Matrix.Translation((0.0, y, z)))
    o.matrix_world = Matrix.Identity(4)
    parts.append(o)
    for side in (-1.0, 1.0):
        parts.append(box("Berceau_Secours", (side * (r + 0.04), y, z + 0.1), (0.05, 0.08, 0.35), m["noir"]))


def toolbox(parts, x, y, z, m, length=1.0, mat=None):
    """Coffre a outils sous le chassis : caisse, couvercle, poignee."""
    side = 1.0 if x >= 0 else -1.0
    parts.append(box("Coffre", (x, y, z), (0.5, length, 0.45), mat or m["alu"]))
    parts.append(box("Coffre_Couvercle", (x + side * 0.252, y, z + 0.02), (0.01, length - 0.06, 0.36), m["plastique"]))
    parts.append(box("Coffre_Poignee", (x + side * 0.27, y, z + 0.12), (0.02, 0.18, 0.03), m["chrome"]))


# ---------------------------------------------------------------- remorques
# Chaque fonction ajoute ses pieces a `parts` et renvoie l'arriere de la
# remorque (y), la hauteur du haut de l'arriere et celle du chassis arriere
# (points d'accroche Socket_Arriere / Socket_Conteneur).


def trailer_conteneur(parts, m):
    """Chassis squelette porte-conteneur rouge, 3 essieux jumeles, jantes alu."""
    rouge = material("Peinture_Cabine_Rouge", (0.75, 0.05, 0.05), 0.3, 0.35)
    kingpin_plate(parts, m, y_front=0.0, width=1.4, top=2.21)
    for side in (-1.0, 1.0):
        # longerons : col plat au-dessus de la sellette, plus hauts ensuite
        parts.append(box("Longeron", (side * 0.5, -1.95, 2.135), (0.16, 3.9, 0.15), rouge))
        parts.append(beam("Longeron_Col", (side * 0.5, -3.9, 2.135), (side * 0.5, -4.6, 1.88), 0.16, 0.3, rouge))
        parts.append(box("Longeron", (side * 0.5, -10.08, 1.88), (0.16, 10.95, 0.66), rouge))
    for y in (-0.15, -3.9, -6.9, -9.9, -15.2):
        parts.append(box("Traverse_Verrou", (0.0, y, 2.14), (2.9, 0.22, 0.14), rouge))
        for side in (-1.0, 1.0):
            parts.append(box("Verrou_Tournant", (side * 1.35, y, 2.2), (0.16, 0.16, 0.06), m["chrome"]))
    for y in (-11.3, -12.65, -14.0):
        axle(parts, y, 0.52, 0.28, True, m["alu"], m, nuts=10, vents=10)
        fender(parts, y + 0.6, y - 0.6, 1.2, 0.68, m["plastique"])
    mud_flaps(parts, -14.65, m)
    landing_gear(parts, -5.0, 1.6, m)
    rear_bar(parts, -15.45, 0.62, m, lights="bloc")
    for side in (-1.0, 1.0):
        contour_tape(parts, side * 1.55, -0.2, -15.1, 2.3, [m["bande_blanche"]])
        side_markers(parts, side * 1.47, -3.9, -14.4, 2.02, m, 3.5)
    rear_outline(parts, -15.42, 1.42, 2.4, 5.2, m)
    air_couplings(parts, 0.14, 2.75, m)
    spare_wheel(parts, -6.2, 1.1, 0.52, 0.28, m["alu"], m)
    return -15.45, 5.38, 2.21


def trailer_citerne(parts, m):
    """Citerne autoportante : sellette et berceau arriere seulement, 3 essieux
    en roues simples larges, jantes blanches, tubes a flexibles et garde-boue
    inox d'un seul tenant."""
    inox = material("Citerne_Inox", (0.8, 0.82, 0.85), 1.0, 0.2)
    blanc = material("Jante_Blanche", (0.92, 0.92, 0.9), 0.2, 0.4)
    kingpin_plate(parts, m, y_front=0.3, width=1.7, top=2.45)
    parts.append(box("Berceau_Avant", (0.0, -1.2, 2.55), (1.9, 2.6, 0.25), m["noir"]))
    for y in (-4.5, -8.0):
        parts.append(box("Selle_Citerne", (0.0, y, 1.45), (1.3, 0.35, 0.2), m["noir"]))
    for side in (-1.0, 1.0):
        parts.append(box("Berceau_Arriere", (side * 0.45, -13.3, 1.4), (0.18, 5.0, 0.3), m["noir"]))
        # tubes a flexibles le long de la citerne
        parts.append(cyl("Tube_Flexible", (side * 1.15, -7.2, 1.25), 0.11, 6.0, "Y", m["alu"], 14))
        # protection laterale tubulaire
        for z in (0.7, 0.98):
            parts.append(tube("Protection_Laterale", (side * 1.32, -4.3, z), (side * 1.32, -10.7, z), 0.03,
                              m["chrome"]))
        for y in (-4.3, -7.5, -10.7):
            parts.append(box("Protection_Patte", (side * 1.32, y, 1.15), (0.05, 0.05, 0.9), m["noir"]))
        parts.append(box("Garde_Boue_Inox", (side * 1.08, -13.35, 1.32), (0.62, 4.3, 0.05), inox))
    for y in (-12.0, -13.35, -14.7):
        axle(parts, y, 0.56, 0.42, False, blanc, m, track=1.3, nuts=10, vents=0)
    mud_flaps(parts, -15.35, m)
    landing_gear(parts, -4.6, 1.5, m, x=0.8)
    rear_bar(parts, -15.75, 0.66, m, width=2.3, lights="rond")
    for side in (-1.0, 1.0):
        side_markers(parts, side * 1.34, -4.3, -10.7, 1.2, m, 2.1)
        contour_tape(parts, side * 1.33, -4.3, -10.7, 0.88, [m["bande_jaune"]], 0.6, 0.04)
    air_couplings(parts, 0.45, 2.7, m, coils=4)
    toolbox(parts, 0.9, -10.95, 1.0, m, 0.8, inox)
    return -15.75, 5.73, 1.55


def trailer_betaillere(parts, m):
    """Cadre perimetrique, jupes laterales vertes, 3 essieux tres ecartes
    jumeles, jantes noires, feux en colonne."""
    vert = material("Peinture_Caisse_Vert", (0.05, 0.35, 0.12), 0.2, 0.4)
    jante = material("Jante_Noire", (0.06, 0.06, 0.06), 0.6, 0.35)
    kingpin_plate(parts, m, y_front=0.2, width=1.5, top=2.26)
    for side in (-1.0, 1.0):
        parts.append(box("Cadre", (side * 1.62, -9.8, 1.86), (0.14, 11.6, 0.22), m["noir"]))
        parts.append(box("Longeron", (side * 0.5, -9.8, 1.74), (0.16, 11.6, 0.46), m["noir"]))
        parts.append(box("Jupe", (side * 1.8, -7.0, 1.25), (0.04, 5.6, 1.2), vert))
        parts.append(box("Jupe_Liseret", (side * 1.81, -7.0, 0.68), (0.04, 5.6, 0.06), m["danger"]))
    for y in (-4.1, -6.5, -9.0, -11.5, -14.0):
        parts.append(box("Traverse", (0.0, y, 1.86), (3.2, 0.14, 0.18), m["noir"]))
    for y in (-10.6, -12.4, -14.2):
        axle(parts, y, 0.5, 0.28, True, jante, m, nuts=8, vents=5)
        fender(parts, y + 0.58, y - 0.58, 1.15, 0.66, m["noir"])
        mud_flaps(parts, y - 0.62, m)
    landing_gear(parts, -4.4, 1.75, m)
    rear_bar(parts, -15.85, 0.6, m, width=2.6, lights="colonne")
    for side in (-1.0, 1.0):
        contour_tape(parts, side * 1.82, -4.0, -15.6, 2.06, [m["bande_blanche"]])
        side_markers(parts, side * 1.82, -4.0, -15.0, 2.14, m, 2.75)
    rear_outline(parts, -15.78, 1.75, 2.1, 6.55, m, [m["bande_rouge"], m["bande_blanche"]])
    air_couplings(parts, 0.32, 2.5, m)
    spare_wheel(parts, -8.4, 1.15, 0.5, 0.28, jante, m)
    return -15.85, 6.69, 1.97


def trailer_porte_voitures(parts, m):
    """Train surbaisse : petites roues simples, 3 essieux serres sous l'arriere,
    jantes violettes, petits garde-boue, rampes de chargement."""
    violet = material("Peinture_Cabine_Violet", (0.4, 0.1, 0.6), 0.3, 0.35)
    kingpin_plate(parts, m, y_front=-0.4, width=1.2, top=2.32)
    for side in (-1.0, 1.0):
        parts.append(box("Berceau_Arriere", (side * 0.32, -14.4, 0.86), (0.14, 3.6, 0.14), m["noir"]))
        parts.append(beam("Rampe", (side * 0.8, -16.1, 0.95), (side * 0.8, -16.5, 2.4), 0.55, 0.06, m["alu"]))
    for y in (-13.3, -14.3, -15.3):
        axle(parts, y, 0.42, 0.3, False, violet, m, track=1.2, nuts=6, vents=0)
        fender(parts, y + 0.42, y - 0.42, 0.95, 0.36, m["plastique"], track=1.2)
    landing_gear(parts, -4.5, 0.95, m, x=0.7)
    rear_bar(parts, -16.0, 0.5, m, width=2.2, lights="rond")
    for side in (-1.0, 1.0):
        side_markers(parts, side * 1.53, -4.5, -15.5, 1.05, m, 2.75)
        contour_tape(parts, side * 1.535, -4.0, -16.0, 0.97, [m["bande_jaune"]])
    air_couplings(parts, 0.3, 2.45, m, coils=2)
    toolbox(parts, 0.8, -12.4, 0.62, m, 0.7, m["plastique"])
    return -16.24, 5.5, 1.0


def trailer_saleuse(parts, m):
    """Semi-tremie a sel : caisse en V sur toute la longueur, faux-chassis,
    convoyeur, epandeur, echelle et bache ; 2 essieux en roues simples larges,
    jantes orange, garde-boue tandem."""
    orange = material("Peinture_Caisse_Orange", (0.95, 0.42, 0.04), 0.2, 0.4)
    bache = material("Bache", (0.05, 0.05, 0.06), 0.0, 0.85)
    kingpin_plate(parts, m, y_front=0.0, width=1.6, top=2.3)
    for side in (-1.0, 1.0):
        parts.append(box("Faux_Chassis", (side * 0.5, -9.7, 1.78), (0.16, 11.4, 0.36), m["noir"]))
        parts.append(beam("Faux_Chassis_Col", (side * 0.5, -1.0, 2.2), (side * 0.5, -4.0, 2.06), 0.16, 0.3,
                          m["noir"]))
    parts.append(prism("Tremie", [(-1.5, 4.7), (1.5, 4.7), (1.5, 3.5), (0.45, 2.0), (-0.45, 2.0), (-1.5, 3.5)],
                       -0.3, -14.2, orange))
    for k in range(10):
        y = -0.9 - k * 1.45
        for side in (-1.0, 1.0):
            parts.append(box("Nervure", (side * 1.53, y, 4.1), (0.06, 0.12, 1.2), orange))
    parts.append(box("Bache", (0.0, -7.25, 4.78), (2.95, 13.8, 0.16), bache))
    for k in range(7):
        parts.append(box("Bache_Sangle", (0.0, -1.2 - k * 2.0, 4.87), (2.97, 0.08, 0.03), m["danger"]))
    parts.append(box("Convoyeur", (0.0, -9.5, 1.85), (0.75, 11.0, 0.3), m["acier"]))
    parts.append(box("Goulotte", (0.0, -14.75, 1.55), (0.7, 1.1, 0.7), m["alu"]))
    parts.append(cyl("Epandeur", (0.0, -15.3, 0.95), 0.55, 0.06, "Z", orange, 24))
    for k in range(4):
        a = k * math.pi / 4
        parts.append(box("Epandeur_Pale", (0.0, -15.3, 1.02), (1.0, 0.06, 0.08), m["noir"]))
        parts[-1].data.transform(Matrix.Translation((0.0, -15.3, 1.02)) @ Matrix.Rotation(a, 4, "Z")
                                 @ Matrix.Translation((0.0, 15.3, -1.02)))
    for side in (-1.0, 1.0):
        parts.append(box("Echelle_Montant", (side * 0.3, -14.27, 3.3), (0.05, 0.05, 2.8), m["alu"]))
        beacon(parts, side * 1.35, -14.0, 4.95, m)
    for k in range(7):
        parts.append(box("Echelle_Barreau", (0.0, -14.27, 2.1 + k * 0.4), (0.6, 0.04, 0.04), m["alu"]))
    for y in (-12.6, -14.0):
        axle(parts, y, 0.56, 0.42, False, orange, m, track=1.3, nuts=10, vents=6)
    fender(parts, -11.9, -14.7, 1.3, 0.5, m["plastique"], track=1.3)
    landing_gear(parts, -4.8, 1.6, m)
    rear_bar(parts, -15.9, 0.6, m, width=2.3, lights="bloc")
    for side in (-1.0, 1.0):
        contour_tape(parts, side * 1.56, -0.6, -14.0, 4.55, [m["bande_jaune"]])
        side_markers(parts, side * 1.53, -0.8, -13.8, 3.62, m, 2.6)
    rear_outline(parts, -14.22, 1.45, 3.55, 4.65, m)
    air_couplings(parts, -0.3, 2.65, m)
    toolbox(parts, -1.0, -10.6, 1.25, m, 0.8)
    return -15.9, 4.95, 1.96


def trailer_pompier(parts, m):
    """Fourgon incendie d'un seul bloc : caisse rouge jusqu'aux jupes, rehaussee
    au-dessus de la sellette, rideaux alu, grande echelle, enrouleurs ; 2
    essieux jumeles, jantes chromees."""
    rouge = material("Peinture_Cabine_Pompier", (0.75, 0.03, 0.03), 0.3, 0.35)
    blanc = material("Texte_Blanc", (0.95, 0.95, 0.95))
    bleu = material("Gyrophare_Bleu", (0.1, 0.3, 1.0), 0.0, 0.3, 3.0)
    tuyau = material("Tuyau_Incendie", (0.16, 0.16, 0.17), 0.0, 0.7)
    kingpin_plate(parts, m, y_front=0.0, width=1.6, top=2.3)
    parts.append(box("Caisse_Col", (0.0, -2.2, 3.4), (3.1, 3.8, 2.2), rouge))
    parts.append(box("Caisse_Avant", (0.0, -7.55, 2.62), (3.1, 6.9, 3.76), rouge))
    parts.append(box("Caisse_Roues", (0.0, -12.55, 2.95), (3.1, 3.1, 3.1), rouge))
    parts.append(box("Caisse_Arriere", (0.0, -14.7, 2.62), (3.1, 1.2, 3.76), rouge))
    # rideaux alu par compartiment, rainures horizontales
    bays = [(-4.3, -5.9), (-6.1, -7.7), (-7.9, -9.4), (-9.6, -10.9), (-11.15, -13.95)]
    for y0, y1 in bays:
        z0 = 1.65 if y0 < -11.0 else 1.0
        for side in (-1.0, 1.0):
            parts.append(box("Rideau", (side * 1.565, (y0 + y1) / 2, (z0 + 4.2) / 2), (0.03, abs(y1 - y0), 4.2 - z0),
                             m["alu"]))
            for k in range(int((4.2 - z0) / 0.35)):
                parts.append(box("Rideau_Rainure", (side * 1.585, (y0 + y1) / 2, z0 + 0.2 + k * 0.35),
                                 (0.02, abs(y1 - y0) - 0.06, 0.03), m["noir"]))
    for side in (-1.0, 1.0):
        parts.append(box("Bande_Blanche", (side * 1.57, -7.5, 0.85), (0.03, 6.5, 0.14), blanc))
        parts.append(box("Bande_Reflechissante", (side * 1.57, -8.0, 4.35), (0.03, 15.2, 0.14), m["danger"]))
        parts.append(box("Passage_Roue", (side * 1.57, -12.55, 1.42), (0.05, 3.2, 0.08), m["alu"]))
    # toit : passerelle, grande echelle, tourelle
    parts.append(box("Passerelle", (0.0, -8.0, 4.53), (2.0, 15.0, 0.06), m["alu"]))
    for side in (-1.0, 1.0):
        parts.append(box("Echelle_Longeron", (side * 0.5, -6.6, 4.85), (0.08, 12.8, 0.22), m["alu"]))
    for k in range(32):
        parts.append(box("Echelle_Barreau", (0.0, -0.4 - k * 0.4, 4.85), (1.0, 0.05, 0.05), m["alu"]))
    parts.append(cyl("Echelle_Tourelle", (0.0, -13.6, 4.7), 0.95, 0.3, "Z", m["noir"], 24))
    parts.append(box("Echelle_Pied", (0.0, -13.4, 4.8), (1.1, 1.0, 0.35), rouge))
    parts.append(box("Rampe_Lumineuse", (0.0, -0.4, 4.6), (2.6, 0.3, 0.12), bleu))
    # arriere : enrouleurs, marchepied
    for side in (-1.0, 1.0):
        # enrouleur de tuyau : tambour de tuyau enroule (axe horizontal), flasques
        parts.append(cyl("Enrouleur_Tuyau", (side * 0.75, -15.5, 2.75), 0.36, 0.5, "X", tuyau, 32))
        for dx in (-0.27, 0.27):
            parts.append(cyl("Enrouleur_Flasque", (side * 0.75 + dx, -15.5, 2.75), 0.44, 0.03, "X", m["alu"], 32))
        parts.append(cyl("Enrouleur_Axe", (side * 0.75, -15.5, 2.75), 0.06, 0.62, "X", m["chrome"], 12))
        parts.append(box("Enrouleur_Support", (side * 0.75, -15.38, 2.3), (0.62, 0.12, 0.5), m["alu"]))
    parts.append(box("Marchepied", (0.0, -15.45, 1.0), (2.6, 0.5, 0.06), m["alu"]))
    for y in (-11.9, -13.3):
        axle(parts, y, 0.5, 0.28, True, m["chrome"], m, nuts=10, vents=8)
    landing_gear(parts, -4.4, 0.8, m)
    rear_bar(parts, -15.6, 0.62, m, width=2.6, lights="bloc")
    for side in (-1.0, 1.0):
        # damier jaune / rouge des vehicules de secours
        contour_tape(parts, side * 1.6, -4.25, -10.75, 0.95, [m["bande_jaune"], m["bande_rouge"]], 0.4, 0.12)
        side_markers(parts, side * 1.56, -4.3, -14.9, 0.8, m, 2.6)
    rear_outline(parts, -15.31, 1.5, 0.85, 4.45, m, [m["bande_rouge"], m["bande_jaune"]])
    air_couplings(parts, -0.3, 2.6, m)
    return -15.6, 4.85, 1.0


def trailer_grue(parts, m):
    """Semi-grue : poutre-caisson centrale jaune sans plateau, grue a l'arriere
    (tourelle, cabine, contrepoids), fleche telescopique couchee vers l'avant
    sur son support, bequilles ; 4 essieux jumeles, jantes jaunes."""
    jaune = material("Peinture_Cabine_Jaune", (0.95, 0.72, 0.03), 0.2, 0.4)
    kingpin_plate(parts, m, y_front=0.0, width=1.6, top=2.3)
    parts.append(box("Col_De_Cygne", (0.0, -1.3, 2.55), (2.5, 3.0, 0.5), jaune))
    parts.append(beam("Col_Pente", (0.0, -2.8, 2.55), (0.0, -3.8, 2.05), 1.6, 0.6, jaune))
    parts.append(box("Poutre_Caisson", (0.0, -9.6, 1.95), (1.1, 12.0, 0.8), jaune))
    for y in (-9.4, -15.0):
        parts.append(box("Stabilisateur_Bras", (0.0, y, 1.9), (4.4, 0.4, 0.34), m["danger"]))
        for side in (-1.0, 1.0):
            parts.append(box("Stabilisateur_Verin", (side * 2.1, y, 1.1), (0.24, 0.24, 1.6), jaune))
            parts.append(box("Stabilisateur_Patin", (side * 2.1, y, 0.3), (0.6, 0.6, 0.08), m["noir"]))
            for k in range(3):
                parts.append(box("Zebra", (side * (1.4 + k * 0.25), y - 0.21, 1.9), (0.1, 0.01, 0.34),
                                 m["danger_noir"]))
    # grue
    parts.append(cyl("Couronne", (0.0, -12.6, 2.52), 1.1, 0.35, "Z", m["noir"], 32))
    parts.append(box("Tourelle", (0.0, -12.9, 3.2), (2.6, 3.0, 1.0), jaune))
    parts.append(box("Contrepoids", (0.0, -14.85, 3.3), (2.7, 0.9, 1.2), m["noir"]))
    for k in range(5):
        parts.append(box("Contrepoids_Zebra", (-1.2 + k * 0.6, -15.31, 3.3), (0.25, 0.01, 1.2), m["danger"]))
    parts.append(box("Cabine_Grue", (-0.85, -11.7, 3.55), (0.9, 1.4, 1.7), jaune))
    parts.append(box("Cabine_Vitre", (-0.85, -10.99, 3.8), (0.8, 0.02, 0.9), m["vitre"]))
    parts.append(box("Cabine_Vitre", (-1.31, -11.7, 3.8), (0.02, 1.2, 0.9), m["vitre"]))
    # fleche telescopique couchee vers l'avant, sur son support
    parts.append(box("Fleche_1", (0.35, -8.9, 4.2), (0.9, 7.6, 0.85), jaune))
    parts.append(box("Fleche_2", (0.35, -3.3, 4.2), (0.72, 4.0, 0.68), jaune))
    parts.append(box("Fleche_3", (0.35, -0.6, 4.2), (0.56, 1.6, 0.52), jaune))
    for k in range(4):
        parts.append(box("Fleche_Zebra", (0.35, 0.1 - k * 0.3, 4.47), (0.58, 0.14, 0.01),
                         m["danger_noir"] if k % 2 else m["danger"]))
    parts.append(box("Pied_Fleche", (0.35, -12.4, 3.95), (0.8, 0.9, 0.7), jaune))
    parts.append(tube("Verin_Levage", (0.35, -11.2, 3.4), (0.35, -8.6, 3.8), 0.13, m["chrome"]))
    for side in (-1.0, 1.0):
        parts.append(beam("Support_Fleche", (side * 0.6, -2.4, 2.8), (side * 0.35, -2.4, 3.78), 0.14, 0.14,
                          m["noir"]))
    parts.append(box("Support_Fleche_Selle", (0.35, -2.4, 3.8), (1.1, 0.3, 0.06), m["noir"]))
    parts.append(box("Moufle", (0.35, 0.05, 3.45), (0.45, 0.35, 0.5), m["danger"]))
    parts.append(tube("Crochet", (0.35, 0.05, 3.2), (0.35, 0.05, 2.95), 0.05, m["chrome"]))
    beacon(parts, 0.9, -12.0, 4.5, m)
    for y in (-10.2, -11.5, -12.8, -14.1):
        axle(parts, y, 0.5, 0.28, True, jaune, m, nuts=10, vents=4)
    fender(parts, -9.6, -14.7, 1.15, 0.66, m["noir"])
    landing_gear(parts, -4.6, 1.65, m)
    rear_bar(parts, -15.55, 0.6, m, width=2.4, lights="rond")
    for side in (-1.0, 1.0):
        contour_tape(parts, side * 0.555, -3.9, -15.4, 1.65, [m["bande_rouge"], m["bande_blanche"]])
        side_markers(parts, side * 0.56, -4.0, -9.0, 1.98, m, 2.5)
    air_couplings(parts, 0.2, 2.55, m)
    toolbox(parts, 0.85, -6.5, 1.75, m, 1.2, jaune)
    return -15.55, 3.9, 2.35


def trailer_porte_engins(parts, m, forklift):
    """Porte-engins surbaisse : col de cygne, plancher bas en bois entre les
    essieux, rampes relevees, deux chariots elevateurs arrimes, panneau convoi ;
    3 essieux a petites roues jumelees, jantes grises."""
    gris = material("Jante_Grise", (0.5, 0.5, 0.52), 0.6, 0.4)
    kingpin_plate(parts, m, y_front=0.0, width=1.6, top=2.3)
    parts.append(box("Col_De_Cygne", (0.0, -1.85, 2.5), (2.6, 4.1, 0.4), m["noir"]))
    parts.append(box("Coffre_Chaines", (0.0, -0.6, 2.95), (2.2, 0.9, 0.5), m["danger"]))
    parts.append(beam("Col_Descente", (0.0, -3.9, 2.5), (0.0, -5.2, 0.95), 2.6, 0.4, m["noir"]))
    parts.append(box("Plancher_Bas", (0.0, -8.5, 0.92), (3.0, 6.6, 0.36), m["noir"]))
    for k in range(14):
        parts.append(box("Planche", (-1.395 + k * 0.215, -8.5, 1.12), (0.2, 6.5, 0.05), m["bois"]))
    for side in (-1.0, 1.0):
        parts.append(box("Rive", (side * 1.52, -8.5, 0.95), (0.08, 6.6, 0.4), m["danger"]))
        parts.append(beam("Rampe_Relevee", (side * 0.85, -15.75, 1.45), (side * 0.85, -16.4, 3.3), 0.7, 0.08,
                          m["alu"]))
        beacon(parts, side * 1.25, -15.65, 2.7, m)
        parts.append(box("Poteau_Gyro", (side * 1.25, -15.65, 2.05), (0.06, 0.06, 1.2), m["noir"]))
    parts.append(box("Plancher_Arriere", (0.0, -13.7, 1.25), (2.9, 3.9, 0.3), m["noir"]))
    parts.append(box("Panneau_Convoi", (0.0, -15.62, 2.05), (2.2, 0.03, 0.55), m["danger"]))
    for k in range(6):
        parts.append(box("Panneau_Zebra", (-0.95 + k * 0.38, -15.64, 2.05), (0.12, 0.01, 0.55), m["danger_noir"]))
    for y in (-12.55, -13.65, -14.75):
        axle(parts, y, 0.4, 0.24, True, gris, m, track=1.3, nuts=6, vents=4)
    landing_gear(parts, -4.6, 1.55, m, x=0.85)
    rear_bar(parts, -15.75, 0.55, m, width=2.4, lights="bloc")
    # deux chariots elevateurs arrimes, fourches en avant : l'un sur le plancher
    # bas, l'autre sur le plancher arriere (le col de cygne laisse passer les
    # roues du tracteur en virage : plancher bas plus court)
    lifts = []
    for k, (y, z) in enumerate(((-7.9, 1.145), (-13.45, 1.4))):
        lift = forklift if k == 0 else forklift.copy()
        if k:
            lift.name = GEN + "Chariot_2"
            bpy.context.scene.collection.objects.link(lift)
        lift.matrix_world = Matrix.Translation((0.0, y, z))
        lifts.append(lift)
        for side in (-1.0, 1.0):
            for dy in (-1.2, 1.4):
                parts.append(tube("Chaine", (side * 0.7, y + dy * 0.8, z + 0.455), (side * 1.4, y + dy, z + 0.005), 0.02,
                                  m["chrome"], 6))
    for side in (-1.0, 1.0):
        contour_tape(parts, side * 1.565, -5.2, -11.8, 0.82, [m["bande_rouge"], m["bande_blanche"]])
        side_markers(parts, side * 1.56, -5.2, -11.6, 1.05, m, 2.1)
    air_couplings(parts, 0.2, 2.55, m)
    return -16.4, 3.3, 1.4, lifts


def forklift_source():
    """Chariot elevateur du fichier, en un maillage, origine au sol au centre."""
    src = bpy.data.objects.get(FORKLIFT)
    if src is not None:
        return src
    names = ("Body", "Mat", "Fourche", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR")
    # deja pose sur une remorque (Chariot_*), sinon le fichier d'origine ; jamais
    # les noms nus quand la tete de camion (Body, Wheel_*) est deja la
    pieces = [o for o in bpy.data.objects if o.type == "MESH" and o.name in ["Chariot_" + n for n in names]]
    if not pieces and bpy.data.objects.get(TRAILER) is None:
        pieces = [o for o in bpy.data.objects if o.type == "MESH" and o.name in names]
    if not pieces:
        raise SystemExit("porte-engins : chariot elevateur introuvable")
    src = join(pieces, FORKLIFT)
    mn, mx = world_bbox([src])
    src.data.transform(Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z)))
    src.matrix_world = Matrix.Identity(4)
    return src


# Roues arriere du tracteur telles qu'affichees en jeu (TruckVisual : modele
# ajuste, roues reduites de 8 %), repere Blender : moyeu, rayon, demi-largeur.
# Le moyeu est pris a sa position visuelle la plus haute : TruckVisual borne
# la montee des roues arriere a REAR_WHEEL_MAX_UP (garder les deux en accord).
REAR_WHEEL_MAX_UP = 0.08
TRACTOR_REAR_WHEELS = [(Vector((side * 1.41, -1.79, 0.88 + REAR_WHEEL_MAX_UP)), 0.88, 0.61) for side in (-1.0, 1.0)]
# Articulation et roulis max de la remorque (VEHICLE_SPEC §5 bis ; TruckVisual :
# lean_max_deg x lean_trailer_roll_ratio) et jeu garde autour des roues.
TRAILER_MAX_ANGLE_DEG = 35.0
TRAILER_MAX_ROLL_DEG = 6.0
SWING_CLEARANCE = 0.08

def surface_points(o, step=0.12):
    """Sommets de `o`, plus une grille sur chaque grande face : une face plate
    peut traverser une roue sans qu'aucun de ses coins n'y entre."""
    mw = o.matrix_world
    pts = [mw @ v.co for v in o.data.vertices]
    for poly in o.data.polygons:
        pts += face_points([mw @ o.data.vertices[i].co for i in poly.vertices], poly.area, step)
    return pts


def face_points(vs, area, step=0.12):
    """Grille de points sur une grande face (sommets monde `vs`)."""
    if area < 0.02 or len(vs) < 3:
        return []
    pts = []
    a, b, d = vs[0], vs[1], vs[-1]
    nu = max(1, int((b - a).length / step))
    nv = max(1, int((d - a).length / step))
    for i in range(nu + 1):
        for j in range(nv + 1):
            if len(vs) == 4:   # quadrilatere (paves) : bilineaire
                u, v = i / nu, j / nv
                pts.append(a.lerp(b, u).lerp(d.lerp(vs[2], u), v))
            elif i / nu + j / nv <= 1.0:
                pts.append(a + (b - a) * (i / nu) + (d - a) * (j / nv))
    return pts


def hits_tractor_wheels(p, angles, reach, top):
    """Vrai si le point `p` de la remorque (repere Blender) entre dans une roue
    arriere du tracteur, pour l'un des angles d'articulation et de roulis."""
    q = Vector((p.x, p.y - KINGPIN.y))
    roll_max = math.radians(TRAILER_MAX_ROLL_DEG)
    if p.z - abs(p.x) * math.sin(roll_max) - (p.z - KINGPIN.z) * (1.0 - math.cos(roll_max)) >= top \
            or q.length > reach:
        return False
    for roll in (-roll_max, 0.0, roll_max):
        # roulis de la remorque autour de son axe, a la hauteur de la sellette
        x = p.x * math.cos(roll) - (p.z - KINGPIN.z) * math.sin(roll)
        z = KINGPIN.z + p.x * math.sin(roll) + (p.z - KINGPIN.z) * math.cos(roll)
        if z >= top:
            continue
        for a in angles:
            # point de la remorque vu du tracteur, remorque pivotee de a
            rx = x * math.cos(a) - q.y * math.sin(a)
            ry = x * math.sin(a) + q.y * math.cos(a) + KINGPIN.y
            if any(abs(rx - c.x) <= hw + SWING_CLEARANCE and math.hypot(ry - c.y, z - c.z) <= r + SWING_CLEARANCE
                   for c, r, hw in TRACTOR_REAR_WHEELS):
                return True
    return False


def swing_limits():
    reach = max(Vector((c.x, c.y - KINGPIN.y)).length + r + hw for c, r, hw in TRACTOR_REAR_WHEELS)
    top = max(c.z + r for c, r, hw in TRACTOR_REAR_WHEELS) + SWING_CLEARANCE
    angles = [math.radians(a) for a in range(-int(TRAILER_MAX_ANGLE_DEG), int(TRAILER_MAX_ANGLE_DEG) + 1, 2)]
    return angles, reach, top

# Au-dela, une piece fautive est coupee (cadre) plutot que retiree entiere.
TRIM_WHOLE_MAX_VERTS = 400
# ...et une piece plus longue que ca (rail) est coupee, pas retiree (m).
TRIM_WHOLE_MAX_LENGTH = 3.0
# Caisses fermees (cuve) : remontees plutot que coupees, sur une rampe (m).
SWING_LIFT = {"Remorque_Citerne"}
LIFT_RAMP = 1.2


def trim_swing_zone(obj):
    """Retire d'une caisse de l'equipe ce qui passerait dans les roues du
    tracteur. Une petite piece fautive (accessoire, feu) part entiere ; une
    grande (cadre du porte-voitures, dont le plancher bas s'avance au-dessus
    des roues) est coupee net : plans y (derriere la zone) et z (haut des
    roues), seule la partie basse avant est retiree. Idempotent."""
    angles, reach, top = swing_limits()
    mw = obj.matrix_world
    inv = mw.inverted()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bad = {v for v in bm.verts if hits_tractor_wheels(mw @ v.co, angles, reach, top)}
    # une longue face peut traverser une roue sans qu'aucun de ses sommets n'y
    # soit : ses sommets comptent aussi, et le point fautif le plus en arriere
    # fixe la coupe
    hit_y = [(mw @ v.co).y for v in bad]
    for face in bm.faces:
        pts = face_points([mw @ v.co for v in face.verts], face.calc_area() * mw.to_3x3().determinant() ** (2 / 3))
        ys = [p.y for p in pts if hits_tractor_wheels(p, angles, reach, top)]
        if ys:
            bad.update(face.verts)
            hit_y += ys
    if not bad:
        bm.free()
        return 0
    seen = set()
    doomed = set()
    cut_y = None
    for v in bad:
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
        ys = [(mw @ x.co).y for x in part]
        if len(part) <= TRIM_WHOLE_MAX_VERTS and max(ys) - min(ys) <= TRIM_WHOLE_MAX_LENGTH:
            doomed.update(part)
        else:
            cut_y = min(hit_y) if cut_y is None else min(cut_y, min(hit_y))
    if doomed:
        bmesh.ops.delete(bm, geom=list(doomed), context="VERTS")
    if cut_y is not None and obj.name in SWING_LIFT:
        # cuve fermee : on ne la troue pas, son ventre remonte a l'avant
        # (au-dessus des roues), en douceur sur LIFT_RAMP metres
        cut_y -= 0.05
        lift_to = top + 0.01
        for v in bm.verts:
            p = mw @ v.co
            if p.z >= lift_to:
                continue
            t = min(max((p.y - (cut_y - LIFT_RAMP)) / LIFT_RAMP, 0.0), 1.0)
            t = t * t * (3.0 - 2.0 * t)
            if t > 0.0:
                v.co = inv @ Vector((p.x, p.y, p.z + (lift_to - p.z) * t))
    elif cut_y is not None:
        cut_y -= 0.05
        for co, no in (((0.0, cut_y, 0.0), (0.0, 1.0, 0.0)), ((0.0, 0.0, top), (0.0, 0.0, 1.0))):
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=inv @ Vector(co),
                                   plane_no=(inv.to_3x3().transposed() @ Vector(no)).normalized())
        low = [v for v in bm.verts if (mw @ v.co).y > cut_y + 1e-4 and (mw @ v.co).z < top - 1e-4]
        bmesh.ops.delete(bm, geom=low, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    mode = "remontee" if obj.name in SWING_LIFT else "coupe"
    print(f"ZONE DES ROUES {obj.name} : {len(bad)} sommets en cause, petites pieces retirees ({len(doomed)} sommets), {mode} a y={cut_y}")
    return len(bad)

def swing_violations(objs):
    """Pieces de remorque qui entreraient dans une roue arriere du tracteur
    quand la remorque pivote autour de la sellette (jusqu'a +-35 deg).
    Renvoie {nom : (points fautifs, y min, y max, z min)} (repere Blender)."""
    angles, reach, top = swing_limits()
    bad = {}
    for o in objs:
        if o.type != "MESH":
            continue
        for p in surface_points(o):
            if hits_tractor_wheels(p, angles, reach, top):
                n, y0, y1, z0 = bad.get(o.name, (0, 9.0, -99.0, 9.0))
                bad[o.name] = (n + 1, round(min(y0, p.y), 2), round(max(y1, p.y), 2), round(min(z0, p.z), 2))
    return bad

TRAILERS = {
    "remorque": trailer_conteneur,
    "citerne": trailer_citerne,
    "betaillere": trailer_betaillere,
    "porte_voitures": trailer_porte_voitures,
    "chasse_neige": trailer_saleuse,
    "pompier": trailer_pompier,
    "grue": trailer_grue,
    "chariot_elevateur": trailer_porte_engins,
}
# Caisses dessinees par l'equipe, gardees : le reste de la remorque est genere.
TEAM_BODIES = {"remorque", "citerne", "betaillere", "porte_voitures"}


def build_trailer(vehicle):
    """Remorque unique du vehicule, sous un pivot `Remorque` a la sellette."""
    scene = bpy.context.scene
    trailer = bpy.data.objects.get(TRAILER)
    lift = forklift_source() if vehicle == "chariot_elevateur" else None
    keep = set(SCENE_PROPS)
    if vehicle in TEAM_BODIES:
        if trailer is None:
            raise SystemExit(f"{vehicle} : remorque de l'equipe introuvable")
        keep |= {o.name for o in trailer.children_recursive
                 if not o.name.startswith(SHARED_PARTS + (GEN, "Socket_"))}
        keep.add(trailer.name)
    if lift is not None:
        keep.add(lift.name)
    delete([o for o in scene.objects if o.name not in keep])
    # materiaux et maillages de l'ancienne tete et de l'ancien chassis purges
    # AVANT de reconstruire : sinon les noms derivent (Chrome.001, .002...) et
    # deux executions ne donnent plus le meme fichier
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    if bpy.data.objects.get(TRAILER) is None:
        trailer = bpy.data.objects.new(TRAILER, None)
        scene.collection.objects.link(trailer)
        trailer.location = KINGPIN
        bpy.context.view_layer.update()

    m = M()
    AXLES.clear()
    parts = []
    if lift is not None:
        rear_y, top_z, chassis_z, lifts = trailer_porte_engins(parts, m, lift)
    else:
        rear_y, top_z, chassis_z = TRAILERS[vehicle](parts, m)
        lifts = []
    team = [o for o in trailer.children_recursive if o.type == "MESH" and not o.name.startswith(GEN)]
    for o in team:
        trim_swing_zone(o)
    bad = swing_violations(parts + AXLES + lifts + team)
    if bad:
        raise SystemExit(f"{vehicle} : en virage, la remorque traverse les roues du tracteur : {bad}")
    pieces = [join(parts, GEN + "Remorque")] + list(AXLES)
    for o in pieces + lifts:
        reparent_keep(o, trailer)
    add_socket("Socket_Arriere", Vector((0.0, round(rear_y + 0.15, 2), round(top_z, 2))), trailer)
    add_socket("Socket_Conteneur", Vector((0.0, round(rear_y + 0.3, 2), round(chassis_z + 0.1, 2))), trailer)
    return trailer


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
    fit = Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Scale(s, 4) @ Matrix.Translation(-c)
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
    if vehicle not in TRAILERS:
        raise SystemExit(f"{vehicle} : remorque inconnue")
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    scene = bpy.context.scene
    trailer = build_trailer(vehicle)
    keep = {trailer} | set(trailer.children_recursive)
    delete([o for o in scene.objects if o not in keep and o.name not in SCENE_PROPS])

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
    tris = sum(len(p.vertices) - 2 for o in trailer.children_recursive if o.type == "MESH"
               for p in o.data.polygons)
    print(f"OK {vehicle} echelle_tete={s:.3f} sockets={len(names)} tris_remorque={tris} "
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
