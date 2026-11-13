import 'dart:convert';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/ffi/llama_bindings.dart';

void main() {
  final library = Platform.environment['OD_CONTEXT_FIT_LIBRARY'];
  final model = Platform.environment['OD_CONTEXT_FIT_MODEL'];
  test(
    'trained context cap fits the same GPU placement as an explicit context',
    () {
      final api = LlamaBindings(libraryPath: library!);
      final options = '{}'.toNativeUtf8();
      final runtime = api.create(options);
      calloc.free(options);
      final path = model!.toNativeUtf8();
      Map<String, dynamic> estimate(int context, {bool guard = true}) {
        final settings = jsonEncode({
          'backend': Platform.environment['OD_CONTEXT_FIT_BACKEND'] ?? 'cuda',
          'nGpuLayers': 999,
          'contextSize': context,
          'memoryGuard': guard,
        }).toNativeUtf8();
        try {
          final result = api.estimate!(runtime, path, settings);
          expect(
            result.address,
            isNot(0),
            reason: api.error(runtime).toDartString(),
          );
          return jsonDecode(result.toDartString()) as Map<String, dynamic>;
        } finally {
          calloc.free(settings);
        }
      }

      try {
        expect(api.estimate, isNotNull);
        const requested = 1 << 20;
        final capped = estimate(requested);
        final context = capped['contextSize'] as int;
        expect(context, lessThan(requested));
        expect(capped['contextRequested'], requested);
        // The fixture needs enough host RAM for the trained context, and a
        // trained length below 1M so the request exercises the cap.
        expect(capped['contextCap'], 'train');
        expect(context, capped['contextTrain']);
        expect(capped['gpuFit'], 'fit');
        // With admission disabled, this independently fits exactly the final
        // context. Use a model/card where the larger cache spills layers.
        final direct = estimate(context, guard: false);
        expect(direct['contextSize'], context);
        expect(capped['gpuLayers'], direct['gpuLayers']);
        expect(capped['gpuExpertsOnCpu'], direct['gpuExpertsOnCpu']);
        expect(capped['vramNeedMb'], direct['vramNeedMb']);
      } finally {
        calloc.free(path);
        api.destroy(runtime);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: library == null || model == null
        ? 'Set OD_CONTEXT_FIT_LIBRARY and OD_CONTEXT_FIT_MODEL for offline GPU integration.'
        : false,
  );
}
