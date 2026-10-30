import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import '../core/platform/desktop_host.dart';
import '../features/settings/presentation/providers/settings_provider.dart';
import '../inference/ffi/llama_bindings.dart';

class CpuVariantSetting extends ConsumerWidget {
  final bool Function()? hasAvx2;
  final bool Function()? hasAvx512;
  const CpuVariantSetting({super.key, this.hasAvx2, this.hasAvx512});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!DesktopHost.active) return const SizedBox.shrink();
    final t = context.l10n;
    final s = ref.watch(settingsProvider);
    final avx2 = (hasAvx2 ?? LlamaBindings.windowsHasAvx2)();
    final avx512 = (hasAvx512 ?? LlamaBindings.windowsHasAvx512)();
    final labels = {
      'auto': t.avx512Auto,
      'avx512': t.avx512Variant,
      'avx2': t.avx512Avx2,
      'compat': t.avx512Compat,
    };
    return ListTile(
      title: Text(t.avx512CpuVariant, style: context.text.body),
      subtitle: Text(
        t.avx512Detected(
          avx2 ? t.avx512Available : t.avx512Unavailable,
          avx512 ? t.avx512Available : t.avx512Unavailable,
        ),
      ),
      trailing: DropdownButton<String>(
        value: s.cpuVariant,
        items: [
          for (final e in labels.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) {
            ref
                .read(settingsProvider.notifier)
                .update(s.copyWith(cpuVariant: v));
          }
        },
      ),
    );
  }
}
