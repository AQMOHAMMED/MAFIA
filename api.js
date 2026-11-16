// الحسابات، الأصدقاء، الإحصائيات ولوحة الصدارة
const express = require('express');
const crypto = require('crypto');
const db = require('./db');

const MIN_RANKED = 5;            // أقل عدد ألعاب لتدخل الترتيب
const DAY = 24 * 60 * 60 * 1000;
const D = () => db.data;

/* ---------- أدوات ---------- */
function hashPass(pass, salt = crypto.randomBytes(16).toString('hex')) {
  return { salt, hash: crypto.scryptSync(String(pass), salt, 64).toString('hex') };
}
function checkPass(user, pass) {
  const { hash } = hashPass(pass, user.salt);
  return crypto.timingSafeEqual(Buffer.from(hash, 'hex'), Buffer.from(user.hash, 'hex'));
}
function newToken(uid) {
  const t = crypto.randomBytes(32).toString('hex');
  D().sessions[t] = { uid, at: Date.now() };
  return t;
}
function userByToken(t) {
  const s = t && D().sessions[t];
  return s ? D().users[s.uid] || null : null;
}
function makeFriendCode() {
  let c;
  do c = 'MAFIA-' + String(crypto.randomInt(1000, 10000));
  while (Object.values(D().users).some(u => u.friendCode === c));
  return c;
}
const cleanName = s => String(s || '').trim().replace(/\s+/g, ' ').slice(0, 20);
const cleanEmail = s => String(s || '').trim().toLowerCase().slice(0, 120);
const validEmail = e => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e);
const nameTaken = (name, exceptId) =>
  Object.values(D().users).some(u => u.id !== exceptId && u.username.toLowerCase() === name.toLowerCase());
const emailTaken = (email, exceptId) =>
  Object.values(D().users).some(u => u.id !== exceptId && u.email === email);

// صورة اللاعب: data URL صغيرة (jpeg/png/webp) بنقبلها لحد ~200KB
function cleanAvatar(a) {
  if (a === null) return null;
  if (typeof a !== 'string') return undefined;
  if (!/^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/.test(a) || a.length > 280000) return undefined;
  return a;
}
const avatarUrl = u => (u && u.avatar ? `/api/avatar/${u.id}?v=${u.avatarV || 0}` : null);

/* ---------- الإحصائيات (بتنحسب من سجلات الألعاب) ---------- */
function myGames(uid, since = 0) {
  return D().games.filter(g => g.endedAt >= since && g.players.some(p => p.uid === uid));
}

function statsFor(uid, since = 0) {
  const s = {
    games: 0, wins: 0, winsTown: 0, winsMafia: 0, gamesTown: 0, gamesMafia: 0,
    saves: 0, protects: 0, snipeMafia: 0, snipeTown: 0, kills: 0, found: 0, silenced: 0, pulled: 0,
    votedOut: 0, killed: 0, sniped: 0, pulledOut: 0, hosted: 0,
    roles: {}, roleWins: {}, streak: 0, mates: {},
  };
  let run = 0;
  const games = myGames(uid, since).sort((a, b) => a.endedAt - b.endedAt);
  for (const g of games) {
    const me = g.players.find(p => p.uid === uid);
    if (!me.role) { if (me.host) s.hosted++; continue; }
    if (me.host) s.hosted++;
    s.games++;
    s.roles[me.role] = (s.roles[me.role] || 0) + 1;
    if (me.team === 'town') s.gamesTown++; else s.gamesMafia++;
    if (me.won) {
      s.wins++; run++; s.streak = Math.max(s.streak, run);
      s.roleWins[me.role] = (s.roleWins[me.role] || 0) + 1;
      if (me.team === 'town') s.winsTown++; else s.winsMafia++;
      for (const o of g.players) if (o.uid && o.uid !== uid && o.role && o.won) s.mates[o.uid] = (s.mates[o.uid] || 0) + 1;
    } else run = 0;
    const f = me.facts || {};
    for (const k of ['saves', 'protects', 'snipeMafia', 'snipeTown', 'kills', 'found', 'silenced', 'pulled']) s[k] += f[k] || 0;
    if (me.out === 'vote') s.votedOut++;
    else if (me.out === 'kill') s.killed++;
    else if (me.out === 'snipe' || me.out === 'sniper') s.sniped++;
    else if (me.out === 'pull') s.pulledOut++;
  }
  s.rate = s.games ? Math.round((s.wins / s.games) * 100) : 0;
  return s;
}

