# NETCODE.md — Architecture réseau (phase 6)

---

## 1. La contrainte de départ

La physique Jolt **n'est pas déterministe d'une machine à l'autre** (multithread,
ordre de résolution des contacts, arrondis flottants). Deux machines partant du
même état avec les mêmes inputs divergent : sur une course, un écart de quelques
centimètres dans un virage devient un camion dans le décor au suivant.

Écarté : lockstep déterministe, rollback complet de toute la course.

Retenu : **host autoritaire** (listen-server). Le host simule la course. Les
clients envoient leurs inputs et affichent l'état reçu. La différence avec un jeu
de combat : chaque client **prédit son propre camion** (§5), parce qu'au volant,
100 ms de latence non compensée rendent la conduite impossible.

## 2. Schéma

```
       Client                              Host (joueur 1)
       ──────                              ───────────────
InputFrame ×3 groupées (18 o, 20 Hz)
  ──unreliable_ordered──────────────────►  RemoteInputSource
       │                                          │
  simule SON camion                        simule TOUTE la course
  immédiatement (prédiction)               (la seule qui fait foi)
       │                                          │
  ◄──unreliable_ordered────────────────── Snapshot (20 Hz)
       │
  corrige son camion en douceur ;
  interpole les autres (buffer ~100 ms)
```

- `peer_id == 1` est le host et l'autorité sur tout : positions, contacts entre
  camions, checkpoints, tours, classement.
- Un client ne valide jamais un checkpoint ni un tour : il **affiche** ce que le
  host a validé.

## 3. Budget de bande passante

État d'un camion par snapshot :

| Donnée | Codage | Octets |
|---|---|---|
| Position | 3 × float32 | 12 |
| Orientation | quaternion *smallest-three* (3 × 10 bits + 2 bits d'index) | 4 |
| Vitesse linéaire | 3 × float16 | 6 |
| Vitesse angulaire | 3 × float16 | 6 |
| Angle de direction | int8 | 1 |
| Flags (frein, boost, frein à main, contact des 4 roues…) | bitfield | 3 |
| **Total par camion** | | **32** |

Les vitesses sont indispensables en course : elles permettent d'extrapoler
proprement un camion à 150 km/h. La compression des suspensions n'est **pas**
envoyée : chaque client la recalcule par ses propres rayons, c'est purement
visuel.

À 4 joueurs, **en-têtes de paquet compris** (~48 o par datagramme) :

| Fréquence | Descendant par client | Montant côté host (3 clients) |
|---|---|---|
| 30 Hz | 32 × 4 × 30 + 48 × 30 ≈ 5,3 ko/s | ≈ 15,8 ko/s = **127 kbps** — à la limite |
| **20 Hz** | ≈ 3,5 ko/s | ≈ 10,6 ko/s = **85 kbps** ✅ |

**Objectif : < 128 kbps montant côté host à 4 joueurs.** Le levier principal est
la fréquence (20 Hz), compensée par l'extrapolation grâce aux vitesses.

Le delta par champ rapporte peu ici — en course, tout bouge en permanence.
S'il devient nécessaire, il **exige un acquittement** : un delta calculé contre
un snapshot perdu (canal non fiable) ne se corrige jamais. Chaque snapshot
porte alors un `snapshot_id` (1 octet) que le client renvoie dans ses paquets
d'input, et le host calcule le delta contre le dernier snapshot acquitté.

### Ce qui ne passe pas par les snapshots

- Les **événements de course** (checkpoint validé, tour bouclé, arrivée,
  classement final) : RPC `reliable`, rares.
- Les **obstacles déterministes** d'une piste (pilotés par le compteur de ticks,
  cf. `track-designer`) : seul leur tick de départ est envoyé, une fois.

## 4. Camions distants : interpolation

- Buffer de **~100 ms** (2 snapshots à 20 Hz). Positions en `lerp`, rotations en
  `slerp`.
- Snapshot manquant → **extrapolation** à partir des vitesses, limitée à
  **250 ms** (15 ticks), puis gel. Un camion est un corps rigide qui roule :
  l'extrapolation linéaire y est bien plus fiable que sur un ragdoll.
- Les camions distants sont **cinématiques** côté client
  (`freeze_mode = FREEZE_MODE_KINEMATIC`) : le camion local peut les percuter,
  mais ils ne sont pas simulés localement.

## 5. Camion local : prédiction et réconciliation

C'est le cœur du netcode d'un jeu de course.

- Le client **simule son propre camion** avec ses propres inputs, immédiatement.
  Il garde un historique `(tick, input, état)` des ~1 s passées.
- À réception d'un snapshot, il compare l'état autoritaire au tick T avec son
  propre état au tick T :
  - écart faible (< 0,5 m) → correction **douce**, étalée sur ~10 ticks, jamais
    de saut visible ;
  - écart moyen → correction douce plus rapide ;
  - écart > **3 m** ou > 45° (collision non prédite, reset) → **snap** assumé,
    la correction douce serait pire.
- Les contacts avec un camion distant sont prédits contre sa position
  interpolée, donc légèrement en retard : une collision mal prédite est corrigée
  par le host. C'est le compromis standard du genre.

## 6. Sécurité et validation

Le host ne fait confiance à rien de ce qui arrive du réseau :
- `tick` hors d'une fenêtre raisonnable (± 2 s) → paquet jeté ;
- `steer` hors de [−1, 1], `throttle` / `brake` hors de [0, 1] → clampés ;
- un peer ne pilote que **son** camion : vérifie
  `multiplayer.get_remote_sender_id()`, jamais un id contenu dans le message ;
- débit entrant par peer plafonné ; au-delà, le peer est déconnecté.

## 7. Fiabilité des RPC

| Message | Mode |
|---|---|
| Paquet d'inputs groupés | `unreliable_ordered` |
| Snapshot d'état | `unreliable_ordered` |
| Checkpoint, tour, arrivée, classement | `reliable` |
| Lobby, choix du camion, départ de course | `reliable` |

Jamais de `reliable` à haute fréquence : sur ENet, un paquet perdu bloque la file
et fait pire que la perte elle-même.

## 8. Déconnexion

- Client qui part → son camion est retiré de la course (classé « abandon »).
- **Host qui part → la course se termine.** Pas de migration d'hôte : migrer
  l'autorité d'une simulation non déterministe est un chantier à part entière.
- L'écran « connexion perdue » se prévoit dès le premier jour de la phase 6.

## 9. Tests obligatoires

| Condition | Attendu |
|---|---|
| 0 ms, 0 % | référence |
| 50 ms, 0 % | indiscernable de la référence |
| 150 ms, 2 % | camion local agréable, camions distants fluides |
| 300 ms, 5 % | jouable en dégradé, aucune désynchronisation du classement |
| Perte de 10 snapshots consécutifs | extrapolation, gel puis reprise propre |
| Collision non prédite entre deux camions | correction sans saut au-delà de 3 m d'écart |

Mesure et logge la bande passante réelle à chaque test, **en-têtes compris** ;
écris-la dans `baseline.json` (`snapshot_bytes_per_truck`,
`uplink_kbps_4_players`).

## 10. Hors périmètre

Matchmaking public, NAT punchthrough et lobbies Steam nécessiteraient GodotSteam :
c'est une phase à part entière, à n'ouvrir que quand le jeu par IP directe est
solide.
