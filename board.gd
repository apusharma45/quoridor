extends Node2D
var state: GameState
var hover_cell := Vector2i(-1, -1)
var highlight_moves: Array[Vector2i] = []
const GRID_SIZE := 9
const CELL := 56
const GAP := 12
var warn_dialog: AcceptDialog
enum WallMode { NONE, H, V }
var wall_mode: WallMode = WallMode.NONE
var game_over := false
var winner := ""  # "Blue" or "Red"
var player1_pos := Vector2i(4, 8) # blue bottom
var player2_pos := Vector2i(4, 0) # red top
var is_player1_turn := true
var ai_vs_ai := true
var ai_delay := 0.25
var ai_timer := 0.0

# store walls by their top-left cell coordinate (x,y)
# H wall sits in the horizontal gap below cell (x,y), spans two cells (x..x+1)
# V wall sits in the vertical gap right of cell (x,y), spans two cells (y..y+1)
var h_walls: Array[Vector2i] = []
var v_walls: Array[Vector2i] = []


func _ready() -> void:
	randomize()
	warn_dialog = AcceptDialog.new()
	warn_dialog.title = "Invalid Wall Placement"
	add_child(warn_dialog)
	state = GameState.new()

	queue_redraw()

func show_warning(msg: String) -> void:
	warn_dialog.dialog_text = msg
	warn_dialog.popup_centered()
func check_win() -> void:
	if player1_pos.y == 0:
		game_over = true
		winner = "Blue"
	elif player2_pos.y == GRID_SIZE - 1:
		game_over = true
		winner = "Red"

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

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < GRID_SIZE and c.y >= 0 and c.y < GRID_SIZE


