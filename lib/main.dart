import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/api/api2_client.dart';
import 'data/database/app_database.dart';
import 'data/session/session_store.dart';
import 'repositories/auth_repository.dart';
import 'sync/sync_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await AppDatabase.open();
  const sessions = SecureSessionStore();
  final api = Api2Client();
  final sync = SyncCoordinator(api, database);
  final auth = AuthRepository(api, database, sessions, sync);
  runApp(GemsnoteApp(repository: auth));
}
