import 'package:drift/drift.dart';

/// A document in the knowledge library (FX-02): its text was extracted on
/// import and split into [KnowledgeChunks]. New imports keep an original file
/// and older revisions; only the selected revision is used for retrieval.
class KnowledgeDocs extends Table {
  TextColumn get id => text()();
  TextColumn get collection => text()();
  TextColumn get name => text()();
  TextColumn get mime => text().withDefault(const Constant('text/plain'))();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  IntColumn get chars => integer().withDefault(const Constant(0))();
  IntColumn get chunkCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get addedAt => dateTime()();
  TextColumn get contentHash => text().nullable()();
  TextColumn get extractionFormat => text().nullable()();
  TextColumn get extractionWarning => text().nullable()();
  TextColumn get originalFile => text().nullable()();
  TextColumn get previousVersionId => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Passages of a document, indexed by `knowledge_fts` (FTS5) for retrieval.
class KnowledgeChunks extends Table {
  TextColumn get id => text()();
  TextColumn get docId =>
      text().references(KnowledgeDocs, #id, onDelete: KeyAction.cascade)();
  IntColumn get ordinal => integer()();
  IntColumn get pageNumber => integer().nullable()();
  // Named `content`: a column called `text` would shadow Drift's builder.
  TextColumn get content => text()();
  // Semantic index (FX-02 second half): the passage's L2-normalised vector
  // as little-endian float32 bytes, and the embedding model that made it.
  // Null until the passage is indexed; a different model re-indexes.
  BlobColumn get embedding => blob().nullable()();
  TextColumn get embeddingModel => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
