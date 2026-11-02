import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_design.dart';
import '../settings/presentation/widgets/settings_widgets.dart';
import '../../core/l10n/l10n.dart';
import '../settings/presentation/providers/settings_provider.dart';
import 'conversation_model.dart';
import 'voice_models.dart';
import 'voice_models_provider.dart';
import 'voice_pipeline.dart';
import 'voice_service.dart';
import '../../core/platform/form_factor.dart';

/// Settings › Voice: the on-device voice switch, its two downloads
/// (Whisper listening, Kokoro speaking) and the Kokoro speaker.
class NaturalVoiceSettings extends ConsumerWidget {
  const NaturalVoiceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final packs = ref.watch(voiceModelsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ConversationModelTile(),
        const _SpokenLengthTile(),
        const _ReadingSpeedTile(),
        SettingsSwitchRow(
          key: const Key('natural-voice'),
          secondary: const Icon(Icons.graphic_eq),
          title: Text(context.l10n.naturalVoiceTitle),
          subtitle: Text(
            (context.isDesktop
                ? context.l10n.naturalVoiceHintPc
                : context.l10n.naturalVoiceHint),
          ),
          value: s.naturalVoice,
          onChanged: (v) => n.update(s.copyWith(naturalVoice: v)),
        ),
        if (s.naturalVoice) ...[
          const _ReadingVoiceTile(),
          const _VoiceDownloadRow(),
          // Offered once the voice pack is in, or while Parakeet is.
          if (packs.of(VoiceModels.listening).status == VoicePackStatus.ready ||
              packs.of(VoiceModels.parakeet).status != VoicePackStatus.missing)
            const _ListeningModelTile(),
          if (packs.canSpeakWith(s.readingVoice)) const _VoicePicker(),
          SettingsSwitchRow(
            key: const Key('talk-over'),
            secondary: const Icon(Icons.record_voice_over_outlined),
            title: Text(context.l10n.talkOverTitle),
            subtitle: Text(
              (context.isDesktop
                  ? context.l10n.talkOverHintPc
                  : context.l10n.talkOverHint),
            ),
            value: s.talkOver,
            onChanged: (v) => n.update(s.copyWith(talkOver: v)),
          ),
        ],
      ],
    );
  }
}

int _mb(int bytes) => (bytes / (1024 * 1024)).round();

