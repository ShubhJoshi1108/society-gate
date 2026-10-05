import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/guard_home.dart';
import 'screens/login_screen.dart';
import 'screens/resident_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.I.init();
  await Api.I.refreshAuth();
  runApp(const SocietyGateApp());
}

class SocietyGateApp extends StatelessWidget {
  const SocietyGateApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1B6B5A);
    return MaterialApp(
      title: 'Society Gate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.dark),
      home: const RootGate(),
    );
  }
}

/// Decides which home screen to show based on login + role.
class RootGate extends StatefulWidget {
  const RootGate({super.key});
  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final api = Api.I;
    if (!api.isLoggedIn) return LoginScreen(onLoggedIn: _refresh);
    switch (api.role) {
      case 'guard':
      case 'admin':
        return GuardHome(onLogout: _refresh);
      case 'resident':
        return ResidentHome(onLogout: _refresh);
      default:
        return Scaffold(
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Your account has no role yet.\nAsk the society admin.', textAlign: TextAlign.center),
              TextButton(
                onPressed: () async {
                  await api.logout();
                  _refresh();
                },
                child: const Text('Log out'),
              ),
            ]),
          ),
        );
    }
  }
}
