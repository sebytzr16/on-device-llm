import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../core/platform/desktop_host.dart';
import '../features/attachments/data/attachment_store.dart';
import '../features/attachments/domain/attachment.dart';
import '../features/image_gen/domain/entities/image_gen_model.dart';
import '../features/image_gen/image_gen_imports.dart';
import '../features/image_gen/image_gen_downloads.dart';
import '../inference/engine/sd_engine.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';
import 'image_gen_page.dart';

/// The picture the chat's generate_image tool made, ready to attach to the
/// assistant message.
class GeneratedChatImage {
  final Attachment attachment;
  final String modelName;
  final int width, height;
  const GeneratedChatImage({
    required this.attachment,
    required this.modelName,
    required this.width,
    required this.height,
  });
}

/// Draws one picture for a chat turn with the image model selected in
/// Create. Desktop only: on the phone the tool says image generation needs
/// the desktop app rather than forwarding the request.
class ChatImageGenerator {
  ChatImageGenerator(this._ref);
  final Ref _ref;

  static const defaultEditStrength = 0.65;
  static const minSide = 256;
  static const maxSide = 2048;

  /// Changes [source] as [instruction] says: the same picture model draws
  /// from it (image to image), at the source's shape, and the result is a
  /// new attachment. [strength] (0.05 to 1) is how far it may move away from
  /// the source: low keeps it nearly as it was, 1 ignores it.
  Future<GeneratedChatImage> edit({
    required Attachment source,
    required String instruction,
    double? strength,
    int? steps,
    String localeCode = '',
    CancelToken? cancel,
    void Function(int step, int total)? onProgress,
    Future<void> Function()? unloadChatModel,
    Future<void> Function()? reloadChatModel,
  }) => generate(
    prompt: instruction,
    steps: steps,
    localeCode: localeCode,
    cancel: cancel,
    onProgress: onProgress,
    unloadChatModel: unloadChatModel,
    reloadChatModel: reloadChatModel,
    source: source,
    strength: strength,
  );

  Future<GeneratedChatImage> generate({
    required String prompt,
    int? width,
    int? height,
    int? steps,
    Attachment? source,
    double? strength,
    String localeCode = '',
    CancelToken? cancel,
    void Function(int step, int total)? onProgress,
    Future<void> Function()? unloadChatModel,
    Future<void> Function()? reloadChatModel,
  }) async {
    final t = stringsFor(localeCode);
    if (!DesktopHost.active) throw StateError(t.chatImageNeedsDesktop);
    final selected = resolveImageGenCompanions(
      _ref.read(desktopImageGenProvider).model,
    );
    if (imageGenNeedsCompanions(selected)) {
      throw StateError(t.imageCompanionsUnknown);
    }
    final model = await _installed(selected);
    if (model == null) {
      throw StateError(
        selected.imported && selected.kind == ImageGenKind.image
            ? t.imageDownloadRequired(selected.displayName)
            : t.chatImageNoModel,
      );
    }
    if (cancel?.isCancelled == true) throw const SdOperationStopped();
    // Its own engine: Create may release its idle one while this job runs.
    final engine = _ref.read(chatImageEngineProvider);
    // Stop in the chat cancels the running draw; the turn's own release
    // cancels the same token later, after this job is over.
    var listening = true;
    void stopDraw() {
      if (listening) engine.cancel();
    }

    final stop = cancel?.whenCancel;
    if (stop != null) {
      unawaited(
        stop.then(
          (_) => stopDraw(),
          onError: (Object _, StackTrace _) => stopDraw(),
        ),
      );
    }
    SdResult? start;
    if (source != null) {
      try {
        start = await loadEditSource(source.path, model.width, model.height);
      } catch (_) {
        listening = false;
        rethrow;
      }
      if (cancel?.isCancelled == true) {
        listening = false;
        throw const SdOperationStopped();
      }
    }
    final request = ImageGenRequest(
      prompt: prompt,
      negativePrompt: '',
      width: start?.width ?? _side(width, model.width),
      height: start?.height ?? _side(height, model.height),
      steps: (steps ?? model.steps).clamp(1, 50),
      seed: -1,
      frames: 1,
      cfgScale: model.cfgScale,
    );
    var freedChat = false;
    SdResult result;
    try {
      result = await _draw(
        engine,
        model,
        request,
        t,
        cancel,
        onProgress,
        start,
        strength,
      );
    } catch (error) {
      // The image model did not fit next to the chat model: the existing
      // admission refused it. Free the chat model and try once more.
      if (freedChat || unloadChatModel == null || !_memoryRefusal(error)) {
        rethrow;
      }
      await unloadChatModel();
      freedChat = true;
      result = await _draw(
        engine,
        model,
        request,
        t,
        cancel,
        onProgress,
        start,
        strength,
      );
    } finally {
      listening = false;
      // The chat keeps the picture, not the image model: its memory goes
      // back so the next turn and Create can use it.
      await engine.dispose();
      if (freedChat) {
        final reload = reloadChatModel;
        if (reload != null) await reload();
      }
    }
    final png = await encodePicturePng(result);
    final attachment = await AttachmentStore.saveGenerated(
      png,
      name: source == null ? t.generatedImageName : t.editedImageName,
    );
    return GeneratedChatImage(
      attachment: attachment,
      modelName: model.displayName,
      width: result.width,
      height: result.height,
    );
  }

