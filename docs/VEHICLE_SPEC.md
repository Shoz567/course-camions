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

Camion de course à deux essieux, **sans remorque** (les remorques sont une
question de design ouverte, cf. `PLAN.md`).

| Grandeur | Valeur |
|---|---|
| Longueur | 5,8 m |
| Largeur | 2,5 m |
| Hauteur (cabine) | 3,2 m |
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

Les roues **ne sont pas des corps physiques**. Chaque roue est un rayon
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
libre du ressort se *déduit* des deux (affaissement statique = m·g / k par
roue) : changer la raideur dans `VehicleTuning` ne doit jamais changer la
hauteur de caisse au repos.

Rappel mesuré : Jolt laisse un corps au repos s'enfoncer de
`penetration_slop` = 0,02 m. Ça ne concerne pas les roues (des rayons), mais
bien le châssis s'il touche le sol.

## 5. Formes de collision

Deux boîtes convexes, **jamais le maillage** :

| Forme | Taille (x × y × z) | Centre (x ; y ; z) |
|---|---|---|
| Châssis | 2,4 × 1,00 × 5,8 | (0 ; 1,25 ; 0) |
| Cabine | 2,4 × 1,40 × 2,2 | (0 ; 2,45 ; −1,8) |

Le bas du châssis est à y = 0,75 : garde au sol de 0,75 m au repos. C'est ce qui
permet de passer les bosses et de retomber d'un saut sur les roues plutôt que
sur le ventre.

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
