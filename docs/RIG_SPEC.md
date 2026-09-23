# RIG_SPEC.md — Squelette, masses et articulations

**Ce fichier est un contrat partagé** entre `tools/blender/` (qui génère le rig)
et `game/characters/` (qui le simule). Les noms d'os doivent être identiques des
deux côtés.

**Personne ne possède ce fichier.** Ni `ragdoll-engineer`, ni `blender-modeler` :
un contrat dont une des deux parties est propriétaire n'est pas un contrat. Toute
modification se demande, se justifie par une mesure, et se fait dans un commit
qui resynchronise **les deux** côtés en même temps (cf. `CLAUDE.md` §8).

---

## 1. Échelle

- 1 unité Godot = 1 mètre. Blender exporte avec `scale = 1.0`, transforms
  appliquées. Vérifié par le spike **S6**.
- Personnage debout : **1,60 m**, masse totale **70 kg**.
- Proportions volontairement cartoon : tête large, membres courts et épais.
  C'est ce qui rend le ragdoll lisible et drôle.

Les longueurs de la table §3 **somment exactement à 1,60 m** sur la chaîne
verticale (§4). Ce n'est pas une coïncidence et ce n'est pas décoratif : si tu
modifies une longueur, tu casses la somme, et tu dois compenser ailleurs.

## 2. Hiérarchie des os

13 os simulés. La racine physique est `pelvis`.

```
pelvis
├── spine
│   ├── head
│   ├── upperarm_l → forearm_l
│   └── upperarm_r → forearm_r
├── thigh_l → shin_l → foot_l
└── thigh_r → shin_r → foot_r
```

Les mains ne sont **pas** des os physiques : chaque `forearm_*` porte un
`Marker3D` nommé `hand_l` / `hand_r` à son extrémité, qui porte l'`Area3D` de
détection du grab et sert d'ancre au joint (ou au ressort, selon le verdict du
spike **S5**).

## 3. Table de référence

| Os | Parent | Longueur (m) | Masse (kg) | Forme de collision |
|---|---|---|---|---|
| `pelvis` | — | 0,17 | 12,0 | boîte 0,30 × 0,17 × 0,20 |
| `spine` | pelvis | 0,38 | 19,0 | capsule r=0,17 |
| `head` | spine | 0,28 | 5,0 | sphère r=0,15 |
| `upperarm_l` | spine | 0,26 | 2,5 | capsule r=0,07 |
| `upperarm_r` | spine | 0,26 | 2,5 | capsule r=0,07 |
| `forearm_l` | upperarm_l | 0,28 | 1,8 | capsule r=0,06 |
| `forearm_r` | upperarm_r | 0,28 | 1,8 | capsule r=0,06 |
| `thigh_l` | pelvis | 0,36 | 8,0 | capsule r=0,09 |
| `thigh_r` | pelvis | 0,36 | 8,0 | capsule r=0,09 |
| `shin_l` | thigh_l | 0,33 | 3,5 | capsule r=0,07 |
| `shin_r` | thigh_r | 0,33 | 3,5 | capsule r=0,07 |
| `foot_l` | shin_l | 0,20 | 1,2 | boîte 0,10 × 0,08 × 0,22 |
| `foot_r` | shin_r | 0,20 | 1,2 | boîte 0,10 × 0,08 × 0,22 |

**Total : 70,0 kg.** Si tu modifies une masse, ajuste une autre pour conserver le
total — le tuning des couples en dépend directement.

Pour `foot_*`, la « longueur » 0,20 est la longueur du pied vers l'avant ; c'est
la **hauteur de boîte 0,08** qui compte dans la chaîne verticale (hauteur de
cheville).

## 4. Vérification géométrique — chaîne verticale

C'est la table que tout le monde oublie d'écrire, et c'est celle qui permet
d'écrire des tests qui ont un sens. Positions au repos, debout, jambes tendues,
sol à y = 0 :

