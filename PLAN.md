# PLAN.md — Ragdoll Brawler

Roadmap par phases. **Une phase à la fois.** Une phase n'est terminée que quand
tous ses critères de sortie sont vérifiés par un test ou une scène de démo.

Légende : `[ ]` à faire · `[~]` en cours · `[x]` fait
Colonne **Agent** = sous-agent de `.claude/agents/` à qui déléguer.

---

## Vue d'ensemble

| Phase | Objectif | Sortie visible | Effort indicatif |
|---|---|---|---|
| 0 | Fondations du dépôt | `make test` passe à vide | 1 j |
| **0.5** | **Spike : valider les hypothèses techniques** | **6 réponses, docs corrigés** | **1–2 j** |
| 1 | Ragdoll actif qui tient debout | une capsule-bonhomme debout, poussable | 1–3 sem |
| 2 | Marche, saut, bras, grab | deux persos qui se saisissent | 1–2 sem |
| 3 | Arène, boucle de manche, premier juice | on gagne et on perd une manche | 1–1,5 sem |
| 4 | Multijoueur local 2–4 manettes | 4 joueurs sur un canapé | 3–5 j |
| 5 | Vrai art 3D généré par Blender | persos et arènes texturés | 1–2 sem |
| 6 | Online host-autoritaire | 2 PC connectés | 2–4 sem |
| 7 | Polish, menus, export | build jouable | 1–2 sem |

