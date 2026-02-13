extends Node2D

const GRID_SIZE := 9
const CELL := 56
const GAP := 12

enum WallMode { NONE, H, V }
var wall_mode: WallMode = WallMode.NONE

var player1_pos := Vector2i(4, 8) # blue bottom
var player2_pos := Vector2i(4, 0) # red top
var is_player1_turn := true

# store walls by their top-left cell coordinate (x,y)
# H wall sits in the horizontal gap below cell (x,y), spans two cells (x..x+1)
# V wall sits in the vertical gap right of cell (x,y), spans two cells (y..y+1)
var h_walls: Array[Vector2i] = []
var v_walls: Array[Vector2i] = []


func _ready() -> void:
	queue_redraw()


func cell_origin(c: Vector2i) -> Vector2:
	return Vector2(c.x * (CELL + GAP), c.y * (CELL + GAP))


func mouse_to_cell(pos: Vector2) -> Vector2i:
	# pos must be LOCAL to Board
	var stride := CELL + GAP

	var cx := int(floor(pos.x / stride))
	var cy := int(floor(pos.y / stride))

	if cx < 0 or cx >= GRID_SIZE or cy < 0 or cy >= GRID_SIZE:
		return Vector2i(-1, -1)

	var local_x := pos.x - cx * stride
	var local_y := pos.y - cy * stride

	# clicked in GAP, not inside a cell
	if local_x >= CELL or local_y >= CELL:
		return Vector2i(-1, -1)

	return Vector2i(cx, cy)


func mouse_to_h_wall(pos: Vector2) -> Vector2i:
	# click must be in H gap band: y in [CELL, CELL+GAP), x in [0, CELL)
	# returns top-left cell coord (x,y) where wall is placed below that cell.
	var stride := CELL + GAP

	var gx := int(floor(pos.x / stride))
	var gy := int(floor(pos.y / stride))

	# must be able to span 2 cells and be between rows => gx,gy in 0..7
	if gx < 0 or gx > 7 or gy < 0 or gy > 7:
		return Vector2i(-1, -1)

	var local_x := pos.x - gx * stride
	var local_y := pos.y - gy * stride

	if local_y >= CELL and local_y < CELL + GAP and local_x >= 0 and local_x < CELL:
		return Vector2i(gx, gy)

	return Vector2i(-1, -1)


func mouse_to_v_wall(pos: Vector2) -> Vector2i:
	# click must be in V gap band: x in [CELL, CELL+GAP), y in [0, CELL)
	# returns top-left cell coord (x,y) where wall is placed right of that cell.
	var stride := CELL + GAP

	var gx := int(floor(pos.x / stride))
	var gy := int(floor(pos.y / stride))

	if gx < 0 or gx > 7 or gy < 0 or gy > 7:
		return Vector2i(-1, -1)

	var local_x := pos.x - gx * stride
	var local_y := pos.y - gy * stride

	if local_x >= CELL and local_x < CELL + GAP and local_y >= 0 and local_y < CELL:
		return Vector2i(gx, gy)

	return Vector2i(-1, -1)


func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var dx = abs(a.x - b.x)
	var dy = abs(a.y - b.y)
	return (dx + dy) == 1


func jump_target(me: Vector2i, other: Vector2i, target: Vector2i) -> Vector2i:
	# straight 2-step with opponent in the middle
	var dx = target.x - me.x
	var dy = target.y - me.y
	if not ((abs(dx) == 2 and dy == 0) or (abs(dy) == 2 and dx == 0)):
		return Vector2i(-1, -1)

	var mid = Vector2i(me.x + dx / 2, me.y + dy / 2)
	if mid != other:
		return Vector2i(-1, -1)

	return target
func has_h_wall(w: Vector2i) -> bool:
	return h_walls.has(w)

func has_v_wall(w: Vector2i) -> bool:
	return v_walls.has(w)

func h_overlaps(w: Vector2i) -> bool:
	# horizontal wall at (x,y) overlaps if there's also one at (x-1,y) or (x+1,y)
	return h_walls.has(w) or h_walls.has(Vector2i(w.x - 1, w.y)) or h_walls.has(Vector2i(w.x + 1, w.y))

func v_overlaps(w: Vector2i) -> bool:
	# vertical wall at (x,y) overlaps if there's also one at (x,y-1) or (x,y+1)
	return v_walls.has(w) or v_walls.has(Vector2i(w.x, w.y - 1)) or v_walls.has(Vector2i(w.x, w.y + 1))

func crosses_hv(h: Vector2i, v: Vector2i) -> bool:
	# A horizontal wall at (hx,hy) crosses a vertical wall at (vx,vy)
	# when they share the same "intersection": v at (hx,hy) crosses h at (hx,hy)
	return h == v

