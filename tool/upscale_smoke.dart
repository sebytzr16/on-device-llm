// Upscaler probe: the app's SdEngine.upscale on raw RGBA, run from a shell.
//   $env:PATH = "$PWD\native\out\windows-x64;$env:PATH"
//   dart run tool/upscale_smoke.dart <model .pth> <in.rgba> <width> <height> <out.rgba> [factor]
// Raw RGBA keeps this free of an image codec; convert with any tool.
import 'dart:io';

import 'package:ondevice_llm/inference/engine/sd_engine.dart';

Future<void> main(List<String> args) async {
  if (args.length < 5) {
    stderr.writeln(
      'usage: upscale_smoke <model> <in.rgba> <w> <h> <out.rgba> [factor]',
    );
    exit(64);
  }
  final [model, input, w, h, out, ...rest] = args;
  final factor = rest.isEmpty ? 2 : int.parse(rest.first);
  final picture = SdResult(
    File(input).readAsBytesSync(),
    int.parse(w),
    int.parse(h),
  );
  final engine = SdEngine();
  final clock = Stopwatch()..start();
  try {
    final result = await engine.upscale(model, picture, factor: factor);
    stdout.writeln(
      'upscaled to ${result.width}x${result.height} '
      'in ${clock.elapsedMilliseconds} ms',
    );
    File(out).writeAsBytesSync(result.rgba);
  } finally {
    await engine.dispose();
  }
}
