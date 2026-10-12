extends SceneTree
## Rules tests. Run from the godot folder:
##   godot --headless --script res://tests/test_rules.gd

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func board(cells: Array) -> Dictionary:
	var b := Rules.empty_board()
	for c in cells:
		b[c[0]][c[1]] = Rules.make_card(c[2], c[3])
	return b


func _init() -> void:
	var rng := RandomNumberGenerator.new()

	# Wood gets +2 for each adjacent Water (left, right, behind), not diagonal.
	var b := board([
		["front", 2, "Wood", 5],
		["front", 1, "Water", 1],
		["front", 3, "Water", 1],
		["back", 2, "Water", 1],
		["back", 1, "Water", 1],
	])
	check(Rules.board_power(b, "front", 2) == 11, "adjacency bonus")

	for el in Rules.ELEMENTS:
		b = board([["front", 0, el, 3], ["front", 1, Rules.FED_BY[el], 1]])
		check(Rules.board_power(b, "front", 0) == 5, "feeder bonus for " + el)

	# Doubling happens after the bonus.
	var p := board([["front", 0, "Fire", 4], ["back", 0, "Wood", 1]])
	var o := board([["front", 0, "Metal", 10], ["back", 0, "Metal", 1]])
	var r := Rules.resolve_battle(p, o, "front", 0)
	check(r.player_power == 12 and r.opp_power == 10 and r.winner == "player" and r.p_doubled, "bonus then double")

	# Ties score nothing.
	check(Rules.resolve_battle(board([["front", 0, "Fire", 5]]), board([["front", 0, "Fire", 5]]), "front", 0).winner == "tie", "tie")

	# Every card starts at 2 power.
	for c in Rules.make_deck(rng):
		check(c.power == 2, "card power is 2")

	# Full AI-vs-AI games: 24 moves, 12 battles, turn order 1, 2, 2, ..., 2, 1.
	for n in 30:
		var g := Rules.new_game(rng)
		var seq := []
		var moves := 0
		while g.turn != "done":
			var side: String = g.turn
			var count := 0
			while g.turn == side:
				var m := Rules.choose_move(g, side, rng)
				check(Rules.place_card(g, side, m.card_id, m.row, m.col), "legal move")
				count += 1
				moves += 1
			seq.append(side[0] + str(count))
		check(moves == 24, "24 moves")
		check(" ".join(seq) == "p1 o2 p2 o2 p2 o2 p2 o2 p2 o2 p2 o2 p1", "turn order: " + " ".join(seq))
		var res := Rules.resolve_all(g.player.board, g.opponent.board)
		check(res.battles.size() == 12, "12 battles")

	if failures == 0:
		print("All rules tests passed")
	quit(1 if failures else 0)
