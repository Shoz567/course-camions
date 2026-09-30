# METRICS.md — Les métriques de conduite sont mesurées, pas décrétées

---

## 1. Le problème que ce fichier résout

Le `track-designer` a besoin de chiffres pour dessiner une piste : à quelle
vitesse arrive-t-on dans ce virage, quel rayon le camion peut-il tenir, jusqu'où
porte ce saut.

Ces chiffres sont des **résultats** du réglage de la phase 1, pas des entrées.
`docs/VEHICLE_SPEC.md` §6 fixe des *cibles* ; ce qui compte pour dessiner une
piste, c'est ce que le camion fait *réellement*. Dessiner une épingle pour un
rayon de braquage supposé de 15 m alors que le camion en tient 22, c'est
refaire la piste.

**Donc : ces valeurs sont produites par un test qui les mesure, et le
`track-designer` les lit. Personne ne les invente.**

## 2. Comment elles sont produites

`game/tests/scenes/handling_test.tscn` (tâche 1.10) pilote de vrais camions par
des `InputFrame` (gaz, frein, braquage, et une commande qui tient une vitesse),
et mesure chaque grandeur selon le protocole du tableau ci-dessous.

- **`make baseline`** écrit les valeurs mesurées dans `game/tests/baseline.json`.
  C'est le seul moyen de changer la référence : un geste explicite, après un
  changement de réglage voulu, committé avec lui.
- **`make test`** (à chaque commit) mesure à nouveau et **échoue** si une valeur
  s'écarte de plus de 10 % de la référence : si la vitesse max augmente de 15 %
  après un réglage, un virage de la piste n°1 est peut-être devenu
  infranchissable, et on veut le savoir avant de dessiner.

Première mesure : 2026-09-26, Godot 4.7.2 (vitesse max 149,2 km/h, 0 → 100 en
6,03 s, freinage 38,7 m, rayon mini 21,6 m à 50 km/h, 0,877 g).

## 3. Le tableau

Valeurs `null` tant que `handling_test` n'a pas tourné. **Un `null` signifie « ne
dessine pas de piste qui en dépend »**, pas « prends la cible ».

| Métrique | Clé dans `baseline.json` | Protocole de mesure |
|---|---|---|
| Vitesse max | `top_speed_kmh` | plein gaz sur le plat jusqu'à stabilisation (±0,5 km/h sur 60 ticks), vitesse **le long de l'axe avant** |
| 0 → 100 km/h | `accel_0_100_s` | ticks entre le départ arrêté et 100 km/h, divisés par 60 |
| Freinage 100 → 0 | `braking_100_0_m` | distance parcourue entre le début du freinage et l'arrêt |
| Rayon de braquage mini | `min_turn_radius_m` | plein braquage à 50 km/h stabilisés, rayon du cercle décrit par le centre de masse |
| Adhérence latérale max | `max_lateral_g` | accélération latérale max tenue sans dérapage, en g |

**Boost** (mesuré par `truck_boost_test`, 2026-09-28) : vitesse max portée de
149 à **179 km/h**, +32 km/h gagnés en 1,5 s. À prendre en compte pour les
sauts et les freinages après une ligne droite.

À ajouter quand les mécaniques existeront : portée d'un saut standard à vitesse
max, vitesse max en dérapage, vitesse max par surface.

### Deux pièges de mesure

**Mesure la vitesse le long de l'axe avant du camion**, pas la norme du vecteur
vitesse. En dérapage, un camion peut filer à 120 km/h de travers : ce n'est pas
de la vitesse utile.

**Le rayon de braquage se mesure sur le centre de masse, en régime établi**,
pas pendant le transitoire d'entrée en virage : au début, le camion décrit un
arc bien plus large qu'une fois stabilisé.

## 4. Dimensions de piste

Ces valeurs-là sont des **choix de design**, pas des mesures.

| Grandeur | Valeur | Justification |
|---|---|---|
| Largeur minimale de piste | **75 m** | décision du 2026-09-29 (playtest à 4 : ×1,5) ; avant : 50 m, puis 35 m (2026-09-28). Arène pour 4 semi-remorques articulées de 16,4 m de front (VEHICLE_SPEC §2), remorques qui balaient jusqu'à 7 m de côté |
| Rayon des virages | **120 à 160 m** | décision du 2026-09-29 ; avant : 100 à 120 m. Plusieurs ensembles de 16 m doivent pouvoir déraper côte à côte sans se coincer dans les murs |
| Largeur de la grille de départ | 4 camions de front, J1 et J2 au centre (±10 m), J3 et J4 à l'extérieur (±30 m, à 7,5 m des murs) ; 2e rang (J5 et J6, décision du 2026-09-30) 20 m derrière, **en quinconce** à ±20 m | 20 m entre deux camions voisins : 4 ensembles partent de front sans se toucher, même remorques braquées ; au 2e rang, un ensemble agrandi (19,7 m) aurait le nez contre la remorque de devant : en quinconce, il a la voie libre entre deux camions du 1er rang (`grid_back_lateral`) |
| Dévers | au plus **9°**, raccords de **120 m**, chaussée pivotant sur son bord **bas** | décision du 2026-09-29 : sur 75 m de large, un dévers autour de l'axe enfonçait le bord intérieur sous le sol (rétrécissement visible) ; le bord haut monte de 37,5 × sin(dévers), d'où des raccords longs |
| Relief | **43 m** de dénivelé sur le tracé, pente max **19,4 %** (mesurées par `track_hazards_test`, bornes : dénivelé ≥ 30 m, pente entre 12 et 20 %) ; raccords de pente lissés sur **30 m** | décision du 2026-09-30 (« Hills ») : vraie côte où l'on sent la masse, descente plongeante où la gravité accélère le camion (≥ +8 km/h en 3 s sans gaz), compression visible au creux (moyeu < 0,4 m à 110 km/h) ; avant : 15 m et 7,7 % |
| Durée d'un tour | 60 à 90 s | assez court pour que les écarts restent lisibles, assez long pour varier les virages |
| Épaisseur minimale d'un mur | **0,3 m** | choix de design (2026-09-26) : le spike V2 n'a mesuré aucune traversée jusqu'à 0,1 m à 200 km/h ; 0,3 m est la glissière de son protocole, avec de la marge |
| Hauteur des murs | **2,8 m** | décision du 2026-09-28 : au-dessus du bas de la caisse de remorque (1,8 m), aucun passage par-dessus bord |
| Frottement des murs | **0,5** | décision du 2026-09-28 : freine les impacts. Jolt retient le plus faible des deux frottements : effectif seulement avec une caisse de camion à 0,5 (`chassis_friction`) |

Principe : **une piste trop large est ennuyeuse**. Les contacts entre camions
font le sel du genre ; si tu hésites, resserre.

## 5. Règle d'usage

- Le `track-designer` **lit** ce fichier et `baseline.json`. Il ne les écrit pas.
- Le `godot-qa` **écrit** `baseline.json` via `make baseline` (`handling_test`).
- Personne ne modifie une valeur mesurée à la main pour faire passer un design.
  Si une piste a besoin d'un rayon de 15 m et que le camion en tient 22, c'est
  soit la piste qui change, soit le réglage — et le réglage se change avec ses
  tests, pas en douce.
