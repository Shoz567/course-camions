"""Objets d'arme : accessoires qui se branchent (ou non) sur un camion.

VISUELS SEULEMENT : aucun comportement ici, le gameplay viendra cote Godot.

Convention commune (docs/ART_PIPELINE.md §4 ter) :
  - l'ORIGINE de l'objet racine est son point d'accroche : on le pose tel quel
    sur un vide `Socket_*` du camion (Socket_Toit, Socket_Lateral_G...) ;
  - l'avant de l'arme est en +Y Blender (-Z Godot), comme le camion ;
  - les pieces mobiles sont des objets separes, pivot a leur axe de rotation
    (tourelle, canon, barillet, lame de scie, portes...) ;
  - les projectiles ont leur origine en leur centre (rotation libre en vol).
"""

import math

from lib import kit
from lib.kit import Part, empty


# ---------------------------------------------------------------------------
# Voiture (largable depuis le conteneur, chargee sur le porte-voitures)
# ---------------------------------------------------------------------------

def _car_profile():
    """Profil lateral (y, z) de la caisse : capot, coffre, passages de roue."""
    def arch(cy, a0, a1, n=12, r=0.43):
        return [(cy + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)),
                 0.34 + r * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]
    pts = [(2.18, 0.30), (2.24, 0.45), (2.24, 0.62), (2.17, 0.80), (2.02, 0.89),
           (1.40, 0.94), (0.95, 0.97), (-1.70, 0.98), (-2.02, 0.94), (-2.18, 0.84),
           (-2.24, 0.66), (-2.24, 0.42), (-2.16, 0.30), (-1.80, 0.30)]
    pts += arch(-1.35, 180, 0)[1:-1]
    pts += [(-0.90, 0.30), (0.90, 0.30)]
    pts += arch(1.35, 180, 0)[1:-1]
    pts += [(1.80, 0.30)]
    return pts


