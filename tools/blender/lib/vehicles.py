"""Vehicules : tracteurs, porteurs, semi-remorques, chariot elevateur.

Cotes du tracteur : docs/VEHICLE_SPEC.md (echelle x1,2 du 2026-09-30), en
repere Blender (X droite, Y avant, Z haut) :
  - origine au sol, au milieu de l'empattement et de la voie ;
  - roues `Wheel_FL/FR/RL/RR` a x = +-1,26, y = +-2,28, moyeu a 0,66 m,
    rayon 0,66 m, largeur 0,48 m, pivot EXACTEMENT au moyeu ;
  - tracteur de y = +3,48 (avant) a -3,46 ; largeur 2,9 m ; cabine 3,8 m ;
  - sellette (pivot de la remorque) en (0 ; -1,44 ; 2,16) : un vide
    `Remorque` y est pose, toute la semi-remorque en est l'enfant.

Points d'accroche des armes (vides `Socket_*`, voir docs/ART_PIPELINE.md §4 ter) :
  Socket_Toit, Socket_Avant, Socket_Lateral_G, Socket_Lateral_D sur le
  tracteur ; Socket_Arriere et Socket_Conteneur sur la remorque (ils suivent
  son articulation) ou sur la caisse d'un porteur.

Le maillage n'a aucune autorite sur la physique (VEHICLE_SPEC §9).
"""

import math

from lib import kit
from lib.kit import Part, empty

# --- Contrat VEHICLE_SPEC (x1,2), repere Blender ----------------------------
WHEEL_X = 1.26
WHEEL_Y = 2.28
WHEEL_R = 0.66
WHEEL_W = 0.48
FRONT_Y = 3.48
REAR_Y = -3.46
KINGPIN = (0.0, -1.44, 2.16)

# Cabine
CAB_W = 2.70
CAB_REAR = 0.84
CAB_BOTTOM = 1.05
CAB_TOP = 3.80

# Semi-remorque : de y = +0,4 a -15,9 (ensemble jusqu'a z = +16,2 Godot).
TRL_FRONT = 0.40
TRL_REAR = -15.90
TRL_DECK = 2.10          # dessus du chassis de remorque
TRL_AXLES = (-11.6, -13.0, -14.4)

WHEELS = {
    "Wheel_FL": (-WHEEL_X, WHEEL_Y, WHEEL_R, -1),
    "Wheel_FR": (WHEEL_X, WHEEL_Y, WHEEL_R, 1),
    "Wheel_RL": (-WHEEL_X, -WHEEL_Y, WHEEL_R, -1),
    "Wheel_RR": (WHEEL_X, -WHEEL_Y, WHEEL_R, 1),
}

TRUCK_WHEELS = list(WHEELS)


# ---------------------------------------------------------------------------
# Roues
# ---------------------------------------------------------------------------

def make_wheels(w=WHEEL_W, layout=None, twin_rear=True):
    """Roues separees, pivot au moyeu. Roue posee : rayon = hauteur du moyeu.

    `twin_rear` : roues arriere jumelees (comme les camions de l'equipe). La
    roue interieure fait partie du meme objet `Wheel_R*` : elle tourne avec
    lui, et son pivot reste le moyeu de la roue exterieure (contrat)."""
    layout = layout or WHEELS
    obs = []
    for name, (x, y, z, side) in layout.items():
        p = Part(name, (x, y, z))
        kit.wheel(p, (x, y, z), side, r=z, w=w)
        if twin_rear and name in ("Wheel_RL", "Wheel_RR"):
            kit.wheel(p, (x - side * 0.44, y, z), side, r=z, w=0.38)
        obs.append(p.finish())
    return obs


# ---------------------------------------------------------------------------
# Cabine et chassis du tracteur
# ---------------------------------------------------------------------------

def _front_face(p, liv, front, z_lo, z_hi, width, number):
    """Calandre, phares, pare-chocs, plaque : la face avant commune."""
    y = front
    p.box((0, y + 0.01, (z_lo + z_hi) / 2), (width * 0.63, 0.05, z_hi - z_lo), "Plastique_Noir")
    n = 5
    for k in range(n):
        z = z_lo + 0.12 + (z_hi - z_lo - 0.24) * k / (n - 1)
        p.box((0, y + 0.04, z), (width * 0.59, 0.03, 0.035), "Chrome")
    for sx in (-1, 1):
        p.box((sx * width * 0.36, y + 0.01, z_lo - 0.02), (0.48, 0.05, 0.29), "Chrome", bevel=0.03)
        p.box((sx * width * 0.36, y + 0.02, z_lo - 0.02), (0.44, 0.06, 0.25), "Plastique_Noir", bevel=0.03)
        for k in (-1, 1):
            p.cyl((sx * width * 0.36 + k * 0.11, y + 0.05, z_lo - 0.02), 0.085, 0.03, "Phare",
                  axis="Y", seg=14)
            p.lathe((sx * width * 0.36 + k * 0.11, 0, z_lo - 0.02),
                    [(0.10, y + 0.07), (0.10, y + 0.04), (0.085, y + 0.04), (0.085, y + 0.07)],
                    "Chrome", axis="Y", seg=14, closed=True)
        p.box((sx * width * 0.46, y + 0.02, z_lo - 0.02), (0.15, 0.06, 0.12), "Clignotant", bevel=0.02)
    # Pare-chocs, lame, plaque neutre (sans bande d'un pays).
    p.box((0, y + 0.10, 1.00), (2.90, 0.34, 0.42), "Plastique_Noir", bevel=0.06, seg=2)
    p.box((0, y + 0.16, 0.74), (3.00, 0.46, 0.06), "Carbone", bevel=0.02)
    p.box((0, y + 0.28, 1.00), (0.62, 0.02, 0.14), "Plaque_Fond")
    for sx in (-1, 1):
        p.box((sx * 1.30, y + 0.27, 1.08), (0.18, 0.03, 0.09), "Clignotant")


def _mirrors(p, y, z):
    for sx in (-1, 1):
        p.cyl((sx * 1.50, y, z + 0.15), 0.025, 0.32, "Chrome", axis="X", seg=8)
        p.cyl((sx * 1.50, y, z - 0.30), 0.02, 0.32, "Chrome", axis="X", seg=8)
        p.box((sx * 1.66, y - 0.04, z), (0.07, 0.18, 0.48), "Plastique_Noir", bevel=0.02)
        p.box((sx * 1.66, y - 0.135, z), (0.05, 0.01, 0.42), "Chrome")
        p.box((sx * 1.66, y - 0.04, z - 0.40), (0.07, 0.16, 0.20), "Plastique_Noir", bevel=0.02)
        p.box((sx * 1.66, y - 0.125, z - 0.40), (0.05, 0.01, 0.15), "Chrome")


def _race_number(p, x, y, z, number):
    """Rond blanc + numero noir, des deux cotes (style des camions de l'equipe)."""
    for sx in (-1, 1):
        p.cyl((sx * x, y, z), 0.32, 0.02, "Texte_Blanc", axis="X", seg=20, smooth=False)
        rot = (90, 0, 90) if sx > 0 else (90, 0, -90)
        p.text((sx * (x + 0.012), y, z), number, 0.42, "Texte_Noir", rot=rot)


def _stacks(p, y, z_top=4.30, x=1.22):
    """Cheminees chromees a flamme (signature des camions de l'equipe)."""
    for sx in (-1, 1):
        zc = (1.0 + z_top) / 2
        p.cyl((sx * x, y, zc), 0.10, z_top - 1.0, "Chrome", seg=12)
        p.cyl((sx * x, y, 1.35), 0.125, 0.15, "Carbone", seg=12)
        p.cyl((sx * x, y, 2.25), 0.13, 0.90, "Chrome", seg=12)
        for k in range(6):
            p.box((sx * (x + 0.125), y, 1.90 + 0.14 * k), (0.02, 0.10, 0.06), "Carbone")
        for z in (1.78, 2.72, z_top - 0.05):
            p.lathe((sx * x, y, z), [(0.14, 0.02), (0.14, -0.02), (0.10, -0.02), (0.10, 0.02)],
                    "Carbone", seg=12, closed=True)
        p.cyl((sx * x, y, z_top + 0.25), 0.10, 0.50, "Flamme", seg=8, r2=0.0)


def _roof_lights(p, y, z, width=1.8, n=4, m="Phare"):
    p.box((0, y, z), (width, 0.20, 0.15), "Plastique_Noir", bevel=0.03)
    for k in range(n):
        x = -width * 0.36 + width * 0.72 * k / max(n - 1, 1)
        p.cyl((x, y + 0.11, z), 0.085, 0.08, m, axis="Y", seg=10)