func neighbors(c: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for d in dirs:
		var n = c + d
		if in_bounds(n) and not is_blocked(c, n):
			result.append(n)
	return result


func has_path_to_goal(start: Vector2i, goal_y: int) -> bool:
	# BFS on cells; ignores pawns (standard for wall legality)
	var q: Array[Vector2i] = [start]
	var visited := {}
	visited[start] = true

	while q.size() > 0:
		var cur = q.pop_front()
		if cur.y == goal_y:
			return true

		for n in neighbors(cur):
			if not visited.has(n):
				visited[n] = true
				q.append(n)

	return false


func wall_keeps_paths() -> bool:
	# Player1 (blue) goal is TOP row y=0
	# Player2 (red) goal is BOTTOM row y=GRID_SIZE-1
	return has_path_to_goal(player1_pos, 0) and has_path_to_goal(player2_pos, GRID_SIZE - 1)




func legal_pawn_moves(me: Vector2i, other: Vector2i) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

	for d: Vector2i in dirs:
		var n: Vector2i = me + d
		if not in_bounds(n):
			continue
		if is_blocked(me, n):
			continue

		# normal move to empty adjacent cell
		if n != other:
			moves.append(n)
			continue

		# opponent is adjacent: attempt straight jump
		var behind: Vector2i = other + d
		var can_jump_straight := in_bounds(behind) and (not is_blocked(other, behind))

		if can_jump_straight:
			moves.append(behind)
		else:
			# straight jump blocked (or border): allow diagonal around opponent
			var perp: Array[Vector2i]
			if d.x != 0:
				perp = [Vector2i(0,1), Vector2i(0,-1)]
			else:
				perp = [Vector2i(1,0), Vector2i(-1,0)]

			for pd: Vector2i in perp:
				var diag: Vector2i = other + pd
				if in_bounds(diag) and (not is_blocked(other, diag)):
					moves.append(diag)

	return moves



func legal_pawn_actions(me: Vector2i, other: Vector2i) -> Array[Dictionary]:
	var acts: Array[Dictionary] = []
	for m in legal_pawn_moves(me, other):
		acts.append({"type":"move", "to": m})
	return acts


func legal_wall_actions() -> Array[Dictionary]:
	# brute force all possible wall anchors (0..7, 0..7) for both orientations
	var acts: Array[Dictionary] = []
	for y in range(0, 8):
		for x in range(0, 8):
			var w := Vector2i(x, y)

			# H candidate
			if not h_walls.has(w) \
			and not h_walls.has(Vector2i(x - 1, y)) \
			and not h_walls.has(Vector2i(x + 1, y)) \
			and not v_walls.has(w):
				h_walls.append(w)
				var ok := wall_keeps_paths()
				h_walls.pop_back()
				if ok:
					acts.append({"type":"wall", "ori":"H", "at": w})

			# V candidate
			if not v_walls.has(w) \
			and not v_walls.has(Vector2i(x, y - 1)) \
			and not v_walls.has(Vector2i(x, y + 1)) \
			and not h_walls.has(w):
				v_walls.append(w)
				var ok2 := wall_keeps_paths()
				v_walls.pop_back()
				if ok2:
					acts.append({"type":"wall", "ori":"V", "at": w})

	return acts


func legal_actions_for_turn() -> Array[Dictionary]:
	# For now, we allow both move and wall actions.
	# (Later you can limit wall actions if you track remaining wall counts.)
	var acts: Array[Dictionary] = []

	if is_player1_turn:
		acts.append_array(legal_pawn_actions(player1_pos, player2_pos))
	else:
		acts.append_array(legal_pawn_actions(player2_pos, player1_pos))

	acts.append_array(legal_wall_actions())
	return acts
func apply_action(action: Dictionary) -> void:
	if action["type"] == "move":
		var to: Vector2i = action["to"]
		if is_player1_turn:
			player1_pos = to
		else:
			player2_pos = to
		is_player1_turn = !is_player1_turn
		check_win()
		return

	if action["type"] == "wall":
		var at: Vector2i = action["at"]
		var ori: String = action["ori"]
		if ori == "H":
			h_walls.append(at)
		else:
			v_walls.append(at)
		is_player1_turn = !is_player1_turn
		check_win()
		return


func _process(delta: float) -> void:
	# --- highlight moves ---
	var p := to_local(get_viewport().get_mouse_position())
	var cell := mouse_to_cell(p)
	if cell != hover_cell:
		hover_cell = cell
		if is_player1_turn:
			highlight_moves = legal_pawn_moves(player1_pos, player2_pos)
		else:
			highlight_moves = legal_pawn_moves(player2_pos, player1_pos)
		queue_redraw()

	# --- AI vs AI autoplay ---
	if not ai_vs_ai:
		return
	if game_over:
		return

	ai_timer += delta
	if ai_timer < ai_delay:
		return
	ai_timer = 0.0

	# Get pawn actions for current player
	var pawn_actions: Array[Dictionary]
	if is_player1_turn:
		pawn_actions = legal_pawn_actions(player1_pos, player2_pos)
	else:
		pawn_actions = legal_pawn_actions(player2_pos, player1_pos)

	# Get wall actions (can be expensive, but ok for now)
	var wall_actions: Array[Dictionary] = legal_wall_actions()

	var roll := randi() % 100
	var choose_move := roll < 80

	var chosen: Dictionary

	if choose_move and pawn_actions.size() > 0:
		chosen = pawn_actions[randi() % pawn_actions.size()]
	elif wall_actions.size() > 0:
		chosen = wall_actions[randi() % wall_actions.size()]
	elif pawn_actions.size() > 0:
		chosen = pawn_actions[randi() % pawn_actions.size()]
	else:
		print("No legal actions?!")
		return

	print(("Blue" if is_player1_turn else "Red"), " chose: ", chosen)
	apply_action(chosen)
	queue_redraw()


func _input(event: InputEvent) -> void:
	# --- handle keys ---
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

				# crossing
				if v_walls.has(w):
					print("Invalid H wall (crossing):", w)
					queue_redraw()
					return

				# tentatively place then validate paths
				h_walls.append(w)
				if not wall_keeps_paths():
					h_walls.pop_back()
					show_warning("You can't place that wall because it blocks all paths to the goal for at least one player.")
					queue_redraw()
					return

				# success: wall uses turn + exit wall mode
				print("Placed H wall:", w)
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

				# crossing
				if h_walls.has(w):
					print("Invalid V wall (crossing):", w)
					queue_redraw()
					return

				# tentatively place then validate paths
				v_walls.append(w)
				if not wall_keeps_paths():
					v_walls.pop_back()
					show_warning("You can't place that wall because it blocks all paths to the goal for at least one player.")
					queue_redraw()
					return

				# success: wall uses turn + exit wall mode
				print("Placed V wall:", w)
				is_player1_turn = !is_player1_turn
				wall_mode = WallMode.NONE
				queue_redraw()
				return

		# ===== PAWN MODE (uses full legal move generator incl. diagonal) =====
		var target := mouse_to_cell(p)
		if target.x == -1:
			return

		if is_player1_turn:
			var moves := legal_pawn_moves(player1_pos, player2_pos)
			if moves.has(target):
				player1_pos = target
				is_player1_turn = false
		else:
			var moves := legal_pawn_moves(player2_pos, player1_pos)
			if moves.has(target):
				player2_pos = target
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
	# --- Highlight legal moves for current player ---
	for m in highlight_moves:
		var top_left := cell_origin(m)
		var r := Rect2(top_left, Vector2(CELL, CELL))
		draw_rect(r, Color(0.2, 0.8, 0.2, 0.35), true)
	
	# --- Draw pawns ---
	var p1_center := cell_origin(state.player1_pos) + Vector2(CELL/2, CELL/2)
	draw_circle(p1_center, CELL/3, Color.BLUE)

	var p2_center := cell_origin(state.player2_pos) + Vector2(CELL/2, CELL/2)
	draw_circle(p2_center, CELL/3, Color.RED)
