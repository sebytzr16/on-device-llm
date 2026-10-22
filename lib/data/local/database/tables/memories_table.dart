import 'package:drift/drift.dart';

/// Durable facts about the user, learned from conversations when Memory is
/// on (Settings > Memory) or typed in by hand. Injected into the system
/// prompt of every chat; never leaves the device.
class Memories extends Table {
  TextColumn get id => text()();
  TextColumn get content => text()();

  /// Chat the fact was learned from; null when added manually.
  TextColumn get sourceChatId => text().nullable()();
  TextColumn get sourceMessageId => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
