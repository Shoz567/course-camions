# ART_PIPELINE.md — Blender headless → Godot

Règle fondatrice : **le script Python est la source de vérité, pas le `.blend`.**
Tout asset se régénère depuis zéro par `make assets`. Rien d'artistique n'est
committé en binaire (le hook `pre-commit` refuse les `.glb` et `.blend`).

Pourquoi : un agent peut itérer seul sur un script (générer, mesurer, corriger)
alors qu'il ne peut pas cliquer dans Blender. Et un diff de paramètres est
lisible, un diff de `.blend` ne l'est pas.

---

## 1. Chaîne complète

```
tools/blender/build_*.py
        │  blender -b -P ...
        ▼
game/assets/generated/*.glb          (git-ignoré)
        │  godot --headless --import
        ▼
game/.godot/imported/                (git-ignoré)
        │  instanciation
        ▼
game/vehicles/*.tscn, game/tracks/*.tscn
```

## 2. Squelette d'un script de build

```python
import bpy, sys, argparse
from pathlib import Path

sys.path.append(str(Path(__file__).parent))
from lib import mesh, export

def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--variant", default="default")
    p.add_argument("--out", required=True)
    return p.parse_args(argv)

def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)   # scène vierge, toujours
    objects = build(args.variant)
    export.apply_transforms(objects)
    export.to_glb(args.out, objects)
    print(f"OK {args.out} tris={sum(mesh.tri_count(o) for o in objects)}")
```

Exigences pour tout script de build :
- part d'une scène vide, ne dépend d'aucun état antérieur ;
- **idempotent** : deux exécutions produisent le même résultat ;
- `raise SystemExit("message")` en cas d'échec (code de sortie non nul) ;
- imprime en dernière ligne le chemin produit et le nombre de triangles ;
- chemins construits avec `pathlib`, jamais par concaténation (projet développé
  sous Windows).

## 3. Réglages d'export

Centralisés dans `tools/blender/lib/export.py`, **seul endroit** où l'on appelle
`bpy.ops.export_scene.gltf` : GLB, `export_yup=True`, modificateurs appliqués,
**rotation et échelle appliquées, location conservée**, pas de caméra ni de
lumière.

✅ **Validé** (acquis A6 de `docs/SPIKE.md`) : un cube de 1 m arrive à
1,0000 m dans Godot, les noms sont conservés.

✅ **Validé par le spike V4** (acquis A13) : chassis + 4 roues séparées, pivots
à 0,0000 m du moyeu dans Godot. La location n'est **jamais** appliquée : c'est
elle qui porte le pivot. L'appliquer mettait les roues à 2,24 m du moyeu.

## 4. Le camion

### Objets et noms — un contrat

Un camion est exporté en **objets séparés**, nommés selon
`docs/VEHICLE_SPEC.md` §4 :

| Objet | Rôle | Pivot (origine) |
|---|---|---|
| `Body` | carrosserie : cabine + châssis | origine du camion (au sol, centré) |
| `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR` | roues | **exactement au moyeu** |

Le pivot au moyeu n'est pas un détail : c'est autour de lui que Godot fera
tourner la roue (rotation) et la braquera (direction). Un pivot décalé de 2 cm
donne une roue qui « boite ».

Un renommage appliqué d'un seul côté ne produit pas d'erreur bruyante : la roue
n'est pas trouvée, elle reste immobile. Les noms se changent dans
`VEHICLE_SPEC.md` d'abord, dans le même commit des deux côtés.

### Le maillage n'a aucune autorité sur la physique

Le modèle **suit** `VEHICLE_SPEC.md` (dimensions, positions et rayon des roues),
il ne le définit pas. La physique utilise deux boîtes de collision et quatre
rayons définis côté Godot ; on ne dérive jamais une masse, un centre de masse ou
une forme de collision du maillage. Si le camion paraît trop haut, c'est la
carrosserie qu'on ajuste, pas la suspension.

### 4 bis. Modèle externe des camarades (`Assets_Visuels/`)

