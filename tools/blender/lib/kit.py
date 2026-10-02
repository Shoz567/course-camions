"""Kit de modelisation par script : materiaux, primitives, pieces.

Tout le style visuel partage des vehicules et des objets d'arme vit ici, pour
que les modeles generes ressemblent aux camions de l'equipe
(Assets_Visuels/Camion/Camions_Course_Export/*.glb) :
  - formes franches a aretes arrondies (biseau a 1-2 segments) ;
  - peinture metallisee brillante, chromes, plastiques noirs ;
  - feux emissifs (phares, clignotants, feux arriere, flammes) ;
  - noms de materiaux REPRIS des modeles de l'equipe (Peinture_Cabine_*,
    Chrome, Jante, Pneu...) : la livree de TruckVisual (par prefixe de nom de
    materiau) s'applique telle quelle.

Repere Blender : X a droite, Y vers l'AVANT, Z en haut. A l'export glTF
(export_yup), +Y Blender devient -Z Godot : l'avant est donc en -Z dans Godot,
conformement a docs/VEHICLE_SPEC.md §1.

Une `Part` accumule de la geometrie (plusieurs primitives, plusieurs
materiaux) dans un seul maillage, puis devient UN objet Blender dont l'origine
(le pivot) est choisie : moyeu pour une roue, charniere pour une porte...
"""

import math

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

# ---------------------------------------------------------------------------
# Materiaux
# ---------------------------------------------------------------------------

