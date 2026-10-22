# CLAUDE.md — Crazy Wheels (course de camions arcade)

Règles de travail pour Claude Code sur ce dépôt. Lis ce fichier en entier avant
toute modification. En cas de contradiction avec une demande ponctuelle de
l'utilisateur, c'est l'utilisateur qui gagne.

---

## 1. Le projet en une phrase

Jeu de **course de camions arcade** en 3D : conduite permissive et
spectaculaire (dérapages, sauts, contacts entre camions), multijoueur **local
en écran partagé d'abord** (2 à 4 manettes), **online host-autoritaire**
ensuite.

*Titre : « Crazy Wheels » (anciennement « Course de camions »).* Aucun nom, logo, véhicule ou circuit
d'un jeu ou d'une marque existants ne doit apparaître dans le code, les assets
ou l'UI.

> **Historique.** Ce dépôt a d'abord porté un jeu de combat en ragdoll. Tout ce
> travail est archivé par le tag `archive/ragdoll-brawler` (récupérable avec
> `git switch -c ragdoll archive/ragdoll-brawler`). Seule l'infrastructure
> générique a été conservée : socle de tests, runner, `DebugDraw`, Makefile,
> hooks git, pipeline d'export Blender.

## 2. Stack et versions

| Élément | Choix | Notes |
|---|---|---|
| Moteur | **Godot 4.7.2 stable** | installé ; ne pas changer de version sans demander |
| Langage | **GDScript** | C# uniquement si un profilage prouve un goulot |
| Physique 3D | **Jolt** | `physics/3d/physics_engine = "Jolt Physics"` |
| Renderer | Forward+ | à reconsidérer si l'écran partagé à 4 ne tient pas (spike V3) |
| Modélisation | **Blender 5.2 LTS en headless + Python** | tout l'art 3D est généré par script |
| Format d'échange | **glTF 2.0 (.glb)** | jamais de .blend importé directement dans Godot |
| Tests | socle maison `PhysicsTest` + `cli_runner.gd` | gdUnit4 seulement si un besoin réel apparaît |
| Réseau | `ENetMultiplayerPeer` + RPC manuels | phase 6, voir `docs/NETCODE.md` |

Les versions exactes installées sont figées dans **`docs/ENVIRONMENT.md`**. Un
changement de version de Godot peut changer le comportement du solveur : c'est
un événement à signaler, pas un détail. Le passage de 4.6.3 à 4.7.2 a été
vérifié : socle de tests et réglages Jolt identiques.

**Ne change jamais le moteur physique, le tick rate physique ou l'échelle du
monde sans en parler.** Tout le réglage de la conduite en dépend.

## 3. Structure du dépôt

```
.
├── CLAUDE.md                  ← ce fichier
├── PLAN.md                    ← roadmap par phases, source de vérité du "quoi"
├── .claude/agents/            ← définitions des sous-agents
├── .githooks/                 ← hooks git versionnés (voir ENVIRONMENT.md §6)
├── docs/
│   ├── ENVIRONMENT.md         ← outils, versions, machine de référence, git
│   ├── SPIKE.md               ← phase 0.5 : hypothèses à valider + acquis techniques
│   ├── VEHICLE_SPEC.md        ← contrat du camion : dimensions, masse, roues, noms
│   ├── ART_PIPELINE.md        ← Blender headless → glb → Godot
│   ├── INPUT_SPEC.md          ← manettes, device id, InputFrame de conduite
│   ├── METRICS.md             ← métriques de conduite : mesurées, jamais décrétées
│   └── NETCODE.md             ← architecture réseau, budget bande passante
├── tools/blender/             ← scripts Python de génération d'assets
│   ├── lib/                   ← helpers partagés (export glTF, budgets)
│   └── build_all.py
├── game/                      ← projet Godot (project.godot ici)
│   ├── assets/generated/      ← .glb produits par tools/blender (git-ignorés)
│   ├── vehicles/              ← camion : physique, réglages, scène
│   ├── tracks/                ← pistes, checkpoints, zones de reset
│   ├── gameplay/              ← autoloads, règles de course
│   ├── net/
│   ├── ui/
│   └── tests/
│       ├── physics_test.gd    ← socle commun des tests
│       ├── cli_runner.gd      ← lanceur headless
│       ├── baseline.json      ← mesures de référence, versionné
│       ├── scenes/            ← tests lancés par make test
│       └── selftest/          ← auto-tests du socle
└── Makefile                   ← la seule définition des commandes
```

