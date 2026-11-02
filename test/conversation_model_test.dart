import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/voice/conversation_model.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

List<ModelInfo> _catalog(Set<String> downloaded) => [
  for (final m in bundledCatalog)
    m.copyWith(isDownloaded: downloaded.contains(m.id)),
];

void main() {
  test('Qwen3.5 0.8B answers by default', () {
    final catalog = _catalog({'gemma4-e2b-qat', 'qwen35-0.8b-q8_0'});
    expect(
      ConversationModel.pick('', catalog, loadedId: 'gemma4-e2b-qat')?.id,
      'qwen35-0.8b-q8_0',
    );
    expect(ConversationModel.missing('', catalog), isNull);
  });

  test('any downloaded model can be picked, the 0.8B listed first', () {
    // Owner 2026-11-01: a model picker for Conversation (LFM3 included).
    final catalog = _catalog({'gemma4-e2b-qat', 'qwen35-0.8b-q8_0'});
    expect(
      ConversationModel.pick('gemma4-e2b-qat', catalog)?.id,
      'gemma4-e2b-qat',
    );
    expect(ConversationModel.choices(catalog).map((m) => m.id), [
      'qwen35-0.8b-q8_0',
      'gemma4-e2b-qat',
    ]);
    // A pick that is no longer downloaded falls back to the 0.8B.
    expect(
      ConversationModel.pick('qwen35-9b-q4km', catalog)?.id,
      'qwen35-0.8b-q8_0',
    );
  });

  test('without the 0.8B another model answers and says so', () {
    final catalog = _catalog({'qwen35-2b-iq4nl', 'gemma4-e2b-qat'});
    expect(
      ConversationModel.pick('', catalog, loadedId: 'gemma4-e2b-qat')?.id,
      'gemma4-e2b-qat',
    );
    expect(ConversationModel.pick('', catalog)?.id, 'qwen35-2b-iq4nl');
    expect(ConversationModel.missing('', catalog)?.id, 'qwen35-0.8b-q8_0');
    // A model picked on purpose needs no notice.
    expect(ConversationModel.missing('gemma4-e2b-qat', catalog), isNull);
    expect(ConversationModel.pick('', _catalog({})), isNull);
  });

  test('the choice is kept in the settings', () {
    const s = InferenceSettings(conversationModelId: 'gemma4-e2b-qat');
    expect(
      InferenceSettings.fromJson(s.toJson()).conversationModelId,
      'gemma4-e2b-qat',
    );
    expect(const InferenceSettings().conversationModelId, '');
  });

  test('a remote connection answers unless a phone model was picked', () {
    // Phone test, 2026-10-18: a remote model is used in Conversation too.
    const remote = InferenceSettings(
      remoteEnabled: true,
      remoteProfiles: [
        RemoteProfile(
          id: 'laptop',
          name: 'LM Studio',
          providerId: 'lmstudio',
          baseUrl: 'http://10.0.0.9:1234/v1',
          model: 'gemma-4-e4b',
        ),
      ],
      remoteProfileId: 'laptop',
    );
    expect(ConversationModel.usesRemote('', remote), isTrue);
    expect(ConversationModel.usesRemote('gemma4-e2b-qat', remote), isFalse);
    expect(
      ConversationModel.usesRemote(ConversationModel.defaultId, remote),
      isFalse,
    );
    expect(
      ConversationModel.usesRemote('', const InferenceSettings()),
      isFalse,
    );
    expect(ConversationModel.remoteName(remote), 'LM Studio · gemma-4-e4b');
  });
}
