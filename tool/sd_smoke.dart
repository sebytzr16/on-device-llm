// Desktop image/video acceptance probe: the app's SdEngine, run from a shell.
//   $env:PATH = "$PWD\native\out\windows-x64;$env:PATH"
//   dart run tool/sd_smoke.dart <models dir> <model id> <out file> "<prompt>" [key=value…]
// Writes a PNG for a picture; for a video, an .avi plus the first frame as PNG.
import 'dart:io';
import 'dart:typed_data';

import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';
import 'package:ondevice_llm/inference/engine/sd_engine.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.length < 4) {
    stderr.writeln(
      'usage: sd_smoke <models dir> <model id> <out> <prompt> [k=v…]',
    );
    exit(64);
  }
  final [dir, id, out, prompt, ...rest] = args;
  final model = imageGenCatalog.firstWhere((m) => m.id == id);
  // `load.flashAttn=0` style keys override a load setting (0/1 for flags).
  final extra = {
    for (final kv in rest) kv.split('=').first: num.parse(kv.split('=').last),
  };
  final loadOverrides = {
    for (final k in [...extra.keys.where((k) => k.startsWith('load.'))])
      k.substring(5): extra.remove(k) != 0,
  };
  final paths = {for (final f in model.files) f.role: p.join(dir, f.fileName)};
  final video = model.kind == ImageGenKind.video;
  final engine = SdEngine();
  final clock = Stopwatch()..start();
  try {
    await engine.load(
      key: model.id,
      vaePath: paths[ImageGenRole.vae] ?? '',
      settings: {...model.loadSettings(paths), ...loadOverrides},
    );
    stdout.writeln('loaded in ${clock.elapsed.inSeconds} s');
    clock.reset();
    var last = -1;
    final want = (
      width: (extra.remove('width') ?? model.width).toInt(),
      height: (extra.remove('height') ?? model.height).toInt(),
    );
    final plan = video
        ? (width: want.width, height: want.height, upscale: 1)
        : pictureSizePlan(want.width, want.height);
    var result = await engine.generate(
      {
        'prompt': prompt,
        'width': plan.width,
        'height': plan.height,
        'steps': model.steps,
        'cfgScale': model.cfgScale,
        'seed': 42,
        'sampler': model.sampler,
        ...model.samplerExtras,
        if (video) ...{'frames': model.frames, 'fps': model.fps},
        ...extra,
      },
      video: video,
      onProgress: (step, total) {
        if (step != last) stdout.writeln('step $step/$total');
        last = step;
      },
    );
    stdout.writeln(
      'drew ${result.width}x${result.height} in ${clock.elapsed.inSeconds} s',
    );
    if (plan.upscale > 1) {
      clock.reset();
      result = await engine.upscale(paths[ImageGenRole.upscaler]!, result);
      stdout.writeln('enlarged in ${clock.elapsed.inSeconds} s');
    }
    if (!video) result = result.cropCentre(want.width, want.height);
    stdout.writeln(
      'generated ${result.width}x${result.height}x${result.frames} '
      'in ${clock.elapsed.inSeconds} s',
    );
    final png = video ? p.setExtension(out, '.png') : out;
    File(
      png,
    ).writeAsBytesSync(_png(result.frame(0), result.width, result.height));
    if (video) await engine.saveVideo(out, result);
    stdout.writeln('wrote $out');
  } finally {
    await engine.dispose();
  }
}

/// A minimal RGBA PNG: one IDAT, no filtering.
Uint8List _png(Uint8List rgba, int w, int h) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    raw.add(Uint8List.sublistView(rgba, y * w * 4, (y + 1) * w * 4));
  }
  final out = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    out
      ..add(_u32(data.length))
      ..add(body)
      ..add(_u32(_crc(body)));
  }

  chunk('IHDR', [..._u32(w), ..._u32(h), 8, 6, 0, 0, 0]);
  chunk('IDAT', ZLibCodec().encode(raw.takeBytes()));
  chunk('IEND', const []);
  return out.takeBytes();
}

List<int> _u32(int v) => [v >> 24 & 255, v >> 16 & 255, v >> 8 & 255, v & 255];

int _crc(List<int> bytes) {
  var c = 0xffffffff;
  for (final b in bytes) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = c & 1 != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
  }
  return c ^ 0xffffffff;
}