## 4. Commandes

`godot`, `blender` et `make` sont installés et disponibles en ligne de commande
(versions exactes dans `docs/ENVIRONMENT.md` §2).

```bash
make assets        # régénère tous les assets 3D (Blender headless)
make import        # godot --headless --path game --import
make test          # suite rapide : 1 run par test, à chaque commit
make test-full     # suite complète : 5 runs par test physique, fin de phase
make test-selftest # vérifie le socle de test lui-même (après l'avoir modifié)
make baseline      # mesure les métriques de conduite et les ÉCRIT dans baseline.json
make run           # lance le jeu
```

- `make test` doit rester **sous 60 s** : le hook `pre-commit` la lance à chaque
  commit. Si elle déborde, découpe la suite, ne retire pas le hook. Depuis le
  2026-10-22, les scènes tournent **en parallèle** (`cli_runner.gd`,
  `--jobs`) : ~75 s sur la machine de référence (9 min 20 l'une après
  l'autre), encore au-dessus de la cible. Une scène qui mesure un temps réel
  (`Time.get_ticks_*`, `Performance.get_monitor`) passe seule à la fin ; une
  scène réseau (`NetSession`, `ENetMultiplayerPeer`) dans une file unique.
- Tout lancement **fenêtré** pour un essai ou une capture passe par
  `tools/hidden_run.ps1` : la fenêtre naît dans une fenêtre hôte réduite et
  non activée, rien ne s'affiche (pas même l'écran de démarrage), mais
  l'essai est dans la barre des tâches (« Crazy Wheels - essai de Claude ») et
  le joueur peut l'ouvrir. Il prend `-- --offscreen` (`GameState.go_offscreen` :
  réglages du joueur jamais réécrits ; lancé seul, fenêtre hors de l'écran
  et sans focus) et `--mute` pour couper le son, sauf quand on travaille le
  son. Le projet démarre sinon en plein écran, devant le joueur.
- `make test-full` applique la règle des 5 runs (§10) et valide les critères de
  sortie de phase.

Le `Makefile` est **la seule définition** des commandes du projet. Si une
commande manque, ajoute-la au `Makefile` plutôt que de taper des lignes ad hoc.
Contrainte Windows : **pas de `&&`, pas de `$(shell …)`, pas de boucle shell**
dans les recettes.

Toute scène de test hérite de `PhysicsTest` (`game/tests/physics_test.gd`) :
comptage en ticks, lecture de `baseline.json`, verdict PASS / FAIL / SKIP. Mode
d'emploi dans `.claude/agents/godot-qa.md`.

## 5. Conventions de code

- **Fichiers** : `snake_case.gd`, `snake_case.tscn`. **Classes** : `PascalCase`.
  **Méthodes / variables** : `snake_case`. **Constantes** : `SCREAMING_SNAKE`.
- `class_name` sur tout script réutilisable, typage statique **partout**. Le
  typage statique n'est pas cosmétique : il change les perfs GDScript.
- Signaux au passé : `lap_completed`, `checkpoint_passed`, `race_finished`.
- **Toute la physique dans `_physics_process(delta)`** ou `_integrate_forces()`,
  jamais dans `_process`. Aucune allocation dans ces fonctions (pas de
  `Array.new()`, pas de `String` formatée, pas de `get_node()` — met les refs en
  cache dans `_ready`).
- Les constantes de réglage (ressorts, moteur, adhérence, direction) vont dans
  une **ressource `.tres`** typée (`VehicleTuning`), jamais en dur dans le script.