def car(name, color, at=(0.0, 0.0, 0.0), lod=False):
    """Citadine arcade (4,5 m), origine au sol au centre, avant en +Y.

    Caisse profilee a passages de roue, habitacle vitre sombre avec montants
    peints, portes, poignees, retroviseurs, calandre, optiques a lentilles,
    feux, plaques, echappement, roues completes (pneu sculpte, jante).
    `lod` ne garde que des roues un peu plus simples (porte-voitures)."""
    x0, y0, z0 = at
    paint = "Peinture_Cabine_" + color
    p = Part(name, at)

    def P(x, y, z):
        return (x0 + x, y0 + y, z0 + z)

    # Caisse : profil extrude, puis flancs legerement bombes (deux passes).
    prof = _car_profile()
    p.prism(P(0, 0, 0), prof, 1.80, paint, axis="X")
    p.prism(P(0, 0, 0), [(y * 0.985, 0.30 + (z - 0.30) * 0.92) for y, z in prof], 1.86,
            paint, axis="X")
    # Habillage interieur des passages de roue.
    for y in (1.35, -1.35):
        p.arc(P(0, y, 0.34), 0.40, 0.44, 1.70, 0, 180, "Plastique_Noir", axis="X", seg=10)
    # Bas de caisse et baguettes.
    for sx in (-1, 1):
        p.box(P(sx * 0.92, 0, 0.36), (0.05, 1.70, 0.12), "Plastique_Noir", bevel=0.02)
        p.box(P(sx * 0.935, 0.0, 0.70), (0.02, 3.50, 0.035), "Chrome")
    # Habitacle : fond sombre + vitrage brillant, toit et montants peints.
    green = ((0.86, 0.95, 0.96), (0.72, 0.33, 1.47), (0.72, -1.08, 1.47), (0.86, -1.72, 0.97))
    p.hull([P(sx * w, y, z) for sx in (-1, 1) for (w, y, z) in green], "Plastique_Interieur", smooth=True)
    p.hull([P(sx * (w + 0.008), y + (0.008 if y > 0 else -0.008), z + 0.006)
            for sx in (-1, 1) for (w, y, z) in green], "Vitre", smooth=True)
    p.hull([P(sx * w, y, z) for sx in (-1, 1)
            for (w, y, z) in ((0.70, 0.28, 1.46), (0.70, -1.02, 1.46), (0.68, 0.24, 1.50),
                              (0.68, -0.98, 1.50))], paint, smooth=True)
    for sx in (-1, 1):
        # Montants A, B, C.
        for (y_lo, z_lo, y_hi, z_hi) in ((0.95, 0.97, 0.33, 1.47), (-1.72, 0.97, -1.08, 1.47)):
            p.hull([P(sx * (w + dx), y + dy, z) for (w, y, z) in
                    ((0.87, y_lo, z_lo), (0.73, y_hi, z_hi)) for dx in (0.0, 0.02)
                    for dy in (-0.05, 0.05)], paint)
        p.hull([P(sx * (w + dx), y + dy, z) for (w, y, z) in
                ((0.875, -0.40, 0.97), (0.735, -0.36, 1.47)) for dx in (0.0, 0.02)
                for dy in (-0.06, 0.06)], paint)
        # Portes : joints, poignees, retroviseurs.
        for y in (0.95, -0.40, -1.62):
            p.box(P(sx * 0.932, y, 0.66), (0.012, 0.015, 0.58), "Joint_Porte")
        p.box(P(sx * 0.932, (0.95 - 1.62) / 2, 0.37), (0.012, 2.57, 0.012), "Joint_Porte")
        for y in (0.15, -1.15):
            p.box(P(sx * 0.94, y, 0.86), (0.025, 0.18, 0.035), "Chrome", bevel=0.01)
        p.box(P(sx * 0.98, 0.82, 1.03), (0.12, 0.05, 0.05), "Plastique_Noir")
        p.box(P(sx * 1.05, 0.80, 1.06), (0.08, 0.16, 0.12), paint, bevel=0.03)
        p.box(P(sx * 1.05, 0.715, 1.06), (0.06, 0.01, 0.09), "Chrome")
        # Optiques avant : boitier noir, deux lentilles, clignotant.
        p.box(P(sx * 0.62, 2.215, 0.70), (0.42, 0.04, 0.17), "Plastique_Noir", bevel=0.03)
        for k in (-1, 1):
            p.cyl(P(sx * 0.62 + k * 0.10, 2.24, 0.70), 0.055, 0.02, "Phare", axis="Y", seg=12)
        p.box(P(sx * 0.80, 2.23, 0.70), (0.06, 0.03, 0.10), "Clignotant")
        p.cyl(P(sx * 0.68, 2.25, 0.40), 0.05, 0.02, "Phare", axis="Y", seg=10)   # antibrouillard
        # Feux arriere : rouge + recul blanc.
        p.box(P(sx * 0.66, -2.235, 0.74), (0.38, 0.04, 0.15), "Feu_Arriere", bevel=0.03)
        p.box(P(sx * 0.44, -2.24, 0.74), (0.08, 0.035, 0.12), "Phare")
        # Essuie-glaces.
        p.box(P(sx * 0.32, 0.96, 0.995), (0.55, 0.02, 0.015), "Plastique_Noir", rot=(0, 0, sx * 6))
    # Calandre, pare-chocs, plaques, echappement, antenne.
    p.box(P(0, 2.23, 0.62), (0.70, 0.04, 0.16), "Plastique_Noir", bevel=0.02)
    for z in (0.58, 0.62, 0.66):
        p.box(P(0, 2.25, z), (0.62, 0.02, 0.015), "Chrome")
    p.box(P(0, 2.22, 0.40), (1.20, 0.06, 0.10), "Plastique_Noir", bevel=0.02)
    p.box(P(0, 2.255, 0.50), (0.48, 0.015, 0.10), "Plaque_Fond")
    p.box(P(0, -2.255, 0.55), (0.48, 0.015, 0.10), "Plaque_Fond")
    p.box(P(0, -2.22, 0.38), (1.50, 0.06, 0.12), "Plastique_Noir", bevel=0.02)
    p.box(P(0, -2.225, 0.86), (1.40, 0.01, 0.012), "Joint_Porte")            # coffre
    p.cyl(P(0.55, -2.22, 0.32), 0.04, 0.12, "Chrome", axis="Y", seg=10)
    p.cyl(P(-0.45, -0.95, 1.62), 0.008, 0.28, "Plastique_Noir", seg=4, rot=(-25, 0, 0))
    # Roues completes.
    for sx in (-1, 1):
        for y in (1.35, -1.35):
            kit.wheel(p, P(sx * 0.78, y, 0.34), sx, r=0.34, w=0.24, seg=10 if lod else 12)
    return p.finish()


