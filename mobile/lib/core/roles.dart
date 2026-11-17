class RoleInfo {
  final String name, icon, team;
  const RoleInfo(this.name, this.icon, this.team);
  bool get mafia => team == 'mafia';
}

const Map<String, RoleInfo> kRoles = {
  'mafiaSheikh': RoleInfo('شيخ المافيا', '🔪', 'mafia'),
  'mafiaGirl': RoleInfo('بنت المافيا', '🎭', 'mafia'),
  'mafiaBoy': RoleInfo('ولد المافيا', '🤐', 'mafia'),
  'mafia': RoleInfo('مافيا', '🕶️', 'mafia'),
  'townSheikh': RoleInfo('شيخ الصالحين', '👳', 'town'),
  'doctor': RoleInfo('بنت الصالحين', '💉', 'town'),
  'sniper': RoleInfo('قناص الصالحين', '🎯', 'town'),
  'townBoy': RoleInfo('ولد الصالحين', '⛓️', 'town'),
  'citizen': RoleInfo('مواطن صالح', '🙂', 'town'),
};
const kSpecial = ['mafiaSheikh', 'mafiaGirl', 'mafiaBoy', 'mafia', 'townSheikh', 'doctor', 'sniper', 'townBoy'];
const kAllRoles = [...kSpecial, 'citizen'];
const kTeamName = {'mafia': 'مافيا', 'town': 'مواطن صالح'};

RoleInfo role(String? k) => kRoles[k] ?? kRoles['citizen']!;
String cardAsset(String role) => 'assets/cards/$role.webp';

// مكان خانة الاسم الفاضية بكل صورة كرت (نسبة من ارتفاع الكرت)
const Map<String, double> kNameY = {
  'mafiaSheikh': .599, 'mafiaGirl': .531, 'mafiaBoy': .531, 'mafia': .530, 'townSheikh': .601,
  'doctor': .601, 'sniper': .601, 'townBoy': .601, 'citizen': .601,
};

class HostOpt {
  final String mode, icon, title, sub;
  const HostOpt(this.mode, this.icon, this.title, this.sub);
}

const kHostOpts = [
  HostOpt('first', '🃏', 'أول واحد بسلّم كرته', 'الكل بلعب، وأول واحد بيطلع من اللعبة بصير الهوست وبشوف كل الكروت.'),
  HostOpt('fixed', '🎙️', 'هوست ثابت (أنا)', 'أنا ما بلعب، بدير اللعبة وبشوف كل الكروت من البداية.'),
];

Map<String, int> defaultRoles(int n) {
  final m = (n / 4).floor() < 1 ? 1 : (n / 4).floor();
  return {
    'mafiaSheikh': 1, 'mafiaGirl': m >= 2 ? 1 : 0, 'mafiaBoy': m >= 3 ? 1 : 0, 'mafia': m - 3 > 0 ? m - 3 : 0,
    'townSheikh': 1, 'doctor': n >= 4 ? 1 : 0, 'sniper': n >= 7 ? 1 : 0, 'townBoy': n >= 8 ? 1 : 0,
  };
}