| Point | Calcul | y (m) |
|---|---|---|
| Sol | — | 0,00 |
| Cheville (haut de `foot`) | 0,08 | 0,08 |
| Genou (haut de `shin`) | 0,08 + 0,33 | 0,41 |
| Hanche (haut de `thigh`) | 0,41 + 0,36 | 0,77 |
| Haut du bassin | 0,77 + 0,17 | 0,94 |
| Base du cou (haut de `spine`) | 0,94 + 0,38 | 1,32 |
| **Sommet du crâne** | 1,32 + 0,28 | **1,60** ✅ |

### Centre de masse au repos

| Segment | Masse totale (kg) | y du centre (m) | Moment (kg·m) |
|---|---|---|---|
| `foot_*` ×2 | 2,4 | 0,04 | 0,096 |
| `shin_*` ×2 | 7,0 | 0,245 | 1,715 |
| `thigh_*` ×2 | 16,0 | 0,59 | 9,440 |
| `pelvis` | 12,0 | 0,855 | 10,260 |
| `spine` | 19,0 | 1,13 | 21,470 |
| `head` | 5,0 | 1,46 | 7,300 |
| `upperarm_*` ×2 | 5,0 | 1,15 | 5,750 |
| `forearm_*` ×2 | 3,6 | 0,88 | 3,168 |
| **Total** | **70,0** | | **59,199** |

**Centre de masse : 59,199 / 70,0 = 0,846 m**, soit **53 % de la hauteur**.
Légèrement en avant des chevilles.

C'est la donnée la plus importante du document pour l'équilibre. Le spike **S4**
la vérifie par la mesure : si le centre de masse simulé s'écarte de plus de
**3 cm** de 0,85 m, quelque chose ne correspond pas à cette table — cherche là
avant de toucher aux gains du PD.

### Conséquence pour les tests

Le centre de l'os `head` est à **y = 1,46 m** au repos. C'est cette valeur, et
non la hauteur totale, que mesure un test d'équilibre.

> ✅ **Vérifié par la mesure** (spike S4, rig inerte de 13 corps) : masse totale
> 70,0 kg, `head_y` = **1,454 m**, centre de masse = **0,840 m**. Les trois
> tombent à moins d'un centimètre des valeurs calculées ci-dessus. Cette table
> n'est pas théorique : elle décrit le rig tel qu'il se comporte.
>
> Attention en l'implémentant : `physical_bones_start_simulation()` positionne
> les corps d'après les **`bone_rest` du squelette**. Les transforms posés
> directement sur les `PhysicalBone3D` sont ignorés — c'est l'erreur qui a
> produit un personnage de 24 cm au premier essai.

Ne code **jamais** un seuil absolu du type « tête > 1,3 m » : il serait à 11 %
de la valeur au repos, c'est-à-dire à la limite du bruit d'une flexion de genoux
normale. Le critère s'écrit en ratio mesuré au tick 0 de la scène elle-même
(cf. `CLAUDE.md` §10 règle (a)) :

```
head_y(t = 600 ticks) > 0,92 × head_y(t = 0)
```

## 5. Limites articulaires

Toutes les articulations sont des `Generic6DOFJoint3D` avec les 3 axes linéaires
**verrouillés** (lower = upper = 0) et les axes angulaires limités.

### Ce que Jolt honore réellement (mesuré au spike S2)

