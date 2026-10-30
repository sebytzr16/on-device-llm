import '../../inference/ffi/llama_bindings.dart';
import 'l10n.dart';

String? cpuVariantFallback(AppLocalizations t, Map<String, dynamic> metrics) {
  final variant = LlamaBindings.windowsCpuOf(
    metrics['nativeLibrary'] as String?,
  );
  if (variant == null) return null;
  final skipped = (metrics['nativeLibrarySkipped'] as List? ?? []).join('\n');
  final label = variant == 'compat' ? t.avx512Compat : variant.toUpperCase();
  if (skipped.contains('trying the next CPU')) {
    return t.avx512LoadFallback(label);
  }
  if (skipped.contains('OS reports')) return t.avx512OsFallback(label);
  return null;
}
