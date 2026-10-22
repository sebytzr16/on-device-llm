import 'package:drift/drift.dart';

import 'chats_table.dart';

class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get chatId =>
      text().references(Chats, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get reasoning => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('complete'))();
  TextColumn get sourcesJson => text().withDefault(const Constant('[]'))();

  /// Files attached to a user turn (schema v2): JSON list of
  /// `Attachment.toJson()`; document text travels with the row so a chat
  /// can be reopened and continued after the source file is gone.
  TextColumn get attachmentsJson => text().withDefault(const Constant('[]'))();
  TextColumn get modelId => text().nullable()();

  /// The turn this one continues (schema v7): a question's parent is the
  /// answer before it, an answer's parent is its question, an edited or
  /// regenerated turn is a sibling of the one it replaces. The live
  /// conversation is the chain from the newest live row back to the root;
  /// restoring a branch follows this instead of storage order.
  TextColumn get parentId => text().nullable()();

  /// What produced an answer (schema v8, CHAT-04): `TurnRun.toJson()` —
  /// effective settings, preset, model, engine parameters and metrics.
  TextColumn get runJson => text().nullable()();
  DateTimeColumn get timestamp => dateTime()();
  IntColumn get tokenCount => integer().nullable()();
  IntColumn get sequence => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
