import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';

// Premium purple theme: navy text + purple primary + lavender accents on a soft lilac background.
// (kBlue keeps its old name because the whole app uses it; it is the PRIMARY colour, now purple.)
const kBlue = Color(0xFF6338D6); // primary
const kLavender = Color(0xFFA78BFA); // secondary
const kLilac = Color(0xFFEDE7FF); // light tint (selected tab, chips)
const kNavy = Color(0xFF172554); // text
const kBg = Color(0xFFF7F5FF); // background
const kBorder = Color(0xFFE8E3F8);

void main() => runApp(const HomeTwinApp());

class HomeTwinApp extends StatelessWidget {
  const HomeTwinApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Home Digital Twin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: kBlue, primary: kBlue, secondary: kLavender),
          scaffoldBackgroundColor: kBg,
          // Inter is downloaded the first time (needs internet); offline it falls back to the system font.
          textTheme: GoogleFonts.interTextTheme(),
          appBarTheme: AppBarTheme(
            backgroundColor: kBg,
            foregroundColor: kNavy,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleTextStyle: GoogleFonts.inter(color: kNavy, fontSize: 22, fontWeight: FontWeight.w700),
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
            indicatorColor: kLilac,
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