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
  return room.players.filter(p => !(room.hostMode === 'fixed' && p.id === room.leaderId));
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
    io.to(p.socketId).emit('state', {
      ...state,
      me: { id: p.id, role: p.role, surrendered: p.surrendered },
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

  function attach(r, p) {
    room = r;
    player = p;
    p.socketId = socket.id;
    p.online = true;
    socket.join(r.code);
    socket.emit('joined', { code: r.code, playerId: p.id });
    broadcast(r);
  }

  socket.on('create', ({ name, size, roles, hostMode }) => {
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

  socket.on('join', ({ code, name, playerId }) => {
    const r = rooms.get(String(code || '').trim());
    if (!r) return fail('ما في غرفة بهالكود');
    // رجوع لاعب انقطع اتصاله
    const existing = playerId && r.players.find(p => p.id === playerId);
    if (existing) return attach(r, existing);
    name = String(name || '').trim().slice(0, 20);
    if (!name) return fail('اكتب اسمك');
    if (r.phase !== 'lobby') return fail('اللعبة بلّشت، استنى الجولة الجاية');
    const capacity = r.size + (r.hostMode === 'fixed' ? 1 : 0);
    if (r.players.length >= capacity) return fail('الغرفة مليانة');
    if (r.players.some(p => p.name === name)) return fail('الاسم مستخدم، اختار اسم ثاني');
    const p = { id: crypto.randomUUID(), name, online: true, surrendered: false, role: null };
    r.players.push(p);
    attach(r, p);
  });

  socket.on('settings', ({ size, roles, hostMode }) => {
    if (!room || player.id !== room.leaderId || room.phase !== 'lobby') return;
    room.size = Math.max(3, Math.min(30, parseInt(size) || room.size));
    room.roles = sanitizeRoles(roles);
    room.hostMode = sanitizeHostMode(hostMode);
    broadcast(room);
  });

  socket.on('kick', id => {
    if (!room || player.id !== room.leaderId || room.phase !== 'lobby' || id === player.id) return;
    const k = room.players.find(p => p.id === id);
    room.players = room.players.filter(p => p.id !== id);
    if (k && k.socketId) io.to(k.socketId).emit('kicked');
    broadcast(room);
  });

  socket.on('start', () => {
    if (!room || player.id !== room.leaderId || room.phase !== 'lobby') return;
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

  socket.on('surrender', () => {
    if (!room || room.phase !== 'playing' || !player.role || player.surrendered) return;
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

  socket.on('reset', () => {
    if (!room || player.id !== room.leaderId) return;
    room.phase = 'lobby';
    room.winner = null;
    room.hostId = null;
    room.log = [];
    room.players.forEach(p => { p.role = null; p.surrendered = false; });
    broadcast(room);
  });

  socket.on('leave', () => {
    if (!room) return;
    const r = room;
    if (r.phase === 'lobby') {
      r.players = r.players.filter(p => p.id !== player.id);
      if (r.leaderId === player.id && r.players[0]) r.leaderId = r.players[0].id;
    } else {
      player.online = false;
      player.socketId = null;
    }
    socket.leave(r.code);
    room = player = null;
    if (!r.players.some(p => p.online)) rooms.delete(r.code);
    else broadcast(r);
  });

  socket.on('disconnect', () => {
    if (!room) return;
    player.online = false;
    player.socketId = null;
    const r = room;
    broadcast(r);
    // نحذف الغرفة إذا ضلت فاضية ساعة
    setTimeout(() => {
      if (rooms.get(r.code) === r && !r.players.some(p => p.online)) rooms.delete(r.code);
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