Les modèles `Assets_Visuels/Camion/Camions_Course_Export/*.glb` sont faits à la
main, hors pipeline Blender scripté, et versionnés **par Git LFS** depuis le
2026-10-02 (`docs/ENVIRONMENT.md` §6.7 ; les `.fbx` sources restent hors
dépôt). `TruckVisual` (`game/vehicles/truck_visual.gd`) les charge **à
l'exécution** s'ils existent ; sinon le camion garde ses boîtes de blockout. Un
clone sans Git LFS et les tests (headless) ne dépendent donc d'aucun binaire. Un export du jeu
ne les embarquera pas : à régler en phase 7 (import dans le projet, licence et
origine confirmées).

Mesuré sur `Camion_Bleu.glb` (2026-09-28), **le modèle ne suit pas la spec** :

| Point du contrat | Spec | Modèle |
|---|---|---|
| Avant | −Z | +Z |
| Échelle | appliquée (1,0) | ×1,25 non appliqué sur la racine |
| Remorque | semi-remorque (depuis le 2026-09-28) | semi-remorque 3 essieux avec aileron : conservée |
| Longueur du tracteur | 5,8 m | 6,1 m |
| Largeur / hauteur | 2,5 / 3,2 m | 2,9 m (cabine), 3,7 m hors tout / 3,7 m (4,7 m échappements) |
| Empattement / voie | 3,8 / 2,1 m | 3,1 / 2,4 m |
| Rayon de roue | 0,55 m | 0,72 m (AV), 0,84 m (AR jumelées) |
| Noms des roues | `Wheel_FL`… pivot au moyeu | `Roue_AV_G`… groupes sans pivot au moyeu ; « G » est à droite une fois l'avant en −Z |

`TruckVisual` l'**ajuste** donc sans toucher à la physique : demi-tour,
échelle uniforme ×0,947 calculée sur le **tracteur** (5,8 m) et appliquée à tout
l'ensemble (semi-remorque exclue du calage mais affichée : 16,4 m hors tout),
centrage sur la caisse du tracteur, bas des pneus au sol, pivot recalé au moyeu
de chaque groupe de roues du tracteur, roues associées aux rayons **par
position** (pas par nom) ; les roues de remorque restent fixes. Le nœud
`Remorque` (toute la semi-remorque, aileron et roues compris) est accroché à un
pivot posé sur la sellette de la spec (0 ; 1,8 ; 1,2) et tourne avec l'angle de
remorque du camion (VEHICLE_SPEC §5 bis). Restent
visibles : cabine plus large (3,5 m) et plus haute (4,4 m) que sa collision, et
roues visuelles à l'empattement du modèle (≈ 3,0 m) au lieu de 3,8 m.
`truck_visual_test` vérifie l'ajustement ; il se saute sans le modèle.

**À corriger à la source** (blender-modeler / camarades) : avant en −Z, échelle
appliquée, empattement 3,8 m, voie 2,1 m, roues de 0,55 m, objets `Body` +
`Wheel_FL/FR/RL/RR` pivotés au moyeu (§4), caisse de remorque de 13,0 × 3,0 m
dont le bas est à 1,8 m (VEHICLE_SPEC §5). **À
vérifier** : les nœuds `Logo_001`, `Embleme_004/005` et `Plaque_AV_UE` ne
doivent reproduire aucune marque existante (`CLAUDE.md` §1).

### Style

Formes franches et lisibles de loin — en écran partagé à 4, chaque camion
occupe une petite portion d'une petite vue. Silhouettes de cabine distinctes
d'une variante à l'autre, couleur dominante par joueur. Aucun camion, logo ou
marque existants.

### 4 ter. Catalogue de véhicules et objets d'arme (2026-10-02)

Demandé par l'utilisateur : des véhicules et des armes **dans le style des
camions de l'équipe** (cabine avancée à arêtes arrondies, peinture
métallisée, chromes, cheminées à flamme, rampe de phares, numéro de course
dans un rond blanc, grosses roues à jante alu). **Visuels seulement** : le
gameplay des armes sera spécifié plus tard.

