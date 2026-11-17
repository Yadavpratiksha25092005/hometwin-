import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../api.dart';
import '../main.dart';
import 'home_shell.dart';

/// Login / Sign up screen.
/// `onAuthenticated` main.dart se aata hai; logout ke baad `const AuthScreen()` push hota hai,
/// tab login ke baad seedha HomeShell khul jata hai.
class AuthScreen extends StatefulWidget {
  final VoidCallback? onAuthenticated;
  const AuthScreen({super.key, this.onAuthenticated});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _done() {
    if (!mounted) return;
    if (widget.onAuthenticated != null) {
      widget.onAuthenticated!();
    } else {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeShell()), (_) => false);
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
      _done();
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run(() async {
        final email = _email.text.trim();
        final pass = _pass.text;
        if (email.isEmpty || pass.isEmpty) throw Exception('Email and password are required');
        if (_signup) {
          if (_name.text.trim().isEmpty) throw Exception('Please enter your name');
          if (pass.length < 6) throw Exception('Password must be at least 6 characters');
          await Api.register(_name.text.trim(), email, pass, phone: _phone.text.trim());
        } else {
          await Api.login(email, pass);
        }
      });

  Future<void> _google() => _run(() async {
        final acc = await GoogleSignIn(
          scopes: ['email'],
          // same Web client ID the backend verifies (google_auth.go)
          serverClientId: '690646162387-1i02fqiqpfpi30f9rni7tlom0s18c8ra.apps.googleusercontent.com',
        ).signIn();
        if (acc == null) throw Exception('Google sign-in cancelled');
        final auth = await acc.authentication;
        final token = auth.idToken;
        if (token == null) throw Exception('Google did not return an ID token');
        await Api.googleLogin(token);
      });

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.home_work_rounded, size: 64, color: kBlue),
                const SizedBox(height: 12),
                const Text('Home Digital Twin',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kNavy)),
                const SizedBox(height: 4),
                Text(_signup ? 'Create your account' : 'Welcome back',
                    textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF5A6785))),
                const SizedBox(height: 28),
                if (_signup) ...[
                  TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: _dec('Name', Icons.person_outline)),
                  const SizedBox(height: 12),
                ],
                TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _dec('Email', Icons.mail_outline)),
                const SizedBox(height: 12),
                if (_signup) ...[
                  TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: _dec('Phone (optional)', Icons.phone_outlined)),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _pass,
                  obscureText: _hide,
                  onSubmitted: (_) => _busy ? null : _submit(),
                  decoration: _dec('Password', Icons.lock_outline,
                      suffix: IconButton(
                          icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _hide = !_hide))),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : Text(_signup ? 'Sign up' : 'Log in'),
                  ),
                ),
                if (Api.remote) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _google,
                      icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                      label: const Text('Continue with Google'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : () => setState(() {
                        _signup = !_signup;
                        _error = null;
                      }),
                  child: Text(_signup ? 'Already have an account? Log in' : 'New here? Create an account'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}