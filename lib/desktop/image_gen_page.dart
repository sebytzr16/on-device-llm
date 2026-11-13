import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import 'history_store.dart';
import 'history_video.dart';
import '../core/l10n/l10n.dart';
import '../features/settings/presentation/providers/settings_provider.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/image_gen/domain/entities/image_gen_model.dart';
import '../features/image_gen/image_gen_model_widgets.dart';
import '../features/image_gen/image_gen_downloads.dart';
import '../features/models/presentation/widgets/model_capabilities.dart';
import 'hf_discover.dart';
import '../features/image_gen/image_gen_imports.dart';
import '../features/image_gen/image_gen_preferences.dart';
import '../data/network/hugging_face.dart';
import '../inference/engine/sd_engine.dart';
import '../inference/ffi/sd_bindings.dart';
import 'focus_ring.dart';
import 'image_gen_import_dialog.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum _GenStatus { idle, loading, generating, upscaling, done, error }

class _ImageGenState {
  final ImageGenModel model;
  final _GenStatus status;
  final String? errorMessage;
  final SdResult? result;
  final HistoryEntry? historyEntry;

  /// Decoded frames of [result]: one for a picture.
  final List<ui.Image> frames;
  final int progressStep, progressTotal;
  final DateTime? startedAt;
  final Duration? took;

  /// ×2 or ×4 while upscaling.
  final int factor;

  const _ImageGenState({
    required this.model,
    this.status = _GenStatus.idle,
    this.errorMessage,
    this.result,
    this.historyEntry,
    this.frames = const [],
    this.progressStep = 0,
    this.progressTotal = 0,
    this.startedAt,
    this.took,
    this.factor = 2,
  });

  bool get busy =>
      status == _GenStatus.loading ||
      status == _GenStatus.generating ||
      status == _GenStatus.upscaling;

  _ImageGenState copyWith({
    ImageGenModel? model,
    _GenStatus? status,
    String? errorMessage,
    bool clearError = false,
    SdResult? result,
    HistoryEntry? historyEntry,
    List<ui.Image>? frames,
    bool clearResult = false,
    int? progressStep,
    int? progressTotal,
    DateTime? startedAt,
    Duration? took,
    int? factor,
  }) => _ImageGenState(
    model: model ?? this.model,
    status: status ?? this.status,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    result: clearResult ? null : result ?? this.result,
    historyEntry: clearResult ? null : historyEntry ?? this.historyEntry,
    frames: clearResult ? const [] : frames ?? this.frames,
    progressStep: progressStep ?? this.progressStep,
    progressTotal: progressTotal ?? this.progressTotal,
    startedAt: startedAt ?? this.startedAt,
    took: clearResult ? null : took ?? this.took,
    factor: factor ?? this.factor,
  );
}

/// What the user asked for; defaults come from the model card.
class ImageGenRequest {
  final String prompt, negativePrompt;
  final int width, height, steps, seed, frames;
  final double cfgScale;
  const ImageGenRequest({
    required this.prompt,
    required this.negativePrompt,
    required this.width,
    required this.height,
    required this.steps,
    required this.seed,
    required this.frames,
    required this.cfgScale,
  });
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

final desktopImageEngineProvider = Provider<SdEngine>((ref) => SdEngine());

class _ImageGenNotifier extends Notifier<_ImageGenState> {
  late SdEngine _engine;
  AppLocalizations get _t => stringsFor(ref.read(settingsProvider).localeCode);
  int _epoch = 0;
  bool _alive = true;
  Timer? _idleRelease;
  Future<void>? _releasing;
  bool _pageVisible = false;

  void pageEntered() {
    _pageVisible = true;
  }

  void pageLeft() {
    _pageVisible = false;
    _releaseWhenIdle();
  }

  // Only the native engine is released. Results and decoded frames belong to
  // the notifier and stay available when the page is opened again.
  void _releaseWhenIdle() {
    if (!_alive || state.busy) return;
    _idleRelease?.cancel();
    _releasing ??= _engine.dispose().whenComplete(() => _releasing = null);
    unawaited(_releasing);
  }

  void _jobFinished() {
    if (!_alive) return;
    if (!_pageVisible) {
      _releaseWhenIdle();
    } else {
      _idleRelease?.cancel();
      _idleRelease = Timer(const Duration(minutes: 2), _releaseWhenIdle);
    }
  }

  bool _stopped(int epoch) => !_alive || epoch != _epoch;

  @override
  _ImageGenState build() {
    _engine = ref.read(desktopImageEngineProvider);
    var frames = stateOrNull?.frames ?? <ui.Image>[];
    listenSelf((previous, next) => frames = next.frames);
    ref.onDispose(() {
      _idleRelease?.cancel();
      _alive = false;
      _epoch++;
      _engine.cancel();
      unawaited(_releasing ?? _engine.dispose());
      _disposeFrames(frames);
    });
    return _ImageGenState(model: defaultImageGenModel(imageGenCatalog));
  }

  void selectModel(ImageGenModel model) {
    if (state.busy) return;
    state = state.copyWith(model: model, clearError: true);
  }

  String _operationError(Object error) {
    final detail = error is StateError ? error.message : '$error';
    final models = ref.read(modelManagerProvider);
    final loaded = models.loadedModel?.displayName ?? models.loadedModelId;
    if (loaded == null || error is SdOperationStopped) return detail;
    return _t.imageChatModelMemoryRecovery(detail, loaded);
  }

