import 'package:flutter/material.dart';

import 'repositories/auth_repository.dart';
import 'ui/login_page.dart';
import 'ui/workspace_page.dart';

class GemsnoteApp extends StatelessWidget {
  const GemsnoteApp({required this.repository, super.key});

  final AuthRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemsnote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff173d38),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff6f4eb),
        useMaterial3: true,
      ),
      home: _RootGate(repository: repository),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate({required this.repository});

  final AuthRepository repository;

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  StoredSession? _session;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final session = await widget.repository.restore();
    if (mounted) {
      setState(() {
        _session = session;
        _ready = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session == null) {
      return LoginPage(
        repository: widget.repository,
        onSignedIn: (session) => setState(() => _session = session),
      );
    }
    return WorkspacePage(
      repository: widget.repository,
      session: _session!,
      onSignedOut: () => setState(() => _session = null),
    );
  }
}