# ---------------------------------------------------------------------------
# Missiles (tires depuis l'arriere de la remorque)
# ---------------------------------------------------------------------------

def _missile(p, c, length=1.7, r=0.14, body="Texte_Blanc", accent="Aimant_Rouge", seg=12):
    """Missile d'axe +Y centre en `c` (nez vers +Y)."""
    x, y, z = c
    tail = y - length / 2
    p.lathe((x, 0, z), [(0.0, tail + length), (r * 0.55, tail + length - 0.18),
                        (r, tail + length - 0.42), (r, tail + 0.18), (r * 0.8, tail),
                        (0.0, tail)], body, axis="Y", seg=seg)
    p.lathe((x, 0, z), [(r * 1.02, tail + length - 0.42), (r * 1.02, tail + length - 0.56),
                        (r * 0.98, tail + length - 0.56), (r * 0.98, tail + length - 0.42)],
            accent, axis="Y", seg=seg, closed=True)
    p.cyl((x, tail - 0.04, z), r * 0.62, 0.10, "Chassis", axis="Y", seg=seg - 2)
    for k in range(4):
        a = 45 + 90 * k
        p.prism((x, tail + 0.20, z), [(0.0, r * 0.6), (0.0, -0.1), (r * 2.2, -0.12), (r * 2.2, 0.08)],
                0.025, accent, axis="X", rot=(0, a, 0))
    return p


def missile(name="Missile"):
    """Projectile seul : origine au centre, nez vers +Y."""
    p = Part(name)
    _missile(p, (0, 0, 0))
    p.cyl((0, -0.98, 0), 0.07, 0.25, "Flamme", axis="Y", seg=8, r2=0.0, rot=(180, 0, 0))
    return [p.finish()]


def missile_launcher():
    """Caisson a 2 x 3 tubes sur affut orientable. Pivots : `Lance_Missiles`
    (racine, lacet), `Lance_Missiles_Caisson` (tangage) ; missiles
    `Missile_1..6` separes (caches un a un quand ils partent)."""
    obs = []
    b = Part("Lance_Missiles")
    b.cyl((0, 0, 0.10), 0.55, 0.20, "Chassis", seg=18)
    b.box((0, 0, 0.40), (0.70, 0.60, 0.40), "Blindage", bevel=0.06)
    for sx in (-1, 1):
        b.box((sx * 0.55, 0, 0.70), (0.12, 0.50, 0.70), "Blindage", bevel=0.04)
    base = b.finish()
    obs.append(base)
    piv = (0, 0, 0.85)
    c = Part("Lance_Missiles_Caisson", piv)
    c.box((0, 0.0, 0.95), (1.05, 1.90, 0.75), "Blindage", bevel=0.08, seg=2)
    kit.hazard_stripes(c, (0, 0.96, 1.36), (1.05, 0.04, 0.10), 8, axis="X")
    for sx in (-1, 1):
        c.box((sx * 0.53, 0.0, 0.95), (0.02, 1.4, 0.18), "Aimant_Rouge")
    tubes = []
    for row, z in enumerate((1.12, 0.78)):
        for col, x in enumerate((-0.32, 0.0, 0.32)):
            c.cyl((x, 0.96, z), 0.15, 0.04, "Chassis", axis="Y", seg=12)
            c.lathe((x, 0, z), [(0.17, 0.98), (0.17, 0.92), (0.15, 0.92), (0.15, 0.98)],
                    "Aluminium", axis="Y", seg=12, closed=True)
            tubes.append((x, z))
    caisson = c.finish(base)
    obs.append(caisson)
    for k, (x, z) in enumerate(tubes, start=1):
        m = Part("Missile_%d" % k, (x, 0.30, z))
        _missile(m, (x, 0.30, z), length=1.30, r=0.12, seg=8)
        obs.append(m.finish(caisson))
    return obs


# ---------------------------------------------------------------------------
# Scie geante laterale
# ---------------------------------------------------------------------------