# nom -> (couleur lineaire, metallic, roughness, emission (couleur, force), alpha)
_BASE = {
    # Repris des modeles de l'equipe (valeurs mesurees sur Camion_Bleu.glb).
    "Acier_Sellette": ((0.12, 0.12, 0.13), 0.9, 0.40, None, 1.0),
    "Aluminium": ((0.70, 0.70, 0.72), 1.0, 0.30, None, 1.0),
    "Carbone": ((0.02, 0.02, 0.02), 0.0, 0.35, None, 1.0),
    "Chassis": ((0.05, 0.05, 0.05), 0.3, 0.60, None, 1.0),
    "Chrome": ((0.90, 0.90, 0.90), 1.0, 0.08, None, 1.0),
    "Clignotant": ((1.00, 0.45, 0.00), 0.0, 0.10, ((1.0, 0.40, 0.0), 1.5), 1.0),
    "Feu_Arriere": ((0.60, 0.00, 0.00), 0.0, 0.10, ((1.0, 0.0, 0.0), 2.0), 1.0),
    "Flamme": ((1.00, 0.25, 0.00), 0.0, 0.50, ((1.0, 0.22, 0.0), 3.0), 1.0),
    "Jante": ((0.60, 0.60, 0.62), 1.0, 0.25, None, 1.0),
    "Joint_Porte": ((0.01, 0.01, 0.01), 0.0, 0.70, None, 1.0),
    "Phare": ((0.90, 0.90, 0.85), 0.0, 0.05, ((1.0, 0.97, 0.90), 3.0), 1.0),
    "Plaque_Fond": ((0.85, 0.85, 0.83), 0.0, 0.35, None, 1.0),
    "Plastique_Interieur": ((0.05, 0.05, 0.05), 0.0, 0.60, None, 1.0),
    "Plastique_Noir": ((0.02, 0.02, 0.02), 0.0, 0.55, None, 1.0),
    "Pneu": ((0.01, 0.01, 0.01), 0.0, 0.85, None, 1.0),
    "Texte_Blanc": ((0.90, 0.90, 0.90), 0.0, 0.40, None, 1.0),
    "Texte_Noir": ((0.01, 0.01, 0.01), 0.0, 0.50, None, 1.0),
    "Vitre": ((0.04, 0.06, 0.07), 0.0, 0.02, None, 0.28),
    # Nouveaux, dans la meme gamme.
    "Citerne_Inox": ((0.80, 0.81, 0.83), 1.0, 0.15, None, 1.0),
    "Danger_Jaune": ((1.00, 0.62, 0.00), 0.0, 0.35, None, 1.0),
    "Danger_Noir": ((0.02, 0.02, 0.02), 0.0, 0.40, None, 1.0),
    "Plaque_Danger": ((1.00, 0.30, 0.00), 0.0, 0.40, None, 1.0),
    "Gyrophare_Bleu": ((0.05, 0.20, 1.00), 0.0, 0.10, ((0.1, 0.3, 1.0), 4.0), 1.0),
    "Gyrophare_Orange": ((1.00, 0.40, 0.00), 0.0, 0.10, ((1.0, 0.45, 0.0), 4.0), 1.0),
    "Caoutchouc": ((0.03, 0.03, 0.03), 0.0, 0.90, None, 1.0),
    "Bois": ((0.30, 0.15, 0.05), 0.0, 0.70, None, 1.0),
    "Lame_Acier": ((0.75, 0.76, 0.78), 1.0, 0.22, None, 1.0),
    "Blindage": ((0.18, 0.19, 0.20), 0.8, 0.45, None, 1.0),
    "Laiton": ((0.80, 0.55, 0.15), 1.0, 0.25, None, 1.0),
    "Grenade_Kaki": ((0.10, 0.14, 0.04), 0.2, 0.55, None, 1.0),
    "Aimant_Rouge": ((0.70, 0.02, 0.02), 0.3, 0.30, None, 1.0),
    "Peluche_Marron": ((0.30, 0.13, 0.04), 0.0, 1.00, None, 1.0),
    "Peluche_Beige": ((0.75, 0.52, 0.30), 0.0, 1.00, None, 1.0),
    "Peluche_Rose": ((0.90, 0.35, 0.45), 0.0, 1.00, None, 1.0),
    "Oeil": ((0.01, 0.01, 0.01), 0.0, 0.05, None, 1.0),
    "Ruban_Rouge": ((0.70, 0.02, 0.05), 0.0, 0.50, None, 1.0),
    "Couture": ((0.12, 0.05, 0.02), 0.0, 1.00, None, 1.0),
    "Creme_Tuyau": ((0.85, 0.80, 0.65), 0.0, 0.70, None, 1.0),
    "Neon_Cyan": ((0.00, 0.80, 1.00), 0.0, 0.10, ((0.0, 0.85, 1.0), 5.0), 1.0),
    "Neon_Rouge": ((1.00, 0.02, 0.02), 0.0, 0.10, ((1.0, 0.05, 0.02), 5.0), 1.0),
    "Neon_Violet": ((0.60, 0.05, 1.00), 0.0, 0.10, ((0.6, 0.1, 1.0), 5.0), 1.0),
    "Bouclier_Coque": ((0.00, 0.55, 0.90), 0.0, 0.05, ((0.0, 0.6, 1.0), 1.5), 0.22),
    "Bouclier_Trame": ((0.00, 0.85, 1.00), 0.0, 0.10, ((0.0, 0.9, 1.0), 6.0), 1.0),
    "Laser_Coeur": ((1.00, 0.85, 0.85), 0.0, 0.10, ((1.0, 0.6, 0.6), 12.0), 1.0),
    "Laser_Halo": ((1.00, 0.02, 0.02), 0.0, 0.10, ((1.0, 0.0, 0.0), 6.0), 0.35),
}

# Couleurs de livree (lineaires). Une livree donne trois materiaux :
# Peinture_Cabine_<Nom> (metallisee), Peinture_Caisse_<Nom> (mate),
# Bande_Deco_<Nom> (bande decorative).
COULEURS = {
    "Bleu": (0.02, 0.10, 0.42),
    "Rouge": (0.60, 0.01, 0.01),
    "Jaune": (1.00, 0.55, 0.00),
    "Vert": (0.02, 0.35, 0.06),
    "Orange": (1.00, 0.28, 0.01),
    "Violet": (0.22, 0.03, 0.45),
    "Pompier": (0.80, 0.00, 0.00),
    "Blanc": (0.88, 0.89, 0.90),
    "Noir": (0.02, 0.02, 0.02),
    "Gris": (0.22, 0.23, 0.25),
    "Turquoise": (0.00, 0.40, 0.45),
    "Rose": (0.90, 0.20, 0.40),
    "Creme": (0.85, 0.80, 0.65),
    "Bordeaux": (0.25, 0.01, 0.03),
}

_PAINT_KINDS = {
    "Peinture_Cabine_": (0.35, 0.25),
    "Peinture_Caisse_": (0.00, 0.35),
    "Bande_Deco_": (0.30, 0.30),
    "Conteneur_": (0.20, 0.45),
}


