import 'package:flutter/material.dart';
import '../api.dart';
import '../main.dart';
import 'home_shell.dart';

class AuthScreen extends StatefulWidget {
  /// Agar main.dart callback deta hai to login ke baad wahi chalega, warna seedha HomeShell khulta hai.
  final VoidCallback? onAuthenticated;
  const AuthScreen({super.key, this.onAuthenticated});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false, _busy = false, _hide = true;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      if (_register) {
        await Api.register(_name.text.trim(), _email.text.trim(), _pass.text);
      } else {
        await Api.login(_email.text.trim(), _pass.text);
      }
      if (!mounted) return;
      if (widget.onAuthenticated != null) {
        widget.onAuthenticated!();
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBlue, width: 1.6)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0xFFFFF1D0), kBg]),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [BoxShadow(color: kNavy.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 8))],
                    ),
                    child: const Icon(Icons.home_work_rounded, size: 48, color: kBlue),
                  ),
                  const SizedBox(height: 16),
                  const Text('Home Digital Twin', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kNavy)),
                  const SizedBox(height: 4),
                  const Text('Your Home. Digitized. Organized. Protected.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF5A6785))),
                  const SizedBox(height: 28),
                  if (_register) ...[
                    TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: _dec('Name', Icons.person_outline)),
                    const SizedBox(height: 12),
                  ],
                  TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: _dec('Email', Icons.mail_outline)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    decoration: _dec('Password', Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        )),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(_register ? 'Create account' : 'Login', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register ? 'Already have an account? Login' : 'New here? Sign up'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}