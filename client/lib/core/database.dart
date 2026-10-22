import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Device preferences only. Local image metadata has its own account-scoped DB.
class AppDatabase extends GeneratedDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(
    name: 'huabu_preferences',
    native: DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory),
  ));

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (_) async {
    await customStatement('CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  });

  Future<String?> readPreference(String key) async =>
    (await customSelect('SELECT value FROM preferences WHERE key = ?', variables: [Variable(key)]).getSingleOrNull())?.read<String>('value');

  Future<void> writePreference(String key, String value) => customStatement(
    'INSERT INTO preferences (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [key, value],
  );
}