def chassis(p, rear=REAR_Y, front=FRONT_Y - 0.25):
    """Longerons, traverses, reservoirs, marchepieds, feux arriere."""
    L = front - rear
    cy = (front + rear) / 2
    for sx in (-1, 1):
        p.box((sx * 0.50, cy, 0.92), (0.16, L, 0.34), "Chassis")
    for y in (2.9, 1.0, -1.0, -2.9):
        if rear < y < front:
            p.box((0, y, 0.92), (0.90, 0.14, 0.22), "Chassis")
    for sx in (-1, 1):
        p.cyl((sx * 1.00, 0.15, 0.88), 0.32, 1.30, "Aluminium", axis="Y", seg=14)
        p.box((sx * 1.00, 0.15, 0.88), (0.68, 0.06, 0.68), "Chassis")
        for z in (0.55, 0.25):
            p.box((sx * 1.30, 1.25, z), (0.38, 0.42, 0.06), "Aluminium", bevel=0.01)
    chassis_details(p, rear)
    # Barre arriere + feux.
    p.box((0, rear + 0.08, 0.78), (2.50, 0.14, 0.18), "Chassis")
    for sx in (-1, 1):
        p.box((sx * 0.85, rear + 0.02, 0.98), (0.48, 0.05, 0.16), "Feu_Arriere", bevel=0.02)
        p.box((sx * 0.55, rear + 0.02, 0.98), (0.14, 0.05, 0.16), "Phare")


def chassis_details(p, rear=REAR_Y):
    """Mecanique visible sous le camion : essieux, pont, ressorts a lames,
    amortisseurs, arbre de transmission, boite, reservoirs d'air, batteries."""
    # Essieu avant (poutre) et pont arriere (trompettes + differentiel).
    p.box((0, WHEEL_Y, WHEEL_R), (2.10, 0.16, 0.18), "Chassis", bevel=0.04)
    p.cyl((0, -WHEEL_Y, WHEEL_R), 0.11, 2.20, "Chassis", axis="X", seg=12)
    p.sphere((0, -WHEEL_Y, WHEEL_R), 0.30, "Chassis", seg=14, rings=8, scale=(1.0, 0.9, 0.85))
    p.cyl((0, -WHEEL_Y + 0.28, WHEEL_R), 0.10, 0.18, "Acier_Sellette", axis="Y", seg=12)
    for y in (WHEEL_Y, -WHEEL_Y):
        for sx in (-1, 1):
            # Ressort a lames : 5 lames empilees, de plus en plus courtes.
            for k in range(5):
                p.box((sx * 0.50, y, 0.80 - 0.035 * k), (0.10, 1.40 - 0.22 * k, 0.03), "Acier_Sellette",
                      bevel=0.01)
            for sy in (-1, 1):
                p.box((sx * 0.50, y + sy * 0.70, 0.83), (0.12, 0.10, 0.10), "Chassis")
            p.box((sx * 0.50, y, 0.72), (0.14, 0.20, 0.10), "Chrome")      # bride
            # Amortisseur incline.
            p.cyl((sx * 0.74, y + 0.25, 0.92), 0.05, 0.55, "Danger_Jaune", seg=10, rot=(18, 0, 0))
            p.cyl((sx * 0.74, y + 0.20, 1.05), 0.035, 0.40, "Chrome", seg=8, rot=(18, 0, 0))
    # Moteur, boite, arbre de transmission.
    p.box((0, 2.30, 0.95), (0.85, 1.30, 0.55), "Chassis", bevel=0.06)
    p.box((0, 1.25, 0.82), (0.55, 0.80, 0.42), "Acier_Sellette", bevel=0.05)
    p.cyl((0, (0.85 - WHEEL_Y + 0.4) / 2, 0.72), 0.065, 0.85 + WHEEL_Y - 0.4 - 0.3, "Chrome",
          axis="Y", seg=10, rot=(4, 0, 0))
    for y in (0.75, -WHEEL_Y + 0.45):
        p.cyl((0, y, 0.72), 0.09, 0.08, "Chassis", axis="Y", seg=10)
    # Reservoirs d'air et coffre a batteries.
    for sx in (-1, 1):
        p.cyl((sx * 0.80, -1.10, 0.62), 0.14, 0.95, "Acier_Sellette", axis="Y", seg=12)
        for y in (-0.70, -1.50):
            p.lathe((sx * 0.80, 0, 0.62), [(0.155, y + 0.025), (0.155, y - 0.025), (0.13, y - 0.025),
                                           (0.13, y + 0.025)], "Chrome", axis="Y", seg=12, closed=True)
    p.box((1.05, 1.15, 0.62), (0.40, 0.55, 0.45), "Plastique_Noir", bevel=0.03)
    p.box((1.26, 1.15, 0.70), (0.02, 0.45, 0.06), "Chrome")
    # Sangles chromees des reservoirs de carburant + bouchon.
    for sx in (-1, 1):
        for y in (-0.25, 0.55):
            p.lathe((sx * 1.00, 0, 0.88), [(0.335, y + 0.04), (0.335, y - 0.04), (0.31, y - 0.04),
                                           (0.31, y + 0.04)], "Chrome", axis="Y", seg=14, closed=True)
        p.cyl((sx * 1.00, 0.15, 1.21), 0.07, 0.05, "Chrome", seg=10)


def cab_details(p, front, top, cab_w=CAB_W, door_y=None, roof_y=None):
    """Petits elements qui font la richesse des camions de l'equipe :
    essuie-glaces, antibrouillards, klaxons de toit, antenne, poignees,
    feux de gabarit lateraux, retroviseurs grand-angle."""
    door_y = FRONT_Y - 1.55 if door_y is None else door_y
    roof_y = CAB_REAR + 0.55 if roof_y is None else roof_y
    for sx in (-1, 1):
        # Essuie-glaces en bas du pare-brise.
        p.box((sx * 0.45, front + 0.035, top - 1.23), (0.85, 0.02, 0.025), "Plastique_Noir",
              rot=(0, -sx * 8, 0))
        p.cyl((sx * 0.85, front + 0.03, top - 1.26), 0.03, 0.04, "Plastique_Noir", axis="Y", seg=8)
        # Antibrouillards ronds dans le pare-chocs.
        p.cyl((sx * 0.98, front + 0.28, 0.95), 0.09, 0.04, "Phare", axis="Y", seg=14)
        p.lathe((sx * 0.98, 0, 0.95), [(0.115, front + 0.30), (0.115, front + 0.26), (0.09, front + 0.26),
                                       (0.09, front + 0.30)], "Chrome", axis="Y", seg=14, closed=True)
        # Klaxons pneumatiques chromes sur le toit.
        p.cyl((sx * 0.30, roof_y, top + 0.12), 0.055, 0.60, "Chrome", axis="Y", seg=12)
        p.cyl((sx * 0.30, roof_y + 0.36, top + 0.12), 0.06, 0.16, "Chrome", axis="Y", seg=14, r2=0.12)
        # Poignees de maintien verticales a cote des portes.
        p.cyl((sx * (cab_w / 2 + 0.06), door_y, 2.05), 0.025, 0.90, "Chrome", seg=8)
        for z in (1.62, 2.48):
            p.box((sx * (cab_w / 2 + 0.03), door_y, z), (0.06, 0.03, 0.03), "Chrome")
        # Feux de gabarit lateraux.
        for y in (front - 0.25, CAB_REAR + 0.20):
            p.box((sx * (cab_w / 2 + 0.008), y, 1.30), (0.02, 0.10, 0.06), "Clignotant")
    p.cyl((0.95, CAB_REAR + 0.30, top + 0.50), 0.012, 1.0, "Plastique_Noir", seg=4)   # antenne
    p.sphere((0.95, CAB_REAR + 0.30, top + 1.00), 0.025, "Plastique_Noir", seg=6, rings=4)


def conspicuity(p, x, z, front, rear, n=40):
    """Bande retro-reflechissante rouge / blanche le long d'une remorque."""
    L = front - rear
    for k in range(n):
        m = "Feu_Arriere" if k % 2 else "Texte_Blanc"
        for sx in (-1, 1):
            p.box((sx * x, front - L * (k + 0.5) / n, z), (0.012, L / n * 0.9, 0.05), m)


def rivets(p, x, z, front, rear, step=0.25, r=0.018, m="Aluminium"):
    y = front
    while y > rear:
        for sx in (-1, 1):
            p.cyl((sx * x, y, z), r, 0.02, m, axis="X", seg=2)
        y -= step


def fenders(p, liv, front=True, rear=True, front_m="Plastique_Noir"):
    for sx in (-1, 1):
        if front:
            p.arc((sx * WHEEL_X, WHEEL_Y, WHEEL_R), 0.74, 0.82, 0.58, 0, 180, front_m, seg=10)
        if rear:
            p.arc((sx * WHEEL_X, -WHEEL_Y, WHEEL_R), 0.74, 0.82, 0.62, 0, 180, liv["cab"], seg=10)
            p.box((sx * WHEEL_X, -WHEEL_Y - 0.86, 0.75), (0.56, 0.03, 0.60), "Plastique_Noir")


