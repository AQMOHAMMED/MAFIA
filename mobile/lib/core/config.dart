// عنوان السيرفر. بنقدر نغيّره وقت البناء:
//   flutter run --dart-define=SERVER=http://192.168.1.5:3000
const String kServer = String.fromEnvironment('SERVER', defaultValue: 'https://mafia-m22y.onrender.com');

// روابط الصور اللي بترجع من السيرفر بتكون نسبية (/api/avatar/..)
String? absUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http') || url.startsWith('data:')) return url;
  return '$kServer$url';
}
