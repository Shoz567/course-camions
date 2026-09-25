# ENVIRONMENT.md — Outils, versions, commandes

Ce fichier décrit la machine sur laquelle le projet est développé. Il existe
pour deux raisons : les commandes du `Makefile` ne sont pas directement
utilisables sous Windows, et **un critère de perf n'a aucun sens sans la machine
sur laquelle il a été mesuré**.

À remplir lors de la tâche 0.1, puis tenu à jour.

---

## 1. Machine de référence

C'est la machine qui fait foi pour tous les critères de performance du projet.

| Élément | Valeur |
|---|---|
| OS | Windows 11 Home (10.0.26200) |
| CPU | Intel Core i7-1255U — 10 cœurs / 12 threads |
| RAM | 15,7 Go |
| GPU | Intel Iris Xe Graphics (intégré) |

Si le projet change de machine principale, **re-mesure la baseline** avant de
conclure à une régression. Une perte de 30 % sur `physics_frame_ms` entre deux
machines n'est pas un bug.

> ⚠️ **Conséquence à connaître dès maintenant.** C'est un CPU d'ultraportable
> (i7-1255U, architecture hybride avec 2 cœurs performants et 8 cœurs efficients)
> et un GPU intégré. Deux implications pour ce projet :
>
> - Le budget « temps physique < 4 ms à 4 persos » est **exigeant** sur cette
>   machine. Le spike S4 doit le mesurer tôt : s'il s'avère hors d'atteinte, il
>   vaut mieux le savoir en phase 0.5 et ajuster la cible que le découvrir en
>   phase 4.
> - Les CPU mobiles réduisent leur fréquence sous charge prolongée. Une mesure de
>   perf prise sur batterie ou après 20 minutes de tests **n'est pas comparable**
>   à une mesure prise à froid sur secteur. Mesure toujours dans les mêmes
>   conditions, et note-les.

## 2. Versions figées

Installées et vérifiées le 2026-09-18 :

| Outil | Version attendue | Version réelle | Commande de vérification |
|---|---|---|---|
| Godot | 4.6.x stable | ✅ **4.6.3.stable.official** (`7d41c59c4`) | `godot --version` |
| Blender | 4.x ou 5.x LTS | ✅ **5.2.1 LTS** | `blender --version` |
| Python | 3.13 | ✅ 3.13 (`C:\Program Files\Python313`) | `python --version` |
| Git | présent | ✅ `C:\Program Files\Git` | `git --version` |
| make | GNU Make | ✅ **4.4.1** (ezwinports, natif Windows) | `make --version` |

### Note sur Blender 5.2 au lieu de 4.x

Le pack ciblait Blender 4.x ; c'est la 5.2.1 LTS qui a été installée. La
compatibilité du pipeline a été **vérifiée par script**, pas supposée :

```
BLENDER_VERSION 5.2.1 LTS
MISSING aucun            ← les 11 paramètres glTF de ART_PIPELINE.md §3 existent
OP wm.read_factory_settings / object.transform_apply / parent_set / shade_smooth  → OK
MOD REMESH / DECIMATE / WEIGHTED_NORMAL / BOOLEAN                                 → OK
```

Tout ce dont `ART_PIPELINE.md` a besoin est présent. Le spike **S6** reste
néanmoins à faire : il vérifie que l'export *produit* le bon résultat (échelle,
orientation, noms d'os), ce qui est une question différente de « l'API existe ».

### Note sur `make`

C'est le port **ezwinports** (GNU Make 4.4.1), pas GnuWin32 — lequel en est
resté à la version 3.81 de 2006. ezwinports est un binaire natif Windows, sans
dépendance MSYS ni Cygwin.

La chaîne complète a été testée, pas seulement l'installation : un `Makefile`
avec dépendances entre cibles appelant `godot --headless` et `blender` s'exécute
correctement et rend un code de sortie 0. C'est ce qui importait, parce que le
risque réel de `make` sous Windows n'est pas le binaire mais **le shell qu'il
utilise pour ses recettes** — nos recettes étant des appels directs à des `.exe`,
sans syntaxe POSIX, le problème ne se pose pas.

Garde cette contrainte en tête en écrivant le `Makefile` (tâche 0.5) : **pas de
`&&`, pas de `$(shell …)`, pas de boucle shell** dans les recettes. Une commande
par ligne, et les enchaînements exprimés comme des dépendances entre cibles.
C'est de toute façon la bonne façon d'écrire un `Makefile`.

