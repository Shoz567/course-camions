"""Version realiste des tracteurs et des remorques (2026-10-07 : « rends la tete
et les remorques plus realistes »).

    blender -b -P tools/blender/realisme_vehicules.py
    blender -b -P tools/blender/realisme_vehicules.py -- --only Camion_Bleu

Part des modeles de l'equipe, JAMAIS modifies, et ecrit a cote une version
detaillee (le jeu charge celle-ci, l'originale reste la source) :

    Assets_Visuels/Camion/Camions_Course_Export/Camion_*.glb
        -> Assets_Visuels/Camion/Camions_Course_Export/Realiste/Camion_*.glb
    Assets_Visuels/Armes_et_camions/vehicules/*.glb
        -> Assets_Visuels/Armes_et_camions/vehicules/Realiste/*.glb

Ce qui faisait « maquette » et ce que le script y change :
  1. aretes vives au rasoir sur des centaines de boites : chaque piece a
     angles marques recoit un chanfrein arrondi (2 segments, 4 a 18 mm selon
     sa taille) qui accroche la lumiere, et un lissage par angle (faces
     planes nettes, aretes adoucies). Pneus, jantes, textes, plaques : intacts ;
  2. tracteur : details d'un vrai camion de route - pare-soleil au-dessus du
     pare-brise, grille de calandre a barreaux verticaux, entourage noir et
     optiques rondes dans les phares, antibrouillards dans le pare-chocs,
     poignees de maintien chromees a cote des portes, pare-chaleur sur les
     cheminees d'echappement, cornets sous les retroviseurs, garde-boue
     arriere en plastique noir (plus en couleur carrosserie) ;
  3. remorques : les garde-boue plats (planches au-dessus des roues) deviennent
     des garde-boue cintres qui epousent chaque roue ; pieces de coin sur la
     caisse d'un conteneur, barres de verrouillage sur ses portes.
Le nommage contractuel (Roue_*, Remorque, Gen_Essieu_*, Phare*, Feu_*...) ne
change pas ; tout ajout porte le prefixe Detail_. Idempotent : chaque
execution repart de l'original.

Repere Blender apres import : haut +Z ; tracteur : avant en -Y ; remorques
du catalogue : avant en +Y (la caisse s'etend vers -Y depuis la sellette).
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
HEADS_DIR = REPO_ROOT / "Assets_Visuels" / "Camion" / "Camions_Course_Export"
TRAILERS_DIR = REPO_ROOT / "Assets_Visuels" / "Armes_et_camions" / "vehicules"
OUT_DIR = "Realiste"
HEADS = ["Camion_Bleu", "Camion_Rouge", "Camion_Jaune", "Camion_Vert"]
TRAILERS = ["remorque", "citerne", "betaillere", "porte_voitures", "chariot_elevateur", "chasse_neige",
            "grue", "pompier"]

DETAIL = "Detail_"
# Chanfrein : fraction de la plus petite dimension de la piece, borne (m).
BEVEL_RATIO = 0.12
BEVEL_MIN = 0.004
BEVEL_MAX = 0.018
BEVEL_SEGMENTS = 2
# Une arete est « vive » au-dela de cet angle entre ses faces.
SHARP_DEG = 35.0
# Lissage : au-dela, l'arete reste marquee (faces planes nettes).
SMOOTH_DEG = 40.0
# Pieces deja detaillees (formes rondes) ou plates par nature : intactes.
KEEP_MATERIALS = ("Pneu", "Jante", "Texte", "Plaque", "Vitre")
KEEP_NAMES = ("Texte", "Plaque", "Embleme", "Logo", "T_", "Joint_Porte", "Essuie_Glace", "Ecrou", "Moyeu",
              "Voile_Jante", "Pneu", "Jante", "Gen_Essieu_", "Socket_")
MAX_BEVEL_TRIS = 12000


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--only", default="", help="un seul modele (nom de fichier sans .glb)")
    return p.parse_args(argv)


# --- outils ----------------------------------------------------------------------

def wbox(obj):
    """Boite englobante monde (min, max) d'un objet mesh."""
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def find(prefix, root=None):
    """Objets mesh dont le nom commence par `prefix` (sous `root` si donne)."""
    out = []
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name.startswith(prefix):
            if root is None or is_under(o, root):
                out.append(o)
    return out


