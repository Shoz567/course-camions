# Course de camions arcade

*Titre provisoire.* Jeu de course de camions arcade en 3D, développé avec
Godot 4.7 et Claude Code : conduite permissive et spectaculaire, écran partagé
jusqu'à 6 joueurs, puis online.

## Démarrer

```bash
git clone https://github.com/Shoz567/ragdoll-brawler.git
cd ragdoll-brawler
git config core.hooksPath .githooks     # obligatoire : active les vérifications
make test                                # doit afficher 0 échec
```

Outils requis : **Godot 4.7.2**, **Blender 5.2 LTS**, **GNU Make**. Installation
sous Windows et pièges connus : `docs/ENVIRONMENT.md`.

Dans Claude Code :

```
> Lis CLAUDE.md, PLAN.md et docs/SPIKE.md, puis attaque la phase 0.5.
```

## Où en est le projet

| Phase | État |
|---|---|
| 0 — Fondations | ✅ socle de tests, Makefile, hooks git, pipeline Blender, Godot 4.7.2 |
| **0.5 — Spikes du camion** | **⏭️ prochaine étape** |
| 1 à 7 | à venir — voir `PLAN.md` |

## Contenu

| Fichier | Rôle |
|---|---|
| `CLAUDE.md` | Règles permanentes : stack, conventions, garde-fous. Lu à chaque session. |
| `PLAN.md` | Roadmap en 8 phases avec critères de sortie mesurables. |
| `.claude/agents/*.md` | 6 sous-agents spécialisés. |
| `docs/ENVIRONMENT.md` | Outils, versions, machine de référence, fonctionnement git. |
| `docs/SPIKE.md` | Acquis techniques mesurés + hypothèses à valider en phase 0.5. |
| `docs/VEHICLE_SPEC.md` | Contrat du camion : dimensions, masse, roues, noms. |
| `docs/METRICS.md` | Métriques de conduite, mesurées par un test, jamais décrétées. |
| `docs/INPUT_SPEC.md` | Input abstrait, manettes, écran partagé. |
| `docs/ART_PIPELINE.md` | Génération de tout l'art 3D par scripts Blender headless. |
| `docs/NETCODE.md` | Online host-autoritaire, prédiction du camion local. |

## Travailler en équipe

- **Une branche par tâche**, jamais de travail sur `main` : le hook `pre-push`
  le refuse. Nommage `<zone>/<sujet>`, par exemple `phase-1/suspension`.
- **Une pull request par branche**, fusionnée en *squash*.
- **Deux personnes ne modifient pas la même scène** `.tscn` en même temps.

Détail : `docs/ENVIRONMENT.md` §6.

## Les trois pièges de ce projet

1. **La sensation de conduite régresse en silence.** Un réglage qui améliore les
   virages peut ruiner les sauts. Chaque comportement est verrouillé par un test
   headless chiffré *avant* d'être réglé (`CLAUDE.md` §10).
2. **La règle d'input abstrait** (`CLAUDE.md` §7). Un camion ne lit jamais
   `Input` directement. Elle semble inutile en phase 1, et c'est elle qui rend
   possibles à la fois l'écran partagé, les tests et l'online.
3. **Ne commencez pas par l'art.** Les modèles arrivent en phase 5, une fois
   que des boîtes sont déjà amusantes à conduire.

## Historique

Ce dépôt a d'abord porté un jeu de combat en ragdoll, abandonné le 2026-09-25.
Tout ce travail est conservé par le tag **`archive/ragdoll-brawler`** :

```bash
git switch -c ragdoll archive/ragdoll-brawler
```

L'infrastructure générique en a été conservée : socle de tests, runner,
`DebugDraw`, Makefile, hooks, pipeline d'export Blender, et les acquis
techniques de `docs/SPIKE.md`.
