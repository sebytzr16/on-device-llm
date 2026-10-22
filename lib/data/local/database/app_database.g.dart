// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ChatsTable extends Chats with TableInfo<$ChatsTable, Chat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _folderMeta = const VerificationMeta('folder');
  @override
  late final GeneratedColumn<String> folder = GeneratedColumn<String>(
    'folder',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _overridesJsonMeta = const VerificationMeta(
    'overridesJson',
  );
  @override
  late final GeneratedColumn<String> overridesJson = GeneratedColumn<String>(
    'overrides_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    modelId,
    createdAt,
    updatedAt,
    pinned,
    folder,
    tags,
    overridesJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chats';
  @override
  VerificationContext validateIntegrity(
    Insertable<Chat> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('folder')) {
      context.handle(
        _folderMeta,
        folder.isAcceptableOrUnknown(data['folder']!, _folderMeta),
      );
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    if (data.containsKey('overrides_json')) {
      context.handle(
        _overridesJsonMeta,
        overridesJson.isAcceptableOrUnknown(
          data['overrides_json']!,
          _overridesJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chat(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      folder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder'],
      ),
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      )!,
      overridesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}overrides_json'],
      )!,
    );
  }

  @override
  $ChatsTable createAlias(String alias) {
    return $ChatsTable(attachedDatabase, alias);
  }
}

class Chat extends DataClass implements Insertable<Chat> {
  final String id;
  final String title;
  final String? modelId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Organisation (FX-06, schema v4): pinned chats sit on top, a folder is
  /// a free-text name, tags are a JSON list of strings.
  final bool pinned;
  final String? folder;
  final String tags;