def _spec(name):
    if name in _BASE:
        return _BASE[name]
    for prefix, (met, rough) in _PAINT_KINDS.items():
        if name.startswith(prefix):
            color = name[len(prefix):]
            if color not in COULEURS:
                raise SystemExit("couleur inconnue : %s" % name)
            return (COULEURS[color], met, rough, None, 1.0)
    raise SystemExit("materiau inconnu : %s" % name)


def mat(name):
    """Materiau Principled nomme `name`, cree a la demande."""
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    color, metallic, rough, emission, alpha = _spec(name)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission[0], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission[1]
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = "BLENDED"
        else:
            m.blend_method = "BLEND"
    m.diffuse_color = (*color, alpha)
    return m


def livery(color):
    """Noms des materiaux de livree pour une couleur de COULEURS."""
    return {
        "cab": "Peinture_Cabine_" + color,
        "box": "Peinture_Caisse_" + color,
        "stripe": "Bande_Deco_" + color,
    }


# ---------------------------------------------------------------------------
# Qualite
# ---------------------------------------------------------------------------

# Niveau de detail global (demande du 2026-10-02 : meme densite que les
# modeles de l'equipe, ~64 000 triangles par camion). Les segments donnes
# dans le code sont des valeurs de base, multipliees ici.
SEG_MULT = 3.0        # cylindres, revolutions, arcs
SPHERE_MULT = 2.0     # spheres (segments et anneaux)
BEVEL_SEG = 4         # segments minimaux d'un biseau
SEG_MAX = 72


def _seg(n, mult=None):
    return max(3, min(SEG_MAX, int(round(n * (SEG_MULT if mult is None else mult)))))


# ---------------------------------------------------------------------------
# Transformations
# ---------------------------------------------------------------------------

_AXIS_ROT = {
    "Z": Matrix.Identity(4),
    "X": Matrix.Rotation(math.radians(90), 4, "Y"),   # +Z local -> +X
    "Y": Matrix.Rotation(math.radians(-90), 4, "X"),  # +Z local -> +Y
}


def _place(c, rot=None, axis="Z"):
    """Matrice : primitive construite a l'origine selon Z -> monde."""
    m = _AXIS_ROT[axis]
    if rot is not None:
        m = Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4() @ m
    return Matrix.Translation(Vector(c)) @ m


# ---------------------------------------------------------------------------
# Piece : un maillage, plusieurs materiaux, un pivot
# ---------------------------------------------------------------------------

