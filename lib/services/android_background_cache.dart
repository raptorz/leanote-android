import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../core/api/api2_client.dart';
import '../data/database/app_database.dart';
import '../data/session/session_store.dart';
import '../repositories/auth_repository.dart';
import '../sync/sync_coordinator.dart';

const _taskName = 'gemsnote.resourceCache';
const _periodicName = 'gemsnote.resourceCache.periodic';
const _resumeName = 'gemsnote.resourceCache.resume';

@pragma('vm:entry-point')
void backgroundCacheDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    if (taskName != _taskName) return true;
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return runBackgroundResourceCache();
  });
}

/// Runs only for the account that is still active when the task starts. The
/// durable queue owns a SQLite lease, so a foreground runner cannot overlap.
Future<bool> runBackgroundResourceCache() async {
  final database = await AppDatabase.open();
  try {
    final api = Api2Client();
    final repository = AuthRepository(
      api,
      database,
      const SecureSessionStore(),
      SyncCoordinator(api, database),
    );
    final session = await repository.restore();
    if (session == null || !await repository.autoCacheFiles(session)) {
      return true;
    }
    final queue = repository.fileCacheQueue(session);
    Future<void> checkAccount() async {
      final active = await database.activeAccount();
      if (active?.cacheKey != session.account.cacheKey ||
          !await repository.autoCacheFiles(session)) {
        queue.cancel();
        throw StateError('backgroundCacheAccountChanged');
      }
    }

    await queue.run(
      (await repository.notes(session.account.cacheKey))
          .where((note) => note.usn > 0)
          .map((note) => note.noteId)
          .toList(),
      listFiles: (id) async {
        await checkAccount();
        return repository.noteFiles(session, id);
      },
      download: (id, file) async {
        await checkAccount();
        if (file.isAttachment) {
          await repository.noteAttachment(session, id, file);
        } else {
          await repository.noteImage(session, id, file);
        }
      },
      onProgress: (_, _, _) {},
    );
    final active = await database.activeAccount();
    if (active?.cacheKey != session.account.cacheKey ||
        !await repository.autoCacheFiles(session)) {
      return true;
    }
    final status = await repository.downloadQueueStatus(session);
    return status.failed == 0;
  } on Object {
    return false;
  } finally {
    await database.raw.close();
  }
}

class AndroidBackgroundCache {
  const AndroidBackgroundCache._();

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(backgroundCacheDispatcher);
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    if (enabled) {
      await Workmanager().registerPeriodicTask(
        _periodicName,
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } else {
      await Workmanager().cancelByUniqueName(_periodicName);
      await Workmanager().cancelByUniqueName(_resumeName);
    }
  }

  static Future<void> resumeOnce() async {
    if (!Platform.isAndroid) return;
    await Workmanager().registerOneOffTask(
      _resumeName,
      _taskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }
}
