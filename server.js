const express = require('express');
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server);

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

const rooms = new Map(); // code -> room

function makeCode() {
  let code;
  do code = String(Math.floor(1000 + Math.random() * 9000));
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

// إذا الليدر طلع أو انقطع، بننقل القيادة لأول لاعب متصل
function passLeader(room) {
  const next = room.players.find(p => p.online && p.id !== room.leaderId);
  if (!next) return false;
  room.leaderId = next.id;
  return true;
}

function publicState(room) {
  return {
    code: room.code,
    size: room.size,
    roles: room.roles,
    hostMode: room.hostMode,
    hostId: room.hostId,
    leaderId: room.leaderId,
    phase: room.phase,
    winner: room.winner,
    players: room.players.map(p => ({
      id: p.id,
      name: p.name,
      online: p.online,
      surrendered: p.surrendered,
      // الفريق يظهر فقط بعد تسليم الكرت
      team: p.surrendered ? ROLES[p.role].team : null,
    })),
    log: room.log,
  };
}

function broadcast(room) {
  const state = publicState(room);
  for (const p of room.players) {
    if (!p.socketId) continue;
    const seeAll = (p.id === room.hostId && room.phase !== 'lobby') || room.phase === 'ended';
    // المافيا بس بيعرفوا جماعتهم، وما بتنبعت لحدا غيرهم
    const isMafia = p.role && ROLES[p.role].team === 'mafia';
    const mates = isMafia
      ? room.players.filter(x => x.id !== p.id && x.role && ROLES[x.role].team === 'mafia')
          .map(x => ({ name: x.name, role: x.role, out: x.surrendered }))
      : null;
    io.to(p.socketId).emit('state', {
      ...state,
      me: { id: p.id, role: p.role, surrendered: p.surrendered, mates },
      // الراوي يشوف كل الأدوار، والكل يشوفها بنهاية الجولة
      allRoles: seeAll ? Object.fromEntries(room.players.map(x => [x.id, x.role])) : null,
    });
  }
}

function checkWinner(room) {
  const alive = playingPlayers(room).filter(p => !p.surrendered);
  const mafia = alive.filter(p => ROLES[p.role].team === 'mafia').length;
  const town = alive.length - mafia;
  if (mafia === 0) return 'town';
  if (mafia >= town) return 'mafia';
  return null;
}

io.on('connection', socket => {
  let room = null;
  let player = null;

  const fail = msg => socket.emit('fail', msg);
  // كل رسالة من اللاعب بتمر من هون: أي خطأ بينطبع بس، وما بيوقّع السيرفر على الكل
  const on = (ev, fn) => socket.on(ev, (...args) => {
    try { fn(...args); } catch (e) { console.error('خطأ بـ', ev, e); }
  });
  const obj = d => (d && typeof d === 'object' ? d : {});
  // هالاتصال هو الاتصال الحالي للاعب؟ (لو فتح من مكان ثاني، الاتصال القديم ما بيقدر يعمل إشي)
  const active = () => !!(room && player && player.socketId === socket.id);

  function leaveRoom() {
    if (!room) return;
    const r = room, p = player;
    room = player = null;
    socket.leave(r.code);
    if (p.socketId !== socket.id) return;
    p.online = false;
    p.socketId = null;
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
    socket.join(r.code);
    socket.emit('joined', { code: r.code, playerId: p.id });
    broadcast(r);
  }

  on('create', d => {
    let { name, size, roles, hostMode } = obj(d);
    name = String(name || '').trim().slice(0, 20);
    size = Math.max(3, Math.min(30, parseInt(size) || 0));
    if (!name) return fail('اكتب اسمك');
    const code = makeCode();
    const p = { id: crypto.randomUUID(), name, online: true, surrendered: false, role: null };
    const r = {
      code, size, hostMode: sanitizeHostMode(hostMode), hostId: null, roles: sanitizeRoles(roles),
      leaderId: p.id, phase: 'lobby', winner: null, players: [p], log: [],
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
    name = String(name || '').trim().slice(0, 20);
    if (!name) return playerId ? socket.emit('expired') : fail('اكتب اسمك');
    // نفس الاسم ومش متصل: نفس اللاعب رجع من متصفح ثاني (مثلاً واتساب ← كروم)
    const byName = r.players.find(p => p.name === name);
    if (byName) return byName.online ? fail('الاسم مستخدم، اختار اسم ثاني') : attach(r, byName);
    if (r.phase !== 'lobby') return fail('اللعبة بلّشت، استنى الجولة الجاية');
    const capacity = r.size + (r.hostMode === 'fixed' ? 1 : 0);
    if (r.players.length >= capacity) return fail('الغرفة مليانة');
    const p = { id: crypto.randomUUID(), name, online: true, surrendered: false, role: null };
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
    room.players.forEach(p => { p.role = null; p.surrendered = false; });
    players.forEach((p, i) => { p.role = deck[i]; });
    // الهوست الثابت هو اللي عمل الروم، وإلا أول واحد بسلّم كرته
    room.hostId = room.hostMode === 'fixed' ? room.leaderId : null;
    room.phase = 'playing';
    room.winner = null;
    room.log = [];
    broadcast(room);
  });

  on('surrender', () => {
    if (!active() || room.phase !== 'playing' || !player.role || player.surrendered) return;
    player.surrendered = true;
    const team = ROLES[player.role].team;
    const becameHost = !room.hostId;
    if (becameHost) room.hostId = player.id;
    room.log.push({ name: player.name, team, host: becameHost });
    io.to(room.code).emit('reveal', { name: player.name, team, host: becameHost });
    room.winner = checkWinner(room);
    if (room.winner) room.phase = 'ended';
    broadcast(room);
  });

  on('reset', () => {
    if (!active() || player.id !== room.leaderId) return;
    room.phase = 'lobby';
    room.winner = null;
    room.hostId = null;
    room.log = [];
    room.players.forEach(p => { p.role = null; p.surrendered = false; });
    broadcast(room);
  });

  on('leave', leaveRoom);

  on('disconnect', () => {
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
      if (rooms.get(r.code) === r && !r.players.some(x => x.online)) rooms.delete(r.code);
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

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  const nets = require('os').networkInterfaces();
  console.log(`Mafia running: http://localhost:${PORT}`);
  for (const list of Object.values(nets))
    for (const n of list || [])
      if (n.family === 'IPv4' && !n.internal) console.log(`On your Wi-Fi: http://${n.address}:${PORT}`);
});
