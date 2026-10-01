class_name TruckTestUtil
extends RefCounted

## Mesures communes aux tests du camion.


## (tangage, roulis) en degres. Tangage > 0 : nez en l'air. Roulis > 0 : cote
## droit leve.
static func pitch_roll_deg(t: Node3D) -> Vector2:
	var b := t.global_transform.basis
	var pitch := rad_to_deg(asin(clampf((-b.z).normalized().y, -1.0, 1.0)))
	var roll := rad_to_deg(asin(clampf(b.x.normalized().y, -1.0, 1.0)))
	return Vector2(pitch, roll)


## Angle d'inclinaison total (deg) entre le haut du camion et la verticale.
static func tilt_deg(t: Node3D) -> float:
	return rad_to_deg(t.global_transform.basis.y.normalized().angle_to(Vector3.UP))


## Angle de derive (deg) entre le cap et la vitesse horizontale ; 0 a l'arret.
static func sideslip_deg(t: RigidBody3D) -> float:
	var v := Vector3(t.linear_velocity.x, 0.0, t.linear_velocity.z)
	if v.length() < 1.0:
		return 0.0
	var fwd := -t.global_transform.basis.z
	fwd.y = 0.0
	return rad_to_deg(fwd.normalized().angle_to(v.normalized()))


static func spawn_truck(parent: Node, position: Vector3, rotation_deg: Vector3 = Vector3.ZERO) -> Truck:
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.position = position
	t.rotation_degrees = rotation_deg
	parent.add_child(t)
	return t