def cab_flat(p, liv, number, top=CAB_TOP, sleeper=False):
    """Cabine avancee a face plate (silhouette des camions de l'equipe)."""
    cy = (FRONT_Y + CAB_REAR) / 2
    L = FRONT_Y - CAB_REAR
    zc = (CAB_BOTTOM + top) / 2
    p.box((0, cy, zc), (CAB_W, L, top - CAB_BOTTOM), liv["cab"], bevel=0.17, seg=2)
    # Pare-brise et son cadre, vitres laterales, joints de porte.
    p.box((0, FRONT_Y + 0.005, top - 0.75), (CAB_W - 0.30, 0.03, 1.08), "Joint_Porte")
    p.box((0, FRONT_Y + 0.026, top - 0.75), (CAB_W - 0.42, 0.01, 0.96), "Vitre")
    for sx in (-1, 1):
        p.box((sx * (CAB_W / 2 + 0.004), FRONT_Y - 0.80, top - 0.75), (0.02, 1.05, 0.85), "Plastique_Interieur")
        p.box((sx * (CAB_W / 2 + 0.018), FRONT_Y - 0.80, top - 0.75), (0.01, 1.05, 0.85), "Vitre")
        p.box((sx * (CAB_W / 2 + 0.004), FRONT_Y - 1.40, zc), (0.02, 0.025, top - CAB_BOTTOM - 0.35), "Joint_Porte")
        p.box((sx * (CAB_W / 2 + 0.004), FRONT_Y - 0.10, zc - 0.25), (0.02, 0.025, top - CAB_BOTTOM - 0.9), "Joint_Porte")
        p.box((sx * (CAB_W / 2 + 0.02), FRONT_Y - 1.10, zc - 0.05), (0.04, 0.28, 0.06), "Chrome")
        p.box((sx * (CAB_W / 2 + 0.006), cy, CAB_BOTTOM + 0.35), (0.02, L - 0.3, 0.12), liv["stripe"])
    # Pare-soleil, rampe de phares, feux de gabarit.
    p.box((0, FRONT_Y + 0.10, top - 0.12), (CAB_W - 0.2, 0.28, 0.06), "Plastique_Noir")
    _roof_lights(p, FRONT_Y - 0.55, top + 0.08)
    for sx in (-1, 1):
        p.box((sx * 0.62, CAB_REAR + 0.95, top + 0.03), (0.16, 0.08, 0.07), "Clignotant")
    if sleeper:
        # Cellule couchette surelevee + deflecteur : silhouette plus haute.
        p.box((0, CAB_REAR + 1.05, top + 0.30), (CAB_W - 0.10, 2.0, 0.6), liv["cab"], bevel=0.2, seg=2)
        p.hull([(sx * (CAB_W / 2 - 0.1), y, z)
                for sx in (-1, 1)
                for (y, z) in ((CAB_REAR + 2.05, top + 0.05), (CAB_REAR + 0.25, top + 0.60),
                               (CAB_REAR + 0.05, top + 0.60), (CAB_REAR + 0.05, top + 0.05))],
               liv["cab"])
    _front_face(p, liv, FRONT_Y, 1.45, 2.30, CAB_W, number)
    _mirrors(p, FRONT_Y - 0.25, top - 0.95)
    cab_details(p, FRONT_Y, top, roof_y=FRONT_Y - 1.40 if not sleeper else CAB_REAR + 2.15,
                )
    _race_number(p, CAB_W / 2 + 0.006, FRONT_Y - 1.95, CAB_BOTTOM + 1.05, number)
    # Plancher visible sous la cabine.
    p.box((0, cy, CAB_BOTTOM - 0.05), (CAB_W - 0.3, L - 0.3, 0.12), "Plastique_Interieur")


def cab_hood(p, liv, number):
    """Cabine a capot (silhouette distincte des cabines plates)."""
    hood_rear = 1.95
    p.box((0, (FRONT_Y + hood_rear) / 2 - 0.05, 1.80), (2.25, FRONT_Y - hood_rear + 0.1, 1.40),
          liv["cab"], bevel=0.22, seg=2)
    # Capot bombe : dessus legerement incline vers l'avant.
    p.hull([(sx * 1.05, y, z) for sx in (-1, 1)
            for (y, z) in ((FRONT_Y - 0.05, 2.40), (hood_rear, 2.62), (hood_rear, 2.40), (FRONT_Y - 0.05, 2.30))],
           liv["cab"], smooth=False)
    # Calandre haute chromee.
    p.box((0, FRONT_Y + 0.01, 1.85), (1.55, 0.06, 1.05), "Chrome", bevel=0.04)
    p.box((0, FRONT_Y + 0.03, 1.85), (1.35, 0.05, 0.90), "Plastique_Noir")
    for k in range(7):
        p.box((-0.6 + 0.2 * k, FRONT_Y + 0.06, 1.85), (0.04, 0.03, 0.85), "Chrome")
    for sx in (-1, 1):
        p.cyl((sx * 0.95, FRONT_Y - 0.05, 1.50), 0.17, 0.12, "Phare", axis="Y", seg=14)
        p.cyl((sx * 0.95, FRONT_Y - 0.12, 1.50), 0.21, 0.08, "Chrome", axis="Y", seg=14)
        p.box((sx * 1.20, FRONT_Y - 0.15, 1.25), (0.14, 0.06, 0.10), "Clignotant")
        # Ailes avant galbees autour des roues.
        p.arc((sx * WHEEL_X, WHEEL_Y, WHEEL_R), 0.72, 0.84, 0.62, -10, 190, liv["cab"], seg=12)
    p.box((0, FRONT_Y + 0.10, 1.00), (2.90, 0.34, 0.42), "Chrome", bevel=0.08, seg=2)
    p.box((0, FRONT_Y + 0.28, 1.00), (0.62, 0.02, 0.14), "Plaque_Fond")
    # Cabine derriere le capot.
    c_front, c_rear = hood_rear, 0.05
    cy = (c_front + c_rear) / 2
    p.box((0, cy, 2.55), (CAB_W, c_front - c_rear, 2.50), liv["cab"], bevel=0.18, seg=2)
    p.box((0, c_front + 0.004, 3.20), (CAB_W - 0.40, 0.02, 0.85), "Plastique_Interieur")
    p.box((0, c_front + 0.018, 3.20), (CAB_W - 0.40, 0.01, 0.85), "Vitre")
    for sx in (-1, 1):
        p.box((sx * (CAB_W / 2 + 0.004), cy + 0.35, 3.15), (0.02, 0.95, 0.80), "Plastique_Interieur")
        p.box((sx * (CAB_W / 2 + 0.018), cy + 0.35, 3.15), (0.01, 0.95, 0.80), "Vitre")
        p.box((sx * (CAB_W / 2 + 0.006), cy, 1.62), (0.02, c_front - c_rear - 0.3, 0.12), liv["stripe"])
    _roof_lights(p, c_front - 0.30, 3.88, width=1.6, n=5, m="Clignotant")
    _mirrors(p, c_front - 0.10, 2.95)
    cab_details(p, c_front, 3.80, door_y=cy, roof_y=c_front - 0.95)
    _race_number(p, CAB_W / 2 + 0.006, cy - 0.35, 2.10, number)
    p.box((0, (FRONT_Y + c_rear) / 2, 1.0), (1.4, FRONT_Y - c_rear, 0.3), "Chassis")


def tractor(liv, number, style="flat", fifth_wheel=True, stacks_y=CAB_REAR - 0.16):
    """Corps `Body` du tracteur (cabine + chassis), sans les roues."""
    p = Part("Body")
    chassis(p)
    if style == "hood":
        cab_hood(p, liv, number)
        fenders(p, liv, front=False)
        _stacks(p, -0.10, z_top=4.40)
    else:
        cab_flat(p, liv, number, sleeper=(style == "sleeper"))
        fenders(p, liv)
        _stacks(p, stacks_y)
    if fifth_wheel:
        p.box((0, -1.60, 1.15), (1.70, 3.40, 0.10), "Carbone")
        p.box((0, KINGPIN[1], 1.62), (1.10, 1.10, 0.85), "Chassis", bevel=0.05)
        p.cyl((0, KINGPIN[1], KINGPIN[2] - 0.09), 0.72, 0.08, "Acier_Sellette", seg=20)
    return p


def tractor_sockets(body, top=CAB_TOP, roof_y=CAB_REAR + 1.3):
    return [
        empty("Socket_Toit", (0, roof_y, top + 0.05), body),
        empty("Socket_Avant", (0, FRONT_Y + 0.30, 1.20), body),
        empty("Socket_Lateral_G", (-1.55, -0.10, 1.10), body),
        empty("Socket_Lateral_D", (1.55, -0.10, 1.10), body),
    ]


# ---------------------------------------------------------------------------
# Semi-remorques (tout est enfant du vide `Remorque`, pose a la sellette)
# ---------------------------------------------------------------------------

