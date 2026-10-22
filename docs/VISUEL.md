# Visuel : décor, style et qualité extrême

Travail du 2026-10-22 sur la branche **`visuel/decor-style-extreme`**, partie
du `main` à jour (après #92). Rien côté réseau ni gameplay. Les 121 tests
passent. Intégrée dans `main` après #95 (bots en ligne, latence,
12 joueurs) : 132 tests, mesures dans PLAN.md (« Intégration de
`visuel/decor-style-extreme` »).

| Commit | Contenu | Qualités concernées |
|---|---|---|
| `031942f` | Décor près des routes et au-dessus, décor lointain allégé | **toutes** (basse, moyenne, haute, extrême) |
| `9f3f3ee` | Style des éléments « qui font tache » ; qualité extrême | style : **toutes** ; contenu extrême : **extrême seulement** |
| `bd22536` | Reflets de la mer de Playa ; décor extrême coupé en écran partagé sur puce intégrée | reflets : **toutes** (plus nets en extrême) |
| `4d6e226` | Décor **sur** la route ; jonctions des raccourcis ; tablier du pont de Sakura | **toutes** (plus dense en extrême) |
| (suivant) | Tours de Cyber City noires en haute et extrême ; fenêtres sans grain | haute et extrême surtout |

Tout est sur la même branche. Le décor proche, le décor lointain allégé et le
nouveau style s'appliquent en basse, moyenne et haute comme en extrême ; le
contenu « extrême » (effets au maximum, arbres et bâtiments détaillés, décor
plus dense) ne s'active que si le joueur choisit **Qualité graphique :
extrême**.

---

## 1. Les demandes

1. « Rendre moins vide les graphismes proches des routes ou au-dessus des
   routes, pour que ce soit tout le temps beau et immersif. »
2. « Pour les assets de loin, moins visibles, faire du trick en 2D tourné,
   sans que ça fasse tache, pour optimiser medium/high. »
3. « Redesign les assets visuels pauvres (captures) dans le style du jeu, de
   la map sélectionnée : HUD, bouton son / roue, pont vide, soucis de texture
   aux joints avec les raccourcis, fumée noire. »
4. « Un dernier setting Extreme : plus d'assets, plus détaillés, pour la 4K,
   branches et feuillages individuels, effets (lumière, reflets, ombres) mis
   en valeur ; un avertissement avant de le sélectionner. »
5. « Améliorer les reflets de l'eau » (Playa, après le test en extrême).
6. « À certaines intersections il y a encore des bugs de blend des routes » ;
   « sans tanker les perfs, en tous les modes, ajoute des décors sur la
   route (fences, objets qui montent et descendent, panneaux) : les routes
   faisaient trop vides. »

---

## 2. Décor près des routes et au-dessus (toutes qualités)

Script : `game/tracks/roadside_dressing.gd` (`RoadsideDressing`), un nœud
ajouté à chaque scène de circuit (`track_01_blockout.tscn`,
`track_02_playa.tscn`, `track_03_sakura.tscn`).

**Au-dessus de la route** (environ tous les 95 m) : deux mâts et un câble en
travers.

- Cyber City : enseignes néon suspendues (KARAOKE, RAMEN, ネオン…).
- Playa : guirlandes de fanions et banderoles (FIESTA, SURF CUP…).
- Sakura : guirlandes de lanternes de papier, corde sacrée (shimenawa).

Règles : au moins **14,5 m** de hauteur libre au-dessus du bord le plus haut
de la chaussée (plus haut que les arches, 13 m), jamais à moins de 75 m d'une
arche, ni aux tribunes, ni sur un raccourci, ni près d'une autre partie de la
piste (le croisement du 8 de Sakura).

**Sur les murs** : bornes néon (Cyber), drapeaux (Playa), bannières nobori et
lanternes (Sakura). **Sur la face intérieure des murs** : écrans holo
animés, panneaux de sponsors (COCO LOCO, HELADOS…), rideaux de fête rouge
et blanc.

**Au pied des murs**, là où la route est au sol : distributeurs lumineux et
écrans holo (Cyber), planches de surf, tours de sauveteur, paillotes, herbes
de dune, buissons (Playa), azalées, palissades de bambou (Sakura).

