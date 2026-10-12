# Quick Card Game

A two-player elemental card game you play in the browser, against the computer or a friend on the same device.

## Play it

- **On your computer:** download this repo (Code → Download ZIP), unzip it, and double-click `index.html`. No install or build step.
- **Online:** turn on GitHub Pages (Settings → Pages → Deploy from a branch → pick this branch and `/ (root)`), then open the link GitHub shows.

## Playing with a friend

Pick **Opponent → Friend (same device)** at the top. Player 1 places cards on the bottom half and Player 2 on the top half. After each turn the hand is covered so you can pass the device without showing your cards; the next player taps **Show my hand**.

## How it plays

1. You and your opponent take turns placing one card from your hand into one of your empty zones. Each side has **6 front zones** and **6 back zones**. You go first.
2. After placing a card you draw a new one. Each player has a 20-card deck and a 5-card hand.
3. When all 24 zones are full, the cards fight. Each card fights the opposing card in the same spot: front vs front and back vs back, column by column, so there are 12 battles.
4. The higher power wins the battle and scores **1 point**. Most points wins.

### Elements

There are five elements: Fire, Earth, Metal, Water and Wood.

**Adjacency bonus (+2):** a card gets +2 for every touching card on its own side of the element that feeds it.

| Card  | +2 for each adjacent |
|-------|----------------------|
| Wood  | Water |
| Water | Metal |
| Metal | Earth |
| Earth | Fire  |
| Fire  | Wood  |

**Attack advantage (×2):** a card's power is doubled when it attacks the element it beats.

| Attacker | Doubled against |
|----------|-----------------|
| Wood     | Earth |
| Earth    | Water |
| Water    | Fire  |
| Fire     | Metal |
| Metal    | Wood  |

## Choices I made that the original rules didn't specify

These are easy to change, mostly as constants at the top of `game.js`:

- **Card power:** every card has a random power from 1 to 9. Decks have 4 cards of each element.
- **Adjacent** means orthogonal neighbours on your own side: left, right, and the card directly in front of or behind it. Diagonals don't count.
- **Who fights whom:** front cards fight the opposing front card in the same column, and back cards fight the opposing back card in the same column. The back row also boosts the front row through adjacency bonuses.
- **Order of bonuses:** the +2 bonuses are added first, then the ×2 is applied. Both cards in a battle attack each other at the same time, so either one can get the ×2.
- **Ties:** equal power is a tie and nobody scores.
- **Turn order:** you (or Player 1) always go first. Placed cards are face up.
- **Computer opponent:** it tries every card in every empty zone and picks the move that looks best right now.

## Files

- `index.html`, `style.css`, `ui.js` — the page and its interface.
- `game.js` — the rules and the computer opponent, with no browser code.
- `test/rules.test.js` — rules tests. Run with `node test/rules.test.js`.
