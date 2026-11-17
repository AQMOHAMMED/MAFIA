import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/app_state.dart';
import 'screens/auth.dart';
import 'screens/game.dart';
import 'screens/shell.dart';
import 'ui/overlays.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: C.bg,
  ));
  final app = AppState()..init();
  runApp(ChangeNotifierProvider.value(value: app, child: const MafiaApp()));
}

class MafiaApp extends StatelessWidget {
  const MafiaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'مافيا',
        debugShowCheckedModeBanner: false,
        navigatorKey: navKey,
        theme: buildTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Stack(children: [
          child!,
          const RevealOverlay(),
          const InviteBanner(),
          const ToastView(),
        ]),
        home: const Root(),
      );
}

// الشاشة الأساسية بتتحدد من الحالة: لعبة، رئيسية، أو تسجيل دخول
class Root extends StatelessWidget {
  const Root({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    Widget body;
    if (!app.ready) {
      body = const Splash();
    } else if (app.s != null) {
      body = const GameScreen();
    } else if (app.loggedIn || app.guest) {
      body = const MainShell();
    } else {
      body = const LoginScreen();
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey(body.runtimeType), child: body));
  }
}

class Splash extends StatelessWidget {
  const Splash({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: Bg(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/img/logo.webp', width: 220),
              const SizedBox(height: 24),
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            ]),
          ),
        ),
      );
}