function levelOf(s) {
  const xp = s.games * 40 + s.wins * 60 + s.hosted * 20;
  return { level: 1 + Math.floor(xp / 300), xp: xp % 300, next: 300 };
}
function titleOf(s) {
  if (s.games < 5) return 'لاعب جديد';
  const fav = Object.entries(s.roles).sort((a, b) => b[1] - a[1])[0];
  if (fav && fav[0] === 'sniper') return 'قنّاص محترف';
  if (fav && fav[0] === 'doctor') return 'حامية المدينة';
  if (fav && fav[0] === 'townSheikh') return 'كاشف الأسرار';
  return s.winsMafia > s.winsTown ? 'زعيم المافيا' : 'حامي المدينة';
}
function favRole(s) {
  const fav = Object.entries(s.roles).sort((a, b) => b[1] - a[1])[0];
  return fav ? { role: fav[0], count: fav[1], rate: Math.round(((s.roleWins[fav[0]] || 0) / fav[1]) * 100) } : null;
}

function recentGames(uid, n = 3) {
  return myGames(uid).sort((a, b) => b.endedAt - a.endedAt).slice(0, n).map(g => gameSummary(g, uid));
}
function gameSummary(g, uid) {
  const me = g.players.find(p => p.uid === uid);
  return {
    id: g.id, num: g.num, code: g.code, at: g.endedAt, players: g.players.filter(p => p.role).length,
    nights: g.nights, winner: g.winner, role: me ? me.role : null, won: me ? !!me.won : false, host: me ? !!me.host : false,
  };
}

/* ---------- العلاقات ---------- */
const friendsOf = u => u.friends || (u.friends = []);
function relation(me, other) {
  if (!me || !other) return 'none';
  if (me.id === other.id) return 'self';
  if (friendsOf(me).includes(other.id)) return 'friend';
  if (D().requests.some(r => r.from === me.id && r.to === other.id)) return 'sent';
  if (D().requests.some(r => r.from === other.id && r.to === me.id)) return 'received';
  return 'none';
}

