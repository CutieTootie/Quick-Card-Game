extends Control
## The whole game screen, built in code so it's easy to read and change.
## Modes: play the computer, two players passing one device, or a friend over Steam.

const AI_DELAY := 0.55
const BATTLE_DELAY := 0.38
const ZONE_SIZE := Vector2(104, 136)
const HAND_CARD_SIZE := Vector2(110, 146)

const COLORS := {
	"bg": Color("14161c"),
	"panel": Color("1e2129"),
	"zone": Color("262a34"),
	"zone_hi": Color("33405a"),
	"line": Color("3a3f4c"),
	"text": Color("ece9e2"),
	"muted": Color("9a9fab"),
	"you": Color("5ac8fa"),
	"cpu": Color("ff7a6b"),
	"win": Color("4cd37d"),
	"x2": Color("ffe066"),
	"Fire": Color("e5533d"),
	"Earth": Color("b8873e"),
	"Metal": Color("9aa6b5"),
	"Water": Color("3b8fe0"),
	"Wood": Color("3fa65a"),
}

enum Mode { CPU, LOCAL, STEAM }

var rng := RandomNumberGenerator.new()
var mode: Mode = Mode.CPU
var game: Dictionary
var game_token := 0 # bumps on every new game so stale timers stop
var selected_id := -1
var results := {} # battle results shown so far, keyed "row-col"
var score := {"player": 0, "opponent": 0}
var busy := false
var hand_hidden := false # same-device mode covers the hand between players

# Steam play
var net: SteamNet
var seat := "player" # which side this computer plays in Steam mode
var round_no := 0
var moves := [] # every move this round, so a late joiner can catch up
var friend := "Friend"

# Nodes
var score_label: Label
var mode_button: OptionButton
var new_button: Button
var status_label: Label
var steam_bar: HBoxContainer
var lobby_panel: PanelContainer
var lobby_list: VBoxContainer
var lobby_msg: Label
var lobby_buttons: Array[Button] = []
var board_box: VBoxContainer
var rows := {} # "top-back" etc -> HBoxContainer
var row_labels := {} # "top-back" etc -> Label
var hand_title: Label
var deck_label: Label
var hand_box: HBoxContainer
var pass_box: VBoxContainer
var pass_label: Label
var rules_dialog: AcceptDialog


func _ready() -> void:
	rng.randomize()
	if net == null: # tests can hand in a stand-in before the scene starts
		net = SteamNet.new()
	if net.get_parent() == null:
		add_child(net)
	_build_ui()
	_connect_steam()
	start_game()


# ---------------------------------------------------------------- UI building

