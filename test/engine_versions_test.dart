import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/engine_versions.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/advanced_pages.dart';
import 'package:ondevice_llm/features/settings/presentation/widgets/engine_versions_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings();
  }

  @override
  Future<void> update(InferenceSettings next) async => state = next;
}

String _release(String tag) => jsonEncode({'tag_name': tag});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('pins match native/REVISION and the fetch scripts', () {
    expect(
      File('native/REVISION').readAsStringSync().trim(),
      EnginePins.llamaCppCommit,
    );
    expect(
      File('scripts/bootstrap.ps1').readAsStringSync(),
      contains('--branch ${EnginePins.llamaCppTag} '),
    );
    expect(
      File('scripts/fetch-stable-diffusion.ps1').readAsStringSync(),
      contains(EnginePins.sdCommit),
    );
  });

  group('backend label', () {
    test('loaded library wins', () {
      expect(
        resolveBackendLabel(
          library: r'C:\app\ondevice_llm_cuda.dll',
          selected: 'auto',
        ),
        'CUDA (ondevice_llm_cuda.dll)',
      );
    });
    test('selected, then detected, then unknown', () {
      expect(resolveBackendLabel(selected: 'vulkan'), 'Vulkan');
      expect(
        resolveBackendLabel(
          selected: 'auto',
          hardware: {
            'devices': [
              {'type': 'cpu', 'backend': 'CPU'},
              {'type': 'gpu', 'backend': 'OpenCL'},
            ],
          },
        ),
        'OpenCL',
      );
      expect(
        resolveBackendLabel(
          selected: 'auto',
          hardware: {
            'devices': [
              {'type': 'cpu', 'backend': 'CPU'},
            ],
          },
        ),
        'CPU',
      );
      expect(resolveBackendLabel(selected: 'auto'), 'Unknown');
    });
  });

  test('version parsing', () {
    expect(llamaBuildNumber('b12342'), 12342);
    expect(llamaBuildNumber('v1.2'), isNull);
    expect(
      cudaRuntimeFromFileNames(['a.dll', 'cublas64_13.dll', 'cudart64_12.dll']),
      '12',
    );
    expect(cudaRuntimeFromFileNames(['x.dll']), isNull);
    expect(parseNvidiaSmiDriver('581.15\r\n'), '581.15');
    expect(parseNvidiaSmiDriver('NVIDIA-SMI has failed'), isNull);
    expect(driverSupports('581.15', '580.65'), isTrue);
    expect(driverSupports('527.40', '527.41'), isFalse);
    expect(driverSupports(null, '527.41'), isNull);
    expect(minDriverForCudaMajor('12'), '527.41');
  });

  test('update check compares with a fake client', () async {
    final newer = await EngineUpdateChecker(
      fetch: (u) async => u.path.contains('llama.cpp')
          ? _release('b12400')
          : _release('master-1-6879155'),
    ).check();
    expect(newer[0].state, EngineUpdateState.newer);
    expect(newer[0].latest, 'b12400');
    expect(newer[1].state, EngineUpdateState.upToDate);

    final same = await EngineUpdateChecker(
      fetch: (u) async => u.path.contains('llama.cpp')
          ? _release(EnginePins.llamaCppTag)
          : _release('master-9-abcdef0'),
    ).check();
    expect(same[0].state, EngineUpdateState.upToDate);
    expect(same[1].state, EngineUpdateState.newer);

    final off = await EngineUpdateChecker(
      fetch: (_) async => throw const SocketException('offline'),
    ).check();
    expect(off.every((i) => i.state == EngineUpdateState.offline), isTrue);
  });

  testWidgets('hardware page shows CUDA, not Unknown, and checks updates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          detectedHardwareProvider.overrideWith(
            (ref) async => {
              'ramTotalMb': 16000,
              'devices': [
                {'type': 'cpu', 'description': 'CPU', 'backend': 'CPU'},
                {
                  'type': 'gpu',
                  'description': 'RTX',
                  'backend': 'CUDA',
                  'totalMb': 8192,
                },
              ],
            },
          ),
          loadedEngineLibraryProvider.overrideWithValue(
            'ondevice_llm_cuda.dll',
          ),
          engineRuntimeInfoProvider.overrideWith(
            (ref) async => const EngineRuntimeInfo(
              cudaRuntimeMajor: '12',
              driverVersion: '581.15',
            ),
          ),
          engineUpdateCheckerProvider.overrideWithValue(
            EngineUpdateChecker(
              fetch: (u) async => _release(
                u.path.contains('llama.cpp') ? 'b12400' : 'master-1-6879155',
              ),
            ),
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const HardwarePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CUDA (ondevice_llm_cuda.dll)'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
    await tester.tap(find.text('Check for engine updates'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Newer llama.cpp available: b12400'),
      findsOneWidget,
    );
    expect(find.textContaining('supports CUDA 12'), findsOneWidget);
  });
}
