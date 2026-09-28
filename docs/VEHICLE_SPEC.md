# VEHICLE_SPEC.md — Le camion : dimensions, masse, roues, noms

**Ce fichier est un contrat** entre trois chaînes d'outils :

- `game/vehicles/` (la physique) ;
- `tools/blender/` (le modèle 3D) ;
- `game/tracks/` (les pistes, dimensionnées d'après le camion).

**Personne ne le possède.** Un agent qui a besoin d'un changement le demande,
avec une justification chiffrée ; la modification et la resynchronisation des
trois côtés se font dans le même commit, décidé par l'utilisateur
(`CLAUDE.md` §8).

Les valeurs ci-dessous sont des **points de départ**. Le spike V1 et les tests
de la phase 1 peuvent en invalider certaines : c'est alors ce fichier qu'on
corrige, pas le code qu'on contourne.

---

## 1. Repère et échelle

- 1 unité Godot = 1 mètre. Blender exporte avec `scale = 1.0`, transforms
  appliquées (validé au millimètre, cf. `docs/SPIKE.md`, acquis A6).
- **Origine du camion** : au sol, au milieu de l'empattement et de la voie, le
  camion étant au repos sur ses roues.
- **Avant vers −Z**, haut vers +Y, droite vers +X (convention Godot).

## 2. Gabarit

**Tracteur à deux essieux + semi-remorque de course avec aileron** : c'est
l'identité visuelle du jeu (décision du 2026-09-28, modèles de l'équipe). La
semi-remorque est **rigide**, portée par le même corps que le tracteur (§5 bis) :
pas d'articulation, pas de mise en portefeuille. Les cotes ci-dessous sont
celles du tracteur, sauf mention « ensemble ».

| Grandeur | Valeur |
|---|---|
| Longueur (tracteur) | 5,8 m |
| Longueur (ensemble) | **16,4 m** (de z = −2,9 à +13,5) |
| Largeur (tracteur / remorque) | 2,5 m / 3,0 m |
| Hauteur (cabine / remorque / aileron) | 3,2 m / 4,9 m / 5,8 m |
| Masse totale | **5 000 kg** |
| Empattement | 3,8 m (essieu avant z = −1,9 ; arrière z = +1,9) |
| Voie | 2,1 m (roues à x = ±1,05) |

## 3. Centre de masse

**(0 ; 0,80 ; −0,30)** dans le repère du camion.

Il est **volontairement plus bas** que celui d'un vrai camion (~1,3 m) : c'est
le premier levier de stabilité d'un jeu arcade. Un camion qui se retourne au
premier virage serré n'est pas « réaliste », il est injouable. Légèrement vers
l'avant (moteur), ce qui rend le camion plus stable qu'un train arrière
survireur.

Il se règle par `RigidBody3D.center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM`,
jamais en déplaçant les formes de collision.

## 4. Roues et suspension

Modèle confirmé par le spike V1 : `RigidBody3D` + rayons (`VehicleBody3D`
écarté). Les roues **ne sont pas des corps physiques**. Chaque roue est un rayon
(raycast) tiré vers le bas depuis un point d'ancrage sur le châssis ; la force
de suspension s'applique au châssis, au point d'ancrage. Les maillages de roues
sont purement visuels et suivent le rayon.

| Roue | Nom (contrat) | Ancrage (x ; y ; z) |
|---|---|---|
| Avant gauche | `Wheel_FL` | (−1,05 ; 1,00 ; −1,90) |
| Avant droite | `Wheel_FR` | (+1,05 ; 1,00 ; −1,90) |
| Arrière gauche | `Wheel_RL` | (−1,05 ; 1,00 ; +1,90) |
| Arrière droite | `Wheel_RR` | (+1,05 ; 1,00 ; +1,90) |

| Grandeur | Valeur |
|---|---|
| Rayon de roue | 0,55 m |
| Largeur de roue | 0,40 m |
| Débattement max (ancrage → moyeu) | 0,60 m |
| **Hauteur du moyeu au repos** | **0,55 m** (roue posée) |
| Longueur du rayon | débattement + rayon de roue = 1,15 m |

**La hauteur au repos est un contrat, la raideur est un réglage.** La longueur
libre du ressort se *déduit* des deux, **essieu par essieu** : changer la
raideur dans `VehicleTuning` ne doit jamais changer la hauteur de caisse au
repos.

Le centre de masse étant à z = −0,30 (§3), les essieux ne portent pas la même
charge. Charge statique d'une roue, avec `a` = 1,9 + 0,3 = 2,2 m (CdM → essieu
arrière) et `L` = 3,8 m (empattement) :

| Essieu | Part de la masse | Charge par roue |
|---|---|---|
| avant | a / L = **57,9 %** | 14 199 N |
| arrière | 1 − a / L = **42,1 %** | 10 326 N |

`longueur libre = 0,45 m (ancrage → moyeu au repos) + charge de la roue / k`.
Avec une longueur libre commune calculée sur M/4, le camion pique du nez
(avant −1,5 cm, arrière +1,5 cm, ~0,46°) : mesuré au spike V1. La raideur `k`
reste réglée en fréquence sur `m_roue` = M/4 (`vehicle-physics-engineer.md`) ;
la longueur libre ne l'est pas.