def trailer_base(liv, deck=TRL_DECK, front=TRL_FRONT, rear=TRL_REAR, skirts=True):
    """Chassis commun : longerons, essieux, roues fixes, bequilles, feux."""
    root = empty("Remorque", KINGPIN)
    p = Part("Remorque_Chassis", KINGPIN)
    L = front - rear
    cy = (front + rear) / 2
    for sx in (-1, 1):
        p.box((sx * 0.55, cy, deck - 0.18), (0.18, L - 0.2, 0.36), "Chassis")
    for y in range(int(front) - 1, int(rear), -2):
        p.box((0, y, deck - 0.18), (1.30, 0.12, 0.20), "Chassis")
    p.cyl((0, KINGPIN[1], KINGPIN[2] - 0.02), 0.09, 0.12, "Acier_Sellette", seg=10)
    for y in TRL_AXLES:
        p.box((0, y, WHEEL_R), (2.20, 0.16, 0.16), "Chassis")
        for sx in (-1, 1):
            p.box((sx * 0.55, y, (WHEEL_R + deck - 0.36) / 2), (0.14, 0.30, deck - 0.36 - WHEEL_R + 0.1), "Chassis")
    # Bequilles.
    for sx in (-1, 1):
        p.box((sx * 0.90, -2.4, (deck - 0.36 + 0.35) / 2), (0.16, 0.16, deck - 0.36 - 0.35), "Chassis")
        p.box((sx * 0.90, -2.4, 0.33), (0.40, 0.40, 0.05), "Acier_Sellette")
    p.box((0, -2.4, 1.0), (1.8, 0.07, 0.07), "Chassis")
    # Arriere : pare-encastrement, feux, bavettes.
    p.box((0, rear + 0.05, 0.78), (2.70, 0.15, 0.18), "Chassis")
    for sx in (-1, 1):
        p.box((sx * 1.00, rear - 0.02, deck - 0.45), (0.50, 0.05, 0.17), "Feu_Arriere", bevel=0.02)
        p.box((sx * 0.62, rear - 0.02, deck - 0.45), (0.18, 0.05, 0.17), "Phare")
        p.box((sx * 0.98, rear + 0.75, 0.75), (0.78, 0.03, 0.70), "Plastique_Noir")
        p.box((sx * 0.30, rear + 0.10, deck - 0.45), (0.65, 0.02, 0.14), "Plaque_Fond")
    # Lisse laterale (pare-cycliste) qui porte la bande retro-reflechissante.
    # Entre les bequilles et le premier essieu : jamais au-dessus du tracteur.
    g_front, g_rear = -3.0, TRL_AXLES[0] + 0.9
    for sx in (-1, 1):
        p.box((sx * 1.40, (g_front + g_rear) / 2, deck - 0.30), (0.05, g_front - g_rear, 0.14),
              "Chassis", bevel=0.01)
        for y in (g_front - 0.3, -5.6, -8.2, g_rear + 0.3):
            p.box((sx * 0.98, y, deck - 0.30), (0.80, 0.08, 0.08), "Chassis")
    conspicuity(p, 1.43, deck - 0.30, g_front, g_rear, n=26)
    for sx in (-1, 1):
        p.cyl((sx * 0.25, -4.5, deck - 0.55), 0.17, 1.2, "Acier_Sellette", axis="Y", seg=12)
    p.box((-1.05, -7.5, deck - 0.75), (0.55, 1.1, 0.55), "Plastique_Noir", bevel=0.03)   # coffre
    p.box((-1.33, -7.5, deck - 0.65), (0.02, 0.25, 0.08), "Chrome")
    # Flexibles d'air (rouge / jaune) et cable electrique vers le tracteur.
    for k, (m, x) in enumerate((("Aimant_Rouge", -0.25), ("Danger_Jaune", 0.0), ("Plastique_Noir", 0.25))):
        for j in range(8):
            a = math.radians(45 * j)
            p.cyl((x, front - 0.20 + 0.05 * math.sin(a), deck + 0.25 + 0.05 * math.cos(a) + 0.06 * j),
                  0.025, 0.12, m, axis="X", seg=6, rot=(0, 0, 0))
    if skirts:
        for sx in (-1, 1):
            for z in (deck - 0.70, deck - 0.95):
                p.box((sx * 1.25, (-3.0 + TRL_AXLES[0] + 0.9) / 2, z),
                      (0.04, abs(TRL_AXLES[0] + 0.9 + 3.0), 0.12), "Aluminium")
            for y in (-3.4, -6.5, -9.6):
                p.box((sx * 0.95, y, deck - 0.62), (0.60, 0.08, 0.08), "Chassis")
                p.box((sx * 1.22, y, deck - 0.78), (0.06, 0.08, 0.42), "Chassis")
    obs = [root, p.finish(root)]
    w = Part("Remorque_Roues", KINGPIN)
    for y in TRL_AXLES:
        for sx in (-1, 1):
            kit.wheel(w, (sx * WHEEL_X, y, WHEEL_R), sx, r=WHEEL_R, w=WHEEL_W, seg=14)
    obs.append(w.finish(root))
    return root, obs


def _side_lights(p, x, z, front, rear, n=7):
    for k in range(n):
        y = front - 0.8 - (front - rear - 1.6) * k / (n - 1)
        for sx in (-1, 1):
            p.box((sx * x, y, z), (0.03, 0.12, 0.07), "Clignotant")


def _spoiler(p, liv, rear, z_top, width=3.0):
    """Aileron de course (identite visuelle des remorques de l'equipe)."""
    y = rear + 0.6
    for sx in (-1, 1):
        p.box((sx * 0.60, y, z_top + 0.30), (0.10, 0.22, 0.60), "Carbone")
        p.box((sx * (width / 2 - 0.03), y, z_top + 0.62), (0.06, 1.30, 0.75), liv["cab"], bevel=0.03)
    p.box((0, y, z_top + 0.66), (width, 1.05, 0.14), "Carbone", bevel=0.04, seg=2,
          rot=(-8, 0, 0))


def trailer_tanker(liv, number):
    root, obs = trailer_base(liv, skirts=False)
    p = Part("Remorque_Citerne", KINGPIN)
    r = 1.45
    zc = TRL_DECK + r + 0.05
    front, rear = 0.20, -15.40
    p.lathe((0, 0, zc), [(0.0, front + 0.35), (0.80, front + 0.25), (1.25, front + 0.10),
                         (r, front - 0.15), (r, rear + 0.25), (1.25, rear),
                         (0.80, rear - 0.15), (0.0, rear - 0.25)],
            "Citerne_Inox", axis="Y", seg=22, smooth=True)
    # Cerclages peints.
    for y in (front - 1.5, -4.0, -7.6, -11.2, rear + 1.5):
        p.lathe((0, 0, zc), [(r + 0.04, y + 0.14), (r + 0.04, y - 0.14), (r - 0.02, y - 0.14),
                             (r - 0.02, y + 0.14)], liv["cab"], axis="Y", seg=22, closed=True)
    # Bande decorative longitudinale.
    for sx in (-1, 1):
        p.box((sx * (r - 0.02), (front + rear) / 2, zc - 0.25), (0.06, front - rear - 1.2, 0.22), liv["stripe"])
    # Berceaux, passerelle, trous d'homme, rambardes, echelle.
    for y in (-1.0, -6.0, -10.6, -14.6):
        p.box((0, y, TRL_DECK + 0.25), (2.0, 0.35, 0.50), "Chassis")
    top = zc + r
    p.box((0, (front + rear) / 2, top + 0.06), (0.70, front - rear - 2.0, 0.06), "Aluminium")
    for y in (-2.2, -6.0, -9.8, -13.4):
        p.cyl((0, y, top + 0.10), 0.34, 0.16, "Aluminium", seg=14)
        p.cyl((0, y, top + 0.20), 0.26, 0.06, "Chassis", seg=14)
    for sx in (-1, 1):
        p.cyl((sx * 0.45, (front + rear) / 2, top + 0.65), 0.03, front - rear - 2.2, "Danger_Jaune", axis="Y", seg=6)
        for y in range(0, 15, 2):
            p.cyl((sx * 0.45, front - 1.3 - y, top + 0.37), 0.03, 0.56, "Danger_Jaune", seg=6)
    for sx in (-1, 1):
        p.box((sx * 0.30, rear - 0.30, zc + 0.2), (0.06, 0.06, 2.9), "Aluminium")
    for k in range(7):
        p.box((0, rear - 0.30, zc - 1.1 + 0.4 * k), (0.60, 0.05, 0.05), "Aluminium")
    p.box((0, rear - 0.28, zc - 0.6), (0.55, 0.03, 0.40), "Plaque_Danger")
    for sx in (-1, 1):
        p.box((sx * (r + 0.03), -7.6, zc + 0.15), (0.02, 0.55, 0.40), "Plaque_Danger")
    _side_lights(p, 1.30, TRL_DECK - 0.25, front, rear)
    # Collecteur de vidange : tuyau longitudinal, vannes papillon rouges.
    for sx in (-1, 1):
        p.cyl((sx * 1.10, -7.0, TRL_DECK - 0.45), 0.08, 7.4, "Aluminium", axis="Y", seg=12)
        for y in (-3.8, -6.0, -8.2, -10.3):
            p.cyl((sx * 0.80, y, TRL_DECK - 0.15), 0.07, 0.6, "Aluminium", seg=10)
            p.cyl((sx * 1.10, y, TRL_DECK - 0.45), 0.13, 0.10, "Aimant_Rouge", axis="Y", seg=12)
            p.box((sx * 1.10, y, TRL_DECK - 0.28), (0.04, 0.04, 0.22), "Aimant_Rouge")
    rivets(p, r * 0.99, zc, front - 0.4, rear + 0.4, step=0.35, m="Chrome")
    obs.append(p.finish(root))
    obs += [empty("Socket_Arriere", (0, rear - 0.2, top + 0.15), root),
            empty("Socket_Conteneur", (0, rear - 0.5, TRL_DECK + 0.1), root)]
    return root, obs