  Future<void> generate(ImageGenRequest r) async {
    if (state.busy) return;
    _idleRelease?.cancel();
    final epoch = ++_epoch;
    final model = state.model;
    final previous = state.frames;
    state = state.copyWith(
      status: _GenStatus.loading,
      clearError: true,
      clearResult: true,
      progressStep: 0,
      progressTotal: r.steps,
      startedAt: DateTime.now(),
    );
    _disposeFrames(previous);
    try {
      await _releasing;
      if (_stopped(epoch)) return;
      final video = model.kind == ImageGenKind.video;
      final result = await runImageGeneration(
        engine: _engine,
        model: model,
        request: r,
        t: _t,
        cancelled: () => _stopped(epoch),
        loaded: () => state = state.copyWith(status: _GenStatus.generating),
        upscaling: (factor) => state = state.copyWith(
          status: _GenStatus.upscaling,
          factor: factor,
        ),
        onProgress: (step, total) {
          if (!_stopped(epoch) && state.busy) {
            state = state.copyWith(progressStep: step, progressTotal: total);
          }
        },
      );
      if (_stopped(epoch)) return;
      final frames = <ui.Image>[];
      try {
        for (var i = 0; i < result.frames; i++) {
          frames.add(
            await _decode(result.frame(i), result.width, result.height),
          );
          if (_stopped(epoch)) {
            _disposeFrames(frames);
            return;
          }
        }
      } catch (_) {
        _disposeFrames(frames);
        rethrow;
      }
      final entry =
          await _remember(result, frames.first, {
            'prompt': r.prompt,
            'negativePrompt': r.negativePrompt,
            'modelId': model.id,
            'steps': r.steps,
            'guidance': r.cfgScale,
            'seed': r.seed,
            'kind': video ? 'video' : 'picture',
          }).catchError((Object error, StackTrace stack) {
            _disposeFrames(frames);
            Error.throwWithStackTrace(error, stack);
          });
      if (_stopped(epoch)) {
        _disposeFrames(frames);
        return;
      }
      state = state.copyWith(
        status: _GenStatus.done,
        historyEntry: entry,
        // The saved video file is durable, so drop the Dart RGBA copy; only
        // the decoded preview frames stay for playback (E12: no extra copies).
        result: video
            ? SdResult(
                Uint8List(0),
                result.width,
                result.height,
                frames: result.frames,
                fps: result.fps,
              )
            : result,
        frames: frames,
        took: DateTime.now().difference(state.startedAt!),
      );
    } catch (e) {
      if (_stopped(epoch)) return;
      state = state.copyWith(
        status: _GenStatus.error,
        errorMessage: _operationError(e),
      );
    } finally {
      if (_alive && epoch != _epoch) {
        state = state.copyWith(status: _GenStatus.idle);
      }
      _jobFinished();
    }
  }

  /// Upscales the user's own picture ([encoded]: PNG, JPEG, WebP, BMP…).
  Future<void> upscale(
    Uint8List encoded,
    int factor,
    ImageGenModel upscaler,
  ) async {
    if (state.busy) return;
    _idleRelease?.cancel();
    final epoch = ++_epoch;
    final previous = state.frames;
    state = state.copyWith(
      status: _GenStatus.upscaling,
      clearError: true,
      clearResult: true,
      startedAt: DateTime.now(),
      factor: factor,
    );
    _disposeFrames(previous);
    try {
      await _releasing;
      if (_stopped(epoch)) return;
      // The size comes from the header: a huge photo is refused before it
      // is decoded to full RGBA (P3-37).
      final (width, height) = await pictureSize(encoded);
      if (width > upscaleMaxSide || height > upscaleMaxSide) {
        throw StateError(
          _t.imageUpscaleTooLarge('$upscaleMaxSide', '$width', '$height'),
        );
      }
      final source = await decodePicture(encoded);
      if (_stopped(epoch)) return;
      final paths = await ImageGenDownloadsNotifier.paths(upscaler);
      if (_stopped(epoch)) return;
      final result = await _engine.upscale(
        paths[ImageGenRole.upscaler]!,
        source,
        factor: factor,
      );
      if (_stopped(epoch)) return;
      final frame = await _decode(result.rgba, result.width, result.height);
      if (_stopped(epoch)) {
        frame.dispose();
        return;
      }
      final entry =
          await _remember(result, frame, {
            'prompt': '',
            'negativePrompt': '',
            'modelId': upscaler.id,
            'steps': 0,
            'guidance': 0.0,
            'seed': -1,
            'kind': 'upscale',
            'factor': factor,
          }).catchError((Object error, StackTrace stack) {
            frame.dispose();
            Error.throwWithStackTrace(error, stack);
          });
      if (_stopped(epoch)) {
        frame.dispose();
        return;
      }
      state = state.copyWith(
        status: _GenStatus.done,
        historyEntry: entry,
        result: result,
        frames: [frame],
        took: DateTime.now().difference(state.startedAt!),
      );
    } catch (e) {
      if (_stopped(epoch)) return;
      state = state.copyWith(
        status: _GenStatus.error,
        errorMessage: _operationError(e),
      );
    } finally {
      if (_alive && epoch != _epoch) {
        state = state.copyWith(status: _GenStatus.idle);
      }
      _jobFinished();
    }
  }

  void cancel() {
    _epoch++;
    _engine.cancel();
    // Keep the job busy until native work returns; a new job cannot reset its cancel.
  }

