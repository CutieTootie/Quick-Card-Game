class_name Rules
extends RefCounted
## Core rules for Quick Card Game. No UI code here, so it can be tested headless.
## A card is a Dictionary {id, element, power}. A board is {"front": [6], "back": [6]}
## where empty zones are null. A game is a Dictionary, see new_game().

const ELEMENTS := ["Fire", "Earth", "Metal", "Water", "Wood"]
const COLS := 6
const ROWS := ["front", "back"]
const HAND_SIZE := 5
const DECK_SIZE := 20 # 4 of each element
const MIN_POWER := 2 # every card starts at 2; widen this range for random power
const MAX_POWER := 2
const ADJACENT_BONUS := 2
# Turn order: the first player places FIRST_TURN_CARDS, then players take
# turns placing CARDS_PER_TURN each. The first player's last turn ends up
# as a single card, so the order is 1, 2, 2, ..., 2, 1.
const FIRST_TURN_CARDS := 1
const CARDS_PER_TURN := 2

## An element gets +2 for every adjacent friendly card of the element listed here.
const FED_BY := {
	"Wood": "Water",
	"Water": "Metal",
	"Metal": "Earth",
	"Earth": "Fire",
	"Fire": "Wood",
}

## An element's power is doubled when it attacks the element listed here.
const BEATS := {
	"Wood": "Earth",
	"Earth": "Water",
	"Water": "Fire",
	"Fire": "Metal",
	"Metal": "Wood",
}

static var _next_id := 1


static func make_card(element: String, power: int) -> Dictionary:
	var card := {"id": _next_id, "element": element, "power": power}
	_next_id += 1
	return card


static func make_deck(rng: RandomNumberGenerator) -> Array:
	var deck := []
	for i in DECK_SIZE:
		deck.append(make_card(ELEMENTS[i % ELEMENTS.size()], rng.randi_range(MIN_POWER, MAX_POWER)))
	# Fisher-Yates shuffle
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	return deck


static func empty_board() -> Dictionary:
	var front := []
	var back := []
	front.resize(COLS)
	back.resize(COLS)
	return {"front": front, "back": back}


static func other_row(row: String) -> String:
	return "back" if row == "front" else "front"


static func other_side(side: String) -> String:
	return "opponent" if side == "player" else "player"


## Orthogonal neighbours on the same side: left/right in the row, and the
## card directly in front of or behind it.
static func neighbours(board: Dictionary, row: String, col: int) -> Array:
	var out := []
	if col > 0:
		out.append(board[row][col - 1])
	if col < COLS - 1:
		out.append(board[row][col + 1])
	out.append(board[other_row(row)][col])
	return out.filter(func(c): return c != null)


static func adjacency_bonus(board: Dictionary, row: String, col: int) -> int:
	var card = board[row][col]
	if card == null:
		return 0
	var feeder: String = FED_BY[card.element]
	var count := 0
	for c in neighbours(board, row, col):
		if c.element == feeder:
			count += 1
	return count * ADJACENT_BONUS


## Power on the board before any attack matchup.
static func board_power(board: Dictionary, row: String, col: int) -> int:
	var card = board[row][col]
	if card == null:
		return 0
	return card.power + adjacency_bonus(board, row, col)


static func beats(attacker, defender) -> bool:
	return attacker != null and defender != null and BEATS[attacker.element] == defender.element


## Power when this card attacks the given defender (bonus first, then doubled).
static func attack_power(board: Dictionary, row: String, col: int, defender) -> int:
	var base := board_power(board, row, col)
	return base * 2 if beats(board[row][col], defender) else base


static func is_full(board: Dictionary) -> bool:
	for row in ROWS:
		for c in board[row]:
			if c == null:
				return false
	return true


static func empty_slots(board: Dictionary) -> Array:
	var slots := []
	for row in ROWS:
		for col in COLS:
			if board[row][col] == null:
				slots.append({"row": row, "col": col})
	return slots