def saw(side="D"):
    """Bras hydraulique + lame circulaire. `side` : D (vers +X) ou G (-X).
    Pivots : `Scie_Bras` (racine, deploiement), `Scie_Lame` (rotation, axe X)."""
    s = 1 if side == "D" else -1
    obs = []
    a = Part("Scie_Bras_" + side)
    a.box((s * 0.10, 0, 0), (0.20, 0.70, 0.60), "Blindage", bevel=0.05)
    a.box((s * 0.75, 0, 0.05), (1.30, 0.32, 0.30), "Blindage", bevel=0.05)
    kit.hazard_stripes(a, (s * 0.75, 0.165, 0.05), (1.20, 0.02, 0.26), 8, axis="X")
    kit.hazard_stripes(a, (s * 0.75, -0.165, 0.05), (1.20, 0.02, 0.26), 8, axis="X")
    a.cyl((s * 0.55, 0, 0.32), 0.07, 1.0, "Chrome", axis="X", seg=8)
    a.cyl((s * 0.20, 0, 0.32), 0.10, 0.4, "Chassis", axis="X", seg=10)
    # Carter moteur + carter de protection (demi-disque) de la lame.
    a.cyl((s * 1.40, 0, 0.05), 0.30, 0.34, "Aimant_Rouge", axis="X", seg=16)
    a.cyl((s * 1.62, 0, 0.05), 0.12, 0.10, "Chrome", axis="X", seg=10)
    a.arc((s * 1.55, 0, 0.05), 1.10, 1.22, 0.24, 15, 165, "Blindage", axis="X", seg=10)
    arm = a.finish()
    obs.append(arm)
    hub = (s * 1.55, 0, 0.05)
    blade = Part("Scie_Lame_" + side, hub)
    teeth = 32
    pts = []
    for k in range(teeth):
        a0 = 2 * math.pi * k / teeth
        a1 = 2 * math.pi * (k + 0.55) / teeth
        pts.append((1.05 * math.cos(a0), 1.05 * math.sin(a0)))
        pts.append((1.18 * math.cos(a1), 1.18 * math.sin(a1)))
    blade.prism(hub, pts, 0.04, "Lame_Acier", axis="X")
    blade.cyl(hub, 0.55, 0.06, "Chassis", axis="X", seg=20, smooth=False)
    blade.cyl(hub, 0.22, 0.10, "Chrome", axis="X", seg=12, smooth=False)
    for k in range(6):
        a0 = 2 * math.pi * k / 6
        blade.cyl((hub[0], 0.40 * math.cos(a0), 0.05 + 0.40 * math.sin(a0)), 0.07, 0.08,
                  "Aimant_Rouge", axis="X", seg=8, smooth=False)
    obs.append(blade.finish(arm))
    return obs


# ---------------------------------------------------------------------------
# Mitrailleuse de toit (cabine du tracteur)
# ---------------------------------------------------------------------------

def machine_gun():
    """Tourelle a canons rotatifs. Pivots : `Mitrailleuse_Socle` (racine),
    `Mitrailleuse_Tourelle` (lacet), `Mitrailleuse_Canon` (tangage),
    `Mitrailleuse_Barillet` (rotation des canons, axe Y)."""
    obs = []
    b = Part("Mitrailleuse_Socle")
    b.cyl((0, 0, 0.06), 0.62, 0.12, "Chassis", seg=20)
    b.cyl((0, 0, 0.18), 0.48, 0.14, "Blindage", seg=20)
    for k in range(8):
        a = 2 * math.pi * k / 8
        b.cyl((0.54 * math.cos(a), 0.54 * math.sin(a), 0.13), 0.04, 0.04, "Chrome", seg=6)
    base = b.finish()
    obs.append(base)
    t = Part("Mitrailleuse_Tourelle", (0, 0, 0.25))
    t.box((0, -0.05, 0.50), (0.80, 0.80, 0.45), "Blindage", bevel=0.08, seg=2)
    # Boucliers inclines.
    for sx in (-1, 1):
        t.hull([(sx * x, y, z) for (x, y, z) in
                ((0.42, 0.45, 0.30), (0.42, 0.45, 1.05), (0.42, -0.30, 0.30), (0.42, -0.30, 0.85),
                 (0.50, 0.45, 0.30), (0.50, 0.45, 1.05), (0.50, -0.30, 0.30), (0.50, -0.30, 0.85))],
               "Blindage", smooth=True)
    t.box((0, -0.55, 0.55), (0.55, 0.40, 0.40), "Grenade_Kaki", bevel=0.04)  # caisse de munitions
    kit.hazard_stripes(t, (0, -0.76, 0.55), (0.55, 0.02, 0.10), 6, axis="X")
    tur = t.finish(base)
    obs.append(tur)
    gp = (0, 0.15, 0.62)
    g = Part("Mitrailleuse_Canon", gp)
    g.box((0, 0.15, 0.62), (0.34, 0.60, 0.34), "Chassis", bevel=0.06)
    g.box((0, 0.20, 0.86), (0.08, 0.20, 0.12), "Neon_Rouge")  # viseur
    # Bande de cartouches vers la caisse.
    for k in range(6):
        g.box((-0.20, -0.12 - 0.07 * k, 0.55 - 0.02 * k), (0.10, 0.05, 0.09), "Laiton")
    gun = g.finish(tur)
    obs.append(gun)
    bp = (0, 0.45, 0.62)
    br = Part("Mitrailleuse_Barillet", bp)
    for k in range(6):
        a = 2 * math.pi * k / 6
        br.cyl((0.09 * math.cos(a), 1.05, 0.62 + 0.09 * math.sin(a)), 0.035, 1.25,
               "Chassis", axis="Y", seg=8)
    for y in (0.55, 1.20, 1.62):
        br.cyl((0, y, 0.62), 0.15, 0.06, "Chrome", axis="Y", seg=12)
    br.cyl((0, 1.68, 0.62), 0.13, 0.04, "Chassis", axis="Y", seg=10)
    obs.append(br.finish(gun))
    return obs


