import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../../inference/engine/llama_engine.dart';
import '../../inference/engine/text_engine.dart';
import '../models/domain/entities/model_info.dart';
import '../settings/domain/entities/inference_settings.dart';
import '../voice/sherpa_voice.dart';
import 'knowledge_media.dart';

/// Only local installed capabilities may derive facts for the library.
/// Missing capabilities leave an explicit import warning.
abstract final class KnowledgeGrounding {
  static Future<String?> transcript(
    File segment,
    SherpaVoice voice, {
    String language = '',
    bool Function()? cancelled,
  }) async {
    if (cancelled?.call() == true) return null;
    final samples = await KnowledgeMedia.transcriptionSamples(segment);
    final text = <String>[];
    // sherpa's Whisper decoder discards audio beyond its ~30 second
    // window. Embedding segments stay 60 seconds; ASR uses overlapping
    // 20 second windows so facts late in each minute are retained.
    const window = 20 * 16000, stride = 19 * 16000;
    for (var start = 0; start < samples.length; start += stride) {
      if (cancelled?.call() == true) return null;
      final piece = Float32List.sublistView(
        samples,
        start,
        (start + window).clamp(0, samples.length),
      );
      if (!piece.any((s) => s.abs() > .0005)) continue;
      final heard = await voice.transcribe(piece, language: language);
      final words = heard?.text.trim() ?? '';
      if (words.isNotEmpty && (text.isEmpty || text.last != words)) {
        text.add(words);
      }
    }
    return cancelled?.call() == true || text.isEmpty ? null : text.join('\n');
  }

  static Future<String?> caption(
    File photo,
    LlamaEngine engine,
    ModelFamily family,
    InferenceSettings settings, {
    bool Function()? cancelled,
  }) async {
    if (!engine.isLoaded ||
        engine.isBusy ||
        engine.metrics['supportsVision'] != true ||
        cancelled?.call() == true) {
      return null;
    }
    final image = await KnowledgeMedia.imageForEmbedding(
      await photo.readAsBytes(),
      edge: 768,
    );
    Timer? limit;
    try {
      final text = StringBuffer();
      limit = Timer(const Duration(seconds: 45), engine.cancel);
      await for (final piece in engine.generate(
        messages: [
          {
            'role': 'system',
            'content':
                'Describe visible facts in this photo in two short sentences. Include readable text. Do not guess identities or facts outside the image. No reasoning or instructions.',
          },
          {
            'role': 'user',
            'content': '${TextEngine.mediaMarker}\nDescribe this photo.',
            'images': [image.path],
          },
        ],
        fallbackTemplate: family.fallbackTemplate,
        settings: settings.copyWith(
          remoteEnabled: false,
          maxTokens: 192,
          temperature: 0,
          thinkingModeEnabled: false,
          promptCache: false,
        ),
      )) {
        if (cancelled?.call() == true) {
          engine.cancel();
          return null;
        }
        text.write(piece);
      }
      return text
          .toString()
          .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '')
          .trim();
    } catch (_) {
      // Captioning is optional. Keep the original photo and expose the
      // missing-grounding warning if the loaded model cannot describe it.
      return null;
    } finally {
      limit?.cancel();
      if (await image.exists()) await image.delete();
    }
  }
}
