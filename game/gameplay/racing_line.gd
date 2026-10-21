class_name RacingLine
extends RefCounted

## Ligne de course des bots (2026-10-20, Â« meme en dur ils sont faciles a
## battre, trajectoires pas optimales Â») : calculee sur la piste, pas
## dessinee a la main. Ecart lateral par point (m, > 0 a droite), dans la
## chaussee moins MARGIN_M de chaque mur :
##   - virages : trajectoire a courbure minimale (somme des carres des
##     differences secondes) : grand arc, exterieur, corde, exterieur ; un long
##     virage par le grand rayon. Gauss-Seidel projete (chaque point au minimum
##     local (4 (P-1 + P+1) - (P-2 + P+2)) / 6, ramene dans ses bornes), du
##     grossier au fin (LEVELS) : les grandes ondulations convergent vite en
##     grossier, le fin precise ;
##   - pads de boost : la ligne passe dessus ; sauts, flaques et barils : elle
##     passe a cote, du cote faisable le plus proche ; seulement pour un petit detour
##     (DETOUR_M) ;
##   - courbure de la trajectoire (cercle par trois points, a plat) et profil
##     de vitesse (speed_profile) : vitesse de virage sqrt(a / k), plafonnee,
##     puis passe arriere de freinage (v2 = v1^2 + 2 a d) : la vitesse visee en
##     chaque point permet toujours de freiner a temps.
## Calculee une fois par piste (cache), deterministe. (Essai du 2026-10-20 :
## la ligne la plus courte sur les portions a fond, raccordee aux virages,
## cassait la trajectoire en angles et coutait 6 a 13 s au tour : abandonnee.)

## Marge laterale de chaque mur (m) : demi-largeur d'un ensemble, remorque qui
## deborde en virage, murs inclines.
const MARGIN_M := 5.5
## Niveaux de calcul de la courbure minimale : [pas en echantillons, passes].
const LEVELS := [[16, 500], [8, 300], [4, 150]]
## Reprise apres pose des contournements.
const REFINE := [[8, 200], [4, 120]]
## Pads : la ligne a moins de PAD_INSET_M du bord du pad. Sauts, flaques :
## a plus de AVOID_CLEAR_M du bord.
const PAD_INSET_M := 1.5
const AVOID_CLEAR_M := 3.0
## Plus grand ecart (m) a la ligne libre pour viser un pad ou eviter un
## obstacle.
const DETOUR_M := 8.0
## Pad vise s'il est suivi de PAD_RUN_M qui se prennent a PAD_TOP_MS (vitesse
## max et son boost) avec l'adherence PAD_LATERAL.
const PAD_RUN_M := 150.0
const PAD_TOP_MS := 150.0 / 3.6
const PAD_LATERAL := 1.145 * 0.9 * 9.81
## Ligne la plus rapide, pas la plus lisse (2026-10-20 : « il ne coupe pas un
## virage en passant a l'interieur, il respecte trop le circuit ») : presque
## tous les virages se prennent a fond, la longueur compte donc autant que la
## courbure. Chaque ligne essayee minimise longueur + (SMOOTH_M / pas)^2 x
## courbure (un ressort qui tend la ligne vers la corde, lisse sur SMOOTH_M) ;
## 0 : courbure seule. Gardee : celle du meilleur tour estime (_lap_time),
## aux reglages du bot dur.
const SMOOTH_M := [0.0, 160.0, 110.0, 75.0, 50.0]
const EST_LATERAL := 1.145 * 0.95 * 9.81
const EST_BRAKE := 9.9 * 0.95
const EST_ACCEL := 3.0
const EST_TOP := 150.0 / 3.6
## Demi-base de la courbure (points du dernier niveau) : cercle par i - K, i, i + K.
const CURV_K := 2

static var _cache: Dictionary = {}