class Part:
    """Accumule des primitives dans un maillage. `origin` = pivot de l'objet.

    Toutes les coordonnees passees aux methodes sont en repere MONDE (celui du
    vehicule) ; elles sont ramenees au pivot a l'ajout.
    """

    def __init__(self, name, origin=(0.0, 0.0, 0.0)):
        self.name = name
        self.origin = Vector(origin)
        self.bm = bmesh.new()
        self.mats = []

    # -- interne ------------------------------------------------------------

    def _mi(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def _merge(self, t, mat_name, matrix, smooth):
        """`smooth` : False, True, 'sides' (faces non alignees sur Z local)
        ou 'bevel' (faces non alignees sur un axe local)."""
        flags = {}
        for f in t.faces:
            n = f.normal
            if smooth == "sides":
                flags[f] = abs(n.z) < 0.7
            elif smooth == "bevel":
                flags[f] = max(abs(n.x), abs(n.y), abs(n.z)) < 0.985
            else:
                flags[f] = bool(smooth)
        full = Matrix.Translation(-self.origin) @ matrix
        bmesh.ops.transform(t, matrix=full, verts=t.verts)
        mi = self._mi(mat_name)
        vmap = {v: self.bm.verts.new(v.co) for v in t.verts}
        for f in t.faces:
            nf = self.bm.faces.new([vmap[v] for v in f.verts])
            nf.material_index = mi
            nf.smooth = flags[f]
        t.free()
        return self

    # -- primitives ---------------------------------------------------------

    def box(self, c, s, m, bevel=0.0, seg=1, rot=None):
        """Boite centree en `c`, de taille `s`, aretes biseautees de `bevel`."""
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        bmesh.ops.scale(t, vec=Vector(s), verts=t.verts)
        if bevel > 0.0:
            b = min(bevel, min(s) * 0.45)
            bmesh.ops.bevel(t, geom=list(t.edges), offset=b, segments=max(seg, BEVEL_SEG),
                            profile=0.5, affect="EDGES", clamp_overlap=True)
            bmesh.ops.recalc_face_normals(t, faces=t.faces)
        t.normal_update()
        return self._merge(t, m, _place(c, rot), "bevel" if bevel > 0 else False)

    def cyl(self, c, r, depth, m, axis="Z", seg=16, r2=None, rot=None, smooth=True):
        """Cylindre (ou tronc de cone si `r2`) d'axe `axis`. `r2` = rayon cote +axe."""
        t = bmesh.new()
        bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=_seg(seg),
                              radius1=r, radius2=r if r2 is None else r2,
                              depth=depth)
        t.normal_update()
        return self._merge(t, m, _place(c, rot, axis), "sides" if smooth else False)

    def sphere(self, c, r, m, seg=12, rings=8, scale=(1, 1, 1), rot=None):
        t = bmesh.new()
        bmesh.ops.create_uvsphere(t, u_segments=_seg(seg, SPHERE_MULT),
                                  v_segments=_seg(rings, SPHERE_MULT), radius=r)
        bmesh.ops.scale(t, vec=Vector(scale), verts=t.verts)
        t.normal_update()
        return self._merge(t, m, _place(c, rot), True)

    def lathe(self, c, prof, m, axis="Z", seg=16, closed=False, rot=None, smooth="sides"):
        """Revolution du profil [(rayon, hauteur)] autour de l'axe local Z.

        Un point de rayon nul ferme en pointe. `closed` relie le dernier point
        au premier (tore, pneu).
        """
        seg = _seg(seg)
        t = bmesh.new()
        rings = []
        for r, h in prof:
            if r < 1e-6:
                v = t.verts.new((0.0, 0.0, h))
                rings.append([v] * seg)
            else:
                rings.append([t.verts.new((r * math.cos(2 * math.pi * i / seg),
                                           r * math.sin(2 * math.pi * i / seg), h))
                              for i in range(seg)])
        n = len(rings)
        for k in range(n if closed else n - 1):
            a, b = rings[k], rings[(k + 1) % n]
            for i in range(seg):
                j = (i + 1) % seg
                quad = []
                for v in (a[i], a[j], b[j], b[i]):
                    if v not in quad:
                        quad.append(v)
                if len(quad) >= 3:
                    t.faces.new(quad)
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        t.normal_update()
        return self._merge(t, m, _place(c, rot, axis), smooth)

    def prism(self, c, pts, thick, m, axis="X", rot=None, smooth=False):
        """Polygone 2D `pts` (dans le plan local XY) extrude de `thick`
        selon l'axe `axis` (centre sur `c`)."""
        t = bmesh.new()
        lo = [t.verts.new((u, v, -thick / 2)) for u, v in pts]
        hi = [t.verts.new((u, v, thick / 2)) for u, v in pts]
        t.faces.new(lo)
        t.faces.new(hi)
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            t.faces.new([lo[i], lo[j], hi[j], hi[i]])
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        t.normal_update()
        # Plan local XY -> plan perpendiculaire a `axis`, en gardant un
        # sens lisible : pour axis X, (u, v) -> (y, z) ; pour Y, (u, v) -> (x, z).
        if axis == "X":
            base = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        elif axis == "Y":
            base = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        else:
            base = Matrix.Identity(4)
        mtx = Matrix.Translation(Vector(c))
        if rot is not None:
            mtx = mtx @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
        r = self._merge(t, m, mtx @ base, smooth)
        return r

    def arc(self, c, r_in, r_out, width, a0, a1, m, axis="X", seg=10, rot=None):
        """Secteur d'anneau (garde-boue) : angles en degres dans le plan
        perpendiculaire a `axis`, 0 = vers l'avant (+Y) pour axis X."""
        seg = _seg(seg)
        pts = []
        for i in range(seg + 1):
            a = math.radians(a0 + (a1 - a0) * i / seg)
            pts.append((r_out * math.cos(a), r_out * math.sin(a)))
        for i in range(seg, -1, -1):
            a = math.radians(a0 + (a1 - a0) * i / seg)
            pts.append((r_in * math.cos(a), r_in * math.sin(a)))
        t = bmesh.new()
        lo = [t.verts.new((u, v, -width / 2)) for u, v in pts]
        hi = [t.verts.new((u, v, width / 2)) for u, v in pts]
        n = len(pts)
        # Faces laterales en quads (pas de n-gone concave).
        for i in range(seg):
            o0, o1 = i, i + 1
            i1, i0 = n - 1 - (i + 1), n - 1 - i
            t.faces.new([lo[o0], lo[o1], lo[i1], lo[i0]])
            t.faces.new([hi[o0], hi[o1], hi[i1], hi[i0]])
        for i in range(n):
            j = (i + 1) % n
            t.faces.new([lo[i], lo[j], hi[j], hi[i]])
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        t.normal_update()
        if axis == "X":
            base = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        else:
            base = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        mtx = Matrix.Translation(Vector(c))
        if rot is not None:
            mtx = mtx @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
        return self._merge(t, m, mtx @ base, "bevel")

    def hull(self, pts, m, smooth=False):
        """Enveloppe convexe d'un nuage de points (monde)."""
        t = bmesh.new()
        vs = [t.verts.new(p) for p in pts]
        res = bmesh.ops.convex_hull(t, input=vs)
        junk = [g for g in res["geom_interior"] + res["geom_unused"]
                if isinstance(g, bmesh.types.BMVert)]
        if junk:
            bmesh.ops.delete(t, geom=junk, context="VERTS")
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        t.normal_update()
        return self._merge(t, m, Matrix.Identity(4), "bevel" if smooth else False)

    def text(self, c, body, size, m, rot=(90, 0, 90), depth=0.01):
        """Texte en relief (numero de course). Par defaut, lisible depuis +X."""
        cu = bpy.data.curves.new("txt_" + body, "FONT")
        cu.body = body
        cu.size = size
        cu.extrude = depth
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.resolution_u = 6
        ob = bpy.data.objects.new("txt_" + body, cu)
        bpy.context.scene.collection.objects.link(ob)
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        t = bmesh.new()
        t.from_mesh(me)
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)
        bpy.data.meshes.remove(me)
        bmesh.ops.triangulate(t, faces=t.faces)
        t.normal_update()
        return self._merge(t, m, _place(c, rot), False)

    def merge_part(self, other):
        """Absorbe une autre piece (ses coordonnees sont celles de SON pivot)."""
        t = other.bm
        for mname in other.mats:
            self._mi(mname)
        off = other.origin - self.origin
        vmap = {v: self.bm.verts.new(v.co + off) for v in t.verts}
        for f in t.faces:
            nf = self.bm.faces.new([vmap[v] for v in f.verts])
            nf.material_index = self._mi(other.mats[f.material_index])
            nf.smooth = f.smooth
        t.free()
        other.bm = bmesh.new()
        return self

    # -- sortie -------------------------------------------------------------

    def tri_count(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)

    def finish(self, parent=None):
        """Cree l'objet Blender. Son origine est `origin` (en monde)."""
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for mname in self.mats:
            me.materials.append(mat(mname))
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        attach(ob, self.origin, parent)
        return ob


