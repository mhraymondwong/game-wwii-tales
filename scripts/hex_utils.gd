class_name HexUtils
extends RefCounted
## Pointy-top hex helpers (odd-r offset coordinates).

static func oddr_to_axial(col: int, row: int) -> Vector2i:
	var q := col - (row - (row & 1)) / 2
	return Vector2i(q, row)

static func axial_to_oddr(q: int, r: int) -> Vector2i:
	var col := q + (r - (r & 1)) / 2
	return Vector2i(col, r)

static func oddr_to_pixel(col: int, row: int, size: float) -> Vector2:
	var x := size * sqrt(3.0) * (col + 0.5 * (row & 1))
	var y := size * 1.5 * row
	return Vector2(x, y)

static func pixel_to_oddr(pos: Vector2, size: float) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * pos.x - 1.0 / 3.0 * pos.y) / size
	var r := (2.0 / 3.0 * pos.y) / size
	var axial := axial_round(q, r)
	return axial_to_oddr(axial.x, axial.y)

static func axial_round(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundi(q)
	var rr := roundi(r)
	var rs := roundi(s)
	var q_diff := absf(rq - q)
	var r_diff := absf(rr - r)
	var s_diff := absf(rs - s)
	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs
	return Vector2i(rq, rr)

static func oddr_neighbors(col: int, row: int) -> Array[Vector2i]:
	# Pointy-top odd-r neighbor offsets
	var dirs_even: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
	]
	var dirs_odd: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1)
	]
	var dirs := dirs_odd if (row & 1) else dirs_even
	var out: Array[Vector2i] = []
	for d in dirs:
		out.append(Vector2i(col + d.x, row + d.y))
	return out

static func axial_distance(a: Vector2i, b: Vector2i) -> int:
	var aq := oddr_to_axial(a.x, a.y)
	var bq := oddr_to_axial(b.x, b.y)
	return int((absi(aq.x - bq.x) + absi(aq.x + aq.y - bq.x - bq.y) + absi(aq.y - bq.y)) / 2)

static func hex_corners(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var angle := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(angle), sin(angle)) * size)
	return pts
