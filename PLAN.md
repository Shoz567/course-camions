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
| 1.8 | `InputFrame` de conduite + `ScriptedInputSource` (tests) + `LocalInputSource` | gameplay-engineer | `[~]` sources manette, clavier, scriptée ; `DeviceInputSource` anticipe la 4.1 |
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

| # | Tâche | Agent |
|---|---|---|
| 2.1 | Caméra de poursuite amortie (ne tremble jamais, ne passe pas dans les murs) | gameplay-engineer |
| 2.2 | Piste blockout n°1, dimensionnée sur `docs/METRICS.md` : virages variés, un saut | track-designer |
| 2.3 | Checkpoints ordonnés + ligne d'arrivée + détection du mauvais sens | track-designer |
| 2.4 | Zones de reset (hors-piste, vide) + points de réapparition | track-designer |
| 2.5 | Tours et chrono (dérivé des ticks), meilleur tour | gameplay-engineer |
| 2.6 | Reset manuel et automatique (retourné ou immobile hors piste pendant N ticks) | gameplay-engineer |
| 2.7 | HUD minimal : vitesse, tour, chrono | gameplay-engineer |
| 2.8 | Tests : tour compté seulement si les checkpoints sont passés dans l'ordre ; raccourci refusé ; reset replace sur la piste | godot-qa |

**Critères de sortie**
- Un joueur fait 3 tours chronométrés sur la piste n°1.
- Un raccourci qui saute un checkpoint n'est jamais compté.
- Un camion retourné ou tombé est remis en piste, n'importe où sur le circuit.

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

| # | Tâche | Agent |
|---|---|---|
| 4.1 | `DeviceInputSource` : routage des `InputEvent` par `device` id (`docs/INPUT_SPEC.md`) | gameplay-engineer |
| 4.2 | Lobby local : « appuyez sur A pour rejoindre », 2 à 4 joueurs, couleur par joueur | gameplay-engineer |
| 4.3 | Écran partagé : 1 caméra et 1 HUD par joueur dans des `SubViewport` (2, 3, 4 vues) | gameplay-engineer |
| 4.4 | Manette branchée ou débranchée à chaud, sans pause ni crash | gameplay-engineer |
| 4.5 | Tests : isolation des inputs entre joueurs ; perf du rendu à 4 vues | godot-qa |

**Critères de sortie**
- 4 manettes, 4 camions indépendants, aucune fuite d'input (test automatisé).
- Débrancher une manette en pleine course ne crashe pas et ne met pas en pause.
- Rendu à 4 vues dans le budget fixé par le spike V3.

> 🎉 **Ici le jeu est jouable.** Faites-y jouer de vraies personnes avant
> d'aller plus loin. Si ce n'est pas drôle sur un canapé, l'art et le réseau n'y
> changeront rien.

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
| 7.3 | Sons et musique complets | — |
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
- **Remorques.** Changent profondément la conduite (attelage, mise en
  portefeuille) et la physique (acquis A5 de `docs/SPIKE.md`).
- **Boost / objets.** Arcade pur (boost, objets) ou course « propre » ?

## Ce qu'on ne fait volontairement pas (pour l'instant)

- Matchmaking public, NAT punchthrough (nécessiterait GodotSteam).
- Netcode déterministe ou rollback complet : Jolt n'est pas déterministe d'une
  machine à l'autre.
- Simulation réaliste (boîte de vitesses, usure des pneus) : le jeu est arcade.
- Cross-play.
