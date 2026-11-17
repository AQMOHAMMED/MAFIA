import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'api.dart';
import 'config.dart';
import 'roles.dart';
import 'sound.dart';

typedef J = Map<String, dynamic>;

final navKey = GlobalKey<NavigatorState>();

// حالة التطبيق كلها: الحساب، الاتصال، وحالة اللعبة اللي بتوصل من السيرفر
class AppState extends ChangeNotifier {
  late SharedPreferences prefs;
  final api = Api();
  io.Socket? socket;

  bool ready = false;
  bool connected = false;
  J? me; // الحساب (null = ضيف أو مش مسجّل)
  bool guest = false;
  String guestName = '';

  J? s; // حالة الغرفة من السيرفر
  String? myId;
  String _gameKey = '';

  // أحداث بتظهر فوق كل الشاشات
  final toastMsg = ValueNotifier<String?>(null);
  final invite = ValueNotifier<J?>(null);
  final reveal = ValueNotifier<J?>(null);
  int friendsTick = 0; // بيزيد لما يتغير إشي بالأصدقاء
  final List<String> pendingInvites = [];
  Timer? _toastT, _inviteT, _revealT;

  /* ---------- البداية ---------- */
  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    api.token = prefs.getString('token');
    api.onUnauthorized = () => setAuth(null, null);
    guest = prefs.getBool('guest') ?? false;
    guestName = prefs.getString('name') ?? '';
    if (api.token != null) {
      try {
        me = Map<String, dynamic>.from(await api.get('/me'));
      } on ApiError catch (e) {
        // بدون نت بنضل محتفظين بالتوكن، بس إذا السيرفر رفضه بنمسحه
        if (e.status == 401) api.token = null;
      }
    }
    _connect();
    ready = true;
    notifyListeners();
  }

  bool get loggedIn => me != null;
  String get myName => me != null ? me!['username'] as String : guestName.trim();
  J get settings => (me?['settings'] as Map?)?.cast<String, dynamic>() ?? const {};

  void setGuestName(String v) {
    guestName = v;
    prefs.setString('name', v.trim());
  }

  void playAsGuest() {
    guest = true;
    prefs.setBool('guest', true);
    notifyListeners();
  }

  void setAuth(String? token, J? user, {bool remember = true}) {
    api.token = token;
    me = user;
    if (token != null && remember) {
      prefs.setString('token', token);
    } else {
      prefs.remove('token');
    }
    // نعيد الاتصال عشان السيرفر يعرف مين إحنا
    _connect();
    popToRoot();
    notifyListeners();
  }

  Future<void> refreshMe() async {
    if (api.token == null) return;
    try {
      me = Map<String, dynamic>.from(await api.get('/me'));
      notifyListeners();
    } catch (_) {}
  }

  void updateMe(J m) {
    me = m;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/logout');
    } catch (_) {}
    guest = false;
    prefs.remove('guest');
    setAuth(null, null);
  }

  /* ---------- رسائل وتنبيهات ---------- */
  void toast(String msg) {
    toastMsg.value = msg;
    _toastT?.cancel();
    _toastT = Timer(const Duration(milliseconds: 2800), () => toastMsg.value = null);
  }

  void vibrate([int strength = 1]) {
    if (settings['vibrate'] == false) return;
    if (strength >= 3) {
      HapticFeedback.heavyImpact();
    } else if (strength == 2) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void beep(int tone) {
    if (settings['sounds'] == false) return;
    Sound.play(tone);
  }

  /* ---------- الاتصال ---------- */
  void _connect() {
    socket?.dispose();
    connected = false;
    final sock = io.io(
      kServer,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': api.token ?? ''})
          .enableForceNew()
          .enableReconnection()
          .disableAutoConnect()
          .build(),
    );
    socket = sock;
    J m(dynamic d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

    sock.onConnect((_) {
      connected = true;
      final saved = _session;
      if (saved != null) sock.emit('join', {'code': saved['code'], 'playerId': saved['playerId']});
      notifyListeners();
    });
    sock.onDisconnect((_) {
      connected = false;
      notifyListeners();
    });
    sock.on('joined', (d) {
      final x = m(d);
      myId = x['playerId'];
      prefs.setString('session', jsonEncode({'code': x['code'], 'playerId': x['playerId']}));
      popToRoot();
      if (pendingInvites.isNotEmpty) {
        final list = [...pendingInvites];
        pendingInvites.clear();
        Timer(const Duration(milliseconds: 300), () {
          for (final uid in list) {
            sock.emit('invite', uid);
          }
          toast('انبعتت الدعوة 📨');
        });
      }
    });
    sock.on('fail', (msg) => toast('$msg'));
    sock.on('expired', (_) {
      prefs.remove('session');
      if (s != null) {
        _clearRoom();
        toast('الغرفة انتهت، اعملوا غرفة جديدة');
      }
    });
    sock.on('replaced', (_) {
      _clearRoom();
      toast('فتحت اللعبة من مكان ثاني');
    });
    sock.on('kicked', (_) {
      prefs.remove('session');
      _clearRoom();
      toast('الليدر طلّعك من الغرفة');
    });
    sock.on('notify', (d) {
      final n = m(d);
      if (n['kind'] == 'friends') {
        friendsTick++;
        refreshMe();
      }
      if (n['kind'] == 'invite') showInvite(n);
    });
    sock.on('state', (d) => _onState(m(d)));
    sock.on('reveal', (d) => showReveal(m(d)));
    sock.connect();
  }

  J? get _session {
    final v = prefs.getString('session');
    if (v == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(v));
    } catch (_) {
      return null;
    }
  }

  void emit(String ev, [dynamic data]) {
    final sock = socket;
    if (sock == null) return;
    if (!sock.connected) toast('بنتصل بالسيرفر… جرّب كمان ثانية');
    if (data == null) {
      sock.emit(ev);
    } else {
      sock.emit(ev, data);
    }
  }

  void _onState(J st) {
    final prev = s;
    s = st;
    if (prev != null && prev['stage'] != st['stage']) {
      beep(st['stage'] == 'night' ? 330 : 660);
      vibrate(2);
    }
    // لما تتغير مرحلة اللعبة بنرجع لشاشة اللعب (حتى لو اللاعب فاتح سجل اللعبة مثلاً)
    final key = [st['phase'], st['stage'], st['nightNo'], meState['surrendered'], st['pendingPull'], gameScreen].join('|');
    if (key != _gameKey) {
      _gameKey = key;
      popToRoot();
    }
    WakelockPlus.enable().catchError((_) {});
    notifyListeners();
  }

  void _clearRoom() {
    s = null;
    myId = null;
    _gameKey = '';
    reveal.value = null;
    WakelockPlus.disable().catchError((_) {});
    popToRoot();
    notifyListeners();
  }

  void leaveRoom() {
    emit('leave');
    prefs.remove('session');
    _clearRoom();
  }

  void joinRoom(String code) {
    if (myName.isEmpty) return toast('اكتب اسمك أول');
    if (code.length != 4) return toast('الكود 4 أرقام');
    emit('join', {'code': code, 'name': myName});
  }

  void createRoom(int size, String hostMode) {
    if (myName.isEmpty) return toast('اكتب اسمك أول');
    emit('create', {'name': myName, 'size': size, 'roles': defaultRoles(size), 'hostMode': hostMode});
  }

  // دعوة صديق: إذا إنت بغرفة بتنبعت فوراً، وإلا بنعمل غرفة وبعدين بنبعتها
  bool inviteFriend(String uid) {
    if (s != null && s!['phase'] != 'ended') {
      emit('invite', uid);
      return true;
    }
    if (!pendingInvites.contains(uid)) pendingInvites.add(uid);
    return false;
  }

  void showInvite(J n) {
    invite.value = n;
    beep(780);
    vibrate(3);
    _inviteT?.cancel();
    _inviteT = Timer(const Duration(seconds: 20), () => invite.value = null);
  }

  void acceptInvite() {
    final n = invite.value;
    invite.value = null;
    if (n == null) return;
    if (s != null) leaveRoom();
    emit('join', {'code': n['code'], 'name': myName.isEmpty ? 'لاعب' : myName});
  }

  void showReveal(J r) {
    reveal.value = r;
    vibrate(3);
    beep(r['team'] == 'mafia' ? 220 : 880);
    _revealT?.cancel();
    _revealT = Timer(const Duration(seconds: 6), () => reveal.value = null);
  }

  void popToRoot() {
    final nav = navKey.currentState;
    if (nav != null && nav.canPop()) nav.popUntil((r) => r.isFirst);
  }

  /* ---------- مساعدات اللعبة ---------- */
  List<J> get players => ((s?['players'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
  J get meState => (s?['me'] as Map?)?.cast<String, dynamic>() ?? const {};
  J? get meP => players.where((p) => p['id'] == myId).firstOrNull;
  J? pById(String? id) => id == null ? null : players.where((p) => p['id'] == id).firstOrNull;
  bool get isLeader => s != null && s!['leaderId'] == myId;
  bool get isHost => s != null && s!['hostId'] == myId;
  bool get isController => s != null && s!['phase'] == 'playing' && s!['controllerId'] == myId;
  List<J> get alive => players.where((p) => p['playing'] == true && p['surrendered'] != true).toList();
  J? get night => (meState['night'] as Map?)?.cast<String, dynamic>();

  String get gameScreen {
    final st = s;
    if (st == null) return '';
    if (st['phase'] == 'lobby') return 'lobby';
    if (st['phase'] == 'ended') return 'gameover';
    final me = meState;
    if (st['pendingPull'] != null && meP != null && st['pendingPull'] == meP!['name'] && me['role'] == 'townBoy') return 'pull';
    if (me['role'] != null && me['surrendered'] != true) {
      if (st['stage'] == 'night' && night != null) return night!['picked'] == true ? 'nightRes' : 'night';
      return 'card';
    }
    return 'board';
  }

  // الصبح: بنعرضه مرة وحدة لكل ليلة
  String get _seenKey => 'seen_${s?['code']}_${s?['startedAt']}';
  int get morningSeen => prefs.getInt(_seenKey) ?? 0;
  void markMorningSeen(int no) {
    prefs.setInt(_seenKey, no);
    notifyListeners();
  }
}