**Arbres le long des portions hautes** : sur Playa et Sakura, les arbres
longent aussi les rampes et corniches, au pied du talus
(`TrackBlockout.embankment_reach`). Sakura passe de 760 à 1 700 cerisiers
(au loin, ce ne sont que des sprites, voir §3).

Purement visuel : aucune collision, aucun objet sur la chaussée. Tout est
fusionné par case de 240 m (un appel de rendu par matériau et par case) et
n'est dessiné que jusqu'à 460 m.

Test : `track_dressing_test`.

---

## 3. Décor lointain en « 2D tourné » (toutes qualités)

Script : `game/tracks/far_lod.gd` (`FarLod`), shader
`game/tracks/materials/impostor.gdshader`.

- **Arbres** (palmiers de Playa, cerisiers de Sakura) : en 3D jusqu'à
  **250 m** (MultiMesh coupés en cases de 120 m) ; au-delà, **un sprite par
  arbre** qui tourne autour de la verticale pour faire face à la caméra.
  - Le sprite est une **photo du modèle 3D** (même silhouette, mêmes
    couleurs) : `game/tracks/impostors/*.png`.
  - Il apparaît en fondu tramé à partir de 145 m. Entre 145 et 250 m, l'arbre
    3D et le sprite coexistent : jamais de trou.
  - Plus près, son quad est écrasé en un point : aucun pixel calculé pour
    rien.
- **Foule des tribunes** : au-delà de 250 m, chaque spectateur passe de 56 à
  9 triangles (`CrowdFar` dans `race_decor.gd`) ; couleur et mouvement
  identiques. Test : `track_decor_test`.

Si un modèle d'arbre change, refaire les photos (fenêtré, pas en headless) :

```
godot --path game -s res://dev/bake_impostors.gd
```

**Mesuré** (tour de piste, Radeon 780M, contre `main`) : triangles −45 %
sur Playa, −24 à −36 % sur Sakura, temps GPU inchangé à ±0,3 ms. Sur ce PC,
le GPU est limité par les effets plein écran, pas par la géométrie ; le gain
compte surtout sur une carte plus modeste.

---

## 4. Style : refait dans la DA de chaque circuit (toutes qualités)