- ⚠️ **Piège mesuré** : Godot n'écrit pas dans un `.tres` une valeur égale au
  défaut du script. Dans une ressource de réglage, mets les défauts à **0** et
  fais-les refuser par une méthode `validate()` : ainsi toute valeur réelle est
  écrite explicitement, et changer un défaut du script ne peut plus modifier un
  réglage en silence.
- Un `assert()` pour les invariants de développement, un `push_warning()` pour
  ce qui doit remonter en runtime.

## 6. Règles physique (non négociables)

- **Échelle** : 1 unité Godot = 1 mètre. Dimensions, masse et position des roues
  du camion : `docs/VEHICLE_SPEC.md`, qui est un **contrat**.
- **Tick physique : 60 Hz.** À 160 km/h, un camion parcourt 0,74 m par tick :
  la collision à haute vitesse a été mesurée au **spike V2** : aucune traversée
  de mur, même de 0,1 m à 200 km/h. Le camion a `continuous_cd = true` (il
  limite l'enfoncement visible) ; le tick global ne change pas.
- **Un camion est un seul `RigidBody3D`** (confirmé par le spike V1 ;
  `VehicleBody3D` est écarté) : forces
  continues avec `apply_force(force, position)` / `apply_central_force()` /
  `apply_torque()`, **dans `_physics_process`** ou `_integrate_forces()`.
  Les **impulsions** (`apply_impulse`) sont réservées aux événements ponctuels :
  collision scénarisée, boost instantané, test.
- Les forces sont **proportionnelles à la masse** : une accélération se règle en
  m/s², jamais en newtons en dur.
- **Pas d'amortissement caché** : le camion est en `linear_damp_mode = REPLACE`,
  `linear_damp = 0`. Le défaut du projet (0,1) plafonnait sa vitesse vers
  167 km/h. La traînée est une force explicite de `VehicleTuning`.
- **Interpolation physique activée** (`physics/common/physics_interpolation`) :
  le rendu interpole entre deux ticks, donc pas d'à-coups au-delà de 60 Hz. La
  caméra lit `get_global_transform_interpolated()`. Après toute téléportation,
  `reset_physics_interpolation()` (le camion le fait seul après `reset_to`).
- **Pas de téléportation d'un corps en mouvement** par `global_position`. Le
  reset d'un camion (retour sur la piste) passe par `state.transform` dans
  `_integrate_forces()`, avec les vitesses fixées dans le même tick : à zéro,
  ou à une vitesse choisie vers l'avant (réapparition lancée, depuis le
  2026-10-22) ; jamais l'élan d'avant la téléportation.
- **Les roues ne sont pas des corps physiques** : la suspension est portée par
  des rayons (raycasts) depuis le châssis. Les maillages de roues sont purement
  visuels. On ne fait jamais de collision sur un maillage de véhicule.
