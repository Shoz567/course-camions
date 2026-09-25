# CLAUDE.md — Ragdoll Brawler

Règles de travail pour Claude Code sur ce dépôt. Lis ce fichier en entier avant
toute modification. En cas de contradiction avec une demande ponctuelle de
l'utilisateur, c'est l'utilisateur qui gagne.

---

## 1. Le projet en une phrase

Jeu de combat physique 3D multijoueur dans l'esprit de *Gang Beasts* :
personnages en **ragdoll actif** permanent, mécanique d'**agrippement**, arènes
courtes et mortelles. Multijoueur **local d'abord** (plusieurs manettes sur le
même écran), **online host-autoritaire** en phase 6.

Ce n'est pas un clone asset-par-asset : on reproduit des mécaniques, pas des
personnages, logos ou niveaux existants. Aucun nom, visuel ou marque de *Gang
Beasts* ne doit apparaître dans le code, les assets ou l'UI.

## 2. Stack et versions

| Élément | Choix | Notes |
|---|---|---|
| Moteur | **Godot 4.6.3 stable** | installé ; ne pas migrer de version sans demander |
| Langage | **GDScript** | C# uniquement si un profilage prouve un goulot |
| Physique 3D | **Jolt** | `physics/3d/physics_engine = "Jolt Physics"` (intégré depuis 4.4) |
| Renderer | Forward+ | |
| Modélisation | **Blender 5.2 LTS en headless + Python** | installé ; API du pipeline vérifiée compatible |
| Format d'échange | **glTF 2.0 (.glb)** | jamais de .blend importé directement dans Godot |
| Tests | gdUnit4 (addon) | tests headless obligatoires pour la logique pure |
| Réseau | `ENetMultiplayerPeer` + RPC manuels | phase 6, voir `docs/NETCODE.md` |

Les versions exactes réellement installées sont figées dans
**`docs/ENVIRONMENT.md`** et vérifiées par la tâche 0.1. Un changement de version
mineure de Godot peut changer le comportement du solveur : c'est un événement à
signaler, pas un détail.

**Ne change jamais le moteur physique, le tick rate physique ou l'échelle du
monde sans en parler.** Tout le tuning du ragdoll en dépend et un changement
invalide des semaines de réglages.

## 3. Structure du dépôt

```
.
├── CLAUDE.md                  ← ce fichier
├── PLAN.md                    ← roadmap par phases, source de vérité du "quoi"
├── .claude/agents/            ← définitions des sous-agents
├── docs/
│   ├── ENVIRONMENT.md         ← outils, versions, commandes Windows et POSIX
│   ├── SPIKE.md               ← phase 0.5 : hypothèses techniques à valider
│   ├── RIG_SPEC.md            ← squelette, proportions, masses, joints
│   ├── ART_PIPELINE.md        ← Blender headless → glb → Godot
│   ├── INPUT_SPEC.md          ← manettes, device id, actions
│   ├── METRICS.md             ← métriques de gameplay : contrat du fichier mesuré
│   └── NETCODE.md             ← architecture réseau, budget bande passante
├── tools/blender/             ← scripts Python de génération d'assets
│   ├── lib/                   ← helpers partagés (mesh, rig, export)
│   ├── build_character.py
│   ├── build_arena_*.py
│   └── build_all.py
├── game/                      ← projet Godot (project.godot ici)
│   ├── assets/generated/      ← .glb produits par tools/blender (git-ignorés)
│   ├── characters/
│   ├── gameplay/
│   ├── levels/
│   ├── net/
│   ├── ui/
│   └── tests/
│       ├── baseline.json      ← mesures de référence, versionné
│       └── scenes/
└── Makefile                   ← raccourcis de build et de test
```

## 4. Commandes

`godot`, `blender` et `make` sont installés et disponibles en ligne de commande
(versions exactes dans `docs/ENVIRONMENT.md` §2). Les commandes canoniques sont
dans le `Makefile` :

```bash
make assets        # régénère tous les assets 3D (Blender headless)
make import        # godot --headless --path game --import
make test          # suite rapide : 1 run par test, à chaque commit
make test-full     # suite complète : 5 runs par test physique, fin de phase
make run           # lance le jeu
```

Deux cibles de test, volontairement :

- `make test` doit rester **sous 60 s**. C'est celle qu'on lance sans y penser.
- `make test-full` applique la règle des 5 runs (cf. §10) et peut prendre
  plusieurs minutes. C'est celle qui valide un critère de sortie de phase.