## The card in a row/column fights the opposing card in the same row and column.
static func resolve_battle(player_board: Dictionary, opp_board: Dictionary, row: String, col: int) -> Dictionary:
	var p = player_board[row][col]
	var o = opp_board[row][col]
	var p_pow := attack_power(player_board, row, col, o)
	var o_pow := attack_power(opp_board, row, col, p)
	var winner := "tie"
	if p_pow > o_pow:
		winner = "player"
	elif o_pow > p_pow:
		winner = "opponent"
	return {
		"row": row, "col": col,
		"player_power": p_pow, "opp_power": o_pow,
		"p_doubled": beats(p, o), "o_doubled": beats(o, p),
		"winner": winner,
	}


static func resolve_all(player_board: Dictionary, opp_board: Dictionary) -> Dictionary:
	var battles := []
	var score := {"player": 0, "opponent": 0}
	for row in ROWS:
		for col in COLS:
			var b := resolve_battle(player_board, opp_board, row, col)
			battles.append(b)
			if b.winner != "tie":
				score[b.winner] += 1
	return {"battles": battles, "score": score}


## Deals a new game. Card ids restart at 1, so two computers given RNGs with the
## same seed deal exactly the same game (used by Steam online play).
static func new_game(rng: RandomNumberGenerator) -> Dictionary:
	_next_id = 1
	var g := {
		"player": {"deck": make_deck(rng), "hand": [], "board": empty_board()},
		"opponent": {"deck": make_deck(rng), "hand": [], "board": empty_board()},
		"turn": "player",
		"moves_left": FIRST_TURN_CARDS, # cards the current player still places this turn
	}
	for side in ["player", "opponent"]:
		for i in HAND_SIZE:
			g[side].hand.append(g[side].deck.pop_back())
	return g


## Place a card from `side`'s hand. Returns true on success.
static func place_card(game: Dictionary, side: String, card_id: int, row: String, col: int) -> bool:
	var s: Dictionary = game[side]
	var idx := -1
	for i in s.hand.size():
		if s.hand[i].id == card_id:
			idx = i
	if idx < 0 or s.board[row][col] != null:
		return false
	s.board[row][col] = s.hand[idx]
	s.hand.remove_at(idx)
	if not s.deck.is_empty():
		s.hand.append(s.deck.pop_back())
	var other := other_side(side)
	game.moves_left -= 1
	if is_full(game.player.board) and is_full(game.opponent.board):
		game.turn = "done"
		game.moves_left = 0
	elif game.moves_left > 0 and not is_full(s.board):
		pass # same player keeps going
	else:
		var next := side if is_full(game[other].board) else other
		game.turn = next
		game.moves_left = mini(CARDS_PER_TURN, empty_slots(game[next].board).size())
	return true


static func clone_board(board: Dictionary) -> Dictionary:
	return {"front": board.front.duplicate(), "back": board.back.duplicate()}


## Rough value of a board position for `me` against `them`. Decided zones
## count as a point either way; open zones count a little for raw power.
static func evaluate(me: Dictionary, them: Dictionary) -> float:
	var score := 0.0
	for row in ROWS:
		for col in COLS:
			var mine = me[row][col]
			var theirs = them[row][col]
			if mine != null and theirs != null:
				var a := attack_power(me, row, col, theirs)
				var b := attack_power(them, row, col, mine)
				score += 1.0 if a > b else (-1.0 if a < b else 0.0)
				score += (a - b) * 0.02
			elif mine != null:
				score += board_power(me, row, col) * 0.06
			elif theirs != null:
				score -= board_power(them, row, col) * 0.06
	return score


## Simple greedy computer opponent: try every card in every empty zone and
## keep the move that scores best, with a little noise so games vary.
static func choose_move(game: Dictionary, side: String, rng: RandomNumberGenerator) -> Dictionary:
	var me: Dictionary = game[side]
	var them: Dictionary = game[other_side(side)]
	var best := {}
	for card in me.hand:
		for slot in empty_slots(me.board):
			var trial := clone_board(me.board)
			trial[slot.row][slot.col] = card
			var value := evaluate(trial, them.board) + rng.randf() * 0.05
			if best.is_empty() or value > best.value:
				best = {"card_id": card.id, "row": slot.row, "col": slot.col, "value": value}
	return best
