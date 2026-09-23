# INPUT_SPEC.md — Entrées, manettes, multijoueur local

---

## 1. Le principe qui structure tout

Le code de gameplay ne lit **jamais** `Input.*`. Il consomme une `InputFrame`
fournie par une `InputSource`.

```
LocalKeyboardSource ─┐
DeviceInputSource ───┼──► InputFrame ──► PlayerController ──► CharacterRagdoll
RemoteInputSource ───┤
ScriptedInputSource ─┘
```

C'est ce qui permet, sans toucher au gameplay :
- le multijoueur local (une source par manette),
- l'online (source alimentée par RPC),
- les tests headless (source scriptée),
- les rejeux et le debug.

Une seule violation de cette règle coûte une réécriture en phase 6.

## 2. `InputFrame`

```gdscript
class_name InputFrame extends RefCounted

var tick: int = 0
var move: Vector2 = Vector2.ZERO   # normalisé, dead-zone déjà appliquée
var jump: bool = false             # impulsion : vrai un seul tick
var grab_left: bool = false        # état maintenu
var grab_right: bool = false
var special: bool = false          # coup de tête / charge

func to_bytes() -> PackedByteArray
static func from_bytes(b: PackedByteArray) -> InputFrame
```

### Format binaire : 5 octets

| Champ | Codage | Octets |
|---|---|---|
| `tick` | `uint16`, modulo 65536 | 2 |
| `move.x`, `move.y` | 2 × `int8` (−127..127) | 2 |
| `jump`, `grab_left`, `grab_right`, `special`, réserve | bitfield | 1 |
| **Total** | | **5** |

À 60 Hz : **300 octets/s par joueur** de charge utile. Négligeable.

### Ce qui coûte vraiment : le nombre de paquets

C'est le point que la charge utile masque. Un datagramme UDP transporte environ
**28 octets d'en-têtes IP/UDP**, plus l'en-tête ENet. Envoyer 5 octets utiles
60 fois par seconde coûte donc en réalité :

```
60 paquets/s × (5 o utiles + ~48 o d'en-têtes) ≈ 3,2 ko/s montant par client
```

Soit **dix fois la charge utile**, et le même ordre de grandeur que le flux de
snapshots descendant. L'optimisation n'est pas de compresser les 5 octets : elle
est de **réduire le nombre de paquets**.

**Règle : grouper 3 `InputFrame` consécutives par paquet, envoyé à 20 Hz.**

```
20 paquets/s × (15 o utiles + ~48 o d'en-têtes) ≈ 1,26 ko/s
```

Gain de 60 %, pour un coût de latence d'au plus 2 ticks (33 ms) — largement
absorbé par le buffer d'interpolation de 100 ms côté client. Et le groupement
apporte une redondance gratuite : si un paquet est perdu, le suivant contient
encore deux des trois frames manquantes.

Cette structure se prévoit **dès la phase 2**, dans la façon dont `InputFrame`
se sérialise. Elle ne s'implémente qu'en phase 6.

## 3. Mapping manette (XInput / DualShock)

| Action | Manette | Clavier (joueur 1, dev) |
|---|---|---|
| `move` | stick gauche | ZQSD |
| `jump` | A / Croix | Espace |
| `grab_left` | LT (gâchette) | Clic gauche |
| `grab_right` | RT (gâchette) | Clic droit |
| `special` | B / Rond | E |
| `pause` | Start | Échap |

Gâchettes analogiques : seuil de déclenchement à **0,5**, hystérésis à **0,35**
pour le relâchement (sinon ça clignote et le grab se fait et se défait).

Dead-zone du stick : **radiale à 0,20**, pas par axe. Une dead-zone par axe rend
les diagonales inconfortables.

## 4. Multijoueur local : filtrage par device

Godot ne propose pas d'actions par joueur. La bonne approche est de lire les
événements bruts et de les router par `device` id :

```gdscript
class_name DeviceInputSource extends InputSource

@export var device_id: int = 0

func _input(event: InputEvent) -> void:
    if event.device != device_id:
        return
    # ... mise à jour de l'état interne
```

**Ne crée pas** d'actions `p1_jump`, `p2_jump`, `p3_jump`… dans la map d'input :
ça ne monte pas en nombre de joueurs, ça ne gère pas le branchement à chaud, et
c'est ingérable à remapper.

Le clavier a `device == -1` par convention dans ce projet (les manettes commencent
à 0), ce qui permet de le traiter comme une source parmi d'autres.

## 5. Lobby local

1. Écran « appuyez sur A pour rejoindre ».
2. À la première pression d'un device inconnu → création d'un slot joueur lié à
   ce `device_id`, attribution d'une couleur.
3. B pour quitter son slot. Start (par le joueur 1) pour lancer.
4. Entre 2 et 4 joueurs.

Le mapping `device_id → player_slot` est détenu par `GameState` et **persiste
pendant tout le match**. Ne réattribue jamais les slots en cours de partie.

## 6. Branchement à chaud

`Input.joy_connection_changed` :
- **manette branchée** en partie → elle n'entre pas dans le match en cours, elle
  attend le prochain lobby ;
- **manette débranchée** en partie → le perso reste en jeu, inerte (aucune
  `InputFrame` produite, donc il s'effondre naturellement), et une icône
  « manette déconnectée » s'affiche ;
- la même manette rebranchée reprend **son** slot, via son `device_id`.

Ne mets jamais le jeu en pause sur une déconnexion dans un jeu de couch versus :
c'est plus frustrant que le problème lui-même.

## 7. Tests

`ScriptedInputSource` rejoue une séquence d'`InputFrame` prédéfinie, utilisée par
tous les tests headless. Toutes les durées sont en **ticks**, jamais en secondes
(cf. `CLAUDE.md` §7) :

```gdscript
var src := ScriptedInputSource.new()
src.push_hold(&"move", Vector2.RIGHT, 120)   # 120 ticks (~2 s)
src.push_once(&"jump")
src.push_hold(&"grab_right", true, 60)
```

C'est aussi la source utilisée par `metrics_test` (tâche 2.11) pour mesurer les
valeurs de `docs/METRICS.md`. Elle doit donc être **parfaitement reproductible** :
aucune lecture de temps réel, aucun aléatoire non seedé.

Critère de la phase 4 : avec 4 `DeviceInputSource` simulées, l'input du device 2
ne modifie **aucun** état du joueur 1, 3 ou 4 (test automatisé, pas visuel).