/// How long a spoken answer is: short (three sentences), longer (six) or
/// all of it (tester, 2026-10-19).
class _SpokenLengthTile extends ConsumerWidget {
  const _SpokenLengthTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final l10n = context.l10n;
    final choices = [
      (3, l10n.spokenLengthShort),
      (6, l10n.spokenLengthLonger),
      (0, l10n.spokenLengthFull),
    ];
    final chosen = choices.any((c) => c.$1 == s.spokenSentences)
        ? s.spokenSentences
        : 3;
    return SettingsRow(
      key: const Key('spoken-length'),
      leading: const Icon(Icons.short_text),
      title: Text(l10n.spokenLengthTitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.spokenLengthHint),
          const SizedBox(height: AppDesign.xs),
          Wrap(
            spacing: AppDesign.xs,
            runSpacing: AppDesign.xs,
            children: [
              for (final (most, label) in choices)
                ChoiceChip(
                  key: Key('spoken-length-$most'),
                  label: Text(label),
                  selected: chosen == most,
                  onSelected: (_) =>
                      n.update(s.copyWith(spokenSentences: most)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How fast answers are read aloud, for Kokoro and the system voice
/// (owner, 2026-11-01); the Try button plays it at the chosen pace.
class _ReadingSpeedTile extends ConsumerWidget {
  const _ReadingSpeedTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final speed = s.readingSpeed.clamp(0.6, 1.6);
    final label = '${speed.toStringAsFixed(1)}×';
    return SettingsRow(
      key: const Key('reading-speed'),
      leading: const Icon(Icons.speed),
      title: Text(context.l10n.readingSpeedTitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.readingSpeedHint),
          Slider(
            key: const Key('reading-speed-slider'),
            value: speed,
            min: 0.6,
            max: 1.6,
            divisions: 10,
            label: label,
            onChanged: (v) =>
                n.update(s.copyWith(readingSpeed: (v * 10).round() / 10)),
          ),
        ],
      ),
      trailing: Text(label),
    );
  }
}

/// The user can select before downloading, so the
/// existing download row offers exactly the chosen speaking pack.
class _ReadingVoiceTile extends ConsumerWidget {
  const _ReadingVoiceTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return SettingsRow(
      key: const Key('reading-voice'),
      leading: const Icon(Icons.record_voice_over_outlined),
      title: Text(context.l10n.readingVoiceTitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.readingVoiceHint),
          Wrap(
            spacing: AppDesign.xs,
            runSpacing: AppDesign.xs,
            children: [
              for (final (id, label) in [
                ('kokoro', 'Kokoro'),
                ('supertonic-2', 'Supertonic 2'),
              ])
                ChoiceChip(
                  key: Key('reading-$id'),
                  label: Text(label),
                  selected: s.readingVoice == id,
                  onSelected: (_) => ref
                      .read(settingsProvider.notifier)
                      .update(s.copyWith(readingVoice: id)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Both voice packs in one row: one download, one progress, one remove.
class _VoiceDownloadRow extends ConsumerWidget {
  const _VoiceDownloadRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final packs = ref.watch(voiceModelsProvider);
    final notifier = ref.read(voiceModelsProvider.notifier);
    final selectedPacks = VoiceModels.packsFor(
      ref.watch(settingsProvider).readingVoice,
    );
    final states = [for (final p in selectedPacks) packs.of(p)];
    final missing = [
      for (final p in selectedPacks)
        if (packs.of(p).status != VoicePackStatus.ready) p,
    ];
    final total = selectedPacks.fold(0, (a, p) => a + p.sizeBytes);
    final received = selectedPacks.fold(
      0,
      (a, p) =>
          a +
          (packs.of(p).status == VoicePackStatus.ready
              ? p.sizeBytes
              : packs.of(p).received),
    );
    final error = states.map((s) => s.error).whereType<String>().firstOrNull;
    final Widget action;
    if (states.any((s) => s.status == VoicePackStatus.unpacking)) {
      action = OutlinedButton(
        onPressed: null,
        child: Text(context.l10n.voiceUnpacking),
      );
    } else if (states.any((s) => s.status == VoicePackStatus.downloading)) {
      action = OutlinedButton.icon(
        key: const Key('voice-pause'),
        onPressed: () async {
          for (final p in selectedPacks) {
            await notifier.pause(p);
          }
        },
        icon: const Icon(Icons.pause, size: 18),
        label: Text('${(received * 100 / total).round()}%'),
      );
    } else if (missing.isEmpty) {
      action = OutlinedButton.icon(
        key: const Key('voice-remove'),
        onPressed: () async {
          for (final p in selectedPacks) {
            await notifier.delete(p);
          }
        },
        style: OutlinedButton.styleFrom(foregroundColor: c.success),
        icon: const Icon(Icons.check, size: 18),
        label: Text(context.l10n.ready),
      );
    } else {
      action = FilledButton.tonalIcon(
        key: const Key('voice-add'),
        onPressed: () async {
          // One after the other: Whisper first, so dictation works soonest.
          await notifier.downloadAll(missing);
        },
        icon: Icon(
          received > 0 || error != null
              ? Icons.refresh
              : Icons.download_outlined,
          size: 18,
        ),
        label: Text(
          context.l10n.downloadMb(
            _mb(missing.fold(0, (a, p) => a + p.sizeBytes)),
          ),
        ),
      );
    }
    return SettingsRow(
      key: const Key('voice-download'),
      leading: const Icon(Icons.download_for_offline_outlined),
      title: Text(
        '${context.l10n.voiceListeningPack} · ${ref.watch(settingsProvider).readingVoice == VoiceModels.supertonic.id ? context.l10n.supertonicSpeakingPack : context.l10n.voiceSpeakingPack}',
      ),
      // The button sits under the title: a long label (French, large text)
      // must not squeeze the tile.
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) Text(error, style: TextStyle(color: c.warning)),
          const SizedBox(height: AppDesign.xs),
          action,
        ],
      ),
    );
  }
}

/// Whisper base (in the voice pack) or Parakeet v3 (its own download).
/// Parakeet is chosen only once it is downloaded; until then Whisper
/// listens.
class _ListeningModelTile extends ConsumerWidget {
  const _ListeningModelTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final packs = ref.watch(voiceModelsProvider);
    final notifier = ref.read(voiceModelsProvider.notifier);
    const pack = VoiceModels.parakeet;
    final state = packs.of(pack);
    final ready = state.status == VoicePackStatus.ready;
    final parakeet = ready && s.listeningModel == VoiceModels.parakeetSetting;
    final Widget action = switch (state.status) {
      VoicePackStatus.ready => TextButton.icon(
        key: const Key('parakeet-remove'),
        onPressed: () async {
          await notifier.delete(pack);
          await n.update(s.copyWith(listeningModel: ''));
        },
        icon: const Icon(Icons.delete_outline, size: 18),
        label: Text(context.l10n.remove),
      ),
      VoicePackStatus.downloading => OutlinedButton.icon(
        key: const Key('parakeet-pause'),
        onPressed: () => notifier.pause(pack),
        icon: const Icon(Icons.pause, size: 18),
        label: Text('${(state.received * 100 / pack.sizeBytes).round()}%'),
      ),
      VoicePackStatus.unpacking => OutlinedButton(
        onPressed: null,
        child: Text(context.l10n.voiceUnpacking),
      ),
      VoicePackStatus.missing => FilledButton.tonalIcon(
        key: const Key('parakeet-add'),
        onPressed: () async {
          await notifier.download(pack);
          if (ref.read(voiceModelsProvider).of(pack).status ==
              VoicePackStatus.ready) {
            await n.update(
              ref
                  .read(settingsProvider)
                  .copyWith(listeningModel: VoiceModels.parakeetSetting),
            );
          }
        },
        icon: Icon(
          state.received > 0 || state.error != null
              ? Icons.refresh
              : Icons.download_outlined,
          size: 18,
        ),
        label: Text(context.l10n.downloadMb(_mb(pack.sizeBytes))),
      ),
    };
    return SettingsRow(
      key: const Key('listening-model'),
      leading: const Icon(Icons.hearing_outlined),
      title: Text(context.l10n.listeningModelTitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (context.isDesktop
                ? context.l10n.listeningModelHintPc
                : context.l10n.listeningModelHint),
          ),
          const SizedBox(height: AppDesign.xs),
          Wrap(
            spacing: AppDesign.xs,
            runSpacing: AppDesign.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                key: const Key('listening-whisper'),
                label: Text(context.l10n.listeningWhisper),
                selected: !parakeet,
                onSelected: (_) => n.update(s.copyWith(listeningModel: '')),
              ),
              ChoiceChip(
                key: const Key('listening-parakeet'),
                label: Text(context.l10n.listeningParakeet),
                selected: parakeet,
                onSelected: ready
                    ? (_) => n.update(
                        s.copyWith(listeningModel: VoiceModels.parakeetSetting),
                      )
                    : null,
              ),
              action,
            ],
          ),
          if (state.error != null)
            Text(state.error!, style: TextStyle(color: c.warning)),
        ],
      ),
    );
  }
}

