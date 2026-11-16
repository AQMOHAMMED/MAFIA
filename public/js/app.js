'use strict';
/* =====================================================================
   مافيا — الواجهة
   ===================================================================== */
const ROLES = {
  mafiaSheikh: { name: 'شيخ المافيا', icon: '🔪', team: 'mafia' },
  mafiaGirl:   { name: 'بنت المافيا', icon: '🎭', team: 'mafia' },
  mafiaBoy:    { name: 'ولد المافيا', icon: '🤐', team: 'mafia' },
  mafia:       { name: 'مافيا', icon: '🕶️', team: 'mafia' },
  townSheikh:  { name: 'شيخ الصالحين', icon: '👳', team: 'town' },
  doctor:      { name: 'بنت الصالحين', icon: '💉', team: 'town' },
  sniper:      { name: 'قناص الصالحين', icon: '🎯', team: 'town' },
  townBoy:     { name: 'ولد الصالحين', icon: '⛓️', team: 'town' },
  citizen:     { name: 'مواطن صالح', icon: '🙂', team: 'town' },
};
const SPECIAL = ['mafiaSheikh', 'mafiaGirl', 'mafiaBoy', 'mafia', 'townSheikh', 'doctor', 'sniper', 'townBoy'];
const ALL_ROLES = [...SPECIAL, 'citizen'];
const TEAM_NAME = { mafia: 'مافيا', town: 'مواطن صالح' };
// مكان خانة الاسم الفاضية بكل صورة كرت (نسبة من ارتفاع الكرت)
const NAME_Y = { mafiaSheikh: '59.9%', mafiaGirl: '53.1%', mafiaBoy: '53.1%', mafia: '53.0%', townSheikh: '60.1%',
  doctor: '60.1%', sniper: '60.1%', townBoy: '60.1%', citizen: '60.1%' };
const HOST_OPTS = [
  ['first', '🃏', 'أول واحد بسلّم كرته', 'الكل بلعب، وأول واحد بيطلع من اللعبة بصير الهوست وبشوف كل الكروت.'],
  ['fixed', '🎙️', 'هوست ثابت (أنا)', 'أنا ما بلعب، بدير اللعبة وبشوف كل الكروت من البداية.'],
];

/* ---------- أدوات ---------- */
const $ = id => document.getElementById(id);
const esc = t => String(t == null ? '' : t).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const store = {
  get(k) { try { return JSON.parse(localStorage.getItem('mafia_' + k)); } catch { return null; } },
  set(k, v) { try { localStorage.setItem('mafia_' + k, JSON.stringify(v)); } catch {} },
  del(k) { try { localStorage.removeItem('mafia_' + k); } catch {} },
};
function toast(msg) {
  const t = $('toast'); t.textContent = msg; t.style.display = 'block';
  clearTimeout(toast.t); toast.t = setTimeout(() => (t.style.display = 'none'), 2800);
}
function vibrate(p) { if (navigator.vibrate && (!ME || ME.settings.vibrate !== false)) navigator.vibrate(p); }
let audioCtx = null;
function beep(freq = 520, dur = .12) {
  if (ME && ME.settings.sounds === false) return;
  try {
    audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
    const o = audioCtx.createOscillator(), g = audioCtx.createGain();
    o.frequency.value = freq; o.type = 'triangle';
    g.gain.setValueAtTime(.12, audioCtx.currentTime); g.gain.exponentialRampToValueAtTime(.001, audioCtx.currentTime + dur);
    o.connect(g).connect(audioCtx.destination); o.start(); o.stop(audioCtx.currentTime + dur);
  } catch {}
}
function avatar(url, name, size, status) {
  const s = size ? ` style="--s:${size}px"` : '';
  const inner = url ? `<img src="${esc(url)}" alt="" loading="lazy">` : esc((name || '؟').trim().charAt(0));
  const dot = status ? `<span class="on ${status}"></span>` : '';
  return `<span class="av"${s}>${inner}${dot}</span>`;
}
function ago(ts) {
  if (!ts) return '';
  const m = Math.round((Date.now() - ts) / 60000);
  if (m < 1) return 'هلأ';
  if (m < 60) return `قبل ${m} ${m <= 10 ? 'دقايق' : 'دقيقة'}`;
  const h = Math.round(m / 60);
  if (h < 24) return h === 1 ? 'قبل ساعة' : h === 2 ? 'قبل ساعتين' : `قبل ${h} ساعات`;
  const d = Math.round(h / 24);
  return d === 1 ? 'مبارح' : d === 2 ? 'قبل يومين' : `قبل ${d} أيام`;
}
const nightsTxt = n => (n === 0 ? 'بدون ولا ليلة' : n === 1 ? 'ليلة وحدة' : n === 2 ? 'ليلتين' : `${n} ليالي`);
const pct = (a, b) => (b ? Math.round((a / b) * 100) : 0);

