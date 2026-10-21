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
    gagne, bots chasseurs.

### Circuits
- Trois circuits : Cyber City (nuit, néons), Playa Del Sol (île, pont de la
  baie), Sakura (Japon, croisement sous un pont vermillon) (#Sakura du
  2026-10-19).
- **Rallongés** à 4,4–4,6 km avec des détours (Docks, Échangeur, Marina,
  Village de pêcheurs, Rizières) (#70).
- **Raccourcis** : 5 routes droites de 24 m qui coupent les détours
  (~270 m de moins, flaques et barils, portique « RACCOURCI »), gérées par
  `TrackBlockout.branches` (murs ouverts, checkpoints doublés, progression et
  réapparition sur le raccourci, décor dégagé) (#70).
- **Bonus sur la piste** : réparation (✚, +40 PV, +30 remorque, pneus neufs)
  et recharge (⚡, le pouvoir le plus long redevient prêt), rangées de 3,
  retour après 15 s (#71).
- Pièges : flaques, panneaux éjectables, barils explosifs (dégâts visuels),
  plaques de boost, tremplins.

### Camions, dégâts
- Dégâts visibles : tôle cabossée, pièces arrachées, éclats, pneus qui
  éclatent ; sous bouclier, plus aucun dégât visuel (#58).
- Remorques larguées : PV ×2, se cassent en morceaux, se percent quand un
  camion fonce dedans (il la traverse), puis explosent (#65).

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

### Performance, rendu, son, build
- Gros à-coups supprimés, budget V3 (#41) ; creux de carrosserie calculés
  sans figer l'image (#44) ; SDFGI coupé sur puce Intel (#56).
- Sons de tour, d'arrivée, de largage, foule des tribunes (#36, #40).
- Export Windows et Linux préparé (#38).

## Outils hors du jeu

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