L'effort suppose un dev à temps partiel + Claude Code. **La phase 1 est celle
qui déborde toujours** : c'est elle qui fait ou défait le jeu. La phase 0.5
existe précisément pour qu'elle déborde pour de bonnes raisons (le tuning est
difficile) et non pour de mauvaises (l'API n'était pas celle qu'on croyait).

---

## Phase 0 — Fondations

**But** : que tout le monde (toi, Claude, les agents) parte des mêmes rails.

| # | Tâche | Agent |
|---|---|---|
| 0.0 | `git init`, premier commit du pack documentaire. **Avant tout le reste.** | — |
| 0.1 | Remplir `docs/ENVIRONMENT.md` : versions réelles de Godot/Blender, mise au PATH, choix pour `make` sous Windows | — |
| 0.2 | Créer le projet Godot dans `game/`, Forward+, `physics/3d/physics_engine = "Jolt Physics"`, 60 ticks/s | — |
| 0.3 | `.gitignore` (`.godot/`, `game/assets/generated/`, `*.blend1`, `builds/`, `spike/`) — **mais pas** `game/tests/baseline.json` | — |
| 0.4 | `game/tests/cli_runner.gd` avec l'option `--runs=N`. **gdUnit4 volontairement repoussé** : inutile avant les tests unitaires de la phase 2, et `CLAUDE.md` §8 interdit d'ajouter une dépendance sans validation | godot-qa |
| 0.5 | `Makefile` : `assets`, `import`, `test`, `test-full`, `run` | — |
| 0.6 | `game/tests/baseline.json` créé avec ses clés à `null` (cf. `ENVIRONMENT.md` §5) | godot-qa |
| 0.7 | Autoloads vides mais nommés : `GameState`, `MatchManager`, `DebugDraw` | — |
| 0.8 | `tools/blender/lib/` + `build_all.py` qui ne génère encore rien mais tourne | blender-modeler |

**Critères de sortie**
- `make test` s'exécute et affiche 0 échec, **en moins de 60 s**.
- `make assets` s'exécute sans erreur (même sans produire de fichier).
- `godot --headless --path game --import` sort en code 0.
- `docs/ENVIRONMENT.md` ne contient plus aucun « _à remplir_ » dans les §1 et §2.
- Le dépôt est sous git avec au moins un commit.

---

## Phase 0.5 — Spike technique

**But** : répondre par oui ou non à six questions dont dépend toute la phase 1,
**avant** d'y investir des semaines.

Le protocole complet est dans **`docs/SPIKE.md`**. Le code produit vit dans
`spike/`, il est git-ignoré, et il est **supprimé à la fin**.

| # | Tâche | Agent | État |
|---|---|---|---|
| 0.5.1 | **S1** — couple continu sur un `PhysicalBone3D` | ragdoll-engineer | `[x]` |
| 0.5.2 | **S2** — paramètres de joint honorés par Jolt | ragdoll-engineer | `[x]` |
| 0.5.3 | **S3** — pose cible sans conflit avec le simulateur | ragdoll-engineer | `[x]` |
| 0.5.4 | **S4** — coût CPU à 1/2/4 persos, calibration des impulsions | godot-qa | `[x]` partiel |
| 0.5.5 | **S5** — contrainte de joint lisible ? grab sans joint | gameplay-engineer | `[x]` |
| 0.5.6 | **S6** — échelle et noms d'os Blender → Godot | blender-modeler | `[x]` |
| 0.5.7 | **Corrections appliquées aux documents**, `spike/` supprimé | — | `[x]` |

**Critères de sortie** — tous atteints sauf un, explicitement reporté :

- `[x]` Les six lignes du tableau de `docs/SPIKE.md` ont une réponse mesurée.
- `[x]` `CLAUDE.md` §6 contient la ligne de code exacte du couple continu.
- `[x]` `baseline.json` contient les temps physiques à 1, 2 et 4 persos.
- `[x]` `spike/` n'existe plus.
- `[ ]` **`CLAUDE.md` §10 ne contient pas les deux impulsions.** Non par oubli :
  S4 a établi qu'elles ne sont **pas calibrables sur un ragdoll inerte** — sans
  `BalanceController`, le personnage s'effondre quelle que soit l'impulsion
  (ratio 0,12 de 20 à 500 N·s, sans aucune monotonie). Reporté en fin de phase 1.

**Trois décisions issues des spikes, à appliquer plus loin :**

1. **Le grab se fait par ressort PD, pas par joint** (S5). Un joint 6DOF ne se
   sépare jamais — 0,0000 m sous 2000 N — donc sa rupture n'est détectable par
   aucune grandeur observable. Voir tâches 2.5–2.6.
2. **Le budget perf est déjà dépassé** (S4) : 4,351 ms à 4 persos sur un rig
   *inerte*, pour un budget de 4 ms. À trancher en fin de phase 1, avec une
   mesure — optimiser ou renégocier, pas abaisser le seuil en silence.
3. **`PoseProvider` n'a pas besoin d'un squelette séparé** (S3) : le simulateur
   n'écrase pas `bone_pose`. La tâche 1.5 s'en trouve simplifiée.

---

## Phase 1 — Ragdoll actif (le cœur du jeu)

**But** : un personnage entièrement simulé par la physique qui **tient debout
tout seul**, encaisse une poussée et se relève. Pas de contrôle joueur encore.

> ⚠️ Zéro art à cette phase. Capsules et boîtes. Si tu ouvres Blender ici, tu
> perds ton temps.

| # | Tâche | Agent |
|---|---|---|
| 1.0 | ✅ Socle des tests physiques : classe `PhysicsTest`, verdict SKIP, garde anti-blocage, `make test-selftest` | godot-qa |
| 1.1 | Rig placeholder par code : 13 `PhysicalBone3D` selon `docs/RIG_SPEC.md` §3 | ragdoll-engineer |
| 1.2 | Joints via `joint_type = JOINT_TYPE_6DOF` sur chaque `PhysicalBone3D` (pas de nœud joint séparé) + limites de `RIG_SPEC.md` §5, **sans** les paramètres que Jolt ignore | ragdoll-engineer |
| 1.3 | **Test de conformité géométrique** : hauteur et centre de masse mesurés conformes à `RIG_SPEC.md` §4 (±3 cm) | godot-qa |
| 1.4 | ✅ Ressource `CharacterTuning` + `default_tuning.tres` : fréquence, amortissement, couple max pour les 12 articulations (valeurs de départ, non réglées) | ragdoll-engineer |
| 1.5 | `PoseProvider` : pose de référence écrite dans `bone_pose` du même `Skeleton3D` (S3 : aucun conflit avec le simulateur) | ragdoll-engineer |
| 1.6 | `JointDriver` : PD par articulation via `PhysicsServer3D.body_apply_torque`, réappliqué chaque tick (S1) | ragdoll-engineer |
| 1.7 | `BalanceController` : couple correcteur sur le bassin pour le garder vertical | ragdoll-engineer |
| 1.8 | Support au sol : le centre de masse projeté doit rester entre les pieds → déplacement de la pose cible des jambes | ragdoll-engineer |
| 1.9 | État `stunned` : gains à 0 pendant **N ticks** après un impact fort, puis rampe de retour | ragdoll-engineer |
| 1.10 | Overlay debug : centre de masse, polygone de support, vecteurs de couple (`DebugDraw`). 🟡 **Primitives faites** (ligne, flèche, point, polyligne, canaux) ; reste à les brancher sur le rig et le PD | ragdoll-engineer |
| 1.11 | Scènes de test : `ragdoll_balance_test`, `ragdoll_push_recovery_test`, `ragdoll_perf_test` | godot-qa |

**Critères de sortie** (forme définie par `CLAUDE.md` §10)

- Conformité géométrique : `head_y(t=0)` à **1,454 m** ±3 cm, centre de masse à
  **0,840 m** ±3 cm — valeurs *mesurées* au spike S4, pas théoriques.
- Équilibre : 600 ticks sans input → `head_y > 0,92 × head_y(t=0)`.
- Perf : temps de frame physique < 4 ms à 4 persos. ⚠️ **Déjà à 4,351 ms sur rig
  inerte** : ce critère devra être renégocié ou l'implémentation optimisée, avec
  une mesure à l'appui.
- Tous les critères passent **5 fois sur 5** via `make test-full`.

**Puis, une fois l'équilibre obtenu — spike S4-B, reporté ici :**

- Calibrer les impulsions sur le ragdoll *contrôlé* : balayage de 20 à 500 N·s,
  relever le seuil qui déséquilibre et celui qui renverse. Écrire les deux dans
  `baseline.json` (`impulse_stagger_ns`, `impulse_knockdown_ns`).
- Alors seulement, ajouter les deux critères manquants :
  - Résistance : `impulse_stagger_ns` → équilibre toujours vrai 120 ticks après.
  - Récupération : `impulse_knockdown_ns` → chute, puis équilibre de nouveau
    vrai en moins de 240 ticks.

**Pièges connus**
- Gains trop élevés = oscillation/explosion. Commence bas et monte.
- Ne fais pas de `look_at` sur un os simulé. Uniquement des couples.
- Les pieds ont besoin de **friction élevée** (`PhysicsMaterial`) sinon ça patine.
- Le PD doit travailler dans l'espace **local du parent** de l'os, pas en global.
- Avant de soupçonner les gains, vérifie la tâche 1.3 : un centre de masse qui ne
  correspond pas à `RIG_SPEC.md` rend l'équilibre impossible à régler.

---

## Phase 2 — Contrôles, grab, combat

**But** : deux persos contrôlables qui se déplacent, se frappent et s'attrapent.

| # | Tâche | Agent |
|---|---|---|
| 2.1 | `InputFrame` (5 octets, cf. `INPUT_SPEC.md` §2) + `LocalInputSource` — **le contrôleur ne lit jamais `Input` directement** (cf. CLAUDE.md §7) | gameplay-engineer |
| 2.2 | Déplacement : force horizontale sur le bassin, orientation de la pose cible vers la direction du stick | gameplay-engineer |
| 2.3 | Saut : impulsion bassin + extension de la pose des jambes, cooldown en ticks, détection de contact au sol | gameplay-engineer |
| 2.4 | Bras : gâchette L/R → lève le bras (nouvelle pose cible) et augmente sa raideur | gameplay-engineer |
| 2.5 | **Grab**, selon le verdict de **S5** : joint `Generic6DOFJoint3D` main↔corps, ou ressort PD sans joint | gameplay-engineer |
| 2.6 | Rupture du grab : relâchement, stun du porteur, ou **séparation main↔ancre > 0,25 m pendant 6 ticks** | gameplay-engineer |
| 2.7 | Coup de tête / charge : impulsion + application de stun à la cible touchée | gameplay-engineer |
| 2.8 | Escalade : le grab fonctionne aussi sur les surfaces taggées `climbable` | gameplay-engineer |
| 2.9 | Dégâts / KO : jauge par joueur, augmentée par les impacts → stun long | gameplay-engineer |
| 2.10 | Tests : portée et latence du grab, seuil de rupture, pas de grab sur soi-même, stress 5 min | godot-qa |
| 2.11 | **`metrics_test`** : mesure et écrit dans `baseline.json` les valeurs de `docs/METRICS.md` | godot-qa |

**Critères de sortie**
- Un joueur traverse l'arène et saute sur une plateforme **de la hauteur mesurée
  par `metrics_test`**, pas d'une hauteur supposée.
- Un joueur en attrape un autre par le bras et le traîne.
- Un joueur s'accroche à un rebord et s'y maintient.
- Prise établie en moins de **12 ticks** quand la cible est à portée.
- Aucun crash du solveur ni NaN après 5 min de grabs répétés (test de stress).
- `docs/METRICS.md` est renseigné par la mesure : hauteur de saut, portée du
  grab, vitesse de marche, largeur d'épaules.

> ⚠️ La tâche 2.11 n'est pas optionnelle : c'est elle qui donne au
> `level-designer` des chiffres réels au lieu de chiffres inventés. Une arène
> conçue sur un saut supposé de 0,8 m alors qu'il fait 0,55 m est à refaire en
> entier.

---

## Phase 3 — Arène, boucle de manche, premier juice

| # | Tâche | Agent |
|---|---|---|
| 3.1 | Arène blockout n°1, dimensionnée sur `docs/METRICS.md` : plateforme surélevée, bords irréguliers, une rampe | level-designer |
| 3.2 | `KillZone` sous l'arène → signal `player_eliminated` | level-designer |
| 3.3 | `MatchManager` : manches, score, respawn, conditions de victoire | gameplay-engineer |
| 3.4 | Caméra dynamique : cadre tous les joueurs, zoom sur la dispersion, amortie | gameplay-engineer |
| 3.5 | 2 hazards scriptés (plateforme mobile, objet écrasant), pilotés par les ticks | level-designer |
| 3.6 | UI de manche minimale (score, compte à rebours) | gameplay-engineer |
| 3.7 | **Lot de juice minimal** : hitstop ~5 ticks sur impact fort, screenshake amorti, 3 sons (impact, saut, élimination) | gameplay-engineer |
| 3.8 | Tests : élimination émise une seule fois, la manche se termine toujours | godot-qa |

**Critères de sortie**
- Une partie complète en 3 manches se joue du début à la fin sans intervention.
- La caméra ne perd jamais un joueur de vue.
- Exactement **un** signal `player_eliminated` par joueur et par manche.
- Toute manche se termine en moins de 120 s (7200 ticks), y compris si personne
  n'attaque.

> **Pourquoi le juice est ici et pas en phase 7.** Le go/no-go du projet est le
> playtest de fin de phase 4. Sans son d'impact ni hitstop, on fait juger le jeu
> sur sa version la moins agréable : dans ce genre, le retour d'impact représente
> une grande part de la sensation. Le polish complet reste en phase 7 ; ce qui
> remonte ici, c'est le strict minimum pour que le playtest soit honnête.

---

## Phase 4 — Multijoueur local

| # | Tâche | Agent |
|---|---|---|
| 4.1 | `DeviceInputSource` : filtrage des `InputEvent` par `device` id (cf. `docs/INPUT_SPEC.md`) | gameplay-engineer |
| 4.2 | Écran de lobby local : « appuyez sur A pour rejoindre », 2 à 4 joueurs | gameplay-engineer |
| 4.3 | Couleurs/identification par joueur | gameplay-engineer |
| 4.4 | Branchement/débranchement de manette à chaud géré proprement | gameplay-engineer |
| 4.5 | Support clavier pour 1 joueur (dev et solo) | gameplay-engineer |
| 4.6 | Test : 4 sources d'input simulées jouent une manche complète en headless | godot-qa |

**Critères de sortie**
- 4 manettes, 4 persos indépendants, aucune fuite d'input entre joueurs (test
  automatisé : l'input du device 2 ne modifie aucun état des joueurs 1, 3, 4).
- Débrancher la manette 3 en pleine partie ne crashe pas et ne met pas en pause.
- 60 fps stables à 4 joueurs.

> 🎉 **Ici le jeu est réellement jouable.** Fais-y jouer de vraies personnes
> avant d'aller plus loin. Si ce n'est pas drôle en local, le réseau et la 3D
> n'y changeront rien.

---

## Phase 5 — Art 3D généré par Blender

**But** : remplacer les capsules par de vrais personnages et arènes, **sans
casser le tuning physique**.

Principe directeur : la physique reste sur des **formes de collision simples**
(capsules/boîtes). Le maillage Blender est **purement visuel** et suit le
squelette. On ne fait jamais de collision sur un mesh de perso.

| # | Tâche | Agent |
|---|---|---|
| 5.1 | `tools/blender/lib/rig.py` : squelette conforme à `docs/RIG_SPEC.md` (noms d'os **identiques** à ceux du code) | blender-modeler |
| 5.2 | `build_character.py` : corps low-poly stylisé, skinné au rig, export `.glb` | blender-modeler |
| 5.3 | Variantes : paramètres CLI (taille, corpulence, couleur) → plusieurs `.glb` depuis un seul script | blender-modeler |
| 5.4 | Matériaux : couleurs vertex, aucune texture lourde | blender-modeler |
| 5.5 | `build_arena_01.py` : géométrie de l'arène + mesh de collision séparé low-poly (suffixe `-col`) | blender-modeler |
| 5.6 | Pose de référence exportée en animation `idle` (source de la pose cible du PD) | blender-modeler |
| 5.7 | Intégration Godot : scène perso = mesh skinné + `PhysicalBoneSimulator3D` sur le même `Skeleton3D` | ragdoll-engineer |
| 5.8 | **Vérification de cohérence visuel/physique** : le mesh enveloppe bien les capsules, aucun membre visuellement détaché | blender-modeler |
| 5.9 | Test de non-régression : **tous** les tests de la phase 1 passent inchangés, 5 fois sur 5 | godot-qa |

**Critères de sortie**
- `make assets` régénère tout l'art depuis zéro en < 2 min.
- Le perso texturé passe **exactement** les tests de la phase 1, sans qu'aucun
  seuil n'ait été touché.
- Budget respecté : perso < 2 000 tris, arène < 20 000 tris.
- Aucun `.glb` dans le dépôt git.

**Pièges connus**
- Échelle Blender ≠ Godot : applique bien `scale=1`, axe **-Z forward, Y up** à
  l'export glTF. Vérifié une fois pour toutes par le spike S6.
- Les noms d'os sont un **contrat** entre `tools/blender` et `game/characters`.
  Tout renommage casse les deux côtés : ils sont listés dans `RIG_SPEC.md`, que
  personne ne modifie unilatéralement.
- N'exporte pas les contraintes Blender : Godot ne les lit pas.

> **On ne re-tune pas les masses à cette phase.** La tentation est de dériver les
> masses du volume réel du mesh — c'est exactement ce qu'interdit `RIG_SPEC.md`
> §9. Le mesh est visuel ; les masses sont le contrat. Dériver les unes des
> autres invaliderait tout le tuning de la phase 1 au pire moment possible.

---

## Phase 6 — Online (host autoritaire)

Lis `docs/NETCODE.md` avant de commencer. Résumé : la physique de ragdoll n'est
**pas déterministe**, donc ni lockstep ni rollback. Le host simule, les clients
envoient des inputs et affichent un état interpolé.

| # | Tâche | Agent |
|---|---|---|
| 6.1 | Couche transport : `ENetMultiplayerPeer`, host/join par IP, lobby | netcode-engineer |
| 6.2 | `RemoteInputSource` : inputs **groupés par 3** en `unreliable_ordered`, numérotés par tick (cf. `INPUT_SPEC.md` §2) | netcode-engineer |
| 6.3 | Le host fait autorité : seuls ses `PhysicalBone3D` sont simulés | netcode-engineer |
| 6.4 | Sérialisation d'état : bassin (float32) + quaternions d'os quantifiés ; snapshot à 20–30 Hz | netcode-engineer |
| 6.5 | **Keyframes et acquittement** : snapshot complet périodique + ack client, sans quoi le delta diverge (cf. `NETCODE.md` §3.1) | netcode-engineer |
| 6.6 | Clients : ragdoll kinematic, interpolation entre snapshots, buffer ~100 ms | netcode-engineer |
| 6.7 | Delta/priorité : n'envoyer que les os qui ont bougé au-delà d'un epsilon, par rapport au **dernier snapshot acquitté** | netcode-engineer |
| 6.8 | Prédiction locale du bassin du client + réconciliation douce (lerp, jamais de snap sous 1,5 m d'erreur) | netcode-engineer |
| 6.9 | Gestion déconnexion, écran « connexion perdue » | netcode-engineer |
| 6.10 | Simulation de latence et de perte dans les tests | godot-qa |
| 6.11 | Mesure du budget : bande passante réelle à 4 joueurs, **montante et descendante, overhead paquet inclus** | godot-qa |
| 6.12 | Mesure de la dérive : écart max de pose entre host et client, en cm | godot-qa |

**Critères de sortie**
- 2 machines, 4 joueurs, une manche complète.
- À 150 ms de latence et 2 % de perte, le grab reste utilisable.
- Perte de 10 snapshots consécutifs : gel puis reprise propre, **et retour à un
  état correct** (c'est le test qui valide 6.5).
- Bande passante montante côté host < **128 kbps** à 4 joueurs, mesurée
  overhead compris.
- Écart de pose host↔client < 5 cm en régime normal.

---

## Phase 7 — Polish et build

| # | Tâche | Agent |
|---|---|---|
| 7.1 | Menu principal, options, remapping | gameplay-engineer |
| 7.2 | Personnalisation de perso (couleurs, accessoires générés) | blender-modeler |
| 7.3 | SFX complets, musique | — |
| 7.4 | Particules et « juice » complet (le minimum est déjà en 3.7) | gameplay-engineer |
| 7.5 | 2 arènes supplémentaires | level-designer |
| 7.6 | Profilage et optimisation (objectif 60 fps à 4 joueurs) | godot-qa |
| 7.7 | Export Windows/Linux, test sur machine vierge | godot-qa |

---

## Ce qu'on ne fait volontairement pas (pour l'instant)

- Matchmaking public / NAT punchthrough (nécessiterait Steamworks via GodotSteam).
- Splitscreen à caméras séparées.
- IA / bots.
- Netcode déterministe ou rollback : incompatible avec ce type de physique.
- Cross-play.
- Migration d'hôte : migrer l'autorité sur une simulation non déterministe est un
  chantier à part entière.

Si l'une de ces lignes devient nécessaire, elle fait l'objet d'une nouvelle
phase, pas d'un ajout discret au milieu d'une autre.
