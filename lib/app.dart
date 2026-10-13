import 'package:flutter/material.dart';

import 'dart:async';

import 'repositories/auth_repository.dart';
import 'ui/login_page.dart';
import 'ui/workspace_page.dart';
import 'services/home_widget.dart';

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
  final _homeWidget = HomeWidgetController();
  StoredSession? _session;
  var _ready = false;
  bool _freshLogin = false;
  int _sessionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final session = await widget.repository.restore();
    if (mounted) {
      _bindWidget(session);
      setState(() {
        _session = session;
        _ready = true;
      });
    }
  }

  void _bindWidget(StoredSession? session) {
    unawaited(
      _homeWidget.activate(
        session,
        session == null
            ? null
            : () => widget.repository.notes(session.account.cacheKey),
      ),
    );
  }

  @override
  void dispose() {
    _homeWidget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session == null) {
      return LoginPage(
        repository: widget.repository,
        onSessionRestored: (session) => setState(() {
          _bindWidget(session);
          _session = session;
          _freshLogin = false;
        }),
        onSignedIn: (session) => setState(() {
          _bindWidget(session);
          _session = session;
          _freshLogin = true;
        }),
      );
    }
    return WorkspacePage(
      homeWidget: _homeWidget,
      key: ValueKey((_session!.account.cacheKey, _sessionGeneration)),
      onSessionChanged: (session) => setState(() {
        _bindWidget(session);
        _sessionGeneration++;
        _session = session;
        _freshLogin = false;
      }),
      repository: widget.repository,
      session: _session!,
      refreshAvatarOnStart: _freshLogin,
      onSignedOut: () => setState(() {
        _bindWidget(null);
        _session = null;
      }),
    );
  }
}
