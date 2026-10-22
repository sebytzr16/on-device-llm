// GPU-02 access proof: can the *installed app* open the vendor OpenCL driver and
// enumerate a GPU? This deliberately uses no llama.cpp code so that driver
// access and backend build problems cannot be confused with each other.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

typedef _PlatformIdsC =
    Int32 Function(Uint32, Pointer<Pointer<Void>>, Pointer<Uint32>);
typedef _PlatformIdsD =
    int Function(int, Pointer<Pointer<Void>>, Pointer<Uint32>);
typedef _DeviceIdsC =
    Int32 Function(
      Pointer<Void>,
      Uint64,
      Uint32,
      Pointer<Pointer<Void>>,
      Pointer<Uint32>,
    );
typedef _DeviceIdsD =
    int Function(
      Pointer<Void>,
      int,
      int,
      Pointer<Pointer<Void>>,
      Pointer<Uint32>,
    );
typedef _InfoC =
    Int32 Function(Pointer<Void>, Uint32, Size, Pointer<Void>, Pointer<Size>);
typedef _InfoD =
    int Function(Pointer<Void>, int, int, Pointer<Void>, Pointer<Size>);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test('installed app can open the vendor OpenCL driver and see a GPU', () {
    final report = <String, Object?>{'platform': Platform.operatingSystem};
    late final DynamicLibrary lib;
    try {
      lib = DynamicLibrary.open('libOpenCL.so');
      report['dlopen'] = 'ok';
    } catch (e) {
      report['dlopen'] = '$e';
      // ignore: avoid_print
      print('OPENCL_PROBE: ${jsonEncode(report)}');
      fail('libOpenCL.so is not loadable from the app: $e');
    }
    final getPlatforms = lib.lookupFunction<_PlatformIdsC, _PlatformIdsD>(
      'clGetPlatformIDs',
    );
    final getDevices = lib.lookupFunction<_DeviceIdsC, _DeviceIdsD>(
      'clGetDeviceIDs',
    );
    final platformInfo = lib.lookupFunction<_InfoC, _InfoD>(
      'clGetPlatformInfo',
    );
    final deviceInfo = lib.lookupFunction<_InfoC, _InfoD>('clGetDeviceInfo');

    String str(_InfoD fn, Pointer<Void> id, int param) {
      final size = calloc<Size>();
      final buf = calloc<Uint8>(4096);
      try {
        final rc = fn(id, param, 4096, buf.cast(), size);
        if (rc != 0) return 'CL error $rc';
        return buf.cast<Utf8>().toDartString();
      } finally {
        calloc.free(size);
        calloc.free(buf);
      }
    }

    int num(_InfoD fn, Pointer<Void> id, int param) {
      final out = calloc<Uint64>();
      try {
        return fn(id, param, 8, out.cast(), nullptr) == 0 ? out.value : -1;
      } finally {
        calloc.free(out);
      }
    }

    final count = calloc<Uint32>();
    final ids = calloc<Pointer<Void>>(8);
    try {
      final rc = getPlatforms(8, ids, count);
      report['clGetPlatformIDs'] = rc;
      report['platforms'] = count.value;
      expect(rc, 0, reason: 'clGetPlatformIDs failed');
      expect(
        count.value,
        greaterThan(0),
        reason: 'driver reports no platforms',
      );
      final platform = ids[0];
      report['platformName'] = str(platformInfo, platform, 0x0902);
      report['platformVersion'] = str(platformInfo, platform, 0x0901);
      report['platformVendor'] = str(platformInfo, platform, 0x0903);
      final devCount = calloc<Uint32>();
      final devIds = calloc<Pointer<Void>>(8);
      try {
        final drc = getDevices(platform, 0xFFFFFFFF, 8, devIds, devCount);
        report['clGetDeviceIDs'] = drc;
        report['devices'] = devCount.value;
        expect(drc, 0, reason: 'clGetDeviceIDs failed');
        expect(devCount.value, greaterThan(0), reason: 'no OpenCL devices');
        final dev = devIds[0];
        report['deviceName'] = str(deviceInfo, dev, 0x102B);
        report['deviceVersion'] = str(deviceInfo, dev, 0x102F);
        report['driverVersion'] = str(deviceInfo, dev, 0x102D);
        report['openclCVersion'] = str(deviceInfo, dev, 0x103D);
        report['computeUnits'] = num(deviceInfo, dev, 0x1002) & 0xFFFFFFFF;
        report['globalMemMb'] = num(deviceInfo, dev, 0x101F) ~/ (1024 * 1024);
        report['maxAllocMb'] = num(deviceInfo, dev, 0x1010) ~/ (1024 * 1024);
        report['localMemKb'] = num(deviceInfo, dev, 0x1023) ~/ 1024;
        report['maxWorkGroup'] = num(deviceInfo, dev, 0x1004);
        final ext = str(deviceInfo, dev, 0x1030);
        report['extensions'] = ext
            .split(' ')
            .where((e) => e.isNotEmpty)
            .toList();
      } finally {
        calloc.free(devCount);
        calloc.free(devIds);
      }
    } finally {
      calloc.free(count);
      calloc.free(ids);
      // ignore: avoid_print
      print('OPENCL_PROBE: ${jsonEncode(report)}');
    }
  });
}