  Future<SdResult> _draw(
    SdEngine engine,
    ImageGenModel model,
    ImageGenRequest request,
    AppLocalizations t,
    CancelToken? cancel,
    void Function(int step, int total)? onProgress, [
    SdResult? start,
    double? strength,
  ]) => runImageGeneration(
    engine: engine,
    model: model,
    request: request,
    t: t,
    cancelled: () => cancel?.isCancelled == true,
    onProgress: onProgress,
    edit: start,
    strength: strength ?? defaultEditStrength,
  );

  /// [selected] when it is an installed picture model, else another installed
  /// picture model; null when none is installed.
  Future<ImageGenModel?> _installed(ImageGenModel selected) async {
    final seen = <String>{};
    for (final model in [
      selected,
      ...imageGenCatalog.where((m) => m.kind == ImageGenKind.image),
    ]) {
      if (model.kind != ImageGenKind.image || !seen.add(model.id)) continue;
      try {
        if (await ImageGenDownloadsNotifier.isReady(model)) return model;
      } catch (e, st) {
        quietFailure('chat_image_generation:155', e, st);
      }
    }
    return null;
  }

  static int _side(int? value, int fallback) {
    final side = (value ?? fallback).clamp(minSide, maxSide);
    return (side ~/ 32) * 32;
  }

  /// The SD bridge reports a refused admission as `std::bad_alloc`; the
  /// llama bridge words it as "Not enough free memory".
  static bool _memoryRefusal(Object error) {
    final text = error is StateError ? error.message : '$error';
    final lower = text.toLowerCase();
    return text.contains('bad_alloc') ||
        text.contains('Not enough free memory') ||
        lower.contains('out of memory') ||
        lower.contains('not enough memory');
  }
}

final chatImageGeneratorProvider = Provider<ChatImageGenerator>(
  ChatImageGenerator.new,
);

/// The chat's own image engine, so a job here and Create's idle release
/// never touch the same worker.
final chatImageEngineProvider = Provider<SdEngine>((ref) => SdEngine());

/// The size an edit is drawn at: [srcWidth]x[srcHeight]'s shape holding about
/// the pixel count of the model's own size ([modelWidth]x[modelHeight]),
/// each side a multiple of 32 within [ChatImageGenerator.minSide] and
/// [ChatImageGenerator.maxSide]. A source smaller than that stays small:
/// size alone adds no detail.
({int width, int height}) editSizeFor(
  int srcWidth,
  int srcHeight,
  int modelWidth,
  int modelHeight,
) {
  final sw = srcWidth < 1 ? 1 : srcWidth, sh = srcHeight < 1 ? 1 : srcHeight;
  var scale = math.sqrt((modelWidth * modelHeight) / (sw * sh));
  if (scale > 1) scale = 1;
  int side(int v) => (((v * scale) / 32).round() * 32).clamp(
    ChatImageGenerator.minSide,
    ChatImageGenerator.maxSide,
  );
  return (width: side(sw), height: side(sh));
}

/// The image file at [path] as RGBA at [editSizeFor]'s size for the model.
Future<SdResult> loadEditSource(
  String path,
  int modelWidth,
  int modelHeight,
) async {
  final Uint8List bytes;
  try {
    bytes = await File(path).readAsBytes();
  } on FileSystemException {
    throw StateError('The picture to edit is no longer on disk.');
  }
  final (w, h) = await pictureSize(bytes);
  final size = editSizeFor(w, h, modelWidth, modelHeight);
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: size.width,
    targetHeight: size.height,
  );
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return SdResult(data!.buffer.asUint8List(), image.width, image.height);
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
