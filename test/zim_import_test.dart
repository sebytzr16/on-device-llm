import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/features/zim/zim_tile.dart';
import 'package:ondevice_llm/features/zim/zim_wikipedia.dart';

import 'local_backup_service_test.dart' show BackupPaths;

final class SlowZimFile extends PlatformFile {
  final Uint8List bytes;
  final copying = Completer<void>();
  final resume = Completer<void>();
  SlowZimFile(this.bytes);
  @override
  String get name => 'test.zim';
  @override
  Uri get uri => Uri.file('test.zim');
  @override
  int? lengthSync() => bytes.length;
  @override
  Future<int?> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() async* {
    copying.complete();
    yield Uint8List.sublistView(bytes, 0, 80);
    await resume.future;
    yield Uint8List.sublistView(bytes, 80);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ZimPicker extends FilePickerPlatform {
  final PlatformFile file;
  ZimPicker(this.file);
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => [file];
}

void main() {
  testWidgets('ZIM import completes after its tile is unmounted', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('zim-unmount-');
    final paths = PathProviderPlatform.instance;
    final picker = FilePickerPlatform.instance;
    final file = (await tester.runAsync(
      () async =>
          SlowZimFile(File('test/fixtures/zim/mini.zim').readAsBytesSync()),
    ))!;
    PathProviderPlatform.instance = BackupPaths(root.path, root.path);
    FilePickerPlatform.instance = ZimPicker(file);
    final container = ProviderContainer(
      overrides: [zimWikipediaProvider.overrideWith((ref) async => null)],
    );
    addTearDown(() {
      container.dispose();
      PathProviderPlatform.instance = paths;
      FilePickerPlatform.instance = picker;
      root.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ZimTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      tester
          .widget<TextButton>(find.byKey(const Key('zim-action')))
          .onPressed!();
      await file.copying.future.timeout(const Duration(seconds: 5));
    });
    await tester.pumpWidget(const SizedBox());
    final target = ZimWikipedia.fileIn(root.path);
    file.resume.complete();
    for (var i = 0; i < 100 && !File(target).existsSync(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(File(target).readAsBytesSync(), file.bytes);
    expect(File('$target.part').existsSync(), isFalse);
    expect(tester.takeException(), isNull);
    expect(p.basename(target), 'wikipedia.zim');
  });
}
