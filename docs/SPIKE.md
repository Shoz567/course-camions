# SPIKE.md — Phase 0.5 : valider les hypothèses avant de construire dessus

---

## Pourquoi ce document existe

Le reste du pack décrit un plan cohérent. Mais ce plan repose sur **six
hypothèses d'API Godot et Jolt que personne n'a vérifiées**. Trois d'entre elles
portent la phase 1 en entier — c'est-à-dire 60 % de la difficulté du projet.

Si l'une est fausse, on ne le découvre pas en une heure : on le découvre au bout
de plusieurs jours de tuning inexplicable, en croyant que le problème vient des
gains du PD. C'est le scénario d'échec le plus probable de ce projet, et il est
évitable pour deux jours de travail.

**Règle : tant qu'un spike n'a pas répondu, le code de production qui en dépend
ne s'écrit pas.**

## Ce que ce spike n'est pas

- Ce n'est **pas** le début de la phase 1. Aucun tuning, aucune recherche
  d'équilibre, aucune jolie architecture.
- Le code produit est **jetable**. Il vit dans `spike/`, il est git-ignoré, et
  il est supprimé à la fin. S'il finit en production, le spike a échoué dans son
  intention.
- Le livrable n'est pas du code : c'est **six réponses et les corrections à
  apporter aux documents du dépôt.**

Durée cible : **1 à 2 jours.** Si un spike déborde, c'est qu'il a trouvé un vrai
problème — arrête-toi et remonte-le, ne t'acharne pas.

---

## S1 — Comment applique-t-on un couple continu à un `PhysicalBone3D` ?

**Criticité : bloquante.** C'est la fondation du PD-controller, donc de toute la
phase 1.

**L'hypothèse à vérifier.** `CLAUDE.md` §6 et l'agent `ragdoll-engineer`
supposaient initialement `bone.apply_torque(v)` et `bone.angular_velocity`. Or
`PhysicalBone3D` hérite de `PhysicsBody3D`, **pas** de `RigidBody3D` : ces
membres n'y sont pas nécessairement exposés.

**Protocole.**

1. Une scène : un sol, un `Skeleton3D` avec deux os, un
   `PhysicalBoneSimulator3D`, deux `PhysicalBone3D` reliés par un
   `Generic6DOFJoint3D`.
2. Dans un script, tester dans l'ordre et noter ce qui compile et ce qui agit
   réellement sur le corps :
   - `bone.apply_torque(Vector3.UP)` — existe ? a un effet ?
   - `bone.apply_central_force(...)` — idem
   - `bone.angular_velocity` en lecture — propriété ou `get_angular_velocity()` ?
   - `_integrate_forces(state)` sur une classe dérivée de `PhysicalBone3D` :
     `state.apply_torque()`, `state.angular_velocity` — la virtuelle est-elle
     appelée quand le bone est simulé ?
   - `PhysicsServer3D.body_apply_torque(bone.get_rid(), v)` — effet ?
3. Mesure objective : appliquer un couple constant sur l'axe Y pendant
   60 ticks, sans gravité, et logger `angular_velocity.y` tous les 10 ticks.
   Un couple qui « existe » mais ne fait rien bouger se voit immédiatement.

**Réponse attendue.** *La* ligne de code canonique à écrire dans le PD, plus la
réponse à : le couple doit-il être réappliqué chaque tick ou est-il persistant ?

**Impact si l'hypothèse est fausse.** Réécriture de `CLAUDE.md` §6, de la section
« forme canonique » de `ragdoll-engineer.md`, et probablement passage de tout le
solveur en classe dérivée avec `_integrate_forces`.

---

## S2 — Jolt honore-t-il les limites et l'amortissement des `Generic6DOFJoint3D` ?

**Criticité : bloquante pour le rig (phase 1) et le grab (phase 2).**

**L'hypothèse à vérifier.** Tout le squelette (12 joints) et la mécanique de
grab reposent sur `Generic6DOFJoint3D`. `gameplay-engineer` spécifie pour le
grab « axes angulaires libres mais **amortis** — une prise molle, pas une
soudure ». Jolt et Godot Physics n'implémentent pas ce joint de façon
identique : certains paramètres (ressorts angulaires, soft limits, moteurs)
peuvent être partiellement ou pas du tout supportés.

**Protocole.**

1. Pendule simple : un corps statique, un corps libre, un `Generic6DOFJoint3D`
   entre les deux. Gravité active.
2. Test A — **limites angulaires** : fixer `angular_limit_x` à ±30°, lâcher le
   pendule, logger l'angle max atteint. Est-il borné à 30° ? Déborde-t-il ? De
   combien sous forte charge (masse ×10) ?