def trailer_livestock(liv, number):
    root, obs = trailer_base(liv)
    p = Part("Remorque_Betaillere", KINGPIN)
    front, rear = 0.30, -15.70
    W, z0, z1 = 3.0, TRL_DECK, 5.70
    L = front - rear
    cy = (front + rear) / 2
    # Interieur sombre (vu entre les ridelles), plancher, etage, toit.
    p.box((0, cy, (z0 + z1) / 2), (W - 0.12, L - 0.1, z1 - z0 - 0.05), "Plastique_Interieur")
    p.box((0, cy, z0 + 0.06), (W, L, 0.14), "Chassis")
    p.box((0, cy, z1), (W + 0.04, L + 0.04, 0.12), "Aluminium", bevel=0.04)
    # Nez arrondi et porte arriere peints.
    p.box((0, front - 0.06, (z0 + z1) / 2), (W, 0.14, z1 - z0), liv["box"], bevel=0.05)
    p.box((0, rear + 0.06, (z0 + z1) / 2), (W, 0.14, z1 - z0), liv["box"], bevel=0.05)
    for sx in (-1, 1):
        p.box((sx * 0.75, rear - 0.02, (z0 + z1) / 2), (0.03, 0.03, z1 - z0 - 0.2), "Joint_Porte")
        p.box((sx * 0.40, rear - 0.04, z0 + 1.0), (0.30, 0.05, 0.05), "Aluminium")
    # Ridelles : lattes horizontales avec jours d'aeration.
    n = 8
    h = (z1 - z0) / n
    for k in range(n):
        z = z0 + h * (k + 0.5)
        if k in (3, 6):
            continue  # jours d'aeration (on voit l'interieur sombre)
        m = liv["box"] if k not in (1, 5) else liv["stripe"]
        for sx in (-1, 1):
            p.box((sx * (W / 2), cy, z), (0.06, L - 0.1, h * 0.84), m)
    # Poteaux.
    for i in range(11):
        y = front - 0.1 - (L - 0.2) * i / 10
        for sx in (-1, 1):
            p.box((sx * (W / 2 + 0.04), y, (z0 + z1) / 2), (0.06, 0.10, z1 - z0), "Aluminium")
    # Tetes de vaches stylisees qui depassent des jours d'aeration (formes
    # simples, pas de personnage existant).
    for k, y in enumerate((-2.5, -6.5, -10.5)):
        sx = -1 if k % 2 else 1
        zc = z0 + h * 3.5
        x = sx * (W / 2 + 0.12)
        p.box((x, y, zc), (0.36, 0.55, 0.40), "Texte_Blanc", bevel=0.10, seg=2)
        p.box((x + sx * 0.05, y, zc - 0.12), (0.30, 0.40, 0.22), "Peluche_Rose", bevel=0.08)
        p.box((x - sx * 0.06, y + 0.12, zc + 0.10), (0.20, 0.18, 0.12), "Danger_Noir", bevel=0.04)
        for sy in (-1, 1):
            p.cyl((x - sx * 0.05, y + sy * 0.30, zc + 0.20), 0.04, 0.18, "Plaque_Fond", axis="Y", seg=6)
            p.sphere((x + sx * 0.12, y + sy * 0.14, zc + 0.08), 0.045, "Oeil", seg=8, rings=5)
    _side_lights(p, W / 2 + 0.08, z0 - 0.1, front, rear)
    _spoiler(p, liv, rear, z1, width=W)
    obs.append(p.finish(root))
    obs += [empty("Socket_Arriere", (0, rear - 0.1, z1 + 0.1), root),
            empty("Socket_Conteneur", (0, rear - 0.4, z0 + 0.15), root)]
    return root, obs


def trailer_container(liv, number, container_color="Turquoise"):
    """Plateau + conteneur dont les portes arriere s'ouvrent (largage)."""
    root, obs = trailer_base(liv)
    front, rear = 0.30, -15.70
    p = Part("Remorque_Plateau", KINGPIN)
    p.box((0, (front + rear) / 2, TRL_DECK + 0.05), (3.0, front - rear, 0.14), "Bois")
    for sx in (-1, 1):
        p.box((sx * 1.50, (front + rear) / 2, TRL_DECK - 0.02), (0.08, front - rear, 0.22), liv["cab"])
    _side_lights(p, 1.56, TRL_DECK - 0.05, front, rear)
    obs.append(p.finish(root))

    cm = "Conteneur_" + container_color
    W, H = 2.95, 3.15
    c_front, c_rear = 0.10, -15.20
    z0 = TRL_DECK + 0.12
    cy = (c_front + c_rear) / 2
    L = c_front - c_rear
    c = Part("Conteneur", (0, cy, z0))
    c.box((0, cy, z0 + H / 2), (W, L, H), cm)
    c.box((0, cy, z0 + H / 2), (W - 0.2, L - 0.1, H - 0.2), "Plastique_Interieur")
    # Nervures (tole ondulee) sur les flancs et le toit.
    ribs = 22
    for i in range(ribs):
        y = c_front - 0.5 - (L - 1.0) * i / (ribs - 1)
        for sx in (-1, 1):
            c.box((sx * (W / 2 + 0.02), y, z0 + H / 2), (0.04, 0.22, H - 0.30), cm)
    for sx in (-1, 1):
        for sy, y in ((1, c_front), (-1, c_rear)):
            for z in (z0 + 0.08, z0 + H - 0.08):
                c.box((sx * (W / 2 - 0.08), y - sy * 0.08, z), (0.20, 0.20, 0.18), "Chassis")
        c.box((sx * (W / 2), cy, z0 + H - 0.05), (0.08, L, 0.12), "Chassis")
        c.box((sx * (W / 2), cy, z0 + 0.05), (0.08, L, 0.12), "Chassis")
    c.box((0, c_front - 0.02, z0 + H / 2), (W, 0.06, H), cm)
    rivets(c, W / 2 + 0.06, z0 + 0.12, c_front - 0.1, c_rear + 0.1, step=0.30, m="Chassis")
    rivets(c, W / 2 + 0.06, z0 + H - 0.12, c_front - 0.1, c_rear + 0.1, step=0.30, m="Chassis")
    for k in range(5):
        c.box((-1.0 + 0.5 * k, c_front + 0.02, z0 + H / 2), (0.12, 0.04, H - 0.3), cm)
    con = c.finish(root)
    obs.append(con)
    # Portes : pivot sur la charniere exterieure (x = +-W/2), ouverture en lacet.
    for side, sx in (("G", -1), ("D", 1)):
        hinge = (sx * (W / 2), c_rear, z0 + H / 2)
        d = Part("Conteneur_Porte_" + side, hinge)
        d.box((sx * W / 4, c_rear - 0.04, z0 + H / 2), (W / 2 - 0.02, 0.06, H - 0.12), cm)
        for k in range(3):
            d.box((sx * (W / 4), c_rear - 0.09, z0 + 0.6 + k * 1.0), (W / 2 - 0.25, 0.04, 0.10), cm)
        for xo in (0.25, 0.60):
            d.cyl((sx * (W / 2 - xo), c_rear - 0.12, z0 + H / 2), 0.03, H - 0.25, "Aluminium", seg=6)
            d.box((sx * (W / 2 - xo), c_rear - 0.16, z0 + 1.2), (0.06, 0.08, 0.25), "Aluminium")
        obs.append(d.finish(con))
    a = Part("Remorque_Aileron", KINGPIN)
    _spoiler(a, liv, c_rear - 0.2, z0 + H, width=W)
    obs.append(a.finish(root))
    obs += [empty("Socket_Arriere", (0, c_rear - 0.1, z0 + H + 0.1), root),
            empty("Socket_Conteneur", (0, c_rear + 0.6, z0 + 0.1), root)]
    return root, obs