  Future<HistoryEntry> _remember(
    SdResult result,
    ui.Image frame,
    Map<String, dynamic> settings,
  ) async {
    final store = await ref.read(creationHistoryStoreProvider.future);
    final png = (await frame.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(png, targetWidth: 160);
    final thumb = (await codec.getNextFrame()).image;
    codec.dispose();
    final thumbnail = (await thumb.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    thumb.dispose();
    final entry = HistoryEntry(
      data: {
        ...settings,
        'width': result.width,
        'height': result.height,
        'frames': result.frames,
        'fps': result.fps,
        'durationMs': DateTime.now()
            .difference(state.startedAt!)
            .inMilliseconds,
        'videoDurationMs': result.fps > 0
            ? result.frames * 1000 ~/ result.fps
            : 0,
      },
    );
    await store.save(
      entry,
      thumbnailPng: thumbnail,
      writeMedia: (path) async {
        if (settings['kind'] == 'video') {
          await _engine.saveVideo(path, result);
        } else {
          await File(path).writeAsBytes(png, flush: true);
        }
      },
    );
    ref.invalidate(creationHistoryProvider);
    return entry;
  }

  Future<void> showHistory(HistoryEntry entry) async {
    if (state.busy) return;
    final epoch = ++_epoch;
    state = state.copyWith(status: _GenStatus.loading, clearError: true);
    final store = await ref.read(creationHistoryStoreProvider.future);
    final frames = <ui.Image>[];
    try {
      if (entry.data['kind'] == 'video') {
        // Our engine writes MJPG AVI. Read compressed frame chunks one at a
        // time, retaining only decoded preview frames, as generation does.
        frames.addAll(await decodeHistoryVideo(store.media(entry)));
      } else {
        final codec = await ui.instantiateImageCodec(
          await store.media(entry).readAsBytes(),
        );
        frames.add((await codec.getNextFrame()).image);
        codec.dispose();
      }
      if (_stopped(epoch)) {
        _disposeFrames(frames);
        return;
      }
      final d = entry.data;
      final model = imageGenSelectableModels(
        ref.read(imageGenImportsProvider),
      ).where((m) => m.id == d['modelId']).firstOrNull;
      final previous = state.frames;
      state = state.copyWith(
        model: model,
        status: _GenStatus.done,
        clearError: true,
        historyEntry: entry,
        frames: frames,
        result: SdResult(
          Uint8List(0),
          d['width'] as int,
          d['height'] as int,
          frames: d['frames'] as int,
          fps: d['fps'] as int,
        ),
        took: Duration(milliseconds: d['durationMs'] as int),
      );
      _disposeFrames(previous);
      _jobFinished();
    } catch (_) {
      _disposeFrames(frames);
      if (!_stopped(epoch)) state = state.copyWith(status: _GenStatus.error);
      rethrow;
    }
  }

  Future<void> deleteHistory(HistoryEntry item) async {
    final store = await ref.read(creationHistoryStoreProvider.future);
    await store.delete(item);
    if (!_alive) return;
    if (state.historyEntry?.id == item.id) {
      final previous = state.frames;
      state = state.copyWith(status: _GenStatus.idle, clearResult: true);
      _disposeFrames(previous);
    }
    ref.invalidate(creationHistoryProvider);
  }

  /// Exports a copy; videos no longer depend on a live native worker.
  Future<String?> save([HistoryEntry? item]) async {
    final entry = item ?? state.historyEntry;
    if (entry == null) return null;
    final store = await ref.read(creationHistoryStoreProvider.future);
    final video = entry.data['kind'] == 'video';
    final source = store.media(entry);
    final saved = await FilePicker.saveFile(
      dialogTitle: video ? _t.imageSaveVideo : _t.imageSavePicture,
      fileName: video ? 'video.avi' : 'picture.png',
      bytes: Uint8List(0),
      type: FileType.custom,
      allowedExtensions: [video ? 'avi' : 'png'],
    );
    final path = saved?.toFilePath();
    if (path == null) return null;
    if (!p.equals(p.normalize(path), p.normalize(source.path))) {
      await source.copy(path);
    }
    return path;
  }

  static void _disposeFrames(List<ui.Image> frames) {
    for (final f in frames) {
      f.dispose();
    }
  }

  static Future<ui.Image> _decode(Uint8List rgba, int w, int h) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }
}

/// A picture's width and height from its header, without decoding it.
Future<(int, int)> pictureSize(Uint8List encoded) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = (descriptor.width, descriptor.height);
    descriptor.dispose();
    return size;
  } finally {
    buffer.dispose();
  }
}

/// Decodes a PNG, JPEG, WebP, GIF or BMP into the bridge's RGBA layout.
Future<SdResult> decodePicture(Uint8List encoded) async {
  final codec = await ui.instantiateImageCodec(encoded);
  final frame = await codec.getNextFrame();
  codec.dispose();
  final image = frame.image;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return SdResult(data!.buffer.asUint8List(), image.width, image.height);
  } finally {
    image.dispose();
  }
}

/// One picture or video on [engine]: the load, the planned draw size, the
/// generation and the upscale Create runs. Shared with the chat's
/// generate_image tool, which has no page state. [cancelled] is checked
/// after each await so a stopped job does not go on.
Future<SdResult> runImageGeneration({
  required SdEngine engine,
  required ImageGenModel model,
  required ImageGenRequest request,
  required AppLocalizations t,
  bool Function()? cancelled,
  void Function()? loaded,
  void Function(int factor)? upscaling,
  void Function(int step, int total)? onProgress,
  SdResult? edit,
  double strength = 0.65,
}) async {
  void check() {
    if (cancelled?.call() == true) throw const SdOperationStopped();
  }

  model = resolveImageGenCompanions(model);
  final paths = await ImageGenDownloadsNotifier.paths(model);
  check();
  await engine.load(
    key: model.id,
    vaePath: paths[ImageGenRole.vae] ?? '',
    settings: model.loadSettings(paths),
  );
  check();
  loaded?.call();
  final video = model.kind == ImageGenKind.video;
  if (edit != null) {
    // Image to image: the drawing keeps the starting picture's shape and is
    // returned as drawn (no upscale, no crop).
    if (video) throw StateError(t.chatImageEditNeedsPicture);
    final result = await engine.generate(
      {
        'prompt': request.prompt,
        'negativePrompt': request.negativePrompt,
        'width': edit.width,
        'height': edit.height,
        'steps': request.steps,
        'cfgScale': request.cfgScale,
        'seed': request.seed,
        'strength': strength.clamp(0.05, 1.0),
        'sampler': model.sampler,
        ...model.samplerExtras,
      },
      edit: true,
      init: edit,
      onProgress: onProgress,
    );
    check();
    return result;
  }
  final plan = video
      ? (width: request.width, height: request.height, upscale: 1)
      : pictureSizePlan(request.width, request.height);
  final upscaler = paths[ImageGenRole.upscaler];
  if (plan.upscale > 1 && upscaler == null) {
    throw StateError(t.imageMaxSide);
  }
  var result = await engine.generate(
    {
      'prompt': request.prompt,
      'negativePrompt': request.negativePrompt,
      'width': plan.width,
      'height': plan.height,
      'steps': request.steps,
      'cfgScale': request.cfgScale,
      'seed': request.seed,
      'sampler': model.sampler,
      ...model.samplerExtras,
      if (video) ...{'frames': request.frames, 'fps': model.fps},
    },
    video: video,
    onProgress: onProgress,
  );
  check();
  if (plan.upscale > 1) {
    upscaling?.call(plan.upscale);
    result = await engine.upscale(upscaler!, result, factor: plan.upscale);
    check();
  }
  if (!video) result = result.cropCentre(request.width, request.height);
  return result;
}

