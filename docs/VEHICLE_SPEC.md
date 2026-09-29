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
semi-remorque est **articulée** (décision du 2026-09-29) : sa caisse de
collision fait partie du même corps que le tracteur, mais pivote en lacet
autour de la sellette, angle borné à ±35° (§5 bis). Pas de mise en
portefeuille. Les cotes ci-dessous sont celles du tracteur, sauf mention
« ensemble » (ensemble dans l'axe).

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
| Remorque | 3,0 × 3,10 × 13,0 | (0 ; 3,35 ; 6,9) au repos, pivote autour de la sellette (§5 bis) |

La boîte de remorque couvre la caisse du modèle de l'équipe mis à l'échelle du
tracteur (arrière à 13,4 m, visuel à 13,46 m, vérifié par `truck_visual_test`).
Son bas est à 1,8 m : la queue ne talonne pas en dessous de ~9° de tangage. Les
roues et bavettes de la remorque (sous 1,8 m) sont purement visuelles.

Le bas du châssis est à y = 0,75 : garde au sol de 0,75 m au repos. C'est ce qui
permet de passer les bosses et de retomber d'un saut sur les roues plutôt que
sur le ventre.

Le corps du camion a **`continuous_cd = true`** (spike V2 : l'enfoncement dans
un mur à 200 km/h passe de 0,87 m à 0,10 m, sans coût mesurable).

## 5 bis. Semi-remorque articulée, inertie imposée

Laissée à Godot, l'inertie se déduit des formes : la boîte de remorque multiplie
l'inertie en lacet par 17 (16 450 → 285 873 kg·m²) et **tue le drift** (dérive au
frein à main 29° → 3,5° ; mesuré le 2026-09-28). Choix arcade : la remorque pèse
peu dans la dynamique. Masse (5 000 kg) et centre de masse (§3) restent ceux du
tracteur, et les **moments d'inertie sont imposés** par `VehicleTuning`
(`inertia_*_kgm2`, valeurs du tracteur seul : 19 989 / 16 450 / 8 338). La
remorque reste **pleinement physique pour les contacts** (murs, autres camions).
Mesuré : ×1,5 garde un drift (15,6°), ×2 et au-delà dégradent la réception.

**Articulation** (décision du 2026-09-29, mécanique de blocage au conteneur) :

| Grandeur | Valeur |
|---|---|
| Sellette (pivot) | **(0 ; 1,8 ; 1,2)**, lacet seulement |
| Angle max | **±35°** (`trailer_max_angle_deg`) |
| Suivi | ressort amorti 1,6 Hz, ζ = 0,8 (fluide, sans balancier ; 2026-09-30), inertie de lacet propre |
| Consigne en virage | 10° vers l'extérieur par g d'accélération latérale |
| Consigne en dérapage | + 0,6 × l'angle de dérive, vers l'extérieur |

- La cabine réagit seule au volant : la remorque garde sa propre vitesse de
  lacet (dans le monde) et rejoint sa consigne avec retard. Un coup de volant
  sec la laisse d'abord en arrière, puis elle chasse vers l'extérieur et
  dépasse sa consigne (effet de balancier) ; relâchée, elle se réaligne.
- L'accélération latérale est **mesurée** (variation de vitesse, filtrée à
  0,1 s), pas déduite du lacet : en rattrapage de dérapage, le camion tourne sur
  lui-même sans que sa trajectoire tourne autant.
- La **boîte de collision pivote avec le maillage** (`Truck.trailer_local_transform`).
  Masse, centre de masse et inertie ne changent pas : l'articulation ne touche
  pas à la conduite du tracteur (`handling_test` inchangé).
- Un **mur arrête** le balayage (requête de forme avant chaque rotation) ; déjà
  contre un mur, la remorque se replie vers l'axe.
- Un **adversaire balayé** reçoit un choc le long du balayage, à son centre de
  masse (pas de couple : il glisse, il ne se couche pas), plafonné à 8 m/s,
  un choc par adversaire toutes les 0,5 s ; 15 % du choc revient au camion
  qui balaie (arcade : l'attaquant garde sa ligne, le tracteur n'est pas
  désaxé). La caisse pivotant dans le corps, le solveur ne voit pas sa vitesse
  propre : ce choc la remplace.
- Vérifié par `truck_trailer_test` (dérapage, coup de volant, mur, balayage).

## 5 quater bis. Direction et dérapage maîtrisé (2026-09-30)

- Train avant vif : roues à 4°/tick (braquage complet en 8 ticks), angle à
  haute vitesse × 1,35 de l'angle d'adhérence limite. Mesuré : 90 % du lacet
  établi en 11 ticks.
- Dérapage : au frein à main, le lacet est piloté vers une dérive cible
  (28° au plein braquage, proportionnelle au stick) ; mesuré : 31° tenus, à
  vitesse gardée, retour sous 5° en 41 ticks au relâcher.
- Anti tête-à-queue : la dérive prévue à 0,3 s ne dépasse jamais 40°, frein à
  main ou non (14 rad/s² d'autorité). Mesuré : un choc de 4 rad/s en lacet
  plafonne à 36°.
- Vérifié par `truck_drift_control_test`.

## 5 quater. Murs et obstacles (arcade)

- **Anti-collage** (2026-09-29) : un camion qui frotte un mur sans
  interruption (8 ticks sans contact tolérés) pendant `wall_unstick_ticks`
  (96 ticks, 1,6 s) est décollé : vitesse × 0,75, vitesse vers le mur annulée,
  +5 m/s le long de la normale du mur (vers la piste), nez ramené parallèle au
  mur. Détection : contacts du corps (`contact_monitor`) avec un corps statique
  à normale presque horizontale (le sol et les rampes ne comptent pas).
- **Remorque larguée** (pouvoir cargo, 2026-09-30) : la remorque entière se
  détache (caisse de collision du camion coupée, visuel masqué) ; une
  `DetachedTrailer` (9 000 kg, freinée, boîte pleine hauteur, couche 5
  `hazard`) la remplace sur la route pendant 10 s, puis la remorque se
  raccroche dès que sa place est libre. Tracteur seul pendant ce temps :
  vitesse max × 1,12, poussée × 1,3, braquage × 1,15 (mesuré : +18 km/h
  après 5 s). Recharge globale de 30 s depuis le largage.
- **Remorque larguée percutée** : vitesse horizontale × 0,6 et coup de lacet
  de 1,4 rad/s du côté de l'obstacle, une fois par remorque.
- Vérifié par `truck_wall_unstick_test` et `truck_cargo_test`.

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
| 5 `hazard` | objets mobiles dangereux : remorques larguées (`DetachedTrailer`) |

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