Si une commande n'existe pas encore à la phase où tu travailles, crée-la dans le
`Makefile` plutôt que de taper des lignes ad hoc. Le `Makefile` est **la seule
définition** des commandes du projet : c'est ce qui garantit qu'un agent ne
teste pas sans `--headless` pendant qu'un autre oublie `--runs=5`.

Contrainte d'écriture sous Windows : **pas de `&&`, pas de `$(shell …)`, pas de
boucle shell** dans les recettes. Une commande par ligne, les enchaînements
exprimés comme des dépendances entre cibles (cf. `docs/ENVIRONMENT.md` §4.2).

## 5. Conventions de code

- **Fichiers** : `snake_case.gd`, `snake_case.tscn`. **Classes** : `PascalCase`.
  **Méthodes / variables** : `snake_case`. **Constantes** : `SCREAMING_SNAKE`.
- `class_name` sur tout script réutilisable, typage statique **partout**
  (`var vel: Vector3 = Vector3.ZERO`, `func apply(x: float) -> void:`).
  Le typage statique n'est pas cosmétique ici : il change les perfs GDScript.
- Signaux au passé : `player_eliminated`, `grab_released`.
- **Toute la physique dans `_physics_process(delta)`** ou `_integrate_forces()`,
  jamais dans `_process`. Aucune allocation dans ces fonctions (pas de
  `Array.new()`, pas de `String` formatée, pas de `get_node()` — met les refs en
  cache dans `_ready`).
- Les constantes de tuning (raideurs, forces, seuils) vont dans une **ressource
  `.tres`** typée (`CharacterTuning`), jamais en dur dans le script. Un designer
  doit pouvoir les changer sans toucher au code.
- Un `assert()` pour les invariants de développement, un `push_warning()` pour
  ce qui doit remonter en runtime.

## 6. Règles physique (non négociables)

- **Échelle** : 1 unité Godot = 1 mètre. Personnage **1,60 m** pour une masse
  totale de **70 kg** répartie selon `docs/RIG_SPEC.md`. Les longueurs de la
  table de ce fichier somment exactement à 1,60 m et le centre de masse calculé
  vaut 0,85 m : c'est vérifié, ne le casse pas par un ajustement local.
- Tick physique : **60 Hz** (`physics/common/physics_ticks_per_second = 60`).
  Si le ragdoll est instable, **la première soupape n'est pas le tick rate** :
  augmente les itérations du solveur Jolt (`velocity_steps` / `position_steps`
  dans les réglages du projet). C'est beaucoup moins cher en CPU sur un
  empilement de joints contraints. Doubler le tick global se discute *après*
  avoir essayé ça, et se mesure.
- **Couple et force continus** — *mesuré au spike S1, ne pas redécouvrir* :

  ```gdscript
  PhysicsServer3D.body_apply_torque(bone.get_rid(), torque)
  PhysicsServer3D.body_apply_central_force(bone.get_rid(), force)
  ```

  `PhysicalBone3D` hérite de `PhysicsBody3D`, **pas** de `RigidBody3D` :
  `apply_torque()`, `apply_central_force()` et `apply_force()` **n'existent
  pas** dessus, et `_integrate_forces()` non plus. Seules les *impulsions*
  (`apply_impulse`, `apply_central_impulse`) et `angular_velocity` /
  `linear_velocity` sont exposées directement.

  Le couple **ne persiste pas** : il est consommé à chaque step et doit être
  réappliqué à chaque tick. Vérifié : couple constant de 10 N·m sur une boîte
  de 0,2667 kg·m² → ω croît linéairement à 37,5 rad/s², soit 36,875 rad/s après
  59 ticks — exactement la valeur théorique.

  `PhysicsServer3D.body_get_direct_state(rid).apply_torque()` donne le même
  résultat au chiffre près, mais passe par une indirection inutile.
- Les **impulsions** (`apply_impulse`) sont réservées aux événements ponctuels :
  saut, coup, poussée de test. Jamais pour du mouvement continu.
- Aucun `set_global_position` sur un `PhysicalBone3D` en cours de simulation :
  ça téléporte et fait exploser le solveur. Utilise des forces, ou
  `physical_bones_stop_simulation()` → repositionner → redémarrer.
- Les valeurs de force/couple sont **proportionnelles à la masse** du corps
  visé. Ne code jamais un couple absolu en dur sur un membre.
