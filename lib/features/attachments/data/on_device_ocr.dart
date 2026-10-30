import 'package:flutter/services.dart';
import '../domain/scan_options.dart';

class OnDeviceOcr {
  static const channel = MethodChannel('ondevice_llm/ocr');
  static Future<OcrReading> recognize(String path, ScanOptions options) async {
    Map<String, dynamic>? result;
    try {
      result = await channel.invokeMapMethod<String, dynamic>('recognize', {
        'path': path,
        'language': options.language,
      });
    } on MissingPluginException {
      throw const OcrUnavailable();
    } on PlatformException catch (error) {
      if (error.code == 'ocr_unavailable') throw const OcrUnavailable();
      rethrow;
    }
    if (result == null) {
      throw StateError('Text recognition returned no result.');
    }
    return OcrReading.fromJson(result);
  }
}
