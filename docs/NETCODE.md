# NETCODE.md — Architecture réseau (phase 6)

---

## 1. La contrainte de départ

La physique de ragdoll **n'est pas déterministe** : Jolt utilise du multithread,
l'ordre de résolution des contacts varie, et les arrondis flottants diffèrent
selon la plateforme et la compilation. Deux machines partant du même état avec
les mêmes inputs divergent visiblement en quelques secondes.

Donc, définitivement écarté :
- lockstep déterministe,
- rollback netcode (GGPO / prédiction-resimulation),
- simulation partagée entre pairs.

Retenu : **host autoritaire** (listen-server). Une seule machine simule. Les
autres envoient des inputs et affichent un état reçu, interpolé.

C'est exactement ce que font les jeux du genre. Ce n'est pas un compromis au
rabais, c'est la seule option viable.

## 2. Schéma

```
       Client                              Host (joueur 1)
       ──────                              ───────────────
3 × InputFrame groupées (15 o, 20 Hz)
  ──rpc unreliable_ordered──────────────►  RemoteInputSource
                                                  │
                                           simulation physique
                                           (la seule qui existe)
                                                  │
  ◄──rpc unreliable_ordered────────────── Snapshot (20–30 Hz)
       │
  ack du snapshot_id ───────────────────►  (pilote le delta)
       │
  buffer 100 ms → interpolation → rendu
```

- `peer_id == 1` est le host et l'autorité sur tout.
- Un client ne crée, ne détruit et ne déplace jamais une entité de gameplay.
- Les ragdolls distants sont en `freeze = true`,
  `freeze_mode = FREEZE_MODE_KINEMATIC` : aucune physique locale.

## 3. Budget de bande passante

État d'un personnage par snapshot :

| Donnée | Codage | Octets |
|---|---|---|
| Position du bassin | 3 × float32 | 12 |
| Rotation des 13 os | quaternion *smallest-three* (3×10 bits + 2 bits d'index) | 52 |
| Flags (stun, grab, cible) | bitfield | 2 |
| **Total par perso** | | **66** |

À 4 joueurs et 30 Hz, **sans** compression delta :
- descendant vers chaque client : 66 × 4 × 30 ≈ **7,9 ko/s** (63 kbps) — confortable ;
- montant côté host : × 3 clients ≈ **23,8 ko/s** (**190 kbps**) — trop haut pour
  une connexion domestique modeste, surtout en upload.

**Objectif : < 128 kbps montant côté host à 4 joueurs**, overhead de paquet
inclus (cf. `INPUT_SPEC.md` §2 : environ 48 octets d'en-têtes par datagramme, ce
n'est pas négligeable et le budget doit les compter).

### 3.1 Le delta a besoin d'un acquittement — sinon il diverge

C'est le point le plus facile à rater de tout ce document.

L'optimisation n°1 consiste à n'envoyer un os que s'il a bougé « depuis le
dernier snapshot ». Mais les snapshots voyagent en **`unreliable_ordered`** :
ils se perdent. Si le host calcule son delta par rapport au *dernier snapshot
envoyé* et que ce paquet est perdu, le client applique un delta sur une base
qu'il n'a jamais reçue. L'os concerné ne bougeant plus de 2°, il ne sera **plus
jamais renvoyé** — et l'erreur est permanente.

Un delta non acquitté sur un canal non fiable ne converge pas. Il faut l'un des
deux mécanismes, et le choix se fait avant d'écrire la tâche 6.7 :

**Option A — acquittement (recommandée).**
Chaque snapshot porte un `snapshot_id` sur 1 octet (modulo 256). Le client
renvoie le dernier `snapshot_id` reçu, piggybacké dans son paquet d'input — coût
réel : **1 octet**, aucun paquet supplémentaire. Le host maintient, par peer,
l'état du dernier snapshot acquitté et calcule son delta par rapport à celui-là.
C'est correct par construction, et le surcoût mémoire côté host est de 3 états
de référence.

**Option B — keyframes périodiques.**
Un snapshot complet toutes les N frames (typiquement 1 seconde), les autres en
delta. Plus simple à écrire, mais borne le temps d'erreur au lieu de l'éliminer,
et produit un pic de bande passante périodique. Acceptable en repli.

Le test qui valide ce point est le dernier de la §9 : perte de 10 snapshots
consécutifs, puis vérification que l'état revient **correct**, pas seulement
« sans crash ».

### 3.2 Optimisations, par ordre de rentabilité

1. **Delta par os** contre le dernier snapshot **acquitté** (§3.1). Un perso au
   sol ou immobile coûte presque rien → division par 2 à 3 en moyenne. C'est là
   qu'est tout le gain.
2. **20 Hz au lieu de 30**, compensé par l'interpolation : −33 %.
3. **Priorité** : les persos loin de la caméra du client sont envoyés une fois
   sur deux.
4. Compression générique du reste du paquet.

Mesure avant et après chaque optimisation. Un budget théorique n'a jamais fait
tourner un jeu.

### 3.3 Ce qui n'a pas besoin d'être répliqué

Les **hazards** (phase 3.5) sont spécifiés déterministes et pilotés par le
compteur de ticks physiques, pas par des tweens temporels
(cf. `level-designer`). Conséquence directe : ils se répliquent avec **leur seul
tick de départ**, envoyé une fois en `reliable`. Ne les mets pas dans le
snapshot par réflexe — ce serait payer chaque frame pour une information connue
d'avance.

Même logique pour tout objet dont l'état est une fonction pure du tick et d'un
seed. Si tu te surprends à sérialiser la position d'une plateforme mobile,
demande-toi d'abord pourquoi elle n'est pas déterministe.

### 3.4 Hypothèse à valider : la pose reconstruite par cinématique directe

Le snapshot transporte la position du **bassin** et les **rotations** des os :
le client reconstruit les positions par cinématique directe. Cela suppose que la
chaîne d'os est rigide.

Or les `PhysicalBone3D` sont des corps libres reliés par des joints, et les
joints **dérivent** sous charge — typiquement pendant un grab à 4 joueurs. La
pose reconstruite sera donc légèrement différente de celle du host.

Probablement invisible, mais c'est une hypothèse, pas un fait : le spike **S2**
en donne l'ordre de grandeur, et la tâche **6.12** la mesure pour de bon (écart
max host↔client, en cm). Si la dérive dépasse quelques centimètres, il faudra
envoyer aussi la position de quelques os clés.

## 4. Interpolation côté client

- Buffer de **100 ms** (2–3 snapshots à 30 Hz). C'est le prix de la fluidité ; ne
  le réduis pas pour « gagner en réactivité », tu gagneras du saccadement.
- Positions en `lerp`, rotations en `slerp`, appliquées sur le `Skeleton3D`.
- Snapshot manquant → extrapolation linéaire limitée à **200 ms**, puis gel.
  Au-delà, une extrapolation de ragdoll produit des poses absurdes ; mieux vaut
  figer et laisser le prochain snapshot corriger.

## 5. Prédiction et réconciliation

Uniquement pour le personnage du joueur local, et uniquement sur la **position du
bassin** — pas sur la pose complète.

- Le client applique immédiatement son input sur une estimation locale.
- À réception du snapshot autoritaire, l'erreur est résorbée par `lerp` sur
  ~150 ms (9 ticks). **Jamais de snap.** Un décalage de 20 cm corrigé en douceur
  est invisible ; un snap est immédiatement perçu.
- Si l'erreur dépasse 1,5 m (téléportation, respawn, désynchronisation grave),
  snap assumé — la correction douce serait pire.

**Le grab n'est pas prédit.** Le client affiche l'intention (bras qui se lève)
dès la pression, mais la prise n'existe que lorsque le host la confirme. Un joint
physique prédit puis infirmé ne se réconcilie pas proprement.

> Note : si le spike **S5** conclut au grab par **ressort PD sans joint**, ce
> paragraphe devient plus simple — il n'y a plus de joint à créer côté client,
> seulement un état visuel. C'est un des arguments en faveur du plan B.

## 6. Sécurité et validation

Le host ne fait confiance à rien de ce qui arrive du réseau :
- `tick` hors d'une fenêtre raisonnable (± 2 s) → paquet jeté ;
- `move` hors de [−1, 1] → clampé ;
- un peer ne peut envoyer d'input que pour **son** slot (vérifie
  `multiplayer.get_remote_sender_id()`, jamais un id contenu dans le message) ;