var track: TrackBlockout
## Par echantillon de la piste : ecart lateral, courbure (1/m).
var offset: PackedFloat32Array = []
var curvature: PackedFloat32Array = []
var _profiles: Dictionary = {}
## Lissage retenu (SMOOTH_M) et tour estime de chaque essai (s).
var smooth_m: float = 0.0
var lap_estimates: PackedFloat32Array = []
## Bornes laterales par echantillon de la piste.
var _lo: PackedFloat32Array = []
var _hi: PackedFloat32Array = []


## Ligne de `t`, calculee au premier appel puis gardee. La meme piste
## rechargee (nouvelle partie) reprend la ligne gardee, rattachee a elle : la
## piste d'avant est liberee (un profil de vitesse neuf, pour un autre niveau
## de bots, plantait sur elle).
static func of(t: TrackBlockout) -> RacingLine:
	var key := "%s|%.2f|%.1f" % [t.name, t.length(), t.width]
	if not _cache.has(key):
		var l := RacingLine.new()
		l._build(t)
		_cache[key] = l
	var line: RacingLine = _cache[key]
	line.track = t
	return line


func _build(t: TrackBlockout) -> void:
	track = t
	var n := t.sample_count()
	var lim := maxf(0.0, t.width / 2.0 - MARGIN_M)
	_lo.resize(n)
	_hi.resize(n)
	_lo.fill(-lim)
	_hi.fill(lim)
	var o := PackedFloat32Array()
	var best_lap := INF
	for sm: float in SMOOTH_M:
		var c := PackedFloat32Array()
		for level: Array in LEVELS:
			c = _solve(c, level, sm)
		var lap := _lap_time(c)
		lap_estimates.append(lap)
		if lap < best_lap:
			best_lap = lap
			o = c
			smooth_m = sm
	# _base / _right du dernier niveau : memes pour chaque essai
	# pads de boost : passer dessus ; sauts et flaques : a cote, du cote
	# faisable le plus proche. Seulement si le detour reste petit
	# (DETOUR_M) : un grand crochet coute plus qu'il ne rapporte
	var changed := false
	var pad_half := t.boost_pad_size.x / 2.0 - PAD_INSET_M
	var free_k := _curvatures(o)
	for b: Vector2 in t._boosts:
		if not _flat_after(free_k, b.x):
			continue
		var at := _line_at(o, b.x)
		var want := clampf(at, b.y - pad_half, b.y + pad_half)
		if absf(want - at) <= DETOUR_M and b.y - pad_half <= lim and b.y + pad_half >= -lim:
			_bound_zone(b.x, t.boost_pad_size.y / 2.0 + 2.0, maxf(b.y - pad_half, -lim), minf(b.y + pad_half, lim))
			changed = true
	var zones: Array[Vector4] = []
	for j: Vector2 in t._jumps:
		zones.append(Vector4(j.x, t.jump_length / 2.0 + 4.0, j.y, t.jump_width / 2.0))
	for p: Vector3 in t._puddles:
		zones.append(Vector4(p.x, p.z + 4.0, p.y, p.z))
	# barils explosifs (2026-10-20 : « ils foncent dedans ») : zone de
	# declenchement, toujours contourne (quel que soit le detour)
	var first_barrel := zones.size()
	# (zone elargie : le bot le voit sur sa route a moins de sa demi-largeur
	# plus une marge, BotInputSource.CLEAR_M)
	var barrel_r := ExplosiveBarrel.BARREL_RADIUS + 1.0 + 1.5
	for b: Vector2 in t._barrels:
		zones.append(Vector4(b.x, barrel_r + 4.0, b.y, barrel_r))
	for zi in zones.size():
		var z := zones[zi]
		var at := _line_at(o, z.x)
		var c := t.index_at_s(z.x)
		var best := INF
		var best_side := 0.0
		for side: float in [-1.0, 1.0]:
			var edge := z.z + side * (z.w + AVOID_CLEAR_M)
			# cote faisable : la bande restante n'est pas vide
			if (side > 0.0 and edge > _hi[c]) or (side < 0.0 and edge < _lo[c]):
				continue
			var reach := maxf(0.0, (edge - at) * side)
			if reach < best:
				best = reach
				best_side = side
		if best_side == 0.0 or (best > DETOUR_M and zi < first_barrel):
			continue
		var e := z.z + best_side * (z.w + AVOID_CLEAR_M)
		if best_side > 0.0:
			_bound_zone(z.x, z.y, e, INF)
		else:
			_bound_zone(z.x, z.y, -INF, e)
		changed = true
	if changed:
		for level: Array in REFINE:
			o = _solve(o, level, smooth_m)
	var m := o.size()
	var kc := _curvatures(o)
	offset.resize(n)
	curvature.resize(n)
	for i in n:
		var f := float(i) * m / n
		offset[i] = _sample_loop(o, f)
		curvature[i] = _sample_loop(kc, f)