# ---------------------------------------------------------------------------
# Projectiles
# ---------------------------------------------------------------------------

def grenade():
    """Grenade a ailettes geante (0,9 m), origine au centre."""
    p = Part("Grenade")
    p.lathe((0, 0, 0), [(0.0, -0.42), (0.20, -0.40), (0.31, -0.28), (0.34, -0.05),
                        (0.31, 0.20), (0.22, 0.34), (0.0, 0.38)], "Grenade_Kaki", seg=16)
    # Quadrillage en relief.
    for z in (-0.22, -0.05, 0.12):
        p.lathe((0, 0, 0), [(0.355, z + 0.025), (0.355, z - 0.025), (0.32, z - 0.025),
                            (0.32, z + 0.025)], "Grenade_Kaki", seg=16, closed=True)
    for k in range(8):
        a = 360 * k / 8
        p.box((0.33 * math.cos(math.radians(a)), 0.33 * math.sin(math.radians(a)), -0.05),
              (0.04, 0.04, 0.55), "Grenade_Kaki", rot=(0, 0, a))
    p.cyl((0, 0, 0.42), 0.12, 0.14, "Laiton", seg=12)
    p.box((0.10, 0, 0.30), (0.06, 0.10, 0.40), "Laiton", rot=(0, 20, 0))   # cuillere
    p.lathe((-0.18, 0, 0.45), [(0.10, 0.015), (0.10, -0.015), (0.08, -0.015), (0.08, 0.015)],
            "Chrome", axis="X", seg=12, closed=True)                          # goupille
    return [p.finish()]


def truck_projectile(color="Orange"):
    """Camion compact lance comme projectile (5 m), origine au centre."""
    liv = kit.livery(color)
    p = Part("Camion_Projectile")
    p.box((0, 0.95, 0.30), (2.20, 1.90, 2.10), liv["cab"], bevel=0.18, seg=2)
    p.box((0, 1.904, 0.75), (1.80, 0.02, 0.75), "Plastique_Interieur")
    p.box((0, 1.918, 0.75), (1.80, 0.01, 0.75), "Vitre")
    p.box((0, 1.92, -0.15), (1.30, 0.04, 0.50), "Plastique_Noir")
    for k in range(3):
        p.box((0, 1.95, -0.30 + 0.15 * k), (1.20, 0.03, 0.03), "Chrome")
    for sx in (-1, 1):
        p.box((sx * 0.80, 1.93, -0.55), (0.35, 0.04, 0.18), "Phare")
        p.box((sx * 1.104, 1.20, 0.75), (0.02, 1.0, 0.65), "Plastique_Interieur")
        p.box((sx * 1.118, 1.20, 0.75), (0.01, 1.0, 0.65), "Vitre")
        p.cyl((sx * 0.95, 0.0, 1.40), 0.08, 1.1, "Chrome", seg=10)
    p.box((0, 2.00, -0.80), (2.30, 0.30, 0.30), "Plastique_Noir", bevel=0.05)
    p.box((0, -1.25, 0.20), (2.30, 2.50, 2.20), liv["box"], bevel=0.10, seg=2)
    for sx in (-1, 1):
        p.box((sx * 1.16, -1.25, -0.30), (0.02, 2.4, 0.25), liv["stripe"])
    p.box((0, 0.0, -1.00), (1.20, 4.6, 0.30), "Chassis")
    for sx in (-1, 1):
        for y in (1.25, -1.55):
            p.cyl((sx * 1.05, y, -1.05), 0.55, 0.42, "Pneu", axis="X", seg=14)
            p.cyl((sx * 1.27, y, -1.05), 0.32, 0.04, "Jante", axis="X", seg=14, smooth=False)
    # Trainee de flammes (il vole).
    for sx in (-1, 1):
        p.cyl((sx * 0.55, -2.80, -0.40), 0.22, 0.6, "Flamme", axis="Y", seg=10, r2=0.0,
              rot=(180, 0, 0))
    return [p.finish()]


