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
| 0.5 | Spikes du camion | 4 réponses, docs corrigés | ✅ V1, V2, V3, V4 faits (V3 le 2026-10-17) |
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

**Piste n°3, « Sakura »** (2026-10-19, `game/tracks/track_03_sakura.tscn`,
même générateur, thème `TrackTheme.SAKURA`) : le Japon au printemps, un
**circuit en 8** de 2 764 m, 70 m de large. Avenue des cerisiers (départ, sous
un torii 桜街道), virage du sanctuaire, montée des lanternes, épingle du
château (R 123 m, 7°), courbe de la pagode, puis le **pont vermillon** : la
seconde diagonale du 8 passe à 18 m au-dessus de l'avenue (16,4 m de hauteur
libre), torii 神橋 ; descente du torii 花見, saut du ruisseau, S des jardins,
grande courbe des cerisiers, grille à plat. Au croisement, le générateur ne
pose aucune pile sur la route du dessous, aucune zone de reset sur l'autre
branche (`AutoReset` mesure la sortie de piste à la géométrie), et arrête sous
le tablier le checkpoint qui passe dessous. Habillage : chaussée aux pétales
tombés, platelage laqué sur le pont, murs de temple (enduit, poteaux, chaperon
de tuiles ; garde-corps vermillon sur le pont), murs de pierre de château
sous les portions hautes, flaques de bassin aux pétales flottants, barils en
tonneaux de saké (爆, gyrophare conservé). Décor (`SakuraBackdrop`, `JapanKit`,
aucune collision) : ~760 cerisiers et quelques pins, rangées de machiya,
donjon de château, pagode à cinq étages, temple, lanternes de pierre et de
papier, le mont Fuji et une chaîne de montagnes ; pétales qui volent autour de
chaque caméra (`SakuraPetals`), ambiance sonore (brise, clochettes, cloche de
temple). Tests : `track_sakura_test`, `race_sakura_test`.

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
| 3.1 | `RaceManager` : grille de départ, compte à rebours, course, arrivée, résultats (`[x]` 2026-10-17 : machine à états dans `RaceManager`, signaux ; temps limite de 30 s après la première arrivée, « non classé ») | gameplay-engineer |
| 3.2 | Classement en temps réel : checkpoints passés + distance au suivant (`[x]` `RaceLaps.position` ; 2026-10-17 : juste aussi au passage de la ligne, où l'avant du camion valide le tour avant que son centre ne passe) | gameplay-engineer |
| 3.3 | Contacts entre camions : rester jouable, pas de camion « collé » (`[x]` `truck_contact_test`, `track_01_contacts_test`) | vehicle-physics-engineer |
| 3.4 | Piste n°2, d'une autre « idée » que la n°1 (`[x]` Playa Del Sol, `race_playa_test`) | track-designer |
| 3.5 | **Juice minimal** : son moteur au régime, crissement, impacts, fumée de dérapage, vibration de caméra aux chocs (`[x]` 2026-10-17 : `TruckAudio` (moteur à 6 rapports, crissement, chocs, synthétisés), secousse de `ChaseCamera` ; fumée et traces : `TruckWheelFx` ; `juice_test`) | gameplay-engineer |
| 3.6 | Tests : classement correct en toutes circonstances, la course se termine toujours (`[x]` 2026-10-17 : `race_flow_test`) | godot-qa |

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
| 4.2 | Lobby local : « appuyez sur A pour rejoindre », 2 à 4 joueurs, couleur par joueur | gameplay-engineer | `[x]` menu : 1 à 6 joueurs, couleur par joueur ; **salle d'attente** (2026-10-17) : chaque manette rejoint avec Croix, clavier Entrée / Espace (`join_hotplug_test`) |
| 4.3 | Écran partagé : 1 caméra et 1 HUD par joueur dans des `SubViewport` (2, 3, 4 vues) | gameplay-engineer | `[x]` `LocalRace` : plein écran, 2 vues haut / bas, grille 2 × 2 à 3-4, **3 × 2 à 5-6** (à 3 et à 5, la case libre = caméra TV sur le leader), HUD réduit (0,6 puis 0,5) |
| 4.4 | Manette branchée ou débranchée à chaud, sans pause ni crash | gameplay-engineer | `[x]` débranchée : roue libre, « MANETTE DÉCONNECTÉE » dans sa vue, aucune pause ; rebranchée : elle reprend son camion (`join_hotplug_test`, 2026-10-17) |
| 4.5 | Tests : isolation des inputs entre joueurs ; perf du rendu à 4 vues | godot-qa | `[x]` isolation à 2, 4 et 6 joueurs (`race_scene_test`, `race_4p_test`, `race_6p_test`), grilles à 3 et 5 (`race_3p_test`, `race_5p_test`), menu (`main_menu_test`) ; perf de rendu : spike V3 fait le 2026-10-17, 52 images/s à 4 joueurs avec le budget (`[x]` pour la perf) |

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
**Éclairage global** (2026-10-08, demande utilisateur : graphismes et effets
visuels plutôt qu'un port Unreal) : les deux environnements activent **SDFGI**
(4 cascades, cellule 0,5 m, lumière du ciel ; énergie 0,7 à la plage pour ne
pas bleuir la route). Les néons de Cyber City colorent calandres, jantes et
conteneurs ; le dessous des remorques s'assombrit. Coût mesuré sur la RTX
5060 Ti (poste de l'utilisateur, 2026-10-08) : 1 vue ~165 → ~135 images/s,
2 vues 117 → 81, 4 vues 96 → 54, d'où : qualité haute seulement, **jusqu'à 2 vues**. Anticrénelage en qualité haute :
MSAA 2x + **SMAA** (le TAA a été essayé puis écarté : il efface la pluie).
**Post-traitement par vue** (`ScreenFx`, effet du compositeur posé sur la
caméra de chaque joueur, qualité haute et moyenne) : aberration chromatique
légère sur les bords (le camion, au centre, reste net), vignettage. Calculé après les transparents (la pluie reste). Coût mesuré :
~0,25 ms GPU par vue. Le flou radial de vitesse a été retiré le 2026-10-09
(« retire le flou de mouvement »).
**Compteur d'images par seconde** (2026-10-09) : case des paramètres,
affiché en haut à droite au menu et en course (`GameState`).
**Ambiance par circuit** (2026-10-19) : le circuit choisi au menu change
le décor du showroom (`Showroom.set_theme` : toit de Cyber City la nuit, île
de Playa au soleil, jardin japonais de Sakura avec torii, pagode, temple,
cerisiers, Fuji et pétales), le ciel et la lumière, et **toute la direction
artistique de l'interface** (`UiKit.apply_skin`, trois habillages : néon ;
plage — tuiles de bois flotté, lagon, soleil ; Japon — cases en bois de miel,
laque vermillon, plaque de laque noire à lettres d'or, police Mincho). Le menu
se reconstruit en gardant ses choix et le panneau ouvert ; l'habillage suit
jusqu'à l'écran de chargement (image du circuit, `ui/loading/*.jpg`) et au HUD
de la course. Test : `menu_ambiance_test`.
**Effets de roues** (`TruckWheelFx`, nœud « WheelFx » du camion) : glissement
latéral des roues arrière au point de contact ; au-delà de 3,5 m/s, **traces
de gomme** posées sur la route (MultiMesh en coordonnées monde, 720 segments
par camion, les plus anciens s'effacent) ; au-delà de 5 m/s, **fumée de
pneus**, plus épaisse avec le glissement (Playa del Sol seulement, voir
Particules). Au-delà de 40 km/h, **projections** derrière les roues motrices
et le train de la remorque : **traînées d'eau** sous la pluie de Cyber City,
**poussière de sable** à Playa del Sol. Mesuré
(`truck_drift_test`) : aucune trace en ligne droite ni en virage sans frein à
main (glissement 1,6 m/s), traces sur 50 des 60 ticks du drift (18,9 m/s).
**Météo de Playa del Sol** (Cyber City a déjà sa pluie, sa route mouillée et
maintenant ses gerbes d'eau) : **vent de sable** dessiné par la chaussée
(`playa_road.gdshader`) — rubans de sable étirés dans le sens du vent qui
courent en travers de la piste, par rafales (des particules ont été essayées
puis écartées : vues de près, des confettis qui flottent, et chaque vue de
l'écran partagé voyait les émetteurs de tous les joueurs) ; **brume de
chaleur** dans le post-traitement (`ScreenFx.haze`) : l'air ondule juste sous
l'horizon, seulement au-delà de 45 m (profondeur de l'image), jamais sur le
camion ni sur un portique proche.
**Matières** (textures procédurales en mémoire, aucun fichier image, comme le
reste du projet) : le bitume (`asphalt.gdshaderinc`) passe de gravillons ronds
espacés (un motif de pois, de près) à un **granulat** : mosaïque de cailloux
anguleux de 4 et 2 cm, teintes variées, quelques quartz clairs, liant noir
dans les joints, effacée au loin vers sa moyenne. Le béton des tribunes, ponts et
piliers (`concrete.gdshader`, auparavant un gris uni) : banches de 2,4 x
1,2 m avec joints et trous de tiges, teinte par panneau et par plaques,
pores, coulures sur les faces verticales ; trempé et brillant la nuit à
Cyber City.
**Particules** (2026-10-08, demande utilisateur : fumée des camions abîmés,
débris, pluie, étincelles) : briques communes `FxKit`, toutes sur GPU.
- **Fumée** (`fx/smoke.gdshader`) : bouffées qui tournent, contour rongé
  par un bruit propre à chacune, éclairées comme des boules, fondues
  contre le décor. De jour, panache noir épais ; de nuit, plus clair, il
  renvoie la lueur de la ville. La turbulence du moteur a été écartée :
  elle fige les bouffées sur place.
- **Feu moteur** sous 15 PV, avec une lueur qui vacille ; l'épave brûle
  ~10 s.
- **Étincelles** (`fx/spark_particles.gdshader`) : traits étirés sur la
  vitesse, qui refroidissent et rebondissent sur la route (un plan sous
  l'émetteur). Sources : jantes nues, moteur à l'agonie, frottement contre
  un mur (nouveau), gerbe à chaque choc franc (nouveau), avec de la
  poussière de béton si le choc est violent.
- **Explosion** : la sphère orange devient boule de feu, fumée noire,
  braises et souffle au sol ; les barils explosifs l'utilisent aussi.
- **Débris** : plaques de tôle froissée au lieu de boîtes ; les pièces
  soufflées par une explosion fument, les deux premières brûlent.
- **Pluie** (`rain.gdshader`) : les gouttes s'étirent selon leur vitesse
  relative à la caméra et s'allument dans les phares et les lampadaires.
  Éclaboussures sur la route devant la caméra. Chaque vue ne voit que sa
  pluie (calques 13 à 18).
- **Roues** : la fumée de pneus et les projections prennent le même rendu
  de bouffées. Puis (« la fumée des roues empêche la visibilité ») : fumée
  de pneus **à Playa del Sol seulement**, allégée (60 bouffées de 1,3 s au
  lieu de 140 de 2,2 s, deux fois plus transparentes, qui gonflent ×2,4 au
  lieu de ×4) ; poussière de sable allégée aussi. Cyber City n'a plus de
  bouffées : **traînées d'eau** (`fx/water_streak.gdshader`, moteur des
  étincelles) derrière les roues au-delà de 40 km/h, et nappe de gouttes
  chassée du côté où le pneu glisse en dérapage
  (`TruckWheelFx.tire_smoke`).
- **Pièges notés** : un émetteur GPU déplacé d'un coup étale sa première
  émission sur tout le trajet (un « peigne » de traits parallèles), d'où
  les gerbes de choc créées sur place. Les shaders additifs coupent le
  brouillard, qui s'y ajoutait en grands carrés.
- **Coût** : temps GPU inchangé à 4 vues (3 à 4 ms, mesure avant/après).
  L'à-coup de ~140 ms quand un camion explose existait déjà avant ces
  particules.

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
| 4.5.3 | Barils explosifs sur la piste : physique, détonation, projection (*yeet* léger) ; **remasterisation visuelle** (taille x2, balise stroboscopique/lumineuse haute visibilité) | track-designer | `[x]` lot 3 ; `damage_visuals_test`, `track_hazards_test` |
| 4.5.4 | Système de PV (100 HP) : dégâts chocs murs (-1 à -5 HP), barils explosifs (-15 HP), mort et respawn après 3 s ; lot 4 : PV séparés tête / remorque (plus de bouclier), carcasse laissée sur la route | gameplay-engineer | `[x]` `TruckHealth` (nœud « Health » du camion), signal `Truck.wall_impact` par forme touchée ; `truck_health_test`, `truck_damage_split_test` |
| 4.5.5 | Remorques larguées persistantes (50 HP) : restent sur piste sans disparition, nouvelle remorque réapparue sur le tracteur, interdiction de largage les 5 premières secondes | gameplay-engineer | `[x]` dégâts selon l'énergie du choc, explosion à 0 PV ; `trailer_hp_test`, `truck_cargo_test` (dégradation visuelle de la remorque : 4.5.6) |
| 4.5.6 | Dégradations visuelles localisées selon la zone d'impact et fumée progressive (tracteur & remorque) | visual-artist | `[x]` lot 3 : `DamageFx`, `TruckDamageFx`, `DetachedTrailer` ; `damage_visuals_test` |
| 4.5.7 | Sas "READY ?" avant START : écran scindé d'identification des joueurs avec validation sur la touche Carré (PS5 Square) | gameplay-engineer | `[x]` dans la course (`LocalRace`, état LOBBY) ; `race_ready_test` |
| 4.5.8 | Système de pouvoirs : nouvelle formule (anciens pouvoirs provisoires retirés, nouvelle conception en attente) | gameplay-engineer | `[x]` 1re série proposée le 2026-10-17 (à valider par l'équipe) : BOUCLIER (5 s sans dégâts), MISSILE (vise le camion devant, 20 PV), LASER (rayon 1,5 s, 36 PV) sur la croix gauche / droite, armes de l'équipe sur le toit, recharges 15 à 20 s (`TruckPowers`, `PowerMissile`, `powers_test`) ; hors ligne seulement (la page de sélection n'existe pas en ligne) |

**Critères de sortie du Lot 1 (Terminé)**
- Les camions sans remorque accélèrent et pointent à x1.2 de leur vitesse de pointe normale (`solo_top_speed_factor = 1.2`).
- La course se dispute sur 4 tours complets avec affichage HUD synchronisé.
- Les panneaux sont éjectés sans pénaliser la vitesse du camion ; les flaques provoquent une glissade latérale sans freinage.
- Des barils explosifs jalonnent la piste et explosent avec éjection physique au contact.
- `make test` passe à 100 % (47/47 tests).

**Critères de sortie du Lot 2 (Terminé le 2026-10-02)**
- `[x]` PV (100 HP, `TruckHealth`) : un impact contre une glissière coûte de
  1 PV (frottement, < 2 m/s vers le mur) à 5 PV (choc frontal, ≥ 18 m/s),
  proportionnellement à la vitesse normale ; **seul le tracteur encaisse**,
  la remorque sert de bouclier (le camion signale chaque impact avec la forme
  touchée : `Truck.wall_impact`). Baril explosif : -15 PV (`PadEffects`). À
  0 PV : explosion (`ExplosionFx`, son procédural des barils), épave gelée
  3 s (180 ticks, aucune commande, pas de reset), puis réapparition sur la
  ligne de course (`RaceLaps.respawn_transform`) avec 100 PV. HUD : « 100 HP »
  et une fine jauge sous les temps ; « DÉTRUIT ! retour dans 3 s ».
- `[x]` Remorques larguées **persistantes** (plus de disparition) à **50 PV** :
  chaque choc retire 50 × (v / 33 m/s)² PV, v = vitesse d'approche le long de
  la normale avant le choc (de face à 100 km/h : ~35 PV ; 60 km/h : ~13 ;
  sous 4 m/s : rien) ; à 0 PV, explosion et disparition. À la fin de la
  recharge (30 s), une **nouvelle remorque** apparaît sur le camion (dès que
  sa place est libre). Largage **verrouillé 5 s** après le GO (« VERROU 5 s »
  au HUD). Les chocs d'un adversaire le ralentissent toujours (`cargo_hit`),
  à chaque nouveau contact.
- `[x]` Sas **« READY ? »** : chaque vue affiche « J1 - BLEU (Manette 1 /
  flèches) » et « APPUYER SUR [CARRÉ] POUR ÊTRE READY » (clignotant) ; Carré
  (ou Maj, la touche du boost, lue sur la source d'input DU joueur) le passe
  « READY ! » en vert ; quand tous sont prêts, le compte à rebours démarre.
  Carré dans le sas ne consomme pas le boost.
- `[x]` `make test` à 100 % (50/50 : `truck_health_test`, `trailer_hp_test`,
  `race_ready_test` ajoutés ; tests de course sans sas : `ready_gate = false`).

**Critères de sortie du Lot 3 (Terminé le 2026-10-02)**
- `[x]` **Remasterisation des barils explosifs** : taille accrue (~x1.8 à x2, rayon ~1.2m, hauteur ~2.5m), visibilité arcade renforcée (balise lumineuse/stroboscopique clignotante au sommet visible de loin, chevrons d'alerte émissifs contrastés), rayon de déclenchement adapté, non-régression des tests d'explosion et de dégâts (-15 PV).
- `[x]` **Dégradations visuelles localisées (Module 5 & 6)** : éraflures, noircissement et déformations d'impacts sur la carrosserie du tracteur et de la remorque selon l'angle des chocs ; fumée de moteur progressive selon les PV restants (légère sous 70 PV, dense et étincelles sous 30 PV) ; dégradation visuelle de la remorque abandonnée selon ses 50 PV.
- `[x]` `make test` passe toujours à 100 % (51/51, `damage_visuals_test` ajouté).

Réalisation du lot 3 :
- **Baril** (`ExplosiveBarrel`) : rayon 1,2 m, hauteur 2,5 m (×1,85), forme
  physique et zone de déclenchement agrandies (rayon +1 m, hauteur +1,5 m) ;
  deux bandes de chevrons jaunes et noirs lumineux qui pulsent
  (`barrel_chevrons.gdshader`) ; **gyrophare** au sommet : dôme émissif,
  `OmniLight3D` orange et halo additif qui garde au moins 40 pixels à l'écran
  (`beacon_halo.gdshader` : repéré à plus de 250 m), en double éclair toutes
  les 0,9 s, déphasé d'un baril à l'autre. Explosion, son, envol, -15 PV et
  yeet inchangés.
- **Traces de choc localisées** (`DamageFx`, `TruckDamageFx`) : à chaque
  impact (mur, camion, remorque larguée), un décalque procédural au point
  touché - éraflures claires pour un frottement, brûlure noire au-delà -
  plus grand quand c'est plus violent. Le camion signale désormais le point
  et la normale de chaque impact (`Truck.wall_impact_at`, `body_impact`, sans
  effet sur les PV). Avant sur un choc frontal, flanc sur un frottement,
  remorque sur un choc arrière (accrochée à son pivot : elle suit
  l'articulation et part avec la remorque larguée). Les carrosseries sont sur
  le calque de rendu 11, seul marqué : jamais la route. Camion réapparu ou
  nouvelle remorque : neufs.
- **Fumée moteur** (particules CPU, monde) sortant de la calandre : rien
  au-dessus de 70 PV, grise de 70 à 30, anthracite épaisse avec étincelles
  sous 30, fumée d'épave pendant les 3 s avant la réapparition.
- **Remorque larguée** : trace à chaque choc qui l'abîme ; sous 60 % de ses
  PV, flancs noircis et fumée grise ; sous 30 %, toit noirci, fumée
  anthracite et étincelles ; à 0, explosion.

**Lot 4 (2026-10-06, demandes utilisateur : « augmenter la gravité », « bien
distinguer les dégâts faits à la tête du camion et à la remorque », « quand le
camion explose, il reste au milieu du chemin », « que des bouts partent »)**
- `[x]` **Gravité de vol** : en l'air, le camion tombe à 1,6 g
  (`VehicleTuning.air_gravity_factor`) ; au sol, rien ne change (adhérence,
  freinage, `baseline.json` intacts). Saut de plaque : même hauteur (4,7 m),
  1,4 s de vol au lieu de 1,8 s (`PadEffects.jump_up_speed_ms` 8 → 9,5 m/s,
  réception amortie jusqu'à 4,5 m/s au lieu de 3). Butée de suspension
  (`bump_stop_*`) : une chute de 6 m ne pose plus le châssis au sol.
- `[x]` **PV séparés** (`TruckHealth`) : la tête (100 PV) et la remorque
  attelée (PV de la remorque choisie, `TrailerType.dropped_hp`). Ce que la
  remorque encaisse ne touche jamais la tête (fin de la règle « bouclier ») ;
  à 0 PV elle explose et disparaît, l'explosion coûte 20 PV à la tête, et une
  nouvelle remorque arrive après la recharge du cargo. HUD : « REM » et sa
  jauge sous les PV de la tête.
- `[x]` **Obstacles qui blessent** : percuter une remorque larguée ou une
  carcasse (`Truck.hazard_impact`) coûte jusqu'à 40 PV à la partie touchée
  (40 × (v / 33 m/s)², de face à 100 km/h : ~28) ; l'obstacle s'abîme aussi.
  Sa propre remorque larguée aussi, autant que les autres (2026-10-07).
- `[x]` **Chocs entre camions** (`Truck.truck_impact`, 2026-10-07) : même
  barème, les deux camions encaissent à la partie touchée (de face à 15 m/s
  chacun : -29 PV par tête) ; rien sous 4 m/s (coude à coude, frottement).
- `[x]` **Carcasse sur la route** : à 0 PV, la tête explose et sa carcasse
  calcinée reste en place (`TruckWreck`, 60 PV, obstacle), avec la remorque
  attelée et ses PV restants ; le joueur réapparaît 3 s plus tard sur un
  camion neuf, à côté de ce qui encombre la route.
- `[x]` **Carrosserie déformable** (`BodyDamage`, `Debris`) : la tôle
  s'enfonce au point touché (jusqu'à 45 cm), maillages subdivisés au premier
  choc pour que les grands panneaux plient, sans fente ; au-delà de 9 m/s, les
  pièces extérieures proches s'arrachent (rétros, phares, pare-chocs...) et
  des éclats de tôle volent ; à l'explosion, tout ce qui dépasse part.
  Préparation au sas READY (~0,5 s par modèle, une fois) ; un choc coûte
  ~10 ms.
- `[x]` `make test` à 100 % (`truck_damage_split_test`,
  `truck_body_damage_test` ajoutés).

**Rendu réaliste (2026-10-07, demande utilisateur : « améliore les graphismes,
je veux qu'il soit le plus réaliste possible »)** — tout est procédural
(shaders, bruits) : aucun asset tiers, aucun nouveau fichier lourd.
- `[x]` **Bitume** (`asphalt.gdshaderinc`, partagé par les deux chaussées) :
  gravillons effacés au loin (pas de scintillement), ornières de gomme dans
  chaque voie, taches d'huile, rustines, fissures colmatées, salissures le
  long des murs, marquages usés, micro-relief. Cyber City : chaussée
  détrempée, flaques miroir dans les ornières, gouttes qui ricochent.
- `[x]` **Ciels** (`sky_day.gdshader`, `sky_night.gdshader`) : plage —
  atmosphère, halo et disque solaire, cumulus éclairés par le soleil ; ville —
  plafond nuageux éclairé par la ville, étoiles dans les trouées. Rendu AgX,
  ombres douces du soleil (`light_angular_distance`), filtrage anisotrope 16x.
- `[x]` **Mer** : eau sombre qui reflète le ciel (Fresnel), houle et clapot
  sur quatre trains d'ondes, moutons au large, écume au rivage.
- `[x]` **Camions** (`TruckMaterials`) : peinture vernie, chrome, métal
  brossé, gomme, plastiques grenés, verre fumé, d'après les noms de matériaux
  des modèles ; textures de bruit en triplanaire. **Phares qui éclairent**
  (`TruckLights`) la nuit : deux projecteurs et deux feux arrière par camion,
  halo dans la bruine (brouillard volumétrique, qualité haute, ≤ 2 vues).
- `[x]` **Pluie** (`RainFx`) autour de chaque caméra à Cyber City ;
  glissières en béton taché / acier rayé et mouillé ; sol de la ville et toit
  du showroom en dalles de béton mouillées ; spectateurs en silhouettes
  (tête, buste, jambes) aux couleurs de vêtements ternes.
- `[x]` Coût mesuré (RTX 5060 Ti, 1920 × 1080, qualité haute) : 4 vues
  5,7 → 5,9 ms par image ; 1 vue 2,2 → 3,5 ms (brouillard volumétrique et
  reflets). `make test` à 100 % (`truck_realism_test` ajouté).
- `[x]` **Camions qui ne font plus jouet** (2026-10-07, « pas qu'ils
  ressemblent à des jouets ») : carrosserie vieillie par la route
  (`truck_body.gdshader`) — boue et poussière au ras du sol, coulures, voile
  d'usure, poussière sur le dessus ; poussière claire à la plage, crasse
  sombre et carrosseries mouillées sous la pluie (`TruckMaterials.
  set_weather`). Peintures d'origine un peu désaturées, jantes en acier peint
  satiné (plus de miroir), phares en verre sur réflecteur (plus de pavés
  blancs). Cônes de flamme figés des cheminées retirés, bavettes derrière les
  roues arrière du tracteur et de la remorque (`TruckDetails`, elles
  s'arrachent dans un gros choc). Coût de rendu inchangé (4 vues : 5,6 à
  5,8 ms par image).
- `[x]` **Têtes et remorques détaillées** (2026-10-07, « rends la tête et les
  remorques plus réalistes », « ajoute des détails surtout sur les remorques,
  inspire-toi d'images en ligne ») : `tools/blender/realisme_vehicules.py`
  (`make vehicules`) écrit des versions `Realiste/` à côté des modèles de
  l'équipe, jamais modifiés. Tête : calandre à grille, phares à
  doubles optiques cerclées, antibrouillards, poignées de maintien,
  pare-chaleur des cheminées, cornets de rétroviseur, garde-boue arrière
  noirs. Remorques : garde-boue cintrés au-dessus de chaque roue (plus de
  planches plates) ; d'après des photos de semi-remorques européennes et les
  règlements ECE (catalogue) : protection latérale R73, réservoirs d'air,
  extincteur, cales de roue, panneau arrière avec plaques R70, disque « 80 »,
  autocollant « ANGLES MORTS ». Détails fusionnés par famille (draw calls) et
  arrachables (`BodyDamage`, préfixe `Detail_`). 4 vues : 5,8 → 6,4 ms par
  image ; un choc sur la carrosserie : 10 → 13 ms.
- `[x]` **Silhouette de cabine** (2026-10-07, « c'est toujours beaucoup trop
  carré ») : la tête est remodelée par un champ de déformation doux
  (`reshape_cab`) — coins avant arrondis de 28 cm au-dessus des roues, face
  avant et pare-brise inclinés (46 cm de recul en haut du pare-brise en jeu),
  toit bombé, flancs rentrants de 7 %, pare-chocs enveloppant ; autocollants
  et logos déplacés d'un bloc. Le pare-soleil, devenu une casquette sur un
  pare-brise incliné, est retiré. Caisses de remorques gardées droites
  (conteneur, bétaillère, fourgon : des boîtes dans la réalité). Rendu
  inchangé (4 vues : 6,4 ms par image), aucun pneu traversé.
- `[x]` **Cicatrices au lieu de traits blancs** (2026-10-07, « des sortes de
  traits blancs [...] pas très réaliste, quitte à avoir des vraies
  cicatrices ») : les décalques d'éraflures sont remplacés par des
  cicatrices peintes dans la carrosserie (`BodyScars`, `truck_body.gdshader`,
  8 par maillage, paramètres d'instance) — peinture ternie et rayée dans le
  sens du frottement, éclats à bord déchiqueté laissant voir l'apprêt et la
  tôle nue, traces noires, suie au centre des gros chocs. Un nouveau choc
  agrandit la cicatrice voisine ; tout s'efface à la réapparition.
- `[x]` **Cyber City lisible** (2026-10-07, « Night City est trop sombre, la
  vision est compliquée ») : 88 lampadaires LED le long de la piste
  (projecteurs sans ombre, mâts en MultiMesh, aucun au-dessus d'une autre
  partie de la piste), lumière ambiante × 2, exposition 1,15 → 1,6, lune
  0,45 → 0,85, bitume mouillé un peu moins noir. 4 vues : 6,3 ms par image
  (inchangé).
- `[x]` **Virages** (2026-10-07, « mieux tourner sans déraper ») :
  adhérence latérale 0,9 → 0,99 g (haut de la tolérance de VEHICLE_SPEC §6),
  pneus plus vifs (saturation à 5° au lieu de 6°), direction plus rapide
  (5°/tick). Mesuré : 0,877 → 0,961 g, rayon mini à 50 km/h 21,6 → 19,7 m
  (`make baseline`). Puis cible relevée à ~1,15 g (accord de l'utilisateur,
  2026-10-07) : adhérence 1,19 g, mesuré 1,145 g, rayon mini 16,4 m.
- `[x]` **Pneus qui éclatent** (2026-10-07, « quand un pneu est touché, il
  éclate, on perd en adhérence, en maniabilité ») : un choc de côté à hauteur
  de roue, à plus de 7 m/s vers l'obstacle (mur, camion, remorque larguée,
  épave), fait éclater le pneu de ce côté et de cet essieu
  (`TruckTires.wheel_hit`) ; un choc frontal ou un frottement, non. La roue
  garde 45 % de son adhérence latérale, sa jante freine (3 m/s²) et le coin
  descend de 18 cm (`VehicleTuning`, groupe « Pneu éclaté », `debug_tire_burst`).
  Mesuré (`tire_burst_test`) : plein braquage 30 % de virage en moins, le
  camion tire de 5° du côté crevé en 5 s, 13 % de vitesse en moins. Pneu
  écrasé sous la jante et déchiré (`truck_body.gdshader`, `tyre_burst`),
  détonation, fumée, lanières de gomme. Pneus neufs à la réapparition.
  Remorque (« fais aussi éclater les pneus de la remorque ») : un choc de côté
  sur l'arrière de la caisse, à ±2,6 m du train de roues, fait éclater les
  pneus de ce côté (`TruckTires.trailer_hit`, `Truck.TRAILER_LEFT/RIGHT`).
  Sa jante freine sous le train de roues, la remorque chasse et se balance
  plus (×1,6), l'arrière du tracteur garde 80 % d'adhérence par côté crevé.
  Mesuré : l'ensemble tire de 4,5° en 5 s, 13 % de vitesse en moins, la
  remorque balaie 13° contre 8,5° en entrée de virage. Les pneus de ce côté
  de chaque essieu s'écrasent (`tyre_side`), la remorque penche ; ils partent
  avec la remorque larguée, la suivante arrive neuve.
- `[x]` **Relief des matières** (2026-10-07, objectif « modèles plus lisses et
  réalistes, avec des détails en relief ») : `truck_body.gdshader` dessine
  un relief procédural par matière (`TruckMaterials._relief_of`), ses axes
  mesurés par maillage (`_set_relief_frame`) — tôle ondulée trapézoïdale des
  conteneurs ISO (ondes de 28 cm, 3,6 cm de creux, toit en ondes larges,
  portes comprises), sculptures des pneus (4 rainures en zigzag, lamelles en
  quinconce, flancs nervurés), cordons de soudure des viroles de citerne,
  lames nervurées de la bétaillère, plis de bâche ; la crasse se loge dans
  les creux, le relief s'efface au loin (pas de scintillement). Matières
  jusque-là oubliées : caisse du conteneur, inox poli de la citerne, bâche,
  bandes réfléchissantes, extincteurs, tuyaux. 4 vues : 6,3 → 6,5 ms par
  image.
- `[x]` **Pièces plus lisses** : normales pondérées par l'aire après chaque
  chanfrein (plus de dégradé qui « gonfle » les faces planes) ; les châssis
  et caisses fusionnés des remorques, jusque-là laissés à arêtes vives
  (sommets dédoublés par l'export glTF, pièces trop lourdes), sont recousus
  et chanfreinés (7 mm), avec un plafond de triangles par pièce. Têtes
  ~125 k triangles, remorques 51 à 150 k ; 4 vues : 6,5 ms par image.
- `[~]` **Modèles plus réalistes, passe 2** (2026-10-07, « tu peux refaire des
  modèles 3D ou modifier ceux existants » ; objectif « ne t'arrête pas tant
  que les modèles ne sont pas vraiment plus réalistes ») :
  - `[x]` tracteur : calandre à lames dans un entourage chrome (plus de
    gaufrier), phares à réflecteurs en cuvette et feu de jour, pare-soleil,
    prise d'air, réservoirs alu sanglés entre marchepieds et roues arrière ;
    arrière (vu dès qu'on largue la remorque) : lunette cerclée de noir,
    flexibles d'air spiralés rouge et bleu sur leur potence, sellette avec
    gorge d'attelage, rampes et poignée de verrouillage ;
  - `[x]` semi-grue refaite : tourelle profilée à ouïes, cabine de grutier
    vitrée, contrepoids en dalles, flèche à profil arrondi (bagues, tête à
    poulie, câble, moufle, crochet), vérin fût + tige, stabilisateurs à
    vérins et patins ronds, caisson nervuré ;
  - `[x]` fourgon incendie : vrais rideaux roulants (lames de 5 cm en relief,
    matière `Volet_Roulant`), barre basse à poignée, coffre d'enroulement ;
  - `[x]` porte-engins : chariots élévateurs générés (celui du fichier était
    un jouet en boîtes) - contrepoids arrondi, protège-conducteur tubulaire à
    toit à lames, mât à deux montants (vérin, chaînes), dosseret, fourches,
    bandages pleins, siège, volant, bouteille de gaz, phares, gyrophare ;
  - `[x]` porte-voitures : sangle d'arrimage jaune sur chaque roue des
    voitures (par-dessus le pneu, tendue au plancher, cliquet), vérin de
    levage (fût, tige chrome) contre chaque poteau du cadre ;
  - `[x]` matières : plus de « camouflage » sur les toits et les tôles d'alu -
    la poussière du dessus et le voile d'usure suivaient un bruit à plaques
    de 3 m (mat et brillant en nuages) ; film presque uniforme au grain fin ;
    alu brossé à stries fines et serrées ;
  - `[x]` bétaillère : portes arrière ferrées (quatre barres de verrouillage
    chromées à poignée et cames, gonds sur les deux bords), posées sur les
    grandes faces arrière (pas sur le panneau au-dessus du toit).
- `[x]` **Remorques creuses, percées par les chocs** (2026-10-07, « que les
  remorques soient vides : dès qu'elle s'abîme, ça fait des trous dans la
  coque pour qu'on puisse voir à l'intérieur ») : la carrosserie des
  remorques passe par `truck_body_hollow.gdshader` (même matière, vue des
  deux faces). Au cœur d'une cicatrice grave (gravité locale > 0,6 : choc
  violent, ou chocs répétés au même endroit ; 0,74 depuis les chocs irréguliers), la coque est découpée à bord
  déchiqueté, lèvre de tôle nue puis bord noirci ; par le trou, l'intérieur
  vide de la coque (apprêt sombre). La paroi d'en face (au-delà de 1,2 m le
  long de la normale) n'est jamais percée par le même choc. Le tracteur reste
  plein.
- `[x]` **Tôle fatiguée** (2026-10-07, « plus on tape sur une paroi d'une
  remorque ou du camion, plus elle se déforme, en s'enfonçant ») : chaque coup
  près d'un creux déjà là l'enfonce 50 % de plus par coup reçu (jusqu'à ×3)
  et un peu plus large (`BodyDamage`, `META_HITS`). Mesuré
  (`truck_body_damage_test` F, quatre coups à 4 m/s au même endroit) : creux
  de 6, 14, 25, 37 cm, chaque coup creuse plus que le précédent. Le trou de
  la coque se mesure dans le plan de la paroi : la tôle enfoncée se
  déchire au lieu de s'éloigner du point d'impact.
- `[x]` **Chocs de forme irrégulière** (2026-10-07, « les dégâts sur les côtés
  des remorques sont des ronds trop parfaits ; plutôt des trous moins
  réguliers ou enfoncer la coque ») : creux (`BodyDamage`), cicatrices et
  trous (`truck_body.gdshaderinc`, `scar_dist`) prennent une forme propre à
  chaque choc, tirée de son point d'impact : ovale couché, bord lobé, plis en
  travers du creux ; le trou a un bord échancré et se fend en étoile. La coque
  d'une remorque s'enfonce 1,6 fois plus que la cabine
  (`TRAILER_DENT_MULT`) et ne se perce qu'au-delà d'une gravité locale de
  0,74 (au lieu de 0,6). Le creux se calcule sur la tôle au neuf : un
  nouveau coup creuse toute la zone. Mesuré (`truck_body_damage_test`) :
  creux de 9, 24, 43, 68 cm en quatre coups à 4 m/s sur la citerne ; un choc
  de plus coûte 19 ms (15 ms avant, seuil 25).
- `[x]` **Pneus plus résistants, jante à nu qui crache des étincelles**
  (2026-10-08, « les pneus éclatent trop facilement, il faut plusieurs coups ;
  quand il explose, qu'on voie vraiment la jante ; des étincelles entre la
  jante et le sol quand on roule ») : chaque choc qui vise un pneu l'use de 1
  (au seuil) à 1,5 (choc violent), il éclate à 3 : trois coups, deux au
  moins (`TruckTires.take_hit`) ; usure remise à zéro à la réapparition
  (remorque larguée : la sienne). Pneu éclaté : la gomme explose en dix
  morceaux projetés tout autour du pneu (« pas de débris de pneu sur les
  roues, elle part en morceaux »), plus rien ne reste sur la roue, la
  jante à nu pose sur la route (descente visuelle au-delà de
  `tire_burst_drop_m`, la physique ne change pas). Au sol et au-dessus de
  2 m/s, gerbe d'étincelles sous la jante, vers l'arrière, plus vive avec
  la vitesse ; sur la remorque, tout le train de roues
  (`tire_burst_test` H, I).
- `[x]` **Tête du camion : roues et relief** (2026-10-09, « que ses roues
  ressemblent plus aux roues de la remorque, moins plates ; un peu plus
  détaillées, les textures avec plus de relief sur la tête ») :
  - roues refaites par `realisme_vehicules.py` (`rebuild_wheels`) comme
    celles du catalogue : pneu aux flancs bombés, épaulements arrondis,
    bande à deux rainures ; jante emboutie en cuvette, dix ajours, moyeu
    saillant, dix écrous (le voile plat au ras du pneu a disparu). Même
    rayon, même largeur, même centre : pivot, roulement, passages de roue
    et pneu éclaté inchangés (fût de jante à 0,6 × le rayon) ;
  - matières en relief posées sur les pièces (`RELIEF_PARTS`) et dessinées
    par `truck_body.gdshaderinc` (`head_relief`) : marchepieds alu et
    plateau arrière en tôle larmée, pare-chaleur des échappements en tôle
    perforée, calandre et prise d'air en nid d'abeille, longerons percés et
    boulonnés ; trous noirs, motifs fondus au loin (pas de crénelage) ;
  - plastiques moulés grainés (pare-chocs, garde-boue, rétroviseurs), peau
    d'orange plus fine sur la peinture ;
  - inchangé, vérifié en jeu et par les tests : dégâts (creux, cicatrices),
    débris `Detail_`, pneus qui éclatent, jante à nu sur la route, fumée.
    `truck_realism_test` vérifie les reliefs et les jantes à ajours.

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

**État au 2026-10-17.** La phase a été prise par un autre chemin que le tableau
ci-dessus, par décision de l'équipe (`docs/ART_PIPELINE.md` §4 bis à 4 quater) :

- 5.1, 5.2, 5.5 : les camions sont les **modèles de l'équipe**
  (`Assets_Visuels/`, Git LFS depuis le 2026-10-02), recalés sur
  `VEHICLE_SPEC` en jeu par `TruckVisual`. `make vehicules` en dérive le
  catalogue de remorques et les versions réalistes
  (`catalogue_tete_commune.py`, `realisme_vehicules.py`) ;
  `build_truck.py` n'a donc pas été écrit ;
- 5.3, 5.4 : les pistes et le décor sont **générés par le code dans Godot**
  (`track_blockout.gd`, `race_decor.gd`, `city_builder.gd`) ; aucune
  piste Blender ;
- 5.6 : les tests de conduite passent inchangés (`make test` : 66/66).

Mesuré le 2026-10-17 sur la machine de référence : `make assets` 30 s (rien à
générer, `build_all.py` est vide) + `make vehicules` 92 s = **2 min 2 s**, à la limite de la cible (< 2 min ; les 30 s sont surtout le démarrage de Blender),
sans erreur (un avertissement de Blender 6.0 : `mat.use_nodes` déprécié).
Les `.glb` versionnés sont ceux de l'équipe, par Git LFS (exception de
`CLAUDE.md` §8). Reste ouvert : faut-il que `make assets` appelle
`make vehicules` (il réécrirait alors les binaires LFS à chaque passage) ?
Question pour l'équipe.
**Critères de sortie**
- `make assets` régénère tout l'art depuis zéro en < 2 min.
- Les tests de conduite passent sans qu'aucun seuil ait été touché.
- Budgets respectés ; aucun `.glb` dans le dépôt.

---

## Phase 6 — Online host-autoritaire

Lire `docs/NETCODE.md` avant de commencer.

| # | Tâche | Agent |
|---|---|---|
| 6.1 | Transport ENet, host/join par IP, lobby (`[x]` 2026-10-16 : `NetSession`, panneau EN LIGNE du menu, `net_session_test` ; `NetRace` : NETCODE.md §11) | netcode-engineer |
| 6.2 | `RemoteInputSource` : inputs groupés par 3, 20 Hz (`[x]` 2026-10-16 : fronts ni perdus ni répétés, `net_protocol_test` ; le 2026-10-17, 3 frames par paquet mais un paquet par tick) | netcode-engineer |
| 6.3 | Snapshots d'état quantifiés, acquittés par le client (`[x]` 2026-10-17 : `TruckState` 36 o ; acquittement des inputs (`ack`) ; pas de delta, donc pas d'acquittement de snapshot, NETCODE.md §3) | netcode-engineer |
| 6.4 | Camions distants interpolés ; camion local prédit puis corrigé en douceur (`[x]` 2026-10-17 : délai minimal, NETCODE.md §11) | netcode-engineer |
| 6.5 | Contacts entre camions arbitrés par le host (`[x]` 2026-10-17 : le host décide dégâts, épaves, largages, barils ; chez les clients, camions proches en corps dynamiques menés, NETCODE.md §11 ; à confirmer sur 2 PC) | netcode-engineer |
| 6.6 | Déconnexion, écran « connexion perdue » (`[x]` 2026-10-17 : abandon, coupure détectée en 3-8 s, NETCODE.md §11) | netcode-engineer |
| 6.7 | Tests avec latence et perte simulées ; mesure de la bande passante (`[x]` 2026-10-17 : 0 à 300 ms, 0 à 5 %, `baseline.json` ; essai sur 2 PC à faire) | godot-qa |

**Critères de sortie**
- 2 machines, 4 joueurs, une course complète.
- À 150 ms de latence et 2 % de perte, le camion local reste agréable à conduire.
- Bande passante montante du host < 128 kbps à 4 joueurs, en-têtes compris.

État au 2026-10-17 : course complète à 2 joueurs mesurée sur 1 PC (deux instances), pas encore sur 2 machines ni à 4 ; à 150 ms et 2 %, le camion local répond au tick de l'appui (prédit), corrigé en douceur ; montant du host à 4 joueurs : 289 kbps à 60 Hz (choix « moins de délai »), 96 kbps à 20 Hz (option « connexion lente ») : le seuil de 128 kbps n'est tenu qu'à 20 Hz, à trancher par l'équipe.

---

## Phase 7 — Polish et build

| # | Tâche | Agent |
|---|---|---|
| 7.1 | Menu principal, options, remapping (`[x]` 2026-10-17 : options sauvegardées d'un lancement à l'autre - son, volume, qualité, compteur, résolution dynamique, circuit, vitesse, remorques - et réaffectation des boutons de la manette, `settings_remap_test` ; clavier non réaffectable ; écran de chargement avant chaque course, le départ attend qu'il s'efface - `loading_screen_test`) | gameplay-engineer |
| 7.2 | Personnalisation des camions (couleurs, pièces générées) (en attente : décision de l'équipe, 2026-10-17) | blender-modeler |
| 7.3 | Sons et musique complets (`[~]` musique de course procédurale `RaceMusic`, 2026-09-30 : boucle arcade de 16 mesures à 150 BPM, du GO à l'arrivée ; bips du menu et du départ ; bruitages du camion - moteur, crissement, chocs, klaxon, nitro, pneu crevé - et explosions ; 2026-10-17 : carillon de tour, annonce du dernier tour, fanfare d'arrivée (`RaceSound`), sellette au largage, `race_sound_test` ; ambiance des circuits - pluie et ville, vagues et vent (`AmbienceSound`, `ambience_test`) ; rumeur 3D de chaque tribune, clameurs et sifflets (`CrowdSound`, `crowd_sound_test`) - `[x]`) | — |
| 7.4 | Juice complet (particules, ralentis d'arrivée) (`[x]` particules : poussière, gerbes d'eau, étincelles, fumée et débris des dégâts, explosions - phases 3 et 4.5 ; ralenti d'arrivée le 2026-10-17 : 0,3 pendant 0,7 s puis retour en douceur, hors ligne, `finish_slowmo_test`) | gameplay-engineer |
| 7.5 | Pistes supplémentaires (en attente : tracé et ambiance à décider par l'équipe, 2026-10-17) | track-designer |
| 7.6 | Profilage et optimisation (`[x]` passes du 2026-10-09, du 2026-10-17 et du 2026-10-18 ci-dessous : plus de gel au-delà de 50 ms en course à 4 joueurs) | godot-qa |
| 7.7 | Export Windows/Linux, test sur machine vierge (`[~]` 2026-10-17 : `make export` produit les deux en 16 s, modèles copiés à côté ; Windows lancé sur la machine de référence : menu, page de sélection et course Cyber City avec les modèles de l'équipe ; reste : Linux et une machine vierge) | godot-qa |

**Optimisation, passe 1** (2026-10-09, « gros problèmes de performance sur
les petites configurations ; optimise sans forcément diminuer la qualité ») :
mesure d'abord (course réelle, camions lancés à 90 km/h, 600 images,
RTX 5060 Ti en 1080p). Les scripts et la physique ne coûtent que 0,3 à
1,5 ms par image : tout le poids était dans le rendu.
- **Niveaux de détail des camions** : les modèles, chargés à l'exécution
  sans l'import de l'éditeur, n'en avaient aucun (125 à 150 k triangles
  dessinés en entier à 50 m, ombres comprises). Générés au chargement
  (`TruckVisual._generate_lods`, +0,5 s une fois par modèle).
- **Silhouettes d'ombre** (`ShadowProxy`) : 8 600 des 12 000 appels de
  dessin à 4 joueurs étaient les ~140 pièces de chaque camion redessinées
  dans les 4 cascades d'ombre de chaque vue. Carrosserie, remorque et
  jantes projettent leur ombre par un maillage fusionné ; une pièce arrachée
  rend leur ombre aux pièces de sa partie. Image identique (vérifiée).
- **Distance d'affichage par pièce** : au-delà d'un pixel et demi, une
  pièce n'est plus envoyée au rendu ; intérieur de cabine au-delà de 30 m.
- **Foule** : 3 000 spectateurs à ~160 triangles (493 k, plus que tout le
  décor) ; un tronc de cône à anneaux là où le shader façonne la tête :
  56 triangles, même silhouette.
- **Éclairage global à demi-résolution** (−0,3 ms, invisible) ; **ombre du
  soleil en 2 cascades à partir de 3 vues** (vues de 960 × 540 : −26 %
  d'appels de dessin à 4 vues).
- **Qualité au lancement selon la carte graphique** : haute sur carte
  dédiée, moyenne sur puce intégrée, basse en rendu logiciel
  (`GraphicsSettings.default_quality`, modifiable dans les paramètres).
- Mesuré à 4 joueurs (Cyber City) : appels de dessin 11 740 → 3 769,
  triangles 11,9 M → 2,8 M, CPU de rendu 4,6 → 3,0 ms, GPU 7,2 → 6,1 ms,
  125 → 152 images/s ; à 1 joueur 191 → 206 images/s.

**Optimisation, passe 2 : résolution dynamique** (2026-10-09, « continue
l'optimisation pour des petites config avec GPU intégré tout en conservant le
plus possible les graphismes ») : en qualité moyenne (celle d'une puce
intégrée), on a coupé chaque effet tour à tour à 1080p : SSAO 27 % du temps GPU,
MSAA 11 %, flou lumineux 7 %, lumières 9 %, ombres 10 % ; SSAO ou ombres en
qualité réduite : moins de 2 %. La résolution de la 3D, elle, compte d'un
bloc : 77 % → −27 %, 67 % → −39 %. D'où `DynamicResolution` (case
« Résolution dynamique » des paramètres, active par défaut) : tous les effets
restent ; la 3D garde sa pleine résolution tant que le GPU tient 60 images/s,
et ne descend (FSR 1, jusqu'à 60 %) que s'il décroche ; l'interface reste
nette. Vérifié en course avec un budget abaissé pour simuler une petite
carte : 1 vue 2,9 → 1,9 ms (3D à 75 %), 4 vues 5,2 → 3,6 ms (65 %) ; 3 à 4
changements d'échelle au départ, puis plus aucun. Le compteur FPS affiche la
résolution 3D quand elle est baissée.

**Optimisation, passe 3 : à-coups** (2026-10-17, machine de référence,
Iris Xe, course réelle à 4 joueurs, réglages par défaut, budget du spike V3
fusionné) : 56,5 → 59,1 images/s, 1 % bas 7,5 → 18, pire image 370 → 92 ms,
99ᵉ centile 54 → 34 ms.
- **Préchauffe des effets** (`FxWarmup`) : la première explosion de baril
  compilait 9 pipelines (370 ms) ; une vue cachée filme une explosion, un
  KABOOM, des étincelles, une fumée et un débris au chargement. Plus aucune
  compilation en course.
- **Destruction étalée** : les 4 bosses de la cabine (`BodyDamage.dent`,
  ~38 ms chacune) se posent une par image au lieu d'un gel de 190 ms
  (`wreck_dent_spread_test`).
- **Copie de la carrosserie préparée au chargement** (`BodyDamage.prewarm`
  `own`) : ~70 ms et 15 Mo par camion, −45 ms au premier choc dur.
- **Passe 4 (2026-10-18) : creux asynchrones** (`BodyDamage.async_dents`, en
  jeu seulement) : les deux passes d'un creux (forme, normales) tournent sur
  la moitié des cœurs pendant que le jeu dessine ; la pièce prend sa forme 1
  à 3 images plus tard, au sommet près comme en synchrone, deux creux de la
  même pièce enchaînés (`async_dent_test`). Choc dur sur la cabine : 37 ms
  bloqués + 74 ms à l'image suivante → 14 à 19 ms + 30 à 55 ms. Course à
  4 joueurs, mêmes conditions : pire image 120 → 48 ms, 1 % bas 12,8 →
  22,4 images/s.
- Reste : la collecte des cellules d'un creux (GDScript, thread principal,
  ~4 ms par pièce touchée).

---


## Phase 7.8 — Retours de test (2026-10-19)

Liste remontée après les essais multijoueur ; un lot par branche et par PR
(#45 à #53, empilées sur #44), un test chacun, `make test` vert à chaque lot.

- [x] **Sélection en ligne** : CHOISIR MON CONVOI ouvre la page de sélection du
  solo ; remorque et pouvoirs partent au lobby (`NetSession.set_loadout`,
  protocole 3), LANCER attend que tous soient PRÊTS (`net_loadout_test`).
- [x] **Pouvoirs chez les clients** : chaque tir du host part en `Ev.POWER`,
  rejoué en miroir chez les clients sans dégât ; HUD client
  (`net_powers_test`).
- [x] **Fin de course sans gêne** : après la 1re arrivée, ceux qui roulent ont
  un bandeau en haut, plus de carte au centre (`finish_overlay_test`).
- [x] **Délai en ligne** : file d'inputs du host adaptative (1 frame sur une
  liaison régulière), rendu des autres camions selon la gigue, pouvoirs du
  joueur local prédits (`net_latency_test`). Essai 2 instances headless : OK.
- [x] **Robustesse du chargement en ligne** : un client s'annonce prêt une fois
  son écran de chargement levé ; détection de coupure rapide seulement après
  le sas READY ; délai de chargement 15 à 60 s. `BodyDamage` garde les
  tableaux subdivisés au lieu de les relire au serveur de rendu (index faux
  sous forte charge : 65535 pour 61 256 sommets).
- [x] **Essai sur 2 vrais PC** — reporté (décision du 2026-10-19), à faire par l'équipe ; confié le 2026-10-19 (hors de portée d'un seul PC ; liste des points à vérifier dans la PR #54) : sur 1 PC, deux instances affichées
  se figent jusqu'à 16 s en créant la course et la liaison tombe ; en
  headless, tout passe.
- [x] **Sortie de route** : hors piste, le camion tombe et explose au premier
  contact, épave puis réapparition ; en l'air, une trajectoire qui franchirait
  le mur est rabattue (`AutoReset.air_return`, METRICS inchangé) ; corrigé :
  coup de lacet de 14° à chaque réapparition (`air_return_test`,
  `track_01_reset_test`).
- [x] **Bots** hors ligne, 0 à 5, facile / moyen / dur (`BotInputSource`,
  `bot_race_test`).
- [x] **Bots plus forts** (2026-10-20, « même en dur ils sont faciles à
  battre ») : ligne de course calculée à courbure minimale, sur les pads
  utiles et à côté des sauts et flaques (`RacingLine`, `bot_line_test`) ;
  profil de vitesse freinable ; trafic : dépassement du côté libre, suivi,
  côte à côte, contournement des obstacles arrêtés, relance en travers.
  Corrigé au passage : une remorque au-dessus du mur intérieur faisait
  exploser un camion resté sur la route (`AutoReset._past_wall`). Banc :
  `dev/bot_bench.tscn`. Dur seul, tour lancé : Cyber City 78,7 → 73,8 s,
  Playa 68,9 → 63,7 s, Sakura 75,7 → 67,8 s ; à 5 bots, plus aucune chute
  (avant : jusqu'à 11 sur Sakura).
- [x] **Retours d'essai** (2026-10-20) :
  - aide qui rabattait un camion en l'air vers la piste retirée (`air_return_test`) ;
  - bouclier : plus de creux, de pièces arrachées ni d'usure des pneus, même
    en collant un mur (sans bouclier : inchangé) ;
  - baril : tôle enfoncée du côté de l'explosion (`damage_guard_test`) ;
  - bots : ligne la plus rapide (tour estimé, `RacingLine.SMOOTH_M`), qui
    contourne les barils ; ils gardent l'élan des pads ; esquive des remorques
    larguées et des épaves selon leur gabarit (`bot_avoid_test`).
  - Dur seul, tour lancé : Cyber City 73,8 → 68,4 s, Playa 63,7 → 58,5 s,
    Sakura 67,8 → 66 s.
- [x] **Pouvoirs, 2e série** : mitrailleuse, scie géante, boomerang aimanté
  (`powers2_test`).
  - Scie (2026-10-20, « pas vraiment de portée ») : lames à plat à hauteur des
    pneus, ~2,7 m au-delà du flanc, sur tout le flanc du tracteur ; elles
    tranchent les pneus d'à côté (éclatés en ~0,4 s) et la remorque par son
    train de roues.
- [x] **Pouvoirs : remorques et dégâts visuels** (2026-10-20, « tout ce qui
  est capacité puisse endommager les remorques et les camions, en plus des PV
  de manière visuelle ») : chaque coup (missile, laser, mitrailleuse, scie,
  boomerang) retire ses PV à la partie touchée, tête ou remorque, et marque la
  tôle (traces, creux, pièces arrachées selon la force ; rien sous bouclier)
  (`powers_test`, `powers2_test`).
- [x] **Boomerang** (2026-10-20, « il ne va pas très loin, il revient sans
  faire grand-chose ») : vitesse comptée par rapport au tireur, portée 85 m,
  aimanté sur le camion visé à l'aller ; il le traverse, fait demi-tour et
  repasse dessus (2 coups), puis revient (`boomerang_test` : cible à 60 m,
  tous deux à 126 km/h ; l'ancien ne la touchait pas).
- [x] **Visée automatique** (2026-10-20, « que ça vise la personne la plus
  proche devant soi ») : laser et mitrailleuse visent seuls le camion le plus
  proche devant (cône du missile), comme missile et boomerang ; droit devant
  sans cible (`auto_aim_test`).
- [x] **Caméra : regard** (2026-10-20, « bouger légèrement la caméra avec le
  joystick droit... pas une énorme amplitude ; L1 pour regarder derrière ») :
  stick droit, 30° de cap et 10° d'inclinaison au plus, amorti ; L1 tenu
  (clavier : B / Fin) retourne la vue. Le klaxon passe de L1 à L3 (un ancien
  profil réaffecté migre seul). Local, hors `InputFrame` (`camera_look_test`).
- [x] **Cible au choix** (2026-10-20, « une petite cible rouge sur la personne
  qui va prendre le missile, une touche pour changer, en cycle ») : viseur
  rouge sur le camion visé (`TargetReticle`, vif si un pouvoir qui vise est
  prêt) ; flèche haut de la croix (clavier T / J) : cible suivante parmi les
  camions devant, du plus proche au plus loin puis retour. Bit `target_next`
  de l'`InputFrame` : le host vise le même camion (`target_cycle_test`).
- [x] **Remorque en priorité** (2026-10-20, « le pouvoir vise en priorité la
  remorque, pour pénaliser les joueurs qui n'en ont pas ; ça diminue
  fortement les dégâts faits aux camions qui tractent ») : missile,
  boomerang, laser, mitrailleuse et viseur visent la remorque d'un camion qui
  tracte ; elle encaisse les PV de chaque coup, la tête touchée n'en prend que
  20 % (`TOWING_CAB_SHARE`). Sans remorque : tout sur la tête
  (`power_trailer_test`).
- [x] **Remorques larguées** (2026-10-20, « des dégâts au même titre que les
  attelées, même visuels ; augmenter leurs PV ; se casser en morceaux, faire
  un trou en rentrant dedans ; très abîmée, elle explose ») : PV ×2
  (`ROAD_HP_MULT`) ; missile, laser, mitrailleuse, scie et boomerang les
  touchent (PV, traces, creux) ; panneaux arrachés tous les 20 % de PV
  perdus ; un choc de camion retire au plus 45 % ; sous 60 % un camion qui
  fonce dedans la perce et la traverse ; à 0, elle explose
  (`road_trailer_test`).
- [x] **Largages limités** (2026-10-20, « limiter le nombre de largages par
  joueur, le choisir au début d'une course, entre 0 et 5 ; un délai d'une
  vingtaine de secondes une fois la remorque revenue ») : ligne LARGAGES du
  menu (0 à 5, 3 par défaut, `GameState.trailer_drops`, envoyée par le host en
  ligne) ; `TruckCargo.drops_left` posé au GO ; 20 s (`rearm_ticks`) après
  le retour d'une remorque ; HUD « largage dans N s », « PLUS DE LARGAGE »
  (`trailer_drops_test`).
- [x] **Retour de coup et portée** (2026-10-20) : chaque coup qui touche
  (camion ou remorque larguée) → chiffre de dégâts qui monte de la cible
  (« BLOQUÉ » sous bouclier ; rafale et laser cumulés), croix sur le viseur,
  son ; bip au changement de cible. Viseur : rouge si un pouvoir prêt
  l'atteint, gris hors de portée, terne en recharge ; flèches ◄ ► par
  emplacement, distance dessous (`hit_feedback_test`).
- [x] **Bots tactiques** (2026-10-20, « larguer la remorque au bon moment,
  juste avant un virage, avec un poursuivant collé derrière ; bouclier quand un
  missile arrive ») : bouclier sans temps de réaction quand un missile ou un
  boomerang qui le vise est à moins de 25 m (moyen) / 40 m (dur), ou qu'un
  laser le touche ; largage quand un camion le suit dans sa voie juste
  derrière sa remorque (moyen), et seulement avant un virage de moins de
  150 m de rayon (dur). Jamais en facile (`bot_tactics_test`).
- [x] **HUD** (2026-10-20) : pouvoir actif, pastille verte qui se vide avec
  l'effet, puis la recharge.
- [x] **Menu** : boutons 1 à N des joueurs à la couleur de leur pastille
  (`menu_players_test`).
- [x] **HUD de course** : cadran façon arcade (vitesse, nitro, cargo, recharges
  des pouvoirs, `HudDial`) et carte en haut à gauche (position, nom, tour,
  temps, PV) (`race_hud_test`).
- [ ] À valider en jeu par l'équipe : équilibrage des nouveaux pouvoirs et des
  niveaux de bots, lisibilité du HUD à 5-6 joueurs.

## Questions de design ouvertes

À trancher par l'équipe ; chacune deviendrait une phase à part entière, pas un
ajout discret au milieu d'une autre.

- **IA / adversaires pilotés par l'ordinateur.** Bots hors ligne livrés le
  2026-10-19 (phase 7.8) ; en ligne : pas encore.
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