/// [result]'s first frame as PNG, the format attachments are stored in.
Future<Uint8List> encodePicturePng(SdResult result) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(result.frame(0));
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: result.width,
    height: result.height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode the picture');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

final desktopImageGenProvider =
    NotifierProvider<_ImageGenNotifier, _ImageGenState>(_ImageGenNotifier.new);

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class DesktopImageGenPage extends ConsumerStatefulWidget {
  const DesktopImageGenPage({super.key});

  @override
  ConsumerState<DesktopImageGenPage> createState() =>
      _DesktopImageGenPageState();
}

class _DesktopImageGenPageState extends ConsumerState<DesktopImageGenPage> {
  late final _ImageGenNotifier _notifier;
  final _historyScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(desktopImageGenProvider.notifier);
    _notifier.pageEntered();
    unawaited(_restorePreferred());
  }

  /// Opens Create with the model and mode last used, once preferences and
  /// imported models have loaded.
  Future<void> _restorePreferred() async {
    final preferences = ref.read(imageGenPreferencesProvider.notifier);
    await preferences.ready;
    await ref.read(imageGenImportsProvider.notifier).ready;
    if (!mounted) return;
    final settings = ref.read(imageGenPreferencesProvider);
    final imported = ref.read(imageGenImportsProvider);
    final last = settings.lastMode ?? ImageGenMode.image;
    if (last == ImageGenMode.upscale) {
      final upscalers = imageGenUpscalerModels(imported);
      final selected = upscalers
          .where((m) => m.id == settings.of(ImageGenMode.upscale))
          .firstOrNull;
      setState(() {
        _upscaleMode = true;
        if (selected != null) _upscaler = selected;
      });
      return;
    }
    final models = imageGenSelectableModels(imported);
    var selected = models.where((m) => m.id == settings.of(last)).firstOrNull;
    if (selected == null && last == ImageGenMode.image) {
      // Nothing picked yet: the fastest picture model, a downloaded one
      // first.
      final downloaded = <String>{};
      for (final m in models) {
        if (m.kind != ImageGenKind.image) continue;
        try {
          if (await ImageGenDownloadsNotifier.isReady(m)) downloaded.add(m.id);
        } catch (_) {}
      }
      if (!mounted) return;
      selected = defaultImageGenModel(models, downloaded: downloaded);
    }
    if (selected != null && !ref.read(desktopImageGenProvider).busy) {
      _notifier.selectModel(selected);
    }
  }

  void _chooseModel(ImageGenModel model) {
    _notifier.selectModel(model);
    unawaited(
      ref
          .read(imageGenPreferencesProvider.notifier)
          .remember(ImageGenMode.of(model), model.id),
    );
  }

  void _chooseUpscaler(ImageGenModel model) {
    setState(() => _upscaler = model);
    unawaited(
      ref
          .read(imageGenPreferencesProvider.notifier)
          .remember(ImageGenMode.upscale, model.id),
    );
  }

  void _setUpscaleMode(bool upscale) {
    setState(() => _upscaleMode = upscale);
    final mode = upscale
        ? ImageGenMode.upscale
        : ImageGenMode.of(ref.read(desktopImageGenProvider).model);
    unawaited(
      ref.read(imageGenPreferencesProvider.notifier).rememberMode(mode),
    );
  }

  Future<void> _openImport() async {
    // Upscalers are single files with no diffusion pipeline tag, so they keep
    // the paste-a-repo dialog; generation models open Hugging Face discovery.
    if (_upscaleMode) return _importUpscaler();
    final result = await showImageGenDiscovery(context);
    if (result == null || !mounted) return;
    final mode = result.pipeline == HfImagePipeline.textToVideo
        ? ImageGenMode.video
        : ImageGenMode.image;
    try {
      final imported = importedImageGenModel(
        repo: result.files.repo,
        revision: result.files.revision,
        file: result.file,
        license: result.files.license,
        mode: mode,
      );
      await _addImported(imported, mode);
    } catch (e) {
      _importFailed(e);
    }
  }

  Future<void> _importUpscaler() async {
    final imported = await showImageGenImportDialog(context);
    if (imported == null || !mounted) return;
    try {
      await _addImported(imported, ImageGenMode.of(imported));
    } catch (e) {
      _importFailed(e);
    }
  }

  Future<void> _addImported(ImageGenModel imported, ImageGenMode mode) async {
    await ref.read(imageGenImportsProvider.notifier).add(imported);
    await ref
        .read(imageGenPreferencesProvider.notifier)
        .remember(mode, imported.id);
    if (!mounted) return;
    if (mode == ImageGenMode.upscale) {
      setState(() {
        _upscaleMode = true;
        _upscaler = imported;
      });
    } else {
      _notifier.selectModel(imported);
    }
    unawaited(ref.read(imageGenDownloadsProvider.notifier).download(imported));
  }

  void _importFailed(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.imageImportFailed('$e'))),
    );
  }

  final _promptCtrl = TextEditingController();
  final _negCtrl = TextEditingController();
  late int _width, _height, _steps, _frames;
  int _seed = -1;
  late double _cfg;
  String? _defaultsFor;

  /// Bumped when a preset sets the size, so the size fields show it.
  int _sizeKey = 0;

  /// Upscale mode: the user's own picture instead of a prompt.
  bool _upscaleMode = false;
  Uint8List? _picture;
  String? _pictureName;
  (int, int)? _pictureSize;
  String? _pictureError;
  int _factor = 2;
  ImageGenModel _upscaler = upscalerTools.first;
  bool _dropping = false;

  void _historyError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.historyFailed('$error'))),
    );
  }

  Future<void> _restore(HistoryEntry entry) async {
    try {
      await _notifier.showHistory(entry);
      if (!mounted) return;
      final d = entry.data;
      setState(() {
        _defaults(ref.read(desktopImageGenProvider).model);
        _upscaleMode = d['kind'] == 'upscale';
        if (_upscaleMode) {
          _upscaler =
              imageGenUpscalerModels(
                ref.read(imageGenImportsProvider),
              ).where((m) => m.id == d['modelId']).firstOrNull ??
              _upscaler;
          _factor = d['factor'] as int? ?? 2;
        }
        _promptCtrl.text = d['prompt'] as String;
        _negCtrl.text = d['negativePrompt'] as String;
        _width = d['width'] as int;
        _height = d['height'] as int;
        _steps = d['steps'] as int;
        _cfg = (d['guidance'] as num).toDouble();
        _seed = d['seed'] as int;
        _frames = d['frames'] as int;
        _sizeKey++;
      });
    } catch (e) {
      _historyError(e);
    }
  }

  Widget _historyPanel(_ImageGenState st) {
    final t = context.l10n;
    final c = context.colors;
    final entries = ref.watch(creationHistoryProvider);
    final store = ref.watch(creationHistoryStoreProvider).asData?.value;
    final bytes = ref.watch(creationHistorySizeProvider).asData?.value;
    Future<void> delete(HistoryEntry item) async {
      if (!await confirmAction(
        context,
        title: t.historyDelete,
        message: t.historyDeleteConfirm,
        confirmLabel: t.historyDelete,
        destructive: true,
      )) {
        return;
      }
      try {
        await _notifier.deleteHistory(item);
      } catch (e) {
        _historyError(e);
      }
    }

    Widget tile(HistoryEntry item) => Tooltip(
      message: item.data['prompt'] as String,
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        width: 112,
        margin: const EdgeInsets.only(right: AppDesign.sm),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: InkWell(
                onTap: st.busy ? null : () => _restore(item),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (store != null)
                      Image.file(
                        store.thumbnail(item),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.broken_image_outlined,
                          color: c.textFaint,
                        ),
                      ),
                    if (item.data['kind'] == 'video')
                      Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.movie_outlined,
                            size: 16,
                            color: c.text,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 28,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: t.commonSave,
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.save_alt_rounded),
                    onPressed: st.busy
                        ? null
                        : () async {
                            try {
                              await _notifier.save(item);
                            } catch (e) {
                              _historyError(e);
                            }
                          },
                  ),
                  IconButton(
                    tooltip: t.historyDelete,
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: st.busy ? null : () => delete(item),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(t.historyTitle, style: context.text.title),
              const SizedBox(width: AppDesign.md),
              if (bytes != null)
                Text(
                  t.historyStorage(_gb(bytes)),
                  style: context.text.small.copyWith(color: c.textMuted),
                ),
            ],
          ),
          const SizedBox(height: AppDesign.sm),
          entries.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) =>
                Text(t.historyFailed('$e'), style: context.text.small),
            data: (items) => items.isEmpty
                ? Text(
                    t.historyEmpty,
                    style: context.text.small.copyWith(color: c.textMuted),
                  )
                : SizedBox(
                    height: 128,
                    child: Scrollbar(
                      controller: _historyScroll,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _historyScroll,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(bottom: 10),
                        itemCount: items.length,
                        itemBuilder: (context, index) => tile(items[index]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _takePicture(Uint8List bytes, String name) async {
    try {
      final (width, height) = await pictureSize(bytes);
      if (!mounted) return;
      setState(() {
        _picture = bytes;
        _pictureName = name;
        _pictureSize = (width, height);
        _pictureError = width > upscaleMaxSide || height > upscaleMaxSide
            ? context.l10n.imageUpscaleLimit('$upscaleMaxSide')
            : null;
      });
    } catch (_) {
      if (mounted) setState(() => _pictureError = context.l10n.imageNotPicture);
    }
  }

  Future<void> _openPicture() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    final path = files.singleOrNull?.path;
    if (path == null) return;
    await _takePicture(await File(path).readAsBytes(), p.basename(path));
  }

  Future<void> _pastePicture() async {
    final t = context.l10n;
    final bytes = await Pasteboard.image;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        setState(() => _pictureError = context.l10n.imageClipboardEmpty);
      }
      return;
    }
    await _takePicture(bytes, t.imagePastedPicture);
  }

  void _defaults(ImageGenModel m) {
    if (_defaultsFor == m.id) return;
    _defaultsFor = m.id;
    _width = m.width;
    _height = m.height;
    _steps = m.steps;
    _frames = m.frames;
    _cfg = m.cfgScale;
  }

  @override
  void dispose() {
    _historyScroll.dispose();
    _notifier.pageLeft();
    _promptCtrl.dispose();
    _negCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final t = context.l10n;
    try {
      final path = await ref.read(desktopImageGenProvider.notifier).save();
      if (path != null) {
        messenger.showSnackBar(SnackBar(content: Text(t.imageSaved(path))));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(t.imageSaveFailed('$e'))));
    }
  }

  Widget _upscalePanel(
    _ImageGenState st,
    _ImageGenNotifier notifier,
    List<ImageGenModel> upscalers,
    ImageGenModel upscaler,
  ) {
    final c = context.colors;
    final download = ref.watch(imageGenDownloadsProvider).of(upscaler);
    final size = _pictureSize;
    final problem = _pictureError ?? st.errorMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ImageGenModel>(
          segments: [
            for (final m in upscalers)
              ButtonSegment(
                value: m,
                label: Text(
                  m.id == 'nomos2-hq-mosr'
                      ? context.l10n.imageSharp
                      : m.id == 'realesrgan-x4plus'
                      ? context.l10n.imageCleanUp
                      : m.displayName,
                ),
              ),
          ],
          selected: {upscaler},
          onSelectionChanged: st.busy ? null : (v) => _chooseUpscaler(v.single),
        ),
        const SizedBox(height: AppSpace.row),
        _ModelFiles(model: upscaler, state: download),
        if (download.status == ImageGenModelStatus.ready) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: st.busy ? null : _openPicture,
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: Text(context.l10n.imageOpen),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: st.busy ? null : _pastePicture,
                  icon: const Icon(Icons.content_paste_rounded, size: 16),
                  label: Text(context.l10n.imagePaste),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.imageDropHint,
            style: TextStyle(fontSize: 11, color: c.textFaint),
          ),
          if (_picture != null && size != null) ...[
            const SizedBox(height: 12),
            Text(
              '${_pictureName ?? ''} · ${size.$1} × ${size.$2}',
              style: TextStyle(fontSize: 11, color: c.textFaint),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('×2')),
                ButtonSegment(value: 4, label: Text('×4')),
              ],
              selected: {_factor},
              onSelectionChanged: st.busy
                  ? null
                  : (v) => setState(() => _factor = v.single),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.imageResultSize(
                '${size.$1 * _factor}',
                '${size.$2 * _factor}',
              ),
              style: TextStyle(fontSize: 11, color: c.textFaint),
            ),
          ],
          if (problem != null) ...[
            const SizedBox(height: AppSpace.row),
            Text(problem, style: TextStyle(color: c.danger, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          DesktopFocusRing(
            child: FilledButton.tonalIcon(
              style: appTonalButtonStyle(context),
              onPressed: st.busy || _picture == null || _pictureError != null
                  ? null
                  : () => notifier.upscale(_picture!, _factor, upscaler),
              icon: st.busy
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.zoom_out_map_rounded, size: 16),
              label: Text(
                st.busy
                    ? context.l10n.imageUpscaling
                    : context.l10n.imageUpscale,
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!SdBindings.isAvailable()) return _Unavailable(c: c);

    final st = ref.watch(desktopImageGenProvider);
    final notifier = ref.read(desktopImageGenProvider.notifier);
    final imported = ref.watch(imageGenImportsProvider);
    final models = imageGenSelectableModels(imported);
    final upscalers = imageGenUpscalerModels(imported);
    final selected = models.where((m) => m.id == st.model.id).firstOrNull;
    if (selected == null) {
      // The selected imported model was removed: fall back after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = ref.read(desktopImageGenProvider);
        if (!current.busy && !models.any((m) => m.id == current.model.id)) {
          _notifier.selectModel(models.first);
        }
      });
    }
    final model = selected ?? models.first;
    final recommended = recommendedImageGenModels(
      desktopMemoryMb(ref.watch(desktopHfMemoryProvider).asData?.value).$2,
    );
    final upscaler =
        upscalers.where((m) => m.id == _upscaler.id).firstOrNull ??
        upscalers.first;
    final download = ref.watch(imageGenDownloadsProvider).of(model);
    _defaults(model);
    final video = model.kind == ImageGenKind.video;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 300,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              key: ValueKey('${model.id}$_upscaleMode$_sizeKey'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(context.l10n.imageCreate),
                      icon: const Icon(Icons.auto_awesome, size: 16),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(context.l10n.imageUpscale),
                      icon: const Icon(Icons.zoom_out_map_rounded, size: 16),
                    ),
                  ],
                  selected: {_upscaleMode},
                  onSelectionChanged: st.busy
                      ? null
                      : (v) => _setUpscaleMode(v.single),
                ),
                const SizedBox(height: 12),
                if (_upscaleMode)
                  _upscalePanel(st, notifier, upscalers, upscaler)
                else ...[
                  DropdownButtonFormField<ImageGenModel>(
                    decoration: InputDecoration(
                      labelText: context.l10n.imageModel,
                      isDense: true,
                    ),
                    isExpanded: true,
                    itemHeight: 64,
                    initialValue: model,
                    // The closed field shows the model alone; the open list
                    // adds a delete button to downloaded models (owner
                    // 2026-11-12).
                    selectedItemBuilder: (_) => [
                      for (final m in models)
                        ImageGenModelOption(
                          model: m,
                          recommended: recommended.contains(m.id),
                        ),
                    ],
                    items: [
                      for (final m in models)
                        DropdownMenuItem(
                          value: m,
                          child: ImageGenModelOption(
                            model: m,
                            recommended: recommended.contains(m.id),
                            onDelete: st.busy
                                ? null
                                : (menu) {
                                    Navigator.of(menu).pop();
                                    unawaited(
                                      deleteImageGenModel(context, ref, m),
                                    );
                                  },
                          ),
                        ),
                    ],
                    onChanged: st.busy
                        ? null
                        : (m) {
                            if (m != null) _chooseModel(m);
                          },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('image-add-model'),
                      onPressed: st.busy ? null : _openImport,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(context.l10n.imageAddModel),
                    ),
                  ),
                  _ModelFiles(model: model, state: download),
                  if (download.status == ImageGenModelStatus.ready) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _promptCtrl,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: context.l10n.imagePrompt,
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: AppDesign.radius(AppDesign.rMd),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpace.row),
                    TextField(
                      controller: _negCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: context.l10n.imageNegativePrompt,
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: AppDesign.radius(AppDesign.rMd),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!video) ...[
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final preset in picturePresets)
                            ChoiceChip(
                              label: Text(
                                preset.label == 'Square'
                                    ? context.l10n.imageSquare
                                    : preset.label,
                              ),
                              selected:
                                  _width == preset.width &&
                                  _height == preset.height,
                              onSelected: (_) => setState(() {
                                _width = preset.width;
                                _height = preset.height;
                                _sizeKey++;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.row),
                    ],
                    Row(
                      key: ValueKey(_sizeKey),
                      children: [
                        Expanded(
                          child: _IntField(
                            label: context.l10n.imageWidth,
                            value: _width,
                            min: 256,
                            max: video ? 2048 : 3840,
                            onChanged: (v) => setState(() => _width = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _IntField(
                            label: context.l10n.imageHeight,
                            value: _height,
                            min: 256,
                            max: video ? 2048 : 3840,
                            onChanged: (v) => setState(() => _height = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.row),
                    Row(
                      children: [
                        Expanded(
                          child: _IntField(
                            label: context.l10n.imageSteps,
                            value: _steps,
                            min: 1,
                            max: 100,
                            onChanged: (v) => setState(() => _steps = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _DoubleField(
                            label: context.l10n.imageGuidance,
                            value: _cfg,
                            min: 0,
                            max: 20,
                            onChanged: (v) => setState(() => _cfg = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.row),
                    Row(
                      children: [
                        if (video) ...[
                          Expanded(
                            child: _IntField(
                              label: context.l10n.imageFrames,
                              value: _frames,
                              min: 1,
                              max: 121,
                              onChanged: (v) => setState(() => _frames = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: _IntField(
                            label: context.l10n.imageSeed,
                            value: _seed,
                            min: -1,
                            max: 2147483647,
                            onChanged: (v) => setState(() => _seed = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      video
                          ? context.l10n.imageVideoSizeHint(
                              (_frames / model.fps).toStringAsFixed(1),
                              '${model.fps}',
                            )
                          : _width > 2048 || _height > 2048
                          ? context.l10n.imageHalfSizeHint
                          : context.l10n.imageCropHint,
                      style: TextStyle(fontSize: 11, color: c.textFaint),
                    ),
                    if (st.errorMessage != null) ...[
                      const SizedBox(height: AppSpace.row),
                      Text(
                        st.errorMessage!,
                        style: TextStyle(color: c.danger, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 16),
                    DesktopFocusRing(
                      child: FilledButton.tonalIcon(
                        style: appTonalButtonStyle(context),
                        onPressed: st.busy
                            ? null
                            : () => notifier.generate(
                                ImageGenRequest(
                                  prompt: _promptCtrl.text,
                                  negativePrompt: _negCtrl.text,
                                  width: _width,
                                  height: _height,
                                  steps: _steps,
                                  seed: _seed,
                                  frames: _frames,
                                  cfgScale: _cfg,
                                ),
                              ),
                        icon: st.busy
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                video
                                    ? Icons.movie_creation_outlined
                                    : Icons.auto_awesome,
                                size: 16,
                              ),
                        label: Text(
                          st.busy
                              ? context.l10n.imageGenerating
                              : video
                              ? context.l10n.imageMakeVideo
                              : context.l10n.imageMakePicture,
                        ),
                      ),
                    ),
                    if (st.busy) ...[
                      const SizedBox(height: AppSpace.row),
                      DesktopFocusRing(
                        child: OutlinedButton(
                          onPressed: notifier.cancel,
                          child: Text(context.l10n.goalStop),
                        ),
                      ),
                    ],
                  ],
                ],
              ],
            ),
          ),
        ),
        Container(width: 1, color: c.hairline),
        Expanded(
          child: _upscaleMode
              ? CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.keyV,
                      control: true,
                    ): _pastePicture,
                  },
                  child: Focus(
                    autofocus: true,
                    child: DropTarget(
                      enable: !st.busy,
                      onDragEntered: (_) => setState(() => _dropping = true),
                      onDragExited: (_) => setState(() => _dropping = false),
                      onDragDone: (details) async {
                        setState(() => _dropping = false);
                        final file = details.files.firstOrNull;
                        if (file != null) {
                          await _takePicture(
                            await File(file.path).readAsBytes(),
                            file.name,
                          );
                        }
                      },
                      child: _Canvas(
                        state: st,
                        onSave: _save,
                        upscaleMode: true,
                        dropping: _dropping,
                        picture: _picture,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: _Canvas(state: st, onSave: _save),
                    ),
                    Container(height: 1, color: c.hairline),
                    _historyPanel(st),
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

String _gb(int bytes) => bytes < 1 << 30
    ? '${(bytes / (1 << 20)).round()} MB'
    : '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';

/// Download state of the model's files, with download, pause and delete.
class _ModelFiles extends ConsumerWidget {
  final ImageGenModel model;
  final ImageGenModelState state;
  const _ModelFiles({required this.model, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final downloads = ref.read(imageGenDownloadsProvider.notifier);
    final caption = TextStyle(fontSize: 12, color: c.textMuted);
    Future<void> remove() async {
      try {
        await downloads.delete(model);
      } on StateError {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.l10n.modelFilesInUse)));
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(switch (model.id) {
          'nomos2-hq-mosr' => context.l10n.imageBlurbSharp,
          'realesrgan-x4plus' => context.l10n.imageBlurbClean,
          'qwen-image-2.1-q8' => context.l10n.imageBlurbQwen,
          'qwen-image-2.1-q4k' => context.l10n.imageBlurbQwenFast,
          'wan-2.2-ti2v-5b-q4km' => context.l10n.imageBlurbWan,
          'ltx-2.3-22b-distilled-q4km' => context.l10n.imageBlurbLtx,
          _ => model.blurb,
        }, style: caption),
        const SizedBox(height: 4),
        Text(
          '${context.l10n.imageFileCount(model.files.length)}, '
          '${_gb(model.sizeBytes)} · '
          '${model.license}',
          style: TextStyle(fontSize: 11, color: c.textFaint),
        ),
        if (state.missingFiles.isNotEmpty)
          Text(
            context.l10n.imageMissingFiles(state.missingFiles.join(', ')),
            style: caption,
          ),
        const SizedBox(height: AppSpace.row),
        switch (state.status) {
          ImageGenModelStatus.ready =>
            model.imported
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: remove,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: Text(context.l10n.imageDeleteFiles),
                    ),
                  ),
          ImageGenModelStatus.downloading => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: state.received / model.sizeBytes),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.imageDownloaded(
                        _gb(state.received),
                        _gb(model.sizeBytes),
                      ),
                      style: caption,
                    ),
                  ),
                  TextButton(
                    onPressed: () => downloads.pause(model),
                    child: Text(context.l10n.imagePause),
                  ),
                ],
              ),
            ],
          ),
          ImageGenModelStatus.missing => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesktopFocusRing(
                child: FilledButton.icon(
                  onPressed: () => downloads.download(model),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text(
                    state.received > 0
                        ? context.l10n.imageResumeDownload
                        : context.l10n.imageDownload(_gb(model.sizeBytes)),
                  ),
                ),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 4),
                Text(
                  state.error!,
                  style: TextStyle(fontSize: 12, color: c.danger),
                ),
              ],
            ],
          ),
        },
        if (model.imported)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('image-remove-imported-${model.id}'),
              onPressed: remove,
              icon: const Icon(Icons.remove_circle_outline, size: 16),
              label: Text(context.l10n.imageRemoveModel),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('image-remove-unused'),
            style: TextButton.styleFrom(foregroundColor: c.textMuted),
            onPressed: state.status == ImageGenModelStatus.downloading
                ? null
                : () async {
                    try {
                      await downloads.removeUnusedParts();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.l10n.imageUnusedPartsRemoved),
                          ),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.l10n.desktopChatActionFailed),
                          ),
                        );
                      }
                    }
                  },
            child: Text(context.l10n.imageRemoveUnusedParts),
          ),
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  final AppColors c;
  const _Unavailable({required this.c});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.image_not_supported_outlined, size: 48, color: c.textFaint),
        const SizedBox(height: 12),
        Text(
          context.l10n.imageUnavailable,
          style: TextStyle(color: c.textFaint),
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.imageBuildHint,
          style: TextStyle(fontSize: 12, color: c.textFaint),
        ),
      ],
    ),
  );
}