func is_blocked(from: Vector2i, to: Vector2i) -> bool:
	var dx := to.x - from.x
	var dy := to.y - from.y

	# Moving right: crossing the vertical boundary between (from.x, from.y) and (from.x+1, from.y)
	if dx == 1 and dy == 0:
		# A V wall at (from.x, from.y) blocks this edge,
		# AND a V wall at (from.x, from.y-1) also blocks it (because wall spans two rows).
		return v_walls.has(Vector2i(from.x, from.y)) or v_walls.has(Vector2i(from.x, from.y - 1))

	# Moving left
	if dx == -1 and dy == 0:
		# boundary is at x = to.x, check V wall at (to.x, to.y) and (to.x, to.y-1)
		return v_walls.has(Vector2i(to.x, to.y)) or v_walls.has(Vector2i(to.x, to.y - 1))

	# Moving down: crossing the horizontal boundary between (from.x, from.y) and (from.x, from.y+1)
	if dx == 0 and dy == 1:
		# An H wall at (from.x, from.y) blocks this edge,
		# AND an H wall at (from.x-1, from.y) also blocks it (because wall spans two cols).
		return h_walls.has(Vector2i(from.x, from.y)) or h_walls.has(Vector2i(from.x - 1, from.y))

	# Moving up
	if dx == 0 and dy == -1:
		# boundary is at y = to.y, check H wall at (to.x, to.y) and (to.x-1, to.y)
		return h_walls.has(Vector2i(to.x, to.y)) or h_walls.has(Vector2i(to.x - 1, to.y))

	return false




func _input(event: InputEvent) -> void:
	# --- handle keys (reliable) ---
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			wall_mode = WallMode.H
			print("Wall mode: H")
		elif event.keycode == KEY_V:
			wall_mode = WallMode.V
			print("Wall mode: V")
		elif event.keycode == KEY_ESCAPE:
			wall_mode = WallMode.NONE
			print("Wall mode: NONE")
		return

	# --- handle mouse click ---
	if event is InputEventMouseButton and event.pressed:
		var p := to_local(event.position)

		# ===== WALL MODE =====
		if wall_mode != WallMode.NONE:
			if wall_mode == WallMode.H:
				var w := mouse_to_h_wall(p)
				if w.x == -1:
					return

				# duplicate
				if h_walls.has(w):
					print("Invalid H wall (duplicate):", w)
					queue_redraw()
					return

				# overlap (adjacent horizontal in same lane)
				if h_walls.has(Vector2i(w.x - 1, w.y)) or h_walls.has(Vector2i(w.x + 1, w.y)):
					print("Invalid H wall (overlap):", w)
					queue_redraw()
					return

				# crossing (same coordinate as vertical)
				if v_walls.has(w):
					print("Invalid H wall (crossing):", w)
					queue_redraw()
					return

				# place wall
				h_walls.append(w)
				print("Placed H wall:", w)

				# wall uses the turn + exit wall mode
				is_player1_turn = !is_player1_turn
				wall_mode = WallMode.NONE

				queue_redraw()
				return

			elif wall_mode == WallMode.V:
				var w := mouse_to_v_wall(p)
				if w.x == -1:
					return

				# duplicate
				if v_walls.has(w):
					print("Invalid V wall (duplicate):", w)
					queue_redraw()
					return

				# overlap (adjacent vertical in same lane)
				if v_walls.has(Vector2i(w.x, w.y - 1)) or v_walls.has(Vector2i(w.x, w.y + 1)):
					print("Invalid V wall (overlap):", w)
					queue_redraw()
					return

				# crossing (same coordinate as horizontal)
				if h_walls.has(w):
					print("Invalid V wall (crossing):", w)
					queue_redraw()
					return

				# place wall
				v_walls.append(w)
				print("Placed V wall:", w)

				# wall uses the turn + exit wall mode
				is_player1_turn = !is_player1_turn
				wall_mode = WallMode.NONE

				queue_redraw()
				return

		# ===== PAWN MODE =====
		var target := mouse_to_cell(p)
		if target.x == -1:
			return

		if is_player1_turn:
			# normal 1-step move, blocked by walls
			if is_adjacent(player1_pos, target) and target != player2_pos and not is_blocked(player1_pos, target):
				player1_pos = target
				is_player1_turn = false
			else:
				# jump move (NOTE: we haven't applied wall-blocking to jump yet; we'll do next)
				var jt := jump_target(player1_pos, player2_pos, target)
				if jt.x != -1:
					player1_pos = jt
					is_player1_turn = false
		else:
			if is_adjacent(player2_pos, target) and target != player1_pos and not is_blocked(player2_pos, target):
				player2_pos = target
				is_player1_turn = true
			else:
				var jt := jump_target(player2_pos, player1_pos, target)
				if jt.x != -1:
					player2_pos = jt
					is_player1_turn = true

		queue_redraw()


func _draw() -> void:
	# --- Draw 9x9 cells (with gaps) ---
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var top_left := cell_origin(Vector2i(x, y))
			var r := Rect2(top_left, Vector2(CELL, CELL))
			draw_rect(r, Color(0.85, 0.85, 0.85), true)
			draw_rect(r, Color(0.2, 0.2, 0.2), false, 2)

	# --- Draw walls in the GAP lanes ---
	for w in h_walls:
		var top_left := cell_origin(w)
		var wall_pos := Vector2(top_left.x, top_left.y + CELL)
		var wall_size := Vector2((CELL * 2) + GAP, GAP)
		draw_rect(Rect2(wall_pos, wall_size), Color(0.1, 0.1, 0.1), true)

	for w in v_walls:
		var top_left := cell_origin(w)
		var wall_pos := Vector2(top_left.x + CELL, top_left.y)
		var wall_size := Vector2(GAP, (CELL * 2) + GAP)
		draw_rect(Rect2(wall_pos, wall_size), Color(0.1, 0.1, 0.1), true)

	# --- Draw pawns ---
	var p1_center := cell_origin(player1_pos) + Vector2(CELL/2, CELL/2)
	draw_circle(p1_center, CELL/3, Color.BLUE)

	var p2_center := cell_origin(player2_pos) + Vector2(CELL/2, CELL/2)
	draw_circle(p2_center, CELL/3, Color.RED)