## Vrai si la ligne de courbures `k` (dernier niveau) se prend a fond sur
## PAD_RUN_M apres l'abscisse `s` : un pad juste avant un virage ne sert a
## rien (il faudra freiner) et son detour coute.
func _flat_after(k: PackedFloat32Array, s: float) -> bool:
	var m := k.size()
	var c0 := int(float(track.index_at_s(s)) * m / track.sample_count())
	var steps := ceili(PAD_RUN_M / (track.length() / m))
	for d in steps:
		var kk := absf(k[(c0 + d) % m])
		if kk > 1e-6 and sqrt(PAD_LATERAL / kk) < PAD_TOP_MS:
			return false
	return true


## Ecart lateral de la ligne `o` (dernier niveau) a l'abscisse `s`.
func _line_at(o: PackedFloat32Array, s: float) -> float:
	return _sample_loop(o, float(track.index_at_s(s)) * o.size() / track.sample_count())


## Resserre les bornes autour de l'abscisse `s` (sur +/- `half_len` m).
func _bound_zone(s: float, half_len: float, lo: float, hi: float) -> void:
	var n := track.sample_count()
	var step := track.length() / n
	var c := track.index_at_s(s)
	for d in range(-ceili(half_len / step), ceili(half_len / step) + 1):
		var i := posmod(c + d, n)
		_lo[i] = maxf(_lo[i], lo)
		_hi[i] = minf(_hi[i], hi)
		if _lo[i] > _hi[i]:
			var mid := (_lo[i] + _hi[i]) / 2.0
			_lo[i] = mid
			_hi[i] = mid


## Un niveau de calcul : `level` = [pas en echantillons, passes], depart `from`
## (vide : ligne dessinee).
func _solve(from: PackedFloat32Array, level: Array, smooth: float) -> PackedFloat32Array:
	var t := track
	var n := t.sample_count()
	var stride: int = level[0]
	var m := maxi(16, n / stride)
	var base := PackedVector3Array()
	var right := PackedVector3Array()
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	var o := PackedFloat32Array()
	base.resize(m)
	right.resize(m)
	lo.resize(m)
	hi.resize(m)
	o.resize(m)
	for c in m:
		var i := c * n / m
		base[c] = t.sample_position(i)
		var r := t.sample_right(i)
		right[c] = Vector3(r.x, 0.0, r.z).normalized()
		# bornes du point : les plus serrees de l'intervalle qu'il couvre
		var a := -INF
		var b := INF
		for d in range(-stride / 2, stride / 2 + 1):
			var k := posmod(i + d, n)
			a = maxf(a, _lo[k])
			b = minf(b, _hi[k])
		if a > b:
			a = (a + b) / 2.0
			b = a
		lo[c] = a
		hi[c] = b
		var start := t.line_offset(i) if from.is_empty() else _sample_loop(from, float(c) * from.size() / m)
		o[c] = clampf(start, a, b)
	_base = base
	_right = right
	# poids de la courbure face au ressort : (lissage / pas)^2 ; 0 : courbure seule
	var mu := 0.0
	if smooth > 0.0:
		var h := t.length() / m
		mu = (smooth / h) * (smooth / h)
	for _p in int(level[1]):
		for c in m:
			var near := _pt(o, c - 1) + _pt(o, c + 1)
			var bend := 4.0 * near - (_pt(o, c - 2) + _pt(o, c + 2))
			var target := bend / 6.0 if smooth <= 0.0 else (near + mu * bend) / (2.0 + 6.0 * mu)
			o[c] = clampf((target - base[c]).dot(right[c]), lo[c], hi[c])
	return o