def trailer_car_carrier(liv, number, car_builder):
    """Porte-voitures deux etages, charge de voitures detachables."""
    root, obs = trailer_base(liv, skirts=False)
    front, rear = 0.30, -15.70
    low, up = 1.30, 3.70
    p = Part("Remorque_Porte_Voitures", KINGPIN)
    # Col de cygne sur la sellette, puis plancher bas entre col et essieux.
    p.box((0, -1.0, TRL_DECK + 0.05), (2.9, 2.6, 0.16), liv["cab"])
    p.box((0, -2.55, (low + TRL_DECK) / 2), (2.9, 0.30, TRL_DECK - low + 0.2), liv["cab"], rot=(-25, 0, 0))
    for sx in (-1, 1):
        p.box((sx * 1.15, (-2.8 + TRL_AXLES[0] + 0.9) / 2, low - 0.08),
              (0.55, abs(-2.8 - TRL_AXLES[0] - 0.9), 0.10), "Aluminium")
        p.box((sx * 1.15, (TRL_AXLES[0] + 0.9 + rear) / 2, TRL_DECK - 0.05),
              (0.55, abs(TRL_AXLES[0] + 0.9 - rear), 0.10), "Aluminium")
        # Etage superieur : deux chemins de roulement.
        p.box((sx * 1.15, (front + rear) / 2 - 0.3, up), (0.55, front - rear - 0.6, 0.10), "Aluminium")
        p.box((sx * 1.45, (front + rear) / 2 - 0.3, up - 0.10), (0.08, front - rear - 0.6, 0.30), liv["cab"])
        # Poteaux.
        for y in (0.0, -2.6, -5.4, -8.2, -11.0, -13.8, -15.5):
            zb = TRL_DECK - 0.1 if (y > -2.0 or y < TRL_AXLES[0] + 0.9) else low - 0.1
            p.box((sx * 1.45, y, (zb + up) / 2), (0.10, 0.12, up - zb), liv["cab"])
        p.box((sx * 1.45, (front + rear) / 2, low - 0.25), (0.10, front - rear, 0.25), "Chassis")
    for y in (-0.8, -4.0, -7.0, -10.0, -13.0):
        p.box((0, y, up - 0.04), (2.9, 0.10, 0.10), "Chassis")
    # Rampes arriere relevees.
    for sx in (-1, 1):
        p.box((sx * 1.15, rear - 0.35, up - 0.35), (0.5, 0.08, 0.9), "Aluminium", rot=(20, 0, 0))
    _side_lights(p, 1.52, low - 0.2, front, rear)
    obs.append(p.finish(root))
    # Voitures chargees : objets separes (detachables en jeu).
    slots = [(-6.0, low), (-10.5, low), (-1.6, up + 0.05), (-6.4, up + 0.05), (-11.2, up + 0.05)]
    colors = ["Rouge", "Blanc", "Jaune", "Bleu", "Vert"]
    for k, ((y, z), col) in enumerate(zip(slots, colors), start=1):
        car = car_builder("Voiture_Chargee_%d" % k, col, (0, y, z), lod=True)
        car.parent = root
        car.location = car.location - root.matrix_world.translation
        obs.append(car)
    obs += [empty("Socket_Arriere", (0, rear - 0.1, up + 0.3), root),
            empty("Socket_Conteneur", (0, rear - 0.3, up + 0.1), root)]
    return root, obs


# ---------------------------------------------------------------------------
# Porteurs (sans remorque)
# ---------------------------------------------------------------------------

def crane_body(liv):
    """Plateau, grue telescopique (tourelle / fleche / crochet), stabilisateurs."""
    obs = []
    p = Part("Porteur_Plateau")
    p.box((0, -1.40, 1.24), (2.70, 4.20, 0.06), "Chassis")
    for k in range(13):
        p.box((-1.26 + 0.21 * k, -1.40, 1.31), (0.19, 4.16, 0.08), "Bois", bevel=0.015)
    rivets_z = 1.36
    for k in range(13):
        for y in (0.6, -1.4, -3.4):
            p.cyl((-1.26 + 0.21 * k, y, rivets_z), 0.018, 0.02, "Acier_Sellette", seg=2)
    for sx in (-1, 1):
        p.box((sx * 1.36, -1.40, 1.45), (0.06, 4.20, 0.30), liv["cab"])
        # Stabilisateurs deployables (rentres).
        for y in (0.45, -3.25):
            p.box((sx * 1.25, y, 0.95), (0.60, 0.30, 0.30), "Chassis")
            kit.hazard_stripes(p, (sx * 1.58, y, 0.95), (0.06, 0.30, 0.30), 4, axis="Z")
            p.cyl((sx * 1.50, y, 0.62), 0.09, 0.45, "Danger_Jaune", seg=12)
            p.cyl((sx * 1.50, y, 0.32), 0.06, 0.40, "Chrome", seg=12)
            p.cyl((sx * 1.50, y, 0.10), 0.24, 0.06, "Acier_Sellette", seg=16)
            p.cyl((sx * 1.50, y, 0.16), 0.06, 0.08, "Chassis", seg=10)
            for k in range(4):
                p.box((sx * 1.50, y, 0.05), (0.42, 0.04, 0.02), "Chassis", rot=(0, 0, 45 * k))
    p.box((0, -3.30, 1.80), (2.2, 0.4, 0.9), "Chassis", bevel=0.05)  # contrepoids
    kit.hazard_stripes(p, (0, -3.52, 1.80), (2.2, 0.04, 0.5), 8, axis="X")
    # Charge decorative : poutrelles.
    for k in range(3):
        p.box((-0.6 + 0.6 * k, -1.95, 1.55), (0.25, 2.0, 0.35), "Danger_Jaune")
    obs.append(p.finish())
    pivot = (0, -0.05, 1.40)
    t = Part("Grue_Tourelle", pivot)
    t.cyl((0, -0.05, 1.55), 0.75, 0.30, "Chassis", seg=18)
    t.box((0, -0.15, 2.15), (1.10, 1.20, 1.00), liv["cab"], bevel=0.10, seg=2)
    t.box((0.56, 0.10, 2.30), (0.02, 0.45, 0.45), "Plastique_Interieur")
    t.box((0.575, 0.10, 2.30), (0.01, 0.45, 0.45), "Vitre")
    kit.hazard_stripes(t, (0, -0.76, 2.15), (1.0, 0.02, 0.5), 6, axis="X")
    tour = t.finish()
    obs.append(tour)
    # Fleche au repos, couchee vers l'avant au-dessus de la cabine.
    fp = (0, -0.30, 2.55)
    f = Part("Grue_Fleche", fp)
    f.box((0, -0.30, 2.55), (0.55, 0.70, 0.55), liv["cab"], bevel=0.08)
    f.box((0, 1.60, 4.20), (0.50, 3.90, 0.42), liv["cab"], bevel=0.06)
    # Sections telescopiques, patins, flexibles hydrauliques le long de la fleche.
    for k, y in enumerate((0.5, 1.6, 2.7)):
        f.lathe((0, 0, 4.20), [(0.31, y + 0.04), (0.31, y - 0.04), (0.27, y - 0.04), (0.27, y + 0.04)],
                "Chassis", axis="Y", seg=8, closed=True)
    for sx in (-1, 1):
        f.cyl((sx * 0.28, 1.6, 4.05), 0.025, 3.6, "Plastique_Noir", axis="Y", seg=6)
        f.cyl((sx * 0.28, 1.6, 4.35), 0.02, 3.6, "Plastique_Noir", axis="Y", seg=6)
        for y in (0.2, 1.0, 1.8, 2.6, 3.3):
            f.box((sx * 0.27, y, 4.20), (0.04, 0.06, 0.40), "Acier_Sellette")
    for k in range(5):
        f.box((0, 3.30 + 0.24 * k, 4.42), (0.30, 0.10, 0.03), "Danger_Noir")
    f.cyl((0, 4.40, 4.42), 0.12, 0.10, "Chrome", axis="X", seg=14)   # poulie
    f.box((0, 3.80, 4.20), (0.40, 1.20, 0.34), "Danger_Jaune", bevel=0.04)
    f.box((0, 4.40, 4.20), (0.32, 0.30, 0.28), "Chassis")
    f.cyl((0, 0.45, 3.25), 0.11, 1.80, "Chrome", seg=10, rot=(-55, 0, 0))
    # Bras vertical qui porte la fleche horizontale au-dessus de la cabine.
    f.box((0, -0.30, 3.35), (0.36, 0.45, 1.75), liv["cab"], bevel=0.05)
    fl = f.finish(tour)
    obs.append(fl)
    h = Part("Grue_Crochet", (0, 4.40, 4.00))
    h.cyl((0, 4.40, 3.65), 0.02, 0.70, "Chassis", seg=6)
    h.box((0, 4.40, 3.25), (0.30, 0.18, 0.30), "Danger_Jaune", bevel=0.05)
    h.lathe((0, 4.40, 3.0), [(0.10, 0.0), (0.04, -0.15), (0.0, -0.20)], "Chrome", seg=8)
    obs.append(h.finish(fl))
    return obs


