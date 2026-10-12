// Core rules for Quick Card Game. No DOM code here, so it can be tested in Node.
(function (root) {
  'use strict';

  const ELEMENTS = ['Fire', 'Earth', 'Metal', 'Water', 'Wood'];
  const COLS = 6;
  const ROWS = ['front', 'back'];
  const HAND_SIZE = 5;
  const DECK_SIZE = 20; // 4 of each element
  const MIN_POWER = 2; // every card starts at 2; widen this range for random power
  const MAX_POWER = 2;
  const ADJACENT_BONUS = 2;
  // Turn order: the first player places FIRST_TURN_CARDS, then players take
  // turns placing CARDS_PER_TURN each. The first player's last turn ends up
  // as a single card, so the order is 1, 2, 2, ..., 2, 1.
  const FIRST_TURN_CARDS = 1;
  const CARDS_PER_TURN = 2;

  // An element gets +2 for every adjacent friendly card of the element listed here.
  const FED_BY = {
    Wood: 'Water',
    Water: 'Metal',
    Metal: 'Earth',
    Earth: 'Fire',
    Fire: 'Wood',
  };

  // An element's power is doubled when it attacks the element listed here.
  const BEATS = {
    Wood: 'Earth',
    Earth: 'Water',
    Water: 'Fire',
    Fire: 'Metal',
    Metal: 'Wood',
  };

  let nextId = 1;

  function randInt(min, max, rng) {
    return min + Math.floor(rng() * (max - min + 1));
  }

  function makeCard(element, power) {
    return { id: nextId++, element, power };
  }

  function makeDeck(rng) {
    rng = rng || Math.random;
    const deck = [];
    for (let i = 0; i < DECK_SIZE; i++) {
      deck.push(makeCard(ELEMENTS[i % ELEMENTS.length], randInt(MIN_POWER, MAX_POWER, rng)));
    }
    // Fisher-Yates shuffle
    for (let i = deck.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      [deck[i], deck[j]] = [deck[j], deck[i]];
    }
    return deck;
  }

  function emptyBoard() {
    return { front: Array(COLS).fill(null), back: Array(COLS).fill(null) };
  }

  // Orthogonal neighbours on the same side: left/right in the row, and the
  // card directly in front of or behind it.
  function neighbours(board, row, col) {
    const out = [];
    if (col > 0) out.push(board[row][col - 1]);
    if (col < COLS - 1) out.push(board[row][col + 1]);
    out.push(board[row === 'front' ? 'back' : 'front'][col]);
    return out.filter(Boolean);
  }

  function adjacencyBonus(board, row, col) {
    const card = board[row][col];
    if (!card) return 0;
    const feeder = FED_BY[card.element];
    return neighbours(board, row, col).filter((c) => c.element === feeder).length * ADJACENT_BONUS;
  }

  // Power on the board before any attack matchup.
  function boardPower(board, row, col) {
    const card = board[row][col];
    if (!card) return 0;
    return card.power + adjacencyBonus(board, row, col);
  }

  // Power when this card attacks the given defender card (bonus first, then doubled).
  function attackPower(board, row, col, defender) {
    const base = boardPower(board, row, col);
    const card = board[row][col];
    if (card && defender && BEATS[card.element] === defender.element) return base * 2;
    return base;
  }

  function isFull(board) {
    return ROWS.every((r) => board[r].every(Boolean));
  }

  function emptySlots(board) {
    const slots = [];
    for (const row of ROWS) {
      for (let col = 0; col < COLS; col++) {
        if (!board[row][col]) slots.push({ row, col });
      }
    }
    return slots;
  }

  // Resolve a single zone: the card in a row/column fights the opposing card
  // in the same row and column. Returns 'player', 'opponent' or 'tie'.
  function resolveBattle(playerBoard, oppBoard, row, col) {
    const p = playerBoard[row][col];
    const o = oppBoard[row][col];
    const pPow = attackPower(playerBoard, row, col, o);
    const oPow = attackPower(oppBoard, row, col, p);
    const pDoubled = !!(p && o && BEATS[p.element] === o.element);
    const oDoubled = !!(p && o && BEATS[o.element] === p.element);
    let winner = 'tie';
    if (pPow > oPow) winner = 'player';
    else if (oPow > pPow) winner = 'opponent';
    return { row, col, playerPower: pPow, oppPower: oPow, pDoubled, oDoubled, winner };
  }

  function resolveAll(playerBoard, oppBoard) {
    const battles = [];
    for (const row of ROWS) {
      for (let col = 0; col < COLS; col++) battles.push(resolveBattle(playerBoard, oppBoard, row, col));
    }
    const score = { player: 0, opponent: 0 };
    for (const b of battles) if (b.winner !== 'tie') score[b.winner]++;
    return { battles, score };
  }

  function newGame(rng) {
    rng = rng || Math.random;
    const g = {
      player: { deck: makeDeck(rng), hand: [], board: emptyBoard() },
      opponent: { deck: makeDeck(rng), hand: [], board: emptyBoard() },
      turn: 'player',
      movesLeft: FIRST_TURN_CARDS, // cards the current player still places this turn
    };
    for (const side of ['player', 'opponent']) {
      for (let i = 0; i < HAND_SIZE; i++) g[side].hand.push(g[side].deck.pop());
    }
    return g;
  }

  // Place a card from `side`'s hand. Returns true on success.
  function placeCard(game, side, cardId, row, col) {
    const s = game[side];
    const idx = s.hand.findIndex((c) => c.id === cardId);
    if (idx < 0 || s.board[row][col]) return false;
    s.board[row][col] = s.hand.splice(idx, 1)[0];
    if (s.deck.length) s.hand.push(s.deck.pop());
    const other = side === 'player' ? 'opponent' : 'player';
    game.movesLeft = (game.movesLeft || 1) - 1;
    if (isFull(game.player.board) && isFull(game.opponent.board)) {
      game.turn = 'done';
      game.movesLeft = 0;
    } else if (game.movesLeft > 0 && !isFull(s.board)) {
      // Same player keeps going.
    } else {
      const next = isFull(game[other].board) ? side : other;
      game.turn = next;
      game.movesLeft = Math.min(CARDS_PER_TURN, emptySlots(game[next].board).length);
    }
    return true;
  }

  function cloneBoard(board) {
    return { front: board.front.slice(), back: board.back.slice() };
  }

  // Rough value of a board position for `me` against `them`. Decided zones
  // count as a point either way; open zones count a little for raw power.
  function evaluate(me, them) {
    let score = 0;
    for (const row of ROWS) {
      for (let col = 0; col < COLS; col++) {
        const mine = me[row][col];
        const theirs = them[row][col];
        if (mine && theirs) {
          const a = attackPower(me, row, col, theirs);
          const b = attackPower(them, row, col, mine);
          score += a > b ? 1 : a < b ? -1 : 0;
          score += (a - b) * 0.02;
        } else if (mine) {
          score += boardPower(me, row, col) * 0.06;
        } else if (theirs) {
          score -= boardPower(them, row, col) * 0.06;
        }
      }
    }
    return score;
  }

  // Simple greedy computer opponent: try every card in every empty zone and
  // keep the move that scores best, with a little noise so games vary.
  function chooseMove(game, side, rng) {
    rng = rng || Math.random;
    const me = game[side];
    const them = game[side === 'player' ? 'opponent' : 'player'];
    let best = null;
    for (const card of me.hand) {
      for (const { row, col } of emptySlots(me.board)) {
        const trial = cloneBoard(me.board);
        trial[row][col] = card;
        const value = evaluate(trial, them.board) + rng() * 0.05;
        if (!best || value > best.value) best = { cardId: card.id, row, col, value };
      }
    }
    return best;
  }

  const api = {
    ELEMENTS, COLS, ROWS, HAND_SIZE, FED_BY, BEATS, ADJACENT_BONUS, FIRST_TURN_CARDS, CARDS_PER_TURN,
    makeDeck, emptyBoard, neighbours, adjacencyBonus, boardPower, attackPower,
    isFull, emptySlots, resolveBattle, resolveAll, newGame, placeCard, chooseMove,
    makeCard,
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.Game = api;
})(this);
