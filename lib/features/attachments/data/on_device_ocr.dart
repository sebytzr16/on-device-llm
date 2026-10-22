import 'package:flutter/services.dart';
import '../domain/scan_options.dart';

class OnDeviceOcr {
  static const channel = MethodChannel('ondevice_llm/ocr');
  static Future<OcrReading> recognize(String path, ScanOptions options) async {
    final result = await channel.invokeMapMethod<String, dynamic>('recognize', {
      'path': path,
      'language': options.language,
    });
    if (result == null) {
      throw StateError('Text recognition returned no result.');
    }
    return OcrReading.fromJson(result);
  }
}
