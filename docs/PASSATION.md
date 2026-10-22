# Passation — Crazy Wheels (course de camions arcade)

État au 2026-10-21. Tout est fusionné dans `main` (PR #30 à #72) ; seule la
PR #22 (Hezox83, `assets/tete-commune-catalogue`) reste ouverte, volontairement.
Le détail tâche par tâche est dans `PLAN.md` ; ce document résume.

## Où en est le jeu

- **Godot 4.7.2 + Jolt**, GDScript, 60 Hz. Lancer : `make run` ou le raccourci
  du Bureau.
- **Tests** : `make test` (≈ 105 scènes headless, ~4 min), lancé par le hook
  `pre-commit`. Tous verts à la fusion de #72.
- **Règles de dépôt** : branche `<zone>/<sujet>`, jamais de push sur `main`
  (hook `pre-push`), fusion par PR (squash). Messages de commit en français à
  l'impératif, sujet ≤ 72 caractères (hook `commit-msg`). Voir `CLAUDE.md`.
- **Contrats** : `docs/VEHICLE_SPEC.md` et `docs/METRICS.md` ne changent
  qu'avec l'accord de l'équipe. Dernier changement validé : tour de 90 à
  130 s, course en 3 tours (2026-10-20).

## Ce qui a été fait

### Réseau (en ligne, host qui fait foi)
- En ligne avec délai minimal : lobby, host / client, prédiction du camion
  local, interpolation des autres (#30, #48 latence réduite, #54 chargement
  robuste).
- Page de sélection en ligne : remorque et pouvoirs choisis par chaque joueur
  et envoyés au host (#45).
- Pouvoirs rejoués chez les clients (missile, laser, aura, recharges) (#46).
- Bots en ligne, simulés par le host, vus en marionnettes par les clients
  (#93) ; tours du client à jour à chaque checkpoint (#92).
- Autres camions au présent du joueur local (façon Rocket League), sur leur
  courbe, lissés ; bonus prédits (#94).
- 12 joueurs en ligne (écran partagé : 6) ; débit du host affiché au
  salon ; bots deux fois moins coûteux à 12 (#95).
- Décor proche et lointain, style par circuit, qualité extrême
  (`visuel/decor-style-extreme`, intégrée après #95, `docs/VISUEL.md`) :
  vérifiée en ligne et à 12 camions (PLAN.md).
- Correctifs : largage prédit refusé par le host rendu, trou dans une remorque
  aussi chez le client, délai de largage à la réapparition (#67).
- À faire : **test réel sur 2 PC** (reporté depuis longtemps).

### Course et règles
- RaceManager : temps limite après la 1re arrivée, sons moteur, secousse
  caméra (#31) ; la fin du 1er ne cache plus l'écran des autres (#47) ;
  ralenti d'arrivée (#37).
- Salle d'attente : chaque joueur rejoint avec sa manette (#33).
- Sortie de route : chute puis explosion au sol (#49) ; l'aide qui rabattait
  un camion en l'air vers la piste est retirée (#58).
- **Largages de remorque limités** : 0 à 5 par course (menu, 3 par défaut),
  20 s de délai après le retour d'une remorque (#66).
- **Modes de jeu** (#72, ligne MODE du menu ; en ligne depuis le
  2026-10-21, sauf le contre-la-montre) :
  - Élimination : après 30 s puis toutes les 20 s, le dernier saute ;
  - Contre-la-montre : seul, fantôme du meilleur tour sauvegardé
    (`user://ghosts`) ;
  - Arène stock-car : 3 arènes (une par habillage), 3 vies, le dernier debout
    gagne, bots chasseurs (ils reculent quand ils poussent sans avancer).
    Tremplins en bosses (deux rampes dos à dos, flancs inclinés) ; départs,
    réapparitions et bonus à l'écart des obstacles. Camions plus maniables
    (`VehicleTuning.for_arena`) ; une remorque par vie, pas de largage ;
    carte d'arène façon FPS ; bots qui vont aux bonus et évitent murs, îlot
    et barils. Niveaux de bots distincts en arène : facile (lent, jamais de
    soin, pouvoirs rares), moyen (soin une fois sur deux, attaque
    régulière), dur (charge à la nitro, interception, proies abîmées, soin
    systématique) ; `arena_levels_test` mesure le danger de chaque niveau.
- **Bots en course** (2026-10-22) : échelle repartie du dur (environ +7 %
  par tour en moyen, +18 % en facile), remorques par niveau, bonus pris par
  le dur et le moyen, plaques de boost et sauts maîtrisés. Outil :
  `dev/bot_bench` (historique des 20 dernières secondes avant un blocage ou
  une chute).

### Circuits
- Trois circuits : Cyber City (nuit, néons), Playa Del Sol (île, pont de la
  baie), Sakura (Japon, croisement sous un pont vermillon) (#Sakura du
  2026-10-19).
- **Rallongés** à 4,4–4,6 km avec des détours (Docks, Échangeur, Marina,
  Village de pêcheurs, Rizières) (#70).
- **Raccourcis** : 5 routes qui coupent les détours (flaques et barils,
  portique « RACCOURCI »), gérées par `TrackBlockout.branches` (murs
  ouverts, checkpoints doublés, progression et réapparition sur le
  raccourci, décor dégagé) (#70). Depuis le 2026-10-21 : jonctions au ras
  de la piste (ni marche ni scintillement), tracés en S (docks, village,
  rizières) et sauts (échangeur 85 km/h, marina 95 km/h ; tombé : chute,
  réapparition après le vide). Les bots les prennent.
- **Bonus sur la piste** : réparation (✚, +40 PV, +30 remorque, pneus neufs)
  et recharge (⚡, le pouvoir le plus long redevient prêt), rangées de 3,
  retour après 15 s (#71).
- Pièges : flaques, panneaux éjectables, barils explosifs (dégâts visuels),
  plaques de boost, tremplins.
- **Décor près de la route** (2026-10-22, `RoadsideDressing`, nœud de chaque
  scène de circuit) : câbles tendus au-dessus de la piste (enseignes néon de
  Cyber City, fanions et banderoles de Playa, lanternes et shimenawa de
  Sakura), objets sur les murs (bornes, drapeaux, nobori, lanternes),
  panneaux sur leur face intérieure (écrans holo, sponsors, rideaux de fête)
  et au pied des murs (distributeurs, planches de surf, tours de sauveteur,
  paillotes, herbes de dune, azalées, palissades de bambou). Purement
  visuel, sans collision, généré à graine fixe (`track_dressing_test`).
  Sakura et Playa : les arbres longent aussi les portions hautes, au pied
  du talus (`TrackBlockout.embankment_reach`) ; Sakura passe de 760 à 1 700
  cerisiers.
- **Ponts** (2026-10-22, « pont vide ») : garde-corps sur les murs des
  tabliers - laque vermillon à giboshi de bronze et lanternes bonbori
  (Sakura), poteaux de bois flotté, cordages, bouées, réverbères (Playa) ;
  tablier de Sakura en hinoki patiné (poutres cloutées tous les 6 m).
- **Joints des raccourcis** : leur chaussée et leurs murs n'avaient pas de
  couleur de sommet, les shaders de Playa et Sakura y dessinaient un pont de
  bois ; corrigé (chaussée et murs ordinaires), et un pilier à l'habillage
  du circuit cache chaque bout de mur ouvert.

### Camions, dégâts
- Dégâts visibles : tôle cabossée, pièces arrachées, éclats, pneus qui
  éclatent ; sous bouclier, plus aucun dégât visuel (#58).
- Remorques larguées : PV ×2, se cassent en morceaux, se percent quand un
  camion fonce dedans (il la traverse), puis explosent (#65).
- Réapparition lancée à 80 km/h (moins avant un virage), joueurs et bots
  (#91).

### Pouvoirs (6 : bouclier, missile, laser, mitrailleuse, scie, boomerang)
- Séries 1 et 2 (#43, #52) ; scie à hauteur des pneus, qui les crève (#59) ;
  boomerang aimanté avec de la portée (#60).
- Tous abîment tête et remorque, PV et tôle (#59) ; ils visent la remorque
  d'un camion qui tracte, la tête n'en prend que 20 % (#64).
- Visée automatique sur le camion le plus proche devant (#61) ; **cible
  rouge** sur le camion visé, flèche haut de la croix pour changer de cible
  en cycle (#63).
- **Retour de coup** : chiffre des dégâts, croix, son, bip au changement de
  cible ; viseur rouge / gris (hors de portée) / terne (recharge) (#68).
- HUD : pastille verte qui se vide pendant l'effet d'un pouvoir actif.

### Bots (solo et écran partagé)
- Bots en 3 niveaux (#50) ; ligne de course optimisée, coupent les virages,
  évitent barils et remorques (#58).
- Tactiques : bouclier quand un missile arrive, largage devant un poursuivant
  avant un virage (#69). En arène, ils chassent.

### Caméra et commandes
- Stick droit : regard autour (30° / 10°) ; **L1 maintenu : regarder
  derrière** ; le klaxon passe sur L3 (#62).
- Manette réaffectable, options sauvegardées (#35) ; schéma DualSense dans
  les paramètres.

### Interface
- Menus d'Angelo fusionnés et étendus (#39), habillages par circuit
  (néon, Playa, Sakura) (#57, ambiance du 2026-10-19).
- Écran de chargement avant chaque course (#42).
- HUD de course : cadran façon arcade, carte du pilote (#53) ; boutons de
  joueurs à leur couleur (#51).
- **HUD, boutons et compteur à l'habillage du circuit** (2026-10-22, « ça
  blend pas, fait tache ») : cadran en diodes néon (Cyber City), en bouée
  corail et blanche sur un lagon (Playa), en laque noire cerclée d'or avec
  une fleur de cerisier en tête de jauge (Sakura) ; pouvoirs en tuiles
  (parallélogrammes néon, bois flotté, ema de bois à cordon rouge) qui se
  remplissent par le bas ; état du largage sur une plaquette ; aide des
  commandes en barre de pictos manette + ligne clavier, effacée après 14 s
  (`HudDial`, `RaceHud`). Menu : boutons ronds Son / Paramètres à
  l'habillage (`UiKit.style_icon`), compteur FPS en plaquette sous ces
  boutons (il les recouvrait).
- **Menus rangés en pages** (2026-10-22) : accueil à quatre tuiles, partie
  locale par étapes, menu en ligne à part (`OnlineMenu` : héberger ou
  rejoindre, puis salon avec les règles du host vues par tous) ; réglages
  du local et de l'en ligne séparés (`GameState.use_profile`). Circuit en
  premier, au menu déroulant (local et salon).
- Musique du menu (`MenuMusic`) ; camions du plateau muets (le « bruit
  sourd ») ; bruitages 6 dB plus bas, musique de course 2 dB plus haut.
  Trois jauges dans les paramètres : général, musique, bruitages.
- Vraies musiques (CC0, MintoDog, Git LFS) : une par circuit, version
  rapide au dernier tour, une pour le menu (`game/audio/music/`).

### Performance, rendu, son, build
- Détail du travail visuel du 2026-10-22 (décor proche, décor lointain,
  style, qualité extrême, reflets) : `docs/VISUEL.md`.
- Gros à-coups supprimés, budget V3 (#41) ; creux de carrosserie calculés
  sans figer l'image (#44) ; SDFGI coupé sur puce Intel (#56).
- **Décor lointain allégé** (2026-10-22) : palmiers et cerisiers en 3D
  jusqu'à 250 m seulement (cases de 120 m), au-delà un sprite par arbre qui
  tourne face à la caméra (`FarLod`, `impostor.gdshader`). Le sprite est
  une photo du modèle 3D : `godot --path game -s res://dev/bake_impostors.gd`
  (fenêtré) refait `tracks/impostors/*.png` si le modèle change. Foule des
  tribunes : 9 triangles par spectateur au-delà de 250 m au lieu de 56
  (`CrowdFar`). Mesuré (tour de piste, cette machine) : triangles −45 %
  (Playa) et −24 à −36 % (Sakura) par rapport à `main`, temps GPU inchangé
  à ±0,3 ms : ici le GPU est limité par les effets plein écran, pas par la
  géométrie ; le gain compte sur une carte plus modeste.
- **Qualité « extrême »** (2026-10-22, en tête de la liste des paramètres,
  après un avertissement « requiert un GPU ») : tous les effets jusqu'à
  4 vues, réglages au maximum (occlusion et éclairage indirect ultra à
  pleine résolution, ombres douces ultra sur 8192 px, reflets à 128 pas,
  éclairage global à 128 rayons), MSAA 4x + SMAA, détail maximal, filtrage
  16x, ombre du soleil 1,6 fois plus loin (`GraphicsSettings`). Le décor se
  construit plus riche (`GraphicsSettings.extreme_assets`) : palmiers et
  cerisiers détaillés (`TreeKit` : folioles, branches, grappes de fleurs à
  cinq pétales ; ~5 700 et ~8 500 triangles), 3D jusqu'à 420 m et sprites
  photographiés sur ces modèles (`impostors/*_hd.png`), +38 % de palmiers,
  +35 % de cerisiers, maisons de Sakura ouvragées (lattis, noren, lanterne,
  chevrons, fenêtres à barreaux, faîtage ; clochettes des pagodes), tours de
  Cyber City détaillées (corniches, acrotère, toits équipés, enseignes
  verticales) et plus nombreuses, décor de bord de piste plus serré et vu
  jusqu'à 690 m (`extreme_quality_test`). Sur ce PC portable, la qualité
  extrême fait chuter les images par seconde : c'est attendu (testé : 13 à
  17 images/s à 1 joueur sur Radeon 780M). En écran partagé sur puce
  intégrée (3 vues et plus), le décor reste ordinaire, comme les effets
  (`split_quality`).
- **Reflets de la mer** (Playa, 2026-10-22) : ciel reflété en 1024 px en
  extrême (128 sinon ; ciels statiques, calculés une fois), mer qui se calme
  au loin (îlots, palmiers et pont s'y reflètent), sol hors de la grille de
  l'éclairage global et cascades de celui-ci laissées à 4 : leurs voxels
  tachaient l'eau de plaques sombres à bord net.
- Fumée des dégâts redessinée : bouffées rondes à bord net, éclairage en
  deux tons, gris qui s'éclaircit en montant (plus de tache noire en plein
  jour).
- Sons de tour, d'arrivée, de largage (#36, #40) ; la foule des tribunes,
  jugée brouillonne, est muette depuis le 2026-10-22.
- Export Windows et Linux préparé (#38).

## Outils hors du jeu

- **Essai en ligne sur un seul PC** : `dev/net_e2e.tscn`, host et client
  pilotés par des bots, journal comparable des deux côtés (#92).

- **Barre d'état Claude Code** : `~/.claude/statusline.js` (modèle, branche,
  coût, jauges du contexte et des quotas). Paquet à partager :
  `barre-etat-claude-code.zip` (sur le Bureau, notice incluse).

## Limites connues

- Le contre-la-montre ne se joue pas en ligne (en ligne : course normale) ;
  Élimination et Arène en ligne n'ont pas encore été essayés sur 2 PC.
- Les bots se larguent leurs remorques dessus dans le peloton : à juger en
  partie (nombre de largages réglable au menu).
- Bots : dépassement dans l'épingle serrée de Sakura ; premiers tours en
  peloton lents.
- Option « Vibrations manette (bientôt) » : sans effet pour l'instant.
- `make test` dure ~4 min, au-delà des 60 s visées par `CLAUDE.md`.
- Rien des derniers lots (#59 à #72) n'a encore été essayé manette en main.

## Suites possibles

- Essai réel en ligne sur 2 PC ; modes en ligne.
- Bots qui vont chercher les bonus.
- Vibrations de manette ; tutoriel des nouvelles commandes à la 1re course.
- Relevé de fin de course (dégâts par pouvoir, largages) pour équilibrer.
- Scinder `make test` en suite rapide / complète.
