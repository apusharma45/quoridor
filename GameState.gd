extends RefCounted
class_name GameState

const GRID_SIZE := 9

var player1_pos: Vector2i
var player2_pos: Vector2i
var is_player1_turn: bool

var h_walls: Array[Vector2i]
var v_walls: Array[Vector2i]

func _init():
	player1_pos = Vector2i(4, 8)
	player2_pos = Vector2i(4, 0)
	is_player1_turn = true
	h_walls = []
	v_walls = []

func clone() -> GameState:
	var s: GameState = GameState.new()
	s.player1_pos = player1_pos
	s.player2_pos = player2_pos
	s.is_player1_turn = is_player1_turn
	s.h_walls = h_walls.duplicate()
	s.v_walls = v_walls.duplicate()
	return s