/* ---------- الحساب ---------- */
let TOKEN = store.get('token');
let ME = null;
async function api(method, path, body) {
  const res = await fetch('/api' + path, {
    method, headers: { 'Content-Type': 'application/json', ...(TOKEN ? { Authorization: 'Bearer ' + TOKEN } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = null;
  try { data = await res.json(); } catch {}
  if (res.status === 401 && TOKEN) { setAuth(null, null); }
  if (!res.ok) throw new Error((data && data.error) || 'صار خطأ، جرّب كمان مرة');
  return data;
}
function setAuth(token, user, remember = true) {
  TOKEN = token; ME = user;
  if (token && remember) store.set('token', token); else store.del('token');
  if (token && !remember) sessionStorage.setItem('mafia_token', token); else sessionStorage.removeItem('mafia_token');
  // نعيد الاتصال عشان السيرفر يعرف مين إحنا
  socket.auth = { token: TOKEN };
  if (socket.connected) { socket.disconnect(); socket.connect(); }
  paintHello();
}
if (!TOKEN) TOKEN = sessionStorage.getItem('mafia_token');

// تصغير الصورة قبل الرفع
function readAvatar(file) {
  return new Promise((resolve, reject) => {
    if (!file) return reject(new Error('ما في صورة'));
    const img = new Image();
    img.onload = () => {
      const s = 192, c = document.createElement('canvas'); c.width = c.height = s;
      const k = Math.max(s / img.width, s / img.height), w = img.width * k, h = img.height * k;
      c.getContext('2d').drawImage(img, (s - w) / 2, (s - h) / 2, w, h);
      URL.revokeObjectURL(img.src);
      resolve(c.toDataURL('image/jpeg', .82));
    };
    img.onerror = () => reject(new Error('الصورة مش مدعومة'));
    img.src = URL.createObjectURL(file);
  });
}

/* ---------- التنقل ---------- */
const TABS = ['home', 'leaderboard', 'friends', 'stats', 'profile'];
const GAME_SCREENS = ['lobby', 'card', 'night', 'nightRes', 'pull', 'board', 'gameover'];
const NEED_LOGIN = ['friends', 'stats', 'profile', 'addfriend', 'requests', 'friend', 'settings', 'mygames'];
let current = null;
const stack = [];
function show(id) {
  document.querySelectorAll('.screen').forEach(s => s.classList.toggle('on', s.id === id));
  $('card').classList.toggle('on', id === 'card');
  document.body.classList.toggle('has-nav', TABS.includes(id));
  document.querySelectorAll('#nav button').forEach(b => b.classList.toggle('on', b.dataset.tab === id));
  if (id !== current) window.scrollTo(0, 0);
  current = id;
  paintHostBar();
}
function go(id, push = true) {
  if (NEED_LOGIN.includes(id) && !ME) { toast('سجّل دخول لتشوف هاي الصفحة'); return go('login'); }
  if (push && current && current !== id && !GAME_SCREENS.includes(current)) stack.push(current);
  if (TABS.includes(id)) stack.length = 0;
  show(id);
  const loaders = { home: loadHome, leaderboard: loadBoard, friends: loadFriends, stats: loadStats, profile: loadProfile,
    addfriend: loadAddFriend, requests: loadRequests, settings: loadSettings, mygames: loadMyGames };
  if (loaders[id]) loaders[id]();
}
function back() {
  const prev = stack.pop();
  if (S && !prev) return render(true);
  go(prev || (ME || store.get('guest') ? 'home' : 'login'), false);
}
document.addEventListener('click', e => {
  const g = e.target.closest('[data-go]'); if (g) { e.preventDefault(); go(g.dataset.go); }
  const b = e.target.closest('[data-back]'); if (b) { e.preventDefault(); back(); }
  const t = e.target.closest('[data-terms]'); if (t) { e.preventDefault(); toast('العب بروح رياضية، واحترم أصحابك 🤝'); }
  const eye = e.target.closest('[data-eye]');
  if (eye) { const i = $(eye.dataset.eye); i.type = i.type === 'password' ? 'text' : 'password'; eye.firstElementChild.textContent = i.type === 'password' ? 'visibility' : 'visibility_off'; }
});
document.querySelectorAll('#nav button').forEach(b => (b.onclick = () => go(b.dataset.tab)));

/* =====================================================================
   تسجيل الدخول / حساب جديد
   ===================================================================== */
$('loginForm').onsubmit = async e => {
  e.preventDefault();
  try {
    const r = await api('POST', '/login', { login: $('lgUser').value, password: $('lgPass').value });
    setAuth(r.token, r.user, $('lgRemember').checked);
    $('lgPass').value = '';
    afterLogin();
  } catch (err) { toast(err.message); }
};
$('forgotBtn').onclick = () => toast('تواصل مع صاحب اللعبة ليرجّعلك حسابك');
$('guestBtn').onclick = () => { store.set('guest', true); go('home'); };

let regAvatar = null;
$('regAvFile').onchange = async e => {
  try { regAvatar = await readAvatar(e.target.files[0]); $('regAv').innerHTML = `<img src="${regAvatar}" alt=""><span class="cam"><span class="ms">photo_camera</span></span>`; }
  catch (err) { toast(err.message); }
};
$('regForm').onsubmit = async e => {
  e.preventDefault();
  if ($('rgPass').value !== $('rgPass2').value) return toast('كلمتين السر مش متطابقات');
  if (!$('rgTerms').checked) return toast('لازم توافق على شروط الاستخدام');
  try {
    const r = await api('POST', '/register', { username: $('rgUser').value, email: $('rgEmail').value, password: $('rgPass').value, avatar: regAvatar });
    setAuth(r.token, r.user);
    toast(`أهلاً فيك يا ${r.user.username} 🔥`);
    afterLogin();
  } catch (err) { toast(err.message); }
};
function afterLogin() {
  const pend = store.get('pendingAdd');
  if (pend) { store.del('pendingAdd'); sendRequest(pend); }
  if (S) return render(true);
  go('home');
}

/* =====================================================================
   الرئيسية
   ===================================================================== */
function myName() { return ME ? ME.username : $('nameInput').value.trim(); }
$('nameInput').value = store.get('name') || '';
$('nameInput').addEventListener('input', () => store.set('name', $('nameInput').value.trim()));

function paintHello() {
  $('guestName').classList.toggle('hidden', !!ME);
  $('hello').innerHTML = ME
    ? `${avatar(ME.avatar, ME.username, 44)}<div><small>أهلاً فيك</small><b>${esc(ME.username)}</b></div>`
    : `<button class="sbtn gold" data-go="login"><span class="ms">person</span> تسجيل دخول</button>`;
  $('bellBtn').classList.toggle('hidden', !ME);
  $('bellBtn').querySelector('.dotn')?.remove();
  if (ME && ME.requests) $('bellBtn').insertAdjacentHTML('beforeend', `<span class="dotn">${ME.requests}</span>`);
  $('reqBtn').querySelector('.dotn')?.remove();
  if (ME && ME.requests) $('reqBtn').insertAdjacentHTML('beforeend', `<span class="dotn">${ME.requests}</span>`);
}
$('bellBtn').onclick = () => go('requests');
$('reqBtn').onclick = () => go('requests');

let pendingInvites = [];
async function loadHome() {
  paintHello();
  if (!ME) { $('homeFriends').innerHTML = ''; $('homeLast').innerHTML = ''; return; }
  try {
    const [me, friends, games] = await Promise.all([api('GET', '/me'), api('GET', '/friends'), api('GET', '/games')]);
    ME = me; paintHello();
    const on = friends.filter(f => f.online);
    $('homeFriends').innerHTML = `<h2>أصدقائك المتصلين ${on.length ? `<span class="tag town">● ${on.length} متصل</span>` : ''}
      <button class="more" data-go="friends">عرض الكل</button></h2>` + (on.length
      ? `<div class="hrow">${on.map(f => `<div class="fcard">${avatar(f.avatar, f.username, 56, f.playing ? 'busy' : 'on')}
          <b>${esc(f.username)}</b><small>${f.playing ? 'بيلعب هلأ' : 'متصل الآن'}</small>
          <button class="sbtn" data-inv="${f.id}">+ ادعي</button></div>`).join('')}</div>`
      : `<div class="empty">ما في حدا من أصحابك متصل هلأ</div>`);
    $('homeFriends').querySelectorAll('[data-inv]').forEach(b => (b.onclick = () => inviteFriend(b.dataset.inv, b)));
    const g = games[0];
    $('homeLast').innerHTML = g ? `<h2>🕓 آخر لعبة <span class="more">#${g.code}</span></h2>
      <button class="panel lastgame" data-game="${g.id}" style="width:100%;text-align:start">
        <span class="ric">${g.role ? ROLES[g.role].icon : '🎙️'}</span>
        <span style="flex:1"><b>${g.role ? ROLES[g.role].name : 'كنت الهوست'}</b>
          <span class="tag ${g.winner}">${g.winner === 'mafia' ? 'المافيا فازت' : 'الصالحين فازوا'}</span><br>
          <small class="muted">${g.players} لاعبين · ${ago(g.at)}</small></span>
        <span class="linkbtn">سجل اللعبة ‹</span></button>` : '';
    $('homeLast').querySelector('[data-game]')?.addEventListener('click', ev => openGameLog(ev.currentTarget.dataset.game));
  } catch (err) { /* بنضل نعرض الرئيسية حتى لو صار خطأ */ }
}

// دعوة صديق: إذا إنت بغرفة بتنبعت فوراً، وإلا بنعمل غرفة وبعدين بنبعتها
function inviteFriend(uid, btn) {
  if (S && S.phase !== 'ended') {
    socket.emit('invite', uid);
    if (btn) { btn.textContent = 'انبعتت ✓'; btn.disabled = true; }
    return;
  }
  if (!pendingInvites.includes(uid)) pendingInvites.push(uid);
  toast('اعمل الغرفة وبنبعتله الدعوة');
  go('create');
}

/* ---------- كود الغرفة (4 خانات) ---------- */
const codeBoxes = [...$('code4').querySelectorAll('input')];
codeBoxes.forEach((inp, i) => {
  inp.addEventListener('input', () => {
    const d = inp.value.replace(/\D/g, '');
    if (d.length > 1) { fillCode(d); return; }
    inp.value = d;
    if (d && codeBoxes[i + 1]) codeBoxes[i + 1].focus();
    if (codeVal().length === 4) joinRoom();
  });
  inp.addEventListener('keydown', e => { if (e.key === 'Backspace' && !inp.value && codeBoxes[i - 1]) codeBoxes[i - 1].focus(); });
  inp.addEventListener('paste', e => { e.preventDefault(); fillCode((e.clipboardData.getData('text') || '').replace(/\D/g, '')); });
});
function fillCode(d) { codeBoxes.forEach((b, i) => (b.value = d[i] || '')); (codeBoxes[Math.min(d.length, 3)]).focus(); }
const codeVal = () => codeBoxes.map(b => b.value).join('');
$('goJoin').onclick = () => codeBoxes[codeVal().length < 4 ? codeVal().length : 0].focus();
$('joinBtn').onclick = joinRoom;
function joinRoom() {
  if (!myName()) { toast('اكتب اسمك أول'); return $('nameInput').focus(); }
  const code = codeVal();
  if (code.length !== 4) return toast('الكود 4 أرقام');
  socket.emit('join', { code, name: myName() });
}

/* =====================================================================
   إنشاء غرفة
   ===================================================================== */
let createSize = 8, createHostMode = 'first';
function optsHTML() {
  return HOST_OPTS.map(([m, i, b, s]) => `<button class="opt" data-m="${m}"><span class="oi">${i}</span><span><b>${b}</b><small>${s}</small></span></button>`).join('');
}
$('createHost').innerHTML = optsHTML();
$('lobbyHost').innerHTML = optsHTML();
function paintOpts(box, mode, enabled) {
  box.querySelectorAll('.opt').forEach(o => { o.classList.toggle('sel', o.dataset.m === mode); o.disabled = !enabled; });
}
$('goCreate').onclick = () => { if (!myName()) { toast('اكتب اسمك أول'); return $('nameInput').focus(); } go('create'); };
$('create').querySelectorAll('[data-d]').forEach(b => (b.onclick = () => {
  createSize = Math.max(3, Math.min(30, createSize + +b.dataset.d)); $('sizeV').textContent = createSize;
}));
$('createHost').querySelectorAll('.opt').forEach(o => (o.onclick = () => { createHostMode = o.dataset.m; paintOpts($('createHost'), createHostMode, true); }));
paintOpts($('createHost'), createHostMode, true);
$('createBtn').onclick = () => {
  if (!myName()) { toast('اكتب اسمك أول'); return go('home'); }
  socket.emit('create', { name: myName(), size: createSize, roles: defaultRoles(createSize), hostMode: createHostMode });
};
function defaultRoles(n) {
  const m = Math.max(1, Math.floor(n / 4));
  return { mafiaSheikh: 1, mafiaGirl: m >= 2 ? 1 : 0, mafiaBoy: m >= 3 ? 1 : 0, mafia: Math.max(0, m - 3),
    townSheikh: 1, doctor: n >= 4 ? 1 : 0, sniper: n >= 7 ? 1 : 0, townBoy: n >= 8 ? 1 : 0 };
}

/* =====================================================================
   السوكيت
   ===================================================================== */
const socket = io({ auth: { token: TOKEN } });
let S = null, myId = null;
socket.on('connect', () => {
  const saved = store.get('session');
  if (saved) socket.emit('join', { code: saved.code, playerId: saved.playerId });
  else if (urlRoom && (ME || myName())) { socket.emit('join', { code: urlRoom, name: myName() }); urlRoom = null; }
});
socket.on('joined', ({ code, playerId }) => {
  myId = playerId;
  store.set('session', { code, playerId });
  history.replaceState(null, '', location.pathname);
  // دعوات مستنية من الرئيسية
  if (pendingInvites.length) { setTimeout(() => { pendingInvites.forEach(uid => socket.emit('invite', uid)); toast('انبعتت الدعوة 📨'); pendingInvites = []; }, 300); }
});
socket.on('fail', msg => toast(msg));
socket.on('expired', () => {
  store.del('session');
  if (S) { S = null; go('home'); toast('الغرفة انتهت، اعملوا غرفة جديدة'); }
});
socket.on('replaced', () => { S = null; go('home'); toast('فتحت اللعبة من مكان ثاني'); });
socket.on('kicked', () => { store.del('session'); S = null; go('home'); toast('الليدر طلّعك من الغرفة'); });
socket.on('invited', () => {});
socket.on('notify', n => {
  if (n.kind === 'friends') { if (ME) api('GET', '/me').then(m => { ME = m; paintHello(); }).catch(() => {}); if (current === 'requests') loadRequests(); if (current === 'friends') loadFriends(); }
  if (n.kind === 'invite') showInvite(n);
});
socket.on('state', st => {
  const prev = S; S = st;
  if (prev && prev.stage !== st.stage) { beep(st.stage === 'night' ? 330 : 660, .25); vibrate(80); }
  render(false, prev);
});
socket.on('reveal', showReveal);

function showInvite(n) {
  const c = $('inviteCard');
  c.innerHTML = `${avatar(n.avatar, n.from, 42)}<div class="grow">${esc(n.from)} عزمك على غرفة <b style="color:var(--gold)">${esc(n.code)}</b></div>
    <button class="sbtn gold" id="invYes">انضم</button><button class="iconbtn" id="invNo" style="width:36px;height:36px;flex-basis:36px"><span class="ms">close</span></button>`;
  c.className = 'on';
  beep(780, .15); vibrate([60, 60, 60]);
  $('invNo').onclick = () => (c.className = '');
  $('invYes').onclick = () => {
    c.className = '';
    if (S) { socket.emit('leave'); store.del('session'); S = null; }
    socket.emit('join', { code: n.code, name: myName() || 'لاعب' });
  };
  clearTimeout(showInvite.t); showInvite.t = setTimeout(() => (c.className = ''), 20000);
}

/* =====================================================================
   رسم اللعبة
   ===================================================================== */
const meP = () => S && S.players.find(p => p.id === myId);
const isLeader = () => S && S.leaderId === myId;
const isHost = () => S && S.hostId === myId;
const isController = () => S && S.phase === 'playing' && S.controllerId === myId;
const alive = () => S.players.filter(p => p.playing && !p.surrendered);
const pById = id => S.players.find(p => p.id === id);
let gameKey = '';

function gameScreen() {
  if (S.phase === 'lobby') return 'lobby';
  if (S.phase === 'ended') return 'gameover';
  const me = S.me;
  if (S.pendingPull && meP() && S.pendingPull === meP().name && me.role === 'townBoy') return 'pull';
  if (me.role && !me.surrendered) {
    if (S.stage === 'night' && me.night) return me.night.picked ? 'nightRes' : 'night';
    return 'card';
  }
  return 'board';
}

function render(force, prev) {
  if (!S) return;
  const scr = gameScreen();
  // بنحوّل الشاشة لما تتغير مرحلة اللعبة، أو إذا اللاعب أصلاً على شاشة لعب
  const key = [S.phase, S.stage, S.nightNo, S.me.surrendered, S.pendingPull, scr].join('|');
  const changed = key !== gameKey; gameKey = key;
  if (force || changed || GAME_SCREENS.includes(current) || !current) {
    if (scr === 'card' && current !== 'card') cardFlipped = false;
    if (resFlipNo !== S.nightNo) { resFlipped = false; resFlipNo = S.nightNo; }
    ({ lobby: renderLobby, card: renderCard, night: renderNight, nightRes: renderNightRes, pull: renderPull, board: renderBoard, gameover: renderGameOver })[scr]();
    show(scr);
  }
  // الصبح
  if (S.morning && S.phase !== 'lobby' && S.morning.no > (store.get(seenKey()) || 0)) showMorning();
  paintHostBar();
}

/* ---------- الغرفة ---------- */
function renderLobby() {
  $('roomCode').textContent = S.code;
  const fixed = S.hostMode === 'fixed';
  const playing = S.players.length - (fixed ? 1 : 0);
  $('pCount').textContent = `${Math.max(0, playing)} / ${S.size}`;
  $('pList').innerHTML = S.players.map(p => `<li class="${p.online ? '' : 'off'}">${avatar(p.avatar, p.name, 38, p.online ? 'on' : 'off')}
    <span class="nm">${esc(p.name)}${p.id === myId ? ' <small class="muted">(إنت)</small>' : ''}</span>
    ${p.id === S.leaderId ? `<span class="tag gold">${fixed ? '🎙️ الهوست' : '👑 الليدر'}</span>` : ''}
    ${isLeader() && p.id !== myId ? `<button class="x" data-kick="${p.id}"><span class="ms">close</span></button>` : ''}</li>`).join('');
  $('pList').querySelectorAll('[data-kick]').forEach(b => (b.onclick = () => socket.emit('kick', b.dataset.kick)));

  // الكروت
  const used = SPECIAL.reduce((a, k) => a + S.roles[k], 0);
  const rows = [...SPECIAL.map(k => [k, S.roles[k]]), ['citizen', Math.max(0, S.size - used)]];
  $('roleSteppers').innerHTML = `<div class="stepper"><div class="nm">👥 عدد اللاعبين</div>${ctl('size', S.size)}</div>` +
    rows.map(([k, v]) => `<div class="stepper"><div class="nm">${ROLES[k].icon} ${ROLES[k].name}
      <span class="tag ${ROLES[k].team}">${ROLES[k].team === 'mafia' ? 'مافيا' : 'مواطنين'}</span></div>${k === 'citizen' ? `<div class="ctl"><span class="v">${v}</span></div>` : ctl(k, v)}</div>`).join('');
  function ctl(k, v) {
    return isLeader() ? `<div class="ctl"><button data-k="${k}" data-d="-1">−</button><span class="v">${v}</span><button data-k="${k}" data-d="1">+</button></div>`
      : `<div class="ctl"><span class="v">${v}</span></div>`;
  }
  $('roleSteppers').querySelectorAll('button').forEach(b => (b.onclick = () => {
    const k = b.dataset.k, d = +b.dataset.d;
    let size = S.size, roles = { ...S.roles };
    if (k === 'size') { size = Math.max(3, Math.min(30, size + d)); roles = defaultRoles(size); }
    else roles[k] = Math.max(0, roles[k] + d);
    socket.emit('settings', { size, roles, hostMode: S.hostMode });
  }));
  paintOpts($('lobbyHost'), S.hostMode, isLeader());
  $('lobbyHost').querySelectorAll('.opt').forEach(o => (o.onclick = () => socket.emit('settings', { size: S.size, roles: S.roles, hostMode: o.dataset.m })));

  $('startBtn').classList.toggle('hidden', !isLeader());
  $('startBtn').disabled = playing !== S.size;
  $('waitMsg').textContent = isLeader()
    ? (playing < S.size ? `ناقص ${S.size - playing} لاعب` : playing > S.size ? `في ${playing - S.size} زيادة` : 'جاهزين! 🔥')
    : 'استنى الليدر يبدأ اللعبة…';
  loadLobbyFriends();
}
let lobbyFriendsAt = 0;
async function loadLobbyFriends() {
  if (!ME) return $('lobbyInvite').classList.add('hidden');
  if (Date.now() - lobbyFriendsAt < 8000) return;
  lobbyFriendsAt = Date.now();
  try {
    const list = (await api('GET', '/friends')).filter(f => f.online && !S.players.some(p => p.uid === f.id));
    $('lobbyInvite').classList.toggle('hidden', !list.length);
    $('lobbyFriends').innerHTML = list.map(f => `<div class="fcard">${avatar(f.avatar, f.username, 50, f.playing ? 'busy' : 'on')}<b>${esc(f.username)}</b>
      <button class="sbtn" data-inv="${f.id}">+ ادعي</button></div>`).join('');
    $('lobbyFriends').querySelectorAll('[data-inv]').forEach(b => (b.onclick = () => inviteFriend(b.dataset.inv, b)));
  } catch {}
}
const inviteLink = () => `${location.origin}${location.pathname}?room=${S.code}`;
$('copyLink').onclick = async () => {
  try { await navigator.clipboard.writeText(inviteLink()); toast('انسخ الرابط ✔️'); }
  catch { prompt('انسخ الرابط:', inviteLink()); }
};
$('shareLink').onclick = () => navigator.share
  ? navigator.share({ title: 'مافيا', text: `تعال العب مافيا! كود الغرفة ${S.code}`, url: inviteLink() }).catch(() => {})
  : $('copyLink').onclick();
$('startBtn').onclick = () => socket.emit('start');
function leave() { socket.emit('leave'); store.del('session'); S = null; gameKey = ''; document.body.classList.remove('has-hb'); go(ME || store.get('guest') ? 'home' : 'login'); }
$('leaveBtn').onclick = leave;
$('leaveBtn2').onclick = () => { if (confirm('بدك تطلع من الغرفة؟')) leave(); };

/* ---------- الكرت ---------- */
let cardFlipped = false;
function renderCard() {
  const role = S.me.role, r = ROLES[role];
  const hasFile = role in NAME_Y;
  $('cFlip').classList.toggle('nofile', !hasFile);
  $('cFallback').innerHTML = hasFile ? '' : `<div class="fb-icon">${r.icon}</div><div class="fb-title">${esc(r.name)}</div><p>${esc(meP()?.name)}</p>`;
  $('card').className = 'on ' + r.team + (cardFlipped ? ' flipped' : '') + (S.silenced && S.silenced.id === myId ? ' silenced' : '');
  $('cHint').textContent = cardFlipped ? 'اضغط مرة ثانية لتخبّيه' : '👆 اضغط على الكرت لتقلبه';
  if (hasFile) $('cImg').src = `img/cards/${role}.webp`;
  $('cImg').alt = r.name;
  $('cPlayer').style.setProperty('--ny', NAME_Y[role] || '60%');
  $('cPlayer').textContent = meP()?.name || '';
  renderMates();
  resetSurrender();
}
function renderMates() {
  const mates = S.me.mates;
  $('card').classList.toggle('has-mates', !!mates);
  $('cMates').innerHTML = !mates ? '' : mates.length
    ? `<span class="hd">🤝 جماعتك بالمافيا</span><div class="list">` + mates.map(m =>
        `<span class="mate${m.out ? ' out' : ''}">${ROLES[m.role].icon} ${esc(m.name)} <small>${esc(ROLES[m.role].name)}</small></span>`).join('') + '</div>'
    : `<span class="hd" style="margin:0">🕶️ إنت المافيا الوحيد بهاي الجولة</span>`;
  fitCard();
}
// الكرت بيصغر على قد اللي تحته، عشان الزر يضل ظاهر بدون سكرول
function fitCard() {
  requestAnimationFrame(() => {
    let r = 130 + (document.body.classList.contains('has-hb') ? 86 : 0);
    if (cardFlipped && S.me.mates) r += $('cMates').offsetHeight + 10;
    if (S.silenced && S.silenced.id === myId) r += 44;
    $('card').style.setProperty('--reserve', r + 'px');
  });
}
$('cFlip').onclick = () => { cardFlipped = !cardFlipped; vibrate(15); renderCard(); };
const sBtn = $('surrenderBtn');
function resetSurrender() { sBtn.classList.remove('confirm'); $('sLabel').textContent = 'سلّم كرتك'; }
sBtn.onclick = () => {
  if (!sBtn.classList.contains('confirm')) {
    sBtn.classList.add('confirm'); $('sLabel').textContent = 'متأكد؟ اضغط كمان مرة';
    clearTimeout(sBtn.t); sBtn.t = setTimeout(resetSurrender, 3000);
    return;
  }
  clearTimeout(sBtn.t); socket.emit('surrender');
};

/* ---------- شريط الهوست ---------- */
function paintHostBar() {
  const show = !!S && isController() && GAME_SCREENS.includes(current) && !$('morning').classList.contains('on');
  document.body.classList.toggle('has-hb', show);
  if (!show) return;
  const al = alive().length;
  let html;
  if (S.stage === 'night') {
    const p = S.progress || { done: 0, total: al };
    html = `<div class="lbl"><b><span class="ms">mic</span> أدوات الهوست</b><small>${p.done >= p.total ? 'كلهم اختاروا ✓' : `اختاروا ${p.done} من ${p.total}`}</small>
      <div class="bar"><i style="width:${pct(p.done, p.total)}%"></i></div></div>
      <button class="btn${p.done >= p.total ? '' : ' dark'}" id="hbEnd"><span>${p.done >= p.total ? '☀️ طلّع الصبح' : 'أنهِ الليل'}</span></button>`;
  } else if (S.pendingPull) {
    html = `<div class="lbl"><b><span class="ms">mic</span> أدوات الهوست</b><small>⛓️ ${esc(S.pendingPull)} بختار مين يسحب معه…</small></div>
      <button class="btn dark" id="hbSkip"><span>تخطّي</span></button>`;
  } else {
    html = `<div class="lbl"><b><span class="ms">mic</span> أدوات الهوست</b><small>الليلة ${S.nightNo + 1} · باقي ${al} لاعبين</small></div>
      <button class="btn" id="hbNight"><span>🌙 الليلة التالية</span></button>`;
  }
  if ($('hbIn').dataset.h !== html) { $('hbIn').innerHTML = html; $('hbIn').dataset.h = html; }
  const n = $('hbNight'), e = $('hbEnd'), sk = $('hbSkip');
  if (n) n.onclick = () => { if (confirm('نبلّش الليل؟ كل اللاعبين رح يختاروا عتلفوناتهم')) socket.emit('nextNight'); };
  if (e) e.onclick = () => { const p = S.progress; if (!p || p.done >= p.total || confirm(`لسا ${p.total - p.done} ما اختاروا. ننهي الليل؟`)) socket.emit('endNight'); };
  if (sk) sk.onclick = () => { if (confirm('نتخطّى السحب؟')) socket.emit('skipPull'); };
  if (current === 'card') fitCard();
}

/* ---------- الليل ---------- */
let nightSel = null, nightSelNo = -1;
function instruction() {
  const role = S.me.role, n = S.me.night;
  if (n.killer) {
    const killers = role !== 'mafiaSheikh';
    return killers ? 'شيخكم طالع — اختاروا مين تغتالوا الليلة (الأكثرية بتقرر)' : 'اختار مين بدكم تغتالوا الليلة';
  }
  return ({
    mafiaGirl: 'اقترحي على شيخ المافيا مين تغتالوا', mafia: 'اقترح على شيخ المافيا مين تغتالوا',
    mafiaBoy: 'اختار مين بدك تسكّته بكرة',
    doctor: 'اختاري مين بدك تحمي الليلة (بتقدري تحمي حالك)',
    sniper: n.bullet ? 'اختار مين بدك تقنص (معك طلقة وحدة) — أو ولا حدا' : 'طلقتك خلصت — مين بتشك إنه مافيا؟',
    townSheikh: 'اختار مين بدك تسأل عنه',
  })[role] || 'مين بتشك إنه مافيا؟';
}
function nightTop(noEl, progEl) {
  $(noEl).innerHTML = `<span class="ms">bedtime</span> الليلة ${S.nightNo}`;
  const p = S.progress || { done: 0, total: 0 };
  $(progEl).innerHTML = `<span class="dot"></span> اختاروا ${p.done} من ${p.total}`;
}
function renderNight() {
  if (nightSelNo !== S.nightNo) { nightSel = null; nightSelNo = S.nightNo; }
  nightTop('nNo', 'nProg');
  $('nInstr').textContent = instruction();
  const sug = S.me.night.suggest;
  $('nSugg').classList.toggle('hidden', !(sug && sug.length));
  if (sug && sug.length) $('nSugg').textContent = '🤝 اقتراحات جماعتك: ' + sug.map(s => `${s.from} ← ${pById(s.to)?.name || '؟'}`).join(' · ');
  const votes = {};
  (sug || []).forEach(s => (votes[s.to] = (votes[s.to] || 0) + 1));
  const canSelf = S.me.role === 'doctor';
  const tiles = S.players.filter(p => p.playing).map(p => {
    const out = p.surrendered, self = p.id === myId, dis = out || (self && !canSelf);
    const sub = out ? 'طالع' : self ? 'إنت' : votes[p.id] ? `${votes[p.id]} ${votes[p.id] > 1 ? 'أصوات' : 'صوت'}` : 'لاعب';
    return `<button class="tile${nightSel === p.id ? ' sel' : ''}" data-t="${p.id}" ${dis ? 'disabled' : ''}>${avatar(p.avatar, p.name, 58)}
      <b>${esc(p.name)}</b><small class="${votes[p.id] ? 'v' : ''}">${sub}</small></button>`;
  });
  tiles.push(`<button class="tile${nightSel === 'none' ? ' sel' : ''}" data-t="none"><span class="none"><span class="ms">block</span></span><b>ولا حدا</b><small>تخطّي الليلة</small></button>`);
  $('nGrid').innerHTML = tiles.join('');
  $('nGrid').querySelectorAll('.tile').forEach(t => (t.onclick = () => { nightSel = t.dataset.t; vibrate(10); renderNight(); }));
  $('nConfirm').disabled = !nightSel;
}
$('nConfirm').onclick = () => {
  if (!nightSel) return;
  socket.emit('pick', { target: nightSel === 'none' ? null : nightSel });
  vibrate(30);
};
let resFlipped = false, resFlipNo = -1;
function renderNightRes() {
  nightTop('rNo', 'rProg');
  const res = S.me.night.result || { kind: 'chose' };
  const t = res.target && pById(res.target);
  let front;
  if (res.kind === 'ask') {
    front = `<div class="hand ${res.answer}">${res.answer === 'up' ? '👍' : '👎'}</div>${avatar(t?.avatar, res.name, 64)}<b>${esc(res.name)}</b>`;
  } else {
    front = `<div class="moon">🌙</div>${t ? avatar(t.avatar, t.name, 64) : '<span class="none" style="font-size:48px">🚫</span>'}
      <b>اخترت: ${t ? esc(t.name) : 'ولا حدا'}</b><small>اختيارك انحفظ 🤫</small>`;
  }
  $('rFront').innerHTML = front;
  $('nightRes').classList.toggle('flipped', resFlipped);
  $('rHint').textContent = resFlipped ? 'اضغط مرة ثانية لتخبّيه' : '👆 اضغط على الكرت لتقلبه';
  const who = new Set((S.progress && S.progress.who) || []);
  $('rWait').innerHTML = alive().map(p => `<span title="${esc(p.name)}">${avatar(p.avatar, p.name, 40).replace('</span>', who.has(p.id) ? '<span class="ok">✓</span></span>' : '</span>')}</span>`).join('');
}
$('rFlip').onclick = () => { resFlipped = !resFlipped; vibrate(15); renderNightRes(); };

/* ---------- ولد الصالحين ---------- */
let pullSel = null;
function renderPull() {
  $('pGrid').innerHTML = alive().map(p => `<button class="tile green${pullSel === p.id ? ' sel' : ''}" data-t="${p.id}">${avatar(p.avatar, p.name, 58)}<b>${esc(p.name)}</b><small>لاعب</small></button>`).join('');
  $('pGrid').querySelectorAll('.tile').forEach(t => (t.onclick = () => { pullSel = t.dataset.t; renderPull(); }));
  $('pConfirm').disabled = !pullSel;
}
$('pConfirm').onclick = () => { if (pullSel && confirm(`متأكد بدك تسحب ${pById(pullSel)?.name} معك؟`)) { socket.emit('pull', pullSel); pullSel = null; } };
$('pSkip').onclick = () => { if (confirm('أكيد ما بدك تسحب حدا؟')) socket.emit('pull', null); };

/* ---------- اللي طالعين / الهوست ---------- */
function renderBoard() {
  const night = S.stage === 'night';
  let head;
  if (isHost()) head = `<div class="center" style="font-size:54px">🎙️</div><h1>إنت الهوست</h1><p class="sub">${night ? `الليلة ${S.nightNo} — بتشوف مين اختار مين` : 'بتشوف كل الكروت. أدير اللعبة من الشريط تحت'}</p>`;
  else if (night) head = `<div class="bigmoon">🌙</div><h1>المدينة نايمة…</h1><p class="sub">بنستنى الباقي يختاروا</p>`;
  else if (S.me.role) head = `<div class="center" style="font-size:54px">🪦</div><h1>إنت طالع</h1><p class="sub">كمّل تفرّج على اللعبة… بس بدون ما تحكي 🤫</p>`;
  else head = `<div class="center" style="font-size:54px">👀</div><h1>بتتفرّج</h1>`;
  $('boardHead').innerHTML = head;
  const all = S.allRoles, picks = S.allPicks || {};
  $('boardPTitle').textContent = all ? 'كروت الكل' : 'اللاعبين';
  const who = new Set((S.progress && S.progress.who) || []);
  $('bList').innerHTML = S.players.filter(p => p.playing).map(p => {
    const role = all && all[p.id];
    let right = '';
    if (role) right = `<span class="tag ${ROLES[role].team}">${ROLES[role].icon} ${ROLES[role].name}</span>`;
    else if (p.team) right = `<span class="tag ${p.team}">${TEAM_NAME[p.team]}</span>`;
    let pick = '';
    if (night && all && !p.surrendered) pick = p.id in picks ? `<small class="muted"> ← ${picks[p.id] ? esc(pById(picks[p.id])?.name) : 'ولا حدا'}</small>` : '<small class="muted"> …</small>';
    else if (night && !p.surrendered && who.has(p.id)) pick = ' <small style="color:var(--gold)">✓</small>';
    return `<li class="${p.surrendered ? 'dead' : ''}">${avatar(p.avatar, p.name, 36)}<span class="nm">${esc(p.name)}${pick}</span>${right}</li>`;
  }).join('');
  $('resetBtn').classList.toggle('hidden', !isLeader());
}
$('boardLog').onclick = () => openLiveLog();
$('resetBtn').onclick = () => { if (confirm('متأكد بدك تنهي الجولة؟')) socket.emit('reset'); };

/* ---------- الكشف (سلّم كرتك / سحب) ---------- */
function showReveal({ name, avatar: av, team, host, pulledBy }) {
  $('revealWrap').innerHTML = `${pulledBy ? `<div style="font-size:44px">⛓️</div><div class="rh">${esc(pulledBy)} سحب ${esc(name)} معه!</div>` : ''}
    ${avatar(av, name, 120)}<div class="rn">${esc(name)}</div>
    <div class="badge3d ${team}">${team === 'mafia' ? '🔪 مافيا' : '🕊️ مواطن صالح'}</div>
    ${host ? `<div class="rh">🎙️ وصار هو الهوست</div>` : ''}<div class="tap">اضغط بأي مكان للإغلاق</div>`;
  $('reveal').className = 'overlay on';
  vibrate(team === 'mafia' ? [200, 100, 200] : 150);
  beep(team === 'mafia' ? 220 : 880, .3);
  clearTimeout(showReveal.t); showReveal.t = setTimeout(() => ($('reveal').className = 'overlay'), 6000);
}
$('reveal').onclick = () => ($('reveal').className = 'overlay');

/* ---------- الصبح ---------- */
function evHTML(e, events) {
  const badge = t => `<span class="tag ${t}">${TEAM_NAME[t]}</span>`;
  const pav = id => { const p = S && pById(id); return avatar(p?.avatar, p?.name, 34); };
  switch (e.t) {
    case 'kill': return `<div class="ev"><span class="ei">🔪</span><span class="et">${esc(e.name)} انغتل الليلة</span><span class="avs">${pav(e.pid)}</span>${badge(e.team)}</div>`;
    case 'saved': return `<div class="ev saved"><span class="ei">⚕️</span><span class="et">المافيا حاولوا يغتالوا حدا… بس بنت الصالحين حمته!<small>ما حدا مات</small></span></div>`;
    case 'snipe': {
      const sn = events.find(x => x.t === 'sniper');
      if (sn) return `<div class="ev"><span class="ei">🎯</span><span class="et">القناص قنص مواطن صالح… وطلعوا الاثنين<small>${esc(e.name)} و ${esc(sn.name)}</small></span><span class="avs">${pav(e.pid)}${pav(sn.pid)}</span>${badge('town')}</div>`;
      return `<div class="ev"><span class="ei">🎯</span><span class="et">${esc(e.name)} انقنص</span><span class="avs">${pav(e.pid)}</span>${badge(e.team)}</div>`;
    }
    case 'sniper': return '';
    case 'silence': return `<div class="ev"><span class="ei">🤐</span><span class="et">${esc(e.name)} مسكّت اليوم<small>ممنوع يحكي</small></span></div>`;
    case 'host': return `<div class="ev"><span class="ei">🎙️</span><span class="et">${esc(e.name)} صار الهوست</span></div>`;
    case 'calm': return `<div class="ev"><span class="ei">🌙</span><span class="et">ليلة هادية… ما صار إشي</span></div>`;
  }
  return '';
}
const seenKey = () => `seen_${S.code}_${S.startedAt}`;
function showMorning() {
  const m = S.morning;
  if ($('morning').classList.contains('on') && $('morning').dataset.no == m.no) return;
  $('morning').dataset.no = m.no;
  const iDied = m.events.some(e => ['kill', 'snipe', 'sniper'].includes(e.t) && e.pid === myId);
  $('mWrap').innerHTML = `<div class="center" style="font-size:54px">☀️</div><h1>صباح الخير</h1><p class="sub">الليلة ${m.no}</p>
    ${m.events.map(e => evHTML(e, m.events)).join('')}
    <p class="muted center small">النقاش والتصويت بالإيد · اللي بيطلع بيكبس سلّم كرتك</p>
    <button class="btn" id="mOk"><span>${S.me.role && !S.me.surrendered ? 'رجوع لكرتي' : 'تمام'}</span></button>`;
  $('morning').className = 'overlay on';
  paintHostBar();
  $('mOk').onclick = () => {
    store.set(seenKey(), m.no);
    $('morning').className = 'overlay';
    if (iDied) showOut(m.events.find(e => e.pid === myId).t);
    paintHostBar();
  };
}
function showOut(t) {
  const role = S.me.role;
  $('oWrap').innerHTML = `<div class="outcard"><img src="img/cards/${role}.webp" alt=""><div class="stamp">طالع</div></div>
    <h1>${t === 'kill' ? '🔪 انغتلت الليلة' : '🎯 انقنصت'}</h1>
    <p class="sub">خلص دورك… بس فيك تضل تتفرج وما تحكي 🤫</p>
    <button class="btn" id="oOk"><span>تفرّج على اللعبة</span></button>`;
  $('outOv').className = 'overlay on';
  vibrate([300, 100, 300]);
  $('oOk').onclick = () => ($('outOv').className = 'overlay');
}

/* ---------- نهاية اللعبة ---------- */
function renderGameOver() {
  const mw = S.winner === 'mafia';
  $('goBanner').className = 'banner ' + (mw ? 'mafia' : 'town');
  $('goBanner').innerHTML = `<div class="bt">${mw ? 'المافيا فازت! 🔪' : 'الصالحين فازوا! 🏆'}</div>
    <small>${mw ? 'المافيا سيطروا على المدينة' : 'المدينة نضفت من المافيا'} · ${nightsTxt(S.nightNo)}</small>`;
  const all = S.allRoles || {};
  $('goCards').innerHTML = S.players.filter(p => all[p.id]).map(p => {
    const r = all[p.id], win = ROLES[r].team === S.winner;
    return `<div class="mini ${win ? 'win' : 'lose'}">${win ? '<span class="cr">👑</span>' : ''}<img src="img/cards/${r}.webp" alt="">${esc(p.name)}<small>${ROLES[r].name}</small></div>`;
  }).join('');
  const A = { kills: ['🔪', 'أكثر واحد اغتال'], saves: ['🛡️', 'أحسن حماية'], snipe: ['🎯', 'قنصة اللعبة'], found: ['👳', 'كشف المافيا'] };
  const aw = S.awards || [];
  $('goAwardsP').classList.toggle('hidden', !aw.length);
  $('goAwards').innerHTML = aw.map(a => `<div class="award">${A[a.k][0]} ${A[a.k][1]}: <span style="color:var(--gold)">${esc(a.name)}</span> <small class="muted">(${a.n})</small></div>`).join('');
  $('goAgain').classList.toggle('hidden', !isLeader());
  $('goWait').classList.toggle('hidden', isLeader());
}
$('goAgain').onclick = () => socket.emit('reset');
$('goLog').onclick = () => (S.gameId ? openGameLog(S.gameId) : openLiveLog());
$('goShare').onclick = () => {
  const text = `${S.winner === 'mafia' ? 'المافيا فازت 🔪' : 'الصالحين فازوا 🏆'} بلعبة مافيا! ${nightsTxt(S.nightNo)} · ${S.players.filter(p => p.playing).length} لاعبين`;
  if (navigator.share) navigator.share({ title: 'مافيا', text, url: location.origin }).catch(() => {});
  else navigator.clipboard?.writeText(text).then(() => toast('انسخت النتيجة ✔️'));
};
$('goLeave').onclick = leave;

/* =====================================================================
   سجل اللعبة
   ===================================================================== */
function openLiveLog() {
  renderLog({ num: null, code: S.code, players: S.players.filter(p => p.playing).map(p => ({ ...p, role: S.allRoles ? S.allRoles[p.id] : null, team: p.team })),
    winner: S.winner, log: S.log, at: null, live: true });
  go('gamelog');
}
async function openGameLog(id) {
  try { renderLog(await api('GET', '/games/' + id)); go('gamelog'); } catch (err) { toast(err.message); }
}
function logLine(e) {
  const b = t => t ? `<span class="tag ${t}">${TEAM_NAME[t]}</span>` : '';
  switch (e.t) {
    case 'vote': return ['🗳️', `${esc(e.name)} طلع تصويت${e.host ? ' · صار الهوست' : ''}`, b(e.team)];
    case 'kill': return ['🔪', `${esc(e.name)} انغتل`, b(e.team)];
    case 'saved': return ['🛡️', 'بنت الصالحين حمت حدا وما حدا مات', ''];
    case 'snipe': return ['🎯', `${esc(e.name)} انقنص`, b(e.team)];
    case 'sniper': return ['💥', `${esc(e.name)} طلع مع اللي قنصه`, b(e.team)];
    case 'silence': return ['🤐', `${esc(e.name)} انسكّت`, ''];
    case 'pull': return ['⛓️', `${esc(e.name)} سحب ${esc(e.tname)} معه`, b(e.team)];
    case 'host': return ['🎙️', `${esc(e.name)} صار الهوست`, ''];
    case 'calm': return ['🌙', 'ليلة هادية… ما صار إشي', ''];
  }
  return ['•', '', ''];
}
function renderLog(g) {
  const n = g.players.filter(p => p.role).length || g.players.length;
  $('glMeta').textContent = [g.num ? `لعبة #${g.num}` : 'اللعبة الحالية', `غرفة ${g.code}`, `${n} لاعبين`, g.endedAt ? ago(g.endedAt) : ''].filter(Boolean).join(' · ');
  let html = g.winner ? `<div class="banner ${g.winner}"><div class="bt" style="font-size:30px">${g.winner === 'mafia' ? 'المافيا فازت 🔪' : 'الصالحين فازوا 🏆'}</div></div>` : '';
  let lastHd = '';
  const items = [];
  for (const e of g.log) {
    const hd = e.night ? `الليلة ${e.night}` : `النهار ${e.day || 1}`;
    if (hd !== lastHd) { items.push(`<span class="hd">${hd}</span>`); lastHd = hd; }
    const [i, t, bd] = logLine(e);
    if (t) items.push(`<div class="it"><span class="ei">${i}</span><span class="tx">${t}</span>${bd}</div>`);
  }
  html += `<div class="panel"><div class="tl">${items.length ? items.join('') : '<div class="empty">لسا ما صار إشي</div>'}</div></div>`;
  const withRoles = g.players.filter(p => p.role);
  if (withRoles.length) {
    html += `<div class="panel"><h2>🃏 كروت الكل</h2><ul class="plist">${withRoles.map(p => `<li class="${p.won === false && g.winner ? 'off' : ''}">${avatar(p.avatar, p.name, 34)}
      <span class="nm">${esc(p.name)}</span><span class="tag ${p.won ? 'gold' : ROLES[p.role].team}">${ROLES[p.role].icon} ${ROLES[p.role].name}</span></li>`).join('')}</ul></div>`;
  }
  if (!g.live && S && S.phase === 'ended' && isLeader()) html += `<button class="btn" onclick="socket.emit('reset')"><span>جولة جديدة</span></button>`;
  $('glBody').innerHTML = html;
}

/* =====================================================================
   ألعابي
   ===================================================================== */
let mgFilter = 'all', mgData = [];
const MG = [['all', 'الكل'], ['won', 'فزت'], ['lost', 'خسرت'], ['mafia', 'كنت مافيا'], ['town', 'كنت مواطن']];
$('mgFilter').innerHTML = MG.map(([v, t]) => `<button data-v="${v}" class="${v === 'all' ? 'on' : ''}">${t}</button>`).join('');
$('mgFilter').onclick = e => { const b = e.target.closest('button'); if (!b) return; mgFilter = b.dataset.v; [...$('mgFilter').children].forEach(x => x.classList.toggle('on', x === b)); paintMyGames(); };
async function loadMyGames() { try { mgData = await api('GET', '/games'); paintMyGames(); } catch (err) { toast(err.message); } }
function paintMyGames() {
  const list = mgData.filter(g => mgFilter === 'all' || (mgFilter === 'won' && g.won) || (mgFilter === 'lost' && g.role && !g.won)
    || (g.role && ROLES[g.role].team === mgFilter));
  $('mgList').innerHTML = list.length ? list.map(gameRow).join('') : '<div class="empty">ما في ألعاب هون لسا</div>';
  $('mgList').querySelectorAll('[data-game]').forEach(b => (b.onclick = () => openGameLog(b.dataset.game)));
}
function gameRow(g) {
  const r = g.role ? ROLES[g.role] : null;
  return `<button class="li" data-game="${g.id}" style="text-align:start"><span style="font-size:26px">${r ? r.icon : '🎙️'}</span>
    <span class="info"><b>${r ? r.name : 'كنت الهوست'} <small style="display:inline;color:var(--muted)">#${g.code}</small></b>
    <small>${new Date(g.at).toLocaleDateString('ar', { day: 'numeric', month: 'short' })} · ${g.players} لاعبين · ${nightsTxt(g.nights)} · ${g.winner === 'mafia' ? 'المافيا فازت' : 'الصالحين فازوا'}</small></span>
    ${g.role ? `<span class="tag ${g.won ? 'gold' : 'grey'}">${g.won ? 'فوز' : 'خسارة'}</span>` : ''}</button>`;
}

/* =====================================================================
   لوحة الصدارة
   ===================================================================== */
const LB = { scope: 'all', period: 'all', sort: 'rate' };
[['lbScope', 'scope'], ['lbPeriod', 'period'], ['lbSort', 'sort']].forEach(([id, k]) => ($(id).onclick = e => {
  const b = e.target.closest('button'); if (!b) return;
  if (k === 'scope' && b.dataset.v === 'friends' && !ME) return toast('سجّل دخول لتشوف أصحابك');
  LB[k] = b.dataset.v; [...$(id).children].forEach(x => x.classList.toggle('on', x === b)); loadBoard();
}));
async function loadBoard() {
  try {
    const d = await api('GET', `/leaderboard?scope=${LB.scope}&period=${LB.period}&sort=${LB.sort}`);
    $('lbNote').textContent = `لازم تلعب ${d.min} ألعاب على الأقل لتدخل الترتيب`;
    const [a, b, c] = d.list;
    const pod = (p, cls, medal) => p ? `<div class="pod ${cls}" data-user="${p.id}"><span class="medal">${medal}</span>${avatar(p.avatar, p.username)}<b>${esc(p.username)}</b>
      <span class="r">${p.rate}%</span><small>${p.wins} فوز</small></div>` : '<div></div>';
    $('lbPodium').innerHTML = d.list.length ? `<div class="podium">${pod(b, 'p2', '🥈')}${pod(a, 'p1', '👑')}${pod(c, 'p3', '🥉')}</div>` : '<div class="empty">لسا ما حدا دخل الترتيب… العبوا أكثر! 🔥</div>';
    $('lbList').innerHTML = d.list.slice(3).map((p, i) => lbRow(p, i + 4)).join('') +
      (d.mine ? `<div class="li mine">${d.mine.rank ? `<span class="num">#${d.mine.rank}</span>` : ''}${avatar(d.mine.avatar, d.mine.username, 40)}
        <span class="info"><b>${esc(d.mine.username)} (إنت)</b><small>${d.mine.rank ? `عدد الألعاب ${d.mine.games}` : `لعبت ${d.mine.games} من ${d.min} لتدخل الترتيب`}</small></span>
        <span class="rt"><b>${d.mine.rate}%</b><br><small class="muted">${d.mine.wins} فوز</small></span></div>` : '');
    document.querySelectorAll('#leaderboard [data-user]').forEach(x => (x.onclick = () => openUser(x.dataset.user)));
  } catch (err) { toast(err.message); }
}
function lbRow(p, n) {
  return `<div class="li" data-user="${p.id}"><span class="num">${n}</span>${avatar(p.avatar, p.username, 40)}
    <span class="info"><b>${esc(p.username)}</b><small>عدد الألعاب ${p.games}</small><div class="tr"><i style="width:${p.rate}%"></i></div></span>
    <span class="rt"><b>${p.rate}%</b><br><small class="muted">${p.wins} فوز</small></span></div>`;
}

/* =====================================================================
   الأصدقاء
   ===================================================================== */
let frData = [];
async function loadFriends() {
  paintHello();
  try { frData = await api('GET', '/friends'); paintFriends(); } catch (err) { toast(err.message); }
}
$('frSearch').oninput = paintFriends;
function statusOf(f) {
  if (f.playing) return ['busy', 'بيلعب هلأ'];
  if (f.online) return ['on', 'متصل الآن'];
  return ['off', f.lastSeen ? `آخر ظهور ${ago(f.lastSeen)}` : 'مش متصل'];
}
function paintFriends() {
  const q = $('frSearch').value.trim().toLowerCase();
  const list = frData.filter(f => !q || f.username.toLowerCase().includes(q));
  $('frList').innerHTML = list.length ? list.map(f => {
    const [cls, txt] = statusOf(f);
    return `<div class="li">${avatar(f.avatar, f.username, 48, cls)}<span class="info" data-user="${f.id}"><b>${esc(f.username)}</b><small class="${cls}">${txt}</small></span>
      <span class="acts2"><button class="sbtn gold" data-inv="${f.id}">ادعيه للعبة</button><button class="sbtn" data-user="${f.id}" style="padding:9px"><span class="ms">more_horiz</span></button></span></div>`;
  }).join('') : `<div class="empty">${frData.length ? 'ما لقينا حدا بهالاسم' : 'لسا ما عندك أصحاب… اضغط "أضف صديق" 👇'}</div>`;
  $('frList').querySelectorAll('[data-inv]').forEach(b => (b.onclick = () => inviteFriend(b.dataset.inv, b)));
  $('frList').querySelectorAll('[data-user]').forEach(b => (b.onclick = () => openUser(b.dataset.user)));
}

/* ---------- إضافة صديق ---------- */
function relBtn(u) {
  if (u.relation === 'friend') return `<span class="tag grey">صديق</span>`;
  if (u.relation === 'sent') return `<span class="sbtn" style="border-color:var(--gold2);color:var(--gold)">تم الإرسال ✓</span>`;
  if (u.relation === 'received') return `<button class="sbtn gold" data-acc="${u.id}">قبول</button>`;
  return `<button class="sbtn gold" data-add="${u.id}">+ أضف</button>`;
}
function bindRel(box, reload) {
  box.querySelectorAll('[data-add]').forEach(b => (b.onclick = async () => { await sendRequest(b.dataset.add); reload(); }));
  box.querySelectorAll('[data-acc]').forEach(b => (b.onclick = async () => { try { await api('POST', '/friends/accept', { from: b.dataset.acc }); toast('صرتوا أصحاب ✓'); reload(); } catch (e) { toast(e.message); } }));
  box.querySelectorAll('[data-user]').forEach(b => (b.onclick = () => openUser(b.dataset.user)));
}
async function sendRequest(to) {
  try { const r = await api('POST', '/friends/request', { to }); toast(r.relation === 'friend' ? 'صرتوا أصحاب ✓' : 'انبعت طلب الصداقة ✓'); return true; }
  catch (e) { toast(e.message); return false; }
}
const addLink = () => `${location.origin}${location.pathname}?add=${ME.friendCode}`;
async function loadAddFriend() {
  $('afCode').textContent = ME.friendCode;
  $('afQr').classList.add('hidden');
  $('afResults').innerHTML = '';
  try {
    const rec = await api('GET', '/recent-players');
    $('afRecent').innerHTML = rec.length ? `<h2>لعبت معهم مؤخراً</h2><div class="hrow">${rec.map(u => `<div class="fcard">${avatar(u.avatar, u.username, 52)}
      <b data-user="${u.id}">${esc(u.username)}</b>${relBtn(u)}</div>`).join('')}</div>` : '';
    bindRel($('afRecent'), loadAddFriend);
  } catch {}
}
$('afForm').onsubmit = async e => {
  e.preventDefault();
  const q = $('afQ').value.trim();
  if (!q) return;
  try {
    const list = await api('GET', '/users/search?q=' + encodeURIComponent(q));
    $('afResults').innerHTML = `<h2>نتائج البحث</h2><div class="list">${list.length ? list.map(u => `<div class="li">${avatar(u.avatar, u.username, 46)}
      <span class="info" data-user="${u.id}"><b>${esc(u.username)}</b><small>${u.games} لعبة · ${u.rate}% فوز</small></span>${relBtn(u)}</div>`).join('') : '<div class="empty">ما لقينا حدا</div>'}</div>`;
    bindRel($('afResults'), () => $('afForm').onsubmit(new Event('submit')));
  } catch (err) { toast(err.message); }
};
$('afCopy').onclick = () => navigator.clipboard?.writeText(ME.friendCode).then(() => toast('انسخ الكود ✔️')).catch(() => prompt('الكود:', ME.friendCode));
$('afShare').onclick = () => navigator.share
  ? navigator.share({ title: 'مافيا', text: `ضيفني بلعبة مافيا! كودي ${ME.friendCode}`, url: addLink() }).catch(() => {})
  : navigator.clipboard?.writeText(addLink()).then(() => toast('انسخ رابط الإضافة ✔️'));
$('afQrBtn').onclick = () => {
  const box = $('afQrBox');
  $('afQr').classList.toggle('hidden');
  if (!box.firstChild && window.QRCode) new QRCode(box, { text: addLink(), width: 180, height: 180, colorDark: '#160307', colorLight: '#ffffff' });
};

/* ---------- طلبات الصداقة ---------- */
let rqTab = 'received';
$('rqTabs').onclick = e => { const b = e.target.closest('button'); if (!b) return; rqTab = b.dataset.v; [...$('rqTabs').children].forEach(x => x.classList.toggle('on', x === b)); loadRequests(); };
async function loadRequests() {
  try {
    const d = await api('GET', '/friends/requests');
    $('rqTabs').children[0].textContent = `وصلتني (${d.received.length})`;
    $('rqTabs').children[1].textContent = `بعتها (${d.sent.length})`;
    const list = d[rqTab];
    $('rqList').innerHTML = list.length ? list.map(u => rqTab === 'received'
      ? `<div class="li" id="rq_${u.id}">${avatar(u.avatar, u.username, 48)}<span class="info" data-user="${u.id}"><b>${esc(u.username)}</b>
          <small>بدو يضيفك صديق · ${ago(u.at)}</small>${u.together ? `<small style="color:var(--gold)">لعبتوا مع بعض ${u.together} مرات</small>` : ''}</span>
          <span class="acts2"><button class="sbtn gold" data-acc="${u.id}">قبول</button><button class="sbtn" data-rej="${u.id}">رفض</button></span></div>`
      : `<div class="li" style="opacity:.85">${avatar(u.avatar, u.username, 48)}<span class="info" data-user="${u.id}"><b>${esc(u.username)}</b><small>بانتظار الرد</small></span>
          <button class="sbtn" data-can="${u.id}">إلغاء الطلب</button></div>`).join('')
      : `<div class="empty"><div style="font-size:54px">✉️</div>ما في طلبات ${rqTab === 'received' ? 'جديدة' : 'مبعوتة'}</div>`;
    $('rqList').querySelectorAll('[data-acc]').forEach(b => (b.onclick = async () => {
      try {
        await api('POST', '/friends/accept', { from: b.dataset.acc });
        b.parentElement.innerHTML = `<span class="tag town">صرتوا أصحاب ✓</span><button class="sbtn gold" data-inv="${b.dataset.acc}">ادعيه للعبة</button>`;
        $('rqList').querySelectorAll('[data-inv]').forEach(x => (x.onclick = () => inviteFriend(x.dataset.inv, x)));
        ME = await api('GET', '/me'); paintHello();
      } catch (e) { toast(e.message); }
    }));
    $('rqList').querySelectorAll('[data-rej]').forEach(b => (b.onclick = async () => { await api('POST', '/friends/reject', { from: b.dataset.rej }); ME = await api('GET', '/me'); paintHello(); loadRequests(); }));
    $('rqList').querySelectorAll('[data-can]').forEach(b => (b.onclick = async () => { await api('POST', '/friends/cancel', { to: b.dataset.can }); loadRequests(); }));
    $('rqList').querySelectorAll('[data-user]').forEach(b => (b.onclick = () => openUser(b.dataset.user)));
  } catch (err) { toast(err.message); }
}

/* =====================================================================
   البروفايلات
   ===================================================================== */
const STAT_TILES = [
  ['winsTown', '🛡️', 'فزت وأنا مواطن', 'g'], ['winsMafia', '🗡️', 'فزت وأنا مافيا', 'r'],
  ['saves', '⚕️', 'حميت صح وأنا بنت الصالحين', 'g'], ['snipeMafia', '🎯', 'قنصت مافيا وأنا القناص', 'g'],
  ['snipeTown', '⚠️', 'قنصت مواطن بالغلط', 'r'], ['kills', '🔪', 'اغتلت وأنا بالمافيا', 'r'],
  ['found', '👎', 'كشفت مافيا وأنا شيخ الصالحين', 'g'], ['silenced', '🤐', 'سكّت حدا وأنا ولد المافيا', 'r'],
  ['pulled', '⛓️', 'سحبت حدا معي وأنا ولد الصالحين', 'g'], ['votedOut', '🙌', 'طلعت تصويت', ''],
  ['killed', '🌙', 'انغتلت بالليل', ''], ['hosted', '🎙️', 'كنت الهوست', ''],
];
function tilesHTML(s, she) {
  const t = she ? x => x.replace('فزت', 'فاز').replace('حميت', 'حمى').replace('قنصت', 'قنص').replace('اغتلت', 'اغتال').replace('كشفت', 'كشف')
    .replace('سكّت', 'سكّت').replace('سحبت', 'سحب').replace('طلعت', 'طلع').replace('انغتلت', 'انغتل').replace('كنت', 'كان').replace('وأنا', 'وهو').replace('معي', 'معه') : x => x;
  return `<div class="tiles">${STAT_TILES.map(([k, i, l, c]) => `<div class="st ${c}"><div class="top"><b>${s[k] || 0}</b><span class="i">${i}</span></div><span>${t(l)}</span></div>`).join('')}</div>`;
}
function favHTML(fav, label) {
  if (!fav) return '';
  const r = ROLES[fav.role];
  return `<div class="panel"><h2>🃏 ${label} <span class="more tag mafia">${fav.count} مرة</span></h2>
    <div class="favrole"><img src="img/cards/${fav.role}.webp" alt=""><div><span class="tag ${r.team}">فريق ${r.team === 'mafia' ? 'المافيا' : 'الصالحين'}</span>
    <div style="font-family:Lalezar;font-size:26px;color:var(--gold)">${r.name}</div><small class="muted">نسبة الفوز فيه ${fav.rate}%</small></div></div></div>`;
}
function recentHTML(list, all) {
  return `<div class="panel"><h2>🕓 آخر الألعاب ${all ? '<button class="more" data-go="mygames">كل ألعابي</button>' : ''}</h2>
    <div class="list">${list.length ? list.map(gameRow).join('') : '<div class="empty">لسا ما في ألعاب</div>'}</div></div>`;
}
function headHTML(d, crown) {
  return `<div class="phead"><span style="position:relative">${avatar(d.avatar, d.username, 108)}${crown ? '<span class="crown">👑</span>' : ''}</span>
    <div class="nm">${esc(d.username)}</div><div class="handle">${esc(d.friendCode)}</div>
    <div class="rank"><div class="row"><b>🎖️ ${d.title}</b><span class="tag mafia">المستوى ${d.level}</span></div>
    <div class="xp"><i style="width:${pct(d.xp, d.next)}%"></i></div><div class="row" style="justify-content:space-between;margin-top:4px"><small class="muted">الخبرة (XP)</small><small class="muted">${d.xp} / ${d.next}</small></div></div></div>
    <div class="counters"><div><b>${d.stats.games}</b><small>لعبة</small></div><div><b style="color:var(--green)">${d.stats.wins}</b><small>فوز</small></div><div><b>${d.stats.rate}%</b><small>نسبة الفوز</small></div></div>`;
}
async function loadProfile() {
  try {
    const d = await api('GET', '/profile');
    $('pfBody').innerHTML = headHTML(d, d.rank && d.rank <= 10) +
      `<div class="center"><button class="linkbtn" data-go="friends">👥 ${d.friends} صديق</button></div>
      <div class="row"><button class="btn grow sm" data-go="settings"><span><span class="ms">edit</span> تعديل الحساب</span></button>
      <button class="btn dark grow sm" id="pfShare"><span><span class="ms">share</span> مشاركة البروفايل</span></button></div>
      <div class="panel"><h2>📊 إحصائياتي</h2>${tilesHTML(d.stats)}</div>${favHTML(d.fav, 'أكثر كرت طلعلي')}${recentHTML(d.recent, true)}`;
    $('pfShare').onclick = () => {
      const text = `بروفايلي بلعبة مافيا: ${d.stats.games} لعبة · ${d.stats.rate}% فوز. ضيفني: ${ME.friendCode}`;
      navigator.share ? navigator.share({ title: 'مافيا', text, url: addLink() }).catch(() => {}) : navigator.clipboard?.writeText(text + ' ' + addLink()).then(() => toast('انسخ ✔️'));
    };
    bindGames($('pfBody'));
  } catch (err) { toast(err.message); }
}
function bindGames(box) { box.querySelectorAll('[data-game]').forEach(b => (b.onclick = () => openGameLog(b.dataset.game))); }

let fpUser = null;
async function openUser(id) {
  if (!ME) return toast('سجّل دخول لتشوف البروفايلات');
  if (id === ME.id) return go('profile');
  try {
    const d = await api('GET', '/users/' + id);
    fpUser = d;
    const [cls, txt] = statusOf(d);
    const rel = d.relation === 'friend' ? `<button class="btn dark grow sm" id="fpRel"><span>صديق ✓</span></button>`
      : d.relation === 'sent' ? `<button class="btn dark grow sm" disabled><span>تم إرسال الطلب ✓</span></button>`
      : d.relation === 'received' ? `<button class="btn grow sm" id="fpAcc"><span>قبول الطلب</span></button>`
      : `<button class="btn grow sm" id="fpAdd"><span><span class="ms">person_add</span> أضف صديق</span></button>`;
    $('fpBody').innerHTML = headHTML(d).replace('<div class="handle">', `<small class="${cls}" style="color:${cls === 'on' ? 'var(--green)' : cls === 'busy' ? '#ff8d97' : 'var(--muted)'};font-weight:700">● ${txt}</small><div class="handle">`) +
      `<div class="row">${d.relation === 'friend' ? `<button class="btn grow sm" data-inv="${d.id}"><span>ادعيه للعبة</span></button>` : ''}${rel}</div>
      <div class="panel red"><h2>🤝 أنا و${esc(d.username)}</h2>
        <div class="row" style="justify-content:center;gap:18px">${avatar(ME.avatar, ME.username, 54)}<span style="color:var(--gold);font-size:24px">⚔️</span>${avatar(d.avatar, d.username, 54)}</div>
        <div class="tiles">
          <div class="st"><b>${d.together.games}</b><span>لعبتوا مع بعض</span></div>
          <div class="st g"><b>${d.together.sameWin}</b><span>فزتوا بنفس الفريق</span></div>
          <div class="st r"><b>${d.together.against}</b><span>كان مافيا ضدك</span></div>
          <div class="st r"><b>${d.together.killedMe}</b><span>اغتالك</span></div></div></div>
      <div class="panel"><h2>📊 إحصائياته</h2>${tilesHTML(d.stats, true)}</div>${favHTML(d.fav, 'أكثر كرت بيطلعله')}${recentHTML(d.recent)}`;
    $('fpBody').querySelector('[data-inv]')?.addEventListener('click', e => inviteFriend(d.id, e.currentTarget));
    $('fpAdd') && ($('fpAdd').onclick = async () => { if (await sendRequest(d.id)) openUser(d.id); });
    $('fpAcc') && ($('fpAcc').onclick = async () => { await api('POST', '/friends/accept', { from: d.id }); openUser(d.id); });
    $('fpRel') && ($('fpRel').onclick = () => $('fpMenu').onclick());
    bindGames($('fpBody'));
    if (current !== 'friend') go('friend');
  } catch (err) { toast(err.message); }
}
$('fpMenu').onclick = async () => {
  if (!fpUser || fpUser.relation !== 'friend') return;
  if (confirm(`بدك تشيل ${fpUser.username} من أصحابك؟`)) {
    await api('POST', '/friends/remove', { id: fpUser.id }); toast('انشال من أصحابك'); openUser(fpUser.id);
  }
};

/* =====================================================================
   الإحصائيات
   ===================================================================== */
let stPeriod = 'all';
$('stPeriod').onclick = e => { const b = e.target.closest('button'); if (!b) return; stPeriod = b.dataset.v; [...$('stPeriod').children].forEach(x => x.classList.toggle('on', x === b)); loadStats(); };
async function loadStats() {
  try {
    const { stats: s, days, best } = await api('GET', '/stats?period=' + stPeriod);
    const outs = [['votedOut', 'تصويت', '#f3c75a'], ['killed', 'اغتيال', '#ff3b55'], ['sniped', 'قنص', '#ff8d40'], ['pulledOut', 'سحب', '#2ef08a']];
    const outTotal = outs.reduce((a, [k]) => a + s[k], 0);
    // دونات
    const tot = s.winsTown + s.winsMafia, C = 2 * Math.PI * 48, tw = tot ? (s.winsTown / tot) * C : 0;
    const donut = `<svg viewBox="0 0 120 120" width="130" height="130"><circle cx="60" cy="60" r="48" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="16"/>
      ${tot ? `<circle cx="60" cy="60" r="48" fill="none" stroke="#ff3b55" stroke-width="16" stroke-dasharray="${C - tw} ${C}" stroke-dashoffset="${-tw}" transform="rotate(-90 60 60)"/>
      <circle cx="60" cy="60" r="48" fill="none" stroke="#2ef08a" stroke-width="16" stroke-dasharray="${tw} ${C}" transform="rotate(-90 60 60)"/>` : ''}
      <text x="60" y="58" text-anchor="middle" fill="#f3c75a" font-size="24" font-weight="900" font-family="Cairo">${tot}</text>
      <text x="60" y="78" text-anchor="middle" fill="#a8939a" font-size="12" font-weight="700" font-family="Cairo">فوز</text></svg>`;
    // خط آخر 30 يوم: الفوز التراكمي
    let cum = 0;
    const pts = days.map((d, i) => { cum += d.wins; return [i, cum]; });
    const maxY = Math.max(1, cum), W = 300, H = 110;
    const xy = ([i, y]) => `${(i / 29) * W},${H - 10 - (y / maxY) * (H - 20)}`;
    const line = `<svg viewBox="0 0 ${W} ${H}" width="100%" height="${H}" preserveAspectRatio="none" style="direction:ltr">
      <polygon points="0,${H} ${pts.map(xy).join(' ')} ${W},${H}" fill="rgba(255,59,85,.15)"/>
      <polyline points="${pts.map(xy).join(' ')}" fill="none" stroke="#f3c75a" stroke-width="2.5" style="filter:drop-shadow(0 0 4px rgba(243,199,90,.7))"/>
      ${pts.filter((p, i) => days[i].games).map(p => `<circle cx="${xy(p).split(',')[0]}" cy="${xy(p).split(',')[1]}" r="3.5" fill="#fff0b0"/>`).join('')}</svg>`;
    $('stBody').innerHTML = `
      <div class="kpis"><div><b>${s.games}</b><small>الألعاب</small></div><div><b>${s.wins}</b><small>الفوز</small></div><div><b>${s.rate}%</b><small>نسبة الفوز</small></div><div><b>${s.streak}</b><small>أطول سلسلة فوز</small></div></div>
      <div class="panel"><h2>فزت مع مين؟</h2><div class="donut">${donut}<div class="legend" style="flex-direction:column">
        <span><i style="background:#2ef08a"></i>مواطنين ${s.winsTown}</span><span><i style="background:#ff3b55"></i>مافيا ${s.winsMafia}</span></div></div></div>
      <div class="panel"><h2>نسبة فوزي بكل دور</h2><div class="bars">${ALL_ROLES.map(r => { const n = s.roles[r] || 0, p = pct(s.roleWins[r] || 0, n);
        return `<div class="b"><span>${ROLES[r].icon} ${ROLES[r].name}</span><span class="tr"><i style="width:${p}%"></i></span><span class="p">${n ? p + '%' : '—'}</span></div>`; }).join('')}</div></div>
      <div class="panel"><h2>أدائي آخر 30 يوم <span class="more muted">الفوز التراكمي</span></h2>${line}</div>
      <div class="tiles">
        <div class="st g"><div class="top"><b>${pct(s.saves, s.protects)}%</b><span class="i">⚕️</span></div><span>دقة الحماية</span><small class="muted">${s.saves} من ${s.protects} حماية صح</small></div>
        <div class="st r"><div class="top"><b>${pct(s.snipeMafia, s.snipeMafia + s.snipeTown)}%</b><span class="i">🎯</span></div><span>دقة القنص</span><small class="muted">${s.snipeMafia} من ${s.snipeMafia + s.snipeTown} قنصة صح</small></div></div>
      <div class="panel"><h2>كيف طلعت من اللعبة</h2><div class="stack">${outTotal ? outs.map(([k, , c]) => `<i style="width:${pct(s[k], outTotal)}%;background:${c}"></i>`).join('') : ''}</div>
        <div class="legend">${outs.map(([k, l, c]) => `<span><i style="background:${c}"></i>${l} ${s[k]}</span>`).join('')}</div></div>
      ${best ? `<div class="panel"><h2>أكثر لاعب بتفوز معه</h2><div class="li" data-user="${best.id}">${avatar(best.avatar, best.username, 50)}<span class="info"><b>${esc(best.username)}</b><small>فزتوا مع بعض ${best.together} مرة</small></span></div></div>` : ''}`;
    $('stBody').querySelectorAll('[data-user]').forEach(b => (b.onclick = () => openUser(b.dataset.user)));
  } catch (err) { toast(err.message); }
}

/* =====================================================================
   الإعدادات
   ===================================================================== */
const TOGGLES = [['vibrate', '📳 الاهتزاز'], ['sounds', '🔊 الأصوات'], ['invites', '📨 إشعارات دعوات اللعب'], ['showOnline', '🟢 إظهار إني متصل للأصدقاء']];
let setAvatarData;
function loadSettings() {
  setAvatarData = undefined;
  $('setAv').outerHTML = avatar(ME.avatar, ME.username, 92).replace('class="av"', 'class="av" id="setAv"');
  $('setUser').value = ME.username; $('setEmail').value = ME.email;
  $('passForm').classList.add('hidden');
  $('setToggles').innerHTML = TOGGLES.map(([k, l]) => `<label class="li"><span class="info"><b>${l}</b></span><span class="toggle"><input type="checkbox" data-set="${k}" ${ME.settings[k] !== false ? 'checked' : ''}><i></i></span></label>`).join('');
  $('setToggles').querySelectorAll('[data-set]').forEach(i => (i.onchange = async () => {
    try { ME = await api('PUT', '/me', { settings: { [i.dataset.set]: i.checked } }); } catch (e) { toast(e.message); }
  }));
}
$('setAvFile').onchange = async e => {
  try { setAvatarData = await readAvatar(e.target.files[0]); $('setAv').innerHTML = `<img src="${setAvatarData}" alt="">`; } catch (err) { toast(err.message); }
};
$('setForm').onsubmit = async e => {
  e.preventDefault();
  try {
    const body = { username: $('setUser').value, email: $('setEmail').value };
    if (setAvatarData) body.avatar = setAvatarData;
    ME = await api('PUT', '/me', body); paintHello(); toast('انحفظ ✔️');
    if (setAvatarData) setAuth(TOKEN, ME, !!store.get('token')); // نحدّث الصورة بالغرفة
  } catch (err) { toast(err.message); }
};
$('setPass').onclick = () => $('passForm').classList.toggle('hidden');
$('passForm').onsubmit = async e => {
  e.preventDefault();
  try { await api('PUT', '/me/password', { old: $('pwOld').value, password: $('pwNew').value }); toast('تغيّرت كلمة السر ✔️'); $('passForm').reset(); $('passForm').classList.add('hidden'); }
  catch (err) { toast(err.message); }
};
$('logoutBtn').onclick = async () => {
  if (!confirm('بدك تسجّل خروج؟')) return;
  try { await api('POST', '/logout'); } catch {}
  setAuth(null, null); store.del('guest'); go('login');
};
$('deleteBtn').onclick = async () => {
  const pw = prompt('حذف الحساب نهائي وما بيرجع. اكتب كلمة السر للتأكيد:');
  if (!pw) return;
  try { await api('DELETE', '/me', { password: pw }); setAuth(null, null); toast('انحذف الحساب'); go('login'); } catch (err) { toast(err.message); }
};

/* =====================================================================
   البداية
   ===================================================================== */
const params = new URLSearchParams(location.search);
let urlRoom = params.get('room');
const urlAdd = params.get('add');
(async function boot() {
  if (urlRoom) {
    const saved = store.get('session');
    if (saved && saved.code !== urlRoom) store.del('session');
    fillCode(urlRoom);
  }
  if (TOKEN) {
    try { ME = await api('GET', '/me'); } catch { ME = null; }
  }
  paintHello();
  if (urlAdd) {
    history.replaceState(null, '', location.pathname);
    if (ME) sendRequest(urlAdd); else { store.set('pendingAdd', urlAdd); toast('سجّل دخول لتضيف صاحبك'); }
  }
  if (S) return; // السوكيت رجّعنا لغرفة
  if (ME) go('home');
  else if (urlRoom || store.get('guest')) { go('home'); if (urlRoom) setTimeout(() => $('nameInput').focus(), 100); }
  else go('login');
  // إذا مسجّل ورابط دعوة، بندخل الغرفة مباشرة
  if (urlRoom && ME && socket.connected && !store.get('session')) { socket.emit('join', { code: urlRoom, name: ME.username }); urlRoom = null; }
})();
