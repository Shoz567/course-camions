# Crazy Wheels

Jeu de course de camions arcade en 3D, développé avec Godot 4.7 et Claude
Code : conduite permissive et spectaculaire, écran partagé jusqu'à 6 joueurs,
puis online.

> ### ⚠️ 2026-10-01 : tout est sur `main`, repartez de `main`
>
> La branche `phase-4/menu-et-ecran-partage` a été fusionnée dans `main` (PR #9),
> avec les PR #7 (conduite) et #8 (menu). `main` contient maintenant le jeu
> complet : deux circuits, course à 3 tours, écran partagé de 1 à 6 joueurs,
> menu, sons.
>
> La fusion s'est faite en *squash* : un seul commit sur `main`. **Ne continuez
> pas sur `phase-4/menu-et-ecran-partage`** (ni sur les anciennes branches
> `phase-0.5`, `phase-1`, `phase-2`) : une PR depuis ces branches ramènerait
> toute l'ancienne histoire en double. Elles restent sur GitHub pour consulter
> l'historique détaillé, en lecture seule.
>
> Pour reprendre :
>
> ```bash
> git switch main
> git pull
> git switch -c <zone>/<sujet>        # par exemple piste/troisieme-circuit
> ```
>
> Du travail **pas encore poussé** sur une ancienne branche ? Récupérez-le sur
> une nouvelle branche partie de `main` :
>
> ```bash
> git switch main
> git pull
> git switch -c <zone>/<sujet>
> git cherry-pick <sha1> <sha2> ...    # vos commits, du plus ancien au plus récent
> ```

## Démarrer

```bash
git clone https://github.com/Shoz567/course-camions.git
cd course-camions
git config core.hooksPath .githooks     # obligatoire : active les vérifications
make test                                # doit afficher 0 échec
make run                                 # lance le jeu (menu principal)
```

Outils requis : **Godot 4.7.2**, **Blender 5.2 LTS**, **GNU Make**. Installation
sous Windows et pièges connus : `docs/ENVIRONMENT.md`.

Dans Claude Code :

```
> Lis CLAUDE.md et PLAN.md, puis propose la prochaine tâche.
```

## Où en est le projet

| Phase | État |
|---|---|
| 0 — Fondations | ✅ socle de tests, Makefile, hooks git, pipeline Blender, Godot 4.7.2 |
| 0.5 — Spikes du camion | ✅ V1, V2, V4 ; V3 (rendu à 4 vues sur la machine de référence) à mesurer |
| 1 — Un camion qui se conduit bien | ✅ |
| 2 — Piste et tour solo | ✅ |
| 3 — Course complète et juice | 🟡 en partie : 2e circuit, sons et musique ; voir `PLAN.md` |
| **4 — Écran partagé local** | **🟡 en cours** : 1 à 6 joueurs, menu ; « appuyez sur A pour rejoindre » et rebranchement à chaud à faire |
| 5 à 7 | à venir — voir `PLAN.md` |

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
- **Une pull request par branche**, fusionnée en *squash*. Une branche
  fusionnée est terminée : on n'y ajoute plus rien, on repart de `main`.
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
