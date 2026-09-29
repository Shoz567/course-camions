# INPUT_SPEC.md — Entrées, manettes, écran partagé

---

## 1. Le principe qui structure tout

Le code de conduite ne lit **jamais** `Input.*`. Il consomme une `InputFrame`
fournie par une `InputSource`.

```
KeyboardInputSource ─┐
DeviceInputSource ───┼──► InputFrame ──► Truck.set_input() ──► Truck (RigidBody3D)
RemoteInputSource ───┤
ScriptedInputSource ─┘

LocalInputSource = première manette + clavier fusionnés (joueur solo, dev)
```

C'est ce qui permet, sans toucher au camion :
- l'écran partagé (une source par manette) ;
- l'online (une source alimentée par le réseau) ;
- les tests headless (une source scriptée qui « conduit » le camion) ;
- les rejeux et le debug.

Une seule violation de cette règle coûte une réécriture en phase 6.

## 2. `InputFrame`

```gdscript
class_name InputFrame extends RefCounted

var tick: int = 0
var steer: float = 0.0        # -1 (gauche) .. +1 (droite), zone morte appliquée
var throttle: float = 0.0     # 0 .. 1
var brake: float = 0.0        # 0 .. 1 ; à l'arrêt, freiner = marche arrière
var handbrake: bool = false   # état maintenu : dérapage
var boost: bool = false       # état maintenu
var reset: bool = false       # front montant : vrai un seul tick
var honk: bool = false        # front montant : coup de klaxon
var cargo: bool = false       # front montant : largage de cargo

func to_bytes() -> PackedByteArray
static func from_bytes(b: PackedByteArray) -> InputFrame
```

La caméra (regard arrière, changement de vue) n'est **pas** dans l'`InputFrame` :
elle ne modifie pas la simulation, elle reste locale au joueur.

### Format binaire : 6 octets

| Champ | Codage | Octets |
|---|---|---|
| `tick` | `uint16`, modulo 65536 | 2 |
| `steer` | `int8` (−127..127) | 1 |
| `throttle` | `uint8` (0..255) | 1 |
| `brake` | `uint8` (0..255) | 1 |
| `handbrake`, `boost`, `reset`, `honk` (klaxon), `cargo`, réserve | bitfield | 1 |
| **Total** | | **6** |

À 60 Hz : 360 octets/s de charge utile par joueur. Négligeable.

### Ce qui coûte vraiment : le nombre de paquets

Un datagramme UDP transporte ~48 octets d'en-têtes (IP, UDP, ENet). Envoyer
6 octets 60 fois par seconde coûte donc ~3,2 ko/s par client, soit **neuf fois
la charge utile**.

**Règle : grouper 3 `InputFrame` consécutives par paquet, envoyé à 20 Hz**
(~1,3 ko/s, −60 %). Le coût en latence (2 ticks au plus) est absorbé par la
prédiction du camion local (`docs/NETCODE.md` §5), et le groupement donne une
redondance gratuite : un paquet perdu, le suivant contient encore deux des trois
frames. À prévoir dès la phase 1 dans `to_bytes()`, à implémenter en phase 6.

## 3. Mapping

Profil **Forza Horizon, manette PlayStation 5 DualSense** (décidé le
2026-09-30 après le playtest ; avant : Mario Kart 8 sur Switch). Godot (SDL)
nomme les boutons **par position** : `JOY_BUTTON_A` = bas (Croix),
`JOY_BUTTON_B` = droite (Rond), `JOY_BUTTON_X` = gauche (Carré),
`JOY_BUTTON_Y` = haut (Triangle), `JOY_BUTTON_BACK` = Create,
`JOY_BUTTON_START` = Options. Une manette Xbox ou Switch fonctionne à la même
position. Chaque action est une **liste** de boutons exportée par
`DeviceInputSource` : réaffectable sans code.

