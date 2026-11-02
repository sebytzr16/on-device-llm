import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/device_info.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_capabilities.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_tags.dart';

void main() {
  // A laptop with 32 GB RAM, 8 GB RTX 3070, 14.6 GB free.
  const facts = <String, dynamic>{
    'ramAvailableMb': 14960,
    'ramTotalMb': 32468,
    'devices': [
      {'type': 'gpu', 'freeMb': 7000, 'totalMb': 8192},
    ],
  };

  test('desktop budget is installed RAM plus the card, not free RAM', () {
    expect(desktopMemoryMb(facts), (32468.0, 8192.0));
    expect(desktopMemoryMb(const {'ramAvailableMb': 4000}), (4000.0, 0.0));
  });

  test('26B and 35B MoE GGUFs fit RAM + VRAM', () {
    final (ram, vram) = desktopMemoryMb(facts);
    final memory = DeviceMemory(
      totalBytes: ((ram + vram) * 1048576).round(),
      availableBytes: 0,
      lowMemory: false,
    );
    ModelInfo gguf(String id, double gb) => ModelInfo(
      id: id,
      displayName: id,
      fileName: '$id.gguf',
      family: ModelFamily.other,
      quantization: ModelQuantization.unknown,
      sizeBytes: (gb * 1073741824).round(),
    );
    expect(modelFit(memory, gguf('gemma-4-26b-q4', 16.8)), ModelFit.fits);
    expect(modelFit(memory, gguf('qwen3.6-35b-a3b-q4', 21.2)), ModelFit.fits);
    expect(modelFit(memory, gguf('huge-70b', 40)), ModelFit.tooLarge);
  });
}
