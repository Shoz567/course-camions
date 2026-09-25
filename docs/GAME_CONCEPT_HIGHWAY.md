# GAME_CONCEPT_HIGHWAY.md — Concept & Arène Principale

## 1. La Vision en une phrase
Un brawler physique multijoueur mêlant le chaos de **Gang Beasts** et la course d'obstacles de **Fall Guys**, se déroulant sur une **autoroute à 3 voies en défilement continu** où les joueurs sautent de véhicule en véhicule tout en se battant pour ne pas être éjectés par l'arrière du convoi.

---

## 2. Piliers de Gameplay

### A. La Menace du Décor (Fall Guys)
- **Défilement continu** : Le convoi avance à pleine vitesse. Tout joueur qui tombe sur le bitume ou se fait dépasser par l'arrière de l'écran est éliminé (`KillZone`).
- **Obstacles aériens & tunnels** : Portiques de signalisation, panneaux d'autoroute et tunnels bas qui obligent les joueurs à **s'accroupir (Crouch)** sous peine d'être fauchés du toit d'un camion !
- **Sauts d'obstacles** : Espaces variables entre les remorques et voitures, nécessitant des sauts précis ou des plongeons (Dive).

### B. Le Combat Physique Actif (Gang Beasts)
- **Poings Indépendants** : Clic gauche / LT = poing gauche, Clic droit / RT = poing droit (tapoter pour frapper, coups portés qui déstabilisent l'équilibre adverse).
- **Grab & Traction** : Maintenir les gâchettes/clics pour attraper un adversaire, le porter au-dessus de sa tête et le balancer entre deux remorques, ou s'agripper d'urgence au pare-choc arrière d'un véhicule pour remonter.
- **État K.O. (KnockOff / Stun)** : Un joueur assommé par un coup de poing ou un impact contre un panneau devient un chiffon inerte pendant quelques secondes, risquant de glisser du toit s'il ne se relève pas vite.

---

## 3. Guide pour l'Équipe 3D (Collègues sur Blender)

Tous les assets visuels doivent être exportés au format **`.glb`** (glTF 2.0 binaire) :

1. **Véhicules (Plateformes de combat) :**
   - **Semi-remorque classique** (toit plat, 10–12 m de long, zone de combat principale).
   - **Camion Citerne** (toit incurvé, plus glissant / instable, fun pour les chutes !).
   - **Camion plateau / Flatbed** (obstacles bas, caisses).
   - **Petites voitures / Taxis / Pick-ups** (plateformes d'appoint pour les sauts entre voies).
2. **Éléments de décor & Dangers :**
   - **Tronçon d'autoroute 3 voies** (texture bitume, lignes blanches, barrières de sécurité latérales).
   - **Portiques & Panneaux suspendus** (hauteur calibrée pour imposer de se baisser / crouch).
