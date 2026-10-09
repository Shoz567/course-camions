# Bloc-notes & GIGA TODO — Crazy Wheels

---

## ÉTAT DE LA BASE DE CODE
- Branche : `main` alignée sur `origin/main` (`dba2a5e`).
- 46 tests automatisés au vert (`make test` : 46/46 PASS).
- Déjà implémenté : 2 circuits (Cyber City & Playa Del Sol), 1 à 6 joueurs en écran partagé (grille 3x2), manette PS5 DualSense style Forza Horizon, musique arcade Mega Drive FM procédurale, collines 43m de dénivelé, drift débridé à 16° sans tête-à-queue, 4 vitesses (50cc à 200cc).

---

## GIGA TODO : PLAN D'IMPLÉMENTATION PAR MODULES

### Module 1 : Véhicule & Conduite Légère
- [x] **Vitesse tracteur solo (sans remorque)** :
  - Multiplicateur de vitesse max à **x1.2** (`solo_top_speed_factor = 1.2`) et accélération accrue quand la remorque est larguée pour un boost d'agilité immédiat.

### Module 2 : Système de Points de Vie (HP) & Mort / Respawn
- [x] **Barre de PV (100 HP)** (Lot 2, `TruckHealth`) :
  - Suivi des 100 HP (affichage discret / petit ou interne avant dégradations visuelles).
  - Calcul des dégâts : uniquement le tracteur (cabine / avant) encaisse les dégâts sur les PV du joueur.
  - Chocs contre les murs : **-1 à -5 HP** selon la violence / vitesse de l'impact.
  - Percussion d'un baril explosif : **-15 HP**.
  - La remorque agit comme un **bouclier défensif** (protège l'arrière du joueur, les chocs dessus n'entament pas les 100 HP du tracteur).
- [x] **Mort & Respawn** (épave gelée 3 s, explosion, réapparition sur la ligne de course) :
  - À 0 HP : explosion / fumée, immobilisation pendant **3 secondes**, puis réapparition (respawn) sur la piste avec 100 HP restaurés.

### Module 3 : Course & Règles (4 Tours)
- [x] **4 Laps** :
  - Passage du nombre de tours de 3 à **4 tours** (`total_laps = 4`) et synchronisation HUD/menu.

### Module 4 : Obstacles du Circuit : Panneaux, Flaques & Barils Explosifs
- [x] **Panneaux de virage sans pénalité** :
  - Éjection spectaculaire (*yeet* > 11 m) conservée, suppression de la division de vitesse par 2 (flow de course arcade préservé).
- [x] **Flaques d'huile / eau glissantes** :
  - Ne freinent plus le camion (vitesse longitudinale 100 % préservée) : perte brutale d'adhérence latérale (effet savonnette) obligeant à contre-braquer.
- [x] **Barils explosifs** (Lot 1 fonctionnel ; Lot 3 : 1,2 m x 2,5 m, chevrons lumineux, gyrophare stroboscopique à halo) :
  - Fût métallique rouge et jaune émissif sur la piste.
  - Détonation au contact : onde de choc, lumière dynamique, son d'explosion procédural et léger *yeet* physique du camion sans basculement. Éjection du baril et respawn après 6 s. Dégâts -15 HP (TruckHealth).
  - Remasterisation (demande utilisateur) : barils actuellement trop petits et peu visibles à grande vitesse sur la piste de 75 m ; à agrandir sensiblement (~x1.8 à x2), contraste renforcé et ajout d'une balise stroboscopique/lumineuse arcade clignotante visible de loin.

### Module 5 : Dégradations Visuelles Localisées
- [x] **Système de dégradations visuelles par zone** (Lot 3 : décalques de choc localisés, fumée moteur selon les PV, `TruckDamageFx`) :
  - Déformations et éraflures/noirceur là où le camion a tapé ou s'est fait taper (avant, flancs, remorque).
  - Fumée légère -> fumée dense selon le niveau de PV restants.

### Module 6 : Remorques Larguées Persistantes & Destructibles
- [x] **Persistance sur la piste** (Lot 2) :
  - Les remorques larguées ne disparaissent plus au bout d'un timer : elles restent comme obstacles physiques sur la piste !
- [x] **Règles d'équilibrage du largage** (verrou 5 s au GO, nouvelle remorque après la recharge de 30 s) :
  - Les **5 premières secondes** de course : largage interdit (évite le bouchon au départ).
  - Après largage : une nouvelle remorque réapparaît sur le camion du joueur pour lui permettre d'en larguer d'autres.
- [x] **Points de vie de la remorque (50 HP)** (Lot 2 : PV, dégâts selon l'énergie du choc, explosion ; Lot 3 : traces, suie et fumée selon ses PV) :
  - Chaque remorque abandonnée sur la piste a **50 HP**.
  - Elle perd des PV lors des chocs avec les autres camions ou attaques.
  - Dégradation visuelle progressive puis destruction / disparition quand ses 50 HP tombent à 0.

### Module 7 : Flux Menu & Sas READY
- [x] **Sas READY** (Lot 2 : dans la course, chaque joueur valide avec Carré avant le compte à rebours).
- [ ] **Bouton READY au menu principal** :
  - Remplacer le bouton "COMMENCER" direct par un bouton **"READY"**.

### Module 8 : Système de Pouvoirs (En attente de la nouvelle approche)
- [ ] **Nouvelle formule de pouvoirs** :
  - Les anciens pouvoirs provisoires (ancien 16 lance-missiles et ancien 17 citerne d'essence) sont supprimés.
  - La nouvelle mécanique de pouvoirs sera spécifiée selon les retours et choix de gameplay du joueur.
