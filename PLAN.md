# PLAN.md — Course de camions arcade

Roadmap par phases. **Une phase à la fois.** Une phase n'est terminée que quand
tous ses critères de sortie sont vérifiés par un test ou une scène de démo.

Légende : `[ ]` à faire · `[~]` en cours · `[x]` fait
Colonne **Agent** = sous-agent de `.claude/agents/` à qui déléguer.

---

## Vue d'ensemble

| Phase | Objectif | Sortie visible | Effort indicatif |
|---|---|---|---|
| 0 | Fondations du dépôt | `make test` passe | ✅ fait |
| 0.5 | Spikes du camion | 4 réponses, docs corrigés | 🟡 V1, V2, V4 faits ; V3 ouvert |
| **1** | **Un camion arcade qui se conduit bien** | **un camion sur un plat, testé** | **1–3 sem** |
| 2 | Piste et tour solo | 3 tours chronométrés | 1–2 sem |
| 3 | Course complète + premier juice | une course avec départ, classement, arrivée | 1–1,5 sem |
| 4 | Écran partagé 2 à 4 joueurs | 4 joueurs sur un canapé | 1 sem |
| 4.5 | Combat arcade : PV, pouvoirs, obstacles & dégradations | course armée avec PV, pouvoirs D-PAD et obstacles dynamiques | 1 sem |
| 5 | Art généré par Blender | camions et pistes texturés | 1–2 sem |
| 6 | Online host-autoritaire | 2 PC connectés | 2–4 sem |
| 7 | Polish, menus, export | build jouable | 1–2 sem |