def teddy():
    """Doudou geant (3,2 m de haut assis), origine au centre. Ours generique."""
    p = Part("Doudou_Geant")
    fur, light = "Peluche_Marron", "Peluche_Beige"
    p.sphere((0, 0, -0.30), 0.95, fur, seg=14, rings=9, scale=(1.0, 0.85, 1.05))
    p.sphere((0, 0.45, -0.30), 0.60, light, seg=14, rings=8, scale=(1.0, 0.55, 1.1))
    p.sphere((0, 0, 0.95), 0.72, fur, seg=14, rings=9)
    p.sphere((0, 0.55, 0.82), 0.32, light, seg=12, rings=8, scale=(1.1, 0.8, 0.8))
    p.sphere((0, 0.80, 0.92), 0.09, "Oeil", seg=10, rings=6, scale=(1.3, 1, 0.9))
    for sx in (-1, 1):
        p.sphere((sx * 0.52, 0.0, 1.55), 0.26, fur, seg=12, rings=7, scale=(1, 0.6, 1))
        p.sphere((sx * 0.52, 0.06, 1.55), 0.15, "Peluche_Rose", seg=10, rings=6, scale=(1, 0.5, 1))
        p.sphere((sx * 0.25, 0.63, 1.10), 0.08, "Oeil", seg=10, rings=6)
        p.sphere((sx * 0.27, 0.69, 1.13), 0.025, "Texte_Blanc", seg=6, rings=4)
        # Bras et jambes.
        p.sphere((sx * 0.95, 0.15, 0.0), 0.32, fur, seg=10, rings=7, scale=(0.9, 0.9, 1.5),
                 rot=(0, sx * 30, 0))
        p.sphere((sx * 0.55, 0.65, -1.05), 0.36, fur, seg=10, rings=7, scale=(0.95, 1.4, 0.9))
        p.sphere((sx * 0.55, 1.12, -1.05), 0.25, light, seg=10, rings=6, scale=(1, 0.35, 1))
    # Noeud papillon et couture rapiecee.
    p.box((0, 0.62, 0.28), (0.14, 0.14, 0.14), "Ruban_Rouge", bevel=0.04)
    for sx in (-1, 1):
        p.hull([(sx * 0.07, 0.62, 0.28), (sx * 0.38, 0.60, 0.45), (sx * 0.38, 0.60, 0.11),
                (sx * 0.07, 0.68, 0.28), (sx * 0.38, 0.66, 0.45), (sx * 0.38, 0.66, 0.11)],
               "Ruban_Rouge")
    # Piece rapiecee posee sur le ventre (normale ~ +Y inclinee vers +X).
    p.box((0.40, 0.735, -0.20), (0.35, 0.04, 0.30), "Peluche_Rose", bevel=0.01, rot=(0, 0, -25))
    for k in range(4):
        p.box((0.29 + 0.07 * k, 0.765 - 0.03 * k, -0.20), (0.02, 0.02, 0.38), "Couture", rot=(0, 0, -25))
    return [p.finish()]


# ---------------------------------------------------------------------------
# Bouclier cybernetique
# ---------------------------------------------------------------------------