class _Canvas extends StatelessWidget {
  final _ImageGenState state;
  final VoidCallback onSave;
  final bool upscaleMode, dropping;

  /// The picture waiting to be upscaled, shown until there is a result.
  final Uint8List? picture;
  const _Canvas({
    required this.state,
    required this.onSave,
    this.upscaleMode = false,
    this.dropping = false,
    this.picture,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final result = state.result;
    if (dropping) {
      return Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: c.accent, width: 2),
          borderRadius: AppDesign.radius(AppDesign.rMd),
        ),
        alignment: Alignment.center,
        child: Text(
          context.l10n.imageDropToUpscale,
          style: TextStyle(color: c.accent),
        ),
      );
    }
    if (result != null && state.frames.isNotEmpty) {
      final secs = state.took == null
          ? ''
          : upscaleMode
          ? context.l10n.imageUpscaledIn('${state.took!.inSeconds}')
          : context.l10n.imageMadeIn('${state.took!.inSeconds}');
      return Column(
        children: [
          Expanded(
            child: state.frames.length > 1
                ? _FramePlayer(frames: state.frames, fps: result.fps)
                : RawImage(image: state.frames.first, fit: BoxFit.contain),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${result.width} × ${result.height}'
                  '${result.frames > 1 ? context.l10n.imageFrameCount('${result.frames}') : ''}'
                  '$secs',
                  style: TextStyle(fontSize: 11, color: c.textFaint),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save_alt_rounded, size: 16),
                  label: Text(context.l10n.commonSave),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (state.busy) {
      final total = state.progressTotal;
      return Center(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: state.status == _GenStatus.generating && total > 0
                    ? state.progressStep / total
                    : null,
              ),
              const SizedBox(height: 12),
              _Elapsed(
                since: state.startedAt,
                label: state.status == _GenStatus.loading
                    ? context.l10n.imageLoadingModel
                    : state.status == _GenStatus.upscaling
                    ? context.l10n.imageUpscalingFactor('${state.factor}')
                    : total > 0 && state.progressStep > 0
                    ? context.l10n.imageStepProgress(
                        '${state.progressStep}',
                        '$total',
                      )
                    : context.l10n.imageReadingPrompt,
              ),
            ],
          ),
        ),
      );
    }
    if (upscaleMode && picture != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Image.memory(picture!, fit: BoxFit.contain),
      );
    }
    if (upscaleMode) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.zoom_out_map_rounded,
              size: 64,
              color: c.textFaint.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSpace.row),
            Text(
              context.l10n.imageChoosePicture,
              style: TextStyle(color: c.textFaint),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            state.model.kind == ImageGenKind.video
                ? Icons.movie_outlined
                : Icons.image_outlined,
            size: 64,
            color: c.textFaint.withValues(alpha: 0.3),
          ),
          const SizedBox(height: AppSpace.row),
          Text(
            context.l10n.imageDescribe,
            style: TextStyle(color: c.textFaint),
          ),
        ],
      ),
    );
  }
}