func _label(text: String, size := 16, color: Color = COLORS.text) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _box(color: Color, radius := 8, border := 0, border_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	return s


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_stylebox_override("normal", _box(COLORS.zone, 8, 1, COLORS.line))
	b.add_theme_stylebox_override("hover", _box(COLORS.zone_hi, 8, 1, COLORS.line))
	b.add_theme_stylebox_override("pressed", _box(COLORS.zone_hi, 8, 1, COLORS.you))
	b.add_theme_stylebox_override("disabled", _box(COLORS.panel, 8, 1, COLORS.line))
	for side in ["left", "right"]:
		b.get_theme_stylebox("normal").set("content_margin_" + side, 12)
	return b


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = COLORS.bg
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# Header
	var header := HBoxContainer.new()
	var title := _label("Quick Card Game", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	score_label = _label("", 22)
	header.add_child(score_label)
	root.add_child(header)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	controls.add_child(_label("Opponent", 16, COLORS.muted))
	mode_button = OptionButton.new()
	mode_button.add_theme_font_size_override("font_size", 18)
	mode_button.add_item("Computer", Mode.CPU)
	mode_button.add_item("Friend (same device)", Mode.LOCAL)
	mode_button.add_item("Friend (Steam)", Mode.STEAM)
	mode_button.item_selected.connect(_on_mode_selected)
	controls.add_child(mode_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	var rules_button := _button("Rules")
	rules_button.pressed.connect(func(): rules_dialog.popup_centered(Vector2i(640, 900)))
	controls.add_child(rules_button)
	new_button = _button("New game")
	new_button.pressed.connect(_on_new_pressed)
	controls.add_child(new_button)
	root.add_child(controls)

	# Steam bar, shown while in a Steam game
	steam_bar = HBoxContainer.new()
	steam_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	steam_bar.add_theme_constant_override("separation", 8)
	var invite := _button("Invite a Steam friend")
	invite.pressed.connect(func(): net.invite_friend())
	steam_bar.add_child(invite)
	var leave := _button("Leave game")
	leave.pressed.connect(_leave_steam_game)
	steam_bar.add_child(leave)
	steam_bar.visible = false
	root.add_child(steam_bar)

	status_label = _label("", 20)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 56
	root.add_child(status_label)

	root.add_child(_build_lobby())

	# Board: top player's back row at the top, front rows meet at the battle line.
	board_box = VBoxContainer.new()
	board_box.add_theme_constant_override("separation", 4)
	for key in ["top-back", "top-front", "divider", "bottom-front", "bottom-back"]:
		if key == "divider":
			var d := _label("— battle line —", 14, COLORS.muted)
			d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			board_box.add_child(d)
			continue
		var lbl := _label("", 13, COLORS.muted)
		row_labels[key] = lbl
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		rows[key] = row
		if key.begins_with("top"):
			board_box.add_child(lbl)
			board_box.add_child(row)
		else:
			board_box.add_child(row)
			board_box.add_child(lbl)
	root.add_child(board_box)

	# Hand
	var hand_panel := PanelContainer.new()
	hand_panel.add_theme_stylebox_override("panel", _box(COLORS.panel, 10))
	var hand_v := VBoxContainer.new()
	hand_v.add_theme_constant_override("separation", 8)
	var hand_head := HBoxContainer.new()
	hand_title = _label("Your hand", 18)
	hand_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_head.add_child(hand_title)
	deck_label = _label("", 14, COLORS.muted)
	hand_head.add_child(deck_label)
	hand_v.add_child(hand_head)
	hand_box = HBoxContainer.new()
	hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_box.add_theme_constant_override("separation", 8)
	hand_v.add_child(hand_box)
	pass_box = VBoxContainer.new()
	pass_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pass_label = _label("", 20)
	pass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pass_box.add_child(pass_label)
	var show := _button("Show my hand")
	show.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	show.pressed.connect(func():
		hand_hidden = false
		after_move())
	pass_box.add_child(show)
	pass_box.custom_minimum_size.y = HAND_CARD_SIZE.y
	hand_v.add_child(pass_box)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	pad.add_child(hand_v)
	hand_panel.add_child(pad)
	board_box.add_child(hand_panel)

	# Element cheat sheet
	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.add_theme_font_size_override("normal_font_size", 15)
	legend.text = "[color=#9a9fab]+2 next to:[/color]  " + "   ".join(Rules.ELEMENTS.map(func(e): return "%s ← %s" % [_el(e), _el(Rules.FED_BY[e])])) \
		+ "\n[color=#9a9fab]×2 attacking:[/color]  " + "   ".join(Rules.ELEMENTS.map(func(e): return "%s → %s" % [_el(e), _el(Rules.BEATS[e])]))
	root.add_child(legend)

	_build_rules_dialog()


func _build_lobby() -> PanelContainer:
	lobby_panel = PanelContainer.new()
	lobby_panel.add_theme_stylebox_override("panel", _box(COLORS.panel, 10))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	lobby_panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pad.add_child(v)
	v.add_child(_label("Play a friend on Steam", 22))
	var info := _label("One of you hosts a game. The other joins it from the list, or accepts a Steam invite.", 16, COLORS.muted)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var host := _button("Host a game")
	host.pressed.connect(func():
		lobby_msg.text = "Creating a game…"
		net.host_game())
	buttons.add_child(host)
	var refresh := _button("Refresh list")
	refresh.pressed.connect(_refresh_lobbies)
	buttons.add_child(refresh)
	lobby_buttons = [host, refresh]
	v.add_child(buttons)
	lobby_msg = _label("", 16, COLORS.cpu)
	lobby_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(lobby_msg)
	v.add_child(_label("Games waiting for a player", 15, COLORS.muted))
	lobby_list = VBoxContainer.new()
	lobby_list.add_theme_constant_override("separation", 6)
	v.add_child(lobby_list)
	lobby_panel.visible = false
	return lobby_panel


func _build_rules_dialog() -> void:
	rules_dialog = AcceptDialog.new()
	rules_dialog.title = "How to play"
	rules_dialog.ok_button_text = "Got it"
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.custom_minimum_size = Vector2(580, 760)
	text.add_theme_font_size_override("normal_font_size", 17)
	var fed := "\n".join(Rules.ELEMENTS.map(func(e): return "• %s gets +2 for each adjacent %s" % [_el(e), _el(Rules.FED_BY[e])]))
	var beats := "\n".join(Rules.ELEMENTS.map(func(e): return "• %s is doubled when attacking %s" % [_el(e), _el(Rules.BEATS[e])]))
	text.text = """1. Players take turns placing cards from their hand into their own empty zones: 6 front and 6 back.
2. The first player places 1 card. After that each turn is 2 cards, and the first player's last turn is 1 card.
3. After placing each card you draw a new one.
4. When all 24 zones are full, every card fights the opposing card in the same spot: front vs front, back vs back.
5. Higher power wins the battle and scores 1 point. Ties score nothing. Most points wins.

[b]Element bonuses[/b]
A card gets +2 for every touching card on its side (left, right, and the card directly in front of or behind it) of the element that feeds it:
%s

A card's power is doubled when it attacks the element it beats. Bonuses are added first, then doubled:
%s""" % [fed, beats]
	rules_dialog.add_child(text)
	add_child(rules_dialog)


func _el(e: String) -> String:
	return "[color=#%s]%s[/color]" % [COLORS[e].to_html(false), e]


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_ignore_mouse(c)


## A card face: element colour, power in the middle, element name below.
func _card_face(card: Dictionary, size: Vector2, bonus := 0, fight := "") -> Control:
	var face := Panel.new()
	face.custom_minimum_size = size
	face.add_theme_stylebox_override("panel", _box(COLORS[card.element], 6))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var power := _label(str(card.power), 34, Color.WHITE)
	power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	v.add_child(power)
	var element_label := _label(card.element.to_upper(), 13, Color.WHITE)
	element_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(element_label)
	face.add_child(v)
	if bonus > 0:
		var b := _label("+%d" % bonus, 14, Color.WHITE)
		b.position = Vector2(size.x - 34, 4)
		b.add_theme_stylebox_override("normal", _box(Color(0, 0, 0, 0.35), 4))
		face.add_child(b)
	if fight != "":
		var f := RichTextLabel.new()
		f.bbcode_enabled = true
		f.text = "[center][b]%s[/b][/center]" % fight
		f.add_theme_font_size_override("normal_font_size", 15)
		f.add_theme_font_size_override("bold_font_size", 15)
		f.position = Vector2(0, size.y - 26)
		f.size = Vector2(size.x, 24)
		f.scroll_active = false
		face.add_child(f)
	_ignore_mouse(face)
	return face


# ---------------------------------------------------------------- Who is who

func bottom_side() -> String:
	return seat if mode == Mode.STEAM else "player"


func label_for(side: String) -> String:
	match mode:
		Mode.CPU:
			return "You" if side == "player" else "Computer"
		Mode.LOCAL:
			return "Player 1" if side == "player" else "Player 2"
		_:
			return "You" if side == seat else friend


func rows_label_for(side: String) -> String:
	var n := label_for(side)
	if n == "You":
		return "Your"
	return n if mode == Mode.LOCAL else n + "'s"


func is_human(side: String) -> bool:
	match mode:
		Mode.LOCAL:
			return true
		Mode.STEAM:
			return side == seat
		_:
			return side == "player"


func in_steam_game() -> bool:
	return mode == Mode.STEAM and net.lobby_id != 0


func both_seated() -> bool:
	return mode != Mode.STEAM or net.member_count() >= 2


func hand_side() -> String:
	if mode == Mode.STEAM:
		return seat
	if mode == Mode.LOCAL and game.turn == "opponent":
		return "opponent"
	return "player"


func can_act(side: String) -> bool:
	return not busy and not hand_hidden and both_seated() and game.turn == side and is_human(side)


# ---------------------------------------------------------------- Rendering

func render() -> void:
	var b := bottom_side()
	var t := Rules.other_side(b)
	score_label.text = "%s %d  ·  %s %d" % [label_for(b), score[b], label_for(t), score[t]]

	var in_lobby := mode == Mode.STEAM and net.lobby_id == 0
	lobby_panel.visible = in_lobby
	board_box.visible = not in_lobby
	steam_bar.visible = in_steam_game()
	var done: bool = game.turn == "done" and not busy
	new_button.text = "Play again" if done else "New game"
	new_button.visible = mode != Mode.STEAM or (in_steam_game() and done)
	if in_lobby:
		return

	var sides := {"top": t, "bottom": b}
	for pos in ["top", "bottom"]:
		for row in Rules.ROWS:
			var key: String = pos + "-" + row
			row_labels[key].text = "%s %s" % [rows_label_for(sides[pos]), row]
			var row_box: HBoxContainer = rows[key]
			for c in row_box.get_children():
				c.queue_free()
			for col in Rules.COLS:
				row_box.add_child(_zone(sides[pos], row, col))
	_render_hand()


func _zone(side: String, row: String, col: int) -> Control:
	var board: Dictionary = game[side].board
	var card = board[row][col]
	var zone := Button.new()
	zone.custom_minimum_size = ZONE_SIZE
	zone.focus_mode = Control.FOCUS_NONE
	var border := 0
	var border_color := Color.TRANSPARENT
	var bg: Color = COLORS.zone

	if card != null:
		var fight := ""
		var battle = results.get(row + "-" + str(col))
		if battle != null:
			var mine := side == "player"
			var power: int = battle.player_power if mine else battle.opp_power
			var doubled: bool = battle.p_doubled if mine else battle.o_doubled
			fight = str(power) + (" [color=#ffe066]×2[/color]" if doubled else "")
			if battle.winner == "tie":
				border = 3
				border_color = COLORS.muted
			elif battle.winner == side:
				border = 3
				border_color = COLORS.win
			else:
				zone.modulate = Color(1, 1, 1, 0.4)
		var face := _card_face(card, ZONE_SIZE - Vector2(8, 8), Rules.adjacency_bonus(board, row, col), fight)
		face.position = Vector2(4, 4)
		zone.add_child(face)
		zone.disabled = true
	elif selected_id != -1 and can_act(side):
		# Preview the power the selected card would have here.
		bg = COLORS.zone_hi
		border = 2
		border_color = COLORS.you if side == bottom_side() else COLORS.cpu
		var trial := Rules.clone_board(board)
		trial[row][col] = _find_in_hand(side, selected_id)
		zone.text = str(Rules.board_power(trial, row, col))
		zone.add_theme_font_size_override("font_size", 22)
		zone.add_theme_color_override("font_color", border_color)
		zone.add_theme_color_override("font_hover_color", border_color)
		zone.pressed.connect(place.bind(side, row, col))
	else:
		zone.disabled = true

	var style := _box(bg, 8, border, border_color)
	for state in ["normal", "hover", "pressed", "disabled"]:
		zone.add_theme_stylebox_override(state, style)
	return zone


func _find_in_hand(side: String, id: int):
	for c in game[side].hand:
		if c.id == id:
			return c
	return null


func _render_hand() -> void:
	var side := hand_side()
	var owner := label_for(side)
	hand_title.text = "Your hand" if owner == "You" else owner + "'s hand"
	deck_label.text = "%d cards left in deck" % game[side].deck.size()
	for c in hand_box.get_children():
		c.queue_free()
	var covered: bool = hand_hidden and game.turn != "done"
	pass_box.visible = covered
	hand_box.visible = not covered
	if covered:
		pass_label.text = "Pass the device to %s." % label_for(game.turn)
		return
	var active := can_act(side)
	for card in game[side].hand:
		var b := Button.new()
		b.custom_minimum_size = HAND_CARD_SIZE
		b.focus_mode = Control.FOCUS_NONE
		var chosen: bool = card.id == selected_id
		var style := _box(Color.TRANSPARENT, 8, 3, Color.WHITE if chosen else Color.TRANSPARENT)
		for state in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(state, style)
		var face := _card_face(card, HAND_CARD_SIZE - Vector2(6, 6))
		face.position = Vector2(3, 3)
		b.add_child(face)
		b.disabled = not active
		b.modulate = Color(1, 1, 1, 1.0 if active else 0.6)
		b.pressed.connect(func():
			selected_id = -1 if selected_id == card.id else card.id
			render())
		hand_box.add_child(b)


func set_status(text: String) -> void:
	status_label.text = text


func cards_left() -> String:
	var n: int = max(game.moves_left, 1)
	return "place 1 card" if n == 1 else "place %d cards" % n


# ---------------------------------------------------------------- Game flow

func reset_view() -> void:
	selected_id = -1
	results = {}
	score = {"player": 0, "opponent": 0}
	busy = false
	hand_hidden = false
	game_token += 1


func start_game() -> void:
	game = Rules.new_game(rng)
	reset_view()
	after_move()


func place(side: String, row: String, col: int) -> void:
	if not can_act(side) or selected_id == -1:
		return
	var card_id := selected_id
	if not Rules.place_card(game, side, card_id, row, col):
		return
	selected_id = -1
	if mode == Mode.STEAM:
		moves.append({"card": card_id, "row": row, "col": col})
		net.send({"t": "move", "round": round_no, "n": moves.size() - 1, "card": card_id, "row": row, "col": col})
	# Cover the hand when the device has to change hands.
	if mode == Mode.LOCAL and game.turn != side and game.turn != "done":
		hand_hidden = true
	after_move()


func after_move() -> void:
	if game.turn == "done":
		render()
		start_combat()
	elif mode == Mode.CPU and game.turn == "opponent":
		busy = true
		set_status("Computer is thinking…")
		render()
		var token := game_token
		await get_tree().create_timer(AI_DELAY).timeout
		if token != game_token:
			return
		var m := Rules.choose_move(game, "opponent", rng)
		Rules.place_card(game, "opponent", m.card_id, m.row, m.col)
		busy = false
		after_move()
	elif mode == Mode.STEAM:
		if net.lobby_id == 0:
			set_status("")
		elif not both_seated():
			set_status("Waiting for a friend to join. Use Invite a Steam friend, or have them pick your game from the list.")
		elif game.turn == seat:
			set_status("Your turn: %s. Pick a card from your hand, then an empty zone." % cards_left())
		else:
			set_status("Waiting for %s to play…" % friend)
		render()
	elif hand_hidden:
		set_status("%s's turn: %s." % [label_for(game.turn), cards_left()])
		render()
	elif mode == Mode.CPU:
		set_status("Your turn: %s. Pick a card from your hand, then an empty zone." % cards_left())
		render()
	else:
		var where := "bottom" if game.turn == "player" else "top"
		set_status("%s's turn: %s. Pick a card, then an empty zone on the %s half." % [label_for(game.turn), cards_left(), where])
		render()


func start_combat() -> void:
	busy = true
	var token := game_token
	var full := Rules.resolve_all(game.player.board, game.opponent.board)
	set_status("All zones are full. Fight!")
	for b in full.battles:
		await get_tree().create_timer(BATTLE_DELAY).timeout
		if token != game_token:
			return
		results[b.row + "-" + str(b.col)] = b
		if b.winner != "tie":
			score[b.winner] += 1
		render()
	finish()


func finish() -> void:
	busy = false
	var b := bottom_side()
	var t := Rules.other_side(b)
	var msg: String
	if score.player == score.opponent:
		msg = "It's a draw, %d to %d." % [score.player, score.opponent]
	else:
		var w := b if score[b] > score[t] else t
		var l := Rules.other_side(w)
		if label_for(w) == "You":
			msg = "You win %d to %d!" % [score[w], score[l]]
		else:
			msg = "%s wins %d to %d." % [label_for(w), score[w], score[l]]
	set_status(msg + "  Tap Play again for another round.")
	render()


func _on_new_pressed() -> void:
	if busy:
		return
	if mode == Mode.STEAM:
		# A rematch deals a new round for both players.
		if in_steam_game() and game.turn == "done":
			_start_steam_round(round_no + 1, true)
	else:
		start_game()


func _on_mode_selected(index: int) -> void:
	var picked := mode_button.get_item_id(index) as Mode
	if busy and mode != Mode.STEAM:
		mode_button.select(mode_button.get_item_index(mode))
		return
	if mode == Mode.STEAM and picked != Mode.STEAM:
		net.leave()
	mode = picked
	if mode == Mode.STEAM:
		_open_lobby()
	else:
		start_game()


# ---------------------------------------------------------------- Steam

func _connect_steam() -> void:
	net.lobby_entered.connect(_on_lobby_entered)
	net.lobbies_found.connect(_on_lobbies_found)
	net.message_received.connect(_on_steam_message)
	net.friend_joined.connect(_on_friend_joined)
	net.friend_left.connect(_on_friend_left)
	net.problem.connect(func(text):
		lobby_msg.text = text
		if in_steam_game():
			set_status(text))


func _open_lobby() -> void:
	reset_view()
	game = Rules.new_game(rng)
	for b in lobby_buttons:
		b.disabled = not net.available
	if not net.available:
		lobby_msg.text = net.unavailable_reason
	else:
		lobby_msg.text = ""
		_refresh_lobbies()
	set_status("")
	render()


func _refresh_lobbies() -> void:
	if not net.available:
		lobby_msg.text = net.unavailable_reason
		return
	net.find_games()


func _on_lobbies_found(lobbies: Array) -> void:
	for c in lobby_list.get_children():
		c.queue_free()
	if lobbies.is_empty():
		lobby_list.add_child(_label("No games right now. Host one, or tap Refresh list.", 15, COLORS.muted))
	for l in lobbies:
		var row := HBoxContainer.new()
		var host_label := _label("%s's game" % (l.name if l.name != "" else "Someone"), 18)
		host_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(host_label)
		var join := _button("Join")
		join.pressed.connect(func():
			lobby_msg.text = "Joining…"
			net.join(l.id))
		row.add_child(join)
		lobby_list.add_child(row)


func _on_lobby_entered(_id: int, host: bool) -> void:
	seat = "player" if host else "opponent"
	friend = net.friend_name()
	lobby_msg.text = ""
	if host:
		_start_steam_round(1, false)
	else:
		# Ask the host for the current game; it answers with a sync message.
		reset_view()
		game = Rules.new_game(rng)
		net.send({"t": "hello"})
		set_status("Connecting to %s's game…" % friend)
		render()


func _on_friend_joined(who: String) -> void:
	friend = who
	if net.is_host:
		net.set_open(false)
	after_move()


func _on_friend_left(who: String) -> void:
	if net.is_host:
		net.set_open(true)
	set_status("%s left the game. Invite someone else, or leave and host a new one." % who)
	render()


## Start a round from a shared seed, so both computers deal the same cards.
func _start_steam_round(new_round: int, announce: bool) -> void:
	round_no = new_round
	var deal_seed := rng.randi()
	_deal_from_seed(deal_seed)
	if announce:
		net.send({"t": "round", "round": round_no, "seed": deal_seed})
	after_move()


func _deal_from_seed(deal_seed: int) -> void:
	var dealer := RandomNumberGenerator.new()
	dealer.seed = deal_seed
	game = Rules.new_game(dealer)
	game["seed"] = deal_seed
	moves = []
	reset_view()


func _on_steam_message(data: Dictionary) -> void:
	match data.get("t", ""):
		"hello":
			if net.is_host:
				friend = net.friend_name()
				net.send({"t": "sync", "round": round_no, "seed": game.get("seed", 0), "moves": moves})
				after_move()
		"sync", "round":
			round_no = int(data.round)
			_deal_from_seed(int(data.seed))
			for m in data.get("moves", []):
				_apply_remote_move(m)
			if game.turn == "done":
				start_combat()
			else:
				after_move()
		"move":
			if int(data.round) != round_no or int(data.n) != moves.size():
				return # stale or out of order
			_apply_remote_move(data)
			after_move()


func _apply_remote_move(m: Dictionary) -> void:
	var side: String = game.turn
	if Rules.place_card(game, side, int(m.card), m.row, int(m.col)):
		moves.append({"card": int(m.card), "row": m.row, "col": int(m.col)})


func _leave_steam_game() -> void:
	net.leave()
	_open_lobby()
