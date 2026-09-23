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

.PHONY: help assets import test test-full run clean-spike

help:
	@echo "Cibles disponibles :"
	@echo "  make assets     - regenere tous les assets 3D (Blender headless)"
	@echo "  make import     - importe les assets dans Godot"
	@echo "  make test       - suite rapide : 1 run par test (< 60 s)"
	@echo "  make test-full  - suite complete : 5 runs par test physique"
	@echo "  make run        - lance le jeu"
	@echo "  make clean-spike- supprime spike/ (fin de phase 0.5)"

assets:
	$(BLENDER) -b -P tools/blender/build_all.py

import:
	$(GODOT) --headless --path $(PROJECT) --import

# Suite rapide, lancee a chaque commit. Doit rester sous 60 s.
test:
	$(GODOT) --headless --path $(PROJECT) -s res://tests/cli_runner.gd

# Suite complete, pour valider un critere de sortie de phase.
# 5 runs : la physique n'est pas deterministe (cf. CLAUDE.md §10).
test-full:
	$(GODOT) --headless --path $(PROJECT) -s res://tests/cli_runner.gd -- --runs=5

run:
	$(GODOT) --path $(PROJECT)

clean-spike:
	rm -rf spike
