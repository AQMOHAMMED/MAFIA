const express = require('express');
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const { Server } = require('socket.io');
const db = require('./db');
const makeApi = require('./api');
const { userByToken, avatarUrl } = require('./api');

const app = express();
const server = http.createServer(app);
const io = new Server(server);

app.set('trust proxy', 1);
app.use(express.static(path.join(__dirname, 'public')));

// الأدوار المتاحة — team: mafia | town
const ROLES = {
  mafiaSheikh: { team: 'mafia' },
  mafiaGirl: { team: 'mafia' },
  mafiaBoy: { team: 'mafia' },
  mafia: { team: 'mafia' },
  townSheikh: { team: 'town' },
  doctor: { team: 'town' },
  sniper: { team: 'town' },
  townBoy: { team: 'town' },
  citizen: { team: 'town' },
};
const teamOf = p => ROLES[p.role].team;

/* ---------- مين متصل من الحسابات ---------- */
const userSockets = new Map(); // uid -> Set(socketId)
const userRoom = new Map();    // uid -> room code
function presence(uid) {
  const online = (userSockets.get(uid) || new Set()).size > 0;
  const code = userRoom.get(uid);
  const r = code && rooms.get(code);
  return { online, playing: online && !!r && r.phase === 'playing' };
}
presence.notify = (uid, kind, data) => {
  for (const sid of userSockets.get(uid) || []) io.to(sid).emit('notify', { kind, ...(data || {}) });
};
app.use('/api', makeApi(presence));

const rooms = new Map(); // code -> room

function makeCode() {
  let code;
  do code = String(crypto.randomInt(1000, 10000));
  while (rooms.has(code));
  return code;
}