- Chaque nouvelle force ou contrainte ajoutée doit être **désactivable** par un
  flag de debug, pour pouvoir isoler ce qui casse l'équilibre.

## 7. Règles réseau (à respecter dès la phase 1)

Même avant d'écrire la moindre ligne de réseau, le code gameplay doit être écrit
pour le supporter :

- **Séparer input / simulation / rendu.** Un contrôleur ne lit jamais
  `Input.*` directement : il consomme une struct `InputFrame` fournie par une
  source (locale ou distante). C'est la règle la plus importante du dépôt.
- La simulation ne lit jamais de temps réel (`Time.get_ticks_msec()`,
  `get_tree().create_timer()`) pour de la logique de jeu — uniquement le
  compteur de ticks physiques. **Corollaire d'écriture** : toute durée de
  logique se spécifie **en ticks**, y compris dans les specs et les tickets. Les
  millisecondes ne servent qu'à donner l'intuition, entre parenthèses :
  `12 ticks (~200 ms)`.
- Aucun état de jeu dans les nœuds d'UI.
- Rien d'aléatoire sans un `RandomNumberGenerator` seedé et possédé par le
  serveur.

## 8. Ce que tu ne fais pas sans demander

- Changer de version de Godot, de moteur physique ou de langage.
- Ajouter une dépendance externe (addon, GDExtension, plugin Blender).
- Committer des binaires : `*.glb`, `*.blend1`, `.godot/`, `builds/` sont
  git-ignorés. Les assets se **régénèrent**, ils ne se versionnent pas.
  Exception explicite : `game/tests/baseline.json` **est** versionné.
- Télécharger des assets tiers (modèles, textures, sons) : tout est généré ou
  fourni par l'utilisateur.
- Refactorer une couche qui n'est pas dans la phase en cours de `PLAN.md`.
- **Modifier `docs/RIG_SPEC.md` ou `docs/METRICS.md`.** Ce sont des contrats
  entre plusieurs chaînes d'outils : aucun agent n'en est propriétaire. Un agent
  qui a besoin d'un changement le **demande**, avec sa justification chiffrée ;
  la modification et la resynchronisation des deux côtés se font dans le même
  commit, décidé par l'utilisateur.

## 9. Workflow attendu

1. Lis `PLAN.md`, identifie la **phase courante** et la tâche.
2. Si la tâche correspond à un sous-agent de `.claude/agents/`, délègue-lui.
3. Implémente la plus petite tranche vérifiable.
4. **Vérifie** : `make test` pendant l'itération, `make test-full` pour clore une
   phase. Une phase n'est finie que quand ses critères de sortie dans `PLAN.md`
   sont cochés **et mesurés**.
5. Commit atomique, message en français, à l'impératif :
   `ragdoll: ajoute le couple correcteur du bassin`.
6. Mets à jour la case correspondante dans `PLAN.md`.

Le dépôt doit être sous git **avant** la première ligne de code. Pendant les
semaines de tuning de la phase 1, la capacité à revenir à « l'état où ça tenait
debout » vaut plus que n'importe quel test.

## 10. Comment vérifier du gameplay physique sans jouer

Le piège de ce projet : « ça a l'air bien » n'est pas un test. Chaque
comportement physique doit avoir une **scène de test headless** qui mesure une
grandeur et échoue sur un seuil.

### Trois règles d'écriture des critères

**(a) Un seuil se dérive, il ne s'invente pas.** Un critère en valeur absolue
(« tête > 1,3 m ») casse dès que les proportions bougent de 5 cm, et ne dit rien
de ce qu'on cherche vraiment à mesurer : l'affaissement. Exprime-le en **ratio
par rapport à une mesure prise au tick 0 de la scène elle-même** :

```
head_y(t = 600 ticks) > 0,92 × head_y(t = 0)
```

**(b) Une poussée se spécifie en impulsion (N·s), pas en force (N).** « 300 N »
ne veut rien dire sans durée : 300 N pendant 1 tick, c'est 5 N·s et le
personnage ne bouge pas ; pendant 1 s, c'est 300 N·s et il traverse l'arène.
Écris toujours `impulsion de X N·s appliquée en un tick`, ou
`force de X N pendant n ticks`.

**(c) Un critère doit être mesurable avec les API existantes.** Godot n'expose
pas la force interne d'un joint : un seuil de rupture de grab exprimé en newtons
n'est pas testable tel quel. Il se formule en **grandeur observable** —
séparation main↔ancre au-delà de `d` mètres pendant `n` ticks. Le spike S5
tranche définitivement ce point.