def plow_body(liv):
    obs = []
    p = Part("Porteur_Saleuse")
    # Tremie a sel (pyramide tronquee) et disque d'epandage.
    p.hull([(sx * w, y, z) for sx in (-1, 1)
            for (w, y, z) in ((0.55, 0.25, 1.30), (0.55, -3.0, 1.30),
                              (1.32, 0.55, 3.35), (1.32, -3.30, 3.35))],
           liv["box"])
    p.box((0, -1.40, 3.40), (2.70, 3.95, 0.10), "Chassis")
    for k in range(7):
        y = 0.40 - 3.60 * k / 6
        for sx in (-1, 1):
            p.box((sx * 0.97, y, 2.35), (0.06, 0.08, 2.1), liv["box"], rot=(0, sx * -21, 0))
        p.cyl((0, y, 3.48), 0.03, 2.6, "Danger_Jaune", axis="X", seg=8)
    for sx in (-1, 1):
        p.cyl((sx * 0.55, -3.37, 2.30), 0.025, 2.0, "Aluminium", seg=8)
    for k in range(6):
        p.cyl((0, -3.37, 1.45 + 0.32 * k), 0.02, 1.1, "Aluminium", axis="X", seg=8)
    p.box((0, -3.62, 0.70), (1.0, 0.08, 0.30), "Chassis", bevel=0.02)       # vis d'Archimede
    p.cyl((0, -1.6, 1.20), 0.14, 3.6, "Acier_Sellette", axis="Y", seg=14)
    # Projecteurs de travail a l'arriere de la tremie, goulotte d'epandage.
    for sx in (-1, 1):
        p.box((sx * 1.10, -3.30, 3.62), (0.30, 0.16, 0.22), "Plastique_Noir", bevel=0.04)
        p.cyl((sx * 1.10, -3.39, 3.62), 0.08, 0.03, "Phare", axis="Y", seg=14)
        p.box((sx * 1.10, -3.30, 3.48), (0.06, 0.06, 0.12), "Chassis")
    p.hull([(sx * w, y, z) for sx in (-1, 1)
            for (w, y, z) in ((0.25, -3.30, 1.35), (0.30, -3.60, 1.10), (0.10, -3.55, 1.40),
                              (0.12, -3.62, 1.12))], "Acier_Sellette", smooth=True)
    kit.hazard_stripes(p, (0, -3.36, 2.70), (2.6, 0.04, 0.35), 10, axis="X")
    p.cyl((0, -3.55, 0.95), 0.45, 0.06, "Aluminium", seg=16)
    for k in range(4):
        p.box((0, -3.55, 1.00), (0.80, 0.06, 0.08), "Chassis", rot=(0, 0, 45 * k))
    p.box((0, -3.40, 1.25), (0.16, 0.16, 0.5), "Chassis")
    for sx in (-1, 1):
        p.box((sx * 1.33, -1.4, 2.35), (0.02, 3.4, 0.25), liv["stripe"])
    # Gyrophares orange sur le toit de la cabine.
    for sx in (-1, 1):
        p.cyl((sx * 0.85, FRONT_Y - 1.0, CAB_TOP + 0.14), 0.15, 0.22, "Gyrophare_Orange", seg=12)
        p.cyl((sx * 0.85, FRONT_Y - 1.0, CAB_TOP + 0.03), 0.18, 0.06, "Plastique_Noir", seg=12)
    obs.append(p.finish())
    # Lame chasse-neige : profil en C ouvert vers l'avant, pivot a l'attache
    # (pour la lever / l'orienter).
    F = FRONT_Y
    piv = (0, F + 0.35, 0.95)
    b = Part("Lame_Neige", piv)
    b.arc((0, F + 1.75, 1.00), 1.00, 1.10, 3.80, 128, 236, liv["box"], axis="X", seg=12)
    b.box((0, F + 1.18, 0.20), (3.80, 0.14, 0.18), "Caoutchouc")
    for k in range(19):
        b.cyl((-1.80 + 0.20 * k, F + 1.25, 0.23), 0.022, 0.03, "Chrome", axis="Y", seg=2)
    for k in range(9):
        # Raidisseurs courbes au dos de la lame.
        b.arc((-1.6 + 0.4 * k, F + 1.75, 1.00), 1.10, 1.22, 0.06, 132, 232, "Chassis", axis="X", seg=10)
    for sx in (-1, 1):
        # Verins d'orientation et feux de gabarit de lame.
        b.cyl((sx * 1.05, F + 0.55, 1.05), 0.08, 0.75, "Danger_Jaune", axis="Y", seg=12, rot=(0, 0, sx * 35))
        b.cyl((sx * 1.15, F + 0.60, 1.05), 0.045, 0.80, "Chrome", axis="Y", seg=10, rot=(0, 0, sx * 35))
        b.sphere((sx * 1.93, F + 1.10, 2.52), 0.07, "Clignotant", seg=10, rings=6)
    kit.hazard_stripes(b, (0, F + 1.08, 1.80), (3.80, 0.10, 0.12), 12, axis="X")
    for sx in (-1, 1):
        b.box((sx * 1.93, F + 0.98, 1.0), (0.06, 0.50, 1.60), "Chassis")
        b.cyl((sx * 1.93, F + 1.10, 2.15), 0.03, 0.70, "Danger_Jaune", seg=6)
        b.box((sx * 0.55, F + 0.55, 0.95), (0.16, 0.50, 0.16), "Chassis")
        b.cyl((sx * 0.55, F + 0.50, 1.15), 0.06, 0.6, "Chrome", axis="Y", seg=8, rot=(25, 0, 0))
    obs.append(b.finish())
    return obs


def fire_body(liv):
    obs = []
    p = Part("Porteur_Pompier")
    y0, y1 = CAB_REAR - 0.10, -3.95
    z0, z1 = 1.10, 3.45
    cy, L = (y0 + y1) / 2, y0 - y1
    p.box((0, cy, (z0 + z1) / 2), (2.70, L, z1 - z0), liv["cab"], bevel=0.10, seg=2)
    # Rideaux de coffres (aluminium nervure) des deux cotes.
    for sx in (-1, 1):
        for k in range(3):
            yc = y0 - 0.25 - (L - 0.5) * (k + 0.5) / 3
            p.box((sx * 1.355, yc, 2.30), (0.02, L / 3 - 0.25, 1.70), "Aluminium")
            for j in range(6):
                p.box((sx * 1.37, yc, 1.60 + 0.28 * j), (0.02, L / 3 - 0.25, 0.03), "Chassis")
        p.box((sx * 1.36, cy, 1.25), (0.02, L, 0.16), "Texte_Blanc")
        p.box((sx * 1.36, cy, 3.30), (0.02, L, 0.10), "Texte_Blanc")
    # Plateforme de toit, devidoir, lance a eau.
    p.box((0, cy, z1 + 0.05), (2.5, L, 0.08), "Aluminium")
    for sx in (-1, 1):
        # Devidoir de tuyau a l'arriere, tuyau enroule (anneaux).
        p.cyl((sx * 0.75, y1 - 0.25, 2.40), 0.42, 0.06, "Aimant_Rouge", axis="X", seg=16,
              rot=(0, 0, 0))
        for k in range(7):
            p.lathe((sx * 0.75 + (k - 3) * 0.06, y1 - 0.25, 2.40),
                    [(0.36, 0.025), (0.36, -0.025), (0.24, -0.025), (0.24, 0.025)],
                    "Texte_Blanc" if k % 2 else "Creme_Tuyau", axis="X", seg=14, closed=True)
        p.cyl((sx * 0.75, y1 - 0.25, 2.40), 0.10, 0.50, "Chrome", axis="X", seg=12)
        # Rambarde de toit.
        p.cyl((sx * 1.25, cy, z1 + 0.40), 0.03, L - 0.3, "Chrome", axis="Y", seg=8)
        for y in (y0 - 0.2, cy, y1 + 0.2):
            p.cyl((sx * 1.25, y, z1 + 0.22), 0.025, 0.36, "Chrome", seg=8)
        # Poignees de rideaux et feux de flanc.
        for k in range(3):
            yc = y0 - 0.25 - (L - 0.5) * (k + 0.5) / 3
            p.box((sx * 1.39, yc, 1.55), (0.04, 0.35, 0.05), "Chrome", bevel=0.01)
            p.box((sx * 1.37, yc, 3.20), (0.02, 0.18, 0.08), "Gyrophare_Bleu")
    # Equipements de toit : echelle a coulisse rangee, caisses, lance a eau.
    for k in range(3):
        p.box((-0.55 + 0.55 * k, -0.6, z1 + 0.22), (0.45, 0.70, 0.28), "Aluminium", bevel=0.03)
    p.cyl((0.0, y0 - 0.25, z1 + 0.35), 0.10, 0.30, "Chrome", seg=12)
    p.cyl((0.0, y0 - 0.05, z1 + 0.52), 0.06, 0.50, "Laiton", axis="Y", seg=10, rot=(-12, 0, 0))
    p.box((0, y1 - 0.02, (z0 + z1) / 2), (2.6, 0.04, z1 - z0 - 0.2), "Aluminium")
    for sx in (-1, 1):
        p.box((sx * 0.9, y1 - 0.04, z1 - 0.2), (0.25, 0.05, 0.15), "Gyrophare_Bleu")
    # Rampe de gyrophares bleus sur la cabine.
    p.box((0, FRONT_Y - 0.60, CAB_TOP + 0.10), (2.2, 0.32, 0.12), "Plastique_Noir", bevel=0.03)
    for sx in (-1, 1):
        p.box((sx * 0.75, FRONT_Y - 0.60, CAB_TOP + 0.22), (0.55, 0.28, 0.14), "Gyrophare_Bleu", bevel=0.05)
    p.box((0, FRONT_Y - 0.60, CAB_TOP + 0.22), (0.5, 0.28, 0.14), "Phare", bevel=0.05)
    p.cyl((0, FRONT_Y - 1.20, CAB_TOP + 0.15), 0.10, 0.25, "Chrome", seg=10)
    p.cyl((0, FRONT_Y - 1.05, CAB_TOP + 0.30), 0.06, 0.45, "Chrome", axis="Y", seg=8, rot=(-15, 0, 0))
    obs.append(p.finish())
    # Echelle : tourelle (lacet) + echelle (tangage), couchee vers l'avant.
    tp = (0, -3.20, z1 + 0.10)
    t = Part("Echelle_Tourelle", tp)
    t.cyl((0, -3.20, z1 + 0.20), 0.65, 0.20, "Chassis", seg=18)
    t.box((0, -3.20, z1 + 0.50), (0.9, 0.9, 0.45), "Aluminium", bevel=0.06)
    tour = t.finish()
    obs.append(tour)
    ep = (0, -3.20, z1 + 0.75)
    e = Part("Echelle", ep)
    length = 7.2
    y_front = -3.20 + length - 0.6
    for sx in (-1, 1):
        e.box((sx * 0.45, -3.20 + length / 2 - 0.6, z1 + 0.80), (0.08, length, 0.18), "Aluminium")
        e.box((sx * 0.45, -3.20 + length / 2 - 0.6, z1 + 1.00), (0.05, length, 0.05), "Aluminium")
    for k in range(26):
        y = -3.40 + (length - 0.2) * k / 25
        e.cyl((0, y, z1 + 0.88), 0.022, 0.84, "Aluminium", axis="X", seg=8)
    for sx in (-1, 1):
        for k in range(10):
            y = -3.30 + (length - 0.4) * k / 9
            e.box((sx * 0.45, y, z1 + 0.90), (0.03, 0.03, 0.22), "Aluminium", rot=(30 if k % 2 else -30, 0, 0))
    e.box((0, y_front, z1 + 0.85), (1.1, 0.30, 0.30), liv["cab"], bevel=0.05)
    obs.append(e.finish(tour))
    return obs