  /// Chat-level setting overrides (schema v9): a JSON object of setting
  /// keys layered over the model profile and preset for this chat only.
  final String overridesJson;
  const Chat({
    required this.id,
    required this.title,
    this.modelId,
    required this.createdAt,
    required this.updatedAt,
    required this.pinned,
    this.folder,
    required this.tags,
    required this.overridesJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || modelId != null) {
      map['model_id'] = Variable<String>(modelId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['pinned'] = Variable<bool>(pinned);
    if (!nullToAbsent || folder != null) {
      map['folder'] = Variable<String>(folder);
    }
    map['tags'] = Variable<String>(tags);
    map['overrides_json'] = Variable<String>(overridesJson);
    return map;
  }

  ChatsCompanion toCompanion(bool nullToAbsent) {
    return ChatsCompanion(
      id: Value(id),
      title: Value(title),
      modelId: modelId == null && nullToAbsent
          ? const Value.absent()
          : Value(modelId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      pinned: Value(pinned),
      folder: folder == null && nullToAbsent
          ? const Value.absent()
          : Value(folder),
      tags: Value(tags),
      overridesJson: Value(overridesJson),
    );
  }

  factory Chat.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chat(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      modelId: serializer.fromJson<String?>(json['modelId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      folder: serializer.fromJson<String?>(json['folder']),
      tags: serializer.fromJson<String>(json['tags']),
      overridesJson: serializer.fromJson<String>(json['overridesJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'modelId': serializer.toJson<String?>(modelId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'pinned': serializer.toJson<bool>(pinned),
      'folder': serializer.toJson<String?>(folder),
      'tags': serializer.toJson<String>(tags),
      'overridesJson': serializer.toJson<String>(overridesJson),
    };
  }

  Chat copyWith({
    String? id,
    String? title,
    Value<String?> modelId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? pinned,
    Value<String?> folder = const Value.absent(),
    String? tags,
    String? overridesJson,
  }) => Chat(
    id: id ?? this.id,
    title: title ?? this.title,
    modelId: modelId.present ? modelId.value : this.modelId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    pinned: pinned ?? this.pinned,
    folder: folder.present ? folder.value : this.folder,
    tags: tags ?? this.tags,
    overridesJson: overridesJson ?? this.overridesJson,
  );
  Chat copyWithCompanion(ChatsCompanion data) {
    return Chat(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      folder: data.folder.present ? data.folder.value : this.folder,
      tags: data.tags.present ? data.tags.value : this.tags,
      overridesJson: data.overridesJson.present
          ? data.overridesJson.value
          : this.overridesJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Chat(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('modelId: $modelId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('pinned: $pinned, ')
          ..write('folder: $folder, ')
          ..write('tags: $tags, ')
          ..write('overridesJson: $overridesJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    modelId,
    createdAt,
    updatedAt,
    pinned,
    folder,
    tags,
    overridesJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chat &&
          other.id == this.id &&
          other.title == this.title &&
          other.modelId == this.modelId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.pinned == this.pinned &&
          other.folder == this.folder &&
          other.tags == this.tags &&
          other.overridesJson == this.overridesJson);
}

class ChatsCompanion extends UpdateCompanion<Chat> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> modelId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> pinned;
  final Value<String?> folder;
  final Value<String> tags;
  final Value<String> overridesJson;
  final Value<int> rowid;
  const ChatsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.modelId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.pinned = const Value.absent(),
    this.folder = const Value.absent(),
    this.tags = const Value.absent(),
    this.overridesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatsCompanion.insert({
    required String id,
    required String title,
    this.modelId = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.pinned = const Value.absent(),
    this.folder = const Value.absent(),
    this.tags = const Value.absent(),
    this.overridesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Chat> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? modelId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? pinned,
    Expression<String>? folder,
    Expression<String>? tags,
    Expression<String>? overridesJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (modelId != null) 'model_id': modelId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (pinned != null) 'pinned': pinned,
      if (folder != null) 'folder': folder,
      if (tags != null) 'tags': tags,
      if (overridesJson != null) 'overrides_json': overridesJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? modelId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? pinned,
    Value<String?>? folder,
    Value<String>? tags,
    Value<String>? overridesJson,
    Value<int>? rowid,
  }) {
    return ChatsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      modelId: modelId ?? this.modelId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      folder: folder ?? this.folder,
      tags: tags ?? this.tags,
      overridesJson: overridesJson ?? this.overridesJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (folder.present) {
      map['folder'] = Variable<String>(folder.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (overridesJson.present) {
      map['overrides_json'] = Variable<String>(overridesJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('modelId: $modelId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('pinned: $pinned, ')
          ..write('folder: $folder, ')
          ..write('tags: $tags, ')
          ..write('overridesJson: $overridesJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES chats (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasoningMeta = const VerificationMeta(
    'reasoning',
  );
  @override
  late final GeneratedColumn<String> reasoning = GeneratedColumn<String>(
    'reasoning',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('complete'),
  );
  static const VerificationMeta _sourcesJsonMeta = const VerificationMeta(
    'sourcesJson',
  );
  @override
  late final GeneratedColumn<String> sourcesJson = GeneratedColumn<String>(
    'sources_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _runJsonMeta = const VerificationMeta(
    'runJson',
  );
  @override
  late final GeneratedColumn<String> runJson = GeneratedColumn<String>(
    'run_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokenCountMeta = const VerificationMeta(
    'tokenCount',
  );
  @override
  late final GeneratedColumn<int> tokenCount = GeneratedColumn<int>(
    'token_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    chatId,
    role,
    content,
    reasoning,
    status,
    sourcesJson,
    attachmentsJson,
    modelId,
    parentId,
    runJson,
    timestamp,
    tokenCount,
    sequence,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('reasoning')) {
      context.handle(
        _reasoningMeta,
        reasoning.isAcceptableOrUnknown(data['reasoning']!, _reasoningMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('sources_json')) {
      context.handle(
        _sourcesJsonMeta,
        sourcesJson.isAcceptableOrUnknown(
          data['sources_json']!,
          _sourcesJsonMeta,
        ),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('run_json')) {
      context.handle(
        _runJsonMeta,
        runJson.isAcceptableOrUnknown(data['run_json']!, _runJsonMeta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('token_count')) {
      context.handle(
        _tokenCountMeta,
        tokenCount.isAcceptableOrUnknown(data['token_count']!, _tokenCountMeta),
      );
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chat_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      reasoning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reasoning'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      sourcesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sources_json'],
      )!,
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      ),
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      runJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}run_json'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      tokenCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}token_count'],
      ),
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String chatId;
  final String role;
  final String content;
  final String? reasoning;
  final String status;
  final String sourcesJson;

  /// Files attached to a user turn (schema v2): JSON list of
  /// `Attachment.toJson()`; document text travels with the row so a chat
  /// can be reopened and continued after the source file is gone.
  final String attachmentsJson;
  final String? modelId;

  /// The turn this one continues (schema v7): a question's parent is the
  /// answer before it, an answer's parent is its question, an edited or
  /// regenerated turn is a sibling of the one it replaces. The live
  /// conversation is the chain from the newest live row back to the root;
  /// restoring a branch follows this instead of storage order.
  final String? parentId;

  /// What produced an answer (schema v8, CHAT-04): `TurnRun.toJson()` —
  /// effective settings, preset, model, engine parameters and metrics.
  final String? runJson;
  final DateTime timestamp;
  final int? tokenCount;
  final int sequence;
  const Message({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    this.reasoning,
    required this.status,
    required this.sourcesJson,
    required this.attachmentsJson,
    this.modelId,
    this.parentId,
    this.runJson,
    required this.timestamp,
    this.tokenCount,
    required this.sequence,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['chat_id'] = Variable<String>(chatId);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || reasoning != null) {
      map['reasoning'] = Variable<String>(reasoning);
    }
    map['status'] = Variable<String>(status);
    map['sources_json'] = Variable<String>(sourcesJson);
    map['attachments_json'] = Variable<String>(attachmentsJson);
    if (!nullToAbsent || modelId != null) {
      map['model_id'] = Variable<String>(modelId);
    }
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || runJson != null) {
      map['run_json'] = Variable<String>(runJson);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    if (!nullToAbsent || tokenCount != null) {
      map['token_count'] = Variable<int>(tokenCount);
    }
    map['sequence'] = Variable<int>(sequence);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      chatId: Value(chatId),
      role: Value(role),
      content: Value(content),
      reasoning: reasoning == null && nullToAbsent
          ? const Value.absent()
          : Value(reasoning),
      status: Value(status),
      sourcesJson: Value(sourcesJson),
      attachmentsJson: Value(attachmentsJson),
      modelId: modelId == null && nullToAbsent
          ? const Value.absent()
          : Value(modelId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      runJson: runJson == null && nullToAbsent
          ? const Value.absent()
          : Value(runJson),
      timestamp: Value(timestamp),
      tokenCount: tokenCount == null && nullToAbsent
          ? const Value.absent()
          : Value(tokenCount),
      sequence: Value(sequence),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      chatId: serializer.fromJson<String>(json['chatId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      reasoning: serializer.fromJson<String?>(json['reasoning']),
      status: serializer.fromJson<String>(json['status']),
      sourcesJson: serializer.fromJson<String>(json['sourcesJson']),
      attachmentsJson: serializer.fromJson<String>(json['attachmentsJson']),
      modelId: serializer.fromJson<String?>(json['modelId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      runJson: serializer.fromJson<String?>(json['runJson']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      tokenCount: serializer.fromJson<int?>(json['tokenCount']),
      sequence: serializer.fromJson<int>(json['sequence']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'chatId': serializer.toJson<String>(chatId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'reasoning': serializer.toJson<String?>(reasoning),
      'status': serializer.toJson<String>(status),
      'sourcesJson': serializer.toJson<String>(sourcesJson),
      'attachmentsJson': serializer.toJson<String>(attachmentsJson),
      'modelId': serializer.toJson<String?>(modelId),
      'parentId': serializer.toJson<String?>(parentId),
      'runJson': serializer.toJson<String?>(runJson),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'tokenCount': serializer.toJson<int?>(tokenCount),
      'sequence': serializer.toJson<int>(sequence),
    };
  }

  Message copyWith({
    String? id,
    String? chatId,
    String? role,
    String? content,
    Value<String?> reasoning = const Value.absent(),
    String? status,
    String? sourcesJson,
    String? attachmentsJson,
    Value<String?> modelId = const Value.absent(),
    Value<String?> parentId = const Value.absent(),
    Value<String?> runJson = const Value.absent(),
    DateTime? timestamp,
    Value<int?> tokenCount = const Value.absent(),
    int? sequence,
  }) => Message(
    id: id ?? this.id,
    chatId: chatId ?? this.chatId,
    role: role ?? this.role,
    content: content ?? this.content,
    reasoning: reasoning.present ? reasoning.value : this.reasoning,
    status: status ?? this.status,
    sourcesJson: sourcesJson ?? this.sourcesJson,
    attachmentsJson: attachmentsJson ?? this.attachmentsJson,
    modelId: modelId.present ? modelId.value : this.modelId,
    parentId: parentId.present ? parentId.value : this.parentId,
    runJson: runJson.present ? runJson.value : this.runJson,
    timestamp: timestamp ?? this.timestamp,
    tokenCount: tokenCount.present ? tokenCount.value : this.tokenCount,
    sequence: sequence ?? this.sequence,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      reasoning: data.reasoning.present ? data.reasoning.value : this.reasoning,
      status: data.status.present ? data.status.value : this.status,
      sourcesJson: data.sourcesJson.present
          ? data.sourcesJson.value
          : this.sourcesJson,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      runJson: data.runJson.present ? data.runJson.value : this.runJson,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      tokenCount: data.tokenCount.present
          ? data.tokenCount.value
          : this.tokenCount,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('chatId: $chatId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('reasoning: $reasoning, ')
          ..write('status: $status, ')
          ..write('sourcesJson: $sourcesJson, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('modelId: $modelId, ')
          ..write('parentId: $parentId, ')
          ..write('runJson: $runJson, ')
          ..write('timestamp: $timestamp, ')
          ..write('tokenCount: $tokenCount, ')
          ..write('sequence: $sequence')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    chatId,
    role,
    content,
    reasoning,
    status,
    sourcesJson,
    attachmentsJson,
    modelId,
    parentId,
    runJson,
    timestamp,
    tokenCount,
    sequence,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.chatId == this.chatId &&
          other.role == this.role &&
          other.content == this.content &&
          other.reasoning == this.reasoning &&
          other.status == this.status &&
          other.sourcesJson == this.sourcesJson &&
          other.attachmentsJson == this.attachmentsJson &&
          other.modelId == this.modelId &&
          other.parentId == this.parentId &&
          other.runJson == this.runJson &&
          other.timestamp == this.timestamp &&
          other.tokenCount == this.tokenCount &&
          other.sequence == this.sequence);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> chatId;
  final Value<String> role;
  final Value<String> content;
  final Value<String?> reasoning;
  final Value<String> status;
  final Value<String> sourcesJson;
  final Value<String> attachmentsJson;
  final Value<String?> modelId;
  final Value<String?> parentId;
  final Value<String?> runJson;
  final Value<DateTime> timestamp;
  final Value<int?> tokenCount;
  final Value<int> sequence;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.chatId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.reasoning = const Value.absent(),
    this.status = const Value.absent(),
    this.sourcesJson = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.modelId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.runJson = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.tokenCount = const Value.absent(),
    this.sequence = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String chatId,
    required String role,
    required String content,
    this.reasoning = const Value.absent(),
    this.status = const Value.absent(),
    this.sourcesJson = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.modelId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.runJson = const Value.absent(),
    required DateTime timestamp,
    this.tokenCount = const Value.absent(),
    required int sequence,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       chatId = Value(chatId),
       role = Value(role),
       content = Value(content),
       timestamp = Value(timestamp),
       sequence = Value(sequence);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? chatId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<String>? reasoning,
    Expression<String>? status,
    Expression<String>? sourcesJson,
    Expression<String>? attachmentsJson,
    Expression<String>? modelId,
    Expression<String>? parentId,
    Expression<String>? runJson,
    Expression<DateTime>? timestamp,
    Expression<int>? tokenCount,
    Expression<int>? sequence,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (chatId != null) 'chat_id': chatId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (reasoning != null) 'reasoning': reasoning,
      if (status != null) 'status': status,
      if (sourcesJson != null) 'sources_json': sourcesJson,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (modelId != null) 'model_id': modelId,
      if (parentId != null) 'parent_id': parentId,
      if (runJson != null) 'run_json': runJson,
      if (timestamp != null) 'timestamp': timestamp,
      if (tokenCount != null) 'token_count': tokenCount,
      if (sequence != null) 'sequence': sequence,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? chatId,
    Value<String>? role,
    Value<String>? content,
    Value<String?>? reasoning,
    Value<String>? status,
    Value<String>? sourcesJson,
    Value<String>? attachmentsJson,
    Value<String?>? modelId,
    Value<String?>? parentId,
    Value<String?>? runJson,
    Value<DateTime>? timestamp,
    Value<int?>? tokenCount,
    Value<int>? sequence,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      role: role ?? this.role,
      content: content ?? this.content,
      reasoning: reasoning ?? this.reasoning,
      status: status ?? this.status,
      sourcesJson: sourcesJson ?? this.sourcesJson,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      modelId: modelId ?? this.modelId,
      parentId: parentId ?? this.parentId,
      runJson: runJson ?? this.runJson,
      timestamp: timestamp ?? this.timestamp,
      tokenCount: tokenCount ?? this.tokenCount,
      sequence: sequence ?? this.sequence,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (reasoning.present) {
      map['reasoning'] = Variable<String>(reasoning.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (sourcesJson.present) {
      map['sources_json'] = Variable<String>(sourcesJson.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (runJson.present) {
      map['run_json'] = Variable<String>(runJson.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (tokenCount.present) {
      map['token_count'] = Variable<int>(tokenCount.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('chatId: $chatId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('reasoning: $reasoning, ')
          ..write('status: $status, ')
          ..write('sourcesJson: $sourcesJson, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('modelId: $modelId, ')
          ..write('parentId: $parentId, ')
          ..write('runJson: $runJson, ')
          ..write('timestamp: $timestamp, ')
          ..write('tokenCount: $tokenCount, ')
          ..write('sequence: $sequence, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ModelsTable extends Models with TableInfo<$ModelsTable, Model> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _downloadUrlMeta = const VerificationMeta(
    'downloadUrl',
  );
  @override
  late final GeneratedColumn<String> downloadUrl = GeneratedColumn<String>(
    'download_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _licenseMeta = const VerificationMeta(
    'license',
  );
  @override
  late final GeneratedColumn<String> license = GeneratedColumn<String>(
    'license',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('See publisher model card'),
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parameterCountBMeta = const VerificationMeta(
    'parameterCountB',
  );
  @override
  late final GeneratedColumn<int> parameterCountB = GeneratedColumn<int>(
    'parameter_count_b',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _familyMeta = const VerificationMeta('family');
  @override
  late final GeneratedColumn<String> family = GeneratedColumn<String>(
    'family',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantizationMeta = const VerificationMeta(
    'quantization',
  );
  @override
  late final GeneratedColumn<String> quantization = GeneratedColumn<String>(
    'quantization',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDownloadedMeta = const VerificationMeta(
    'isDownloaded',
  );
  @override
  late final GeneratedColumn<bool> isDownloaded = GeneratedColumn<bool>(
    'is_downloaded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_downloaded" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _downloadedAtMeta = const VerificationMeta(
    'downloadedAt',
  );
  @override
  late final GeneratedColumn<DateTime> downloadedAt = GeneratedColumn<DateTime>(
    'downloaded_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    displayName,
    fileName,
    downloadUrl,
    sha256,
    license,
    sizeBytes,
    parameterCountB,
    family,
    quantization,
    isDownloaded,
    localPath,
    downloadedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'models';
  @override
  VerificationContext validateIntegrity(
    Insertable<Model> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('download_url')) {
      context.handle(
        _downloadUrlMeta,
        downloadUrl.isAcceptableOrUnknown(
          data['download_url']!,
          _downloadUrlMeta,
        ),
      );
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('license')) {
      context.handle(
        _licenseMeta,
        license.isAcceptableOrUnknown(data['license']!, _licenseMeta),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('parameter_count_b')) {
      context.handle(
        _parameterCountBMeta,
        parameterCountB.isAcceptableOrUnknown(
          data['parameter_count_b']!,
          _parameterCountBMeta,
        ),
      );
    }
    if (data.containsKey('family')) {
      context.handle(
        _familyMeta,
        family.isAcceptableOrUnknown(data['family']!, _familyMeta),
      );
    } else if (isInserting) {
      context.missing(_familyMeta);
    }
    if (data.containsKey('quantization')) {
      context.handle(
        _quantizationMeta,
        quantization.isAcceptableOrUnknown(
          data['quantization']!,
          _quantizationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quantizationMeta);
    }
    if (data.containsKey('is_downloaded')) {
      context.handle(
        _isDownloadedMeta,
        isDownloaded.isAcceptableOrUnknown(
          data['is_downloaded']!,
          _isDownloadedMeta,
        ),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('downloaded_at')) {
      context.handle(
        _downloadedAtMeta,
        downloadedAt.isAcceptableOrUnknown(
          data['downloaded_at']!,
          _downloadedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Model map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Model(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      downloadUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}download_url'],
      ),
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      license: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}license'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      parameterCountB: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parameter_count_b'],
      ),
      family: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}family'],
      )!,
      quantization: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quantization'],
      )!,
      isDownloaded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_downloaded'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      downloadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}downloaded_at'],
      ),
    );
  }

  @override
  $ModelsTable createAlias(String alias) {
    return $ModelsTable(attachedDatabase, alias);
  }
}

class Model extends DataClass implements Insertable<Model> {
  final String id;
  final String displayName;
  final String fileName;
  final String? downloadUrl;
  final String? sha256;
  final String license;
  final int sizeBytes;
  final int? parameterCountB;
  final String family;
  final String quantization;
  final bool isDownloaded;
  final String? localPath;
  final DateTime? downloadedAt;
  const Model({
    required this.id,
    required this.displayName,
    required this.fileName,
    this.downloadUrl,
    this.sha256,
    required this.license,
    required this.sizeBytes,
    this.parameterCountB,
    required this.family,
    required this.quantization,
    required this.isDownloaded,
    this.localPath,
    this.downloadedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    map['file_name'] = Variable<String>(fileName);
    if (!nullToAbsent || downloadUrl != null) {
      map['download_url'] = Variable<String>(downloadUrl);
    }
    if (!nullToAbsent || sha256 != null) {
      map['sha256'] = Variable<String>(sha256);
    }
    map['license'] = Variable<String>(license);
    map['size_bytes'] = Variable<int>(sizeBytes);
    if (!nullToAbsent || parameterCountB != null) {
      map['parameter_count_b'] = Variable<int>(parameterCountB);
    }
    map['family'] = Variable<String>(family);
    map['quantization'] = Variable<String>(quantization);
    map['is_downloaded'] = Variable<bool>(isDownloaded);
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    if (!nullToAbsent || downloadedAt != null) {
      map['downloaded_at'] = Variable<DateTime>(downloadedAt);
    }
    return map;
  }

  ModelsCompanion toCompanion(bool nullToAbsent) {
    return ModelsCompanion(
      id: Value(id),
      displayName: Value(displayName),
      fileName: Value(fileName),
      downloadUrl: downloadUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(downloadUrl),
      sha256: sha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256),
      license: Value(license),
      sizeBytes: Value(sizeBytes),
      parameterCountB: parameterCountB == null && nullToAbsent
          ? const Value.absent()
          : Value(parameterCountB),
      family: Value(family),
      quantization: Value(quantization),
      isDownloaded: Value(isDownloaded),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      downloadedAt: downloadedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(downloadedAt),
    );
  }

  factory Model.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Model(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      fileName: serializer.fromJson<String>(json['fileName']),
      downloadUrl: serializer.fromJson<String?>(json['downloadUrl']),
      sha256: serializer.fromJson<String?>(json['sha256']),
      license: serializer.fromJson<String>(json['license']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      parameterCountB: serializer.fromJson<int?>(json['parameterCountB']),
      family: serializer.fromJson<String>(json['family']),
      quantization: serializer.fromJson<String>(json['quantization']),
      isDownloaded: serializer.fromJson<bool>(json['isDownloaded']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      downloadedAt: serializer.fromJson<DateTime?>(json['downloadedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'fileName': serializer.toJson<String>(fileName),
      'downloadUrl': serializer.toJson<String?>(downloadUrl),
      'sha256': serializer.toJson<String?>(sha256),
      'license': serializer.toJson<String>(license),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'parameterCountB': serializer.toJson<int?>(parameterCountB),
      'family': serializer.toJson<String>(family),
      'quantization': serializer.toJson<String>(quantization),
      'isDownloaded': serializer.toJson<bool>(isDownloaded),
      'localPath': serializer.toJson<String?>(localPath),
      'downloadedAt': serializer.toJson<DateTime?>(downloadedAt),
    };
  }

  Model copyWith({
    String? id,
    String? displayName,
    String? fileName,
    Value<String?> downloadUrl = const Value.absent(),
    Value<String?> sha256 = const Value.absent(),
    String? license,
    int? sizeBytes,
    Value<int?> parameterCountB = const Value.absent(),
    String? family,
    String? quantization,
    bool? isDownloaded,
    Value<String?> localPath = const Value.absent(),
    Value<DateTime?> downloadedAt = const Value.absent(),
  }) => Model(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    fileName: fileName ?? this.fileName,
    downloadUrl: downloadUrl.present ? downloadUrl.value : this.downloadUrl,
    sha256: sha256.present ? sha256.value : this.sha256,
    license: license ?? this.license,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    parameterCountB: parameterCountB.present
        ? parameterCountB.value
        : this.parameterCountB,
    family: family ?? this.family,
    quantization: quantization ?? this.quantization,
    isDownloaded: isDownloaded ?? this.isDownloaded,
    localPath: localPath.present ? localPath.value : this.localPath,
    downloadedAt: downloadedAt.present ? downloadedAt.value : this.downloadedAt,
  );
  Model copyWithCompanion(ModelsCompanion data) {
    return Model(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      downloadUrl: data.downloadUrl.present
          ? data.downloadUrl.value
          : this.downloadUrl,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      license: data.license.present ? data.license.value : this.license,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      parameterCountB: data.parameterCountB.present
          ? data.parameterCountB.value
          : this.parameterCountB,
      family: data.family.present ? data.family.value : this.family,
      quantization: data.quantization.present
          ? data.quantization.value
          : this.quantization,
      isDownloaded: data.isDownloaded.present
          ? data.isDownloaded.value
          : this.isDownloaded,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      downloadedAt: data.downloadedAt.present
          ? data.downloadedAt.value
          : this.downloadedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Model(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('fileName: $fileName, ')
          ..write('downloadUrl: $downloadUrl, ')
          ..write('sha256: $sha256, ')
          ..write('license: $license, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('parameterCountB: $parameterCountB, ')
          ..write('family: $family, ')
          ..write('quantization: $quantization, ')
          ..write('isDownloaded: $isDownloaded, ')
          ..write('localPath: $localPath, ')
          ..write('downloadedAt: $downloadedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    fileName,
    downloadUrl,
    sha256,
    license,
    sizeBytes,
    parameterCountB,
    family,
    quantization,
    isDownloaded,
    localPath,
    downloadedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Model &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.fileName == this.fileName &&
          other.downloadUrl == this.downloadUrl &&
          other.sha256 == this.sha256 &&
          other.license == this.license &&
          other.sizeBytes == this.sizeBytes &&
          other.parameterCountB == this.parameterCountB &&
          other.family == this.family &&
          other.quantization == this.quantization &&
          other.isDownloaded == this.isDownloaded &&
          other.localPath == this.localPath &&
          other.downloadedAt == this.downloadedAt);
}

class ModelsCompanion extends UpdateCompanion<Model> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<String> fileName;
  final Value<String?> downloadUrl;
  final Value<String?> sha256;
  final Value<String> license;
  final Value<int> sizeBytes;
  final Value<int?> parameterCountB;
  final Value<String> family;
  final Value<String> quantization;
  final Value<bool> isDownloaded;
  final Value<String?> localPath;
  final Value<DateTime?> downloadedAt;
  final Value<int> rowid;
  const ModelsCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.fileName = const Value.absent(),
    this.downloadUrl = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.license = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.parameterCountB = const Value.absent(),
    this.family = const Value.absent(),
    this.quantization = const Value.absent(),
    this.isDownloaded = const Value.absent(),
    this.localPath = const Value.absent(),
    this.downloadedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModelsCompanion.insert({
    required String id,
    required String displayName,
    required String fileName,
    this.downloadUrl = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.license = const Value.absent(),
    required int sizeBytes,
    this.parameterCountB = const Value.absent(),
    required String family,
    required String quantization,
    this.isDownloaded = const Value.absent(),
    this.localPath = const Value.absent(),
    this.downloadedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName),
       fileName = Value(fileName),
       sizeBytes = Value(sizeBytes),
       family = Value(family),
       quantization = Value(quantization);
  static Insertable<Model> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<String>? fileName,
    Expression<String>? downloadUrl,
    Expression<String>? sha256,
    Expression<String>? license,
    Expression<int>? sizeBytes,
    Expression<int>? parameterCountB,
    Expression<String>? family,
    Expression<String>? quantization,
    Expression<bool>? isDownloaded,
    Expression<String>? localPath,
    Expression<DateTime>? downloadedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (fileName != null) 'file_name': fileName,
      if (downloadUrl != null) 'download_url': downloadUrl,
      if (sha256 != null) 'sha256': sha256,
      if (license != null) 'license': license,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (parameterCountB != null) 'parameter_count_b': parameterCountB,
      if (family != null) 'family': family,
      if (quantization != null) 'quantization': quantization,
      if (isDownloaded != null) 'is_downloaded': isDownloaded,
      if (localPath != null) 'local_path': localPath,
      if (downloadedAt != null) 'downloaded_at': downloadedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModelsCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<String>? fileName,
    Value<String?>? downloadUrl,
    Value<String?>? sha256,
    Value<String>? license,
    Value<int>? sizeBytes,
    Value<int?>? parameterCountB,
    Value<String>? family,
    Value<String>? quantization,
    Value<bool>? isDownloaded,
    Value<String?>? localPath,
    Value<DateTime?>? downloadedAt,
    Value<int>? rowid,
  }) {
    return ModelsCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      fileName: fileName ?? this.fileName,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      sha256: sha256 ?? this.sha256,
      license: license ?? this.license,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      parameterCountB: parameterCountB ?? this.parameterCountB,
      family: family ?? this.family,
      quantization: quantization ?? this.quantization,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      localPath: localPath ?? this.localPath,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (downloadUrl.present) {
      map['download_url'] = Variable<String>(downloadUrl.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (license.present) {
      map['license'] = Variable<String>(license.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (parameterCountB.present) {
      map['parameter_count_b'] = Variable<int>(parameterCountB.value);
    }
    if (family.present) {
      map['family'] = Variable<String>(family.value);
    }
    if (quantization.present) {
      map['quantization'] = Variable<String>(quantization.value);
    }
    if (isDownloaded.present) {
      map['is_downloaded'] = Variable<bool>(isDownloaded.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (downloadedAt.present) {
      map['downloaded_at'] = Variable<DateTime>(downloadedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModelsCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('fileName: $fileName, ')
          ..write('downloadUrl: $downloadUrl, ')
          ..write('sha256: $sha256, ')
          ..write('license: $license, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('parameterCountB: $parameterCountB, ')
          ..write('family: $family, ')
          ..write('quantization: $quantization, ')
          ..write('isDownloaded: $isDownloaded, ')
          ..write('localPath: $localPath, ')
          ..write('downloadedAt: $downloadedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MemoriesTable extends Memories with TableInfo<$MemoriesTable, Memory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceChatIdMeta = const VerificationMeta(
    'sourceChatId',
  );
  @override
  late final GeneratedColumn<String> sourceChatId = GeneratedColumn<String>(
    'source_chat_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMessageIdMeta = const VerificationMeta(
    'sourceMessageId',
  );
  @override
  late final GeneratedColumn<String> sourceMessageId = GeneratedColumn<String>(
    'source_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    content,
    sourceChatId,
    sourceMessageId,
    pinned,
    expiresAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Memory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('source_chat_id')) {
      context.handle(
        _sourceChatIdMeta,
        sourceChatId.isAcceptableOrUnknown(
          data['source_chat_id']!,
          _sourceChatIdMeta,
        ),
      );
    }
    if (data.containsKey('source_message_id')) {
      context.handle(
        _sourceMessageIdMeta,
        sourceMessageId.isAcceptableOrUnknown(
          data['source_message_id']!,
          _sourceMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Memory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Memory(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      sourceChatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_chat_id'],
      ),
      sourceMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_message_id'],
      ),
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MemoriesTable createAlias(String alias) {
    return $MemoriesTable(attachedDatabase, alias);
  }
}

class Memory extends DataClass implements Insertable<Memory> {
  final String id;
  final String content;

  /// Chat the fact was learned from; null when added manually.
  final String? sourceChatId;
  final String? sourceMessageId;
  final bool pinned;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Memory({
    required this.id,
    required this.content,
    this.sourceChatId,
    this.sourceMessageId,
    required this.pinned,
    this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || sourceChatId != null) {
      map['source_chat_id'] = Variable<String>(sourceChatId);
    }
    if (!nullToAbsent || sourceMessageId != null) {
      map['source_message_id'] = Variable<String>(sourceMessageId);
    }
    map['pinned'] = Variable<bool>(pinned);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MemoriesCompanion toCompanion(bool nullToAbsent) {
    return MemoriesCompanion(
      id: Value(id),
      content: Value(content),
      sourceChatId: sourceChatId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceChatId),
      sourceMessageId: sourceMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceMessageId),
      pinned: Value(pinned),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Memory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Memory(
      id: serializer.fromJson<String>(json['id']),
      content: serializer.fromJson<String>(json['content']),
      sourceChatId: serializer.fromJson<String?>(json['sourceChatId']),
      sourceMessageId: serializer.fromJson<String?>(json['sourceMessageId']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'content': serializer.toJson<String>(content),
      'sourceChatId': serializer.toJson<String?>(sourceChatId),
      'sourceMessageId': serializer.toJson<String?>(sourceMessageId),
      'pinned': serializer.toJson<bool>(pinned),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Memory copyWith({
    String? id,
    String? content,
    Value<String?> sourceChatId = const Value.absent(),
    Value<String?> sourceMessageId = const Value.absent(),
    bool? pinned,
    Value<DateTime?> expiresAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Memory(
    id: id ?? this.id,
    content: content ?? this.content,
    sourceChatId: sourceChatId.present ? sourceChatId.value : this.sourceChatId,
    sourceMessageId: sourceMessageId.present
        ? sourceMessageId.value
        : this.sourceMessageId,
    pinned: pinned ?? this.pinned,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Memory copyWithCompanion(MemoriesCompanion data) {
    return Memory(
      id: data.id.present ? data.id.value : this.id,
      content: data.content.present ? data.content.value : this.content,
      sourceChatId: data.sourceChatId.present
          ? data.sourceChatId.value
          : this.sourceChatId,
      sourceMessageId: data.sourceMessageId.present
          ? data.sourceMessageId.value
          : this.sourceMessageId,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Memory(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('sourceChatId: $sourceChatId, ')
          ..write('sourceMessageId: $sourceMessageId, ')
          ..write('pinned: $pinned, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    content,
    sourceChatId,
    sourceMessageId,
    pinned,
    expiresAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Memory &&
          other.id == this.id &&
          other.content == this.content &&
          other.sourceChatId == this.sourceChatId &&
          other.sourceMessageId == this.sourceMessageId &&
          other.pinned == this.pinned &&
          other.expiresAt == this.expiresAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MemoriesCompanion extends UpdateCompanion<Memory> {
  final Value<String> id;
  final Value<String> content;
  final Value<String?> sourceChatId;
  final Value<String?> sourceMessageId;
  final Value<bool> pinned;
  final Value<DateTime?> expiresAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MemoriesCompanion({
    this.id = const Value.absent(),
    this.content = const Value.absent(),
    this.sourceChatId = const Value.absent(),
    this.sourceMessageId = const Value.absent(),
    this.pinned = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemoriesCompanion.insert({
    required String id,
    required String content,
    this.sourceChatId = const Value.absent(),
    this.sourceMessageId = const Value.absent(),
    this.pinned = const Value.absent(),
    this.expiresAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       content = Value(content),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Memory> custom({
    Expression<String>? id,
    Expression<String>? content,
    Expression<String>? sourceChatId,
    Expression<String>? sourceMessageId,
    Expression<bool>? pinned,
    Expression<DateTime>? expiresAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (content != null) 'content': content,
      if (sourceChatId != null) 'source_chat_id': sourceChatId,
      if (sourceMessageId != null) 'source_message_id': sourceMessageId,
      if (pinned != null) 'pinned': pinned,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? content,
    Value<String?>? sourceChatId,
    Value<String?>? sourceMessageId,
    Value<bool>? pinned,
    Value<DateTime?>? expiresAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return MemoriesCompanion(
      id: id ?? this.id,
      content: content ?? this.content,
      sourceChatId: sourceChatId ?? this.sourceChatId,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      pinned: pinned ?? this.pinned,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (sourceChatId.present) {
      map['source_chat_id'] = Variable<String>(sourceChatId.value);
    }
    if (sourceMessageId.present) {
      map['source_message_id'] = Variable<String>(sourceMessageId.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoriesCompanion(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('sourceChatId: $sourceChatId, ')
          ..write('sourceMessageId: $sourceMessageId, ')
          ..write('pinned: $pinned, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KnowledgeDocsTable extends KnowledgeDocs
    with TableInfo<$KnowledgeDocsTable, KnowledgeDoc> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KnowledgeDocsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _collectionMeta = const VerificationMeta(
    'collection',
  );
  @override
  late final GeneratedColumn<String> collection = GeneratedColumn<String>(
    'collection',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text/plain'),
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _charsMeta = const VerificationMeta('chars');
  @override
  late final GeneratedColumn<int> chars = GeneratedColumn<int>(
    'chars',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _chunkCountMeta = const VerificationMeta(
    'chunkCount',
  );
  @override
  late final GeneratedColumn<int> chunkCount = GeneratedColumn<int>(
    'chunk_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extractionFormatMeta = const VerificationMeta(
    'extractionFormat',
  );
  @override
  late final GeneratedColumn<String> extractionFormat = GeneratedColumn<String>(
    'extraction_format',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extractionWarningMeta = const VerificationMeta(
    'extractionWarning',
  );
  @override
  late final GeneratedColumn<String> extractionWarning =
      GeneratedColumn<String>(
        'extraction_warning',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _originalFileMeta = const VerificationMeta(
    'originalFile',
  );
  @override
  late final GeneratedColumn<String> originalFile = GeneratedColumn<String>(
    'original_file',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _previousVersionIdMeta = const VerificationMeta(
    'previousVersionId',
  );
  @override
  late final GeneratedColumn<String> previousVersionId =
      GeneratedColumn<String>(
        'previous_version_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    collection,
    name,
    mime,
    sizeBytes,
    chars,
    chunkCount,
    addedAt,
    contentHash,
    extractionFormat,
    extractionWarning,
    originalFile,
    previousVersionId,
    active,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'knowledge_docs';
  @override
  VerificationContext validateIntegrity(
    Insertable<KnowledgeDoc> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('collection')) {
      context.handle(
        _collectionMeta,
        collection.isAcceptableOrUnknown(data['collection']!, _collectionMeta),
      );
    } else if (isInserting) {
      context.missing(_collectionMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('chars')) {
      context.handle(
        _charsMeta,
        chars.isAcceptableOrUnknown(data['chars']!, _charsMeta),
      );
    }
    if (data.containsKey('chunk_count')) {
      context.handle(
        _chunkCountMeta,
        chunkCount.isAcceptableOrUnknown(data['chunk_count']!, _chunkCountMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    }
    if (data.containsKey('extraction_format')) {
      context.handle(
        _extractionFormatMeta,
        extractionFormat.isAcceptableOrUnknown(
          data['extraction_format']!,
          _extractionFormatMeta,
        ),
      );
    }
    if (data.containsKey('extraction_warning')) {
      context.handle(
        _extractionWarningMeta,
        extractionWarning.isAcceptableOrUnknown(
          data['extraction_warning']!,
          _extractionWarningMeta,
        ),
      );
    }
    if (data.containsKey('original_file')) {
      context.handle(
        _originalFileMeta,
        originalFile.isAcceptableOrUnknown(
          data['original_file']!,
          _originalFileMeta,
        ),
      );
    }
    if (data.containsKey('previous_version_id')) {
      context.handle(
        _previousVersionIdMeta,
        previousVersionId.isAcceptableOrUnknown(
          data['previous_version_id']!,
          _previousVersionIdMeta,
        ),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  KnowledgeDoc map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnowledgeDoc(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      collection: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      chars: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chars'],
      )!,
      chunkCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chunk_count'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      ),
      extractionFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extraction_format'],
      ),
      extractionWarning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extraction_warning'],
      ),
      originalFile: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_file'],
      ),
      previousVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}previous_version_id'],
      ),
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
    );
  }

  @override
  $KnowledgeDocsTable createAlias(String alias) {
    return $KnowledgeDocsTable(attachedDatabase, alias);
  }
}

class KnowledgeDoc extends DataClass implements Insertable<KnowledgeDoc> {
  final String id;
  final String collection;
  final String name;
  final String mime;
  final int sizeBytes;
  final int chars;
  final int chunkCount;
  final DateTime addedAt;
  final String? contentHash;
  final String? extractionFormat;
  final String? extractionWarning;
  final String? originalFile;
  final String? previousVersionId;
  final bool active;
  const KnowledgeDoc({
    required this.id,
    required this.collection,
    required this.name,
    required this.mime,
    required this.sizeBytes,
    required this.chars,
    required this.chunkCount,
    required this.addedAt,
    this.contentHash,
    this.extractionFormat,
    this.extractionWarning,
    this.originalFile,
    this.previousVersionId,
    required this.active,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['collection'] = Variable<String>(collection);
    map['name'] = Variable<String>(name);
    map['mime'] = Variable<String>(mime);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['chars'] = Variable<int>(chars);
    map['chunk_count'] = Variable<int>(chunkCount);
    map['added_at'] = Variable<DateTime>(addedAt);
    if (!nullToAbsent || contentHash != null) {
      map['content_hash'] = Variable<String>(contentHash);
    }
    if (!nullToAbsent || extractionFormat != null) {
      map['extraction_format'] = Variable<String>(extractionFormat);
    }
    if (!nullToAbsent || extractionWarning != null) {
      map['extraction_warning'] = Variable<String>(extractionWarning);
    }
    if (!nullToAbsent || originalFile != null) {
      map['original_file'] = Variable<String>(originalFile);
    }
    if (!nullToAbsent || previousVersionId != null) {
      map['previous_version_id'] = Variable<String>(previousVersionId);
    }
    map['active'] = Variable<bool>(active);
    return map;
  }

  KnowledgeDocsCompanion toCompanion(bool nullToAbsent) {
    return KnowledgeDocsCompanion(
      id: Value(id),
      collection: Value(collection),
      name: Value(name),
      mime: Value(mime),
      sizeBytes: Value(sizeBytes),
      chars: Value(chars),
      chunkCount: Value(chunkCount),
      addedAt: Value(addedAt),
      contentHash: contentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(contentHash),
      extractionFormat: extractionFormat == null && nullToAbsent
          ? const Value.absent()
          : Value(extractionFormat),
      extractionWarning: extractionWarning == null && nullToAbsent
          ? const Value.absent()
          : Value(extractionWarning),
      originalFile: originalFile == null && nullToAbsent
          ? const Value.absent()
          : Value(originalFile),
      previousVersionId: previousVersionId == null && nullToAbsent
          ? const Value.absent()
          : Value(previousVersionId),
      active: Value(active),
    );
  }

  factory KnowledgeDoc.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnowledgeDoc(
      id: serializer.fromJson<String>(json['id']),
      collection: serializer.fromJson<String>(json['collection']),
      name: serializer.fromJson<String>(json['name']),
      mime: serializer.fromJson<String>(json['mime']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      chars: serializer.fromJson<int>(json['chars']),
      chunkCount: serializer.fromJson<int>(json['chunkCount']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      contentHash: serializer.fromJson<String?>(json['contentHash']),
      extractionFormat: serializer.fromJson<String?>(json['extractionFormat']),
      extractionWarning: serializer.fromJson<String?>(
        json['extractionWarning'],
      ),
      originalFile: serializer.fromJson<String?>(json['originalFile']),
      previousVersionId: serializer.fromJson<String?>(
        json['previousVersionId'],
      ),
      active: serializer.fromJson<bool>(json['active']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'collection': serializer.toJson<String>(collection),
      'name': serializer.toJson<String>(name),
      'mime': serializer.toJson<String>(mime),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'chars': serializer.toJson<int>(chars),
      'chunkCount': serializer.toJson<int>(chunkCount),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'contentHash': serializer.toJson<String?>(contentHash),
      'extractionFormat': serializer.toJson<String?>(extractionFormat),
      'extractionWarning': serializer.toJson<String?>(extractionWarning),
      'originalFile': serializer.toJson<String?>(originalFile),
      'previousVersionId': serializer.toJson<String?>(previousVersionId),
      'active': serializer.toJson<bool>(active),
    };
  }

  KnowledgeDoc copyWith({
    String? id,
    String? collection,
    String? name,
    String? mime,
    int? sizeBytes,
    int? chars,
    int? chunkCount,
    DateTime? addedAt,
    Value<String?> contentHash = const Value.absent(),
    Value<String?> extractionFormat = const Value.absent(),
    Value<String?> extractionWarning = const Value.absent(),
    Value<String?> originalFile = const Value.absent(),
    Value<String?> previousVersionId = const Value.absent(),
    bool? active,
  }) => KnowledgeDoc(
    id: id ?? this.id,
    collection: collection ?? this.collection,
    name: name ?? this.name,
    mime: mime ?? this.mime,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    chars: chars ?? this.chars,
    chunkCount: chunkCount ?? this.chunkCount,
    addedAt: addedAt ?? this.addedAt,
    contentHash: contentHash.present ? contentHash.value : this.contentHash,
    extractionFormat: extractionFormat.present
        ? extractionFormat.value
        : this.extractionFormat,
    extractionWarning: extractionWarning.present
        ? extractionWarning.value
        : this.extractionWarning,
    originalFile: originalFile.present ? originalFile.value : this.originalFile,
    previousVersionId: previousVersionId.present
        ? previousVersionId.value
        : this.previousVersionId,
    active: active ?? this.active,
  );
  KnowledgeDoc copyWithCompanion(KnowledgeDocsCompanion data) {
    return KnowledgeDoc(
      id: data.id.present ? data.id.value : this.id,
      collection: data.collection.present
          ? data.collection.value
          : this.collection,
      name: data.name.present ? data.name.value : this.name,
      mime: data.mime.present ? data.mime.value : this.mime,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      chars: data.chars.present ? data.chars.value : this.chars,
      chunkCount: data.chunkCount.present
          ? data.chunkCount.value
          : this.chunkCount,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      extractionFormat: data.extractionFormat.present
          ? data.extractionFormat.value
          : this.extractionFormat,
      extractionWarning: data.extractionWarning.present
          ? data.extractionWarning.value
          : this.extractionWarning,
      originalFile: data.originalFile.present
          ? data.originalFile.value
          : this.originalFile,
      previousVersionId: data.previousVersionId.present
          ? data.previousVersionId.value
          : this.previousVersionId,
      active: data.active.present ? data.active.value : this.active,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgeDoc(')
          ..write('id: $id, ')
          ..write('collection: $collection, ')
          ..write('name: $name, ')
          ..write('mime: $mime, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('chars: $chars, ')
          ..write('chunkCount: $chunkCount, ')
          ..write('addedAt: $addedAt, ')
          ..write('contentHash: $contentHash, ')
          ..write('extractionFormat: $extractionFormat, ')
          ..write('extractionWarning: $extractionWarning, ')
          ..write('originalFile: $originalFile, ')
          ..write('previousVersionId: $previousVersionId, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    collection,
    name,
    mime,
    sizeBytes,
    chars,
    chunkCount,
    addedAt,
    contentHash,
    extractionFormat,
    extractionWarning,
    originalFile,
    previousVersionId,
    active,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnowledgeDoc &&
          other.id == this.id &&
          other.collection == this.collection &&
          other.name == this.name &&
          other.mime == this.mime &&
          other.sizeBytes == this.sizeBytes &&
          other.chars == this.chars &&
          other.chunkCount == this.chunkCount &&
          other.addedAt == this.addedAt &&
          other.contentHash == this.contentHash &&
          other.extractionFormat == this.extractionFormat &&
          other.extractionWarning == this.extractionWarning &&
          other.originalFile == this.originalFile &&
          other.previousVersionId == this.previousVersionId &&
          other.active == this.active);
}

class KnowledgeDocsCompanion extends UpdateCompanion<KnowledgeDoc> {
  final Value<String> id;
  final Value<String> collection;
  final Value<String> name;
  final Value<String> mime;
  final Value<int> sizeBytes;
  final Value<int> chars;
  final Value<int> chunkCount;
  final Value<DateTime> addedAt;
  final Value<String?> contentHash;
  final Value<String?> extractionFormat;
  final Value<String?> extractionWarning;
  final Value<String?> originalFile;
  final Value<String?> previousVersionId;
  final Value<bool> active;
  final Value<int> rowid;
  const KnowledgeDocsCompanion({
    this.id = const Value.absent(),
    this.collection = const Value.absent(),
    this.name = const Value.absent(),
    this.mime = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.chars = const Value.absent(),
    this.chunkCount = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.extractionFormat = const Value.absent(),
    this.extractionWarning = const Value.absent(),
    this.originalFile = const Value.absent(),
    this.previousVersionId = const Value.absent(),
    this.active = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KnowledgeDocsCompanion.insert({
    required String id,
    required String collection,
    required String name,
    this.mime = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.chars = const Value.absent(),
    this.chunkCount = const Value.absent(),
    required DateTime addedAt,
    this.contentHash = const Value.absent(),
    this.extractionFormat = const Value.absent(),
    this.extractionWarning = const Value.absent(),
    this.originalFile = const Value.absent(),
    this.previousVersionId = const Value.absent(),
    this.active = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       collection = Value(collection),
       name = Value(name),
       addedAt = Value(addedAt);
  static Insertable<KnowledgeDoc> custom({
    Expression<String>? id,
    Expression<String>? collection,
    Expression<String>? name,
    Expression<String>? mime,
    Expression<int>? sizeBytes,
    Expression<int>? chars,
    Expression<int>? chunkCount,
    Expression<DateTime>? addedAt,
    Expression<String>? contentHash,
    Expression<String>? extractionFormat,
    Expression<String>? extractionWarning,
    Expression<String>? originalFile,
    Expression<String>? previousVersionId,
    Expression<bool>? active,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (collection != null) 'collection': collection,
      if (name != null) 'name': name,
      if (mime != null) 'mime': mime,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (chars != null) 'chars': chars,
      if (chunkCount != null) 'chunk_count': chunkCount,
      if (addedAt != null) 'added_at': addedAt,
      if (contentHash != null) 'content_hash': contentHash,
      if (extractionFormat != null) 'extraction_format': extractionFormat,
      if (extractionWarning != null) 'extraction_warning': extractionWarning,
      if (originalFile != null) 'original_file': originalFile,
      if (previousVersionId != null) 'previous_version_id': previousVersionId,
      if (active != null) 'active': active,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KnowledgeDocsCompanion copyWith({
    Value<String>? id,
    Value<String>? collection,
    Value<String>? name,
    Value<String>? mime,
    Value<int>? sizeBytes,
    Value<int>? chars,
    Value<int>? chunkCount,
    Value<DateTime>? addedAt,
    Value<String?>? contentHash,
    Value<String?>? extractionFormat,
    Value<String?>? extractionWarning,
    Value<String?>? originalFile,
    Value<String?>? previousVersionId,
    Value<bool>? active,
    Value<int>? rowid,
  }) {
    return KnowledgeDocsCompanion(
      id: id ?? this.id,
      collection: collection ?? this.collection,
      name: name ?? this.name,
      mime: mime ?? this.mime,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      chars: chars ?? this.chars,
      chunkCount: chunkCount ?? this.chunkCount,
      addedAt: addedAt ?? this.addedAt,
      contentHash: contentHash ?? this.contentHash,
      extractionFormat: extractionFormat ?? this.extractionFormat,
      extractionWarning: extractionWarning ?? this.extractionWarning,
      originalFile: originalFile ?? this.originalFile,
      previousVersionId: previousVersionId ?? this.previousVersionId,
      active: active ?? this.active,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (collection.present) {
      map['collection'] = Variable<String>(collection.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (chars.present) {
      map['chars'] = Variable<int>(chars.value);
    }
    if (chunkCount.present) {
      map['chunk_count'] = Variable<int>(chunkCount.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (extractionFormat.present) {
      map['extraction_format'] = Variable<String>(extractionFormat.value);
    }
    if (extractionWarning.present) {
      map['extraction_warning'] = Variable<String>(extractionWarning.value);
    }
    if (originalFile.present) {
      map['original_file'] = Variable<String>(originalFile.value);
    }
    if (previousVersionId.present) {
      map['previous_version_id'] = Variable<String>(previousVersionId.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgeDocsCompanion(')
          ..write('id: $id, ')
          ..write('collection: $collection, ')
          ..write('name: $name, ')
          ..write('mime: $mime, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('chars: $chars, ')
          ..write('chunkCount: $chunkCount, ')
          ..write('addedAt: $addedAt, ')
          ..write('contentHash: $contentHash, ')
          ..write('extractionFormat: $extractionFormat, ')
          ..write('extractionWarning: $extractionWarning, ')
          ..write('originalFile: $originalFile, ')
          ..write('previousVersionId: $previousVersionId, ')
          ..write('active: $active, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KnowledgeChunksTable extends KnowledgeChunks
    with TableInfo<$KnowledgeChunksTable, KnowledgeChunk> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KnowledgeChunksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  @override
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
    'doc_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES knowledge_docs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageNumberMeta = const VerificationMeta(
    'pageNumber',
  );
  @override
  late final GeneratedColumn<int> pageNumber = GeneratedColumn<int>(
    'page_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _embeddingMeta = const VerificationMeta(
    'embedding',
  );
  @override
  late final GeneratedColumn<Uint8List> embedding = GeneratedColumn<Uint8List>(
    'embedding',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _embeddingModelMeta = const VerificationMeta(
    'embeddingModel',
  );
  @override
  late final GeneratedColumn<String> embeddingModel = GeneratedColumn<String>(
    'embedding_model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    docId,
    ordinal,
    pageNumber,
    content,
    embedding,
    embeddingModel,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'knowledge_chunks';
  @override
  VerificationContext validateIntegrity(
    Insertable<KnowledgeChunk> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('doc_id')) {
      context.handle(
        _docIdMeta,
        docId.isAcceptableOrUnknown(data['doc_id']!, _docIdMeta),
      );
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('page_number')) {
      context.handle(
        _pageNumberMeta,
        pageNumber.isAcceptableOrUnknown(data['page_number']!, _pageNumberMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('embedding')) {
      context.handle(
        _embeddingMeta,
        embedding.isAcceptableOrUnknown(data['embedding']!, _embeddingMeta),
      );
    }
    if (data.containsKey('embedding_model')) {
      context.handle(
        _embeddingModelMeta,
        embeddingModel.isAcceptableOrUnknown(
          data['embedding_model']!,
          _embeddingModelMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  KnowledgeChunk map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnowledgeChunk(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      docId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_id'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      pageNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_number'],
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      embedding: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}embedding'],
      ),
      embeddingModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}embedding_model'],
      ),
    );
  }

  @override
  $KnowledgeChunksTable createAlias(String alias) {
    return $KnowledgeChunksTable(attachedDatabase, alias);
  }
}

class KnowledgeChunk extends DataClass implements Insertable<KnowledgeChunk> {
  final String id;
  final String docId;
  final int ordinal;
  final int? pageNumber;
  final String content;
  final Uint8List? embedding;
  final String? embeddingModel;
  const KnowledgeChunk({
    required this.id,
    required this.docId,
    required this.ordinal,
    this.pageNumber,
    required this.content,
    this.embedding,
    this.embeddingModel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['doc_id'] = Variable<String>(docId);
    map['ordinal'] = Variable<int>(ordinal);
    if (!nullToAbsent || pageNumber != null) {
      map['page_number'] = Variable<int>(pageNumber);
    }
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || embedding != null) {
      map['embedding'] = Variable<Uint8List>(embedding);
    }
    if (!nullToAbsent || embeddingModel != null) {
      map['embedding_model'] = Variable<String>(embeddingModel);
    }
    return map;
  }

  KnowledgeChunksCompanion toCompanion(bool nullToAbsent) {
    return KnowledgeChunksCompanion(
      id: Value(id),
      docId: Value(docId),
      ordinal: Value(ordinal),
      pageNumber: pageNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(pageNumber),
      content: Value(content),
      embedding: embedding == null && nullToAbsent
          ? const Value.absent()
          : Value(embedding),
      embeddingModel: embeddingModel == null && nullToAbsent
          ? const Value.absent()
          : Value(embeddingModel),
    );
  }

  factory KnowledgeChunk.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnowledgeChunk(
      id: serializer.fromJson<String>(json['id']),
      docId: serializer.fromJson<String>(json['docId']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      pageNumber: serializer.fromJson<int?>(json['pageNumber']),
      content: serializer.fromJson<String>(json['content']),
      embedding: serializer.fromJson<Uint8List?>(json['embedding']),
      embeddingModel: serializer.fromJson<String?>(json['embeddingModel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'docId': serializer.toJson<String>(docId),
      'ordinal': serializer.toJson<int>(ordinal),
      'pageNumber': serializer.toJson<int?>(pageNumber),
      'content': serializer.toJson<String>(content),
      'embedding': serializer.toJson<Uint8List?>(embedding),
      'embeddingModel': serializer.toJson<String?>(embeddingModel),
    };
  }

  KnowledgeChunk copyWith({
    String? id,
    String? docId,
    int? ordinal,
    Value<int?> pageNumber = const Value.absent(),
    String? content,
    Value<Uint8List?> embedding = const Value.absent(),
    Value<String?> embeddingModel = const Value.absent(),
  }) => KnowledgeChunk(
    id: id ?? this.id,
    docId: docId ?? this.docId,
    ordinal: ordinal ?? this.ordinal,
    pageNumber: pageNumber.present ? pageNumber.value : this.pageNumber,
    content: content ?? this.content,
    embedding: embedding.present ? embedding.value : this.embedding,
    embeddingModel: embeddingModel.present
        ? embeddingModel.value
        : this.embeddingModel,
  );
  KnowledgeChunk copyWithCompanion(KnowledgeChunksCompanion data) {
    return KnowledgeChunk(
      id: data.id.present ? data.id.value : this.id,
      docId: data.docId.present ? data.docId.value : this.docId,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      pageNumber: data.pageNumber.present
          ? data.pageNumber.value
          : this.pageNumber,
      content: data.content.present ? data.content.value : this.content,
      embedding: data.embedding.present ? data.embedding.value : this.embedding,
      embeddingModel: data.embeddingModel.present
          ? data.embeddingModel.value
          : this.embeddingModel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgeChunk(')
          ..write('id: $id, ')
          ..write('docId: $docId, ')
          ..write('ordinal: $ordinal, ')
          ..write('pageNumber: $pageNumber, ')
          ..write('content: $content, ')
          ..write('embedding: $embedding, ')
          ..write('embeddingModel: $embeddingModel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    docId,
    ordinal,
    pageNumber,
    content,
    $driftBlobEquality.hash(embedding),
    embeddingModel,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnowledgeChunk &&
          other.id == this.id &&
          other.docId == this.docId &&
          other.ordinal == this.ordinal &&
          other.pageNumber == this.pageNumber &&
          other.content == this.content &&
          $driftBlobEquality.equals(other.embedding, this.embedding) &&
          other.embeddingModel == this.embeddingModel);
}

class KnowledgeChunksCompanion extends UpdateCompanion<KnowledgeChunk> {
  final Value<String> id;
  final Value<String> docId;
  final Value<int> ordinal;
  final Value<int?> pageNumber;
  final Value<String> content;
  final Value<Uint8List?> embedding;
  final Value<String?> embeddingModel;
  final Value<int> rowid;
  const KnowledgeChunksCompanion({
    this.id = const Value.absent(),
    this.docId = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.pageNumber = const Value.absent(),
    this.content = const Value.absent(),
    this.embedding = const Value.absent(),
    this.embeddingModel = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KnowledgeChunksCompanion.insert({
    required String id,
    required String docId,
    required int ordinal,
    this.pageNumber = const Value.absent(),
    required String content,
    this.embedding = const Value.absent(),
    this.embeddingModel = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       docId = Value(docId),
       ordinal = Value(ordinal),
       content = Value(content);
  static Insertable<KnowledgeChunk> custom({
    Expression<String>? id,
    Expression<String>? docId,
    Expression<int>? ordinal,
    Expression<int>? pageNumber,
    Expression<String>? content,
    Expression<Uint8List>? embedding,
    Expression<String>? embeddingModel,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (docId != null) 'doc_id': docId,
      if (ordinal != null) 'ordinal': ordinal,
      if (pageNumber != null) 'page_number': pageNumber,
      if (content != null) 'content': content,
      if (embedding != null) 'embedding': embedding,
      if (embeddingModel != null) 'embedding_model': embeddingModel,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KnowledgeChunksCompanion copyWith({
    Value<String>? id,
    Value<String>? docId,
    Value<int>? ordinal,
    Value<int?>? pageNumber,
    Value<String>? content,
    Value<Uint8List?>? embedding,
    Value<String?>? embeddingModel,
    Value<int>? rowid,
  }) {
    return KnowledgeChunksCompanion(
      id: id ?? this.id,
      docId: docId ?? this.docId,
      ordinal: ordinal ?? this.ordinal,
      pageNumber: pageNumber ?? this.pageNumber,
      content: content ?? this.content,
      embedding: embedding ?? this.embedding,
      embeddingModel: embeddingModel ?? this.embeddingModel,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (docId.present) {
      map['doc_id'] = Variable<String>(docId.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (pageNumber.present) {
      map['page_number'] = Variable<int>(pageNumber.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (embedding.present) {
      map['embedding'] = Variable<Uint8List>(embedding.value);
    }
    if (embeddingModel.present) {
      map['embedding_model'] = Variable<String>(embeddingModel.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgeChunksCompanion(')
          ..write('id: $id, ')
          ..write('docId: $docId, ')
          ..write('ordinal: $ordinal, ')
          ..write('pageNumber: $pageNumber, ')
          ..write('content: $content, ')
          ..write('embedding: $embedding, ')
          ..write('embeddingModel: $embeddingModel, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ChatsTable chats = $ChatsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $ModelsTable models = $ModelsTable(this);
  late final $MemoriesTable memories = $MemoriesTable(this);
  late final $KnowledgeDocsTable knowledgeDocs = $KnowledgeDocsTable(this);
  late final $KnowledgeChunksTable knowledgeChunks = $KnowledgeChunksTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    chats,
    messages,
    models,
    memories,
    knowledgeDocs,
    knowledgeChunks,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'chats',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'knowledge_docs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('knowledge_chunks', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ChatsTableCreateCompanionBuilder =
    ChatsCompanion Function({
      required String id,
      required String title,
      Value<String?> modelId,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<bool> pinned,
      Value<String?> folder,
      Value<String> tags,
      Value<String> overridesJson,
      Value<int> rowid,
    });
typedef $$ChatsTableUpdateCompanionBuilder =
    ChatsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> modelId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> pinned,
      Value<String?> folder,
      Value<String> tags,
      Value<String> overridesJson,
      Value<int> rowid,
    });

final class $$ChatsTableReferences
    extends BaseReferences<_$AppDatabase, $ChatsTable, Chat> {
  $$ChatsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MessagesTable, List<Message>> _messagesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.messages,
    aliasName: 'chats__id__messages__chat_id',
  );

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.chatId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ChatsTableFilterComposer extends Composer<_$AppDatabase, $ChatsTable> {
  $$ChatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folder => $composableBuilder(
    column: $table.folder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get overridesJson => $composableBuilder(
    column: $table.overridesJson,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> messagesRefs(
    Expression<bool> Function($$MessagesTableFilterComposer f) f,
  ) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.chatId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChatsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatsTable> {
  $$ChatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folder => $composableBuilder(
    column: $table.folder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get overridesJson => $composableBuilder(
    column: $table.overridesJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatsTable> {
  $$ChatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<String> get folder =>
      $composableBuilder(column: $table.folder, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get overridesJson => $composableBuilder(
    column: $table.overridesJson,
    builder: (column) => column,
  );

  Expression<T> messagesRefs<T extends Object>(
    Expression<T> Function($$MessagesTableAnnotationComposer a) f,
  ) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.chatId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChatsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatsTable,
          Chat,
          $$ChatsTableFilterComposer,
          $$ChatsTableOrderingComposer,
          $$ChatsTableAnnotationComposer,
          $$ChatsTableCreateCompanionBuilder,
          $$ChatsTableUpdateCompanionBuilder,
          (Chat, $$ChatsTableReferences),
          Chat,
          PrefetchHooks Function({bool messagesRefs})
        > {
  $$ChatsTableTableManager(_$AppDatabase db, $ChatsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<String?> folder = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<String> overridesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatsCompanion(
                id: id,
                title: title,
                modelId: modelId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                pinned: pinned,
                folder: folder,
                tags: tags,
                overridesJson: overridesJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> modelId = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<bool> pinned = const Value.absent(),
                Value<String?> folder = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<String> overridesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatsCompanion.insert(
                id: id,
                title: title,
                modelId: modelId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                pinned: pinned,
                folder: folder,
                tags: tags,
                overridesJson: overridesJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatsTable, Chat>(table),
                  $$ChatsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (messagesRefs) db.messages],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (messagesRefs)
                    await $_getPrefetchedData<Chat, $ChatsTable, Message>(
                      currentTable: table,
                      referencedTable: $$ChatsTableReferences
                          ._messagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ChatsTableReferences(db, table, p0).messagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.chatId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ChatsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatsTable,
      Chat,
      $$ChatsTableFilterComposer,
      $$ChatsTableOrderingComposer,
      $$ChatsTableAnnotationComposer,
      $$ChatsTableCreateCompanionBuilder,
      $$ChatsTableUpdateCompanionBuilder,
      (Chat, $$ChatsTableReferences),
      Chat,
      PrefetchHooks Function({bool messagesRefs})
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      required String id,
      required String chatId,
      required String role,
      required String content,
      Value<String?> reasoning,
      Value<String> status,
      Value<String> sourcesJson,
      Value<String> attachmentsJson,
      Value<String?> modelId,
      Value<String?> parentId,
      Value<String?> runJson,
      required DateTime timestamp,
      Value<int?> tokenCount,
      required int sequence,
      Value<int> rowid,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<String> id,
      Value<String> chatId,
      Value<String> role,
      Value<String> content,
      Value<String?> reasoning,
      Value<String> status,
      Value<String> sourcesJson,
      Value<String> attachmentsJson,
      Value<String?> modelId,
      Value<String?> parentId,
      Value<String?> runJson,
      Value<DateTime> timestamp,
      Value<int?> tokenCount,
      Value<int> sequence,
      Value<int> rowid,
    });

final class $$MessagesTableReferences
    extends BaseReferences<_$AppDatabase, $MessagesTable, Message> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ChatsTable _chatIdTable(_$AppDatabase db) =>
      db.chats.createAlias('messages__chat_id__chats__id');

  $$ChatsTableProcessedTableManager get chatId {
    final $_column = $_itemColumn<String>('chat_id')!;

    final manager = $$ChatsTableTableManager(
      $_db,
      $_db.chats,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_chatIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reasoning => $composableBuilder(
    column: $table.reasoning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcesJson => $composableBuilder(
    column: $table.sourcesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get runJson => $composableBuilder(
    column: $table.runJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tokenCount => $composableBuilder(
    column: $table.tokenCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  $$ChatsTableFilterComposer get chatId {
    final $$ChatsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.chats,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatsTableFilterComposer(
            $db: $db,
            $table: $db.chats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasoning => $composableBuilder(
    column: $table.reasoning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcesJson => $composableBuilder(
    column: $table.sourcesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get runJson => $composableBuilder(
    column: $table.runJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tokenCount => $composableBuilder(
    column: $table.tokenCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  $$ChatsTableOrderingComposer get chatId {
    final $$ChatsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.chats,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatsTableOrderingComposer(
            $db: $db,
            $table: $db.chats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get reasoning =>
      $composableBuilder(column: $table.reasoning, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get sourcesJson => $composableBuilder(
    column: $table.sourcesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get runJson =>
      $composableBuilder(column: $table.runJson, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get tokenCount => $composableBuilder(
    column: $table.tokenCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  $$ChatsTableAnnotationComposer get chatId {
    final $$ChatsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.chats,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatsTableAnnotationComposer(
            $db: $db,
            $table: $db.chats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, $$MessagesTableReferences),
          Message,
          PrefetchHooks Function({bool chatId})
        > {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> chatId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> reasoning = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> sourcesJson = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> runJson = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<int?> tokenCount = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                chatId: chatId,
                role: role,
                content: content,
                reasoning: reasoning,
                status: status,
                sourcesJson: sourcesJson,
                attachmentsJson: attachmentsJson,
                modelId: modelId,
                parentId: parentId,
                runJson: runJson,
                timestamp: timestamp,
                tokenCount: tokenCount,
                sequence: sequence,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String chatId,
                required String role,
                required String content,
                Value<String?> reasoning = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> sourcesJson = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> runJson = const Value.absent(),
                required DateTime timestamp,
                Value<int?> tokenCount = const Value.absent(),
                required int sequence,
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                chatId: chatId,
                role: role,
                content: content,
                reasoning: reasoning,
                status: status,
                sourcesJson: sourcesJson,
                attachmentsJson: attachmentsJson,
                modelId: modelId,
                parentId: parentId,
                runJson: runJson,
                timestamp: timestamp,
                tokenCount: tokenCount,
                sequence: sequence,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MessagesTable, Message>(table),
                  $$MessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({chatId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (chatId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.chatId,
                                referencedTable: $$MessagesTableReferences
                                    ._chatIdTable(db),
                                referencedColumn: $$MessagesTableReferences
                                    ._chatIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, $$MessagesTableReferences),
      Message,
      PrefetchHooks Function({bool chatId})
    >;
typedef $$ModelsTableCreateCompanionBuilder =
    ModelsCompanion Function({
      required String id,
      required String displayName,
      required String fileName,
      Value<String?> downloadUrl,
      Value<String?> sha256,
      Value<String> license,
      required int sizeBytes,
      Value<int?> parameterCountB,
      required String family,
      required String quantization,
      Value<bool> isDownloaded,
      Value<String?> localPath,
      Value<DateTime?> downloadedAt,
      Value<int> rowid,
    });
typedef $$ModelsTableUpdateCompanionBuilder =
    ModelsCompanion Function({
      Value<String> id,
      Value<String> displayName,
      Value<String> fileName,
      Value<String?> downloadUrl,
      Value<String?> sha256,
      Value<String> license,
      Value<int> sizeBytes,
      Value<int?> parameterCountB,
      Value<String> family,
      Value<String> quantization,
      Value<bool> isDownloaded,
      Value<String?> localPath,
      Value<DateTime?> downloadedAt,
      Value<int> rowid,
    });

class $$ModelsTableFilterComposer
    extends Composer<_$AppDatabase, $ModelsTable> {
  $$ModelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get downloadUrl => $composableBuilder(
    column: $table.downloadUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get license => $composableBuilder(
    column: $table.license,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parameterCountB => $composableBuilder(
    column: $table.parameterCountB,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get family => $composableBuilder(
    column: $table.family,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quantization => $composableBuilder(
    column: $table.quantization,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDownloaded => $composableBuilder(
    column: $table.isDownloaded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ModelsTableOrderingComposer
    extends Composer<_$AppDatabase, $ModelsTable> {
  $$ModelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get downloadUrl => $composableBuilder(
    column: $table.downloadUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get license => $composableBuilder(
    column: $table.license,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parameterCountB => $composableBuilder(
    column: $table.parameterCountB,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get family => $composableBuilder(
    column: $table.family,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quantization => $composableBuilder(
    column: $table.quantization,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDownloaded => $composableBuilder(
    column: $table.isDownloaded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ModelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ModelsTable> {
  $$ModelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get downloadUrl => $composableBuilder(
    column: $table.downloadUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get license =>
      $composableBuilder(column: $table.license, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get parameterCountB => $composableBuilder(
    column: $table.parameterCountB,
    builder: (column) => column,
  );

  GeneratedColumn<String> get family =>
      $composableBuilder(column: $table.family, builder: (column) => column);

  GeneratedColumn<String> get quantization => $composableBuilder(
    column: $table.quantization,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDownloaded => $composableBuilder(
    column: $table.isDownloaded,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => column,
  );
}

class $$ModelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ModelsTable,
          Model,
          $$ModelsTableFilterComposer,
          $$ModelsTableOrderingComposer,
          $$ModelsTableAnnotationComposer,
          $$ModelsTableCreateCompanionBuilder,
          $$ModelsTableUpdateCompanionBuilder,
          (Model, BaseReferences<_$AppDatabase, $ModelsTable, Model>),
          Model,
          PrefetchHooks Function()
        > {
  $$ModelsTableTableManager(_$AppDatabase db, $ModelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ModelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ModelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ModelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String?> downloadUrl = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<String> license = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<int?> parameterCountB = const Value.absent(),
                Value<String> family = const Value.absent(),
                Value<String> quantization = const Value.absent(),
                Value<bool> isDownloaded = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<DateTime?> downloadedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModelsCompanion(
                id: id,
                displayName: displayName,
                fileName: fileName,
                downloadUrl: downloadUrl,
                sha256: sha256,
                license: license,
                sizeBytes: sizeBytes,
                parameterCountB: parameterCountB,
                family: family,
                quantization: quantization,
                isDownloaded: isDownloaded,
                localPath: localPath,
                downloadedAt: downloadedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String displayName,
                required String fileName,
                Value<String?> downloadUrl = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<String> license = const Value.absent(),
                required int sizeBytes,
                Value<int?> parameterCountB = const Value.absent(),
                required String family,
                required String quantization,
                Value<bool> isDownloaded = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<DateTime?> downloadedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModelsCompanion.insert(
                id: id,
                displayName: displayName,
                fileName: fileName,
                downloadUrl: downloadUrl,
                sha256: sha256,
                license: license,
                sizeBytes: sizeBytes,
                parameterCountB: parameterCountB,
                family: family,
                quantization: quantization,
                isDownloaded: isDownloaded,
                localPath: localPath,
                downloadedAt: downloadedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ModelsTable, Model>(table),
                  BaseReferences<_$AppDatabase, $ModelsTable, Model>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ModelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ModelsTable,
      Model,
      $$ModelsTableFilterComposer,
      $$ModelsTableOrderingComposer,
      $$ModelsTableAnnotationComposer,
      $$ModelsTableCreateCompanionBuilder,
      $$ModelsTableUpdateCompanionBuilder,
      (Model, BaseReferences<_$AppDatabase, $ModelsTable, Model>),
      Model,
      PrefetchHooks Function()
    >;
typedef $$MemoriesTableCreateCompanionBuilder =
    MemoriesCompanion Function({
      required String id,
      required String content,
      Value<String?> sourceChatId,
      Value<String?> sourceMessageId,
      Value<bool> pinned,
      Value<DateTime?> expiresAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$MemoriesTableUpdateCompanionBuilder =
    MemoriesCompanion Function({
      Value<String> id,
      Value<String> content,
      Value<String?> sourceChatId,
      Value<String?> sourceMessageId,
      Value<bool> pinned,
      Value<DateTime?> expiresAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$MemoriesTableFilterComposer
    extends Composer<_$AppDatabase, $MemoriesTable> {
  $$MemoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceChatId => $composableBuilder(
    column: $table.sourceChatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MemoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $MemoriesTable> {
  $$MemoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceChatId => $composableBuilder(
    column: $table.sourceChatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MemoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MemoriesTable> {
  $$MemoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get sourceChatId => $composableBuilder(
    column: $table.sourceChatId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MemoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MemoriesTable,
          Memory,
          $$MemoriesTableFilterComposer,
          $$MemoriesTableOrderingComposer,
          $$MemoriesTableAnnotationComposer,
          $$MemoriesTableCreateCompanionBuilder,
          $$MemoriesTableUpdateCompanionBuilder,
          (Memory, BaseReferences<_$AppDatabase, $MemoriesTable, Memory>),
          Memory,
          PrefetchHooks Function()
        > {
  $$MemoriesTableTableManager(_$AppDatabase db, $MemoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> sourceChatId = const Value.absent(),
                Value<String?> sourceMessageId = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoriesCompanion(
                id: id,
                content: content,
                sourceChatId: sourceChatId,
                sourceMessageId: sourceMessageId,
                pinned: pinned,
                expiresAt: expiresAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String content,
                Value<String?> sourceChatId = const Value.absent(),
                Value<String?> sourceMessageId = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => MemoriesCompanion.insert(
                id: id,
                content: content,
                sourceChatId: sourceChatId,
                sourceMessageId: sourceMessageId,
                pinned: pinned,
                expiresAt: expiresAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MemoriesTable, Memory>(table),
                  BaseReferences<_$AppDatabase, $MemoriesTable, Memory>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MemoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MemoriesTable,
      Memory,
      $$MemoriesTableFilterComposer,
      $$MemoriesTableOrderingComposer,
      $$MemoriesTableAnnotationComposer,
      $$MemoriesTableCreateCompanionBuilder,
      $$MemoriesTableUpdateCompanionBuilder,
      (Memory, BaseReferences<_$AppDatabase, $MemoriesTable, Memory>),
      Memory,
      PrefetchHooks Function()
    >;
typedef $$KnowledgeDocsTableCreateCompanionBuilder =
    KnowledgeDocsCompanion Function({
      required String id,
      required String collection,
      required String name,
      Value<String> mime,
      Value<int> sizeBytes,
      Value<int> chars,
      Value<int> chunkCount,
      required DateTime addedAt,
      Value<String?> contentHash,
      Value<String?> extractionFormat,
      Value<String?> extractionWarning,
      Value<String?> originalFile,
      Value<String?> previousVersionId,
      Value<bool> active,
      Value<int> rowid,
    });
typedef $$KnowledgeDocsTableUpdateCompanionBuilder =
    KnowledgeDocsCompanion Function({
      Value<String> id,
      Value<String> collection,
      Value<String> name,
      Value<String> mime,
      Value<int> sizeBytes,
      Value<int> chars,
      Value<int> chunkCount,
      Value<DateTime> addedAt,
      Value<String?> contentHash,
      Value<String?> extractionFormat,
      Value<String?> extractionWarning,
      Value<String?> originalFile,
      Value<String?> previousVersionId,
      Value<bool> active,
      Value<int> rowid,
    });

final class $$KnowledgeDocsTableReferences
    extends BaseReferences<_$AppDatabase, $KnowledgeDocsTable, KnowledgeDoc> {
  $$KnowledgeDocsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$KnowledgeChunksTable, List<KnowledgeChunk>>
  _knowledgeChunksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.knowledgeChunks,
    aliasName: 'knowledge_docs__id__knowledge_chunks__doc_id',
  );

  $$KnowledgeChunksTableProcessedTableManager get knowledgeChunksRefs {
    final manager = $$KnowledgeChunksTableTableManager(
      $_db,
      $_db.knowledgeChunks,
    ).filter((f) => f.docId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _knowledgeChunksRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$KnowledgeDocsTableFilterComposer
    extends Composer<_$AppDatabase, $KnowledgeDocsTable> {
  $$KnowledgeDocsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chars => $composableBuilder(
    column: $table.chars,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chunkCount => $composableBuilder(
    column: $table.chunkCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extractionFormat => $composableBuilder(
    column: $table.extractionFormat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extractionWarning => $composableBuilder(
    column: $table.extractionWarning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalFile => $composableBuilder(
    column: $table.originalFile,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previousVersionId => $composableBuilder(
    column: $table.previousVersionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> knowledgeChunksRefs(
    Expression<bool> Function($$KnowledgeChunksTableFilterComposer f) f,
  ) {
    final $$KnowledgeChunksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.knowledgeChunks,
      getReferencedColumn: (t) => t.docId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KnowledgeChunksTableFilterComposer(
            $db: $db,
            $table: $db.knowledgeChunks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$KnowledgeDocsTableOrderingComposer
    extends Composer<_$AppDatabase, $KnowledgeDocsTable> {
  $$KnowledgeDocsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chars => $composableBuilder(
    column: $table.chars,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chunkCount => $composableBuilder(
    column: $table.chunkCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extractionFormat => $composableBuilder(
    column: $table.extractionFormat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extractionWarning => $composableBuilder(
    column: $table.extractionWarning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalFile => $composableBuilder(
    column: $table.originalFile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previousVersionId => $composableBuilder(
    column: $table.previousVersionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KnowledgeDocsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KnowledgeDocsTable> {
  $$KnowledgeDocsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get chars =>
      $composableBuilder(column: $table.chars, builder: (column) => column);

  GeneratedColumn<int> get chunkCount => $composableBuilder(
    column: $table.chunkCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get extractionFormat => $composableBuilder(
    column: $table.extractionFormat,
    builder: (column) => column,
  );

  GeneratedColumn<String> get extractionWarning => $composableBuilder(
    column: $table.extractionWarning,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originalFile => $composableBuilder(
    column: $table.originalFile,
    builder: (column) => column,
  );

  GeneratedColumn<String> get previousVersionId => $composableBuilder(
    column: $table.previousVersionId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  Expression<T> knowledgeChunksRefs<T extends Object>(
    Expression<T> Function($$KnowledgeChunksTableAnnotationComposer a) f,
  ) {
    final $$KnowledgeChunksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.knowledgeChunks,
      getReferencedColumn: (t) => t.docId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KnowledgeChunksTableAnnotationComposer(
            $db: $db,
            $table: $db.knowledgeChunks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$KnowledgeDocsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KnowledgeDocsTable,
          KnowledgeDoc,
          $$KnowledgeDocsTableFilterComposer,
          $$KnowledgeDocsTableOrderingComposer,
          $$KnowledgeDocsTableAnnotationComposer,
          $$KnowledgeDocsTableCreateCompanionBuilder,
          $$KnowledgeDocsTableUpdateCompanionBuilder,
          (KnowledgeDoc, $$KnowledgeDocsTableReferences),
          KnowledgeDoc,
          PrefetchHooks Function({bool knowledgeChunksRefs})
        > {
  $$KnowledgeDocsTableTableManager(_$AppDatabase db, $KnowledgeDocsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KnowledgeDocsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KnowledgeDocsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KnowledgeDocsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> collection = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> mime = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<int> chars = const Value.absent(),
                Value<int> chunkCount = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                Value<String?> extractionFormat = const Value.absent(),
                Value<String?> extractionWarning = const Value.absent(),
                Value<String?> originalFile = const Value.absent(),
                Value<String?> previousVersionId = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnowledgeDocsCompanion(
                id: id,
                collection: collection,
                name: name,
                mime: mime,
                sizeBytes: sizeBytes,
                chars: chars,
                chunkCount: chunkCount,
                addedAt: addedAt,
                contentHash: contentHash,
                extractionFormat: extractionFormat,
                extractionWarning: extractionWarning,
                originalFile: originalFile,
                previousVersionId: previousVersionId,
                active: active,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String collection,
                required String name,
                Value<String> mime = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<int> chars = const Value.absent(),
                Value<int> chunkCount = const Value.absent(),
                required DateTime addedAt,
                Value<String?> contentHash = const Value.absent(),
                Value<String?> extractionFormat = const Value.absent(),
                Value<String?> extractionWarning = const Value.absent(),
                Value<String?> originalFile = const Value.absent(),
                Value<String?> previousVersionId = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnowledgeDocsCompanion.insert(
                id: id,
                collection: collection,
                name: name,
                mime: mime,
                sizeBytes: sizeBytes,
                chars: chars,
                chunkCount: chunkCount,
                addedAt: addedAt,
                contentHash: contentHash,
                extractionFormat: extractionFormat,
                extractionWarning: extractionWarning,
                originalFile: originalFile,
                previousVersionId: previousVersionId,
                active: active,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KnowledgeDocsTable, KnowledgeDoc>(table),
                  $$KnowledgeDocsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({knowledgeChunksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (knowledgeChunksRefs) db.knowledgeChunks,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (knowledgeChunksRefs)
                    await $_getPrefetchedData<
                      KnowledgeDoc,
                      $KnowledgeDocsTable,
                      KnowledgeChunk
                    >(
                      currentTable: table,
                      referencedTable: $$KnowledgeDocsTableReferences
                          ._knowledgeChunksRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$KnowledgeDocsTableReferences(
                            db,
                            table,
                            p0,
                          ).knowledgeChunksRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.docId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$KnowledgeDocsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KnowledgeDocsTable,
      KnowledgeDoc,
      $$KnowledgeDocsTableFilterComposer,
      $$KnowledgeDocsTableOrderingComposer,
      $$KnowledgeDocsTableAnnotationComposer,
      $$KnowledgeDocsTableCreateCompanionBuilder,
      $$KnowledgeDocsTableUpdateCompanionBuilder,
      (KnowledgeDoc, $$KnowledgeDocsTableReferences),
      KnowledgeDoc,
      PrefetchHooks Function({bool knowledgeChunksRefs})
    >;
typedef $$KnowledgeChunksTableCreateCompanionBuilder =
    KnowledgeChunksCompanion Function({
      required String id,
      required String docId,
      required int ordinal,
      Value<int?> pageNumber,
      required String content,
      Value<Uint8List?> embedding,
      Value<String?> embeddingModel,
      Value<int> rowid,
    });
typedef $$KnowledgeChunksTableUpdateCompanionBuilder =
    KnowledgeChunksCompanion Function({
      Value<String> id,
      Value<String> docId,
      Value<int> ordinal,
      Value<int?> pageNumber,
      Value<String> content,
      Value<Uint8List?> embedding,
      Value<String?> embeddingModel,
      Value<int> rowid,
    });

final class $$KnowledgeChunksTableReferences
    extends
        BaseReferences<_$AppDatabase, $KnowledgeChunksTable, KnowledgeChunk> {
  $$KnowledgeChunksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $KnowledgeDocsTable _docIdTable(_$AppDatabase db) => db.knowledgeDocs
      .createAlias('knowledge_chunks__doc_id__knowledge_docs__id');

  $$KnowledgeDocsTableProcessedTableManager get docId {
    final $_column = $_itemColumn<String>('doc_id')!;

    final manager = $$KnowledgeDocsTableTableManager(
      $_db,
      $_db.knowledgeDocs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_docIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$KnowledgeChunksTableFilterComposer
    extends Composer<_$AppDatabase, $KnowledgeChunksTable> {
  $$KnowledgeChunksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageNumber => $composableBuilder(
    column: $table.pageNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get embedding => $composableBuilder(
    column: $table.embedding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get embeddingModel => $composableBuilder(
    column: $table.embeddingModel,
    builder: (column) => ColumnFilters(column),
  );

  $$KnowledgeDocsTableFilterComposer get docId {
    final $$KnowledgeDocsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.knowledgeDocs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KnowledgeDocsTableFilterComposer(
            $db: $db,
            $table: $db.knowledgeDocs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$KnowledgeChunksTableOrderingComposer
    extends Composer<_$AppDatabase, $KnowledgeChunksTable> {
  $$KnowledgeChunksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageNumber => $composableBuilder(
    column: $table.pageNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get embedding => $composableBuilder(
    column: $table.embedding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get embeddingModel => $composableBuilder(
    column: $table.embeddingModel,
    builder: (column) => ColumnOrderings(column),
  );

  $$KnowledgeDocsTableOrderingComposer get docId {
    final $$KnowledgeDocsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.knowledgeDocs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KnowledgeDocsTableOrderingComposer(
            $db: $db,
            $table: $db.knowledgeDocs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$KnowledgeChunksTableAnnotationComposer
    extends Composer<_$AppDatabase, $KnowledgeChunksTable> {
  $$KnowledgeChunksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<int> get pageNumber => $composableBuilder(
    column: $table.pageNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<Uint8List> get embedding =>
      $composableBuilder(column: $table.embedding, builder: (column) => column);

  GeneratedColumn<String> get embeddingModel => $composableBuilder(
    column: $table.embeddingModel,
    builder: (column) => column,
  );

  $$KnowledgeDocsTableAnnotationComposer get docId {
    final $$KnowledgeDocsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.knowledgeDocs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KnowledgeDocsTableAnnotationComposer(
            $db: $db,
            $table: $db.knowledgeDocs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$KnowledgeChunksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KnowledgeChunksTable,
          KnowledgeChunk,
          $$KnowledgeChunksTableFilterComposer,
          $$KnowledgeChunksTableOrderingComposer,
          $$KnowledgeChunksTableAnnotationComposer,
          $$KnowledgeChunksTableCreateCompanionBuilder,
          $$KnowledgeChunksTableUpdateCompanionBuilder,
          (KnowledgeChunk, $$KnowledgeChunksTableReferences),
          KnowledgeChunk,
          PrefetchHooks Function({bool docId})
        > {
  $$KnowledgeChunksTableTableManager(
    _$AppDatabase db,
    $KnowledgeChunksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KnowledgeChunksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KnowledgeChunksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KnowledgeChunksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> docId = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<int?> pageNumber = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<Uint8List?> embedding = const Value.absent(),
                Value<String?> embeddingModel = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnowledgeChunksCompanion(
                id: id,
                docId: docId,
                ordinal: ordinal,
                pageNumber: pageNumber,
                content: content,
                embedding: embedding,
                embeddingModel: embeddingModel,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String docId,
                required int ordinal,
                Value<int?> pageNumber = const Value.absent(),
                required String content,
                Value<Uint8List?> embedding = const Value.absent(),
                Value<String?> embeddingModel = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnowledgeChunksCompanion.insert(
                id: id,
                docId: docId,
                ordinal: ordinal,
                pageNumber: pageNumber,
                content: content,
                embedding: embedding,
                embeddingModel: embeddingModel,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KnowledgeChunksTable, KnowledgeChunk>(table),
                  $$KnowledgeChunksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({docId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (docId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.docId,
                                referencedTable:
                                    $$KnowledgeChunksTableReferences
                                        ._docIdTable(db),
                                referencedColumn:
                                    $$KnowledgeChunksTableReferences
                                        ._docIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$KnowledgeChunksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KnowledgeChunksTable,
      KnowledgeChunk,
      $$KnowledgeChunksTableFilterComposer,
      $$KnowledgeChunksTableOrderingComposer,
      $$KnowledgeChunksTableAnnotationComposer,
      $$KnowledgeChunksTableCreateCompanionBuilder,
      $$KnowledgeChunksTableUpdateCompanionBuilder,
      (KnowledgeChunk, $$KnowledgeChunksTableReferences),
      KnowledgeChunk,
      PrefetchHooks Function({bool docId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ChatsTableTableManager get chats =>
      $$ChatsTableTableManager(_db, _db.chats);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$ModelsTableTableManager get models =>
      $$ModelsTableTableManager(_db, _db.models);
  $$MemoriesTableTableManager get memories =>
      $$MemoriesTableTableManager(_db, _db.memories);
  $$KnowledgeDocsTableTableManager get knowledgeDocs =>
      $$KnowledgeDocsTableTableManager(_db, _db.knowledgeDocs);
  $$KnowledgeChunksTableTableManager get knowledgeChunks =>
      $$KnowledgeChunksTableTableManager(_db, _db.knowledgeChunks);
}