Une version mineure de Godot peut changer le comportement du solveur. Si tu la
changes, relance `make test-full` **avant** de toucher à autre chose, et note le
résultat : c'est la seule façon de distinguer « le moteur a changé » de « j'ai
cassé quelque chose ».

## 3. État de la machine

Relevé initial (2026-09-18), **avant** installation :

```
git     -> C:\Program Files\Git\cmd\git.exe        ✅
python  -> C:\Program Files\Python313\python.exe   ✅
godot   -> ABSENT                                  ❌
blender -> ABSENT                                  ❌
make    -> ABSENT                                  ❌
```

État actuel, après la mise en place de la §4 :

```
git ✅   python ✅   godot ✅ 4.6.3   blender ✅ 5.2.1   make ✅ 4.4.1
```

Toutes les commandes de `CLAUDE.md` §4 sont exécutables.

## 4. Mise en place sous Windows — ce qui a été fait

### 4.1 Installation et mise au PATH

Godot et Blender ont été installés via winget :

```powershell
winget install --id GodotEngine.GodotEngine --version 4.6.3 --exact
winget install --id BlenderFoundation.Blender --exact
```

**Point important : winget n'a pas pu créer les alias de commande**, faute de
droits administrateur (limitation connue de winget — il ne peut pas créer les
liens symboliques sans élévation). Les binaires étaient donc installés mais
inaccessibles par leur nom.

Contournement retenu, sans admin : un dossier de shims dans le PATH utilisateur.

| Fichier | Cible |
|---|---|
| `%LOCALAPPDATA%\bin\godot.cmd` | `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_…\Godot_v4.6.3-stable_win64_console.exe` |
| `%LOCALAPPDATA%\bin\blender.cmd` | `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe` |

`%LOCALAPPDATA%\bin` a été ajouté au PATH **utilisateur**.

> ⚠️ **Le shim Godot pointe volontairement vers `…_console.exe`, pas vers
> l'exécutable normal.** Sous Windows, le binaire Godot standard est une
> application GUI : elle n'écrit rien dans le terminal qui l'a lancée. Avec lui,
> `godot --version` ne renvoie rien, et surtout **tous les tests headless
> paraissent muets** — sortie vide, code de retour inexploitable. C'est un piège
> classique et il se paierait exactement au moment où on met en place
> `cli_runner.gd`.

Vérification, dans un **nouveau** terminal (le PATH n'est pas rafraîchi dans les
terminaux déjà ouverts) :

```powershell
godot --version     # 4.6.3.stable.official.7d41c59c4
blender --version   # Blender 5.2.1 LTS
```

### 4.2 `make`

Installé via winget :

```powershell
winget install --id ezwinports.make --exact
```

Contrairement à Godot, l'alias de commande a été créé sans difficulté : `make`
répond directement, aucun shim nécessaire.

À noter : Git for Windows **n'inclut pas** `make`. Le fait que Git Bash soit
disponible ne dispense pas de cette installation.

Le `Makefile` (tâche 0.5) reste le seul endroit où les commandes du projet sont
définies. C'est sa vraie fonction ici : non pas le rebuild incrémental — nos
cibles sont des one-liners sans graphe de dépendances réel — mais garantir qu'il
existe **une seule définition** de « lancer les tests ». Avec plusieurs agents
qui lancent des commandes, c'est ce qui évite qu'un agent teste sans
`--headless` pendant qu'un autre oublie `--runs=5`.

### 4.3 Équivalents bruts des cibles du Makefile

`make` étant installé, ces commandes ne servent qu'au dépannage — quand une
cible se comporte bizarrement et qu'on veut isoler la commande sous-jacente :

| Cible | Commande équivalente |
|---|---|
| `make assets` | `blender -b -P tools/blender/build_all.py` |
| `make import` | `godot --headless --path game --import` |
| `make test` | `godot --headless --path game -s res://tests/cli_runner.gd` |
| `make test-full` | `godot --headless --path game -s res://tests/cli_runner.gd -- --runs=5` |
| `make run` | `godot --path game` |