def shield_emitter():
    """Emetteur de toit (antenne a anneaux neon). Origine = point d'accroche."""
    p = Part("Bouclier_Emetteur")
    p.cyl((0, 0, 0.08), 0.50, 0.16, "Blindage", seg=6)
    p.cyl((0, 0, 0.20), 0.38, 0.10, "Neon_Cyan", seg=6)
    p.cyl((0, 0, 0.55), 0.10, 0.70, "Chrome", seg=10)
    for k, z in enumerate((0.45, 0.70, 0.95)):
        r = 0.32 - 0.07 * k
        p.lathe((0, 0, z), [(r, 0.03), (r, -0.03), (r - 0.05, -0.03), (r - 0.05, 0.03)],
                "Neon_Cyan", seg=16, closed=True)
    p.sphere((0, 0, 1.0), 0.13, "Neon_Cyan", seg=12, rings=8)
    for k in range(3):
        a = 120 * k
        p.box((0.32 * math.cos(math.radians(a)), 0.32 * math.sin(math.radians(a)), 0.32),
              (0.06, 0.06, 0.30), "Blindage", rot=(0, 0, a))
    return [p.finish()]


def shield_shell(rx=2.8, ry=11.6, rz=4.6):
    """Coque d'energie a facettes hexagonales (ellipsoide autour du camion et
    de sa remorque). Origine au centre ; mise a l'echelle libre dans Godot.
    `Bouclier_Coque` (translucide) + `Bouclier_Trame` (aretes lumineuses)."""
    import bmesh
    from mathutils import Matrix, Vector

    obs = []
    coque = Part("Bouclier_Coque")
    t = bmesh.new()
    bmesh.ops.create_icosphere(t, subdivisions=2, radius=1.0)
    bmesh.ops.scale(t, vec=Vector((rx, ry, rz)), verts=t.verts)
    t.normal_update()
    coque._merge(t, "Bouclier_Coque", Matrix.Identity(4), True)
    obs.append(coque.finish())
    trame = Part("Bouclier_Trame")
    t = bmesh.new()
    bmesh.ops.create_icosphere(t, subdivisions=2, radius=1.0)
    # Trame hexagonale = dual de l'icosphere : chaque arete relie les centres
    # des deux faces qu'elle separe (alveoles a 6 cotes, 12 a 5 cotes).
    scale = Vector((rx, ry, rz))
    t2 = bmesh.new()
    for e in t.edges:
        if len(e.link_faces) != 2:
            continue
        a, b = (f.calc_center_median().normalized() * 1.002 for f in e.link_faces)
        a = Vector((a.x * scale.x, a.y * scale.y, a.z * scale.z))
        b = Vector((b.x * scale.x, b.y * scale.y, b.z * scale.z))
        mid, d = (a + b) / 2, b - a
        if d.length < 1e-6:
            continue
        cyl = bmesh.new()
        bmesh.ops.create_cone(cyl, cap_ends=False, segments=3, radius1=0.06,
                              radius2=0.06, depth=d.length)
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(cyl, matrix=Matrix.Translation(mid) @ rot, verts=cyl.verts)
        vmap = {v: t2.verts.new(v.co) for v in cyl.verts}
        for f in cyl.faces:
            t2.faces.new([vmap[v] for v in f.verts])
        cyl.free()
    t.free()
    bmesh.ops.recalc_face_normals(t2, faces=t2.faces)
    t2.normal_update()
    trame._merge(t2, "Bouclier_Trame", Matrix.Identity(4), False)
    obs.append(trame.finish(obs[0]))
    return obs


# ---------------------------------------------------------------------------
# Rayon laser
# ---------------------------------------------------------------------------