Validé au spike V1 (`docs/SPIKE.md`) : hauteur de caisse au repos à
+0,1 mm de la cote, tangage 0,0005°.

Rappel mesuré : Jolt laisse un corps au repos s'enfoncer de
`penetration_slop` = 0,02 m. Ça ne concerne pas les roues (des rayons), mais
bien le châssis s'il touche le sol.

## 5. Formes de collision

Trois boîtes convexes, **jamais le maillage** :

| Forme | Taille (x × y × z) | Centre (x ; y ; z) |
|---|---|---|
| Châssis | 2,4 × 1,00 × 5,8 | (0 ; 1,25 ; 0) |
| Cabine | 2,4 × 1,40 × 2,2 | (0 ; 2,45 ; −1,8) |
| Remorque | 3,0 × 3,10 × 13,0 | (0 ; 3,35 ; 6,9) |

La boîte de remorque couvre la caisse du modèle de l'équipe mis à l'échelle du
tracteur (arrière à 13,4 m, visuel à 13,46 m, vérifié par `truck_visual_test`).
Son bas est à 1,8 m : la queue ne talonne pas en dessous de ~9° de tangage. Les
roues et bavettes de la remorque (sous 1,8 m) sont purement visuelles.

Le bas du châssis est à y = 0,75 : garde au sol de 0,75 m au repos. C'est ce qui
permet de passer les bosses et de retomber d'un saut sur les roues plutôt que
sur le ventre.

Le corps du camion a **`continuous_cd = true`** (spike V2 : l'enfoncement dans
un mur à 200 km/h passe de 0,87 m à 0,10 m, sans coût mesurable).

## 5 bis. Semi-remorque rigide : inertie imposée

Laissée à Godot, l'inertie se déduit des formes : la boîte de remorque multiplie
l'inertie en lacet par 17 (16 450 → 285 873 kg·m²) et **tue le drift** (dérive au
frein à main 29° → 3,5° ; mesuré le 2026-09-28). Choix arcade : la remorque pèse
peu dans la dynamique. Masse (5 000 kg) et centre de masse (§3) restent ceux du
tracteur, et les **moments d'inertie sont imposés** par `VehicleTuning`
(`inertia_*_kgm2`, valeurs du tracteur seul : 19 989 / 16 450 / 8 338). La
remorque reste **pleinement physique pour les contacts** (murs, autres camions).
Mesuré : ×1,5 garde un drift (15,6°), ×2 et au-delà dégradent la réception.

Conséquence d'une remorque rigide : en braquant fort à basse vitesse, la queue
balaie vers l'extérieur (11,5 m derrière l'essieu arrière).

## 5 ter. Amortissement du corps

`linear_damp_mode = REPLACE`, **`linear_damp = 0`**. Le défaut du projet
(`default_linear_damp` = 0,1) est une traînée cachée qui plafonnait le camion à
~167 km/h (spike V1). La résistance à l'avancement est une force explicite,
réglée dans `VehicleTuning` et désactivable comme les autres.
`angular_damp` reste au défaut du projet.

## 6. Cibles de conduite

Ce sont des **cibles de design** : les tests de la phase 1 mesurent l'écart. Les
valeurs **mesurées** vont dans `game/tests/baseline.json`, et les pistes sont
dessinées sur les valeurs mesurées (`docs/METRICS.md`), pas sur ces cibles.

| Grandeur | Cible | Tolérance |
|---|---|---|
| Vitesse max (plat) | 150 km/h | ± 5 % |
| 0 → 100 km/h | 6,0 s (360 ticks) | ± 5 % |
| Freinage 100 → 0 | < 45 m | — |
| Retournement | jamais, plein braquage à 80 km/h | — |
| Adhérence latérale max | ~0,9 g | ± 10 % |

## 7. Couches de collision

| Couche | Usage |
|---|---|
| 1 `world` | sol de piste, murs, décor statique |
| 2 `vehicle` | châssis des camions |
| 3 `checkpoint` | `Area3D` de checkpoint et ligne d'arrivée |
| 4 `reset_zone` | `Area3D` hors-piste : eau, vide, zone interdite |
| 5 `hazard` | objets mobiles dangereux |

Les rayons de suspension ne visent que la couche 1 : une roue ne « roule » ni
sur un autre camion ni sur un checkpoint.

## 8. Surfaces

Chaque collision de piste porte une **surface**, qui module l'adhérence :

| Surface | Adhérence (multiplicateur) |
|---|---|
| `asphalt` | 1,0 |
| `dirt` | 0,75 |
| `grass` | 0,6 |
| `ice` | 0,3 |

Portée par une métadonnée `surface` sur le `StaticBody3D`, lue par le rayon de
suspension au point de contact. Absente = `asphalt`.

## 9. Ce que le maillage n'a pas le droit de faire

Rappel pour la phase 5 : le modèle Blender **suit** ce fichier (dimensions,
positions et noms des roues), il ne le définit pas. On ne dérive jamais une
masse, un centre de masse ou une forme de collision du maillage.
