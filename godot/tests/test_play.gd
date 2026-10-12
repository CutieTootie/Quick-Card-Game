extends SceneTree
## Plays full games through the real game screen in every mode.
##   godot --headless --script res://tests/test_play.gd

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func first_empty(board: Dictionary) -> Dictionary:
	return Rules.empty_slots(board)[0]


## Make one move for whoever can act on this screen. Returns true if it moved.
func act(main) -> bool:
	if main.hand_hidden:
		main.hand_hidden = false
		main.after_move()
	for side in ["player", "opponent"]:
		if main.can_act(side):
			main.selected_id = main.game[side].hand[0].id
			var slot := first_empty(main.game[side].board)
			main.place(side, slot.row, slot.col)
			return true
	return false


func wait_until(cond: Callable, seconds: float) -> bool:
	var t := 0.0
	while not cond.call() and t < seconds:
		await create_timer(0.05).timeout
		t += 0.05
	return cond.call()


func finished(main) -> bool:
	return main.game.turn == "done" and not main.busy and main.results.size() == 12


func _init() -> void:
	await process_frame
	var scene: PackedScene = load("res://main.tscn")

	# Computer and same-device modes.
	for mode_index in [0, 1]:
		var main = scene.instantiate()
		root.add_child(main)
		await process_frame
		if mode_index == 1:
			main.mode_button.select(1)
			main._on_mode_selected(1)
		var ok: bool = await wait_until(func(): act(main); return main.game.turn == "done", 30.0)
		check(ok, "mode %d reaches the end" % mode_index)
		check(await wait_until(func(): return finished(main), 15.0), "mode %d battles finish" % mode_index)
		check(main.score.player + main.score.opponent <= 12, "score adds up")
		check("win" in main.status_label.text or "draw" in main.status_label.text, "result shown: " + main.status_label.text)
		check(main.new_button.text == "Play again", "play again offered")
		print("mode %d: %s" % [mode_index, main.status_label.text])
		main.queue_free()
		await process_frame

	# Steam mode with two screens talking through the stand-in.
	var fake = load("res://tests/fake_net.gd")
	var host = scene.instantiate()
	var guest = scene.instantiate()
	host.net = fake.new()
	guest.net = fake.new()
	host.net.peer = guest.net
	guest.net.peer = host.net
	root.add_child(host)
	root.add_child(guest)
	await process_frame
	for m in [host, guest]:
		m.mode_button.select(2)
		m._on_mode_selected(2)
	host.net.host_game()
	guest.net.join(1)
	check(await wait_until(func(): return guest.game.get("seed", -1) == host.game.get("seed", -2), 5.0), "guest gets the host's deal")
	check(host.seat == "player" and guest.seat == "opponent", "seats")
	var order := [] # lambdas capture locals by value, so collect into an array
	var done: bool = await wait_until(func():
		if act(host): order.append("H")
		elif act(guest): order.append("G")
		return host.game.turn == "done" and guest.game.turn == "done", 30.0)
	check(done, "steam game reaches the end")
	check("".join(order) == "HGGHHGGHHGGHHGGHHGGHHGGH", "steam turn order: " + "".join(order))
	check(await wait_until(func(): return finished(host) and finished(guest), 15.0), "both screens finish battles")
	check(host.score.player == guest.score.player and host.score.opponent == guest.score.opponent, "both screens agree on the score")
	print("steam host: ", host.status_label.text)
	print("steam guest: ", guest.status_label.text)
	# Rematch from the guest.
	guest._on_new_pressed()
	check(await wait_until(func(): return host.round_no == 2 and host.game.get("seed") == guest.game.get("seed"), 5.0), "rematch reaches the host")

	if failures == 0:
		print("All play tests passed")
	quit(1 if failures else 0)