def find_base(base):
    """Objets mesh nommes exactement `base`, ou `base` suivi d'un suffixe
    Blender (.001...) : « Phare », « Phare.002 », pas « Phare_Rampe »."""
    return [o for o in bpy.data.objects
            if o.type == "MESH" and (o.name == base or o.name.startswith(base + "."))]


def is_under(obj, root):
    p = obj
    while p is not None:
        if p == root:
            return True
        p = p.parent
    return False


def material(prefix):
    """Premier materiau dont le nom commence par `prefix`."""
    for m in bpy.data.materials:
        if m.name.startswith(prefix):
            return m
    raise SystemExit(f"materiau introuvable : {prefix}")


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def add_box(name, size, loc, mat, parent, rot=(0.0, 0.0, 0.0)):
    """Boite chanfreinee de taille `size` (m, monde), centree en `loc` (monde)."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bevel_bm(bm, min(size))
    bm.to_mesh(mesh)
    bm.free()
    return _place(name, mesh, loc, mat, parent, rot)


def add_cylinder(name, radius, depth, loc, mat, parent, axis="Y", segments=20, cap=True):
    """Cylindre (m, monde) d'axe `axis`, centre en `loc`."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segments, radius1=radius, radius2=radius,
                          depth=depth)
    rot = {"X": Matrix.Rotation(math.pi / 2, 4, "Y"), "Y": Matrix.Rotation(math.pi / 2, 4, "X"),
           "Z": Matrix.Identity(4)}[axis]
    bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    if cap:
        bevel_bm(bm, radius)
    bm.to_mesh(mesh)
    bm.free()
    return _place(name, mesh, loc, mat, parent)


def _place(name, mesh, loc, mat, parent, rot=(0.0, 0.0, 0.0)):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.materials.append(mat)
    world = Matrix.Translation(loc) @ Matrix.Rotation(rot[0], 4, "X") @ Matrix.Rotation(rot[1], 4, "Y") \
        @ Matrix.Rotation(rot[2], 4, "Z")
    obj.parent = parent
    obj.matrix_world = world
    smooth(mesh)
    return obj


def bevel_bm(bm, min_dim, scale=1.0):
    """Chanfrein arrondi des aretes vives d'un bmesh (unites locales ; `scale` :
    metres par unite locale)."""
    width = max(BEVEL_MIN, min(BEVEL_MAX, min_dim * BEVEL_RATIO)) / max(scale, 1e-6)
    bm.edges.ensure_lookup_table()
    sharp = math.radians(SHARP_DEG)
    edges = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0.0) > sharp]
    if not edges:
        return 0
    bmesh.ops.bevel(bm, geom=edges, offset=width, offset_type="OFFSET", segments=BEVEL_SEGMENTS,
                    profile=0.5, affect="EDGES", clamp_overlap=True)
    return len(edges)


def smooth(mesh):
    """Faces lissees, aretes au-dela de SMOOTH_DEG gardees nettes."""
    mesh.shade_smooth()
    mesh.set_sharp_from_angle(angle=math.radians(SMOOTH_DEG))


def clear_custom_normals(obj):
    if obj.data.has_custom_normals:
        with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
            bpy.ops.mesh.customdata_custom_splitnormals_clear()


