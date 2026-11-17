# مافيا — تطبيق الموبايل (Flutter)

نفس لعبة الموقع، بيتصل بنفس السيرفر وقاعدة البيانات (`https://mafia-m22y.onrender.com`)،
فاللي على التطبيق واللي على الموقع بيلعبوا بنفس الغرفة.

## البناء

```bash
flutter pub get
flutter build apk --release --split-per-abi   # أندرويد للتجربة
flutter build appbundle --release             # أندرويد لـ Google Play (.aab)
flutter build ipa --release                   # آيفون (بدها ماك + Xcode)
```

تجربة على سيرفر محلي: `flutter run --dart-define=SERVER=http://192.168.1.5:3000`

## التوقيع (Google Play)
ملف `android/key.properties` (مش مرفوع على GitHub):
```
storeFile=C:/path/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```
بدونه، نسخة الـ release بتتوقّع بمفتاح التجربة.

## الهيكل
- `lib/core` — الاتصال (API + Socket.io) وحالة اللعبة
- `lib/screens` — الشاشات (الدخول، الرئيسية، اللعبة، الأصدقاء، الإحصائيات…)
- `lib/ui` — الألوان والأزرار والقطع المشتركة
- `assets` — صور الكروت، الخطوط (Cairo, Lalezar)، الأصوات
