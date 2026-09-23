# Ragdoll Brawler — pack de démarrage pour Claude Code

Plan complet pour développer un jeu de combat physique multijoueur 3D avec Godot,
dans l'esprit de *Gang Beasts*, en pilotant Claude Code et des sous-agents
spécialisés.

## Mise en place

```bash
git init && git add -A && git commit -m "init: plan et agents"
claude
```

Dans Claude Code :

```
> Lis CLAUDE.md, PLAN.md et docs/SPIKE.md, puis attaque la phase 0.
```

Vérifie que les agents sont détectés :

```
> /agents
```

Tu dois voir : `ragdoll-engineer`, `gameplay-engineer`, `blender-modeler`,
`level-designer`, `netcode-engineer`, `godot-qa`.

> ✅ **Outils installés et vérifiés** (2026-09-18) : Godot **4.6.3**, Blender
> **5.2.1 LTS**, GNU Make **4.4.1**. Les trois répondent en ligne de commande, et
> la chaîne `make` → `godot --headless` a été testée de bout en bout. Détails et
> pièges Windows dans `docs/ENVIRONMENT.md`.

## Contenu du pack

| Fichier | Rôle |
|---|---|
| `CLAUDE.md` | Règles permanentes : stack, conventions, garde-fous. Lu automatiquement à chaque session. |
| `PLAN.md` | Roadmap en 9 phases avec critères de sortie mesurables. Source de vérité du « quoi ». |
| `.claude/agents/*.md` | 6 sous-agents spécialisés, avec leur périmètre et leurs règles. |
| `docs/ENVIRONMENT.md` | Outils, versions figées, équivalents Windows, machine de référence. |
| `docs/SPIKE.md` | **Phase 0.5** : les 6 hypothèses techniques à valider avant de construire. |
| `docs/RIG_SPEC.md` | Contrat squelette : noms d'os, masses, limites, géométrie vérifiée. |
| `docs/METRICS.md` | Métriques de gameplay — mesurées par un test, jamais décrétées. |
| `docs/ART_PIPELINE.md` | Génération de tout l'art 3D par scripts Blender headless. |
| `docs/INPUT_SPEC.md` | Input abstrait, manettes, multijoueur local, format binaire. |
| `docs/NETCODE.md` | Architecture online host-autoritaire et budget de bande passante. |

## Comment travailler avec ça

**Une phase à la fois.** Ouvre une session par phase, ou au moins par gros bloc
de tâches. `PLAN.md` sert de mémoire entre les sessions : fais-le mettre à jour
(`[ ]` → `[x]`) à mesure.

**Délègue explicitement.** Claude Code choisira parfois le bon agent seul, mais
c'est plus fiable de le nommer :

```
> Utilise l'agent ragdoll-engineer pour la tâche 1.6 du PLAN.
> Puis fais valider par godot-qa avant de passer à 1.7.
```

**Exige des chiffres.** Sur un jeu physique, « ça marche » ne veut rien dire.
Chaque agent a pour consigne de rendre une mesure. Si tu reçois une conclusion
sans nombre, redemande-la.

## Commence par la phase 0.5, pas par la phase 1

C'est la particularité de ce pack. La phase 1 (le ragdoll actif) représente 60 %
de la difficulté du projet, et elle repose sur six hypothèses d'API Godot et Jolt
que personne n'a vérifiées : la façon exacte d'appliquer un couple à un
`PhysicalBone3D`, ce que Jolt honore vraiment sur un `Generic6DOFJoint3D`,
comment fournir une pose cible sans conflit avec le simulateur…

Si l'une est fausse, tu ne le découvres pas en une heure. Tu le découvres au bout
de plusieurs jours de tuning inexplicable, en croyant que le problème vient de
tes gains.

`docs/SPIKE.md` transforme ça en **1 à 2 jours de code jetable** qui rendent six
réponses et corrigent les documents. C'est le meilleur rapport temps/risque
disponible sur ce projet.

## Les quatre pièges de ce projet

1. **La phase 1 déborde toujours.** Le ragdoll actif est 60 % de la difficulté
   totale. Ne la bâcle pas pour aller « voir le jeu » : tout le reste repose
   dessus. Compte des semaines, pas des jours.
2. **La règle d'input abstrait** (`CLAUDE.md` §7). Elle semble inutile en phase 2,
   et c'est elle qui rend la phase 6 possible sans tout réécrire. Ne la laisse
   jamais se faire contourner.
3. **Ne commence pas par la 3D.** L'art arrive en phase 5, une fois que des
   capsules sont déjà amusantes à faire jouer. Un joli personnage sur une
   mécanique bancale reste un jeu bancal.
4. **Un seuil de test ne s'invente pas.** « La tête doit être à plus de 1,3 m »
   est un chiffre sans origine qui cassera au premier changement de proportions.
   Les critères de ce pack sont des **ratios mesurés au tick 0** et des
   **impulsions en N·s** — pas des valeurs absolues tirées de l'intuition
   (`CLAUDE.md` §10).

## Deux points de décision

**Après la phase 0.5.** Si un spike révèle qu'une hypothèse majeure est fausse,
corrige les documents *avant* d'enchaîner. Une phase 0.5 qui n'a corrigé aucun
document est suspecte.

**Après la phase 4.** Une fois le jeu jouable à 4 en local, fais-y jouer de
vraies personnes avant d'engager la phase 6. Le réseau représente 2 à 4 semaines
de travail et ne rendra pas amusant un jeu qui ne l'est pas déjà sur un canapé.

C'est aussi pourquoi un lot minimal de juice (hitstop, screenshake, trois sons)
est planifié en phase 3 et non en phase 7 : sans retour d'impact, ce playtest
juge le jeu sur sa version la moins agréable, et la décision est faussée.

---

Le plan cible Godot 4.6, avec Jolt Physics activé dans les réglages du projet
(intégré au moteur depuis la 4.4, mais pas activé par défaut). Les versions
réellement installées se figent dans `docs/ENVIRONMENT.md` à la tâche 0.1.
