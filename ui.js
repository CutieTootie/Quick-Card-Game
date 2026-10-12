(function () {
  'use strict';

  const G = window.Game;
  const ICONS = { Fire: '🔥', Earth: '⛰️', Metal: '⚙️', Water: '💧', Wood: '🌳' };
  const AI_DELAY = 550;
  const BATTLE_DELAY = 380;

  const $ = (id) => document.getElementById(id);
  const statusEl = $('status');
  const handEl = $('hand');

  let game;
  let selectedId = null;
  let lastPlaced = null; // "side-row-col" for the drop animation
  let results = null; // battle results once combat has started
  let busy = false;

  function elTag(el) {
    return `<span class="el-tag" style="color:var(--${el})">${ICONS[el]} ${el}</span>`;
  }

  function cardHtml(card, extra) {
    extra = extra || '';
    return `<div class="card" data-id="${card.id}" style="--el:var(--${card.element})">
      <span class="icon">${ICONS[card.element]}</span>
      <span class="power">${card.power}</span>
      <span class="name">${card.element}</span>${extra}
    </div>`;
  }

  function zoneEl(side, row, col) {
    const z = document.createElement('div');
    z.className = 'zone';
    z.dataset.side = side;
    z.dataset.row = row;
    z.dataset.col = col;
    const board = game[side].board;
    const card = board[row][col];

    if (card) {
      let extra = '';
      const bonus = G.adjacencyBonus(board, row, col);
      if (bonus) extra += `<span class="bonus">+${bonus}</span>`;
      const battle = results && results.shown.get(`${row}-${col}`);
      if (battle) {
        const mine = side === 'player';
        const pow = mine ? battle.playerPower : battle.oppPower;
        const doubled = mine ? battle.pDoubled : battle.oDoubled;
        extra += `<span class="fight">${pow}${doubled ? ' <span class="x2">×2</span>' : ''}</span>`;
        const won = battle.winner === side;
        z.classList.add(battle.winner === 'tie' ? 'tied' : won ? 'won' : 'lost');
      }
      z.innerHTML = cardHtml(card, extra);
      if (lastPlaced === `${side}-${row}-${col}`) z.classList.add('just-placed');
    } else if (side === 'player' && selectedId !== null && game.turn === 'player' && !busy) {
      z.classList.add('target');
      // Preview the power the selected card would have here.
      const card = game.player.hand.find((c) => c.id === selectedId);
      const trial = { front: board.front.slice(), back: board.back.slice() };
      trial[row][col] = card;
      z.innerHTML = `<span class="preview">${G.boardPower(trial, row, col)}</span>`;
      z.addEventListener('click', () => playerPlace(row, col));
    }
    return z;
  }

  function renderBoard() {
    for (const side of ['player', 'opponent']) {
      for (const row of G.ROWS) {
        const rowEl = $(`${side}-${row}`);
        rowEl.innerHTML = '';
        for (let col = 0; col < G.COLS; col++) rowEl.appendChild(zoneEl(side, row, col));
      }
    }
  }

  function renderHand() {
    handEl.innerHTML = game.player.hand.map((c) => cardHtml(c)).join('');
    handEl.classList.toggle('disabled', game.turn !== 'player' || busy);
    for (const el of handEl.querySelectorAll('.card')) {
      const id = Number(el.dataset.id);
      if (id === selectedId) el.classList.add('selected');
      el.addEventListener('click', () => {
        if (game.turn !== 'player' || busy) return;
        selectedId = selectedId === id ? null : id;
        render();
      });
    }
    $('deck-count').textContent = `${game.player.deck.length} cards left in deck`;
  }

  function renderScore() {
    const s = results ? results.score : { player: 0, opponent: 0 };
    $('score-player').textContent = s.player;
    $('score-opponent').textContent = s.opponent;
  }

  function render() {
    renderBoard();
    renderHand();
    renderScore();
  }

  function setStatus(html) {
    statusEl.innerHTML = html;
  }

  function playerPlace(row, col) {
    if (busy || game.turn !== 'player' || selectedId === null) return;
    if (!G.placeCard(game, 'player', selectedId, row, col)) return;
    lastPlaced = `player-${row}-${col}`;
    selectedId = null;
    afterMove();
  }

  function afterMove() {
    if (game.turn === 'done') {
      render();
      startCombat();
    } else if (game.turn === 'opponent') {
      busy = true;
      setStatus('Computer is thinking…');
      render();
      setTimeout(() => {
        const move = G.chooseMove(game, 'opponent');
        G.placeCard(game, 'opponent', move.cardId, move.row, move.col);
        lastPlaced = `opponent-${move.row}-${move.col}`;
        busy = false;
        afterMove();
      }, AI_DELAY);
    } else {
      setStatus('Your turn: pick a card from your hand, then an empty zone.');
      render();
    }
  }

  function startCombat() {
    busy = true;
    lastPlaced = null;
    const full = G.resolveAll(game.player.board, game.opponent.board);
    results = { shown: new Map(), score: { player: 0, opponent: 0 } };
    setStatus('All zones are full. Fight!');
    let i = 0;
    const step = () => {
      if (i >= full.battles.length) return finish(full.score);
      const b = full.battles[i++];
      results.shown.set(`${b.row}-${b.col}`, b);
      if (b.winner !== 'tie') results.score[b.winner]++;
      render();
      for (const side of ['player', 'opponent']) {
        const z = document.querySelector(`.zone[data-side="${side}"][data-row="${b.row}"][data-col="${b.col}"]`);
        if (z) z.classList.add('fighting');
      }
      setTimeout(step, BATTLE_DELAY);
    };
    setTimeout(step, BATTLE_DELAY);
  }

  function finish(score) {
    busy = false;
    let msg;
    if (score.player > score.opponent) msg = `You win ${score.player} to ${score.opponent}! 🎉`;
    else if (score.player < score.opponent) msg = `Computer wins ${score.opponent} to ${score.player}.`;
    else msg = `It's a draw, ${score.player} to ${score.opponent}.`;
    setStatus(`<span class="big-result">${msg} <button id="btn-again" type="button">Play again</button></span>`);
    $('btn-again').addEventListener('click', start);
    render();
  }

  function start() {
    game = G.newGame();
    selectedId = null;
    lastPlaced = null;
    results = null;
    busy = false;
    afterMove();
  }

  function fillRules() {
    const fed = G.ELEMENTS.map((e) => `${elTag(e)} ← ${elTag(G.FED_BY[e])}`);
    const beats = G.ELEMENTS.map((e) => `${elTag(e)} → ${elTag(G.BEATS[e])}`);
    $('legend-fed').innerHTML = fed.join(' &nbsp; ');
    $('legend-beats').innerHTML = beats.join(' &nbsp; ');
    $('rules-fed').innerHTML = G.ELEMENTS.map((e) => `<li>${elTag(e)} gets +2 for each adjacent ${elTag(G.FED_BY[e])}</li>`).join('');
    $('rules-beats').innerHTML = G.ELEMENTS.map((e) => `<li>${elTag(e)} is doubled when attacking ${elTag(G.BEATS[e])}</li>`).join('');
  }

  $('btn-new').addEventListener('click', () => { if (!busy) start(); });
  $('btn-rules').addEventListener('click', () => $('rules').showModal());

  fillRules();
  start();
})();