3. Test B — **amortissement** : activer `angular_damping` / le ressort du joint,
   lâcher le pendule, logger l'amplitude sur 300 ticks. La décroissance
   est-elle visible ? Comparer avec le paramètre à 0 : **si les deux courbes
   sont identiques, le paramètre est ignoré.**
4. Test C — **verrouillage** : verrouiller les 3 axes linéaires
   (lower = upper = 0) comme l'impose `RIG_SPEC.md` §4. Mesurer la séparation
   résiduelle entre les deux corps sous charge. Combien de cm de dérive ?

**Réponse attendue.** La liste des paramètres de `Generic6DOFJoint3D` réellement
actifs sous Jolt, et l'ordre de grandeur de la dérive des joints sous charge.

**Impact si l'hypothèse est fausse.** Si l'amortissement angulaire est ignoré, le
grab par joint donne une soudure rigide et **le plan B du grab (§S5) devient le
plan A**. Si la dérive linéaire est importante, `NETCODE.md` §5.3 (reconstruction
de la pose par cinématique directe côté client) est à revoir.

---

## S3 — Comment fournir une pose cible sans entrer en conflit avec le simulateur ?

**Criticité : bloquante pour `PoseProvider` (tâche 1.4).**

**L'hypothèse à vérifier.** La tâche 1.4 dit « une pose de référence fournie par
un `AnimationPlayer` ou en dur », comme si c'était un détail. Or
`PhysicalBoneSimulator3D` **écrit les poses d'os du `Skeleton3D`** pendant qu'il
simule. Un `AnimationPlayer` qui écrit dans le même squelette entre en conflit
direct : selon l'ordre des `SkeletonModifier3D`, l'un écrase l'autre.

**Protocole.**

1. Un `Skeleton3D` + `PhysicalBoneSimulator3D` en simulation, et un
   `AnimationPlayer` qui joue une pose `idle` sur le même squelette.
2. Logger, pour un os donné et sur 60 ticks :
   `skeleton.get_bone_pose_rotation(i)` et la rotation réelle du
   `PhysicalBone3D`. Divergent-elles ? Laquelle gagne ?
3. Tester la solution de repli : un **second `Skeleton3D` de référence**, non
   simulé, animé, dont on lit les poses cibles. Coût CPU d'un squelette
   supplémentaire par personnage à 4 joueurs ?
4. Tester la troisième voie : pas de squelette du tout pour la cible, juste un
   `PackedArray` de quaternions calculé une fois et stocké dans
   `CharacterTuning`.

**Réponse attendue.** L'architecture retenue pour `PoseProvider`, avec son coût
mesuré.

**Impact.** Détermine l'architecture de `PoseProvider`, et donc l'interface par
laquelle `gameplay-engineer` lèvera un bras en phase 2.

---

## S4 — Quel est le coût CPU réel, et quelles impulsions de test ont du sens ?

**Criticité : haute.** Valide à la fois le critère de perf de la phase 1 et les
seuils du catalogue de tests.

**Protocole, partie A — perf.**

1. Instancier 1, puis 2, puis 4 rigs complets (13 corps, 12 joints chacun), en
   chute libre puis au repos sur un sol.
2. Mesurer le **temps de frame total en headless** — attention :
   `Performance.TIME_PHYSICS_PROCESS` mesure le temps du script, pas celui du
   solveur. Le coût du solveur se déduit du temps de frame total à charge
   physique variable, ou se lit dans le profileur de l'éditeur.
3. Noter la courbe : le coût est-il linéaire en nombre de persos, ou explose-t-il
   (contacts croisés, îlots de solveur fusionnés) ?
4. Refaire avec `velocity_steps` / `position_steps` de Jolt doublés : quel est le
   surcoût exact de la soupape recommandée par `CLAUDE.md` §6 ?

**Protocole, partie B — calibrer les impulsions.**

Le catalogue de `CLAUDE.md` §10 propose 60 N·s pour « résiste » et 300 N·s pour
« tombe et se relève ». Ces valeurs sont des paris. Sur un rig inerte de 70 kg :

1. Appliquer une impulsion latérale croissante sur le torse (20, 40, 60, 100,
   200, 300, 500 N·s), une par run.
2. Logger le déplacement du bassin et la hauteur de la tête après 120 ticks.
3. Identifier les deux seuils réels : celui qui déséquilibre sans faire tomber,
   et celui qui fait tomber franchement.

**Réponse attendue.** Le budget CPU réel sur cette machine, écrit dans
`docs/ENVIRONMENT.md`, et **les deux valeurs d'impulsion mesurées**, qui
remplacent les valeurs provisoires de `CLAUDE.md` §10.

