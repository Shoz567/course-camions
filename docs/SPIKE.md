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
| A2 | En headless, le temps mural vaut **16,67 ms/tick quelle que soit la charge** : Godot régule à 60 Hz | 4.6.3 | mesurer la perf avec `Performance.TIME_PHYSICS_PROCESS`, jamais le temps mural |
| A3 | Au démarrage, Godot enchaîne **plusieurs ticks physiques sans rendu** pour rattraper le chargement | 4.6.3 | un test qui observe le rendu n'agit pas avant ~30 ticks |
| A4 | `--quit-after` compte des **itérations**, pas des ticks : ~2,4 par tick sur une scène légère | 4.6.3 | un test long relève `--max-iterations` |
| A5 | Joints 6DOF sous Jolt : limites angulaires **honorées** ; `damping`, `restitution`, `force_limit` des limites **ignorés** ; `angular_spring_*` **supporté** ; axes linéaires verrouillés = **soudure parfaite** (0,0000 m de séparation sous 2 000 N) | 4.6.3 | pour une attache souple (remorque, objet traîné) : ressort, pas limite amortie ; une rupture de joint n'est pas observable par la séparation |
| A6 | Export glTF de `tools/blender/lib/export.py` : cube de 1 m mesuré **1,0000 m**, os de 0,40 m mesuré **0,4000 m**, noms conservés | Blender 5.2.1 + Godot 4.6.3 | le contrat d'export tient ; à revérifier pour des roues à pivot (V4) |
| A7 | Sur une même machine, une simulation se rejoue **à l'identique** d'un lancement à l'autre | 4.6.3 | les écarts entre runs viennent d'ailleurs (autre machine, ordre de création) |
| A8 | Une erreur d'exécution GDScript interrompt la fonction mais **pas la scène** : elle peut encore conclure PASS | 4.6.3, 4.7.2 | le runner compte en échec toute sortie contenant `SCRIPT ERROR` |
| A9 | L'exécutable Godot « normal » sous Windows est une appli graphique : **aucune sortie console** | 4.6.3 | le raccourci `godot` pointe vers `…_console.exe` (ENVIRONMENT.md §4.1) |

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

---

## Livrable de la phase 0.5

| Spike | Question | Réponse | Fichiers à corriger |
|---|---|---|---|
| V1 | modèle de véhicule | | `VEHICLE_SPEC.md`, `vehicle-physics-engineer.md`, `PLAN.md` phase 1 |
| V2 | collisions à haute vitesse | | `CLAUDE.md` §6, `track-designer.md` (épaisseur des murs) |
| V3 | écran partagé à 4 | | `CLAUDE.md` §2, `ENVIRONMENT.md`, budgets d'`ART_PIPELINE.md` |
| V4 | export d'un véhicule | | `ART_PIPELINE.md`, `tools/blender/lib/export.py` |

Une phase 0.5 qui se termine sans avoir corrigé un seul document est suspecte.