def laser_emitter():
    """Canon laser orientable. Pivots : `Laser_Socle` (racine, lacet),
    `Laser_Canon` (tangage). Le faisceau part du vide `Laser_Bouche`."""
    obs = []
    b = Part("Laser_Socle")
    b.cyl((0, 0, 0.08), 0.45, 0.16, "Blindage", seg=8)
    for sx in (-1, 1):
        b.box((sx * 0.30, 0, 0.45), (0.10, 0.40, 0.65), "Blindage", bevel=0.03)
    b.lathe((0, 0, 0.17), [(0.40, 0.02), (0.40, -0.02), (0.34, -0.02), (0.34, 0.02)],
            "Neon_Rouge", seg=8, closed=True)
    base = b.finish()
    obs.append(base)
    cp = (0, 0, 0.62)
    c = Part("Laser_Canon", cp)
    c.cyl((0, -0.10, 0.62), 0.24, 0.90, "Chassis", axis="Y", seg=14)
    for k in range(5):
        c.cyl((0, -0.40 + 0.13 * k, 0.62), 0.30, 0.05, "Blindage", axis="Y", seg=14, smooth=False)
    c.cyl((0, 0.55, 0.62), 0.14, 0.40, "Chrome", axis="Y", seg=12)
    for y in (0.45, 0.62):
        c.lathe((0, 0, 0.62), [(0.17, y + 0.03), (0.17, y - 0.03), (0.13, y - 0.03), (0.13, y + 0.03)],
                "Neon_Rouge", axis="Y", seg=12, closed=True)
    c.cyl((0, 0.77, 0.62), 0.10, 0.04, "Laser_Coeur", axis="Y", seg=12)
    c.box((0, -0.62, 0.62), (0.30, 0.14, 0.30), "Neon_Violet", bevel=0.04)
    can = c.finish(base)
    obs.append(can)
    obs.append(empty("Laser_Bouche", (0, 0.80, 0.62), can, size=0.15))
    return obs


def laser_beam():
    """Faisceau de 1 m vers +Y depuis l'origine : s'etire en Y dans Godot."""
    p = Part("Laser_Faisceau")
    p.cyl((0, 0.5, 0), 0.05, 1.0, "Laser_Coeur", axis="Y", seg=8, smooth=False)
    h = Part("Laser_Halo")
    h.cyl((0, 0.5, 0), 0.16, 1.0, "Laser_Halo", axis="Y", seg=10)
    core = p.finish()
    return [core, h.finish(core)]


# ---------------------------------------------------------------------------
# Boomerang aimante
# ---------------------------------------------------------------------------

def boomerang():
    """Boomerang aimante sur son support de toit. `Boomerang_Support`
    (racine, accroche) ; `Boomerang` (pivot au centre de rotation en vol)."""
    obs = []
    s = Part("Boomerang_Support")
    s.box((0, 0, 0.08), (0.70, 0.50, 0.16), "Blindage", bevel=0.04)
    for sx in (-1, 1):
        s.box((sx * 0.25, 0, 0.30), (0.08, 0.30, 0.40), "Chassis")
        s.box((sx * 0.25, 0.08, 0.48), (0.08, 0.14, 0.06), "Neon_Cyan")
    sup = s.finish()
    obs.append(sup)
    centre = (0, 0.15, 0.55)
    b = Part("Boomerang", centre)
    # Forme en V epaisse, coude arrondi : profil dans le plan XY, extrude en Z.
    oy = 0.50                       # le profil est decale vers l'avant
    elbow = [(0.18 * math.sin(math.radians(a)), 0.10 + 0.18 * math.cos(math.radians(a)))
             for a in range(40, -41, -16)]
    pts = ([(-1.25, -0.80), (-1.15, -0.98), (0.0, -0.38), (1.15, -0.98), (1.25, -0.80),
            (0.70, -0.45)] + elbow + [(-0.70, -0.45)])
    b.prism((0, oy, 0.55), pts, 0.12, "Peinture_Cabine_Violet", axis="Z")
    # Filets neon le long des deux bras.
    for sx in (-1, 1):
        b.box((sx * 0.60, oy - 0.52, 0.615), (1.10, 0.06, 0.02), "Neon_Cyan",
              rot=(0, 0, -sx * 39))
    # Aimants en U aux deux bouts : corps rouge, poles acier.
    for sx in (-1, 1):
        cx, cy = sx * 1.17, oy - 0.89
        b.arc((cx, cy, 0.55), 0.10, 0.22, 0.16, 0, 180, "Aimant_Rouge", axis="Y", seg=8)
        for px in (-0.16, 0.16):
            b.box((cx + px, cy, 0.48), (0.12, 0.16, 0.14), "Chrome")
        # Eclairs de champ magnetique.
        b.prism((cx, cy + 0.10, 0.36), [(-0.05, 0.0), (0.03, -0.10), (-0.01, -0.10),
                                         (0.05, -0.22), (-0.03, -0.12), (0.01, -0.12)],
                0.02, "Neon_Cyan", axis="Y")
    obs.append(b.finish(sup))
    return obs
