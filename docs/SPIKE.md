# SPIKE.md — Acquis techniques et hypothèses à valider

Ce document a deux parties :

1. **Les acquis** : ce qui a été mesuré sur ce moteur et reste valable. Ils
   viennent en partie de l'ancien projet (combat en ragdoll, archivé par le tag
   `archive/ragdoll-brawler`) : la physique Jolt, le socle de tests et le
   pipeline Blender sont les mêmes. Chaque acquis indique la version sur
   laquelle il a été mesuré.
2. **Les hypothèses** propres au camion, à valider en **phase 0.5** avant
   d'écrire la moindre ligne de physique de production.

**Règle : tant qu'un spike n'a pas répondu, le code de production qui en dépend
ne s'écrit pas.** Un spike produit des réponses et des corrections de
documents, pas du code : son code vit dans `spike/` (git-ignoré) et est supprimé
à la fin (`make clean-spike`).

---

## Partie 1 — Acquis

| # | Acquis | Mesuré sur | Conséquence |
|---|---|---|---|
| A1 | Jolt laisse un corps au repos s'enfoncer de `penetration_slop` = **0,02 m** | 4.6.3, **revérifié 4.7.2** | les hauteurs absolues au repos en tiennent compte ; `make test-selftest` le revérifie |
| A2 | En headless, le temps mural vaut **16,67 ms/tick quelle que soit la charge** : Godot régule à 60 Hz | 4.6.3 | mesurer la perf avec `Performance.TIME_PHYSICS_PROCESS`, jamais le temps mural. Le runner lance donc les tests avec `--fixed-fps 60` (sans attente : suite 10× plus rapide), **sauf** les scènes `perf_*` (A11) |
| A3 | Au démarrage, Godot enchaîne **plusieurs ticks physiques sans rendu** pour rattraper le chargement | 4.6.3 | un test qui observe le rendu n'agit pas avant ~30 ticks |
| A4 | `--quit-after` compte des **itérations**, pas des ticks : ~2,4 par tick sur une scène légère | 4.6.3 | un test long relève `--max-iterations`. Sous `--fixed-fps` (runner, hors `perf_*`), **1 itération = 1 tick** : la garde de 7 200 couvre 7 200 ticks |
| A5 | Joints 6DOF sous Jolt : limites angulaires **honorées** ; `damping`, `restitution`, `force_limit` des limites **ignorés** ; `angular_spring_*` **supporté** ; axes linéaires verrouillés = **soudure parfaite** (0,0000 m de séparation sous 2 000 N) | 4.6.3 | pour une attache souple (remorque, objet traîné) : ressort, pas limite amortie ; une rupture de joint n'est pas observable par la séparation |
| A6 | Export glTF de `tools/blender/lib/export.py` : cube de 1 m mesuré **1,0000 m**, os de 0,40 m mesuré **0,4000 m**, noms conservés | Blender 5.2.1 + Godot 4.6.3 | le contrat d'export tient ; à revérifier pour des roues à pivot (V4) |
| A7 | Sur une même machine, une simulation se rejoue **à l'identique** d'un lancement à l'autre | 4.6.3 | les écarts entre runs viennent d'ailleurs (autre machine, ordre de création) |
| A8 | Une erreur d'exécution GDScript interrompt la fonction mais **pas la scène** : elle peut encore conclure PASS | 4.6.3, 4.7.2 | le runner compte en échec toute sortie contenant `SCRIPT ERROR` |
| A9 | L'exécutable Godot « normal » sous Windows est une appli graphique : **aucune sortie console** | 4.6.3 | le raccourci `godot` pointe vers `…_console.exe` (ENVIRONMENT.md §4.1) |
| A10 | `physics/3d/default_linear_damp` vaut **0,1** par défaut : une traînée cachée. Avec 4,63 m/s² de poussée, vitesse limite 167 km/h et 0 → 100 en 571 ticks au lieu de 360 | 4.7.2 (V1) | le camion est en `linear_damp_mode = REPLACE`, `linear_damp = 0` ; la traînée est explicite dans `VehicleTuning` |
| A11 | Sous `--fixed-fps 60` (simulation sans attente du temps réel), `Performance.TIME_PHYSICS_PROCESS` renvoie **0** | 4.7.2 (V1) | un banc accéléré mesure l'intervalle entre ticks (`Time.get_ticks_usec`), majorant ; la perf de référence se mesure sans `--fixed-fps` |
| A12 | Camion (2 boîtes) contre mur statique : **0 traversée sur 720 essais**, 100 à 200 km/h, murs de 1 à 0,1 m, boîte ou maillage triangulé, 0° ou 20°, avec ou sans CCD. Sans CCD, l'avant s'enfonce d'un tick de trajet (0,87 m à 200 km/h) ; avec `continuous_cd`, 0,10 m, coût non mesurable | 4.7.2 (V2) | `continuous_cd = true` sur le camion ; pas d'épaisseur minimale imposée par le *tunneling* |
| A13 | `transform_apply(location=True)` avant l'export ramène l'origine de chaque objet au centre du monde : pivots de roue à **2,24 m** du moyeu dans Godot. Rotation + échelle seules : **0,0000 m**, noms intacts, avant en −Z | Blender 4.4.3 + Godot 4.7.2 (V4) | `export.apply_transforms()` n'applique plus la location |
| A14 | Un blocage ponctuel (ex. : 12 000 échantillons audio calculés en GDScript à l'apparition de chaque camion) est **rattrapé** ensuite par plusieurs pas physiques par image ; `TIME_PHYSICS_PROCESS` les additionne : la perf mesurée à 4 camions était passée de 1,9 à 4,0 ms, bien après le blocage | 4.7.2 (2026-09-28) | aucun calcul lourd à l'instanciation d'un objet de jeu (le partager, `static`) ; un test de perf écarte le rattrapage, pas seulement les premiers ticks |

Les acquis propres au ragdoll (API de `PhysicalBone3D`, placement par
`bone_rest`, conflit de pose) ne s'appliquent plus ; ils restent consultables
dans le tag d'archive.

---

## Partie 2 — Hypothèses du camion (phase 0.5)

Durée cible : **1 à 2 jours**. Si un spike déborde, c'est qu'il a trouvé un vrai
problème : arrête-toi et remonte-le.

### V1 — Quel modèle de véhicule : `VehicleBody3D` ou suspension maison ?

**Criticité : bloquante.** C'est l'architecture de toute la phase 1.

**Les deux candidats.**

- **`VehicleBody3D` + `VehicleWheel3D`**, fournis par Godot. Rapides à brancher,
  mais leur modèle de pneu est pensé pour une conduite réaliste, et leurs
  réglages se prêtent mal à une conduite arcade (dérapage contrôlé, aide en
  l'air, anti-retournement).
- **`RigidBody3D` + 4 rayons de suspension écrits à la main**, l'approche
  habituelle des jeux de course arcade : chaque force (ressort, traction,
  adhérence latérale) est explicite, donc réglable, désactivable et testable
  une à une.

`docs/VEHICLE_SPEC.md` est écrit pour la seconde. V1 confirme ou infirme.

**Protocole.** Monter les deux sur un sol plat, avec les dimensions et la masse
de `VEHICLE_SPEC.md`, et mesurer :

1. **stabilité à l'arrêt** : 600 ticks sans input → roulis, tangage, dérive ;
2. **haute vitesse** : plein gaz jusqu'à 150 km/h → le camion reste-t-il stable,
   sans tremblement de suspension ?
3. **réception** : lâcher de 2 m → rebonds, NaN, temps avant stabilisation ;
4. **contrôle** : peut-on obtenir un dérapage au frein à main qui se rattrape,
   et empêcher le retournement à plein braquage ?

**Réponse attendue.** Le modèle retenu, et la liste des forces à écrire.

**✅ Réponse (2026-09-26, Godot 4.7.2, 5 runs identiques par mesure) :
`RigidBody3D` + 4 rayons.** Réglage identique pour les deux candidats
(1,6 Hz, ζ = 0,45, longueur libre déduite par essieu) :

| Mesure | Rayons | `VehicleBody3D` converti (s = k/M) | `VehicleBody3D` calibré ×1,5 |
|---|---|---|---|
| Repos 600 ticks : tangage / dérive | 0,0005° / 0,2 mm | 0,30° / 3 mm | 0,03° / 0,2 mm |
| Hauteur de caisse (± 3 cm) | +0,1 mm | **−48 mm** | +0,1 mm |
| 150 km/h : oscillation des moyeux (crête à crête) | 1,4 mm | 0,7 mm | 0,5 mm |
| Chute de 2 m : 4 roues au sol après 1er contact / stabilisé | 0 / +47 ticks | 1 / jamais (hauteur) | 1 / +31 ticks |
| Chute de 2 m inclinée 5° × 5° | +5 / +52 ticks | +5 / jamais | +5 / +34 ticks |
| NaN, châssis au sol | aucun | aucun | aucun |

Les deux modèles sont stables : ce sont les pièges de `VehicleBody3D` qui
tranchent. Sa raideur n'est pas en unités physiques (il n'applique que ~2/3 de
`s·M` : calibration empirique ×1,5 nécessaire), il avance vers **+Z** (la spec
dit −Z), et `suspension_max_force` vaut 6 000 N par défaut, moins que la charge
statique d'une roue avant (14 200 N). Les aides arcade seraient de toute façon
écrites à la main par-dessus.

Forces à écrire, dans l'ordre : suspension (au point d'ancrage, le long de
l'axe du ressort), traction et frein, adhérence latérale pondérée par la charge,
direction réduite avec la vitesse, dérapage, aides arcade, traînée explicite.
Le point 4 du protocole (dérapage, anti-retournement) n'a pas été mesuré : il
devient un test de la phase 1.

Deux corrections découlent du spike : le critère de chute (la chute libre de
2 m dure à elle seule ~38 ticks, « au sol en < 30 ticks » depuis le lâcher était
impossible) et la répartition de charge par essieu (57,9 % à l'avant).

### V2 — Collisions à haute vitesse

**Criticité : haute.** À 160 km/h, un camion parcourt 0,74 m par tick.

**L'hypothèse.** Un mur fin (glissière de 0,3 m) peut être traversé en un tick,
sans qu'aucun contact ne soit détecté (*tunneling*).

**Protocole.**

1. Camion lancé à 100, 150 puis 200 km/h contre des murs de 1 m, 0,3 m et
   0,1 m d'épaisseur. Compter les traversées sur 20 essais par configuration.
2. Refaire avec la détection continue de Jolt (`continuous_cd` sur le corps) :
   les traversées disparaissent-elles, et à quel coût CPU ?
3. Seulement si nécessaire : mesurer le coût d'un tick physique à 120 Hz. C'est
   la soupape de dernier recours (`CLAUDE.md` §6).

**Réponse attendue.** L'épaisseur minimale d'un mur de piste, et le réglage de
détection continue à activer.

**✅ Réponse (2026-09-26, camion à rayons de V1, 20 phases de tick par
configuration) :** aucune traversée, voir l'acquis A12. Le camion est trop
épais (2,4 × 5,8 m) pour passer un mur en un tick. **`continuous_cd = true`**
sur le camion, pour l'enfoncement visible (0,87 → 0,10 m à 200 km/h). Le tick
reste à 60 Hz. Aucune épaisseur minimale physique jusqu'à 0,1 m : le minimum
de piste devient un choix de design (proposé : 0,3 m, la glissière du
protocole), **validé : 0,3 m** dans `METRICS.md` §4. **Non testé :** camion contre
camion (deux corps mobiles), objets fins mobiles.

### V3 — Écran partagé à 4 sur la machine de référence

**Criticité : haute pour la phase 4, et elle peut remettre en cause le renderer.**

**L'hypothèse.** L'écran partagé rend la scène **quatre fois par frame**. Sur un
GPU intégré (Iris Xe, `docs/ENVIRONMENT.md` §1), 60 images/s à 4 écrans n'a
rien d'acquis.

**Protocole.**

1. Une piste de test simple, 4 camions, 1 / 2 / 4 `SubViewport`.
2. Mesurer les images/s et le temps GPU en Forward+, puis en Mobile et en
   Compatibility.
3. Mesurer l'effet des ombres, de la résolution de chaque vue et de la distance
   d'affichage.

**Réponse attendue.** Le renderer retenu, et un budget de rendu chiffré
(triangles, ombres, résolution) pour les pistes et les camions.

**⏳ Non mesuré.** Il faut un vrai rendu, fenêtre ouverte, sur la machine de
référence (Iris Xe) : la machine du spike (Ryzen 7 8845HS / Radeon 780M) ne
permet pas de conclure. Bloquant pour la phase 4, pas pour la phase 1.

### V4 — Export Blender d'un véhicule à roues

**Criticité : moyenne.** Une heure de travail, à faire avant la phase 5.

**L'hypothèse.** L'acquis A6 porte sur un cube et une armature. Un camion est
fait d'objets séparés (carrosserie + 4 roues) dont les **pivots** doivent être
exactement au moyeu, sans quoi les roues tournent autour d'un mauvais point.

**Protocole.** Exporter un châssis et quatre roues nommées selon
`VEHICLE_SPEC.md` §4, importer dans Godot 4.7.2, et vérifier : noms intacts,
origine de chaque roue au moyeu (± 1 mm), rotation d'une roue autour de son axe
sans excentricité, avant du camion vers −Z.

**Réponse attendue.** Confirmation chiffrée, ou la correction à apporter à
`tools/blender/lib/export.py`.

**✅ Réponse (2026-09-26) :** hypothèse confirmée, et corrigée. Avec
`apply_transforms()` tel qu'il était, les pivots des 4 roues arrivaient à
2,24 m du moyeu (acquis A13). `export.py` n'applique plus la location : pivots
à 0,0000 m, excentricité nulle en rotation, noms intacts, avant en −Z. Mesuré
avec **Blender 4.4.3** (la machine du spike n'a pas la 5.2.1) : à revérifier
sur 5.2.1 au premier `make assets` de la phase 5.

---

## Livrable de la phase 0.5

| Spike | Question | Réponse | Fichiers à corriger |
|---|---|---|---|
| V1 | modèle de véhicule | ✅ **`RigidBody3D` + 4 rayons** ; `VehicleBody3D` écarté (raideur hors unités physiques, avant en +Z, force max par défaut trop basse). Longueur libre par essieu, `linear_damp = 0` + traînée explicite, critère de chute corrigé | `VEHICLE_SPEC.md`, `vehicle-physics-engineer.md`, `godot-qa.md`, `CLAUDE.md` §6 et §10, `PLAN.md` phase 1 |
| V2 | collisions à haute vitesse | ✅ 0 traversée / 720 essais jusqu'à 0,1 m et 200 km/h ; `continuous_cd = true` sur le camion ; tick à 60 Hz | `CLAUDE.md` §6 ; `METRICS.md` §4 (épaisseur de design : 0,3 m) |
| V3 | écran partagé à 4 | ⏳ **non mesuré** (machine de référence requise) | — |
| V4 | export d'un véhicule | ✅ pivots faux (2,24 m) avec la location appliquée → corrigé, 0,0000 m | `export.py`, `ART_PIPELINE.md` |

Le code des spikes (`spike/`) a été supprimé à la fin de la phase ; les
protocoles et les chiffres ci-dessus suffisent à les refaire.

Une phase 0.5 qui se termine sans avoir corrigé un seul document est suspecte.