def soften(objects):
    """Chanfrein + lissage de toutes les pieces a aretes vives. Renvoie
    (pieces traitees, triangles avant, apres)."""
    done = 0
    before = after = 0
    for obj in objects:
        if obj.type != "MESH" or obj.name.startswith(DETAIL):
            continue
        if obj.name.startswith(KEEP_NAMES):
            continue
        mats = [s.material.name for s in obj.material_slots if s.material]
        if mats and all(m.startswith(KEEP_MATERIALS) for m in mats):
            continue
        tris = tri_count(obj)
        if tris > MAX_BEVEL_TRIS:
            continue
        scale = max(obj.matrix_world.to_scale())
        lo, hi = wbox(obj)
        dims = hi - lo
        min_dim = min(d for d in dims if d > 1e-4) if any(d > 1e-4 for d in dims) else 0.0
        if min_dim < 0.03:
            continue
        clear_custom_normals(obj)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        n = bevel_bm(bm, min_dim, scale)
        bm.to_mesh(obj.data)
        bm.free()
        smooth(obj.data)
        if n:
            done += 1
            before += tris
            after += tri_count(obj)
    return done, before, after


# Les details sont fusionnes par famille et par cote : une piece par phare,
# par antibrouillard, une calandre... (des dizaines de petits objets
# coutaient un appel de dessin chacun, par camion et par vue).
FAMILIES = [("Calandre", "Calandre_Grille", False), ("Phare", "Phare_Optique", True),
            ("Antibrouillard", "Antibrouillard", True), ("Poignee", "Poignee_Maintien", True),
            ("Pare_Chaleur", "Pare_Chaleur", True), ("Retro", "Retro_Angle_Mort", True),
            ("Pare_Soleil", "Pare_Soleil", False), ("Piece_Coin", "Pieces_Coin", False),
            ("Barre_Verrou", "Verrous", False), ("Poignee_Verrou", "Verrous", False)]


def merge_details(objects):
    """Fusionne les details par famille (FAMILIES) et par cote. Renvoie les
    objets fusionnes."""
    groups = {}
    for obj in objects:
        stem = obj.name[len(DETAIL):]
        family, by_side = next(((f, s) for p, f, s in FAMILIES if stem.startswith(p)), (stem.split(".")[0], False))
        side = ""
        if by_side:
            lo, hi = wbox(obj)
            side = "_G" if (lo.x + hi.x) < 0.0 else "_D"
        groups.setdefault(family + side, []).append(obj)
    merged = []
    for key, objs in sorted(groups.items()):
        first = objs[0]
        if len(objs) > 1:
            with bpy.context.temp_override(active_object=first, object=first, selected_objects=objs,
                                           selected_editable_objects=objs):
                bpy.ops.object.join()
        first.name = DETAIL + key
        first.data.name = first.name
        merged.append(first)
    return merged


# --- tracteur --------------------------------------------------------------------

