class_name GameClock

## Horloge de jeu, en ticks physiques (CLAUDE.md §7 : toute duree de logique
## se compte en ticks) : Engine.get_physics_frames(), moins les ticks passes
## en pause (menu pause hors ligne, 2026-10-22). Le compteur du moteur, lui,
## avance aussi en pause : compte a rebours, chrono, recharges et delais
## l'utilisaient, et une pause de 10 s les aurait tous avances de 10 s (le
## depart tombait des la reprise). Le code de jeu lit now() ; PauseMenu
## compte les ticks figes (paused_ticks), il tourne pendant la pause.

static var paused_ticks: int = 0


static func now() -> int:
	return Engine.get_physics_frames() - paused_ticks
