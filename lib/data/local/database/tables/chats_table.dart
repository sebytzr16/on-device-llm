import 'package:drift/drift.dart';

class Chats extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get modelId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Organisation (FX-06, schema v4): pinned chats sit on top, a folder is
  /// a free-text name, tags are a JSON list of strings.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  TextColumn get folder => text().nullable()();
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  /// Chat-level setting overrides (schema v9): a JSON object of setting
  /// keys layered over the model profile and preset for this chat only.
  TextColumn get overridesJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}