def detail_tractor(root):
    """Details d'un tracteur de route. Repere : avant en -Y."""
    paint = find("Cabine")[0].material_slots[0].material
    black = material("Plastique_Noir")
    dark = material("Carbone")
    chrome = material("Chrome")
    lamp = material("Phare")
    alu = material("Aluminium")
    added = []

    # pare-soleil au-dessus du pare-brise, bord avant un peu plus bas
    glass = find("Pare_Brise")[0]
    lo, hi = wbox(glass)
    w = hi.x - lo.x + 0.12
    added.append(add_box(DETAIL + "Pare_Soleil", (w, 0.3, 0.035), Vector((0.0, lo.y - 0.08, hi.z + 0.05)),
                         paint, root, rot=(math.radians(8.0), 0.0, 0.0)))

    # calandre : barreaux verticaux derriere les lames chromees
    grille = find("Calandre")[0]
    lo, hi = wbox(grille)
    n = 18
    for k in range(n):
        x = lo.x + (hi.x - lo.x) * (k + 0.5) / n
        added.append(add_box(DETAIL + f"Calandre_Barreau_{k}", (0.022, 0.025, (hi.z - lo.z) * 0.92),
                             Vector((x, lo.y - 0.006, (lo.z + hi.z) / 2.0)), dark, root))

    # phares : entourage noir, deux optiques rondes
    for p in find_base("Phare"):
        lo, hi = wbox(p)
        c = (lo + hi) / 2.0
        w = hi.x - lo.x
        h = hi.z - lo.z
        t = 0.035
        for side in (-1, 1):
            added.append(add_box(DETAIL + "Phare_Cadre", (t, 0.06, h + 2 * t),
                                 Vector((c.x + side * (w / 2 + t / 2), lo.y - 0.01, c.z)), black, root))
            added.append(add_box(DETAIL + "Phare_Cadre", (w + 2 * t, 0.06, t),
                                 Vector((c.x, lo.y - 0.01, c.z + side * (h / 2 + t / 2))), black, root))
        r = min(w / 4.4, h / 2.4)
        for side in (-1, 1):
            added.append(add_cylinder(DETAIL + "Phare_Optique", r, 0.03,
                                      Vector((c.x + side * w / 4.2, lo.y - 0.012, c.z)), lamp, root))
            added.append(add_cylinder(DETAIL + "Phare_Bague", r * 1.18, 0.022,
                                      Vector((c.x + side * w / 4.2, lo.y - 0.004, c.z)), chrome, root))

    # antibrouillards dans le pare-chocs
    bumper = find("Pare_Choc")[0]
    lo, hi = wbox(bumper)
    for side in (-1, 1):
        x = side * ((hi.x - lo.x) / 2.0 - 0.38)
        z = (lo.z + hi.z) / 2.0
        added.append(add_cylinder(DETAIL + "Antibrouillard_Bague", 0.085, 0.03, Vector((x, lo.y - 0.008, z)),
                                  black, root))
        added.append(add_cylinder(DETAIL + "Antibrouillard", 0.065, 0.03, Vector((x, lo.y - 0.018, z)), lamp,
                                  root))

    # poignees de maintien chromees, derriere chaque porte
    seams = sorted(find("Joint_Porte"), key=lambda o: wbox(o)[1].z - wbox(o)[0].z, reverse=True)
    for seam in seams[:2]:
        lo, hi = wbox(seam)
        side = 1.0 if lo.x > 0 else -1.0
        x = (hi.x if side > 0 else lo.x) + side * 0.06
        y = (lo.y + hi.y) / 2.0 + 0.14
        z0 = lo.z + 0.15
        length = min(0.85, (hi.z - lo.z) * 0.45)
        added.append(add_cylinder(DETAIL + "Poignee_Maintien", 0.018, length,
                                  Vector((x, y, z0 + length / 2.0)), chrome, root, axis="Z", segments=12))
        for zz in (z0 + 0.04, z0 + length - 0.04):
            added.append(add_cylinder(DETAIL + "Poignee_Patte", 0.014, 0.07,
                                      Vector((x - side * 0.035, y, zz)), chrome, root, axis="X", segments=10))

    # pare-chaleur autour des cheminees : manchon d'alu brosse, colliers
    for pipe in find_base("Echappement"):
        lo, hi = wbox(pipe)
        c = (lo + hi) / 2.0
        r = (hi.x - lo.x) / 2.0
        z_mid = hi.z - 1.15
        added.append(add_cylinder(DETAIL + "Pare_Chaleur", r + 0.03, 0.9, Vector((c.x, c.y, z_mid)), alu,
                                  root, axis="Z", segments=24))
        for dz in (-0.42, 0.42):
            added.append(add_cylinder(DETAIL + "Pare_Chaleur_Collier", r + 0.042, 0.035,
                                      Vector((c.x, c.y, z_mid + dz)), dark, root, axis="Z", segments=24))

    # garde-boue arriere : plastique noir mat (comme sur un vrai tracteur), plus
    # couleur carrosserie
    for fender in find("Garde_Boue_AR"):
        for slot in fender.material_slots:
            if slot.material and slot.material.name.startswith("Peinture"):
                slot.material = black

    # retroviseurs : cornet d'angle mort sous le grand miroir
    for box in find("Retro_Boitier"):
        lo, hi = wbox(box)
        c = (lo + hi) / 2.0
        added.append(add_box(DETAIL + "Retro_Angle_Mort", (hi.x - lo.x, hi.y - lo.y, 0.2),
                             Vector((c.x, c.y, lo.z - 0.16)), black, root))
    return merge_details(added)