| Action | Manette (DualSense) | Clavier J1 (flèches) | Clavier J2 / solo (ZQSD) |
|---|---|---|---|
| `steer` | stick gauche, axe X | ← / → | Q / D |
| `throttle` | **R2**, analogique | ↑ | Z |
| `brake` (puis recul à l'arrêt) | **L2**, analogique | ↓ | S |
| `handbrake` (frein à main, drift) | **Croix** ou **R1** | Ctrl droit | Espace |
| `boost` (nitro) | **Carré** (1,5 s, recharge 4 s) | Maj droite | Maj gauche |
| `cargo` (largage de la remorque, recharge 30 s) | **Triangle** | deux touches à gauche de Maj droite (;) | E |
| `honk` (klaxon) | **L1** | touche à gauche de Maj droite (!) | H |
| caméra 1re / 3e personne | **R3**, ou un coup franc du stick droit (local, hors `InputFrame`) | touche suivante (:) | C |
| `reset` | **Options**, **Create** ou **pavé tactile** | Retour arrière | R |
| rejouer après l'arrivée | Options | Entrée | Entrée |
| revenir au menu après l'arrivée | Create | Échap | Échap |

Rond n'a pas d'effet en course. Le schéma de la manette (DualSense dessinée,
légendes reliées à chaque commande) est affiché dans l'écran des paramètres du
menu (`ControllerDiagram`).

En solo, le clavier accepte ZQSD **et** les flèches. En écran partagé, chaque
joueur a sa manette (joueur N = device N − 1, de 0 à 3) ; J1 et J2 ont en plus
leur jeu de touches (flèches, ZQSD) : deux joueurs peuvent partager un clavier.
J3 et J4 n'ont que leur manette (`KeyboardInputSource.Layout.NONE`).

**Menu principal** (`ui/main_menu.tscn`) : navigation par les actions `ui_*` de
Godot (croix directionnelle, stick, flèches, souris). Godot 4.7 ne met aucun
bouton de manette dans `ui_accept` ni `ui_cancel` : le menu y ajoute Croix
(valider) et Rond (revenir) au démarrage. L1 / R1 changent le nombre de joueurs,
Options commence, Rond ou Create ferment les paramètres. En course : Échap
revient au menu à tout moment ; après l'arrivée, Options / Entrée rejoue et
Create revient au menu.

- **Direction** : zone morte **axiale de 0,10** sur X uniquement (un seul axe
  utile), puis courbe de réponse légèrement exponentielle pour la précision en
  ligne droite. La courbe est un paramètre, pas une constante en dur.
- **Gâchettes** : analogiques de bout en bout, pas de seuil — un demi-gaz est
  un demi-gaz.
- **Clavier** : le clavier est binaire. `steer` et `throttle` y sont **lissés
  en ticks** (montée en ~8 ticks) pour ne pas donner des coups de volant
  instantanés qu'aucune manette ne produit.

## 4. Écran partagé : routage par device

Godot ne propose pas d'actions par joueur. On lit les événements bruts et on les
route par `device` id :

```gdscript
class_name DeviceInputSource extends InputSource

@export var device_id: int = 0

func _input(event: InputEvent) -> void:
    if event.device != device_id:
        return
    # ... mise à jour de l'état interne
```

**Ne crée pas** d'actions `p1_throttle`, `p2_throttle`… dans la map d'input : ça
ne monte pas en nombre de joueurs, ça ne gère pas le branchement à chaud, et
c'est ingérable à remapper.

Le clavier a `device == -1` par convention (les manettes commencent à 0).

## 5. Lobby local

1. Écran « appuyez sur A pour rejoindre ».
2. Première pression d'un device inconnu → création d'un slot joueur lié à ce
   `device_id`, attribution d'une couleur de camion.
3. B pour quitter son slot. Start (joueur 1) pour lancer.
4. Entre 1 et 4 joueurs.

Le mapping `device_id → player_slot` est détenu par `GameState` et **persiste
pendant toute la course**.

## 6. Branchement à chaud

`Input.joy_connection_changed` :
- **manette débranchée** en course → le camion ne reçoit plus d'`InputFrame` :
  gaz à zéro, il roule en roue libre et s'arrête. Une icône « manette
  déconnectée » s'affiche dans **sa** vue ;
- la même manette rebranchée reprend **son** camion, via son `device_id` ;
- **manette branchée** en course → elle attend le prochain lobby.

Ne mets jamais la course en pause sur une déconnexion : en écran partagé, c'est
plus frustrant que le problème lui-même.

## 7. Tests

`ScriptedInputSource` rejoue une séquence d'`InputFrame` prédéfinie. C'est elle
qui « conduit » le camion dans tous les tests headless. Durées en **ticks** :

```gdscript
var src := ScriptedInputSource.new()
src.push_hold(&"throttle", 1.0, 600)            # plein gaz 600 ticks (~10 s)
src.push_hold(&"steer", 1.0, 120)               # plein braquage à droite
src.push_hold(&"handbrake", true, 30)
src.push_once(&"reset")
```

C'est aussi la source de `handling_test`, qui mesure les métriques de
`docs/METRICS.md` : elle doit être **parfaitement reproductible** — aucune
lecture de temps réel, aucun aléatoire non seedé.

Critère de la phase 4 : avec 4 `DeviceInputSource` simulées, l'input du device 2
ne modifie **aucun** autre camion (test automatisé, pas visuel).
