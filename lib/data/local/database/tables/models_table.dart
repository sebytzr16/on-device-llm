import 'package:drift/drift.dart';

class Models extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get fileName => text()();
  TextColumn get downloadUrl => text().nullable()();
  TextColumn get sha256 => text().nullable()();
  TextColumn get license =>
      text().withDefault(const Constant('See publisher model card'))();
  IntColumn get sizeBytes => integer()();
  IntColumn get parameterCountB => integer().nullable()();
  TextColumn get family => text()();
  TextColumn get quantization => text()();
  BoolColumn get isDownloaded => boolean().withDefault(const Constant(false))();
  TextColumn get localPath => text().nullable()();
  DateTimeColumn get downloadedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