module.exports = function makeApi(presence) {
  const r = express.Router();
  r.use(express.json({ limit: '400kb' }));

  // محاولات الدخول: حد بسيط ضد التخمين
  const tries = new Map();
  const tooMany = ip => {
    const t = tries.get(ip) || { n: 0, at: Date.now() };
    if (Date.now() - t.at > 10 * 60 * 1000) { t.n = 0; t.at = Date.now(); }
    t.n++; tries.set(ip, t);
    return t.n > 20;
  };

  const auth = (req, res, next) => {
    const t = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    req.user = userByToken(t);
    req.token = t;
    next();
  };
  const need = (req, res, next) => (req.user ? next() : res.status(401).json({ error: 'لازم تسجّل دخول' }));
  r.use(auth);

  const pub = (u, me) => {
    const st = statsFor(u.id);
    const pr = presence(u.id);
    const showOnline = !u.settings || u.settings.showOnline !== false;
    return {
      id: u.id, username: u.username, avatar: avatarUrl(u), friendCode: u.friendCode,
      online: showOnline && pr.online, playing: showOnline && pr.playing,
      lastSeen: showOnline ? (pr.online ? Date.now() : u.lastSeen || null) : null,
      games: st.games, wins: st.wins, rate: st.rate, relation: relation(me, u),
    };
  };
  const meView = u => ({
    id: u.id, username: u.username, email: u.email, avatar: avatarUrl(u), friendCode: u.friendCode,
    settings: { vibrate: true, sounds: true, invites: true, showOnline: true, ...(u.settings || {}) },
    requests: D().requests.filter(x => x.to === u.id).length,
  });

  /* ----- الحساب ----- */
  r.post('/register', (req, res) => {
    if (tooMany(req.ip)) return res.status(429).json({ error: 'محاولات كثير، جرّب بعد شوي' });
    const username = cleanName(req.body.username);
    const email = cleanEmail(req.body.email);
    const password = String(req.body.password || '');
    if (username.length < 2) return res.status(400).json({ error: 'اسم اللاعب لازم يكون حرفين على الأقل' });
    if (!validEmail(email)) return res.status(400).json({ error: 'البريد الإلكتروني مش صحيح' });
    if (password.length < 6) return res.status(400).json({ error: 'كلمة السر لازم تكون 6 أحرف على الأقل' });
    if (nameTaken(username)) return res.status(400).json({ error: 'اسم اللاعب مستخدم، اختار اسم ثاني' });
    if (emailTaken(email)) return res.status(400).json({ error: 'في حساب بهالبريد، سجّل دخول' });
    const avatar = cleanAvatar(req.body.avatar);
    const { salt, hash } = hashPass(password);
    const u = {
      id: crypto.randomUUID(), username, email, salt, hash, avatar: avatar || null, avatarV: 1,
      friendCode: makeFriendCode(), friends: [], createdAt: Date.now(), settings: {},
    };
    D().users[u.id] = u;
    const token = newToken(u.id);
    db.save();
    res.json({ token, user: meView(u) });
  });

  r.post('/login', (req, res) => {
    if (tooMany(req.ip)) return res.status(429).json({ error: 'محاولات كثير، جرّب بعد شوي' });
    const login = String(req.body.login || '').trim().toLowerCase();
    const u = Object.values(D().users).find(x => x.email === login || x.username.toLowerCase() === login);
    if (!u || !checkPass(u, req.body.password)) return res.status(400).json({ error: 'الاسم أو كلمة السر غلط' });
    const token = newToken(u.id);
    db.save();
    res.json({ token, user: meView(u) });
  });

  r.post('/logout', need, (req, res) => { delete D().sessions[req.token]; db.save(); res.json({ ok: true }); });

  r.get('/me', need, (req, res) => res.json(meView(req.user)));

  r.put('/me', need, (req, res) => {
    const u = req.user, b = req.body || {};
    if (b.username !== undefined) {
      const n = cleanName(b.username);
      if (n.length < 2) return res.status(400).json({ error: 'اسم اللاعب لازم يكون حرفين على الأقل' });
      if (nameTaken(n, u.id)) return res.status(400).json({ error: 'اسم اللاعب مستخدم' });
      u.username = n;
    }
    if (b.email !== undefined) {
      const e = cleanEmail(b.email);
      if (!validEmail(e)) return res.status(400).json({ error: 'البريد الإلكتروني مش صحيح' });
      if (emailTaken(e, u.id)) return res.status(400).json({ error: 'البريد مستخدم بحساب ثاني' });
      u.email = e;
    }
    if (b.avatar !== undefined) {
      const a = cleanAvatar(b.avatar);
      if (a === undefined) return res.status(400).json({ error: 'الصورة مش مدعومة' });
      u.avatar = a; u.avatarV = (u.avatarV || 0) + 1;
    }
    if (b.settings && typeof b.settings === 'object') {
      u.settings = u.settings || {};
      for (const k of ['vibrate', 'sounds', 'invites', 'showOnline']) if (typeof b.settings[k] === 'boolean') u.settings[k] = b.settings[k];
    }
    db.save();
    res.json(meView(u));
  });

  r.put('/me/password', need, (req, res) => {
    const u = req.user;
    if (!checkPass(u, req.body.old)) return res.status(400).json({ error: 'كلمة السر الحالية غلط' });
    if (String(req.body.password || '').length < 6) return res.status(400).json({ error: 'كلمة السر الجديدة لازم تكون 6 أحرف على الأقل' });
    Object.assign(u, hashPass(req.body.password));
    // نطلّع كل الأجهزة الثانية
    for (const [t, s] of Object.entries(D().sessions)) if (s.uid === u.id && t !== req.token) delete D().sessions[t];
    db.save();
    res.json({ ok: true });
  });

  r.delete('/me', need, (req, res) => {
    const u = req.user;
    if (!checkPass(u, req.body && req.body.password)) return res.status(400).json({ error: 'كلمة السر غلط' });
    delete D().users[u.id];
    for (const [t, s] of Object.entries(D().sessions)) if (s.uid === u.id) delete D().sessions[t];
    D().requests = D().requests.filter(x => x.from !== u.id && x.to !== u.id);
    for (const o of Object.values(D().users)) if (o.friends) o.friends = o.friends.filter(id => id !== u.id);
    // بنخلي الألعاب القديمة بس بدون ربط بالحساب
    for (const g of D().games) for (const p of g.players) if (p.uid === u.id) p.uid = null;
    db.save();
    res.json({ ok: true });
  });

  r.get('/avatar/:id', (req, res) => {
    const u = D().users[req.params.id];
    if (!u || !u.avatar) return res.status(404).end();
    const m = u.avatar.match(/^data:(image\/\w+);base64,(.*)$/);
    res.set('Content-Type', m[1]).set('Cache-Control', 'public, max-age=31536000, immutable');
    res.send(Buffer.from(m[2], 'base64'));
  });

  /* ----- اللاعبين والأصدقاء ----- */
  r.get('/users/search', need, (req, res) => {
    const q = String(req.query.q || '').trim().toLowerCase();
    if (!q) return res.json([]);
    const list = Object.values(D().users)
      .filter(u => u.id !== req.user.id && (u.username.toLowerCase().includes(q) || u.friendCode.toLowerCase() === q || u.friendCode.toLowerCase() === 'mafia-' + q))
      .slice(0, 20).map(u => pub(u, req.user));
    res.json(list);
  });

  r.get('/users/:id', need, (req, res) => {
    const u = D().users[req.params.id];
    if (!u) return res.status(404).json({ error: 'اللاعب مش موجود' });
    const s = statsFor(u.id);
    // أنا وهو
    const both = D().games.filter(g => g.players.some(p => p.uid === u.id && p.role) && g.players.some(p => p.uid === req.user.id && p.role));
    let sameWin = 0, against = 0, killedMe = 0;
    for (const g of both) {
      const a = g.players.find(p => p.uid === req.user.id), b = g.players.find(p => p.uid === u.id);
      if (a.team === b.team && a.won) sameWin++;
      if (b.team === 'mafia' && a.team === 'town') against++;
      killedMe += g.log.filter(e => e.t === 'kill' && e.pid === a.pid && e.by === b.pid).length;
    }
    res.json({
      ...pub(u, req.user), ...levelOf(s), title: titleOf(s), fav: favRole(s),
      stats: s, recent: recentGames(u.id), friends: friendsOf(u).length,
      together: { games: both.length, sameWin, against, killedMe },
    });
  });

  r.get('/profile', need, (req, res) => {
    const u = req.user, s = statsFor(u.id);
    // ترتيبي بلوحة الصدارة (للتاج)
    const board = leaderboard('all', 0, 'rate');
    const rank = board.findIndex(x => x.id === u.id) + 1;
    res.json({
      ...pub(u, u), ...levelOf(s), title: titleOf(s), fav: favRole(s), stats: s,
      recent: recentGames(u.id), friends: friendsOf(u).length, rank: rank || null,
    });
  });

  r.get('/friends', need, (req, res) => {
    const list = friendsOf(req.user).map(id => D().users[id]).filter(Boolean).map(u => pub(u, req.user));
    list.sort((a, b) => (b.playing - a.playing) || (b.online - a.online) || a.username.localeCompare(b.username));
    res.json(list);
  });

  r.get('/friends/requests', need, (req, res) => {
    const me = req.user;
    const together = other => D().games.filter(g => g.players.some(p => p.uid === me.id) && g.players.some(p => p.uid === other)).length;
    const view = (x, id) => { const u = D().users[id]; return u && { ...pub(u, me), at: x.at, together: together(id) }; };
    res.json({
      received: D().requests.filter(x => x.to === me.id).map(x => view(x, x.from)).filter(Boolean),
      sent: D().requests.filter(x => x.from === me.id).map(x => view(x, x.to)).filter(Boolean),
    });
  });

  r.post('/friends/request', need, (req, res) => {
    const me = req.user;
    const key = String(req.body.to || '').trim();
    const u = D().users[key] || Object.values(D().users).find(x => x.friendCode.toLowerCase() === key.toLowerCase());
    if (!u) return res.status(404).json({ error: 'ما لقينا لاعب بهالكود' });
    const rel = relation(me, u);
    if (rel === 'self') return res.status(400).json({ error: 'هاد إنت 😄' });
    if (rel === 'friend') return res.status(400).json({ error: 'إنتو أصحاب أصلاً' });
    if (rel === 'received') { acceptReq(u.id, me); return res.json({ relation: 'friend' }); }
    if (rel === 'none') D().requests.push({ from: me.id, to: u.id, at: Date.now() });
    db.save();
    presence.notify(u.id, 'friends');
    res.json({ relation: 'sent' });
  });

  function acceptReq(fromId, me) {
    D().requests = D().requests.filter(x => !((x.from === fromId && x.to === me.id) || (x.from === me.id && x.to === fromId)));
    const other = D().users[fromId];
    if (!other) return false;
    if (!friendsOf(me).includes(fromId)) me.friends.push(fromId);
    if (!friendsOf(other).includes(me.id)) other.friends.push(me.id);
    db.save();
    presence.notify(fromId, 'friends');
    return true;
  }

  r.post('/friends/accept', need, (req, res) => {
    const from = String(req.body.from || '');
    if (!D().requests.some(x => x.from === from && x.to === req.user.id)) return res.status(404).json({ error: 'الطلب مش موجود' });
    acceptReq(from, req.user);
    res.json({ ok: true });
  });
  r.post('/friends/reject', need, (req, res) => {
    D().requests = D().requests.filter(x => !(x.from === req.body.from && x.to === req.user.id));
    db.save(); res.json({ ok: true });
  });
  r.post('/friends/cancel', need, (req, res) => {
    D().requests = D().requests.filter(x => !(x.from === req.user.id && x.to === req.body.to));
    db.save(); res.json({ ok: true });
  });
  r.post('/friends/remove', need, (req, res) => {
    const id = String(req.body.id || '');
    req.user.friends = friendsOf(req.user).filter(x => x !== id);
    const o = D().users[id];
    if (o) o.friends = friendsOf(o).filter(x => x !== req.user.id);
    db.save(); res.json({ ok: true });
  });

  // لاعبين لعبت معهم مؤخراً ومش أصحابك
  r.get('/recent-players', need, (req, res) => {
    const me = req.user, seen = new Set(), out = [];
    for (const g of myGames(me.id).sort((a, b) => b.endedAt - a.endedAt)) {
      for (const p of g.players) {
        if (!p.uid || p.uid === me.id || seen.has(p.uid)) continue;
        seen.add(p.uid);
        const u = D().users[p.uid];
        if (u && relation(me, u) !== 'friend') out.push(pub(u, me));
      }
      if (out.length >= 12) break;
    }
    res.json(out);
  });

  /* ----- لوحة الصدارة والإحصائيات ----- */
  const sinceOf = p => (p === 'week' ? Date.now() - 7 * DAY : p === 'month' ? Date.now() - 30 * DAY : 0);
  function leaderboard(scope, since, sort, me) {
    let users = Object.values(D().users);
    if (scope === 'friends' && me) users = users.filter(u => u.id === me.id || friendsOf(me).includes(u.id));
    return users.map(u => { const s = statsFor(u.id, since); return { id: u.id, username: u.username, avatar: avatarUrl(u), games: s.games, wins: s.wins, rate: s.rate }; })
      .filter(x => x.games >= MIN_RANKED)
      .sort((a, b) => sort === 'wins' ? (b.wins - a.wins) || (b.rate - a.rate) : (b.rate - a.rate) || (b.wins - a.wins));
  }

  r.get('/leaderboard', (req, res) => {
    const since = sinceOf(req.query.period);
    const list = leaderboard(req.query.scope, since, req.query.sort, req.user);
    let mine = null;
    if (req.user) {
      const i = list.findIndex(x => x.id === req.user.id);
      const s = statsFor(req.user.id, since);
      mine = { rank: i >= 0 ? i + 1 : null, username: req.user.username, avatar: avatarUrl(req.user), games: s.games, wins: s.wins, rate: s.rate };
    }
    res.json({ min: MIN_RANKED, list: list.slice(0, 100), mine });
  });

  r.get('/stats', need, (req, res) => {
    const since = sinceOf(req.query.period);
    const s = statsFor(req.user.id, since);
    // أداء آخر 30 يوم: نسبة الفوز التراكمية يوم بيوم
    const start = Date.now() - 30 * DAY;
    const games = myGames(req.user.id, start).filter(g => g.players.find(p => p.uid === req.user.id).role);
    const days = [];
    for (let i = 29; i >= 0; i--) {
      const end = Date.now() - i * DAY, from = end - DAY;
      const day = games.filter(g => g.endedAt > from && g.endedAt <= end);
      const wins = day.filter(g => g.players.find(p => p.uid === req.user.id).won).length;
      days.push({ games: day.length, wins });
    }
    const bestId = Object.entries(s.mates).sort((a, b) => b[1] - a[1])[0];
    const best = bestId && D().users[bestId[0]] ? { ...pub(D().users[bestId[0]], req.user), together: bestId[1] } : null;
    res.json({ stats: s, days, best });
  });

  r.get('/games', need, (req, res) => {
    const uid = req.user.id;
    res.json(myGames(uid).sort((a, b) => b.endedAt - a.endedAt).slice(0, 200).map(g => gameSummary(g, uid)));
  });

  r.get('/games/:id', (req, res) => {
    const g = D().games.find(x => x.id === req.params.id);
    if (!g) return res.status(404).json({ error: 'اللعبة مش موجودة' });
    res.json({
      id: g.id, num: g.num, code: g.code, at: g.at, endedAt: g.endedAt, winner: g.winner, nights: g.nights,
      players: g.players.map(p => ({ pid: p.pid, name: p.name, role: p.role, team: p.team, won: p.won, host: p.host, out: p.out,
        avatar: p.uid && D().users[p.uid] ? avatarUrl(D().users[p.uid]) : null })),
      log: g.log,
    });
  });

  r.use((err, req, res, next) => { console.error(err); res.status(500).json({ error: 'صار خطأ، جرّب كمان مرة' }); });
  return r;
};

module.exports.userByToken = userByToken;
module.exports.avatarUrl = avatarUrl;