# --- remorques -------------------------------------------------------------------

def loose_parts(bm):
    """Ilots de faces connectees d'un bmesh (listes de faces)."""
    seen = set()
    parts = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        part = []
        while stack:
            cur = stack.pop()
            part.append(cur)
            for e in cur.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        parts.append(part)
    return parts


def add_arc_fender(name, center, radius, width, x, mat, parent, a0=15.0, a1=165.0, thick=0.025, seg=18):
    """Garde-boue cintre : arc de cercle (axe X, centre de la roue `center`)
    de a0 a a1 degres (0 : vers l'avant +Y, 90 : au-dessus), large de `width`."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for k in range(seg + 1):
        a = math.radians(a0 + (a1 - a0) * k / seg)
        ring = []
        for rr in (radius, radius + thick):
            for xx in (-width / 2.0, width / 2.0):
                ring.append(bm.verts.new((xx, math.cos(a) * rr, math.sin(a) * rr)))
        rings.append(ring)
    for k in range(seg):
        a, b = rings[k], rings[k + 1]
        # dessous, dessus, deux flancs
        bm.faces.new((a[0], a[1], b[1], b[0]))
        bm.faces.new((a[2], b[2], b[3], a[3]))
        bm.faces.new((a[0], b[0], b[2], a[2]))
        bm.faces.new((a[1], a[3], b[3], b[1]))
    for ring in (rings[0], rings[-1]):
        bm.faces.new((ring[0], ring[2], ring[3], ring[1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return _place(name, mesh, Vector((x, center.y, center.z)), mat, parent)


def replace_plank_fenders(trailer):
    """Les garde-boue plats (planches posees au-dessus des roues, fondues dans
    Gen_Remorque) deviennent des garde-boue cintres qui epousent la roue."""
    axles = []
    for a in trailer.children_recursive:
        if a.type == "MESH" and a.name.startswith("Gen_Essieu_"):
            lo, hi = wbox(a)
            axles.append(((lo + hi) / 2.0, (hi.z - lo.z) / 2.0))
    if not axles:
        return []
    added = []
    done = set()
    for obj in [o for o in trailer.children_recursive if o.type == "MESH" and o.name.startswith("Gen_Remorque")]:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.faces.ensure_lookup_table()
        mw = obj.matrix_world
        doomed = []
        found = []
        for part in loose_parts(bm):
            pts = [mw @ v.co for f in part for v in f.verts]
            lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
            hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
            d = hi - lo
            c = (lo + hi) / 2.0
            if not (d.z < 0.12 and 0.3 < d.x < 1.1 and 0.5 < d.y < 2.4 and abs(c.x) > 0.5):
                continue
            near = min(axles, key=lambda a: abs(a[0].y - c.y))
            ac, r = near
            if abs(ac.y - c.y) > 1.3 or not (ac.z + r - 0.05 < lo.z < ac.z + r + 0.6):
                continue
            doomed.extend(part)
            found.append((c.x, d.x, obj.data.materials[part[0].material_index]))
        if doomed:
            bmesh.ops.delete(bm, geom=list({f for f in doomed}), context="FACES")
            bm.to_mesh(obj.data)
        bm.free()
        # un garde-boue cintre par roue, du cote de chaque planche retiree
        for side_x, width, mat in found:
            for ac, r in axles:
                key = (round(side_x, 1), round(ac.y, 2))
                if key in done:
                    continue
                done.add(key)
                added.append(add_arc_fender(DETAIL + "Garde_Boue_Cintre", ac, r + 0.07, width, side_x, mat,
                                            trailer))
    return added


def detail_trailer(name, trailer):
    """Details d'une remorque. La caisse s'etend vers -Y depuis la sellette."""
    added = replace_plank_fenders(trailer)
    caisse = [o for o in trailer.children_recursive if o.type == "MESH" and o.name.startswith("Conteneur")
              and not o.name.startswith("Conteneur_Porte")]
    if caisse:
        steel = material("Chassis")
        lo, hi = wbox(caisse[0])
        # pieces de coin ISO aux huit angles de la caisse
        for x in (lo.x + 0.09, hi.x - 0.09):
            for y in (lo.y + 0.09, hi.y - 0.09):
                for z in (lo.z + 0.06, hi.z - 0.06):
                    added.append(add_box(DETAIL + "Piece_Coin", (0.2, 0.2, 0.13), Vector((x, y, z)), steel,
                                         trailer))
        # barres de verrouillage des portes (arriere : y minimum)
        chrome = material("Chrome")
        for door in [o for o in trailer.children_recursive if o.name.startswith("Conteneur_Porte")]:
            dlo, dhi = wbox(door)
            for f in (0.25, 0.75):
                x = dlo.x + (dhi.x - dlo.x) * f
                h = (dhi.z - dlo.z) * 0.96
                added.append(add_cylinder(DETAIL + "Barre_Verrou", 0.022, h,
                                          Vector((x, dlo.y - 0.03, (dlo.z + dhi.z) / 2.0)), chrome, trailer,
                                          axis="Z", segments=10))
                added.append(add_box(DETAIL + "Poignee_Verrou", (0.05, 0.05, 0.32),
                                     Vector((x + 0.07, dlo.y - 0.06, dlo.z + h * 0.45)), steel, trailer,
                                     rot=(0.0, math.radians(70.0), 0.0)))
    return merge_details(added)


# --- chaine ----------------------------------------------------------------------

def process(src, dst, kind):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(src))
    roots = [o for o in bpy.data.objects if o.parent is None]
    if kind == "tete":
        # la remorque d'origine du tracteur est cachee en jeu : intacte
        trailer = next((o for o in bpy.data.objects if o.name == "Remorque"), None)
        targets = [o for o in bpy.data.objects if trailer is None or not is_under(o, trailer)]
        done, before, after = soften(targets)
        root = roots[0]
        added = detail_tractor(root)
    else:
        trailer = next((o for o in bpy.data.objects if o.name == "Remorque"), None)
        if trailer is None:
            raise SystemExit(f"{src.name} : pas de noeud Remorque")
        done, before, after = soften([o for o in bpy.data.objects if is_under(o, trailer)])
        added = detail_trailer(src.stem, trailer)
    objs = list(bpy.data.objects)
    export.to_glb(dst, objs)
    total = sum(tri_count(o) for o in objs if o.type == "MESH")
    print(f"OK {dst} pieces chanfreinees={done} ({before} -> {after} tris) details={len(added)} tris={total}")


def main():
    args = parse_args()
    jobs = [(HEADS_DIR / f"{n}.glb", HEADS_DIR / OUT_DIR / f"{n}.glb", "tete") for n in HEADS]
    jobs += [(TRAILERS_DIR / f"{n}.glb", TRAILERS_DIR / OUT_DIR / f"{n}.glb", "remorque") for n in TRAILERS]
    if args.only:
        jobs = [j for j in jobs if j[0].stem == args.only]
        if not jobs:
            raise SystemExit(f"modele inconnu : {args.only}")
    for src, dst, kind in jobs:
        if not src.exists():
            raise SystemExit(f"introuvable : {src}")
        process(src, dst, kind)


main()