def tractor_rigid(liv, number, style="flat"):
    """Tracteur sans sellette : base des porteurs."""
    return tractor(liv, number, style=style, fifth_wheel=False)


# ---------------------------------------------------------------------------
# Chariot elevateur
# ---------------------------------------------------------------------------

FORK_WHEELS = {
    "Wheel_FL": (-0.62, 0.85, 0.40, -1),
    "Wheel_FR": (0.62, 0.85, 0.40, 1),
    "Wheel_RL": (-0.58, -0.80, 0.32, -1),
    "Wheel_RR": (0.58, -0.80, 0.32, 1),
}


def forklift(liv):
    """Chariot elevateur (avant = fourches en +Y). Hors gabarit camion : ses
    cotes ne relevent pas de VEHICLE_SPEC (engin de decor ou d'obstacle)."""
    obs = []
    p = Part("Body")
    # Chassis et contrepoids arrondi.
    p.box((0, 0.10, 0.70), (1.30, 2.10, 0.70), liv["cab"], bevel=0.10, seg=2)
    p.hull([(sx * 0.68, y, z) for sx in (-1, 1)
            for (y, z) in ((-0.70, 0.40), (-1.35, 0.55), (-1.35, 1.45), (-0.70, 1.65), (-0.40, 1.65), (-0.40, 0.40))],
           liv["cab"], smooth=True)
    p.box((0, -1.37, 0.95), (1.10, 0.05, 0.25), "Chassis")
    for sx in (-1, 1):
        p.box((sx * 0.45, -1.38, 1.30), (0.18, 0.04, 0.10), "Feu_Arriere")
        p.arc((sx * 0.62, 0.85, 0.40), 0.44, 0.50, 0.30, 0, 180, "Plastique_Noir", seg=8)
    # Siege, volant, protege-conducteur.
    p.box((0, -0.35, 1.25), (0.60, 0.55, 0.12), "Plastique_Noir", bevel=0.04)
    p.box((0, -0.60, 1.55), (0.60, 0.12, 0.55), "Plastique_Noir", bevel=0.04)
    p.box((0, 0.55, 1.30), (0.80, 0.50, 0.40), liv["cab"], bevel=0.06)
    p.cyl((0, 0.40, 1.65), 0.04, 0.4, "Chassis", seg=6, rot=(-30, 0, 0))
    p.lathe((0, 0.30, 1.85), [(0.20, 0.02), (0.20, -0.02), (0.16, -0.02), (0.16, 0.02)],
            "Plastique_Noir", seg=14, closed=True, rot=(-30, 0, 0))
    for sx in (-1, 1):
        for y in (0.75, -0.75):
            p.box((sx * 0.58, y, 1.70), (0.07, 0.07, 1.30), "Chassis")
    p.box((0, 0.0, 2.38), (1.24, 1.60, 0.07), "Chassis")
    for k in range(5):
        p.box((0, -0.6 + 0.3 * k, 2.42), (1.20, 0.05, 0.04), "Chassis")
    p.box((0, -0.75, 2.48), (0.30, 0.15, 0.10), "Gyrophare_Orange", bevel=0.04)
    for sx in (-1, 1):
        p.box((sx * 0.40, 0.75, 2.30), (0.18, 0.06, 0.12), "Phare")
    p.box((0, 0.10, 0.45), (1.0, 2.0, 0.1), "Chassis")
    # Bouteille de gaz couchee sur le contrepoids, avec ses sangles.
    p.lathe((0, -1.05, 1.95), [(0.0, -0.62), (0.16, -0.58), (0.20, -0.48), (0.20, 0.48),
                               (0.16, 0.58), (0.0, 0.62)], "Texte_Blanc", axis="X", seg=16)
    for x in (-0.30, 0.30):
        p.lathe((x, -1.05, 1.95), [(0.215, 0.03), (0.215, -0.03), (0.19, -0.03), (0.19, 0.03)],
                "Chassis", axis="X", seg=16, closed=True)
    p.cyl((0.66, -1.05, 1.95), 0.05, 0.10, "Laiton", axis="X", seg=10)
    p.box((0, -1.05, 1.70), (0.70, 0.30, 0.06), "Chassis")
    # Grille du contrepoids, marchepied, tableau de bord, pedales.
    for k in range(6):
        p.box((-0.40 + 0.16 * k, -1.36, 1.15), (0.06, 0.03, 0.30), "Plastique_Noir")
    for sx in (-1, 1):
        p.box((sx * 0.68, 0.30, 0.55), (0.12, 0.45, 0.04), "Aluminium", bevel=0.01)
    p.box((0, 0.78, 1.55), (0.70, 0.18, 0.12), "Plastique_Noir", bevel=0.03)
    for x in (-0.15, 0.0, 0.15):
        p.cyl((x, 0.86, 1.56), 0.03, 0.02, "Phare" if x else "Neon_Rouge", axis="Y", seg=8)
    for x in (-0.12, 0.12):
        p.box((x, 0.55, 1.12), (0.08, 0.14, 0.03), "Aluminium", rot=(-30, 0, 0))
    # Leviers hydrauliques.
    for k in range(3):
        p.cyl((0.30 + 0.06 * k, 0.70, 1.75), 0.012, 0.30, "Chassis", seg=6, rot=(-15, 0, 0))
        p.sphere((0.30 + 0.06 * k, 0.74, 1.90), 0.025, "Aimant_Rouge", seg=6, rings=4)
    body = p.finish()
    obs.append(body)
    # Mat (inclinaison) et tablier + fourches (levee) : objets separes.
    mp = (0, 1.25, 0.40)
    m = Part("Mat", mp)
    for sx in (-1, 1):
        m.box((sx * 0.38, 1.25, 1.60), (0.10, 0.14, 2.60), "Chassis")
        m.box((sx * 0.28, 1.30, 1.75), (0.08, 0.10, 2.70), "Chassis")
    m.box((0, 1.25, 2.90), (0.90, 0.14, 0.10), "Chassis")
    m.box((0, 1.25, 0.35), (0.90, 0.14, 0.10), "Chassis")
    m.cyl((0, 1.18, 1.40), 0.06, 2.0, "Chrome", seg=8)
    m.cyl((0, 1.18, 0.55), 0.10, 0.40, "Chassis", seg=10)
    # Chaines de levage (maillons) et flexibles.
    for sx in (-1, 1):
        for k in range(30):
            m.box((sx * 0.16, 1.32, 0.50 + 0.08 * k), (0.04, 0.025 if k % 2 else 0.05, 0.07), "Acier_Sellette")
        m.cyl((sx * 0.08, 1.12, 1.6), 0.018, 2.4, "Plastique_Noir", seg=6)
        m.cyl((sx * 0.16, 1.32, 2.85), 0.06, 0.05, "Chrome", axis="X", seg=10)
    mast = m.finish(body)
    obs.append(mast)
    fp = (0, 1.42, 0.25)
    f = Part("Fourche", fp)
    f.box((0, 1.40, 0.75), (1.00, 0.08, 0.90), "Danger_Jaune")
    for k in range(4):
        f.box((0, 1.38, 0.45 + 0.2 * k), (1.00, 0.04, 0.03), "Chassis")
    for sx in (-1, 1):
        f.box((sx * 0.30, 1.47, 0.70), (0.12, 0.06, 1.00), "Chassis")
        f.box((sx * 0.30, 2.05, 0.24), (0.12, 1.20, 0.05), "Chassis")
    obs.append(f.finish(mast))
    obs += make_wheels(layout=FORK_WHEELS, w=0.30, twin_rear=False)
    obs += [empty("Socket_Toit", (0, 0.0, 2.45), body),
            empty("Socket_Avant", (0, 2.65, 0.30), body),
            empty("Socket_Lateral_G", (-0.75, 0.0, 0.70), body),
            empty("Socket_Lateral_D", (0.75, 0.0, 0.70), body),
            empty("Socket_Arriere", (0, -1.40, 1.50), body)]
    return obs