- débit entrant par peer plafonné ; au-delà, le peer est déconnecté ;
- un `snapshot_id` acquitté qui n'a jamais été envoyé → ignoré, jamais utilisé
  comme base de delta.

## 7. Fiabilité des RPC

| Message | Mode |
|---|---|
| Paquet d'inputs groupés (+ ack piggybacké) | `unreliable_ordered` |
| Snapshot d'état | `unreliable_ordered` |
| Début/fin de manche, élimination, spawn, tick de départ des hazards | `reliable` |
| Lobby, choix de perso, chat | `reliable` |

Jamais de `reliable` à haute fréquence : sur ENet, un paquet perdu bloque la file
et fait pire que la perte elle-même.

## 8. Déconnexion

- Client qui part → son perso est retiré à la fin de la manche en cours, pas au
  milieu.
- **Host qui part → la partie se termine.** Pas de migration d'hôte : migrer
  l'autorité sur une simulation physique non déterministe est un chantier à part
  entière, hors périmètre.
- Prévois l'écran « connexion perdue » dès le premier jour de la phase 6, pas à
  la fin.

## 9. Tests obligatoires

Toute fonctionnalité réseau se teste avec latence et perte simulées :

| Condition | Attendu |
|---|---|
| 0 ms, 0 % | référence |
| 50 ms, 0 % | indiscernable de la référence |
| 150 ms, 2 % | grab utilisable, mouvement fluide |
| 300 ms, 5 % | jouable en dégradé, aucune désynchronisation |
| Perte de 10 snapshots consécutifs | gel, puis reprise **et état correct après reprise** (valide §3.1) |
| Régime normal | écart de pose host↔client < 5 cm (valide §3.4) |

Mesure et logge la bande passante réelle à chaque test, **overhead de paquet
inclus** : c'est la seule donnée qui compte pour valider la phase. Écris-la dans
`baseline.json` sous `snapshot_bytes_per_char`.

## 10. Hors périmètre (pour mémoire)

Matchmaking public, NAT punchthrough et lobbies Steam nécessiteraient GodotSteam
et une intégration Steamworks. C'est une phase à part entière, à ouvrir seulement
quand le jeu en réseau local ou par IP directe est solide.
