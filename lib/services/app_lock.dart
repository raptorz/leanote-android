import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

abstract interface class DeviceAuthenticator {
  Future<bool> supported();
  Future<bool> authenticate(String reason);
}

class LocalDeviceAuthenticator implements DeviceAuthenticator {
  LocalDeviceAuthenticator([LocalAuthentication? authentication])
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<bool> supported() => _authentication.isDeviceSupported();

  @override
  Future<bool> authenticate(String reason) => _authentication.authenticate(
    localizedReason: reason,
    biometricOnly: false,
    sensitiveTransaction: true,
    persistAcrossBackgrounding: true,
  );
}

class AppLockController extends ChangeNotifier {
  AppLockController({
    required this.load,
    required this.save,
    DeviceAuthenticator? authenticator,
  }) : _authenticator = authenticator ?? LocalDeviceAuthenticator();

  @visibleForTesting
  final Future<bool> Function() load;
  @visibleForTesting
  final Future<void> Function(bool) save;
  final DeviceAuthenticator _authenticator;
  bool ready = false;
  bool supported = false;
  bool enabled = false;
  bool locked = false;
  bool authenticating = false;
  String? error;

  Future<void> initialize(String reason) async {
    if (ready) return;
    try {
      final stored = await load();
      if (!stored) {
        ready = true;
        notifyListeners();
        await _detectSupport();
        return;
      }
      supported = await _authenticator.supported();
      enabled = supported;
      locked = enabled;
      ready = true;
      notifyListeners();
      if (locked) await unlock(reason);
    } on Object {
      error = 'appLockUnavailable';
      ready = true;
      supported = false;
      enabled = false;
      locked = false;
      notifyListeners();
    }
  }

  Future<void> _detectSupport() async {
    try {
      supported = await _authenticator.supported();
    } on Object {
      supported = false;
    }
    notifyListeners();
  }

  Future<bool> setEnabled(bool value, String reason) async {
    if (!ready || !supported || authenticating) return false;
    if (value == enabled) return true;
    if (!await _verify(reason)) return false;
    try {
      await save(value);
      enabled = value;
      locked = false;
      error = null;
      notifyListeners();
      return true;
    } on Object {
      error = 'appLockSaveFailed';
      notifyListeners();
      return false;
    }
  }

  void backgrounded() {
    if (enabled && !authenticating) {
      locked = true;
      notifyListeners();
    }
  }

  Future<bool> unlock(String reason) async {
    if (!enabled) {
      locked = false;
      return true;
    }
    final ok = await _verify(reason);
    if (ok) {
      locked = false;
      error = null;
      notifyListeners();
    }
    return ok;
  }

  Future<bool> _verify(String reason) async {
    if (authenticating) return false;
    authenticating = true;
    error = null;
    notifyListeners();
    try {
      final ok = await _authenticator.authenticate(reason);
      if (!ok) error = 'appLockCancelled';
      return ok;
    } on Object {
      error = 'appLockFailed';
      return false;
    } finally {
      authenticating = false;
      notifyListeners();
    }
  }

  Future<void> clear() async {
    enabled = false;
    locked = false;
    error = null;
    notifyListeners();
    await save(false);
  }
}
