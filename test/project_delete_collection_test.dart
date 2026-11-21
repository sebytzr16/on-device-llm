import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/domain/conversation_workspace.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/presets/domain/preset.dart';
import 'package:ondevice_llm/features/presets/presentation/providers/presets_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_test.dart' show TestEngine, TestModels, TestSettings;

class _Paths extends PathProviderPlatform {
  final String support;
  _Paths(this.support);
  @override
  Future<String?> getApplicationSupportPath() async => support;
  @override
  Future<String?> getApplicationDocumentsPath() async => support;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform previousPaths;
  late AppDatabase db;
  late ProviderContainer container;
  final date = DateTime(2026, 1, 1);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('project-delete-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(TestEngine()),
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    PathProviderPlatform.instance = previousPaths;
    await root.delete(recursive: true);
  });

  test(
    'deleting a project keeps a collection one of its chats still overrides',
    () async {
      final workspace = container.read(conversationWorkspaceProvider.notifier);
      await workspace.ready;
      await workspace.saveProject(name: 'Physics', collection: 'Physics');
      final project = container
          .read(conversationWorkspaceProvider)
          .projects
          .single;
      await db
          .into(db.chats)
          .insert(
            ChatsCompanion.insert(
              id: 'c1',
              title: 'Physics chat',
              createdAt: date,
              updatedAt: date,
              // A chat keeps other override keys beside knowledgeCollection — the
              // user's own settings and the keys `setChatOverrides` preserves —
              // so the collection is not the encoded object's only entry.
              overridesJson: Value(
                jsonEncode({
                  'knowledgeCollection': 'Physics',
                  'temperature': 0.4,
                  '_fileEditsAllowed:m1': true,
                }),
              ),
            ),
          );
      await db.insertKnowledgeDoc(
        KnowledgeDocsCompanion.insert(
          id: 'doc1',
          collection: 'Physics',
          name: 'notes.txt',
          addedAt: date,
        ),
        const [],
      );

      await container.read(chatProvider.notifier).deleteProject(project.id);

      expect(
        await db.knowledgeDocsIn('Physics'),
        hasLength(1),
        reason: 'chat c1 still resolves to that collection (review 2026-11-20)',
      );
      expect(await db.getChat('c1'), isNotNull, reason: 'chats stay');
    },
  );

  test('deleting a project keeps a collection a preset still names', () async {
    final workspace = container.read(conversationWorkspaceProvider.notifier);
    await workspace.ready;
    await workspace.saveProject(name: 'Physics', collection: 'Physics');
    final project = container
        .read(conversationWorkspaceProvider)
        .projects
        .single;
    final presets = container.read(presetsProvider.notifier);
    await presets.ready;
    await presets.create(
      const Preset(
        id: '',
        name: 'Physics tutor',
        emoji: '🎓',
        systemPrompt: '',
        // A user preset carries generic setting overrides, so it can name a
        // knowledge collection like a chat does (review 2026-11-20).
        overrides: {'knowledgeCollection': 'Physics'},
      ),
    );
    await db.insertKnowledgeDoc(
      KnowledgeDocsCompanion.insert(
        id: 'doc1',
        collection: 'Physics',
        name: 'notes.txt',
        addedAt: date,
      ),
      const [],
    );

    await container.read(chatProvider.notifier).deleteProject(project.id);

    expect(
      await db.knowledgeDocsIn('Physics'),
      hasLength(1),
      reason: 'a preset still resolves to that collection',
    );
  });

  test(
    'deleting a project keeps a collection a model profile still names',
    () async {
      final workspace = container.read(conversationWorkspaceProvider.notifier);
      await workspace.ready;
      await workspace.saveProject(name: 'Physics', collection: 'Physics');
      final project = container
          .read(conversationWorkspaceProvider)
          .projects
          .single;
      final profiles = container.read(modelProfilesProvider.notifier);
      await profiles.ready;
      await profiles.set('m1', {'knowledgeCollection': 'Physics'});
      await db.insertKnowledgeDoc(
        KnowledgeDocsCompanion.insert(
          id: 'doc1',
          collection: 'Physics',
          name: 'notes.txt',
          addedAt: date,
        ),
        const [],
      );

      await container.read(chatProvider.notifier).deleteProject(project.id);

      expect(
        await db.knowledgeDocsIn('Physics'),
        hasLength(1),
        reason: 'a model profile still resolves to that collection',
      );
    },
  );
}
