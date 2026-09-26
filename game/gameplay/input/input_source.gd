class_name InputSource
extends Node

## Source d'InputFrame (docs/INPUT_SPEC.md §1) : clavier, manette, script,
## reseau. Le proprietaire du camion appelle poll(tick) a chaque tick physique
## et transmet le resultat a Truck.set_input().
##
## poll() n'alloue pas : il remplit et renvoie toujours la meme frame.

var frame: InputFrame = InputFrame.new()


## Frame du tick `tick`. A surcharger ; la source de base reste au neutre.
func poll(tick: int) -> InputFrame:
	frame.tick = tick
	return frame