/// A status line with the seconds since [since], ticking once a second.
class _Elapsed extends StatefulWidget {
  final DateTime? since;
  final String label;
  const _Elapsed({required this.since, required this.label});

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.since == null
        ? 0
        : DateTime.now().difference(widget.since!).inSeconds;
    return Text(
      '${widget.label} · $s s',
      style: TextStyle(color: context.colors.textFaint),
    );
  }
}

/// Plays decoded frames in a loop; a click pauses and resumes.
class _FramePlayer extends StatefulWidget {
  final List<ui.Image> frames;
  final int fps;
  const _FramePlayer({required this.frames, required this.fps});

  @override
  State<_FramePlayer> createState() => _FramePlayerState();
}

class _FramePlayerState extends State<_FramePlayer> {
  Timer? _timer;
  var _index = 0;

  void _play() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: 1000 ~/ (widget.fps > 0 ? widget.fps : 16)),
      (_) => setState(() => _index = (_index + 1) % widget.frames.length),
    );
  }

  @override
  void initState() {
    super.initState();
    _play();
  }

  @override
  void didUpdateWidget(_FramePlayer old) {
    super.didUpdateWidget(old);
    if (old.frames != widget.frames) {
      _index = 0;
      _play();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() {
      if (_timer?.isActive ?? false) {
        _timer!.cancel();
      } else {
        _play();
      }
    }),
    child: RawImage(
      image: widget.frames[_index % widget.frames.length],
      fit: BoxFit.contain,
    ),
  );
}

class _IntField extends StatelessWidget {
  final String label;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  const _IntField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: value.toString(),
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(borderRadius: AppDesign.radius(AppDesign.rSm)),
    ),
    keyboardType: TextInputType.number,
    onChanged: (v) {
      final n = int.tryParse(v);
      if (n != null && n >= min && n <= max) onChanged(n);
    },
  );
}

class _DoubleField extends StatelessWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const _DoubleField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: value.toStringAsFixed(1),
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(borderRadius: AppDesign.radius(AppDesign.rSm)),
    ),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (v) {
      final n = double.tryParse(v);
      if (n != null && n >= min && n <= max) onChanged(n);
    },
  );
}
