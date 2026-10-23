# Ragdoll Brawler — raccourcis de build et de test.
#
# Ce fichier est la SEULE definition des commandes du projet (cf. CLAUDE.md §4).
# C'est ce qui garantit qu'un agent ne teste pas sans --headless pendant qu'un
# autre oublie --runs=5.
#
# Contrainte Windows (cf. docs/ENVIRONMENT.md §4.2) : pas de &&, pas de
# $(shell ...), pas de boucle shell dans les recettes. Une commande par ligne,
# les enchainements exprimes comme des dependances entre cibles.

GODOT   := godot
BLENDER := blender
PROJECT := game

.PHONY: help assets import test test-full test-selftest baseline run solo sandbox trailer clean-spike vehicules export export-windows export-linux export-macos share

help:
	@echo "Cibles disponibles :"
	@echo "  make assets     - regenere tous les assets 3D (Blender headless)"
	@echo "  make vehicules  - catalogue des remorques + versions realistes (Realiste/)"
	@echo "  make import     - importe les assets dans Godot"
	@echo "  make test       - suite rapide : 1 run par test (< 60 s)"
	@echo "  make test-full  - suite complete : 5 runs par test physique"
	@echo "  make test-selftest - verifie le socle de test lui-meme"
	@echo "  make baseline   - mesure les metriques de conduite et les ECRIT dans baseline.json"
	@echo "  make run        - lance le jeu : menu principal, puis course de 1 a 4 joueurs"
	@echo "  make export     - exporte le jeu Windows et Linux dans builds/ (modeles d'export requis)"
	@echo "  make share      - jeu a partager : builds/CrazyWheels-Windows.zip et CrazyWheels-Mac.zip"
	@echo "  make solo       - course a 1 joueur, plein ecran, sans passer par le menu"
	@echo "  make sandbox    - lance le bac a sable (arene, tremplin, camions gares)"
	@echo "  make trailer    - enregistre le trailer de 30 s (builds/trailer.avi, 1080p 60 i/s, son)"
	@echo "  make clean-spike- supprime spike/ (fin de phase 0.5)"

assets:
	$(BLENDER) -b -P tools/blender/build_all.py

# Catalogue de vehicules (remorques generees) puis versions realistes des
# tetes et des remorques (Assets_Visuels/.../Realiste/, chargees par le jeu).
# Les modeles de l'equipe restent la source : jamais modifies par le second.
vehicules:
	$(BLENDER) -b -P tools/blender/catalogue_tete_commune.py
	$(BLENDER) -b -P tools/blender/realisme_vehicules.py

import:
	$(GODOT) --headless --path $(PROJECT) --import

# Export (tache 7.7) : jeu autonome dans builds/<plateforme>/, modeles de
# l'equipe copies a cote (TruckVisual.asset_base) ; la copie d'abord : elle cree
# le dossier, que l'export de Godot exige. Modeles d'export Godot
# 4.7.2 requis (docs/ENVIRONMENT.md).
export: export-windows export-linux

# Jeu a partager (2026-10-23) : Windows et Mac, chacun en .zip pret a envoyer
# (builds/CrazyWheels-Windows.zip, builds/CrazyWheels-Mac.zip ; tools/package.js).
share: export-windows export-macos
	node tools/package.js

export-macos: import
	$(GODOT) --headless -s tools/export_assets.gd -- builds/macos/assets
	$(GODOT) --headless --path $(PROJECT) --export-release "macOS" ../builds/macos/CrazyWheels.zip

export-windows: import
	$(GODOT) --headless -s tools/export_assets.gd -- builds/windows
	$(GODOT) --headless --path $(PROJECT) --export-release "Windows Desktop" ../builds/windows/CrazyWheels.exe

export-linux: import
	$(GODOT) --headless -s tools/export_assets.gd -- builds/linux
	$(GODOT) --headless --path $(PROJECT) --export-release "Linux" ../builds/linux/CrazyWheels.x86_64

# Suite rapide, lancee a chaque commit. Doit rester sous 60 s.
test:
	$(GODOT) --headless --path $(PROJECT) -s res://tests/cli_runner.gd

# Suite complete, pour valider un critere de sortie de phase.
# 5 runs : la physique n'est pas deterministe (cf. CLAUDE.md §10).
test-full:
	$(GODOT) --headless --path $(PROJECT) -s res://tests/cli_runner.gd -- --runs=5

# Verifie le socle de test (PhysicsTest + cli_runner) : chaque scene de
# tests/selftest/ declare son verdict attendu dans son nom, et c'est l'ECART
# qui fait echouer. A lancer apres toute modification du socle.
test-selftest:
	$(GODOT) --headless --path $(PROJECT) -s res://tests/cli_runner.gd -- --dir=res://tests/selftest --selftest --max-iterations=600

# Mesure les metriques de conduite (docs/METRICS.md) et les ecrit dans
# tests/baseline.json. Le seul moyen de changer la reference : make test les
# verrouille ensuite a +/- 10 %. A lancer apres un changement de reglage
# VOULU, et a committer avec lui.
baseline:
	$(GODOT) --headless --fixed-fps 60 --path $(PROJECT) res://tests/scenes/handling_test.tscn -- --write-baseline

run:
	$(GODOT) --path $(PROJECT)

solo:
	$(GODOT) --path $(PROJECT) res://dev/track_drive.tscn

sandbox:
	$(GODOT) --path $(PROJECT) res://dev/drive_sandbox.tscn

# Trailer de 30 s (dev/trailer.gd) : Movie Maker de Godot, image par image
# (le rendu peut etre plus lent que le temps reel), MJPEG + son.
trailer:
	$(GODOT) --path $(PROJECT) --write-movie ../builds/trailer.avi --fixed-fps 60 res://dev/trailer.tscn -- --offscreen

clean-spike:
	rm -rf spike
