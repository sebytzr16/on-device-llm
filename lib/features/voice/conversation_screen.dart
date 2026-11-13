import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_design.dart';
import '../../core/l10n/l10n.dart';
import '../../core/motion/motion.dart';
import '../../core/providers/shared_providers.dart';
import '../../inference/engine/llama_engine.dart';
import '../chat/presentation/providers/chat_model_pins.dart';
import '../chat/presentation/providers/chat_provider.dart';
import '../models/presentation/providers/model_manager_provider.dart';
import '../settings/domain/entities/inference_settings.dart';
import '../settings/presentation/providers/settings_provider.dart';
import '../tools/presentation/phone_action_cards.dart';
import 'conversation_model.dart';
import 'conversation_session.dart';
import 'sherpa_voice.dart';
import 'voice_models.dart';
import 'voice_models_provider.dart';
import 'voice_service.dart';

export 'conversation_session.dart' show ConversationPhase;

part 'conversation_widgets.dart';
part 'conversation_wave.dart';

/// Conversation mode (tester, 2026-10-07): a full-screen, hands-free voice
/// chat. The remote connection answers when one is on (tester, 2026-10-18),
/// otherwise a model on the phone (Qwen3.5 0.8B); Whisper listens the whole time
/// (echo-cancelled), Kokoro speaks each sentence as soon as it is written,
/// and talking over the answer interrupts it. The turns are saved as a
/// normal chat. Without the on-device voice, the system recognizer and
/// voice take turns instead.
class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, this.listen = true});

  /// Whether the microphone opens by itself. Off for a launch another app
  /// could have sent: the screen opens muted until the user taps the mic.
  final bool listen;

  /// True while the screen is open (the chat screen then does not read
  /// answers aloud itself).
  static var open = false;

  /// Windows must confirm the current capture stream has system AEC.
  /// Preserve the existing call-path behavior on Android.
  static bool canTalkOver({
    required bool requested,
    required TargetPlatform platform,
    required bool aecActive,
  }) => ConversationSession.canTalkOver(
    requested: requested,
    platform: platform,
    aecActive: aecActive,
  );

  /// Reading sizes of the Conversation screen: larger than chat so the
  /// answer reads from arm's length.
  static const answerFontSize = 22.0;
  static const captionFontSize = 18.0;

  /// [ConversationSession.spokenStyle].
  static const spokenStyle = ConversationSession.spokenStyle;

  /// [ConversationSession.spokenStyleRemote].
  static const spokenStyleRemote = ConversationSession.spokenStyleRemote;

  /// [ConversationSession.styled].
  static String styled(String style, int most) =>
      ConversationSession.styled(style, most);

  /// [ConversationSession.turnSettingsFor].
  static Map<String, Object> turnSettingsFor(int most) =>
      ConversationSession.turnSettingsFor(most);

  /// [ConversationSession.turnSettings].
  static const turnSettings = ConversationSession.turnSettings;

  /// [ConversationSession.maxAnswerTokens].
  static const maxAnswerTokens = ConversationSession.maxAnswerTokens;

  /// [ConversationSession.keepsHolding].
  static bool keepsHolding({
    required bool holding,
    required bool hearing,
    required Duration heldFor,
  }) => ConversationSession.keepsHolding(
    holding: holding,
    hearing: hearing,
    heldFor: heldFor,
  );

  /// [ConversationSession.maxHold].
  static const maxHold = ConversationSession.maxHold;

  /// [ConversationSession.echoOf].
  static bool echoOf(
    String text,
    List<String> said, {
    required bool duringSpeech,
  }) => ConversationSession.echoOf(text, said, duringSpeech: duringSpeech);

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen>
    with WidgetsBindingObserver {
  /// The Riverpod wiring the [ConversationSession] reads through.
  late final _SessionWiring _wiring;
  late final ConversationSession _session;

  /// The whole exchange, scrollable: the user's words and the answers.
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    ConversationScreen.open = true;
    // Muted from the first frame: a pause and resume while the model loads
    // must not open the microphone either.
    _wiring = _SessionWiring(this);
    _session = ConversationSession(
      wiring: _wiring,
      listen: widget.listen,
      changed: _rebuild,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_session.start()),
    );
  }

  /// Rebuilds the widgets after the session changed what it shows.
  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// Out of sight (Home, the lock screen, another app): the answer stops
  /// and the microphone closes; it listens again on return (audit C7).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _session.didChangeLifecycle(state);

  /// End (the button, the X or back): silence and stop the answer at once,
  /// not after the page has slid away.
  void _end() {
    _session.end();
    unawaited(Navigator.of(context).maybePop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.dispose();
    _scroll.dispose();
    ConversationScreen.open = false;
    super.dispose();
  }

  /// Another model picked from the top bar: loaded between turns.
  Future<void> _pickModel() async {
    final l10n = context.l10n;
    if (!await showConversationModelPicker(context, ref) || _session.closed) {
      return;
    }
    if (_session.turn) return; // loaded at the start of the next conversation
    await _session.prepareModel(l10n);
  }

  /// The exchange so far: the user's words in a soft bubble, the answers
  /// as large text with the sentence being spoken lit up. It follows new
  /// words unless the user scrolled up to read.
  Widget _transcript(BuildContext context) {
    final c = context.colors;
    final lines = [
      ..._session.lines,
      if (_session.userCaption.isNotEmpty)
        ConversationLine(true, _session.userCaption, live: true),
    ];
    if (_session.follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients || _session.closed) return;
        final end = _scroll.position.maxScrollExtent;
        if (_scroll.offset < end - 1) {
          unawaited(
            _scroll.glideTo(end, context.motion, duration: AppMotion.track),
          );
        }
      });
    }
    final answerStyle = context.text.body.copyWith(
      color: c.text,
      fontSize: ConversationScreen.answerFontSize,
      height: 1.45,
    );
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification && n.dragDetails != null) {
          _session.follow = n.metrics.pixels >= n.metrics.maxScrollExtent - 32;
        } else if (n is ScrollEndNotification &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 32) {
          _session.follow = true;
        }
        return false;
      },
      child: ShaderMask(
        // The top lines fade out under the wave.
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
          stops: [0, 0.08],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          key: const Key('conversation-transcript'),
          controller: _scroll,
          padding: const EdgeInsets.only(
            top: AppDesign.lg,
            bottom: AppDesign.md,
          ),
          itemCount: lines.length,
          itemBuilder: (context, i) {
            final line = lines[i];
            if (line.user) {
              return Align(
                alignment: Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.only(
                    left: AppDesign.xl * 2,
                    top: AppDesign.md,
                    bottom: AppDesign.md,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesign.lg,
                    vertical: AppDesign.md,
                  ),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    line.text,
                    key: line.live
                        ? const Key('conversation-user-caption')
                        : null,
                    style: context.text.body.copyWith(
                      color: line.live ? c.textMuted : c.text,
                      fontSize: ConversationScreen.captionFontSize,
                      height: 1.35,
                      fontStyle: line.live ? FontStyle.italic : null,
                    ),
                  ),
                ),
              );
            }
            final last = i == _session.lines.length - 1;
            if (line.text.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppDesign.sm),
                child: Text(
                  '…',
                  style: answerStyle.copyWith(color: c.textFaint),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppDesign.sm),
              child: Text.rich(
                _spoken(
                  line.text,
                  last && _session.phase == ConversationPhase.speaking
                      ? _session.assistantCaption
                      : '',
                  answerStyle,
                  c,
                ),
                key: last ? const Key('conversation-assistant-caption') : null,
              ),
            );
          },
        ),
      ),
    );
  }

  /// [text] with the sentence being spoken in full colour and the rest a
  /// little quieter; all of it plain once the answer has been said.
  static TextSpan _spoken(
    String text,
    String now,
    TextStyle style,
    AppColors c,
  ) {
    final at = now.isEmpty ? -1 : text.indexOf(now.trim());
    if (at < 0) return TextSpan(text: text, style: style);
    final end = at + now.trim().length;
    final quiet = style.copyWith(color: c.textMuted);
    return TextSpan(
      children: [
        TextSpan(text: text.substring(0, at), style: quiet),
        TextSpan(text: text.substring(at, end), style: style),
        TextSpan(text: text.substring(end), style: quiet),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.l10n;
    ref.listen(chatProvider, _session.onChat);
    // System voice: when the answer has been read, listen again.
    ref.listen(voiceProvider.select((v) => v.speaking), (was, now) {
      if (!_session.natural && was == true && !now && !_session.turn) {
        _session.listenSystem();
      }
    });
    final packs = ref.watch(voiceModelsProvider);
    final modelName = _session.remote
        ? _session.remoteName
        : ref
              .watch(modelManagerProvider.select((m) => m.catalog))
              .where((m) => m.id == _session.modelId)
              .firstOrNull
              ?.displayName;
    final status = switch (_session.phase) {
      ConversationPhase.starting => '',
      ConversationPhase.idle => _session.muted ? t.convPaused : t.convHint,
      ConversationPhase.listening => t.convListening,
      ConversationPhase.thinking =>
        _session.lookingUp ? t.convLookingUp : t.convThinking,
      ConversationPhase.speaking =>
        _session.natural && !_session.canTalkOverNow
            ? t.convSpeakingTap
            : t.convSpeaking,
    };
    final downloading =
        VoiceModels.packsFor(ref.read(settingsProvider).readingVoice).any(
          (p) =>
              packs.of(p).status != VoicePackStatus.missing &&
              packs.of(p).status != VoicePackStatus.ready,
        );
    return Scaffold(
      key: const Key('conversation-screen'),
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        toolbarHeight: 64,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.conversationTitle, style: context.text.headline),
            if (modelName != null)
              Text(
                modelName,
                key: const Key('conversation-model-name'),
                style: context.text.label.copyWith(color: c.textMuted),
              ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('conversation-model-pick'),
            tooltip: t.convModelTitle,
            icon: const Icon(Icons.tune),
            onPressed: _pickModel,
          ),
          const SizedBox(width: AppDesign.xs),
        ],
        leading: IconButton(
          key: const Key('conversation-close'),
          tooltip: t.convEnd,
          iconSize: 26,
          icon: const Icon(Icons.close),
          onPressed: _end,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDesign.lg),
          child: Column(
            children: [
              if (_session.notice != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppDesign.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_session.notice!, style: context.text.bodyMuted),
                        if (!_session.natural &&
                            (!packs.canListen ||
                                !packs.canSpeakWith(
                                  ref.read(settingsProvider).readingVoice,
                                ))) ...[
                          const SizedBox(height: AppDesign.sm),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonalIcon(
                              key: const Key('conversation-get-voice'),
                              onPressed: downloading
                                  ? null
                                  : () {
                                      final n = ref.read(
                                        voiceModelsProvider.notifier,
                                      );
                                      unawaited(() async {
                                        for (final p in VoiceModels.packsFor(
                                          ref
                                              .read(settingsProvider)
                                              .readingVoice,
                                        )) {
                                          if (!packs.of(p).isReady) {
                                            await n.download(p);
                                          }
                                        }
                                      }());
                                    },
                              icon: downloading
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.download_outlined),
                              label: Text(t.voiceDownloadBoth),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final talk =
                        _session.lines.isNotEmpty ||
                        _session.userCaption.isNotEmpty;
                    return Column(
                      children: [
                        AnimatedContainer(
                          duration: context.motion.fade(AppMotion.glide),
                          curve: AppMotion.ease,
                          height: talk
                              ? math.min(150, box.maxHeight * 0.3)
                              : box.maxHeight,
                          alignment: Alignment.center,
                          child: GestureDetector(
                            key: const Key('conversation-orb'),
                            onTap: _session.tapOrb,
                            child: Wave(
                              phase: _session.phase,
                              level: _session.levelNow,
                              muted: _session.muted,
                            ),
                          ),
                        ),
                        if (talk) Expanded(child: _transcript(context)),
                      ],
                    );
                  },
                ),
              ),
              if (_session.lines.isEmpty && _session.userCaption.isEmpty)
                _Caption(
                  key: const Key('conversation-assistant-caption'),
                  text: _session.assistantCaption,
                  maxLines: 3,
                  style: context.text.body.copyWith(
                    color: c.textMuted,
                    fontSize: ConversationScreen.captionFontSize,
                    height: 1.4,
                  ),
                ),
              if (_session.actions.isNotEmpty) ...[
                const SizedBox(height: AppDesign.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: PhoneActionCards(actions: _session.actions),
                  ),
                ),
              ],
              const SizedBox(height: AppDesign.lg),
              Text(
                status,
                style: context.text.body.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
              const SizedBox(height: AppDesign.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BigButton(
                    label: _session.muted ? t.convUnmute : t.convMute,
                    child: IconButton.filledTonal(
                      key: const Key('conversation-mute'),
                      tooltip: _session.muted ? t.convUnmute : t.convMute,
                      iconSize: 28,
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(_BigButton.size),
                      ),
                      onPressed: _session.phase == ConversationPhase.starting
                          ? null
                          : _session.toggleMute,
                      icon: Icon(_session.muted ? Icons.mic_off : Icons.mic),
                    ),
                  ),
                  const SizedBox(width: AppDesign.md),
                  _BigButton(
                    label: t.convStopAnswer,
                    child: IconButton.filledTonal(
                      key: const Key('conversation-stop'),
                      tooltip: t.convStopAnswer,
                      iconSize: 30,
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(_BigButton.size),
                      ),
                      onPressed: _session.answering
                          ? () {
                              AppHaptics.tick();
                              _session.stopAnswer();
                            }
                          : null,
                      icon: const Icon(Icons.stop_rounded),
                    ),
                  ),
                  const SizedBox(width: AppDesign.md),
                  _BigButton(
                    label: t.convEnd,
                    child: IconButton.filled(
                      key: const Key('conversation-end'),
                      tooltip: t.convEnd,
                      iconSize: 30,
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(_BigButton.size),
                        backgroundColor: c.danger,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _end,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDesign.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// The screen's Riverpod wiring, read through by its [ConversationSession].
class _SessionWiring implements ConversationWiring {
  _SessionWiring(this._screen)
    : chat = _screen.ref.read(chatProvider.notifier),
      voice = _screen.ref.read(voiceProvider.notifier);

  final _ConversationScreenState _screen;

  @override
  final ChatNotifier chat;

  @override
  final VoiceNotifier voice;

  @override
  ChatState get chatState => _screen.ref.read(chatProvider);

  @override
  VoiceState get voiceState => _screen.ref.read(voiceProvider);

  @override
  InferenceSettings get settings => _screen.ref.read(settingsProvider);

  @override
  VoiceModelsState get packs => _screen.ref.read(voiceModelsProvider);

  @override
  SherpaVoice get sherpa => _screen.ref.read(sherpaVoiceProvider);

  @override
  ModelManagerState get models => _screen.ref.read(modelManagerProvider);

  @override
  LlamaEngine get engine => _screen.ref.read(llamaEngineProvider);

  @override
  ModelManagerNotifier get modelManager =>
      _screen.ref.read(modelManagerProvider.notifier);

  @override
  bool get mounted => _screen.mounted;

  @override
  AppLocalizations get l10n => _screen.context.l10n;

  @override
  Future<void> pinModel(String chatId, String modelId) =>
      _screen.ref.read(chatModelPinsProvider.notifier).set(chatId, modelId);
}

extension on VoicePackState {
  bool get isReady => status == VoicePackStatus.ready;
}