---

## S5 — Peut-on mesurer la contrainte d'un joint, et faut-il un grab sans joint ?

**Criticité : haute pour la phase 2.** Ce spike peut attendre la fin de la
phase 1, mais pas le début de la phase 2.

**L'hypothèse à vérifier.** Trois documents spécifient une rupture de grab
« au-delà de 600 N ». À notre connaissance, **Godot n'expose aucune API pour lire
la force interne d'un joint**. Si c'est confirmé, ce critère n'est pas
implémentable tel quel et doit être reformulé.

**Protocole.**

1. Deux corps reliés par un `Generic6DOFJoint3D`, axes linéaires verrouillés.
   Tirer l'un avec une force croissante.
2. Chercher, dans cet ordre : une propriété de force sur le joint, une donnée
   dans `PhysicsDirectBodyState3D`, un retour via `PhysicsServer3D`. Conclure
   par oui ou non.
3. Mesurer l'observable de remplacement : **la séparation** entre les deux points
   d'ancrage en fonction de la force appliquée. Tracer la courbe
   force → séparation. Elle donne la conversion : « 0,25 m de séparation
   correspond à environ X N ».
4. **Prototyper le plan B** : pas de joint du tout. Un ressort PD qui tire la
   main vers le point de prise par `apply_force`, avec rupture quand la distance
   dépasse un seuil. Comparer les deux sur : stabilité à 4 joueurs en chaîne,
   sensation de mollesse, simplicité de la rupture.

**Réponse attendue.** Le seuil de rupture exprimé en mètres de séparation, la
courbe de conversion, et un verdict argumenté joint *vs* ressort.

**Pourquoi le plan B mérite d'être pris au sérieux.** Créer et détruire des
joints à chaud, à 4 joueurs, en chaîne, est la source n°1 d'instabilité de
solveur de ce genre de jeu — le pack le reconnaît déjà en exigeant un test de
stress de 5 minutes. Un ressort PD n'a aucun de ces problèmes, se réplique
trivialement en phase 6 (aucun joint à créer côté client) et rend la rupture
mesurable par construction. Il est aussi plus mou, ce qui est précisément
l'effet recherché.

---

## S6 — L'import glTF de Blender arrive-t-il à l'échelle attendue ?

**Criticité : moyenne.** Peut être fait plus tard, mais **avant** la phase 5, et
il ne coûte qu'une heure.

**L'hypothèse à vérifier.** `ART_PIPELINE.md` §3 affirme qu'un export avec
`export_yup=True` et transforms appliquées donne 1 unité = 1 m dans Godot. C'est
l'erreur n°1 de la chaîne Blender→Godot, et elle ne se voit qu'une fois tout le
pipeline écrit.

**Protocole.**

1. Un script Blender minimal qui exporte un **cube de 1 m** et une **armature de
   deux os aux longueurs connues**, avec les réglages exacts de
   `lib/export.py`.
2. Importer dans Godot, mesurer l'AABB du mesh et la longueur des os.
3. Vérifier l'orientation : le cube regarde-t-il bien vers −Z ?
4. Vérifier que les noms d'os survivent à l'aller-retour **sans suffixe ajouté**
   (Godot renomme parfois en cas de collision de noms). C'est le contrat de
   `RIG_SPEC.md` qui est en jeu.

**Réponse attendue.** Confirmation chiffrée (« cube mesuré à 1,000 m ») ou la
correction à apporter à `lib/export.py`.

---

## Livrable de la phase 0.5

Un rapport unique, et rien d'autre :

| Spike | Question | Réponse | Fichiers à corriger |
|---|---|---|---|
| S1 | couple continu sur `PhysicalBone3D` | | `CLAUDE.md` §6, `ragdoll-engineer.md` |
| S2 | params de joint actifs sous Jolt | | `RIG_SPEC.md` §4, `gameplay-engineer.md` |
| S3 | pose cible sans conflit | | `PLAN.md` 1.4, `ragdoll-engineer.md` |
| S4 | coût CPU et impulsions réelles | | `CLAUDE.md` §10, `ENVIRONMENT.md` |
| S5 | force de joint et plan B du grab | | `CLAUDE.md` §10, `PLAN.md` 2.5–2.6 |
| S6 | échelle et noms d'os à l'import | | `ART_PIPELINE.md` §3 |

Puis : **les corrections sont appliquées aux documents**, `spike/` est supprimé,
et la phase 0 peut commencer sur des bases vérifiées.

Une phase 0.5 qui se termine sans avoir corrigé un seul document est suspecte :
cela signifie soit que les six hypothèses étaient justes du premier coup, soit
que les spikes n'ont pas vraiment cherché.