| Script | Sortie (`game/assets/generated/`) |
|---|---|
| `build_vehicle.py --variant=…` | `vehicules/{citerne, betaillere, remorque, porte_voitures, grue, chasse_neige, pompier, chariot_elevateur}.glb` |
| `build_item.py --item=…` | `armes/{lance_missiles, missile, scie_geante_d/g, mitrailleuse, grenade, camion_projectile, doudou_geant, voiture_*, bouclier_emetteur, bouclier_coque, laser_emetteur, laser_faisceau, boomerang_aimante}.glb` |

Code partagé : `lib/kit.py` (matériaux, primitives, roue), `lib/vehicles.py`,
`lib/items.py`. `make assets` régénère les 26 fichiers en ~15 s.

**Véhicules.** Ils suivent le contrat du §4 et `VEHICLE_SPEC.md` (vérifié
après import dans Godot : roues à (±1,26 ; 0,66 ; ±2,28), sellette à
(0 ; 2,16 ; 1,44), avant en −Z). `Body` + `Wheel_FL/FR/RL/RR` pivotées au
moyeu ; `build_vehicle.py` refuse un objet manquant ou un pivot hors du
moyeu. Trois silhouettes de cabine : plate (citerne, grue, chasse-neige,
pompier), plate à couchette (remorque, porte-voitures), à capot
(bétaillère).
- **Semi-remorques** (citerne, bétaillère, porte-conteneur `remorque`,
  porte-voitures) : tout est enfant du vide `Remorque` posé sur la sellette,
  comme le nœud du même nom des modèles de l'équipe. Roues de remorque fixes
  (`Remorque_Roues`).
- **Porteurs** (grue, chasse-neige, pompier) : pas de sellette ; la caisse
  ou l'équipement est enfant de `Body`.
- **Chariot élévateur** : engin hors gabarit camion (roues de 0,40 / 0,32 m),
  mêmes noms d'objets ; ses cotes ne relèvent pas de `VEHICLE_SPEC.md`.
- **Pièces mobiles**, pivotées sur leur axe : `Grue_Tourelle` / `Grue_Fleche`
  / `Grue_Crochet`, `Echelle_Tourelle` / `Echelle`, `Lame_Neige`, `Mat` /
  `Fourche`, `Conteneur_Porte_G/D` (charnière extérieure),
  `Voiture_Chargee_1..5` (détachables).

**Points d'accroche des armes** : des vides `Socket_*` (des `Node3D` dans
Godot). Une arme se pose en enfant du socket, transformation nulle.

