extends RefCounted
class_name FrontierGeometry


static func build_upward_cone_sector(apex: Vector2, radius: float, half_angle: float, arc_segments: int = 72) -> PackedVector2Array:
	var up_angle := -PI * 0.5
	var right_angle := up_angle + half_angle
	var left_angle := up_angle - half_angle
	return _build_sector_polygon(apex, radius, right_angle, left_angle, arc_segments)


static func build_downward_cone_sector(apex: Vector2, radius: float, half_angle: float, arc_segments: int = 56) -> PackedVector2Array:
	var down_angle := PI * 0.5
	var right_angle := down_angle - half_angle
	var left_angle := down_angle + half_angle
	return _build_sector_polygon(apex, radius, right_angle, left_angle, arc_segments)


static func build_upper_outside_polygon(
	apex: Vector2,
	radius: float,
	half_angle: float,
	world_half_width: float,
	top_y: float,
	baseline_y: float,
	arc_segments: int = 72
) -> PackedVector2Array:
	var up_angle := -PI * 0.5
	var right_angle := up_angle + half_angle
	var left_angle := up_angle - half_angle

	var points := PackedVector2Array()
	points.append(Vector2(-world_half_width, baseline_y))
	points.append(Vector2(-world_half_width, top_y))
	points.append(Vector2(world_half_width, top_y))
	points.append(Vector2(world_half_width, baseline_y))

	var right_arc := apex + (Vector2.RIGHT.rotated(right_angle) * radius)
	points.append(right_arc)
	for i in range(arc_segments + 1):
		var t := float(i) / float(maxi(arc_segments, 1))
		var angle := lerpf(right_angle, left_angle, t)
		points.append(apex + (Vector2.RIGHT.rotated(angle) * radius))
	points.append(apex)
	return points


static func build_full_outside_polygon(
	apex: Vector2,
	half_angle: float,
	world_left: float,
	world_right: float,
	top_y: float,
	bottom_y: float
) -> PackedVector2Array:
	## Full world rectangle minus the upward cone.
	## Cone edges are traced to where they exit the world rect boundary.
	## The returned polygon follows a non-overlapping boundary path so triangulation remains valid.
	var up_angle := -PI * 0.5
	var left_dir := Vector2.RIGHT.rotated(up_angle - half_angle)
	var right_dir := Vector2.RIGHT.rotated(up_angle + half_angle)
	var left_hit := _ray_rect_exit_with_edge(apex, left_dir, world_left, world_right, top_y, bottom_y)
	var right_hit := _ray_rect_exit_with_edge(apex, right_dir, world_left, world_right, top_y, bottom_y)
	var left_exit: Vector2 = left_hit.point
	var right_exit: Vector2 = right_hit.point
	var left_edge: String = left_hit.edge
	var right_edge: String = right_hit.edge
	var pts := PackedVector2Array()
	var tl := Vector2(world_left, top_y)
	var tr := Vector2(world_right, top_y)
	var br := Vector2(world_right, bottom_y)
	var bl := Vector2(world_left, bottom_y)

	pts.append(left_exit)
	pts.append(apex)
	pts.append(right_exit)

	if left_edge == "top" and right_edge == "top":
		# Top intersections: close through top-right, then bottom, then top-left.
		pts.append(tr)
		pts.append(br)
		pts.append(bl)
		pts.append(tl)
	elif left_edge == "left" and right_edge == "top":
		# Left -> top path closes through right side and bottom.
		pts.append(tr)
		pts.append(br)
		pts.append(bl)
	elif left_edge == "top" and right_edge == "right":
		# Top -> right path closes through bottom and top-left.
		pts.append(br)
		pts.append(bl)
		pts.append(tl)
	else:
		# Side intersections (left/right) close through bottom only.
		pts.append(br)
		pts.append(bl)

	return pts


static func _ray_rect_exit_with_edge(
	origin: Vector2,
	direction: Vector2,
	left: float,
	right: float,
	top: float,
	bottom: float
) -> Dictionary:
	var best_t := INF
	var best_edge := ""
	if direction.y != 0.0:
		var t := (top - origin.y) / direction.y
		if t > 0.0:
			var x := origin.x + t * direction.x
			if x >= left and x <= right:
				if t < best_t:
					best_t = t
					best_edge = "top"
		var t2 := (bottom - origin.y) / direction.y
		if t2 > 0.0:
			var x2 := origin.x + t2 * direction.x
			if x2 >= left and x2 <= right:
				if t2 < best_t:
					best_t = t2
					best_edge = "bottom"
	if direction.x != 0.0:
		var t := (left - origin.x) / direction.x
		if t > 0.0:
			var y := origin.y + t * direction.y
			if y >= top and y <= bottom:
				if t < best_t:
					best_t = t
					best_edge = "left"
		var t2 := (right - origin.x) / direction.x
		if t2 > 0.0:
			var y2 := origin.y + t2 * direction.y
			if y2 >= top and y2 <= bottom:
				if t2 < best_t:
					best_t = t2
					best_edge = "right"
	if best_t == INF:
		return {"point": origin, "edge": "none"}
	return {"point": origin + direction * best_t, "edge": best_edge}


static func clamp_polygon_points(points: PackedVector2Array, min_x: float, max_x: float, min_y: float, max_y: float) -> PackedVector2Array:
	var clamped := PackedVector2Array()
	for pt in points:
		clamped.append(Vector2(
			clampf(pt.x, min_x, max_x),
			clampf(pt.y, min_y, max_y)
		))
	return clamped


static func _build_sector_polygon(apex: Vector2, radius: float, start_angle: float, end_angle: float, arc_segments: int) -> PackedVector2Array:
	var safe_radius := maxf(0.0, radius)
	var safe_segments := maxi(4, arc_segments)
	var points := PackedVector2Array()
	points.append(apex)
	for i in range(safe_segments + 1):
		var t := float(i) / float(safe_segments)
		var angle := lerpf(start_angle, end_angle, t)
		points.append(apex + (Vector2.RIGHT.rotated(angle) * safe_radius))
	return points