/// The Kokoro speaker for the app language, with a sample.
class _VoicePicker extends ConsumerWidget {
  const _VoicePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final lang = voiceLanguage(s.localeCode);
    final supertonic = s.readingVoice == VoiceModels.supertonic.id;
    final voices = supertonic
        ? [
            for (var sid = 0; sid < 10; sid++)
              KokoroVoice(sid, lang, context.l10n.supertonicSpeaker(sid + 1)),
          ]
        : KokoroVoice.byLanguage[lang]!;
    final current = supertonic
        ? voices[s.supertonicSid.clamp(0, 9)]
        : KokoroVoice.forLanguage(
            lang,
            sid: s.kokoroSid < 0 ? null : s.kokoroSid,
          );
    return SettingsRow(
      key: const Key('kokoro-voice'),
      leading: const Icon(Icons.person_outline),
      title: Text(context.l10n.voicePick),
      subtitle: Wrap(
        spacing: AppDesign.xs,
        children: [
          for (final v in voices)
            ChoiceChip(
              label: Text(v.name),
              selected: v.sid == current.sid,
              onSelected: (_) => n.update(
                supertonic
                    ? s.copyWith(supertonicSid: v.sid)
                    : s.copyWith(kokoroSid: v.sid),
              ),
            ),
        ],
      ),
      trailing: TextButton.icon(
        key: const Key('kokoro-try'),
        onPressed: () => ref
            .read(voiceProvider.notifier)
            .speak(context.l10n.voiceSample, id: 'voice-sample'),
        icon: const Icon(Icons.play_arrow, size: 18),
        label: Text(context.l10n.voiceTry),
      ),
    );
  }
}