### Le catalogue de référence

| Comportement | Critère mesurable |
|---|---|
| Conformité géométrique | `head_y(t=0)` = **1,454 m** ±3 cm, centre de masse = **0,840 m** ±3 cm *(mesuré S4)* |
| Équilibre | debout 600 ticks (10 s) sans input → `head_y > 0,92 × head_y(t=0)` |
| Résistance | impulsion latérale de `impulse_stagger_ns` → toujours debout 120 ticks après |
| Récupération | impulsion latérale de `impulse_knockdown_ns` → tombe, puis `head_y > 0,92 × head_y(t=0)` en < 240 ticks |
| Grab | prise établie en < **12 ticks** (~200 ms) quand la cible est à portée |
| Rupture du grab | séparation main↔ancre > **0,25 m** pendant 6 ticks → prise relâchée, exactement une fois *(≈ 950 N, mesuré S5)* |
| Éjection | un corps sous y = −10 déclenche **exactement un** signal `player_eliminated` |
| Perf | temps de frame physique < **4 ms** à 4 persos, sur la machine de `docs/ENVIRONMENT.md` |

⚠️ **Les deux valeurs d'impulsion ne sont pas encore connues.** Le spike S4 a
établi qu'elles ne sont **pas calibrables sur un ragdoll inerte** : sans
`BalanceController`, le personnage s'effondre sous son propre poids quelle que
soit l'impulsion (mesuré : ratio 0,12 de 20 à 500 N·s, sans aucune
monotonie). Elles se mesurent **en fin de phase 1**, une fois l'équilibre
obtenu, et s'écrivent alors dans `baseline.json`.

En attendant, les tests de résistance et de récupération lisent
`impulse_stagger_ns` / `impulse_knockdown_ns` depuis `baseline.json` et se
**sautent explicitement** si la valeur est `null` — ils ne prennent pas une
valeur par défaut. Un test qui invente son propre seuil ne mesure rien.

⚠️ **Le budget perf est serré sur la machine actuelle.** Mesuré au spike S4 sur
rig inerte : 2,565 ms à 1 perso, 4,351 ms à 4 persos — soit **déjà au-dessus
des 4 ms avant tout PD**. Le budget sera vraisemblablement à renégocier en fin
de phase 1 ; c'est une décision à prendre avec une mesure sous les yeux, pas un
seuil à abaisser en silence.

### Non-déterminisme

La physique varie d'un run à l'autre. Donc : jamais d'égalité exacte sur une
valeur physique ; `make test-full` lance **5 fois** chaque test physique et exige
5 réussites ; un test qui échoue 1 fois sur 5 n'est pas un test instable, c'est
un **bug de tuning** — remonte-le comme tel.

Écris le test **avant** de tuner. Sinon tu tunes à l'aveugle et tu régresses sans
le voir.

## 11. Ce que les spikes ont établi

La phase 0.5 a répondu aux six hypothèses qui portaient ce plan. Les résultats
détaillés sont dans **`docs/SPIKE.md`** ; voici ce qui change une règle :

| # | Question | Réponse |
|---|---|---|
| S1 | Couple continu sur `PhysicalBone3D` | `PhysicsServer3D.body_apply_torque` — pas `apply_torque()`, qui n'existe pas (§6) |
| S2 | Paramètres de joint sous Jolt | limites honorées ; `damping`/`restitution`/`force_limit` **ignorés** |
| S3 | Pose cible vs simulateur | **aucun conflit** : le simulateur n'écrase pas `bone_pose` |
| S4 | Coût CPU / impulsions | 4,35 ms à 4 persos ; impulsions non calibrables avant la phase 1 |
| S5 | Force de joint / grab | non lisible ; un joint ne se sépare **jamais** → grab par ressort PD |
| S6 | Échelle Blender → Godot | contrat d'export validé au millimètre |

Il reste **une question ouverte**, à trancher en phase 1 : le budget de 4 ms à
4 persos est déjà dépassé par un rig inerte sur cette machine.

Si tu découvres qu'une règle de ce fichier est fausse, **corrige le fichier**
dans le même commit que le code, et dis-le explicitement dans ton rapport. Une
règle fausse qu'on contourne silencieusement est pire que pas de règle du tout.
C'est exactement ce qui est arrivé à la §6 : elle prescrivait une API qui
n'existe pas, et seule une mesure l'a révélé.
