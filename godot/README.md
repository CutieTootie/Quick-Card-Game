# Quick Card Game for Godot

The same game as the browser version, rebuilt for **Godot 4.7.2**. It has the same rules, the same 1, 2, 2, …, 2, 1 turn order, and every card starts at 2 power.

## Play it

1. Install [Godot 4.7.2](https://godotengine.org/download) (the standard version, not .NET).
2. In the Godot Project Manager, click **Import**, pick the `project.godot` file in this folder, and open it.
3. Press **F5** (or the Play button at the top right).

Pick your opponent at the top: **Computer**, **Friend (same device)**, or **Friend (Steam)**.

## Steam play

Steam play uses **Spacewar**, Valve's free test app (app ID **480**), so you can try it on Steam before the game has its own Steam page. Both players need:

1. **Steam open and signed in.**
2. **The GodotSteam add-on** in the project. In Godot, open the **AssetLib** tab at the top, search for **GodotSteam GDExtension**, pick the version made for your Godot version, then click **Download** and **Install**. Restart the editor when it asks.

Then pick **Friend (Steam)**. One player taps **Host a game**. The other taps **Refresh list** and **Join**, or the host uses **Invite a Steam friend** to send an invite through the Steam overlay. While you play, Steam shows you as playing "Spacewar". That's expected with the test app ID.

How it works: the host deals the cards from a random seed and sends the seed to the other player through the Steam lobby chat, so both computers deal the same game. After that, each move is a small message in the lobby chat. Lobbies are tagged `quick-card-game`, so you only see games for this project and not other Spacewar test games.

Without GodotSteam or without Steam running, the game still works. The Steam screen just explains what's missing.

### When the game gets its own Steam app

Change `APP_ID` in `steam_net.gd` and the number in `steam_appid.txt` to your app ID. You get one by signing up for Steamworks and paying the Steam Direct fee.

## Exporting

Use **Project → Export**. The first time, Godot asks you to download export templates. While you're still testing with Spacewar, put `steam_appid.txt` next to the exported game.

## Files

- `rules.gd`: the rules and the computer opponent, with no screen code. The constants at the top (power, turn order, deck size) are the ones to tweak.
- `main.gd` and `main.tscn`: the game screen, built in code.
- `steam_net.gd`: Steam lobbies and messages through GodotSteam.
- `tests/`: run `godot --headless --path . --script res://tests/test_rules.gd` and `godot --headless --path . --script res://tests/test_play.gd`. The play test plays full games in every mode, with a stand-in for Steam.