Note pour les chemins Windows : les scripts Blender doivent utiliser `pathlib`
et jamais de séparateur `/` ou `\` écrit en dur. C'est déjà la règle dans
`ART_PIPELINE.md` §2, elle compte double ici.

## 5. Baseline de performance

`game/tests/baseline.json` est **versionné** (exception explicite à la règle « pas
de binaires » de `CLAUDE.md` §8) et contient les mesures de référence :

```json
{
  "machine": "poste principal — voir ENVIRONMENT.md §1",
  "godot_version": "à remplir",
  "measured_at": "à remplir",
  "physics_frame_ms_1_char": null,
  "physics_frame_ms_4_chars": null,
  "head_y_rest_m": null,
  "com_y_rest_m": null,
  "impulse_stagger_ns": null,
  "impulse_knockdown_ns": null,
  "character_tris": null,
  "arena_tris": null,
  "snapshot_bytes_per_char": null
}
```

Il est créé **vide dès la phase 0** et rempli au fur et à mesure. Le créer tard
est une erreur classique : sans point de départ, une régression de perf apparue
en phase 3 devient impossible à localiser en phase 6.

Règle de lecture : toute dérive de plus de **10 %** sur une valeur de baseline
est signalée en fin de phase, même si tous les tests passent. Un test qui passe
avec 20 % de perf en moins est un test qui passera de justesse au prochain
changement.

## 6. Environnement git

### 6.1 Après un clone — une commande obligatoire

```bash
git config core.hooksPath .githooks
```

Les hooks vivent dans `.githooks/` (versionné) et **non** dans `.git/hooks/`,
qui ne se versionne pas et disparaîtrait au premier clone. Git ne lit pas
`.githooks/` tout seul : sans cette commande, les garde-fous sont silencieusement
inactifs — c'est le pire des deux mondes, on croit être protégé et on ne l'est
pas.

### 6.2 Fins de ligne

`.gitattributes` impose `* text=auto eol=lf` : **LF partout**, dans le dépôt
comme dans la copie de travail. Godot, Python et make lisent tous le LF sans
difficulté sous Windows.

Sans cela, git convertit en CRLF au checkout, ce qui produit un avertissement à
chaque commit et ferait apparaître tout le dépôt comme modifié pour un
collaborateur sous Linux.

La configuration locale accompagne le fichier :

```bash
git config core.autocrlf false
git config core.safecrlf false
```

### 6.3 Ce que les hooks vérifient

**`pre-commit`**, dans l'ordre du moins cher au plus cher :

1. **Aucun artefact régénérable** (`.glb`, `.gltf`, `.blend`, `.pck`, `.exe`).
   Ils se refont avec `make assets` — cf. `CLAUDE.md` §8.
2. **Aucun fichier de plus de 1 Mo.** Sur ce dépôt, un gros fichier est presque
   toujours un asset qui aurait dû être régénéré.
3. **`make test` passe.** C'est la raison d'être de la règle « `make test` sous
   60 s » : au-delà, le hook devient insupportable et quelqu'un finit par le
   désactiver. Si la suite déborde, **découpe la suite**, ne retire pas le hook.

**`commit-msg`** vérifie la convention de `CLAUDE.md` §9 : préfixe de zone,
impératif, sujet de 72 caractères maximum.

```
ragdoll: ajoute le couple correcteur du bassin
phase-1: verrouille l'equilibre par un test headless
```

Contournement : `git commit --no-verify`. À réserver aux cas où tu peux
expliquer pourquoi — un test rouge qu'on contourne est exactement ce que
`CLAUDE.md` §10 cherche à empêcher.

### 6.4 Branches

`main` est la branche de travail. Le projet est mono-développeur : les branches
de fonctionnalité n'apportent rien tant que c'est le cas.

La seule exception qui vaudra le coup : **une branche par session de tuning du
ragdoll en phase 1**. Pouvoir revenir en une commande à « l'état où ça tenait
debout » vaut plus que n'importe quel test pendant ces semaines-là.

### 6.5 Remote

| | |
|---|---|
| URL | `https://github.com/Shoz567/ragdoll-brawler` |
| Visibilité | **privé** |
| Branche par défaut | `main` |
| Authentification | `gh` CLI (GitHub CLI 2.101.0), protocole HTTPS |

`gh` n'est pas dans le PATH des terminaux ouverts avant son installation. Chemin
complet si besoin : `C:\Program Files\GitHub CLI\gh.exe`.

Ce qui **ne** doit **pas** y arriver, et que le hook `pre-commit` empêche :
aucun `.glb`, `.blend`, `.pck` ni `.exe`. Vérification après chaque push :

```bash
git ls-tree -r --name-only origin/main | grep -Ei '\.(glb|blend|pck|exe)$'
```

Cette commande doit ne rien renvoyer. Les assets se régénèrent avec
`make assets` — c'est la règle de `CLAUDE.md` §8, et elle vaut aussi pour le
distant.