- Chaque nouvelle force (suspension, traction, adhérence, anti-retournement,
  aide en l'air…) doit être **désactivable** par un flag de debug, pour isoler
  ce qui casse la conduite.

## 7. Règles réseau (à respecter dès la phase 1)

Même avant la moindre ligne de réseau, le code doit être écrit pour le
supporter :

- **Séparer input / simulation / rendu.** Un camion ne lit jamais `Input.*`
  directement : il consomme une `InputFrame` fournie par une source (locale,
  manette, distante, scriptée). C'est la règle la plus importante du dépôt :
  elle rend possibles à la fois l'écran partagé, l'online et les tests.
- La simulation ne lit jamais de temps réel (`Time.get_ticks_msec()`,
  `create_timer()`) pour de la logique de jeu — uniquement le compteur de ticks.
  **Toute durée de logique se spécifie en ticks**, y compris dans les specs :
  `12 ticks (~200 ms)`. Exception : le **chronomètre affiché** au joueur est
  dérivé du compteur de ticks (`tick / 60`), jamais de l'horloge.
- Aucun état de jeu dans les nœuds d'UI (le HUD lit, il ne décide pas).
- Rien d'aléatoire sans un `RandomNumberGenerator` seedé et possédé par
  `RaceManager`.

## 8. Ce que tu ne fais pas sans demander

- Changer de version de Godot, de moteur physique ou de langage.
- Ajouter une dépendance externe (addon, GDExtension, plugin Blender).
- Committer des binaires : `*.glb`, `*.blend1`, `.godot/`, `builds/` sont
  git-ignorés (le hook `pre-commit` les refuse). Exceptions : `baseline.json`,
  et les modèles `.glb` de l'équipe dans `Assets_Visuels/`, versionnés **par
  Git LFS** (décision du 2026-10-02, `docs/ENVIRONMENT.md` §6.7), et les
  musiques de `game/audio/music/`, en Git LFS aussi (2026-10-22).
- Télécharger des assets tiers (modèles, textures, sons).
  Les sons **synthétisés par le code** (`MenuSound`, `CountdownSound`, moteurs,
  ambiances) ne sont pas des assets tiers. Exception décidée par
  l'utilisateur le 2026-10-22 : les **musiques** (menu, une par circuit et sa
  version du dernier tour) sont des morceaux CC0 de MintoDog choisis par lui
  (`game/audio/music/CREDITS.md`) ; en ajouter un autre se demande.
- Refactorer une couche qui n'est pas dans la phase en cours de `PLAN.md`.
- **Modifier `docs/VEHICLE_SPEC.md` ou `docs/METRICS.md`.** Ce sont des contrats
  entre plusieurs chaînes d'outils (physique, Blender, pistes). Un agent qui a
  besoin d'un changement le **demande**, avec sa justification chiffrée ; la
  modification et la resynchronisation se font dans le même commit, décidé par
  l'utilisateur.

## 9. Workflow attendu

1. Lis `PLAN.md`, identifie la **phase courante** et la tâche.
2. **Crée une branche** depuis un `main` à jour : `<zone>/<sujet>`, par exemple
   `phase-1/suspension`. On ne travaille jamais sur `main` : l'équipe est à
   quatre, et le hook `pre-push` refuse tout push sur `main`.
3. Si la tâche correspond à un sous-agent de `.claude/agents/`, délègue-lui.
4. Implémente la plus petite tranche vérifiable.
5. **Vérifie** : `make test` pendant l'itération, `make test-full` pour clore une
   phase. Une phase n'est finie que quand ses critères de sortie sont cochés
   **et mesurés**.
6. Commit atomique, message en français, à l'impératif :
   `vehicule: ajoute la force de suspension par raycast`.
7. Mets à jour la case correspondante dans `PLAN.md`.
8. Pousse la branche et ouvre une **pull request** vers `main`. Son titre suit la
   même convention : il devient le message du commit fusionné (squash).

Détail des commandes et des règles de branche : `docs/ENVIRONMENT.md` §6.4.

## 10. Comment vérifier une conduite sans jouer

Le piège de ce projet : « ça a l'air bien en jouant » n'est pas un test, et la
sensation de conduite régresse en silence d'un réglage à l'autre. Chaque
comportement physique a une **scène de test headless** qui pilote le camion par
une `ScriptedInputSource` et échoue sur un seuil.

### Trois règles d'écriture des critères

**(a) Un seuil se dérive, il ne s'invente pas.** Une cible (vitesse max, 0-100)
vient de `docs/VEHICLE_SPEC.md` ; une tolérance s'exprime en pourcentage de la
cible, ou en ratio d'une mesure prise au tick 0 de la scène elle-même.

**(b) Une poussée se spécifie en impulsion (N·s) ou en m/s ajoutés, jamais en
« force » sans durée.** 5 000 N pendant 1 tick ne déplacent pas un camion de
5 t ; pendant 1 s, si.

