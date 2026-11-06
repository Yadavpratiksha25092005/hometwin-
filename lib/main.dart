import 'package:flutter/material.dart';
import 'api.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';

const kBlue = Color(0xFF0B6BE6);
const kNavy = Color(0xFF0F1F4B);
const kBg = Color(0xFFF7F9FC);
const kBorder = Color(0xFFE6ECF5);

void main() => runApp(const HomeTwinApp());

class HomeTwinApp extends StatelessWidget {
  const HomeTwinApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Home Digital Twin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: kBlue, primary: kBlue),
          scaffoldBackgroundColor: kBg,
          appBarTheme: const AppBarTheme(
            backgroundColor: kBg,
            foregroundColor: kNavy,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleTextStyle: TextStyle(color: kNavy, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: kBorder),
            ),
          ),
          navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: Color(0xFFE8F1FF),
            surfaceTintColor: Colors.transparent,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: kBlue,
            foregroundColor: Colors.white,
            shape: CircleBorder(),
          ),
        ),
        home: const _Root(),
      );
}

/// Session check -> HomeShell ya AuthScreen.
/// Login/signup hone par AuthScreen `onAuthenticated` call karti hai.
class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool? _authed;

  @override
  void initState() {
    super.initState();
    Api.loadSession().then((v) {
      if (mounted) setState(() => _authed = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_authed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _authed!
        ? const HomeShell()
        : AuthScreen(onAuthenticated: () => setState(() => _authed = true));
  }
}