def attach(ob, world_pos, parent=None):
    """Place `ob` a `world_pos` (monde), sous `parent` si donne."""
    if parent is not None:
        ob.parent = parent
        ob.location = Vector(world_pos) - parent.matrix_world.translation
    else:
        ob.location = Vector(world_pos)
    bpy.context.view_layer.update()
    return ob


def empty(name, world_pos, parent=None, size=0.3):
    """Point d'accroche (Node3D dans Godot). Aucune geometrie."""
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_type = "PLAIN_AXES"
    ob.empty_display_size = size
    bpy.context.scene.collection.objects.link(ob)
    return attach(ob, world_pos, parent)


def hierarchy(root):
    """`root` et tous ses descendants."""
    out = [root]
    for ch in root.children:
        out += hierarchy(ch)
    return out


def tris(objects):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons)
               for o in objects if o.type == "MESH")


# ---------------------------------------------------------------------------
# Elements recurrents
# ---------------------------------------------------------------------------

def wheel(p, hub, side, r=0.66, w=0.48, seg=16):
    """Roue complete ajoutee a la piece `p` : pneu a epaulements arrondis et
    sculptures, jante a voile ajoure, tambour, moyeu bombe, 10 ecrous, valve.

    `hub` = centre du moyeu (monde), `side` = +1 si le flanc exterieur est en
    +X (roue droite), -1 sinon.
    """
    rim = r * 0.60
    s = side
    hx, hy, hz = hub
    h = w / 2
    # Pneu : profil arrondi (epaulements), ferme sur le talon.
    # Carcasse un peu sous le rayon : les sculptures affleurent exactement a
    # `r` (le bas du pneu reste au sol, moyeu a la cote de la spec).
    rc = r - 0.03
    prof = [(rim, -h + 0.02)]
    for k in range(7):
        a = math.radians(90 * k / 6)
        prof.append((rc - 0.09 + 0.09 * math.sin(a), -h + 0.09 - 0.09 * math.cos(a)))
    for k in range(7):
        a = math.radians(90 * k / 6)
        prof.append((rc - 0.09 * (1 - math.cos(a)), h - 0.09 + 0.09 * math.sin(a)))
    prof.append((rim, h - 0.02))
    p.lathe(hub, prof, "Pneu", axis="X", seg=seg, closed=True)
    # Sculptures : deux rangees de pavés decales.
    n = int(_seg(seg) * 0.85)
    for k in range(n):
        for row, xo in enumerate((-w * 0.22, w * 0.22)):
            a = 360.0 * (k + 0.5 * row) / n
            ar = math.radians(a)
            p.box((hx + xo, hy + math.cos(ar) * (r - 0.0175), hz + math.sin(ar) * (r - 0.0175)),
                  (w * 0.36, 2 * math.pi * r / n * 0.55, 0.035), "Pneu", rot=(a - 90, 0, 0))
    # Flanc : anneau en relief.
    o = s * (h - 0.01)
    p.lathe((hx + o, hy, hz), [(r * 0.83, 0.012 * s), (r * 0.83, -0.012 * s), (r * 0.79, -0.012 * s),
                               (r * 0.79, 0.012 * s)], "Caoutchouc", axis="X", seg=seg, closed=True)
    # Jante : voile en cuvette cote exterieur.
    i = -s * (h - 0.06)
    o = s * (h - 0.04)
    p.lathe(hub, [(0.0, i), (rim + 0.01, i), (rim + 0.01, o), (rim * 0.92, o + s * 0.015),
                  (rim * 0.86, o - s * 0.03), (rim * 0.55, o - s * 0.05), (rim * 0.40, o - s * 0.02),
                  (0.0, o - s * 0.02)], "Jante", axis="X", seg=seg, smooth=True)
    # Ajours du voile (6 lumieres sombres).
    for k in range(6):
        a = 2 * math.pi * (k + 0.5) / 6
        p.cyl((hx + o - s * 0.045, hy + math.cos(a) * rim * 0.70, hz + math.sin(a) * rim * 0.70),
              rim * 0.13, 0.012, "Chassis", axis="X", seg=6)
    # Tambour de frein (visible cote interieur) et moyeu bombe.
    p.cyl((hx - s * (h - 0.02), hy, hz), rim * 0.85, 0.06, "Acier_Sellette", axis="X", seg=seg)
    p.lathe((hx + o - s * 0.02, hy, hz), [(0.0, s * 0.10), (r * 0.10, s * 0.08), (r * 0.17, s * 0.03),
                                          (r * 0.19, 0.0), (0.0, 0.0)], "Chrome", axis="X", seg=8)
    for k in range(10):
        a = 2 * math.pi * k / 10
        p.cyl((hx + o - s * 0.0, hy + math.cos(a) * r * 0.27, hz + math.sin(a) * r * 0.27),
              0.026, 0.05, "Chrome", axis="X", seg=2)
    p.cyl((hx + o - s * 0.02, hy + rim * 0.80, hz), 0.012, 0.06, "Chrome", axis="X", seg=2)
    return p


def hazard_stripes(p, c, size, n, axis="Y"):
    """Bande de chevrons jaune / noir (bord de lame, stabilisateur, bras)."""
    cx, cy, cz = c
    sx, sy, sz = size
    for k in range(n):
        m = "Danger_Jaune" if k % 2 == 0 else "Danger_Noir"
        if axis == "Y":
            step = sy / n
            p.box((cx, cy - sy / 2 + step * (k + 0.5), cz), (sx, step, sz), m)
        elif axis == "X":
            step = sx / n
            p.box((cx - sx / 2 + step * (k + 0.5), cy, cz), (step, sy, sz), m)
        else:
            step = sz / n
            p.box((cx, cy, cz - sz / 2 + step * (k + 0.5)), (sx, sy, step), m)
    return p