| Élément | Avant | Maintenant |
|---|---|---|
| **Cadran du HUD** (`hud_dial.gd`) | cercles verts / jaunes génériques | Cyber : diodes néon du cyan au rose, tube lumineux. Playa : bouée de sauvetage corail et blanche autour d'un lagon, cordage. Sakura : laque noire cerclée d'or, jauge vermillon graduée, fleur de cerisier en tête de jauge |
| **Pouvoirs** (pastilles « GO ») | cercles | tuiles qui se remplissent par le bas : parallélogrammes néon, planches de bois flotté, ema de bois à cordon rouge |
| **État du largage** | texte flottant | plaquette à l'habillage |
| **Aide des commandes** (bas de l'écran) | deux longues lignes de texte gris | barre de pictos manette + une ligne clavier, effacée après 14 s ; sans « Remorque » en arène |
| **Boutons Son / Paramètres** du menu (`ui_kit.gd`) | pastilles sombres | néon cyan / lagon cerclé de sable / laque noire et or |
| **Compteur FPS** (`game_state.gd`) | recouvrait la roue des paramètres | plaquette à l'habillage, sous les boutons au menu, en haut en course |
| **Fumée des dégâts** (`fx/smoke.gdshader`, `damage_fx.gd`) | taches noires en plein jour | bouffées rondes à bord net, éclairage en deux tons, gris qui s'éclaircit en montant |
| **Ponts** (850 m chacun) | tablier vide | Sakura : garde-corps vermillon, giboshi de bronze, lanternes bonbori, tablier en hinoki patiné. Playa : poteaux de bois flotté, cordages, bouées, réverbères |
| **Joints des raccourcis** | murs et route dessinés comme un pont en bois | corrigé, plus un pilier à chaque bout de mur ouvert |

**Le bug des raccourcis** : la route et les murs des raccourcis n'avaient
pas de couleur de sommet. Les shaders de Playa et de Sakura lisent
`COLOR.r = 1` comme « pont en bois » : ils y dessinaient des planches. Ils
ont maintenant la couleur de la route ordinaire (`track_blockout.gd`,
`_build_branch_roads`, trois lignes).

---

## 5. Qualité extrême (seulement si choisie)

### Menu

- « Qualité graphique : extrême » en tête de liste (Extrême, Haute, Moyenne,
  Basse).
- Avant de l'activer, un avertissement à l'habillage du circuit : **« Attention,
  ce paramètre requiert un GPU pour tourner stable, voulez-vous poursuivre ? »**
  (Annuler / Oui, activer ; Échap ou Rond annule).
- Valeur enregistrée : `GraphicsSettings.Quality.EXTREME = 3` ; les réglages
  déjà sauvegardés (0 à 2) ne changent pas.

### Effets (`graphics_settings.gd`)

| | Haute | Extrême |
|---|---|---|
| Reflets (SSR), éclairage indirect (SSIL), éclairage global (SDFGI), brouillard volumétrique | selon le nombre de vues (SSIL et SDFGI jusqu'à 2) | tous jusqu'à 4 vues |
| Occlusion ambiante, éclairage indirect | qualité du projet, demi-résolution | ultra, pleine résolution |
| Ombres douces | qualité du projet, atlas 4096 | ultra, atlas 8192 |
| Ombre du soleil | 4 cascades jusqu'à 2 vues | 4 cascades jusqu'à 4 vues, portée × 1,6 |
| Reflets | pas de l'environnement (48 sur Playa) | 128 pas, rugosité haute qualité |
| Reflet du ciel (eau, route mouillée, carrosseries) | 128 px | 1024 px |
| Anticrénelage | MSAA 2x + SMAA | MSAA 4x + SMAA |
| Détail des maillages, filtrage des textures | normal, 4x | maximal, 16x |

### Décor plus riche et plus détaillé

- **Palmiers détaillés** (`game/tracks/tree_kit.gd`) : stipe annelé, 16
  palmes pennées avec une foliole de chaque côté tous les 3 %, palmes sèches,
  noix de coco. ~5 700 triangles (contre ~340). **+38 % de palmiers.**
- **Cerisiers détaillés** : tronc évasé, branches maîtresses, secondaires et
  rameaux, grappes de fleurs à cinq pétales au bout des rameaux. ~8 500
  triangles (contre ~560). **+35 % de cerisiers** (~2 300).
- Au loin, leurs sprites sont des photos des modèles détaillés
  (`palm_hd.png`, `cherry_hd.png`, 512 px) ; la 3D va jusqu'à **420 m**.
- **Maisons de Sakura** (`japan_kit.gd`) : lattis de bois devant le
  rez-de-chaussée, noren indigo, lanterne de papier, chevrons sous l'auvent,
  fenêtres à barreaux, faîtage et tuiles d'about ; clochettes de bronze aux
  toits des pagodes.
- **Tours de Cyber City** (`city_builder.gd`) : corniches d'étage, acrotère,
  climatiseurs, châteaux d'eau, enseignes verticales lumineuses face à la
  piste ; tours plus nombreuses (rangées plus serrées, 240 tours à l'horizon
  au lieu de 170).
- **Décor de bord de piste** : objets plus serrés (pas × 0,75), vus jusqu'à
  690 m.

### Écran partagé

Sur une puce graphique intégrée, à partir de 3 vues, la course passait déjà
en qualité basse (`split_quality`). Le décor reste maintenant ordinaire lui
aussi (le test à 6 joueurs donnait 7 images/s avec le décor extrême).

### Performances constatées

Sur PC portable (Radeon 780M, intégrée) : **13 images/s à 1 joueur sur
Cyber City et Sakura, 17 sur Playa**, avec des creux quand un effet
s'active. GPU à 100 %, CPU à 5-15 %, ~6 Go de RAM. C'est attendu : la qualité
extrême est faite pour une carte graphique dédiée.

Test : `extreme_quality_test` (+ `main_menu_test` pour l'avertissement).

---

## 6. Reflets de la mer (Playa)

`playa_coast.gdshader`, `sky_day.gdshader`, `playa_backdrop.gd`.

- La mer se calme avec la distance : clapot près de la caméra, presque un
  miroir au loin ; îlots, palmiers et pont s'y reflètent.
- Eau un peu plus réfléchissante ; dégradé du ciel sous l'horizon adouci.
- En extrême, reflet du ciel en 1024 px (les ciels sont statiques : calculé
  une fois au chargement).
- **Plaques sombres à bord net** sur l'eau : elles venaient de l'éclairage
  global (SDFGI), pas des reflets. Ses voxels grossiers incluaient la mer, et
  un rayon réfléchi en vue rasante retombait aussitôt dessus. Corrigé : le sol
  de Playa est hors de la grille de l'éclairage global (il le reçoit
  toujours), et les cascades restent à 4.

---

## 7. Décor sur la route et jonctions (toutes qualités)

Script : `game/tracks/road_decor.gd` (`RoadDecor`), appelé par
`RoadsideDressing`. **Rien ne change la conduite** : aucune collision, rien
à hauteur de camion (les bots et le pilotage ne voient aucune différence).

| Élément | Cyber City | Playa | Sakura |
|---|---|---|---|
| **Vibreurs** à la corde des virages (rayon < 230 m), 1,9 m de large, 10 cm de haut | magenta et blanc | rouge et blanc | vermillon et blanc |
| **Panneaux à chevrons** sur le mur extérieur des virages serrés (rayon < 150 m), à la place des sponsors | flèches jaunes lumineuses sur noir | blanches sur rouge | crème sur vermillon |
| **Flèches peintes** dans les 4 voies (droites sur les lignes droites, coudées 30 m avant chaque virage serré) | néon cyan lumineux | blanches | blanches |
| **Passages piétons** en travers de la route (2 par tour) | néon cyan | blancs | blancs |
| **Nom du circuit** peint en grand en travers de la route (2 fois par tour) | CYBER CITY néon | PLAYA DEL SOL | 桜 SAKURA |
| **Plots lumineux** sur les lignes de voie | cyan et ambre | – | – |
| **Objets qui montent et descendent** au-dessus de la route | drones à enseigne néon qui tournent | mouettes qui planent en cercle en battant des ailes | lanternes de papier flottantes, rouges ou blanches |

Les objets volants restent toujours **à 9 m au moins** de la chaussée,
point le plus bas compris (enseigne du drone, au creux de sa descente). Ils
ne sont jamais près d'un tremplin, d'une arche, d'un câble ou du croisement
du 8. Tout leur mouvement est dans le shader (`float_decor.gdshader`), donc
aucun calcul par image côté CPU. Un seul MultiMesh par circuit.

Les marquages au sol sont fusionnés par case de 240 m et sans ombre ; rien
n'est peint sur les plaques, flaques, bonus ou tremplins.

**Coût mesuré** (tour de piste, Radeon 780M, contre le commit précédent) :
+2 à 5 % de triangles, +10 à 40 appels de dessin ; temps GPU : +0,1 ms à
4 joueurs sur Cyber City (3 mesures alternées), dans le bruit ailleurs.

**Jonctions des raccourcis** : là où la piste est haute, son talus de roche
(Playa) ou de pierre (Sakura) partait en biais sur 30 à 40 m et traversait la
route du raccourci. C'étaient le coin beige, la bande de pierre étirée et les
traits sombres en diagonale sur la route. Le talus s'arrête maintenant avant
le couloir de chaque raccourci, et disparaît là où le mur s'ouvre
(`TrackBlockout._embankment_clear`).

**Tablier du pont de Sakura** : au loin, les planches faisaient un moiré en
écailles. Joints et veines s'effacent maintenant dans leur teinte moyenne
avec la distance (`sakura_road.gdshader`).

Test : `track_dressing_test` (vibreurs au bord, flèches et chevrons,
objets volants hors de portée).

---

## 7 bis. Tours de Cyber City en haute et extrême

Retour du test sur le PC fixe (4K) : « en basse et moyenne, c'est beau et
dark ; en haute et extrême, les bâtiments deviennent blancs ». Axel : « bug
de texture sur les fenêtres (les carrés de lumière) ».

- **Les tours blanchissaient** : la haute et l'extrême sont les seules
  qualités avec l'éclairage global (SDFGI) et les reflets d'écran. Les
  milliers de fenêtres lumineuses alimentaient l'éclairage global, qui
  rallumait toute la ville en gris clair, et les façades (35 % métal, à
  demi lisses) le reflétaient avec le ciel. Corrigé : tours, antennes et
  enseignes hors de l'éclairage global (`city_builder.gd`) ; façades mates,
  sans métal ni reflet ; vitres éteintes à peine brillantes ; en extrême,
  corniches et équipements de toit en noir mat (ils étaient gris clair).
- **Grain dans les carrés lumineux** : les reflets d'écran sur les façades à
  demi lisses ajoutaient du bruit dans chaque fenêtre ; les fenêtres
  allumées sont maintenant en émission pure. Le tirage des fenêtres
  allumées utilisait `sin()`, imprécis sur certaines cartes graphiques
  (motifs au lieu du hasard) : remplacé par un hachage sans sinus, comme
  ailleurs dans le projet. Bords des fenêtres lissés au pixel près (moins de
  crénelage qui grouille au loin).
- Au loin, la lueur moyenne d'une tour est un peu plus sombre (dalles moins
  claires dans le brouillard).

Fichiers : `city_building.gdshader`, `city_sign.gdshader`,
`city_antenna.gdshader`, `city_builder.gd`.

---

## 8. Essayé puis retiré

- **Couper murs, sol et talus en cases d'affichage** : peu de triangles en
  moins, +190 appels de dessin à 4 joueurs. Retiré.
- **Fondu progressif des cases 3D lointaines** : un objet en fondu passe dans
  la passe transparente, qui coûte cher. Remplacé par un relais net
  3D → sprite, sans trou.
- **6 cascades d'éclairage global en extrême** : tachaient la mer. Retiré.

---

## 9. Fichiers

**Nouveaux** :

- `game/tracks/roadside_dressing.gd` : décor près des routes, garde-corps
  des ponts, piliers des raccourcis.
- `game/tracks/road_decor.gd` : décor sur la route (vibreurs, chevrons,
  marquages, objets volants) ; shaders `chevron_board`, `float_decor`.
- `game/tracks/far_lod.gd`, `game/tracks/materials/impostor.gdshader`,
  `game/tracks/impostors/*.png` : décor lointain en sprites.
- `game/dev/bake_impostors.gd` : photos des arbres.
- `game/tracks/tree_kit.gd` : arbres détaillés de l'extrême.
- Shaders : `dress_glow`, `bamboo_fence`, `festival_maku`,
  `sakura_blossom.gdshaderinc` + `sakura_blossom_hd`.
- Tests : `track_dressing_test`, `extreme_quality_test`.

**Modifiés, partagés avec Axel** :

- `game/tracks/track_blockout.gd` : couleur de sommet des raccourcis,
  `embankment_reach`, dessous des ponts (`theme.bridge_under`), talus
  arrêté avant les raccourcis (`_embankment_clear`).
- `game/tracks/race_decor.gd` : foule lointaine.
- `game/dev/local_race.gd` : une ligne (compteur FPS en haut en course).
- `game/ui/main_menu.gd` : liste des qualités, avertissement, compteur FPS.
- `game/ui/race_hud.gd`, `game/ui/hud_dial.gd`, `game/ui/ui_kit.gd`,
  `game/ui/pad_glyph.gd` (pictos L2 / R2).
- `game/gameplay/graphics_settings.gd`, `game_state.gd`, `damage_fx.gd`.

**Modifiés, décor des circuits** : `playa_backdrop.gd`, `sakura_backdrop.gd`,
`city_builder.gd`, `japan_kit.gd`, `track_theme.gd`, les trois scènes de
circuit, et les shaders `playa_coast`, `playa_palm`, `sakura_road`,
`sky_day`, `fx/smoke`.