| Socket | Où | Armes prévues |
|---|---|---|
| `Socket_Toit` | toit de la cabine | mitrailleuse, laser, émetteur de bouclier, boomerang |
| `Socket_Avant` | pare-chocs avant | boomerang |
| `Socket_Lateral_G` / `_D` | flancs du tracteur, entre les essieux | scies géantes (`scie_geante_g` / `_d`) |
| `Socket_Arriere` | arrière **de la remorque** (ou de la caisse d'un porteur) | lance-missiles |
| `Socket_Conteneur` | plancher arrière de la remorque | largage des voitures |

Les sockets de remorque sont enfants de `Remorque` : ils suivent son
articulation.

**Objets d'arme.** Origine de la racine = point d'accroche (centre pour un
projectile), avant en +Y Blender (−Z Godot), pièces mobiles séparées :
`Lance_Missiles` (lacet) → `Lance_Missiles_Caisson` (tangage) →
`Missile_1..6` (cachés un à un au tir) ; `Scie_Bras_*` → `Scie_Lame_*`
(rotation sur X) ; `Mitrailleuse_Socle` → `_Tourelle` (lacet) → `_Canon`
(tangage) → `_Barillet` (rotation sur Y) ; `Laser_Socle` → `Laser_Canon` →
vide `Laser_Bouche` ; `laser_faisceau` mesure 1 m en +Y depuis son origine
(à étirer) ; `bouclier_coque` est une coque alvéolée de 5,6 × 23 × 9 m centrée
sur son origine (à poser au centre de l'ensemble, échelle libre) ;
`Boomerang_Support` → `Boomerang` (pivot au centre de rotation en vol). Le
doudou géant est un ours générique, sans personnage existant.

**Matériaux.** Ce catalogue n'applique **pas** le §7 (couleurs vertex) : il
reprend les matériaux nommés des modèles de l'équipe (`Peinture_Cabine_<Couleur>`,
`Chrome`, `Jante`, `Pneu`, `Phare`, `Vitre`…) pour avoir le même rendu
(métal, brillance, feux émissifs) et pour que la livrée de `TruckVisual`
(par préfixe de nom de matériau) s'y applique. Entre 1 et ~20 matériaux par
modèle, partagés entre modèles.

**Non branché dans le jeu.** Aucun `.tscn` ni `.gd` ne charge encore ces
fichiers : `TruckVisual` charge toujours `Camion_Bleu.glb`. Brancher un
véhicule du catalogue ou une arme est une tâche de gameplay à part.

## 5. Les pistes

Deux objets exportés par piste :
- `Track01` : le visuel ;
- `Track01-col` : une version simplifiée. Le suffixe `-col` fait générer par
  Godot un `StaticBody3D` avec `ConcavePolygonShape3D` à l'import.

Rappels :
- concave = **statique uniquement**. Tout obstacle mobile a une collision
  convexe (boîte), donc se construit comme tel ;
- chaque zone de collision porte sa **surface** (`asphalt`, `dirt`, `grass`,
  `ice` : `VEHICLE_SPEC.md` §8), via une propriété personnalisée exportée en
  métadonnée ;
- l'épaisseur des murs respecte le minimum fixé par le spike V2 ;
- les checkpoints, zones de reset et points de réapparition ne sont **pas** de
  l'art : ils sont posés côté Godot par le `track-designer`.

## 6. Budgets

| Asset | Triangles | Matériaux |
|---|---|---|
| Camion (carrosserie) | < 6 000 | 1–2 |
| Roue | < 400 | 1 |
| Piste (visuel) | < 60 000 | ≤ 4 |
| Piste (collision) | < 8 000 | — |
| Prop | < 800 | 1 |
| Catalogue §4 ter : `Body` d'un véhicule | < 60 000 | partagés |
| Catalogue : roue (jumelée comprise) | < 10 000 | 4–5 |
| Catalogue : véhicule complet (tracteur, roues, remorque, chargement) | < 160 000 (mesuré : 25 000 chariot, 65 000 à 71 000 porteurs, 89 000 à 95 000 semi-remorques) | partagés |
| Catalogue : objet d'arme ou projectile | < 30 000 (mesuré : 200 à 10 600) | partagés |
| Catalogue : effet enveloppant (coque du bouclier) | < 30 000 (mesuré : 800) | 2 |

Le catalogue (§4 ter) est en **haute définition** à la demande de
l'utilisateur (2026-10-02) : densité des modèles de l'équipe (~64 000
triangles par camion) ou plus. Le niveau de détail se règle en un seul
endroit, en tête de `lib/kit.py` (`SEG_MULT`, `SPHERE_MULT`, `BEVEL_SEG`) :
les ramener à 1 / 1 / 1 divise grossièrement le compte par 4 à 6. ⚠️ En
écran partagé à 4 avec 4 semi-remorques, c'est ~1,5 M de triangles par vue :
à confronter au spike V3 avant de les mettre en course.

Constantes en tête de `tools/blender/lib/mesh.py`. `build_all.py` échoue si un
budget est dépassé. Les budgets de piste sont **provisoires** : le spike V3
(écran partagé à 4 sur GPU intégré) les confirme ou les réduit. En écran
partagé à 4, chaque triangle est rendu quatre fois.

## 7. Couleurs plutôt que textures

En phase 5 : couleurs vertex + un `StandardMaterial3D` avec
`vertex_color_use_as_albedo = true`. Zéro UV à gérer, zéro poids, variantes de
couleur triviales (couleur de camion par joueur). Les textures ne reviennent en
discussion qu'en phase 7, si le besoin est réel.

## 8. Itération rapide

Pendant le travail sur un asset, ne lance pas `make assets` complet :

```bash
blender -b -P tools/blender/build_truck.py -- --variant=default \
  --out=game/assets/generated/truck_default.glb
godot --headless --path game --import
```

Si la boucle dépasse 30 s, simplifie le modèle pendant l'itération.