**La phase 1 est celle qui déborde** : la sensation de conduite fait ou défait
un jeu de course arcade, et elle se règle par petites touches. La phase 0.5
existe pour qu'elle déborde pour de bonnes raisons (le réglage est difficile)
et non pour de mauvaises (le modèle de véhicule n'était pas le bon).

---

## Phase 0 — Fondations ✅

Héritée de l'ancien projet (archivé par le tag `archive/ragdoll-brawler`), puis
nettoyée pour la course de camions.

| # | Tâche | État |
|---|---|---|
| 0.1 | `docs/ENVIRONMENT.md` : outils, versions, machine de référence | `[x]` |
| 0.2 | Projet Godot dans `game/`, Forward+, Jolt, 60 ticks/s | `[x]` |
| 0.3 | `.gitignore`, `.gitattributes`, hooks versionnés dans `.githooks/` | `[x]` |
| 0.4 | Socle de tests `PhysicsTest`, `cli_runner.gd`, statut SKIP, `make test-selftest` | `[x]` |
| 0.5 | `Makefile` : `assets`, `import`, `test`, `test-full`, `test-selftest`, `run` | `[x]` |
| 0.6 | `baseline.json` versionné | `[x]` |
| 0.7 | Autoloads `GameState`, `RaceManager`, `DebugDraw` (primitives de tracé testées) | `[x]` |
| 0.8 | `tools/blender/lib/export.py` (contrat glTF validé) + `build_all.py` | `[x]` |
| 0.9 | Passage à **Godot 4.7.2** : socle et réglages Jolt revérifiés | `[x]` |

---

## Phase 0.5 — Spikes du camion

**But** : trancher quatre questions avant d'écrire la physique. Protocoles
complets dans **`docs/SPIKE.md`**. Code jetable dans `spike/`, supprimé à la fin.

| # | Tâche | Agent | État |
|---|---|---|---|
| 0.5.1 | **V1** — `VehicleBody3D` ou `RigidBody3D` + suspension par rayons ? → **rayons** | vehicle-physics-engineer | `[x]` |
| 0.5.2 | **V2** — collisions à 160 km/h : épaisseur de mur minimale, détection continue → **CCD, pas de minimum physique** | godot-qa | `[x]` |
| 0.5.3 | **V3** — écran partagé à 4 sur l'Iris Xe : renderer et budget de rendu | godot-qa | `[ ]` machine de référence |
| 0.5.4 | **V4** — export Blender d'un camion à roues séparées → **`export.py` corrigé** | blender-modeler | `[x]` |
| 0.5.5 | Corrections appliquées aux documents, `spike/` supprimé | — | `[x]` |

**Critères de sortie**
- `[~]` Le tableau de livrable de `docs/SPIKE.md` est rempli (V3 ouvert).
- `[x]` `docs/VEHICLE_SPEC.md` confirmé ou corrigé par V1.
- `[ ]` `baseline.json` contient `physics_frame_ms_1_truck`, `physics_frame_ms_4_trucks`
  et `render_frame_ms_split_4` : à mesurer sur la machine de référence
  (`ENVIRONMENT.md` §1). Les deux premiers se mesurent en phase 1 (tâche 1.10).

> La phase 1 démarre sans attendre V3 : V3 ne bloque que la phase 4.

---

## Phase 1 — Un camion arcade qui se conduit bien

**But** : un camion piloté par une `InputFrame`, stable, rapide, qui dérape et se
rattrape. Sur un sol plat : pas encore de piste.

> ⚠️ Zéro art à cette phase. Des boîtes. Si tu ouvres Blender ici, tu perds ton
> temps.

| # | Tâche | Agent | État |
|---|---|---|---|
| 1.1 | Ressource `VehicleTuning` + `default_vehicle.tres` (ressorts en fréquence et amortissement, moteur, freins, direction, adhérence) avec `validate()` | vehicle-physics-engineer | `[x]` |
| 1.2 | Scène du camion construite d'après `VEHICLE_SPEC.md` : `RigidBody3D`, 2 boîtes de collision, centre de masse, 4 ancrages de roue, `linear_damp = 0`, `continuous_cd` | vehicle-physics-engineer | `[x]` |
| 1.3 | Suspension par rayons : force ressort-amortisseur à chaque ancrage, longueur libre déduite **par essieu** | vehicle-physics-engineer | `[x]` |
| 1.4 | Moteur, freins, marche arrière : force longitudinale au point de contact | vehicle-physics-engineer | `[x]` |
| 1.5 | Direction (angle réduit avec la vitesse) et adhérence latérale, modulée par la surface | vehicle-physics-engineer | `[x]` |
| 1.6 | Dérapage au frein à main, anti-retournement, contrôle en l'air | vehicle-physics-engineer | `[x]` |
| 1.7 | Reset : remise sur les roues par `state.transform`, vitesses à zéro | vehicle-physics-engineer | `[x]` `reset_to()` ; le reset automatique est la 2.6 |
| 1.8 | `InputFrame` de conduite + `ScriptedInputSource` (tests) + `LocalInputSource` | gameplay-engineer | `[x]` + manette (`DeviceInputSource`) et clavier ; `LocalInputSource` les fusionne |
| 1.9 | Branchement de `DebugDraw` : rayons de suspension, forces de pneu, centre de masse | vehicle-physics-engineer | `[x]` F1 à F4 dans le bac à sable |
| 1.10 | Tests : stabilité à l'arrêt, hauteur de caisse, `handling_test` (métriques), virage, saut, haute vitesse, perf | godot-qa | `[x]` baseline de perf à écrire sur la machine de référence |

**Critères de sortie** (catalogue de `CLAUDE.md` §10, cibles de `VEHICLE_SPEC.md` §6)
- `[x]` Posé 600 ticks sans input : roulis et tangage < 1°, dérive < 5 cm.
  *Mesuré : 0,0005°, 1,2 mm.*
- `[x]` Hauteur de caisse au repos conforme à ± 3 cm. *Mesuré : +0,1 mm.*
- `[x]` Vitesse max et 0 → 100 km/h à ± 5 % de la cible ; freinage 100 → 0 < 45 m.
  *Mesuré : 149,2 km/h, 6,03 s, 38,7 m.*
- `[x]` Plein braquage à 80 km/h pendant 300 ticks : jamais retourné. *Roulis max 3,5°.*
- `[x]` Chute de 2 m : 4 roues au sol en < 30 ticks **après le premier contact**, stabilisé
  en < 60 ticks après ce contact, châssis jamais au sol, aucun NaN. *Mesuré : 0 et 47 ticks.*
- `[x]` Mur de piste à vitesse max : jamais traversé. *Mur de 0,3 m à 150 km/h, de face et à 30°.*
- `[~]` Physique < 4 ms/tick à 4 camions. *1,66 ms sur Ryzen 7 8845HS ; à confirmer
  sur la machine de référence (i7-1255U), où s'écrit `physics_frame_ms_*`.*
- `[x]` `docs/METRICS.md` renseigné par la mesure (`make baseline`, verrouillé par `make test`).
- `[x]` Tout passe **5 fois sur 5** via `make test-full`.

**Pièges connus**
- Un amortissement de suspension trop faible fait « pomper » le camion à haute
  vitesse ; trop fort, il rebondit sur les bosses comme un bloc.
- L'adhérence latérale doit dépendre de la charge de chaque roue, sinon le
  camion glisse en l'air comme au sol.
- Mesure la vitesse le long de l'axe avant du camion, pas la norme du vecteur :
  en dérapage, les deux diffèrent beaucoup.
- `default_linear_damp` (0,1) est une traînée cachée : le camion la remplace
  par 0, et la traînée est une force de `VehicleTuning` (`docs/SPIKE.md` A10).

---

## Phase 2 — Piste et tour solo

| # | Tâche | Agent | État |
|---|---|---|---|
| 2.1 | Caméra de poursuite amortie (ne tremble jamais, ne passe pas dans les murs) | gameplay-engineer | `[x]` `ChaseCamera` |
| 2.2 | Piste blockout n°1, dimensionnée sur `docs/METRICS.md` : virages variés, un saut | track-designer | `[x]` `track_01_blockout.tscn` |
| 2.3 | Checkpoints ordonnés + ligne d'arrivée + détection du mauvais sens | track-designer | `[x]` 20 `Area3D` (n°0 = ligne) ; mauvais sens par la ligne de course (`RaceLaps`) |
| 2.4 | Zones de reset (hors-piste, vide) + points de réapparition | track-designer | `[x]` 204 `Area3D` au-delà des murs, signaux ; réapparition `get_respawn_transform()` |
| 2.5 | Tours et chrono (dérivé des ticks), meilleur tour | gameplay-engineer | `[x]` `RaceLaps` : 3 tours, ordre strict, réapparition bridée |
| 2.6 | Reset manuel et automatique (retourné ou immobile hors piste pendant N ticks) | gameplay-engineer | `[x]` `AutoReset` : 30 ticks hors piste, 120 ticks couché |
| 2.7 | HUD minimal : vitesse, tour, chrono | gameplay-engineer | `[x]` `RaceHud` : vitesse, tour 1/3, temps, meilleur, jauge de boost |
| 2.8 | Tests : tour compté seulement si les checkpoints sont passés dans l'ordre ; raccourci refusé ; reset replace sur la piste | godot-qa | `[x]` `race_laps_test`, tour piloté compté par les vraies `Area3D`, reset, glissière |

**Piste n°1** (`game/tracks/track_01_blockout.tscn`, générée par `TrackBlockout`),
élargie le 2026-09-29 (playtest à 4 : ×1,5) : 3 008 m, **75 m** de large,
glissières continues de 0,3 m, **2,8 m** de haut, frottement 0,5. Grand virage
relevé (R 160 m, 7°) en montée, plongeon de compression, **grande montée** de
240 m (+40 m), S en dévers inverse (R 140 m, ±40°, 3°), crête à 43 m,
**chicane en descente plongeante** (R 160 m, ±35°, −38 m face aux gratte-ciel),
ligne droite du tremplin, épingle relevée (R 140 m, 9°), bosse et ligne droite
des stands de 602 m, grille de départ à plat (100 m). Le dévers
pivote sur le bord bas, avec des raccords de 120 m : plus de chaussée enfoncée
sous l'herbe (le « rétrécissement » après le départ). Grille de 4 de front
(±10 m, ±30 m). **6 plaques de boost** (chevrons orange, +40 km/h pendant 1,5 s),
**4 rampes de saut** (chevrons cyan, impulsion verticale de 8 m/s, assiette
renforcée en vol, réception amortie), **4 flaques d'eau** sur les mauvaises
trajectoires (vitesse × 0,7 puis freinage) et **8 panneaux** à l'extérieur des
virages (éjectés au contact, vitesse du camion divisée par 2) ; effets
appliqués par `PadEffects`. **Collines** depuis le 2026-09-30 (demande
utilisateur « Hills ») : 43 m de dénivelé, pente max 19,4 %, raccords
de pente lissés sur 30 m (`climb_blend_length`) : compression franche au creux
avant la grande montée (moyeu à 0,04 m de sa butée à 110 km/h), un camion lâché
sans gaz en haut de la chicane prend +9 km/h en 3 s ; pas de frein de
survitesse en descente. Zones de
reset tout autour. Métriques : `baseline.json` du 2026-09-26 (0,877 g,
149,2 km/h), inchangées par la remorque (inertie imposée, VEHICLE_SPEC §5 bis).
**Tour de référence : 87,7 s** (`track_01_lap_test`, pilote à 80 % de
l'adhérence mesurée, camions à l'échelle 1,2, semi-remorque articulée
comprise, plaques et pièges sans effet, relief compris).
**Décors de course** (2026-09-30, `RaceDecor`, purement visuels, aucune
collision) : 3 ponts routiers et un échangeur à deux niveaux enjambent la piste
(tablier à 20 m au-dessus du point le plus haut de la chaussée survolée, piles
au-delà des murs, arc porteur, néons, circulation en points de lumière), chacun
avec un **méga-écran holographique** dont la publicité alterne ; 4 **tribunes**
de part et d'autre du départ (environ 3 000 spectateurs en un MultiMesh : ils sautent,
font la ola, prennent des photos ; projecteurs sans ombres) ; 8 **faisceaux**
qui balaient le ciel. Coût GPU mesuré sur la grille à 6 joueurs (Radeon 780M,
1920 × 1200, qualité haute) : 16,3 ms.

