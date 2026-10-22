import 'dart:io';

// Flutter includes the debug-only integration_test plugin in the generated
// Android registrant even though Gradle excludes it from release builds.
// Remove only that registration; keep JNI and every production plugin.
void main() {
  final file = File(
    'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
  );
  if (!file.existsSync()) {
    throw StateError('Run flutter pub get before preparing a release build.');
  }
  final original = file.readAsStringSync();
  if (!original.contains('com.github.dart_lang.jni.JniPlugin') ||
      !original.contains('com.github.dart_lang.jni_flutter.JniFlutterPlugin')) {
    throw StateError('Generated Android registrant is missing JNI plugins.');
  }
  final integrationRegistration = RegExp(
    r'^    try \{\r?\n'
    r'      flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\r?\n'
    r'    \} catch \(Exception e\) \{\r?\n'
    r'      Log\.e\(TAG, "Error registering plugin integration_test, dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin", e\);\r?\n'
    r'    \}\r?\n',
    multiLine: true,
  );
  final count = integrationRegistration.allMatches(original).length;
  if (count > 1) {
    throw StateError('Unexpected duplicate integration_test registrations.');
  }
  if (count == 1) {
    file.writeAsStringSync(original.replaceFirst(integrationRegistration, ''));
  }
}