## Tour estime (s) de la ligne `o` (dernier niveau) : vitesse de virage
## sqrt(a / k) plafonnee, freinage avant chaque virage, acceleration en
## sortie (EST_*).
func _lap_time(o: PackedFloat32Array) -> float:
	var m := o.size()
	var k := _curvatures(o)
	var v := PackedFloat32Array()
	var d := PackedFloat32Array()
	v.resize(m)
	d.resize(m)
	for c in m:
		var kk := absf(k[c])
		v[c] = EST_TOP if kk < 1e-5 else minf(EST_TOP, sqrt(EST_LATERAL / kk))
		d[c] = _flat(_pt(o, c)).distance_to(_flat(_pt(o, c + 1)))
	for _lap in 2:
		for c in range(m - 1, -1, -1):
			var nxt := v[(c + 1) % m]
			v[c] = minf(v[c], sqrt(nxt * nxt + 2.0 * EST_BRAKE * d[c]))
		for c in m:
			var cur := v[c]
			var j := (c + 1) % m
			v[j] = minf(v[j], sqrt(cur * cur + 2.0 * EST_ACCEL * d[c]))
	var time := 0.0
	for c in m:
		time += d[c] / maxf((v[c] + v[(c + 1) % m]) / 2.0, 1.0)
	return time


## Courbure en chaque point d'une ligne du dernier niveau resolu.
func _curvatures(o: PackedFloat32Array) -> PackedFloat32Array:
	var k := PackedFloat32Array()
	k.resize(o.size())
	for c in o.size():
		k[c] = _circle_curvature(_flat(_pt(o, c - CURV_K)), _flat(_pt(o, c)), _flat(_pt(o, c + CURV_K)))
	return k


var _base := PackedVector3Array()
var _right := PackedVector3Array()


func _pt(o: PackedFloat32Array, c: int) -> Vector3:
	var k := posmod(c, _base.size())
	return _base[k] + _right[k] * o[k]


## Valeur interpolee d'un tableau en boucle a l'indice reel `f`.
static func _sample_loop(a: PackedFloat32Array, f: float) -> float:
	var c0 := posmod(int(floorf(f)), a.size())
	return lerpf(a[c0], a[(c0 + 1) % a.size()], f - floorf(f))


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## Courbure signee du cercle passant par trois points (0 si alignes).
static func _circle_curvature(a: Vector2, b: Vector2, c: Vector2) -> float:
	var cross := (b - a).cross(c - b)
	var d := a.distance_to(b) * b.distance_to(c) * c.distance_to(a)
	return 0.0 if d < 1e-6 else 2.0 * cross / d


## Profil de vitesse (m/s par echantillon) pour une adherence laterale
## `lateral` (m/s2), un freinage `brake` (m/s2) et une vitesse max `top` (m/s).
## Garde en cache par reglage.
func speed_profile(lateral: float, brake: float, top: float) -> PackedFloat32Array:
	var key := "%.2f|%.2f|%.2f" % [lateral, brake, top]
	if _profiles.has(key):
		return _profiles[key]
	var n := offset.size()
	var v := PackedFloat32Array()
	v.resize(n)
	for i in n:
		var k := absf(curvature[i])
		v[i] = top if k < 1e-5 else minf(top, sqrt(lateral / k))
	# passe arriere (deux tours : la boucle se referme)
	for _lap in 2:
		for j in range(n - 1, -1, -1):
			var nxt := v[(j + 1) % n]
			var ds := absf(track.sample_s((j + 1) % n) - track.sample_s(j))
			if ds > track.length() / 2.0:
				ds = track.length() - ds
			v[j] = minf(v[j], sqrt(nxt * nxt + 2.0 * brake * ds))
	_profiles[key] = v
	return v
