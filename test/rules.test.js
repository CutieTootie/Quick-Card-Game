// Run with: node test/rules.test.js
const assert = require('assert');
const G = require('../game.js');

function board(cells) {
  const b = G.emptyBoard();
  for (const [row, col, element, power] of cells) b[row][col] = G.makeCard(element, power);
  return b;
}

// Wood gets +2 for each adjacent Water (left, right, behind), not diagonal.
let b = board([
  ['front', 2, 'Wood', 5],
  ['front', 1, 'Water', 1],
  ['front', 3, 'Water', 1],
  ['back', 2, 'Water', 1],
  ['back', 1, 'Water', 1], // diagonal: no bonus
]);
assert.strictEqual(G.boardPower(b, 'front', 2), 11);

// Every element's feeder gives +2.
for (const el of G.ELEMENTS) {
  b = board([['front', 0, el, 3], ['front', 1, G.FED_BY[el], 1]]);
  assert.strictEqual(G.boardPower(b, 'front', 0), 5, el);
}

// Doubling happens after the bonus.
const p = board([['front', 0, 'Fire', 4], ['back', 0, 'Wood', 1]]); // Fire 4 + 2 = 6
const o = board([['front', 0, 'Metal', 10], ['back', 0, 'Metal', 1]]);
let r = G.resolveBattle(p, o, 'front', 0);
assert.deepStrictEqual([r.playerPower, r.oppPower, r.winner, r.pDoubled], [12, 10, 'player', true]);

// Ties score nothing.
const t1 = board([['front', 0, 'Fire', 5]]);
const t2 = board([['front', 0, 'Fire', 5]]);
assert.strictEqual(G.resolveBattle(t1, t2, 'front', 0).winner, 'tie');

// Full game with the AI on both sides ends with 12 battles.
for (let n = 0; n < 50; n++) {
  const g = G.newGame();
  let moves = 0;
  while (g.turn !== 'done') {
    const m = G.chooseMove(g, g.turn);
    assert.ok(G.placeCard(g, g.turn, m.cardId, m.row, m.col));
    moves++;
  }
  assert.strictEqual(moves, 24);
  const res = G.resolveAll(g.player.board, g.opponent.board);
  assert.strictEqual(res.battles.length, 12);
  assert.ok(res.score.player + res.score.opponent <= 12);
}

// Turn order is 1, 2, 2, ..., 2, 1 (player goes first).
{
  const g = G.newGame();
  const seq = [];
  while (g.turn !== 'done') {
    const side = g.turn;
    let n = 0;
    while (g.turn === side) {
      const m = G.chooseMove(g, side);
      G.placeCard(g, side, m.cardId, m.row, m.col);
      n++;
    }
    seq.push(side[0] + n);
  }
  assert.strictEqual(seq.join(' '), 'p1 o2 p2 o2 p2 o2 p2 o2 p2 o2 p2 o2 p1');
}

console.log('All rules tests passed');