function shuffle(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function playingPlayers(room) {
  // أثناء اللعب: اللي معهم كروت. بالغرفة: الكل ما عدا الهوست الثابت
  if (room.phase !== 'lobby') return room.players.filter(p => p.role);
  return room.players.filter(p => !(room.hostMode === 'fixed' && p.id === room.leaderId));
}
const alivePlayers = room => room.players.filter(p => p.role && !p.surrendered);

// إذا الليدر طلع أو انقطع، بننقل القيادة لأول لاعب متصل
function passLeader(room) {
  const next = room.players.find(p => p.online && p.id !== room.leaderId);
  if (!next) return false;
  room.leaderId = next.id;
  return true;
}

// مين بيتحكم بالليل: الهوست، وإذا لسا ما في هوست (أو مش متصل) الليدر
function controllerId(room) {
  const h = room.hostId && room.players.find(p => p.id === room.hostId);
  return h && h.online ? h.id : room.leaderId;
}

function newFacts() {
  return { saves: 0, protects: 0, snipeMafia: 0, snipeTown: 0, kills: 0, found: 0, silenced: 0, pulled: 0 };
}

function publicState(room) {
  const ended = room.phase === 'ended';
  const night = room.stage === 'night' && room.night;
  return {
    code: room.code,
    size: room.size,
    roles: room.roles,
    hostMode: room.hostMode,
    hostId: room.hostId,
    leaderId: room.leaderId,
    controllerId: room.phase === 'playing' ? controllerId(room) : null,
    phase: room.phase,
    startedAt: room.startedAt || null,
    stage: room.stage,
    nightNo: room.nightNo,
    dayNo: room.dayNo,
    winner: room.winner,
    pendingPull: room.pendingPull ? room.players.find(p => p.id === room.pendingPull)?.name || null : null,
    silenced: room.silenced || null,
    progress: night ? { done: Object.keys(room.night.picks).length, total: alivePlayers(room).length,
      who: Object.keys(room.night.picks) } : null,
    morning: room.morning,
    players: room.players.map(p => ({
      id: p.id,
      name: p.name,
      avatar: p.avatar || null,
      uid: p.uid || null,
      online: p.online,
      playing: !!p.role,
      surrendered: p.surrendered,
      outReason: p.outReason || null,
      // الفريق يظهر فقط بعد ما يطلع اللاعب
      team: p.surrendered && p.role ? teamOf(p) : null,
    })),
    log: room.log,
    gameId: ended ? room.gameId || null : null,
    awards: ended ? room.awards || [] : null,
  };
}

function broadcast(room) {
  const state = publicState(room);
  for (const p of room.players) {
    if (!p.socketId) continue;
    const seeAll = (p.id === room.hostId && room.phase !== 'lobby') || room.phase === 'ended';
    // المافيا بس بيعرفوا جماعتهم، وما بتنبعت لحدا غيرهم
    const isMafia = p.role && teamOf(p) === 'mafia';
    const mates = isMafia
      ? room.players.filter(x => x.id !== p.id && x.role && teamOf(x) === 'mafia')
          .map(x => ({ name: x.name, role: x.role, out: x.surrendered }))
      : null;
    let night = null;
    if (room.stage === 'night' && room.night && p.role && !p.surrendered) {
      const pick = room.night.picks[p.id];
      night = {
        picked: pick !== undefined,
        pick: pick === undefined ? null : pick,
        result: room.night.results[p.id] || null,
        killer: isKiller(room, p),
        bullet: p.role === 'sniper' ? !p.bulletUsed : null,
        // شيخ المافيا (أو اللي بيقرر) بيشوف اقتراحات جماعته
        suggest: isKiller(room, p)
          ? Object.entries(room.night.picks)
              .map(([id, t]) => [room.players.find(x => x.id === id), t])
              .filter(([x, t]) => x && x.id !== p.id && teamOf(x) === 'mafia' && x.role !== 'mafiaBoy' && t)
              .map(([x, t]) => ({ from: x.name, to: t }))
          : null,
      };
    }
    io.to(p.socketId).emit('state', {
      ...state,
      me: { id: p.id, role: p.role, surrendered: p.surrendered, outReason: p.outReason || null, mates, night,
            bullet: p.role === 'sniper' ? !p.bulletUsed : null },
      // الهوست يشوف كل الأدوار، والكل يشوفها بنهاية الجولة
      allRoles: seeAll ? Object.fromEntries(room.players.map(x => [x.id, x.role])) : null,
      // الهوست بيشوف اختيارات الليل وهي بتصير
      allPicks: seeAll && room.stage === 'night' && room.night ? room.night.picks : null,
    });
  }
  // نحدّث حالة "بيلعب هلأ" للأصدقاء
  for (const p of room.players) if (p.uid && p.online) userRoom.set(p.uid, room.code);
}

/* ---------- الليل ---------- */
// مين بيقرر الاغتيال: شيخ المافيا، وإذا طلع، كل المافيا الباقيين (ما عدا ولد المافيا) بيصوّتوا
function isKiller(room, p) {
  if (!p.role || p.surrendered || teamOf(p) !== 'mafia') return false;
  const sheikh = alivePlayers(room).find(x => x.role === 'mafiaSheikh');
  if (sheikh) return p.id === sheikh.id;
  const others = alivePlayers(room).filter(x => teamOf(x) === 'mafia' && x.role !== 'mafiaBoy');
  if (others.length) return p.role !== 'mafiaBoy';
  return p.role === 'mafiaBoy'; // ما ضل غير ولد المافيا
}

function nightResult(room, p, target) {
  const t = target && room.players.find(x => x.id === target);
  if (p.role === 'townSheikh' && t) {
    // بنت المافيا بتطلع للشيخ صالحة
    const up = teamOf(t) === 'town' || t.role === 'mafiaGirl';
    if (!up) p.facts.found++;
    return { kind: 'ask', target, name: t.name, answer: up ? 'up' : 'down' };
  }
  return { kind: 'chose', target: target || null, name: t ? t.name : null };
}

function knockOut(room, p, reason, events) {
  p.surrendered = true;
  p.outReason = reason;
  if (!room.hostId) { room.hostId = p.id; events && events.push({ t: 'host', pid: p.id, name: p.name }); }
}

function resolveNight(room) {
  const n = room.night, no = room.nightNo;
  const alive = alivePlayers(room);
  const pickOf = role => {
    const p = alive.find(x => x.role === role);
    return p ? { p, t: n.picks[p.id] || null } : null;
  };
  const events = [];

  // الاغتيال
  let killTarget = null, killerP = null;
  const killers = alive.filter(p => isKiller(room, p));
  if (killers.length === 1) { killerP = killers[0]; killTarget = n.picks[killerP.id] || null; }
  else if (killers.length > 1) {
    const votes = {};
    for (const k of killers) { const t = n.picks[k.id]; if (t) votes[t] = (votes[t] || 0) + 1; }
    const best = Object.entries(votes).sort((a, b) => b[1] - a[1])[0];
    if (best) { killTarget = best[0]; killerP = killers.find(k => n.picks[k.id] === killTarget); }
  }
  const doc = pickOf('doctor');
  if (doc && doc.t) doc.p.facts.protects++;
  const outs = [];
  if (killTarget) {
    const victim = room.players.find(x => x.id === killTarget);
    if (doc && doc.t === killTarget) { events.push({ t: 'saved' }); doc.p.facts.saves++; }
    else if (victim && !victim.surrendered) { outs.push([victim, 'kill']); killerP.facts.kills++; events.push({ t: 'kill', pid: victim.id, name: victim.name, team: teamOf(victim), by: killerP.id }); }
  }

  // القنص (طلقة وحدة بكل اللعبة)
  const sn = pickOf('sniper');
  if (sn && sn.t && !sn.p.bulletUsed) {
    sn.p.bulletUsed = true;
    const t = room.players.find(x => x.id === sn.t);
    if (t && !t.surrendered) {
      if (!outs.some(([x]) => x === t)) outs.push([t, 'snipe']);
      events.push({ t: 'snipe', pid: t.id, name: t.name, team: teamOf(t) });
      if (teamOf(t) === 'mafia') sn.p.facts.snipeMafia++;
      else {
        sn.p.facts.snipeTown++;
        if (!outs.some(([x]) => x === sn.p)) outs.push([sn.p, 'sniper']);
        events.push({ t: 'sniper', pid: sn.p.id, name: sn.p.name, team: 'town' });
      }
    }
  }

  outs.forEach(([p, reason]) => knockOut(room, p, reason, events));

  // التسكيت (بيضل لآخر النهار)
  const mb = pickOf('mafiaBoy');
  room.silenced = null;
  if (mb && mb.t && !killers.includes(mb.p)) {
    const t = room.players.find(x => x.id === mb.t);
    if (t && !t.surrendered) { room.silenced = { id: t.id, name: t.name }; mb.p.facts.silenced++; events.push({ t: 'silence', pid: t.id, name: t.name }); }
  }

  if (!events.some(e => ['kill', 'snipe', 'saved', 'silence'].includes(e.t))) events.push({ t: 'calm' });

  events.forEach(e => room.log.push({ ...e, night: no }));
  room.morning = { no, events };
  room.night = null;
  room.stage = 'day';
  room.dayNo = no + 1;

  // ولد الصالحين إذا طلع بالليل بيسحب حدا معه
  const boy = outs.map(([p]) => p).find(p => p.role === 'townBoy');
  if (boy && alivePlayers(room).length) room.pendingPull = boy.id;
  finishIfWon(room);
  broadcast(room);
}

/* ---------- نهاية اللعبة وحفظها ---------- */
function checkWinner(room) {
  const alive = alivePlayers(room);
  const mafia = alive.filter(p => teamOf(p) === 'mafia').length;
  const town = alive.length - mafia;
  if (mafia === 0) return 'town';
  if (mafia >= town) return 'mafia';
  return null;
}

function finishIfWon(room) {
  if (room.pendingPull) return false; // بنستنى ولد الصالحين يختار
  const w = checkWinner(room);
  if (!w) return false;
  room.winner = w;
  room.phase = 'ended';
  room.stage = 'day';
  room.night = null;
  // أبطال اللعبة
  const best = k => room.players.filter(p => p.role && p.facts && p.facts[k] > 0).sort((a, b) => b.facts[k] - a.facts[k])[0];
  const a = [];
  const k = best('kills'); if (k) a.push({ k: 'kills', name: k.name, n: k.facts.kills });
  const s = best('saves'); if (s) a.push({ k: 'saves', name: s.name, n: s.facts.saves });
  const sn = best('snipeMafia'); if (sn) a.push({ k: 'snipe', name: sn.name, n: sn.facts.snipeMafia });
  const f = best('found'); if (f) a.push({ k: 'found', name: f.name, n: f.facts.found });
  room.awards = a;
  recordGame(room);
  return true;
}

function recordGame(room) {
  const d = db.data;
  // نحفظ بس الألعاب اللي فيها حساب واحد على الأقل
  if (!room.players.some(p => p.uid)) return;
  d.gameSeq = (d.gameSeq || 0) + 1;
  const g = {
    id: crypto.randomUUID(), num: d.gameSeq, code: room.code, at: room.startedAt, endedAt: Date.now(),
    winner: room.winner, nights: room.nightNo,
    players: room.players.filter(p => p.role || p.id === room.hostId).map(p => ({
      pid: p.id, uid: p.uid || null, name: p.name, role: p.role || null, team: p.role ? teamOf(p) : null,
      won: !!p.role && teamOf(p) === room.winner, host: p.id === room.hostId,
      out: p.surrendered ? p.outReason || 'vote' : null, facts: p.facts || newFacts(),
    })),
    log: room.log,
  };
  d.games.push(g);
  room.gameId = g.id;
  db.save();
}

/* ---------- الاتصال ---------- */
io.on('connection', socket => {
  let room = null;
  let player = null;
  let user = userByToken(socket.handshake.auth && socket.handshake.auth.token);
  if (user) {
    if (!userSockets.has(user.id)) userSockets.set(user.id, new Set());
    userSockets.get(user.id).add(socket.id);
  }

  const fail = msg => socket.emit('fail', msg);
  // كل رسالة من اللاعب بتمر من هون: أي خطأ بينطبع بس، وما بيوقّع السيرفر على الكل
  const on = (ev, fn) => socket.on(ev, (...args) => {
    try { fn(...args); } catch (e) { console.error('خطأ بـ', ev, e); }
  });
  const obj = d => (d && typeof d === 'object' ? d : {});
  // هالاتصال هو الاتصال الحالي للاعب؟ (لو فتح من مكان ثاني، الاتصال القديم ما بيقدر يعمل إشي)
  const active = () => !!(room && player && player.socketId === socket.id);
  const isController = () => active() && room.phase === 'playing' && player.id === controllerId(room);

  function leaveRoom() {
    if (!room) return;
    const r = room, p = player;
    room = player = null;
    socket.leave(r.code);
    if (p.socketId !== socket.id) return;
    p.online = false;
    p.socketId = null;
    if (p.uid && userRoom.get(p.uid) === r.code) userRoom.delete(p.uid);
    if (r.phase === 'lobby') r.players = r.players.filter(x => x !== p);
    if (r.leaderId === p.id && !passLeader(r) && r.players[0]) r.leaderId = r.players[0].id;
    if (!r.players.some(x => x.online)) rooms.delete(r.code);
    else broadcast(r);
  }

  function attach(r, p) {
    if (room && (room !== r || player !== p)) leaveRoom();
    // إذا اللاعب كان فاتح من جهاز أو متصفح ثاني، بنفصل الاتصال القديم
    if (p.socketId && p.socketId !== socket.id) {
      const old = io.sockets.sockets.get(p.socketId);
      if (old) { old.leave(r.code); old.emit('replaced'); }
    }
    room = r;
    player = p;
    p.socketId = socket.id;
    p.online = true;
    if (user) { p.uid = user.id; p.avatar = avatarUrl(user); }
    socket.join(r.code);
    socket.emit('joined', { code: r.code, playerId: p.id });
    broadcast(r);
  }

  const newPlayer = name => ({
    id: crypto.randomUUID(), name, online: true, surrendered: false, role: null,
    uid: user ? user.id : null, avatar: user ? avatarUrl(user) : null,
  });
  const nameFor = n => (user ? user.username : String(n || '').trim().slice(0, 20));

  on('create', d => {
    let { name, size, roles, hostMode } = obj(d);
    name = nameFor(name);
    size = Math.max(3, Math.min(30, parseInt(size) || 0));
    if (!name) return fail('اكتب اسمك');
    const code = makeCode();
    const p = newPlayer(name);
    const r = {
      code, size, hostMode: sanitizeHostMode(hostMode), hostId: null, roles: sanitizeRoles(roles),
      leaderId: p.id, phase: 'lobby', winner: null, players: [p], log: [], stage: 'day', nightNo: 0, dayNo: 1,
    };
    rooms.set(code, r);
    attach(r, p);
  });

  on('join', d => {
    let { code, name, playerId } = obj(d);
    const r = rooms.get(String(code || '').trim());
    // رجوع لجلسة قديمة والغرفة ما عادت موجودة (مثلاً السيرفر عمل ريستارت)
    if (!r) return playerId ? socket.emit('expired') : fail('ما في غرفة بهالكود');
    const existing = playerId && r.players.find(p => p.id === playerId);
    if (existing) return attach(r, existing);
    // نفس الحساب كان بالغرفة من جهاز ثاني
    const mine = user && r.players.find(p => p.uid === user.id);
    if (mine) return attach(r, mine);
    name = nameFor(name);
    if (!name) return playerId ? socket.emit('expired') : fail('اكتب اسمك');
    // نفس الاسم ومش متصل: نفس اللاعب رجع من متصفح ثاني (مثلاً واتساب ← كروم)
    const byName = r.players.find(p => p.name === name);
    if (byName) return byName.online || (byName.uid && (!user || byName.uid !== user.id)) ? fail('الاسم مستخدم بالغرفة، اختار اسم ثاني') : attach(r, byName);
    if (r.phase !== 'lobby') return fail('اللعبة بلّشت، استنى الجولة الجاية');
    const capacity = r.size + (r.hostMode === 'fixed' ? 1 : 0);
    if (r.players.length >= capacity) return fail('الغرفة مليانة');
    const p = newPlayer(name);
    r.players.push(p);
    attach(r, p);
  });

  on('settings', d => {
    const { size, roles, hostMode } = obj(d);
    if (!active() || player.id !== room.leaderId || room.phase !== 'lobby') return;
    room.size = Math.max(3, Math.min(30, parseInt(size) || room.size));
    room.roles = sanitizeRoles(roles);
    room.hostMode = sanitizeHostMode(hostMode);
    broadcast(room);
  });

  on('kick', id => {
    if (!active() || player.id !== room.leaderId || room.phase !== 'lobby' || id === player.id) return;
    const k = room.players.find(p => p.id === id);
    if (!k) return;
    room.players = room.players.filter(p => p !== k);
    const ks = k.socketId && io.sockets.sockets.get(k.socketId);
    if (ks) { ks.leave(room.code); ks.emit('kicked'); }
    k.socketId = null;
    k.online = false;
    if (k.uid) userRoom.delete(k.uid);
    broadcast(room);
  });

  on('start', () => {
    if (!active() || player.id !== room.leaderId || room.phase !== 'lobby') return;
    const players = playingPlayers(room);
    if (players.length !== room.size) return fail(`لازم يكون عدد اللاعبين ${room.size}`);
    const special = Object.entries(room.roles).flatMap(([k, n]) => Array(n).fill(k));
    if (special.length > players.length) return fail('عدد الأدوار أكثر من عدد اللاعبين');
    const mafiaCount = special.filter(r => ROLES[r].team === 'mafia').length;
    if (mafiaCount === 0) return fail('لازم يكون في مافيا وحدة على الأقل');
    if (mafiaCount * 2 >= players.length) return fail('المافيا كثير! لازم يكونوا أقل من نص اللاعبين');
    const deck = shuffle([...special, ...Array(players.length - special.length).fill('citizen')]);
    room.players.forEach(p => { p.role = null; p.surrendered = false; p.outReason = null; p.bulletUsed = false; p.facts = newFacts(); });
    players.forEach((p, i) => { p.role = deck[i]; });
    // الهوست الثابت هو اللي عمل الروم، وإلا أول واحد بيطلع
    room.hostId = room.hostMode === 'fixed' ? room.leaderId : null;
    Object.assign(room, {
      phase: 'playing', winner: null, log: [], stage: 'day', nightNo: 0, dayNo: 1, night: null, morning: null,
      pendingPull: null, silenced: null, startedAt: Date.now(), gameId: null, awards: null,
    });
    broadcast(room);
  });

  // سلّم كرتك = طلعت بالتصويت (بالإيد)
  on('surrender', () => {
    if (!active() || room.phase !== 'playing' || !player.role || player.surrendered) return;
    if (room.stage === 'night') return fail('استنى لحد الصبح');
    const becameHost = !room.hostId;
    knockOut(room, player, 'vote');
    const team = teamOf(player);
    if (room.silenced && room.silenced.id === player.id) room.silenced = null;
    room.log.push({ t: 'vote', pid: player.id, name: player.name, team, host: becameHost, day: room.dayNo });
    io.to(room.code).emit('reveal', { name: player.name, avatar: player.avatar || null, team, host: becameHost });
    if (player.role === 'townBoy' && alivePlayers(room).length) room.pendingPull = player.id;
    finishIfWon(room);
    broadcast(room);
  });

  // ولد الصالحين بيسحب حدا معه
  on('pull', target => {
    if (!active() || room.phase !== 'playing' || room.pendingPull !== player.id) return;
    const t = target && room.players.find(x => x.id === target && x.role && !x.surrendered);
    room.pendingPull = null;
    if (t) {
      knockOut(room, t, 'pull');
      player.facts.pulled++;
      if (room.silenced && room.silenced.id === t.id) room.silenced = null;
      room.log.push({ t: 'pull', pid: player.id, name: player.name, tid: t.id, tname: t.name, team: teamOf(t),
        day: room.stage === 'day' ? room.dayNo : undefined });
      io.to(room.code).emit('reveal', { name: t.name, avatar: t.avatar || null, team: teamOf(t), pulledBy: player.name });
    }
    finishIfWon(room);
    broadcast(room);
  });

  on('skipPull', () => {
    if (!isController() || !room.pendingPull) return;
    room.pendingPull = null;
    finishIfWon(room);
    broadcast(room);
  });

  // الهوست (أو الليدر إذا ما في هوست) بيبلّش الليل
  on('nextNight', () => {
    if (!isController() || room.stage !== 'day') return;
    if (room.pendingPull) return fail('استنى ولد الصالحين يختار');
    room.nightNo += 1;
    room.stage = 'night';
    room.silenced = null;
    room.night = { picks: {}, results: {} };
    broadcast(room);
  });

  on('pick', d => {
    const { target } = obj(d);
    if (!active() || room.stage !== 'night' || !room.night || !player.role || player.surrendered) return;
    if (room.night.picks[player.id] !== undefined) return;
    let t = null;
    if (target) {
      const x = room.players.find(p => p.id === target && p.role && !p.surrendered);
      if (!x) return fail('اختار لاعب موجود');
      if (x.id === player.id && player.role !== 'doctor') return fail('ما بتقدر تختار حالك');
      t = x.id;
    }
    room.night.picks[player.id] = t;
    room.night.results[player.id] = nightResult(room, player, t);
    // الليل ما بيخلص لحاله: الهوست بيطلّع الصبح، عشان آخر واحد يلحق يشوف نتيجته
    broadcast(room);
  });

  on('endNight', () => {
    if (!isController() || room.stage !== 'night') return;
    resolveNight(room);
  });

  // دعوة صديق للغرفة
  on('invite', uid => {
    if (!active() || !user || typeof uid !== 'string') return;
    const me = db.data.users[user.id];
    if (!me || !(me.friends || []).includes(uid)) return;
    const target = db.data.users[uid];
    if (target && target.settings && target.settings.invites === false) return fail('صاحبك مسكّر الدعوات');
    presence.notify(uid, 'invite', { from: user.username, avatar: avatarUrl(user), code: room.code });
    socket.emit('invited', uid);
  });

  on('reset', () => {
    if (!active() || player.id !== room.leaderId) return;
    Object.assign(room, { phase: 'lobby', winner: null, hostId: null, log: [], stage: 'day', nightNo: 0, dayNo: 1,
      night: null, morning: null, pendingPull: null, silenced: null, gameId: null, awards: null });
    room.players.forEach(p => { p.role = null; p.surrendered = false; p.outReason = null; });
    // اللي طلعوا وهم مش متصلين ما بيرجعوا للغرفة الجديدة
    room.players = room.players.filter(p => p.online);
    if (!room.players.some(p => p.id === room.leaderId) && room.players[0]) room.leaderId = room.players[0].id;
    broadcast(room);
  });

  on('leave', leaveRoom);

  on('disconnect', () => {
    if (user) {
      const set = userSockets.get(user.id);
      if (set) { set.delete(socket.id); if (!set.size) { userSockets.delete(user.id); const u = db.data.users[user.id]; if (u) { u.lastSeen = Date.now(); db.save(); } } }
    }
    if (!active()) return;
    const r = room, p = player;
    p.online = false;
    p.socketId = null;
    broadcast(r);
    // إذا الليدر ما رجع خلال 30 ثانية، بتنتقل القيادة لحدا متصل عشان اللعبة ما توقف
    setTimeout(() => {
      if (rooms.get(r.code) === r && !p.online && r.leaderId === p.id && passLeader(r)) broadcast(r);
    }, 30 * 1000);
    // نحذف الغرفة إذا ضلت فاضية ساعة
    setTimeout(() => {
      if (rooms.get(r.code) === r && !r.players.some(x => x.online)) {
        rooms.delete(r.code);
        for (const x of r.players) if (x.uid && userRoom.get(x.uid) === r.code) userRoom.delete(x.uid);
      }
    }, 60 * 60 * 1000);
  });
});

function sanitizeHostMode(m) {
  return m === 'fixed' ? 'fixed' : 'first';
}

function sanitizeRoles(roles) {
  const out = {};
  for (const k of Object.keys(ROLES)) {
    if (k === 'citizen') continue;
    out[k] = Math.max(0, Math.min(15, parseInt(roles && roles[k]) || 0));
  }
  return out;
}

// بنحفظ البيانات قبل ما السيرفر يطفي
for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, async () => { await db.flush(); process.exit(0); });

const PORT = process.env.PORT || 3000;
db.load().then(() => server.listen(PORT, () => {
  const nets = require('os').networkInterfaces();
  console.log(`Mafia running: http://localhost:${PORT}`);
  for (const list of Object.values(nets))
    for (const n of list || [])
      if (n.family === 'IPv4' && !n.internal) console.log(`On your Wi-Fi: http://${n.address}:${PORT}`);
}));
