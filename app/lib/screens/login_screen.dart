import 'package:flutter/material.dart';

import '../api.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLoggedIn});
  final VoidCallback onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController(text: Api.I.serverUrl);
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  Future<void> _login() async {
    if (_server.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Please fill all fields');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.I.login(_server.text, _email.text, _password.text);
      widget.onLoggedIn();
    } catch (e) {
      setState(() => _error = Api.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.door_front_door, size: 72, color: cs.primary),
              const SizedBox(height: 8),
              Text('Society Gate', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              const Text('Visitor approvals for your society', textAlign: TextAlign.center),
              const SizedBox(height: 32),
              TextField(
                controller: _server,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Society server address',
                  hintText: 'mysociety.duckdns.org',
                  prefixIcon: Icon(Icons.dns),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email / username',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _hide,
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: cs.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _login,
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Log in'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Accounts are created by your society admin.\nAsk them for your login details.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
