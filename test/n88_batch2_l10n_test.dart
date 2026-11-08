import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/features/chat/domain/export/document_draft_service.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/conversations_sheet.dart';
import 'package:ondevice_llm/features/helper/helper_live_panel.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/widgets/settings_labels.dart';

void main() {
  test('all ARBs have matching messages and placeholder metadata', () {
    final en =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
    final keys = en.keys.where((key) => !key.startsWith('@')).toSet();
    for (final locale in ['fr', 'es']) {
      final translated =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map;
      expect(
        translated.keys.where((key) => !key.startsWith('@')).toSet(),
        keys,
        reason: locale,
      );
      for (final key in keys) {
        final metadata = en['@$key'] as Map?;
        if (metadata?['placeholders'] case final Map placeholders) {
          for (final name in placeholders.keys) {
            expect(
              translated[key],
              contains('{$name'),
              reason: '$locale $key $name',
            );
          }
        }
      }
    }
  });

  test('count messages cover zero, one and many in each locale', () {
    for (final locale in ['en', 'fr', 'es']) {
      final t = stringsFor(locale);
      for (final count in [0, 1, 2]) {
        expect(
          t.sourceReferenceSponsoredCount(count, count),
          contains('$count'),
        );
        expect(t.effectiveOverrideSummary(count), contains('$count'));
        expect(
          t.effectiveLayerSettingCount(count, 'topP', '…'),
          endsWith('topP…'),
        );
        expect(
          t.knowledgeDocumentStats(count, '5', '2026-11-07'),
          contains('5k'),
        );
        expect(t.settingsToolsSummary(count, '', '', ''), contains('$count'));
        expect(t.settingsOverrideCount(count), contains('$count'));
        expect(t.settingsAdaptersSummary(count, count), contains('$count'));
        expect(
          t.settingsReasoningSummary('auto', count, count, count, 10),
          contains('$count'),
        );
      }
    }
    expect(
      stringsFor('fr').sourceReferenceSponsoredCount(1, 2),
      '1 référence · 2 sponsorisées',
    );
    expect(
      stringsFor('es').sourceReferenceSponsoredCount(2, 1),
      '2 referencias · 1 patrocinada',
    );
    expect(
      stringsFor(
        'fr',
      ).settingsHardwareSummary('cpu', 'all', 'auto', 'auto', 'fp16'),
      contains('toutes les couches'),
    );
    expect(
      stringsFor(
        'es',
      ).settingsHardwareSummary('cpu', 'one', 'auto', 'auto', 'fp16'),
      contains('1 capa'),
    );
  });

  test('display helpers consume French and Spanish localization', () async {
    for (final locale in ['fr', 'es']) {
      final t = stringsFor(locale);
      expect(backendLabel(GpuBackend.cpu, t), t.backendCpuOnly);
      expect(webModeShort(WebMode.always, t), t.webAlwaysShort);
      expect(kvCacheLabel(KvCacheType.q4_0, t), t.kvQ4SavesMoreRam);
      expect(
        threadsLabel(const InferenceSettings(), t),
        startsWith(t.threadsAutoCount(0).split('(').first),
      );
      for (final template in DocumentTemplate.values) {
        expect(
          DocumentDraftService.label(template, t),
          isNot(DocumentDraftService.label(template, stringsFor('en'))),
        );
      }
      final rows = helperMeasurementRows({
        'enabled': true,
        'disabled': false,
        'devices': [
          {'name': 'GPU'},
        ],
      }, t);
      expect(
        rows.map((row) => row.$2),
        containsAll([t.helperMeasurementYes, t.helperMeasurementNo]),
      );
      expect(rows, contains((t.helperMeasurementDevices, 'GPU')));
      final date = relativeTime(
        DateTime(2025, 1, 5),
        now: DateTime(2026, 11, 7),
        l10n: t,
      );
      expect(date, locale == 'fr' ? '5 janv. 2025' : '5 ene 2025');
    }
  });
}