Un `PhysicalBone3D` porte **son propre joint** via `joint_type` : on ne crée pas
de nœud `Generic6DOFJoint3D` séparé entre les os. Ses limites sont des
propriétés **dynamiques** `joint_constraints/<axe>/…`, invisibles dans `ClassDB`
(il faut instancier l'objet pour les lister).

| Paramètre | Sous Jolt |
|---|---|
| `angular_limit_enabled`, `angular_limit_upper`, `angular_limit_lower` | ✅ honoré |
| `angular_damping` (de la limite) | ❌ **ignoré** |
| `angular_restitution` | ❌ **ignoré** |
| force limit angulaire | ❌ **ignoré** |
| `linear_limit_softness`, `linear_damping` | ❌ **ignoré** |
| `angular_spring_*`, `linear_spring_*` | ✅ supporté |

Deux conséquences directes :

- **N'écris pas les paramètres ignorés.** Ils ne produisent aucun effet et
  donnent l'illusion d'un réglage qui n'existe pas — Jolt émet un avertissement,
  mais il se perd dans la sortie.
- **Pour une articulation molle, passe par `angular_spring_*`**, jamais par
  l'amortissement de limite. C'est ce qui a fait basculer le grab vers un
  ressort PD (cf. `docs/SPIKE.md` S5).

Un joint 6DOF à axes linéaires verrouillés est par ailleurs une **soudure
parfaite** : séparation nulle mesurée jusqu'à 2000 N de traction. Aucune dérive,
mais aussi aucune rupture possible.

Angles en degrés, dans le repère local du parent (X = flexion, Y = torsion,
Z = abduction).

| Articulation | X (flexion) | Y (torsion) | Z (abduction) |
|---|---|---|---|
| pelvis → spine | −20 / +35 | −30 / +30 | −25 / +25 |
| spine → head | −30 / +30 | −50 / +50 | −30 / +30 |
| spine → upperarm | −80 / +160 | −60 / +60 | −10 / +100 |
| upperarm → forearm | 0 / +140 | −70 / +70 | 0 / 0 |
| pelvis → thigh | −25 / +110 | −30 / +30 | −40 / +25 |
| thigh → shin | −135 / 0 | 0 / 0 | 0 / 0 |
| shin → foot | −25 / +35 | 0 / 0 | −12 / +12 |

Coude et genou sont des charnières : verrouille leurs axes inutiles plutôt que de
les laisser « presque » libres, ça soulage beaucoup le solveur.

## 6. Matériaux physiques

| Partie | Friction | Rebond |
|---|---|---|
| `foot_*` | **1,2** | 0,0 |
| `forearm_*` (mains) | 0,9 | 0,0 |
| torse, tête, cuisses | 0,4 | 0,05 |

La friction élevée des pieds n'est pas cosmétique : sans elle, le personnage
patine et aucun réglage de PD ne le rattrapera.

## 7. Couches de collision

| Couche | Usage |
|---|---|
| 1 `world` | géométrie statique de l'arène |
| 2 `player_body` | os des personnages |
| 3 `grab_sensor` | `Area3D` des mains |
| 4 `climbable` | rebords agrippables |
| 5 `hazard` | objets dangereux |
| 6 `kill_zone` | zone d'élimination |

Les os d'un même personnage **ne se collisionnent pas entre eux**
(auto-exclusion par `collision_exceptions`), sinon le solveur passe son temps à
résoudre des auto-intersections.

## 8. Pose de référence (`idle`)

Exportée depuis Blender comme unique animation. C'est la cible par défaut du
PD-controller — la façon dont elle est **fournie** au solveur sans entrer en
conflit avec `PhysicalBoneSimulator3D` est l'objet du spike **S3**.

- Debout, pieds écartés de 0,25 m, genoux fléchis de **8°** (jamais 0 : une jambe
  parfaitement tendue est une singularité pour le contrôleur).
- Bras le long du corps, coudes fléchis de 15°, épaules en abduction de 8°.
- Torse vertical, tête droite.

Note : avec 8° de flexion des genoux, la hauteur réelle au repos est très
légèrement inférieure aux 1,60 m de la §4 (~1 cm). C'est sans conséquence
puisque les seuils sont des ratios mesurés au tick 0 — mais c'est la raison pour
laquelle ils sont des ratios.

## 9. Le mesh n'a aucune autorité sur la physique

Rappel, parce que c'est la tentation de la phase 5 : les masses et les longueurs
de ce fichier sont **le contrat**, et le maillage visuel s'y conforme. On ne
dérive jamais les masses du volume du mesh généré par Blender.

Faire l'inverse invaliderait tout le tuning de la phase 1 le jour où l'art
arrive — c'est-à-dire au pire moment possible, quand plus personne ne se souvient
pourquoi les gains valent ce qu'ils valent.

## 10. Ordre de tuning recommandé

1. Masses et centre de masse (ce document, §4).
2. Limites articulaires : le perso inerte doit tomber de façon crédible, sans
   membre qui se retourne.
3. Gains du bassin (verticalité).
4. Gains des hanches, puis genoux, puis chevilles.
5. Torse, puis bras, puis tête.

Ne touche jamais à deux niveaux à la fois.
