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
- [ ] **Barre de PV (100 HP)** :
  - Suivi des 100 HP (affichage discret / petit ou interne avant dégradations visuelles).
  - Calcul des dégâts : uniquement le tracteur (cabine / avant) encaisse les dégâts sur les PV du joueur.
  - Chocs contre les murs : **-1 à -5 HP** selon la violence / vitesse de l'impact.
  - Percussion d'un baril explosif : **-15 HP**.
  - La remorque agit comme un **bouclier défensif** (protège l'arrière du joueur, les chocs dessus n'entament pas les 100 HP du tracteur).
- [ ] **Mort & Respawn** :
  - À 0 HP : explosion / fumée, immobilisation pendant **3 secondes**, puis réapparition (respawn) sur la piste avec 100 HP restaurés.

### Module 3 : Course & Règles (4 Tours)
- [x] **4 Laps** :
  - Passage du nombre de tours de 3 à **4 tours** (`total_laps = 4`) et synchronisation HUD/menu.

### Module 4 : Obstacles du Circuit : Panneaux, Flaques & Barils Explosifs
- [x] **Panneaux de virage sans pénalité** :
  - Éjection spectaculaire (*yeet* > 11 m) conservée, suppression de la division de vitesse par 2 (flow de course arcade préservé).
- [x] **Flaques d'huile / eau glissantes** :
  - Ne freinent plus le camion (vitesse longitudinale 100 % préservée) : perte brutale d'adhérence latérale (effet savonnette) obligeant à contre-braquer.
- [x] **Barils explosifs** :
  - Fût métallique rouge et jaune émissif sur la piste.
  - Détonation au contact : onde de choc, lumière dynamique, son d'explosion procédural et léger *yeet* physique du camion sans basculement. Éjection du baril et respawn après 6 s. (Dégâts -15 HP branchés avec le module PV).

### Module 5 : Dégradations Visuelles Localisées
- [ ] **Système de dégradations visuelles par zone** :
  - Déformations et éraflures/noirceur là où le camion a tapé ou s'est fait taper (avant, flancs, remorque).
  - Fumée légère -> fumée dense selon le niveau de PV restants.

### Module 6 : Remorques Larguées Persistantes & Destructibles
- [ ] **Persistance sur la piste** :
  - Les remorques larguées ne disparaissent plus au bout d'un timer : elles restent comme obstacles physiques sur la piste !
- [ ] **Règles d'équilibrage du largage** :
  - Les **5 premières secondes** de course : largage interdit (évite le bouchon au départ).
  - Après largage : une nouvelle remorque réapparaît sur le camion du joueur pour lui permettre d'en larguer d'autres.
- [ ] **Points de vie de la remorque (50 HP)** :
  - Chaque remorque abandonnée sur la piste a **50 HP**.
  - Elle perd des PV lors des chocs avec les autres camions ou attaques.
  - Dégradation visuelle progressive puis destruction / disparition quand ses 50 HP tombent à 0.

### Module 7 : Flux Menu & Écran Scindé de Sélection des Pouvoirs
- [ ] **Bouton READY au menu principal** :
  - Remplacer le bouton "COMMENCER" direct par un bouton **"READY"**.
- [ ] **Écran de sélection des pouvoirs en écran scindé** :
  - Bascule en écran scindé (selon le nombre de joueurs) sur un sas de préparation.
  - Chaque joueur choisit ses **4 pouvoirs** avec sa manette avant le lancement de la course.
  - Mappage des 4 pouvoirs sur les 4 directions de la **croix directionnelle (D-PAD)** de la manette PS5 DualSense (Haut, Bas, Gauche, Droite).

### Module 8 : Arsenal des Pouvoirs (1ers Pouvoirs)
- [ ] **Pouvoir 1 : Lance-Missiles** :
  - Tire 2 missiles vers l'avant.
  - Dégâts : **-15 HP** à la cible touchée.
  - Cooldown : **5 secondes**.
- [ ] **Pouvoir 2 : Citerne d'Essence / Huile** :
  - Citerne visuelle fixée sur le dos de la remorque (part avec la remorque si larguée, revient avec elle).
  - Déverse de l'essence pendant **2 secondes** créant une traînée ultra-glissante derrière soi.
  - Cooldown : **30 secondes**.
- [ ] **Pouvoir 3 & 4** :
  - Emplacements prévus sur les touches restantes du D-PAD (spécifications à venir selon les retours de l'utilisateur).
