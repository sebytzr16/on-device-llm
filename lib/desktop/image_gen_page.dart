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
import '../core/l10n/l10n.dart';
import '../features/settings/presentation/providers/settings_provider.dart';
import '../features/image_gen/domain/entities/image_gen_model.dart';
import '../features/image_gen/image_gen_downloads.dart';
import '../inference/engine/sd_engine.dart';
import '../inference/ffi/sd_bindings.dart';
import 'focus_ring.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum _GenStatus { idle, loading, generating, upscaling, done, error }

class _ImageGenState {
  final ImageGenModel model;
  final _GenStatus status;
  final String? errorMessage;
  final SdResult? result;

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
  bool _stopped(int epoch) => !_alive || epoch != _epoch;

  @override
  _ImageGenState build() {
    _engine = ref.read(desktopImageEngineProvider);
    ref.onDispose(() {
      _alive = false;
      _epoch++;
      _engine.cancel();
      unawaited(_engine.dispose());
      _disposeFrames(state.frames);
    });
    return _ImageGenState(model: imageGenCatalog.first);
  }

  void selectModel(ImageGenModel model) {
    if (state.busy) return;
    state = state.copyWith(model: model, clearError: true);
  }

  Future<void> generate(ImageGenRequest r) async {
    if (state.busy) return;
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
      final paths = await ImageGenDownloadsNotifier.paths(model);
      if (_stopped(epoch)) return;
      await _engine.load(
        key: model.id,
        vaePath: paths[ImageGenRole.vae] ?? '',
        settings: model.loadSettings(paths),
      );
      if (_stopped(epoch)) return;
      state = state.copyWith(status: _GenStatus.generating);
      final video = model.kind == ImageGenKind.video;
      final plan = video
          ? (width: r.width, height: r.height, upscale: 1)
          : pictureSizePlan(r.width, r.height);
      final upscaler = paths[ImageGenRole.upscaler];
      if (plan.upscale > 1 && upscaler == null) {
        throw StateError(_t.imageMaxSide);
      }
      var result = await _engine.generate(
        {
          'prompt': r.prompt,
          'negativePrompt': r.negativePrompt,
          'width': plan.width,
          'height': plan.height,
          'steps': r.steps,
          'cfgScale': r.cfgScale,
          'seed': r.seed,
          'sampler': model.sampler,
          ...model.samplerExtras,
          if (video) ...{'frames': r.frames, 'fps': model.fps},
        },
        video: video,
        onProgress: (step, total) {
          if (!_stopped(epoch) && state.busy) {
            state = state.copyWith(progressStep: step, progressTotal: total);
          }
        },
      );
      if (_stopped(epoch)) return;
      if (plan.upscale > 1) {
        state = state.copyWith(
          status: _GenStatus.upscaling,
          factor: plan.upscale,
        );
        result = await _engine.upscale(upscaler!, result, factor: plan.upscale);
      }
      if (_stopped(epoch)) return;
      if (!video) result = result.cropCentre(r.width, r.height);
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
      state = state.copyWith(
        status: _GenStatus.done,
        result: result,
        frames: frames,
        took: DateTime.now().difference(state.startedAt!),
      );
    } catch (e) {
      if (_stopped(epoch)) return;
      state = state.copyWith(
        status: _GenStatus.error,
        errorMessage: e is StateError ? e.message : '$e',
      );
    } finally {
      if (_alive && epoch != _epoch) {
        state = state.copyWith(status: _GenStatus.idle);
      }
    }
  }

  /// Upscales the user's own picture ([encoded]: PNG, JPEG, WebP, BMP…).
  Future<void> upscale(
    Uint8List encoded,
    int factor,
    ImageGenModel upscaler,
  ) async {
    if (state.busy) return;
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
      state = state.copyWith(
        status: _GenStatus.done,
        result: result,
        frames: [frame],
        took: DateTime.now().difference(state.startedAt!),
      );
    } catch (e) {
      if (_stopped(epoch)) return;
      state = state.copyWith(
        status: _GenStatus.error,
        errorMessage: e is StateError ? e.message : '$e',
      );
    } finally {
      if (_alive && epoch != _epoch) {
        state = state.copyWith(status: _GenStatus.idle);
      }
    }
  }

  void cancel() {
    _epoch++;
    _engine.cancel();
    // Keep the job busy until native work returns; a new job cannot reset its cancel.
  }

  /// Saves the picture as PNG or the video as MJPG .avi; returns where.
  Future<String?> save() async {
    final result = state.result;
    if (result == null || state.frames.isEmpty) return null;
    if (result.frames > 1) {
      // The bridge writes the .avi straight where asked: the file is never
      // read back into memory (P3-37).
      final saved = await FilePicker.saveFile(
        dialogTitle: _t.imageSaveVideo,
        fileName: 'video.avi',
        // Required by the picker; the bridge then overwrites the empty file.
        bytes: Uint8List(0),
        type: FileType.custom,
        allowedExtensions: ['avi'],
      );
      final path = saved?.toFilePath();
      if (path == null) return null;
      await _engine.saveVideo(path, result);
      return path;
    }
    final png = await state.frames.first.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final saved = await FilePicker.saveFile(
      dialogTitle: _t.imageSavePicture,
      fileName: 'picture.png',
      bytes: png!.buffer.asUint8List(),
      mimeType: 'image/png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );
    return saved?.toFilePath();
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

  Widget _upscalePanel(_ImageGenState st, _ImageGenNotifier notifier) {
    final c = context.colors;
    final download = ref.watch(imageGenDownloadsProvider).of(_upscaler);
    final size = _pictureSize;
    final problem = _pictureError ?? st.errorMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ImageGenModel>(
          segments: [
            for (final m in upscalerTools)
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
          selected: {_upscaler},
          onSelectionChanged: st.busy
              ? null
              : (v) => setState(() => _upscaler = v.single),
        ),
        const SizedBox(height: 8),
        _ModelFiles(model: _upscaler, state: download),
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
            const SizedBox(height: 8),
            Text(problem, style: TextStyle(color: c.danger, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          DesktopFocusRing(
            child: FilledButton.icon(
              onPressed: st.busy || _picture == null || _pictureError != null
                  ? null
                  : () => notifier.upscale(_picture!, _factor, _upscaler),
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
    final download = ref.watch(imageGenDownloadsProvider).of(st.model);
    _defaults(st.model);
    final video = st.model.kind == ImageGenKind.video;

    return Row(
      children: [
        SizedBox(
          width: 300,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              key: ValueKey('${st.model.id}$_upscaleMode'),
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
                      : (v) => setState(() => _upscaleMode = v.single),
                ),
                const SizedBox(height: 12),
                if (_upscaleMode)
                  _upscalePanel(st, notifier)
                else ...[
                  DropdownButtonFormField<ImageGenModel>(
                    decoration: InputDecoration(
                      labelText: context.l10n.imageModel,
                      isDense: true,
                    ),
                    initialValue: st.model,
                    items: [
                      for (final m in imageGenCatalog)
                        DropdownMenuItem(
                          value: m,
                          child: Text(
                            '${m.id == 'qwen-image-2.1-q4k' ? context.l10n.imageFastName : m.displayName} · '
                            '${m.kind == ImageGenKind.video ? context.l10n.imageVideo : context.l10n.imagePicture}',
                          ),
                        ),
                    ],
                    onChanged: st.busy
                        ? null
                        : (m) {
                            if (m != null) notifier.selectModel(m);
                          },
                  ),
                  const SizedBox(height: 8),
                  _ModelFiles(model: st.model, state: download),
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
                    const SizedBox(height: 8),
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
                      const SizedBox(height: 8),
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
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 8),
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
                              (_frames / st.model.fps).toStringAsFixed(1),
                              '${st.model.fps}',
                            )
                          : _width > 2048 || _height > 2048
                          ? context.l10n.imageHalfSizeHint
                          : context.l10n.imageCropHint,
                      style: TextStyle(fontSize: 11, color: c.textFaint),
                    ),
                    if (st.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        st.errorMessage!,
                        style: TextStyle(color: c.danger, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 16),
                    DesktopFocusRing(
                      child: FilledButton.icon(
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
                      const SizedBox(height: 8),
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
              : _Canvas(state: st, onSave: _save),
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
        const SizedBox(height: 8),
        switch (state.status) {
          ImageGenModelStatus.ready => Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                try {
                  await downloads.delete(model);
                } on StateError {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.modelFilesInUse)),
                    );
                  }
                }
              },
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
                child: FilledButton.tonalIcon(
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
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('image-remove-unused'),
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
            icon: const Icon(Icons.cleaning_services_outlined, size: 16),
            label: Text(context.l10n.imageRemoveUnusedParts),
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
            const SizedBox(height: 8),
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
          const SizedBox(height: 8),
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