**(c) Un critère doit être mesurable avec les API existantes.** Mesure des
grandeurs observables : vitesse, position, angle de roulis, contact des roues.

### Le catalogue de référence

| Comportement | Critère mesurable |
|---|---|
| Stabilité à l'arrêt | posé 600 ticks sans input → roulis et tangage < 1°, dérive horizontale < 5 cm |
| Hauteur de caisse | au repos, hauteur du châssis = `VEHICLE_SPEC` ± 3 cm |
| Vitesse max | plein gaz sur le plat → `top_speed_kmh` à ± 5 % de la cible |
| Accélération | 0 → 100 km/h en `accel_0_100_s` ± 5 % de la cible |
| Freinage | 100 → 0 km/h en moins de `braking_100_0_m` |
| Virage | plein braquage à 80 km/h pendant 300 ticks → jamais retourné (roulis < 45°) |
| Saut | chute de 2 m → 4 roues au sol < 30 ticks **après le premier contact**, stabilisé < 60 ticks après, châssis jamais au sol, aucun NaN (la chute libre seule dure ~38 ticks) |
| Haute vitesse | à vitesse max contre un mur de 0,3 m → **jamais traversé**, 5 fois sur 5 |
| Perf | physique < 4 ms/tick à 4 camions ; rendu écran partagé à 4 : ≤ 16,7 ms par image sur la machine de référence, avec le budget du spike V3 (`docs/SPIKE.md`) |

Les cibles vivent dans `docs/VEHICLE_SPEC.md` ; les valeurs **mesurées** dans
`baseline.json`. Un test dont la référence est encore `null` se **saute**
explicitement (`require_baseline()`), il n'invente pas de valeur.

### Non-déterminisme

Jamais d'égalité exacte sur une valeur physique ; `make test-full` lance **5
fois** chaque test et exige 5 réussites ; un test qui échoue 1 fois sur 5 est un
**bug de réglage**, pas un test instable.

Écris le test **avant** de régler. Sinon tu règles à l'aveugle et tu régresses
sans le voir.

## 11. Acquis techniques et hypothèses ouvertes

`docs/SPIKE.md` contient deux choses : les **acquis** mesurés sur ce moteur
(transférés de l'ancien projet, toujours valables) et les **hypothèses** propres
au camion, à valider en phase 0.5 avant d'écrire la physique.

Les acquis qui piègent le plus souvent :

| Acquis | Conséquence |
|---|---|
| Jolt enfonce un corps au repos de `penetration_slop` = 0,02 m (vérifié sur 4.7.2) | les hauteurs absolues au repos en tiennent compte |
| En headless, le temps mural vaut 16,67 ms/tick quelle que soit la charge, et `Performance.TIME_PHYSICS_PROCESS` n'est rafraîchi qu'environ une fois par seconde réelle | mesurer la perf **sous `--fixed-fps 60`** : temps mural ÷ ticks = coût réel d'un tick. Le runner lance **tous** les tests ainsi, `perf_*` compris (A2, A15) |
| Au démarrage, Godot enchaîne plusieurs ticks sans rendu | un test qui observe le rendu n'agit pas dès le tick 1 |
| Jolt ignore `damping`, `restitution`, `force_limit` des joints 6DOF | ne pas les écrire ; pour de la mollesse : `angular_spring_*` |
| Une erreur de script n'empêche pas une scène de conclure PASS | le runner compte en échec toute sortie contenant `SCRIPT ERROR` |
| `default_linear_damp` = 0,1 freine tout corps en silence | le camion le remplace par 0 (A10) |
| Appliquer la location à l'export met le pivot des roues au centre du camion | `export.apply_transforms()` ne l'applique plus (A13) |

Tant qu'un spike n'a pas répondu, **le code de production concerné ne s'écrit
pas**.

Si tu découvres qu'une règle de ce fichier est fausse, **corrige le fichier**
dans le même commit que le code, et dis-le explicitement dans ton rapport. Une
règle fausse qu'on contourne silencieusement est pire que pas de règle du tout.
