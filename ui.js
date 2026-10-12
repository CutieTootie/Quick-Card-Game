(function () {
  'use strict';

  const G = window.Game;
  const ICONS = { Fire: '🔥', Earth: '⛰️', Metal: '⚙️', Water: '💧', Wood: '🌳' };
  const AI_DELAY = 550;
  const BATTLE_DELAY = 380;
  const CODE_LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I or O, they look like 1 and 0

  // 'cpu' = play the computer. 'local' = two people pass one device back and forth.
  // 'online' = two devices share one game through the page's shared storage.
  let mode = 'cpu';
  let game;
  let selectedId = null;
  let lastPlaced = null; // "side-row-col" for the drop animation
  let results = null; // battle results once combat has started
  let busy = false;
  let handHidden = false; // in local mode, the hand stays covered until the next player taps

  // Online state. `db` is null when this page isn't running somewhere that offers shared storage.
  const online = {
    db: null, ref: null, unsub: null, code: null, seat: null, seats: null, round: 0, foughtRound: 0,
    status: 'off', // 'off' (not inside Claude), 'connecting', 'ready', 'unavailable', 'read-only'
    roomsUnsub: null, openRooms: [],
  };
  const OPEN_ROOM_MAX_AGE = 30 * 60 * 1000;
  const clientId = loadClientId();

  const $ = (id) => document.getElementById(id);
  const statusEl = $('status');
  const handEl = $('hand');
  const other = (side) => (side === 'player' ? 'opponent' : 'player');

  function loadClientId() {
    // Per tab, so two tabs on one computer count as two players.
    try {
      let id = sessionStorage.getItem('qcg-client');
      if (!id) {
        id = Math.random().toString(36).slice(2, 12);
        sessionStorage.setItem('qcg-client', id);
      }
      return id;
    } catch (e) {
      return Math.random().toString(36).slice(2, 12);
    }
  }

  // The side drawn at the bottom of the screen: always your own when online.
  const bottomSide = () => (mode === 'online' && online.seat ? online.seat : 'player');
  const inRoom = () => mode === 'online' && !!online.ref;

  function label(side) {
    if (mode === 'cpu') return side === 'player' ? 'You' : 'Computer';
    if (mode === 'local') return side === 'player' ? 'Player 1' : 'Player 2';
    return side === bottomSide() ? 'You' : 'Friend';
  }

  function rowsLabel(side) {
    const name = label(side);
    if (name === 'You') return 'Your';
    return mode === 'local' ? name : `${name}'s`;
  }

  function isHuman(side) {
    if (mode === 'local') return true;
    if (mode === 'online') return side === online.seat;
    return side === 'player';
  }

  function bothSeated() {
    return mode !== 'online' || !!(online.seats && online.seats.player && online.seats.opponent);
  }

  // Whose hand is shown.
  function handSide() {
    if (mode === 'online') return online.seat;
    if (mode === 'local' && game.turn === 'opponent') return 'opponent';
    return 'player';
  }

  function canAct(side) {
    return !busy && !handHidden && bothSeated() && game.turn === side && isHuman(side);
  }

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
    } else if (selectedId !== null && canAct(side)) {
      z.classList.add('target');
      if (side !== bottomSide()) z.classList.add('opp-target');
      // Preview the power the selected card would have here.
      const card = game[side].hand.find((c) => c.id === selectedId);
      const trial = { front: board.front.slice(), back: board.back.slice() };
      trial[row][col] = card;
      z.innerHTML = `<span class="preview">${G.boardPower(trial, row, col)}</span>`;
      z.addEventListener('click', () => place(side, row, col));
    }
    return z;
  }

  function renderBoard() {
    const sides = { bottom: bottomSide(), top: other(bottomSide()) };
    for (const pos of ['bottom', 'top']) {
      for (const row of G.ROWS) {
        const rowEl = $(`${pos}-${row}`);
        rowEl.innerHTML = '';
        for (let col = 0; col < G.COLS; col++) rowEl.appendChild(zoneEl(sides[pos], row, col));
      }
    }
  }

  function renderHand() {
    const side = handSide();
    const owner = label(side) === 'You' ? 'Your' : `${label(side)}'s`;
    $('hand-title').textContent = `${owner} hand`;
    $('deck-count').textContent = `${game[side].deck.length} cards left in deck`;

    const covered = handHidden && game.turn !== 'done';
    $('pass').hidden = !covered;
    handEl.hidden = covered;
    if (covered) {
      $('pass-text').textContent = `Pass the device to ${label(game.turn)}.`;
      handEl.innerHTML = '';
      return;
    }

    handEl.innerHTML = game[side].hand.map((c) => cardHtml(c)).join('');
    handEl.classList.toggle('disabled', !canAct(side));
    for (const el of handEl.querySelectorAll('.card')) {
      const id = Number(el.dataset.id);
      if (id === selectedId) el.classList.add('selected');
      el.addEventListener('click', () => {
        if (!canAct(side)) return;
        selectedId = selectedId === id ? null : id;
        render();
      });
    }
  }

  function renderChrome() {
    const b = bottomSide();
    const t = other(b);
    $('name-bottom').textContent = label(b);
    $('name-top').textContent = label(t);
    for (const el of document.querySelectorAll('.who-bottom')) el.textContent = rowsLabel(b);
    for (const el of document.querySelectorAll('.who-top')) el.textContent = rowsLabel(t);
    const s = results ? results.score : { player: 0, opponent: 0 };
    $('score-bottom').textContent = s[b];
    $('score-top').textContent = s[t];

    const lobby = mode === 'online' && !online.ref;
    $('lobby').hidden = !lobby;
    $('table').hidden = lobby;
    $('roombar').hidden = !inRoom();
    $('room-code').textContent = online.code || '';
    $('btn-new').hidden = mode === 'online';
  }

  function render() {
    renderChrome();
    if (mode === 'online' && !online.ref) return;
    renderBoard();
    renderHand();
  }

  function setStatus(html) {
    statusEl.innerHTML = html;
  }

  function place(side, row, col) {
    if (!canAct(side) || selectedId === null) return;
    if (!G.placeCard(game, side, selectedId, row, col)) return;
    lastPlaced = `${side}-${row}-${col}`;
    selectedId = null;
    // Cover the hand when the device has to change hands.
    if (mode === 'local' && game.turn !== side && game.turn !== 'done') handHidden = true;
    if (mode === 'online') pushState();
    afterMove();
  }

  function afterMove() {
    if (game.turn === 'done') {
      render();
      startCombat();
    } else if (mode === 'cpu' && game.turn === 'opponent') {
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
    } else if (mode === 'online') {
      if (!bothSeated()) setStatus(`Send your friend the room code <b>${online.code}</b>. Waiting for them to join…`);
      else if (game.turn === online.seat) setStatus('Your turn: pick a card from your hand, then an empty zone.');
      else setStatus('Waiting for your friend to play…');
      render();
    } else if (handHidden) {
      setStatus(`${label(game.turn)}'s turn.`);
      render();
    } else if (mode === 'cpu') {
      setStatus('Your turn: pick a card from your hand, then an empty zone.');
      render();
    } else {
      const where = game.turn === 'player' ? 'bottom' : 'top';
      setStatus(`${label(game.turn)}'s turn: pick a card, then an empty zone on the ${where} half.`);
      render();
    }
  }

  function startCombat() {
    busy = true;
    lastPlaced = null;
    const token = game; // stop if a new game replaces this one mid-fight
    if (mode === 'online') online.foughtRound = online.round;
    const full = G.resolveAll(game.player.board, game.opponent.board);
    results = { shown: new Map(), score: { player: 0, opponent: 0 } };
    setStatus('All zones are full. Fight!');
    let i = 0;
    const step = () => {
      if (token !== game) return;
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
    const b = bottomSide();
    const t = other(b);
    let msg;
    if (score.player === score.opponent) msg = `It's a draw, ${score.player} to ${score.opponent}.`;
    else {
      const w = score[b] > score[t] ? b : t;
      const l = other(w);
      msg = label(w) === 'You' ? `You win ${score[w]} to ${score[l]}! 🎉` : `${label(w)} wins ${score[w]} to ${score[l]}.`;
      if (mode === 'local') msg = `${label(w)} wins ${score[w]} to ${score[l]}! 🎉`;
    }
    setStatus(`<span class="big-result">${msg} <button id="btn-again" type="button">Play again</button></span>`);
    $('btn-again').addEventListener('click', () => (mode === 'online' ? rematch() : start()));
    render();
  }

  function resetView() {
    selectedId = null;
    lastPlaced = null;
    results = null;
    busy = false;
    handHidden = false;
  }

  function start() {
    game = G.newGame();
    resetView();
    afterMove();
  }

  // ---- Online play ----

  function showLobby(msg) {
    $('lobby-msg').textContent = msg || '';
    setStatus('');
    watchOpenRooms();
    renderLobby();
    render();
  }

  const NO_ACCESS = "You can't play online on this link yet. Ask the person who shared it to give you Editor access, then reload the page.";

  function renderLobby() {
    const ready = online.status === 'ready';
    $('btn-create').disabled = !ready;
    $('join-code').disabled = !ready;
    $('join-form').querySelector('button').disabled = !ready;
    const info = {
      connecting: 'Connecting…',
      unavailable: "Online play isn't working on this device. Make sure you're signed in to Claude and opened the shared link, then reload the page.",
      'read-only': NO_ACCESS,
    }[online.status];
    if (info) $('lobby-msg').textContent = info;

    const list = $('open-rooms');
    const rooms = ready ? online.openRooms : [];
    list.hidden = rooms.length === 0;
    list.innerHTML = rooms.length ? '<h3>Rooms waiting for a player</h3>' : '';
    for (const r of rooms) {
      const mins = Math.max(0, Math.round((Date.now() - r.updatedAt) / 60000));
      const row = document.createElement('div');
      row.className = 'open-room';
      row.innerHTML = `<span><b>${r.code}</b> <span class="muted">made ${mins ? mins + ' min ago' : 'just now'}</span></span>`;
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.textContent = 'Join';
      btn.addEventListener('click', () => joinRoom(r.code));
      row.appendChild(btn);
      list.appendChild(row);
    }
  }

  // Live list of rooms someone else made that still need a second player.
  function watchOpenRooms() {
    if (online.roomsUnsub || online.status !== 'ready') return;
    try {
      online.roomsUnsub = online.db.collection('games').orderBy('updatedAt', 'desc').limit(20).onSnapshot((snap) => {
        online.openRooms = snap.docs
          .map((d) => d.data())
          .filter((r) => r && r.seats && !r.seats.opponent && r.seats.player !== clientId && Date.now() - (r.updatedAt || 0) < OPEN_ROOM_MAX_AGE);
        if (mode === 'online' && !online.ref) renderLobby();
      }, () => { online.roomsUnsub = null; });
    } catch (e) {
      online.roomsUnsub = null;
    }
  }

  function stopWatchingRooms() {
    if (online.roomsUnsub) online.roomsUnsub();
    online.roomsUnsub = null;
  }

  function writeError(e) {
    const code = e && e.code ? ` (${e.code})` : '';
    if (e && (e.code === 'invalid_argument' || e.code === 'not_granted' || e.code === 'revoked')) return NO_ACCESS + code;
    return `Something went wrong talking to the game. Please try again.${code}`;
  }

  async function pushState() {
    try {
      await online.ref.set({
        code: online.code,
        seats: online.seats,
        state: game,
        round: online.round,
        updatedAt: Date.now(),
      });
    } catch (e) {
      setStatus(writeError(e));
    }
  }

  function makeCode() {
    let code = '';
    for (let i = 0; i < 4; i++) code += CODE_LETTERS[Math.floor(Math.random() * CODE_LETTERS.length)];
    return code;
  }

  async function createRoom() {
    $('lobby-msg').textContent = 'Creating a room…';
    try {
      let code;
      let ref;
      for (let tries = 0; tries < 5; tries++) {
        code = makeCode();
        ref = online.db.doc(`games/${code}`);
        const snap = await ref.get();
        // Reuse codes from rooms nobody has touched for a day.
        if (!snap.exists || Date.now() - (snap.data().updatedAt || 0) > 86400000) break;
      }
      game = G.newGame();
      const seats = { player: clientId, opponent: null };
      await ref.set({ code, seats, state: game, round: 1, updatedAt: Date.now() });
      enterRoom(ref, code, 'player');
    } catch (e) {
      showLobby(writeError(e));
    }
  }

  async function joinRoom(code) {
    code = code.trim().toUpperCase();
    if (!/^[A-Z]{4}$/.test(code)) return showLobby('Room codes are 4 letters.');
    $('lobby-msg').textContent = 'Joining…';
    try {
      const ref = online.db.doc(`games/${code}`);
      const snap = await ref.get();
      if (!snap.exists) return showLobby(`There's no room with the code ${code}. Check the code, or pick the room from the list.`);
      const seats = snap.data().seats || {};
      let seat;
      if (seats.player === clientId) seat = 'player';
      else if (seats.opponent === clientId) seat = 'opponent';
      else if (!seats.opponent) {
        await ref.update({ seats: { opponent: clientId }, updatedAt: Date.now() });
        seat = 'opponent';
      } else return showLobby('That room already has two players.');
      enterRoom(ref, code, seat);
    } catch (e) {
      showLobby(writeError(e));
    }
  }

  function enterRoom(ref, code, seat) {
    online.ref = ref;
    online.code = code;
    online.seat = seat;
    online.round = 0;
    online.foughtRound = 0;
    $('lobby-msg').textContent = '';
    stopWatchingRooms();
    if (online.unsub) online.unsub();
    online.unsub = ref.onSnapshot(onRoomSnapshot, () => {
      leaveRoom();
      showLobby('Lost the connection to the room. Try joining again.');
    });
  }

  // Find the zone the other player just filled, for the drop animation.
  function findNewCard(prev, next, side) {
    if (!prev) return null;
    for (const row of G.ROWS) {
      for (let col = 0; col < G.COLS; col++) {
        if (!prev[side].board[row][col] && next[side].board[row][col]) return `${side}-${row}-${col}`;
      }
    }
    return null;
  }

  function onRoomSnapshot(snap) {
    if (mode !== 'online' || !online.ref) return;
    if (!snap.exists) {
      leaveRoom();
      return showLobby('That room was closed.');
    }
    const data = snap.data();
    const next = JSON.parse(JSON.stringify(data.state)); // snapshots are frozen
    online.seats = data.seats;
    if (data.round !== online.round) {
      online.round = data.round;
      resetView();
      game = next;
    } else {
      if (busy) return; // still showing the battles
      const placed = findNewCard(game, next, other(online.seat));
      game = next;
      if (placed) lastPlaced = placed;
    }
    if (game.turn === 'done' && online.foughtRound === online.round) return;
    afterMove();
  }

  async function rematch() {
    online.round += 1;
    game = G.newGame();
    resetView();
    afterMove();
    await pushState();
  }

  function leaveRoom() {
    if (online.unsub) online.unsub();
    // Close a room you made that nobody joined, so it stops showing in the list.
    if (online.ref && online.seat === 'player' && online.seats && !online.seats.opponent) {
      online.ref.delete().catch(() => {});
    }
    Object.assign(online, { ref: null, unsub: null, code: null, seat: null, seats: null, round: 0, foughtRound: 0 });
    resetView();
  }

  async function detectOnline() {
    if (!window.claude || typeof window.claude.use !== 'function') return;
    // Inside Claude: offer the option right away and explain in the lobby if it can't work.
    const opt = document.createElement('option');
    opt.value = 'online';
    opt.textContent = 'Friend (online)';
    $('mode').appendChild(opt);
    online.status = 'connecting';
    try {
      online.db = await window.claude.use('db');
    } catch (e) {
      online.db = null;
    }
    if (!online.db) {
      online.status = 'unavailable';
    } else {
      let canWrite = null;
      try {
        const user = await window.claude.use('user');
        if (user) canWrite = await user.can('data.write');
      } catch (e) {
        canWrite = null;
      }
      online.status = canWrite === false ? 'read-only' : 'ready';
    }
    if (mode === 'online' && !online.ref) showLobby();
  }

  // ---- Wiring ----

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
  $('btn-show').addEventListener('click', () => {
    handHidden = false;
    afterMove();
  });
  $('mode').addEventListener('change', (e) => {
    if (busy && mode !== 'online') { e.target.value = mode; return; }
    leaveRoom();
    stopWatchingRooms();
    mode = e.target.value;
    if (mode === 'online') showLobby();
    else start();
  });
  $('btn-create').addEventListener('click', createRoom);
  $('join-form').addEventListener('submit', (e) => {
    e.preventDefault();
    joinRoom($('join-code').value);
  });
  $('btn-leave').addEventListener('click', () => {
    leaveRoom();
    showLobby();
  });

  fillRules();
  start();
  detectOnline();
})();
