import 'package:flutter/material.dart';
import '../api.dart';
import '../main.dart';
import 'otp_screen.dart';

const _ink = Color(0xFF1A1240);
const _soft = Color(0xFF5A6785);

InputDecoration _dec(String label, IconData icon, {Widget? suffix}) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _soft, fontSize: 16),
      floatingLabelStyle: const TextStyle(color: kBlue, fontWeight: FontWeight.w600),
      prefixIcon: Icon(icon, color: kBlue),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFDCD2FA))),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFDCD2FA))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: kBlue, width: 1.4)),
    );

/// Step 1: ask for the email, then go to the OTP page, then to the "new password" page.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.initialEmail);

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid email')));
      return;
    }
    final otp = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => OtpScreen(email: email, buttonText: 'Verify OTP')));
    if (otp == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ResetPasswordScreen(email: email, otp: otp)));
  }

  @override
  Widget build(BuildContext context) => AuthPageShell(
        child: Column(children: [
          const AuthIconTile(Icons.lock_reset_rounded),
          const SizedBox(height: 24),
          const Text('Forgot password?', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.4)),
          const SizedBox(height: 10),
          const Text(
            "Enter your email and we'll send you a code to reset your password.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: _soft, height: 1.35),
          ),
          const SizedBox(height: 26),
          AuthCard(
            child: Column(children: [
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: _dec('Email', Icons.mail_outline_rounded)),
              const SizedBox(height: 18),
              PurpleButton(label: 'Send OTP', onTap: _send),
            ]),
          ),
        ]),
      );
}

/// Last step: choose a new password.
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final String otp;
  const ResetPasswordScreen({super.key, required this.email, required this.otp});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _hide = true, _busy = false;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_pass.text.length < 6) {
      messenger.showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters')));
      return;
    }
    if (_pass.text != _confirm.text) {
      messenger.showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.resetPassword(widget.email, widget.otp, _pass.text);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Password updated. Please log in with your new password.')));
      Navigator.popUntil(context, (r) => r.isFirst); // back to the login screen
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthPageShell(
        child: Column(children: [
          const AuthIconTile(Icons.password_rounded),
          const SizedBox(height: 24),
          const Text('Set new password', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.4)),
          const SizedBox(height: 10),
          Text('For ${widget.email}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: _soft)),
          const SizedBox(height: 26),
          AuthCard(
            child: Column(children: [
              TextField(
                controller: _pass,
                obscureText: _hide,
                decoration: _dec('New password', Icons.lock_outline_rounded,
                    suffix: IconButton(
                      icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _ink),
                      onPressed: () => setState(() => _hide = !_hide),
                    )),
              ),
              const SizedBox(height: 14),
              TextField(controller: _confirm, obscureText: _hide, decoration: _dec('Confirm password', Icons.lock_reset_rounded)),
              const SizedBox(height: 18),
              PurpleButton(label: 'Update password', onTap: _save, busy: _busy),
            ]),
          ),
        ]),
      );
}