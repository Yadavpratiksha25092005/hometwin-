import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';

/// For now every OTP (sign up and forgot password) is this code. Replace with a real email OTP later.
const kDemoOtp = '123456';

const _ink = Color(0xFF1A1240);
const _soft = Color(0xFF5A6785);

/// Shared page layout for the sign-up OTP / forgot password pages (purple background + back arrow).
class AuthPageShell extends StatelessWidget {
  final Widget child;
  const AuthPageShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, 0.45, 1], colors: [Color(0xFFDDD2FF), Color(0xFFF3EFFF), kBg]),
          ),
          child: SafeArea(
            child: Column(children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(padding: const EdgeInsets.all(14), icon: const Icon(Icons.arrow_back_rounded, color: _ink), onPressed: () => Navigator.pop(context)),
              ),
              Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), child: child)),
            ]),
          ),
        ),
      );
}

/// Big purple icon tile at the top of those pages.
class AuthIconTile extends StatelessWidget {
  final IconData icon;
  const AuthIconTile(this.icon, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8B5CF6), Color(0xFF4C1D95)]),
          boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Icon(icon, size: 44, color: Colors.white),
      );
}

/// White rounded card that holds the fields.
class AuthCard extends StatelessWidget {
  final Widget child;
  const AuthCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.12), blurRadius: 30, offset: const Offset(0, 12))],
        ),
        child: child,
      );
}

/// Purple gradient button (same look as the Login button).
class PurpleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  const PurpleButton({super.key, required this.label, required this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) => Container(
        height: 56,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF5B2DD0)]),
          boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: busy ? null : onTap,
            child: Center(
              child: busy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
}

/// OTP page. Pops with the entered code (a String) when it is correct, or with null when the user goes back.
class OtpScreen extends StatefulWidget {
  final String email;
  final String buttonText;
  const OtpScreen({super.key, required this.email, this.buttonText = 'Verify & create account'});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController(text: kDemoOtp);
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _verify() {
    final c = _code.text.trim();
    if (c == kDemoOtp) {
      Navigator.pop(context, c);
    } else {
      setState(() => _error = 'Wrong OTP. Please try again.');
    }
  }

  void _resend() {
    setState(() {
      _error = null;
      _code.text = kDemoOtp;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP sent again (demo OTP: $kDemoOtp)')));
  }

  @override
  Widget build(BuildContext context) => AuthPageShell(
        child: Column(children: [
          const AuthIconTile(Icons.mark_email_unread_rounded),
          const SizedBox(height: 24),
          const Text('Verify your email', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.4)),
          const SizedBox(height: 10),
          const Text('We sent a 6-digit code to', style: TextStyle(fontSize: 15, color: _soft)),
          const SizedBox(height: 2),
          Text(widget.email, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: kLilac, borderRadius: BorderRadius.circular(20)),
            child: const Text('Demo OTP: $kDemoOtp', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kBlue)),
          ),
          const SizedBox(height: 26),
          AuthCard(
            child: Column(children: [
              TextField(
                controller: _code,
                autofocus: true,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: 12, color: _ink),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _verify(),
                decoration: InputDecoration(
                  hintText: '------',
                  counterText: '',
                  errorText: _error,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFDCD2FA))),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFDCD2FA))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: kBlue, width: 1.4)),
                ),
              ),
              const SizedBox(height: 18),
              PurpleButton(label: widget.buttonText, onTap: _verify),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _resend,
                child: const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: "Didn't get the code? ", style: TextStyle(color: Color(0xFF5B3FD0), fontWeight: FontWeight.w500)),
                    TextSpan(text: 'Resend', style: TextStyle(color: kBlue, fontWeight: FontWeight.w800)),
                  ]),
                  style: TextStyle(fontSize: 15),
                ),
              ),
            ]),
          ),
        ]),
      );
}