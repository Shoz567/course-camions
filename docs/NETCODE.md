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
InputFrame ×3 (18 o, un paquet par tick)
  ──unreliable_ordered──────────────────►  RemoteInputSource
       │                                          │
  simule SON camion                        simule TOUTE la course
  immédiatement (prédiction)               (la seule qui fait foi)
       │                                          │
  ◄──unreliable_ordered────────────────── Snapshot (60 Hz ; 20 Hz si lent)
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
| Angle de direction | int8 (± 45°, pas de 0,35°) | 1 |
| Angle de la remorque articulée | int8 | 1 |
| Flags (boost, frein à main, épave, remorque larguée, klaxon, 6 pneus crevés) | bitfield | 2 |
| PV de la tête, PV de la remorque, cargo (recharge + verrou), réserve | 4 × u8 | 4 |
| **Total par camion** | | **36** (32 avant l'étape 3) |

Les vitesses sont indispensables en course : elles permettent d'extrapoler
proprement un camion à 150 km/h. La compression des suspensions n'est **pas**
envoyée : chaque client la recalcule par ses propres rayons, c'est purement
visuel.

À 4 joueurs, **en-têtes de paquet compris** (~48 o par datagramme) :

| Fréquence | Descendant par client | Montant côté host (3 clients) |
|---|---|---|
| 30 Hz | 32 × 4 × 30 + 48 × 30 ≈ 5,3 ko/s | ≈ 15,8 ko/s = **127 kbps** — à la limite |
| **20 Hz** | ≈ 3,5 ko/s | ≈ 10,6 ko/s = **85 kbps** ✅ |
| 60 Hz (défaut depuis le 2026-10-17, §11) | ≈ 11 ko/s | ≈ 33 ko/s = **265 kbps** |

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

- Buffer de **2 ticks à 60 Hz** (~33 ms ; 100 ms à l'origine, réduit le 2026-10-17,
  §11). Positions en `lerp`, rotations en
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

## 11. État d'avancement

Branche `reseau/host-et-lobby`. Objectif fixé le 2026-10-17 : **le moins de
délai possible**.

| Étape | Contenu | État |
|---|---|---|
| **1 — Réseau local** | ENet, héberger / rejoindre par IP, lobby, course synchronisée | ✅ jouable, à éprouver sur 2 PC |
| **2 — Délai minimal** | camion local prédit et corrigé en douceur (§5), autres camions à 2 ticks, 60 Hz | ✅ mesuré (ci-dessous) |
| **3 — Ce que voient les clients** | PV, épaves, remorques larguées, barils, panneaux, chocs, klaxon, pneus | ✅ mesuré (ci-dessous) |
| **4 — Robustesse** | déconnexion (écran « connexion perdue », abandon), latence et perte simulées (§9), bande passante dans `baseline.json` | ✅ mesuré (ci-dessous) ; reste l'essai sur 2 PC |

### Les briques

| Brique | Fichier | Rôle |
|---|---|---|
| `NetSession` (autoload) | `game/net/net_session.gd` | host / join, cases du lobby, version du protocole, cadence des snapshots, lancement pour tous |
| `NetRace` | `game/net/net_race.gd` | dans la scène de course : inputs → host, snapshots → clients, prédiction du camion local, marionnettes, état de course et tours en `reliable` |
| `RemoteInputSource` | `game/net/remote_input_source.gd` | côté host, les inputs d'un joueur distant : file de 2 frames, une frame par tick, `ack` de la frame prise en compte |
| `TruckState` | `game/net/truck_state.gd` | état d'un camion en 36 octets (§3) : pose, PV, cargo, pneus, klaxon |
| `Truck.set_net_puppet` / `net_correct` | `game/vehicles/truck.gd` | marionnette cinématique (Jolt en déduit ses vitesses : roues, roulis, effets, HUD suivent) ; correction du camion prédit dans `_integrate_forces` |
| `RaceLaps.mirror` | `game/gameplay/race_laps.gd` | côté client, les tours sont recopiés du host, jamais validés sur place |
| Menu **EN LIGNE** | `game/ui/main_menu.gd` | pseudo, adresse à donner, rejoindre, joueurs, connexion lente, lancer, quitter |

### D'où venait le délai, et ce qui l'a retiré

Étape 1 : ~175 ms entre un appui et la réaction du camion, même en réseau
local. Chaque source, et sa correction :

| Source | Avant | Maintenant |
|---|---|---|
| Camion du joueur | attendait l'aller-retour par le host | **prédit** : simulé sur le PC du joueur, réagit au tick de l'appui |
| Inputs groupés par 3 | jusqu'à 50 ms | un paquet **par tick** (avec les 2 frames précédentes : une perte ne perd rien) |
| Snapshots à 20 Hz | ~25 ms d'attente | **60 Hz** (20 Hz en option « connexion lente ») |
| Paquets envoyés à l'image suivante | jusqu'à 16 ms | **envoi immédiat** (flush ENet) |
| Réseau lu une fois par image, après la physique | jusqu'à 16 ms ; ticks joués sans les inputs arrivés | **lu à chaque tick**, avant la course |
| Retard de rendu des autres camions | 100 ms fixes | **2 ticks (33 ms)** ; un paquet en retard est couvert par l'extrapolation (quelques cm sur 3 ticks) |
| File d'inputs du host | jusqu'à 100 ms ; ticks sautés ou répétés | 2 frames (33 ms), rattrapage d'une frame à la fois |

Prédiction sans rejeu (Jolt ne rejoue pas un seul corps) : le client garde,
pour chaque tick, l'état prédit et le cumul des corrections déjà faites. Le
snapshot porte la frame du client prise en compte par le host (`ack`) ;
l'écart entre l'état du host et la prédiction de cette frame (moins ce qui a
déjà été corrigé depuis) est rattrapé à 20 % par tick, ou d'un coup au-delà de
3 m / 45° (reset, épave). PV, pneus et cargo du camion prédit restent au host
(nœuds passifs) ; ses effets visuels (creux, étincelles) restent locaux.

### Mesures (2026-10-17)

Deux instances sur le même PC (i7-1255U, Iris Xe), 2 joueurs pilotés par
`TrackAutopilot` sur Cyber City, 14 s de course :

| | Réseau local | 100 ms aller-retour simulés |
|---|---|---|
| Réaction du camion du joueur | au tick de l'appui, même courbe d'accélération que sur le host | idem |
| Retard d'affichage des autres camions | 2 ticks (33 ms) + latence | 2 ticks + latence |
| Camion du host vu par le client, au même tick | **1 cm** médian, 5 cm au pire | 2 cm médian, 22 cm au pire |
| À-coups des autres camions d'une image à l'autre | ~1 cm en moyenne | ~1 cm |
| Recalages brutaux du camion prédit | 1 | 4 |

Bande passante montante du host à 4 joueurs, en-têtes compris : **~290 kbps à
60 Hz**, ~96 kbps à 20 Hz (« connexion lente »). Le critère de sortie de la
phase 6 (< 128 kbps) n'est tenu qu'à 20 Hz : choix assumé pour le délai, à
confirmer par l'équipe.

Le PC de mesure fait tourner les deux jeux à 45-55 images/s : les petits
sauts et ticks répétés restants viennent surtout de ses images lentes (et du
simulateur de latence, qui relâche ses paquets par image). À refaire sur 2 PC.

### Étape 3 : ce que voient les clients (2026-10-17)

Principe : **le client rejoue les fonctions de jeu du host, sur ordre du host**.
Épaves, remorques et explosions sont créées par le même code, avec les mêmes
visuels ; seules les décisions (dégâts, crevaisons, largages, explosions)
restent au host. Les nœuds qui décident sont en miroir chez les clients
(`net_mirror` sur `TruckHealth`, `TruckTires`, `TruckCargo`,
`DetachedTrailer`).

| Quoi | Comment |
|---|---|
| PV de la tête et de la remorque, recharge et verrou du cargo, pneus crevés, klaxon | dans chaque snapshot (`TruckState`, 36 o) : une perte se rattrape au suivant ; une baisse de PV rejoue fumée et étincelles |
| Épave et réapparition | événements `WRECK` / `RESPAWN` : `TruckHealth.net_wreck` / `net_respawn` (explosion, carcasse, remorque laissée) |
| Remorque larguée, remorque qui explose sur le camion | `DROP` (`TruckCargo.drop`) / `TRAILER_EXPLODED` |
| Obstacles nés en course (remorques, carcasses) | même id partout ; pose dans les snapshots quand ils bougent (18 o, et une fois toutes les 30 ticks) ; chocs (`OBJECT_HIT` : trace, creux, fumée) et explosion (`OBJECT_GONE`) rejoués |
| Barils, panneaux | même ordre dans la scène partout ; `BARREL` / `SIGN`. Ceux que touche **votre** camion réagissent tout de suite chez vous (prédit) ; le host confirme |
| Chocs des autres camions | `IMPACT` : creux, étincelles et pièces arrachées rejoués sur la marionnette (pas sur la machine du camion, qui les a déjà) |

Mesuré (deux instances, 1 PC, scénario forcé : deux largages, camion du
client détruit, baril et panneau déclenchés) : mêmes PV, même épave, mêmes
remorques au sol des deux côtés ; positions des obstacles au centimètre près ;
réapparition et dégâts suivants identiques, en réseau local comme à 100 ms
d'aller-retour simulés.

Corrigé au passage : un camion gelé (épave) gardait sa vitesse d'avant dans
le snapshot (les clients le faisaient osciller, compteur à 464 km/h) ; une
marionnette téléportée prenait pour un tick des milliers de m/s (Jolt) : elle
saute maintenant gelée en statique ; `BodyDamage._own` repart du neuf quand
le maillage d'une copie ne correspond plus à sa grille (indices hors limites).

### Étape 4 : robustesse (2026-10-17)

**Déconnexion (§8).** Host parti ou coupure : le client affiche « CONNEXION
PERDUE » et la raison 3 s, puis revient au menu (le panneau EN LIGNE la
rappelle). Client parti : son camion roule au neutre, il est classé
« abandon », tout le monde voit « X a quitté la partie », et il ne bloque ni
le sas READY ni la fin de course. Plus aucun snapshot depuis 1,5 s :
« CONNEXION INSTABLE… ». Coupure détectée en 3 à 8 s en course (ENet :
5 à 30 s par défaut, gardé pendant les chargements, où une machine se fige
quelques secondes). Mesuré : host qui quitte à 6,0 s → message chez le client
à 6,05 s.

**Latence et perte simulées (§9)** : `-- --net-latency=<ms>` (ajoutés à
chaque paquet envoyé par la machine) et `-- --net-loss=<%>` (inputs et
snapshots jetés ; les messages `reliable` ne se perdent pas). Deux instances
sur 1 PC, scénario complet (2 largages, épave, réapparition, baril, panneau),
19 s :

| Condition | Votre camion | Autres camions : écart médian / 90 % | À-coups | PV, épave, remorques, classement identiques |
|---|---|---|---|---|
| 0 ms, 0 % | réagit au tick de l'appui | 1 cm / 11 cm | 2 cm | oui |
| 50 ms, 0 % | idem | 1 cm / 5 cm | 2 cm | oui |
| 150 ms, 2 % | idem | 1 cm / 7 cm | 2 cm | oui |
| 300 ms, 5 % | idem | 1 cm / 14 cm | 3 cm | oui |
| 10 snapshots perdus d'affilée | — | extrapolation 15 ticks, gel, reprise interpolée (`net_protocol_test`) | | |

Les 2 à 4 recalages brutaux du camion prédit par passage sont l'épave et la
réapparition forcées (saut assumé). Bande passante dans `baseline.json` :
`snapshot_bytes_per_truck` = 36, `uplink_kbps_4_players` = 289 (60 Hz),
vérifiés à ± 10 % par `net_protocol_test`.

**Contacts entre camions (6.5).** Le host arbitre (dégâts, poussées) ; chez
un client, les autres camions sont des obstacles cinématiques exacts tant
qu'ils sont loin du sien, et deviennent à moins de 25 m des corps
**dynamiques de vraie masse**, menés vers la pose reçue par leur vitesse
(`Truck.set_net_near`) : le camion prédit les pousse comme chez le host au
lieu de buter contre un mur de masse infinie. Mesuré sur 1 PC : camion du
client qui en percute un autre, 7 recalages → 2 ; écart d'affichage des
autres camions proches ~35 cm (90 %), 2 cm médian. Sur ce PC, le host ne tient
pas le temps réel avec deux instances (~38 ticks/s) : il saute ou répète des
inputs du client, et sa trajectoire s'écarte de la prédiction ; à refaire sur
2 PC.
### Étape 5 : retours de test (2026-10-19)

- **Lobby, protocole 3** : chaque membre porte `trailer`, `power_left`,
  `power_right`, `ready` ; le client les envoie au host (`set_loadout`, RPC
  fiable), le host les diffuse avec le lobby et au lancement. LANCER attend
  `all_ready()`.
- **Pouvoirs** : `Ev.POWER [camion, emplacement, cible du missile]`. Chez un
  client, `TruckPowers.mirror` rejoue recharge, aura, rayon, rafale, scies,
  missile et boomerang sans dégât. Son propre tir part à l'appui
  (`predict`) ; l'annonce du host qui suit (dans 90 ticks) ne le rejoue pas.
- **Délai** : cible de la file d'inputs du host adaptative
  (`RemoteInputSource.target`, 1 à 3 frames ; −1 après 3 fenêtres de 120
  ticks sans file vide, +1 dès une file vide) ; retard de rendu des
  marionnettes = intervalle des snapshots + gigue (1 tick à 60 Hz régulier ;
  +1 à 20 Hz).
- **Aide en l'air** (`AutoReset.air_return`) appliquée aussi au camion prédit
  du client (`watch_assist`), pour que sa prédiction suive le host.
- **Chargement** : le client s'annonce prêt (`_scene_ready`) une fois son
  écran de chargement levé ; la détection de coupure rapide (3 à 8 s) n'est
  posée, des deux côtés, qu'après le sas READY ; pendant le chargement, 15 à
  60 s (au réglage d'ENet, 5 à 30 s, un client figé 5 s était coupé une fois
  sur deux).
- Essai 2 instances en headless sur 1 PC : convois, `Ev.POWER` (bouclier,
  laser, recharges) et file adaptative vérifiés. En fenêtré sur 1 PC, chaque
  instance se fige jusqu'à 16 s en créant la course et la liaison tombe :
  limite de la machine, essai à faire sur 2 PC.

### Pas encore fait

- Essai sur 2 vrais PC, puis à 4 joueurs (critère de sortie de la phase 6).
- Débris et éclats : calculés par chaque machine (purement visuels).
- Un seul joueur par PC.
Tester sans 2 PC : lancer deux fois le jeu en fenêtre (`godot --path game
--windowed`), héberger dans l'un, rejoindre `127.0.0.1` dans l'autre.
Latence simulée (tests) : `-- --net-latency=50` (ms ajoutées à chaque
paquet envoyé par cette machine).