**Piste n°2, « Playa Del Sol »** (2026-09-30, `game/tracks/track_02_playa.tscn`,
même générateur, thème `TrackTheme.PLAYA_DEL_SOL`) : une île en plein soleil,
2 673 m, 75 m de large, 40 m de dénivelé, pente max 14 %. Promenade du front de
mer (départ, océan à droite), montée de la corniche (R 160 m, 5°), corniche
(+26 m, 11 %), virage du belvédère (R 140 m, 7°) à 36 m, **descente des
falaises** face à la mer et aux îlots, S des palmiers (R 150 m, ±45°), plage,
**grand pont de la baie** (R 200 m, 6°, tablier de béton sur piles au-dessus de
l'eau), **jetée en bois** sur pieux avec 2 tremplins, grille à plat. 6 plaques
de boost, 4 tremplins, 8 panneaux, et 4 **bancs de sable** (liseré rouge et
blanc) à la place des flaques : même ralentissement (`PadEffects`). Le thème
habille le générateur sans toucher au tracé ni à la physique : chaussée de
jour et planches sur les ponts, glissières blanches à vibreurs, **masque terre /
mer** calculé sur le tracé (terre à 130 m autour, intérieur de la boucle, baie
de 105 m creusée sous les tabliers), talus de roche sous les portions hautes,
segments `"bridge"` (tablier sur piles dès 3 m de haut). Décor
(`PlayaBackdrop`, 6 MultiMesh, aucune collision) : palmiers, parasols, rochers
au large, phare ; tribunes de jour au départ (`RaceDecor`, sans faisceaux
ni projecteurs). Environnement `playa_sun.tres`, soleil avec ombres
(`dev/race_playa.tscn`). **Tour de référence : 76,7 s** (`track_02_lap_test`,
mêmes règles que la piste n°1). Le circuit se choisit au menu
(`GameState.selected_track`, `GameState.TRACKS`).

**Critères de sortie**
- `[x]` Un joueur fait 3 tours chronométrés sur la piste n°1 (`make run` :
  compte à rebours, 3 tours, arrivée, Start pour rejouer).
- `[x]` Un raccourci qui saute un checkpoint n'est jamais compté (`race_laps_test`).
- `[x]` Un camion retourné ou tombé est remis en piste, n'importe où sur le
  circuit (`track_01_reset_test`), sans jamais sauter de checkpoint.

En plus de la phase 2 (demande du 2026-09-28) : schéma de manette style Mario
Kart (`INPUT_SPEC.md` §3), boost avec recharge (1,5 s / 6 s depuis le 2026-09-30, +30 km/h mesurés),
klaxon (son généré, transmis par l'`InputFrame`), vue cabine.

---

## Phase 3 — Course complète et premier juice

| # | Tâche | Agent |
|---|---|---|
| 3.1 | `RaceManager` : grille de départ, compte à rebours, course, arrivée, résultats | gameplay-engineer |
| 3.2 | Classement en temps réel : checkpoints passés + distance au suivant | gameplay-engineer |
| 3.3 | Contacts entre camions : rester jouable, pas de camion « collé » | vehicle-physics-engineer |
| 3.4 | Piste n°2, d'une autre « idée » que la n°1 | track-designer |
| 3.5 | **Juice minimal** : son moteur au régime, crissement, impacts, fumée de dérapage, vibration de caméra aux chocs | gameplay-engineer |
| 3.6 | Tests : classement correct en toutes circonstances, la course se termine toujours | godot-qa |

**Critères de sortie**
- Une course complète se joue du départ aux résultats sans intervention.
- Le classement est juste, y compris au passage de la ligne et après un reset.
- Une course se termine toujours, même si un camion ne finit pas (temps limite).

> **Pourquoi le juice est ici et pas en phase 7.** Le playtest décisif a lieu en
> fin de phase 4. Sans son de moteur ni crissement, un jeu de course arcade est
> jugé sur sa version la moins convaincante.

---

## Phase 4 — Écran partagé local

| # | Tâche | Agent | État |
|---|---|---|---|
| 4.1 | `DeviceInputSource` : routage des `InputEvent` par `device` id (`docs/INPUT_SPEC.md`) | gameplay-engineer | `[x]` + profil MK8 Switch, jeux de touches par joueur |
| 4.2 | Lobby local : « appuyez sur A pour rejoindre », 2 à 4 joueurs, couleur par joueur | gameplay-engineer | `[~]` menu principal (`ui/main_menu.tscn`) : choix de 1 à 6 joueurs, couleur fixe par joueur, joueur N = manette N ; « appuyez sur A pour rejoindre » à faire |
| 4.3 | Écran partagé : 1 caméra et 1 HUD par joueur dans des `SubViewport` (2, 3, 4 vues) | gameplay-engineer | `[x]` `LocalRace` : plein écran, 2 vues haut / bas, grille 2 × 2 à 3-4, **3 × 2 à 5-6** (à 3 et à 5, la case libre = caméra TV sur le leader), HUD réduit (0,6 puis 0,5) |
| 4.4 | Manette branchée ou débranchée à chaud, sans pause ni crash | gameplay-engineer | `[~]` débranchement : roue libre (testé en solo) ; rebranchement en course non testé |
| 4.5 | Tests : isolation des inputs entre joueurs ; perf du rendu à 4 vues | godot-qa | `[~]` isolation à 2, 4 et 6 joueurs (`race_scene_test`, `race_4p_test`, `race_6p_test`), grilles à 3 et 5 (`race_3p_test`, `race_5p_test`), menu (`main_menu_test`) ; perf de rendu : spike V3 |

Anticipé les 2026-09-28 et 29 pour le playtest : **menu principal puis course de
1 à 6 joueurs** (6 depuis le 2026-09-30 ; `make run`, scène principale `ui/main_menu.tscn`). Le menu
(titre animé, choix du **circuit** (Cyber City ou Playa Del Sol ; Triangle ou
T) et du nombre de joueurs à la manette, au clavier ou à la souris, son on / off, écran des paramètres avec le schéma légendé de la manette
et le volume, piste et camions en orbite derrière)
lance la scène de course du circuit (`dev/race.tscn` ou `dev/race_playa.tscn`),
dans la catégorie de vitesse choisie (Lent 50cc 110 km/h,
Normal 100cc 150 km/h, Rapide 150cc 185 km/h, Ultrasonique 200cc 225 km/h ;
`GameState.SPEED_CLASSES`). J1 camion bleu AZUR (manette 0 ou flèches), J2 rouge
DURAND (manette 1 ou ZQSD), J3 jaune SOLEIL (manette 2), J4 vert (manette 3),
**J5 VIOLET NÉO-TOKYO** (manette 4) et **J6 ORANGE CARBO** (manette 5) : pas de
modèle à eux, un modèle existant repeint à l'exécution par une livrée
(`TruckVisual.livery`, par nom de matériau : améthyste vernie et néons magenta ;
orange lave métallisé, carbone mat, jantes cuivrées). 2e rang de la grille en
quinconce (±20 m) ;
compte à rebours, position (POS n/N) dans chaque HUD, classement affiché à tous
dès la première arrivée ; Start / Entrée rejoue, − / Échap revient au menu.
Accès directs : `make solo` (`dev/track_drive.tscn`), `dev/race_2p.tscn`.
Affichage (2026-09-30) : base 1920 × 1080, étirement `canvas_items`, **plein
écran sans bordure** à la résolution de l'écran (plus de fenêtre 1280 × 720
imposée ; F11 : fenêtre), **MSAA 2x** sur la fenêtre et sur chaque vue de
l'écran partagé. Éclairage : les deux environnements activent les reflets
(**SSR**), l'éclairage indirect (**SSIL**) et l'occlusion ambiante (**SSAO**) ;
`GraphicsSettings` en retire selon la qualité choisie dans les paramètres
(haute, moyenne : SSAO seul, basse : aucun effet, FXAA) et, en qualité haute,
selon le nombre de vues : SSIL jusqu'à 2 vues, SSR jusqu'à 4, SSAO toujours.
Coût GPU mesuré le 2026-09-30 sur la machine de développement (Radeon 780M,
1920 × 1200 ; **pas** la machine de référence, rien n'est écrit dans
`baseline.json`) : 1 joueur 8 ms sans effet, 11 à 15 ms avec tout ; 4 joueurs
10 ms → 14 ms (SSR + SSAO) → 16 ms (tout) ; 6 joueurs 12 ms → 15 ms (SSAO) →
19 ms (tout), d'où ces seuils pour tenir 60 images par seconde.

**Critères de sortie**
- 4 manettes, 4 camions indépendants, aucune fuite d'input (test automatisé).
- Débrancher une manette en pleine course ne crashe pas et ne met pas en pause.
- Rendu à 4 vues dans le budget fixé par le spike V3.

> 🎉 **Ici le jeu est jouable.** Faites-y jouer de vraies personnes avant
> d'aller plus loin. Si ce n'est pas drôle sur un canapé, l'art et le réseau n'y
> changeront rien.

---

## Phase 4.5 — Combat arcade : PV, pouvoirs, obstacles & dégradations

Suite aux retours de jeu, enrichissement du gameplay arcade avec affrontement physique, gestion des dégâts, arsenal de pouvoirs sur la croix directionnelle (D-PAD) et obstacles interactifs.

| # | Tâche | Agent | État |
|---|---|---|---|
| 4.5.1 | Vitesse tracteur solo (x1.2 sans remorque) et passage de la course à **4 tours** | gameplay-engineer | `[x]` |
| 4.5.2 | Obstacles dynamiques : suppression du freinage sur les panneaux (*yeet* conservé sans pénalité) et flaques savonnettes (glissade incontrôlée sans perte de vitesse brute) | track-designer | `[x]` |
| 4.5.3 | Barils explosifs sur la piste : physique, détonation, projection (*yeet* léger) | track-designer | `[x]` |
| 4.5.4 | Système de PV (100 HP) : dégâts chocs murs (-1 à -5 HP cabine uniquement), barils explosifs (-15 HP), remorque bouclier, mort et respawn après 3 s (PV discrets/internes avant dégradations) | gameplay-engineer | `[~]` |
| 4.5.5 | Remorques larguées persistantes (50 HP) : restent sur piste sans disparition, nouvelle remorque réapparue sur le tracteur, interdiction de largage les 5 premières secondes | gameplay-engineer | `[~]` |
| 4.5.6 | Dégradations visuelles localisées selon la zone d'impact et fumée progressive | visual-artist | `[ ]` |
| 4.5.7 | Sas "READY ?" avant START : écran scindé d'identification des joueurs avec validation sur la touche Carré (PS5 Square) | gameplay-engineer | `[~]` |
| 4.5.8 | Arsenal des pouvoirs D-PAD : Lance-missiles (2 missiles, 5 s cooldown, -15 HP) et Citerne d'essence sur remorque (traînée glissante 2 s, 30 s cooldown) | gameplay-engineer | `[ ]` |

**Critères de sortie du Lot 1 (Terminé)**
- Les camions sans remorque accélèrent et pointent à x1.2 de leur vitesse de pointe normale (`solo_top_speed_factor = 1.2`).
- La course se dispute sur 4 tours complets avec affichage HUD synchronisé.
- Les panneaux sont éjectés sans pénaliser la vitesse du camion ; les flaques provoquent une glissade latérale sans freinage.
- Des barils explosifs jalonnent la piste et explosent avec éjection physique au contact.
- `make test` passe à 100 % (47/47 tests).

**Critères de sortie du Lot 2 (En cours)**
- Gestion des PV (100 HP) avec calcul des dégâts aux murs et dégâts barils (-15 HP), sans dégradation visuelle pour l'instant.
- Remorques larguées persistantes (50 HP) avec spawn d'une nouvelle remorque sur le camion (verrou 5 premières secondes).
- Sas "READY ?" avant le départ où chaque joueur valide avec la touche Carré.

---

## Phase 5 — Art généré par Blender

Principe directeur : la physique reste sur des **formes simples** (boîtes et
rayons). Le maillage est **purement visuel** et suit `docs/VEHICLE_SPEC.md`.

| # | Tâche | Agent |
|---|---|---|
| 5.1 | `build_truck.py` : carrosserie + 4 roues séparées nommées selon le contrat, pivots au moyeu | blender-modeler |
| 5.2 | Variantes de camions : paramètres CLI (forme de cabine, couleur) | blender-modeler |
| 5.3 | `build_track_01.py` : visuel de la piste + collision séparée (suffixe `-col`), surfaces | blender-modeler |
| 5.4 | Décor et props dans le budget du spike V3 | blender-modeler |
| 5.5 | Intégration : le camion texturé remplace les boîtes, roues animées d'après les rayons | vehicle-physics-engineer |
| 5.6 | Non-régression : **tous** les tests de la phase 1 passent inchangés | godot-qa |

**Critères de sortie**
- `make assets` régénère tout l'art depuis zéro en < 2 min.
- Les tests de conduite passent sans qu'aucun seuil ait été touché.
- Budgets respectés ; aucun `.glb` dans le dépôt.

---

## Phase 6 — Online host-autoritaire

Lire `docs/NETCODE.md` avant de commencer.

| # | Tâche | Agent |
|---|---|---|
| 6.1 | Transport ENet, host/join par IP, lobby | netcode-engineer |
| 6.2 | `RemoteInputSource` : inputs groupés par 3, 20 Hz | netcode-engineer |
| 6.3 | Snapshots d'état quantifiés, acquittés par le client | netcode-engineer |
| 6.4 | Camions distants interpolés ; camion local prédit puis corrigé en douceur | netcode-engineer |
| 6.5 | Contacts entre camions arbitrés par le host | netcode-engineer |
| 6.6 | Déconnexion, écran « connexion perdue » | netcode-engineer |
| 6.7 | Tests avec latence et perte simulées ; mesure de la bande passante | godot-qa |

**Critères de sortie**
- 2 machines, 4 joueurs, une course complète.
- À 150 ms de latence et 2 % de perte, le camion local reste agréable à conduire.
- Bande passante montante du host < 128 kbps à 4 joueurs, en-têtes compris.

---

## Phase 7 — Polish et build

| # | Tâche | Agent |
|---|---|---|
| 7.1 | Menu principal, options, remapping | gameplay-engineer |
| 7.2 | Personnalisation des camions (couleurs, pièces générées) | blender-modeler |
| 7.3 | Sons et musique complets (`[~]` musique de course procédurale `RaceMusic`, 2026-09-30 : boucle arcade de 16 mesures à 150 BPM, du GO à l'arrivée ; bips du menu et du départ ; bruitages à faire) | — |
| 7.4 | Juice complet (particules, ralentis d'arrivée) | gameplay-engineer |
| 7.5 | Pistes supplémentaires | track-designer |
| 7.6 | Profilage et optimisation | godot-qa |
| 7.7 | Export Windows/Linux, test sur machine vierge | godot-qa |

---

## Questions de design ouvertes

À trancher par l'équipe ; chacune deviendrait une phase à part entière, pas un
ajout discret au milieu d'une autre.

- **IA / adversaires pilotés par l'ordinateur.** Sans IA, pas de mode solo
  contre des adversaires : à décider avant la phase 3.
- **Remorques** — tranché le 2026-09-28 (semi-remorque sur le même corps que le
  tracteur, inertie imposée), puis le 2026-09-29 : **articulée** à la sellette,
  ±35°, la caisse de collision pivote et balaie les adversaires (VEHICLE_SPEC
  §2 et §5 bis). Pas de mise en portefeuille ni de corps séparé.
- **Boost / objets.** Arcade retenu : boost à jauge (L), plaques de boost et de
  saut, largage de la remorque entière (Triangle, barrage de 60 s, tracteur
  seul plus rapide pendant ce temps, recharge 30 s : on relargue dès le
  raccrochage). Pas encore d'objets à
  ramasser.

## Ce qu'on ne fait volontairement pas (pour l'instant)

- Matchmaking public, NAT punchthrough (nécessiterait GodotSteam).
- Netcode déterministe ou rollback complet : Jolt n'est pas déterministe d'une
  machine à l'autre.
- Simulation réaliste (boîte de vitesses, usure des pneus) : le jeu est arcade.
- Cross-play.
