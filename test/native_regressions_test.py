"""Host-only native regressions; no Android build or device is involved.

Run: python test/native_regressions_test.py
Requires an MSVC developer shell and the cached Kotlin compiler.
"""
from pathlib import Path
import os
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build' / 'native-regressions'


def run(*args, **kwargs):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result


class NativeRegressions(unittest.TestCase):
    def test_smoke_dependencies_beside_executable(self):
        cc = 'cl.exe'
        app = OUT / 'app'
        pack = OUT / 'staging'
        app.mkdir(parents=True, exist_ok=True)
        pack.mkdir(parents=True, exist_ok=True)
        source = (ROOT / 'windows/runner/main.cpp').read_text()
        probe = source[source.index('namespace {'):source.index('int APIENTRY')]
        exports = re.findall(r"'([^']+)'", (ROOT / 'lib/inference/ffi/llama_bindings.dart')
                             .read_text().split('kBridgeExports = [', 1)[1].split('];', 1)[0])
        (OUT / 'probe.cpp').write_text(
            '#include <windows.h>\n#include <string>\n#include <algorithm>\n#include <cwctype>\n'
            'const char* kBridgeSmokeExports[] = {' + ','.join('"' + e + '"' for e in exports) + '};\n'
            + probe + '\nint wmain(int argc, wchar_t** argv) { return SmokeBridge(argc, argv); }\n')
        (OUT / 'dependency.cpp').write_text('extern "C" __declspec(dllexport) int dependency() { return 7; }')
        (OUT / 'bridge.cpp').write_text(
            'extern "C" __declspec(dllimport) int dependency();\n' + '\n'.join(
                f'extern "C" __declspec(dllexport) int {e}() {{ return dependency(); }}' for e in exports))
        dep = app / 'VCOMP140.DLL'
        run(cc, '/nologo', '/LD', '/MD', OUT / 'dependency.cpp', '/Fe:' + str(dep),
            '/Fo:' + str(OUT / 'dependency.obj'), '/link', '/IMPLIB:' + str(OUT / 'dependency.lib'))
        bridge = pack / 'ondevice_llm_cuda.dll'
        run(cc, '/nologo', '/LD', '/MD', OUT / 'bridge.cpp', OUT / 'dependency.lib',
            '/Fo:' + str(OUT / 'bridge.obj'), '/Fe:' + str(bridge))
        exe = app / 'probe.exe'
        run(cc, '/nologo', '/std:c++17', '/EHsc', '/MD', OUT / 'probe.cpp',
            '/Fo:' + str(OUT / 'probe.obj'), '/Fe:' + str(exe))
        # A staging DLL must find its imported runtime next to the executable.
        self.assertIn('"ok":true', run(exe, '--engine-smoke', bridge).stdout)
        hidden = app / 'VCOMP140.hidden'
        dep.rename(hidden)
        try:
            failed = subprocess.run([str(exe), '--engine-smoke', str(bridge)],
                                    capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn('"ok":false', failed.stdout)
        finally:
            hidden.rename(dep)
        # The pack's own dependency wins over the application copy.
        (OUT / 'dependency.cpp').write_text('extern "C" __declspec(dllexport) int dependency() { return 0; }')
        pack_dep = pack / 'VCOMP140.DLL'
        run(cc, '/nologo', '/LD', '/MD', OUT / 'dependency.cpp', '/Fe:' + str(pack_dep),
            '/Fo:' + str(OUT / 'dependency.obj'))
        try:
            failed = subprocess.run([str(exe), '--engine-smoke', str(bridge)],
                                    capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn('"ok":false', failed.stdout)
        finally:
            pack_dep.unlink()

    def test_dictation_late_final_timeout_and_immediate_stop(self):
        work = OUT / 'dictation'
        work.mkdir(parents=True, exist_ok=True)
        sources = {
            'manifest.kt': 'package android\nobject Manifest { object permission { const val RECORD_AUDIO = "mic" } }',
            'activity.kt': '''package android.app
class Activity {
 fun checkSelfPermission(p: String) = 0
 fun requestPermissions(p: Array<String>, r: Int) {}
}''',
            'intent.kt': '''package android.content
class Intent(action: String) { fun putExtra(k: String, v: Any): Intent = this }''',
            'pm.kt': 'package android.content.pm\nobject PackageManager { const val PERMISSION_GRANTED = 0 }',
            'os.kt': '''package android.os
object Build { object VERSION { const val SDK_INT = 35 }; object VERSION_CODES { const val S = 31 } }
class Bundle(val text: String = "") {
 fun getStringArrayList(k: String): ArrayList<String> = arrayListOf(text)
}
class Looper { companion object { fun getMainLooper() = Looper() } }
class Handler(looper: Looper) {
 companion object {
  var now = 0L
  val jobs = mutableMapOf<Runnable, Long>()
  fun advance(ms: Long) {
   now += ms
   jobs.filterValues { it <= now }.keys.toList().forEach { jobs.remove(it); it.run() }
  }
 }
 fun removeCallbacks(r: Runnable) { jobs.remove(r) }
 fun postDelayed(r: Runnable, ms: Long): Boolean { jobs[r] = now + ms; return true }
}''',
            'speech.kt': '''package android.speech
import android.os.Bundle
import android.app.Activity
import android.content.Intent
interface RecognitionListener {
 fun onReadyForSpeech(params: Bundle?)
 fun onBeginningOfSpeech()
 fun onRmsChanged(rmsdB: Float)
 fun onBufferReceived(buffer: ByteArray?)
 fun onEndOfSpeech()
 fun onEvent(eventType: Int, params: Bundle?)
 fun onPartialResults(results: Bundle?)
 fun onResults(results: Bundle?)
 fun onError(error: Int)
}
object RecognizerIntent {
 const val ACTION_RECOGNIZE_SPEECH = "action"
 const val EXTRA_LANGUAGE_MODEL = "model"
 const val LANGUAGE_MODEL_FREE_FORM = "free"
 const val EXTRA_PARTIAL_RESULTS = "partial"
 const val EXTRA_PREFER_OFFLINE = "offline"
 const val EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS = "silence"
 const val EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS = "possible"
 const val EXTRA_LANGUAGE = "language"
}
class SpeechRecognizer {
 companion object {
  lateinit var latest: SpeechRecognizer
  const val RESULTS_RECOGNITION = "results"
  const val ERROR_INSUFFICIENT_PERMISSIONS = 1
  const val ERROR_NO_MATCH = 2
  const val ERROR_SPEECH_TIMEOUT = 3
  const val ERROR_LANGUAGE_NOT_SUPPORTED = 4
  const val ERROR_LANGUAGE_UNAVAILABLE = 5
  fun isOnDeviceRecognitionAvailable(a: Activity) = true
  fun createOnDeviceSpeechRecognizer(a: Activity) = SpeechRecognizer().also { latest = it }
 }
 lateinit var listener: RecognitionListener
 var stopped = false
 var destroyed = false
 fun setRecognitionListener(l: RecognitionListener) { listener = l }
 fun startListening(i: Intent) {}
 fun stopListening() { stopped = true }
 fun cancel() {}
 fun destroy() { destroyed = true }
}''',
            'flutter.kt': '''package io.flutter.plugin.common
interface BinaryMessenger
class MethodCall(val method: String, val arguments: Map<String, Any> = emptyMap()) {
 @Suppress("UNCHECKED_CAST") fun <T> argument(k: String): T? = arguments[k] as T?
}
class MethodChannel(m: BinaryMessenger, name: String) {
 companion object { val events = mutableListOf<Pair<String, Any?>>() }
 interface MethodCallHandler { fun onMethodCall(call: MethodCall, result: Result) }
 interface Result { fun success(v: Any?); fun error(c: String, m: String?, d: Any?); fun notImplemented() }
 fun setMethodCallHandler(h: MethodCallHandler?) {}
 fun invokeMethod(m: String, args: Any?) { events.add(m to args) }
}''',
            'test.kt': '''import android.app.Activity
import android.os.*
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.*
import app.ondevicellm.ondevice_llm.OfflineDictation
fun main() {
 val dictation = OfflineDictation(Activity(), object : BinaryMessenger {})
 val result = object : MethodChannel.Result {
  override fun success(v: Any?) {}
  override fun error(c: String, m: String?, d: Any?) { error(c) }
  override fun notImplemented() { error("unexpected method") }
 }
 var token = 0
 fun start(): SpeechRecognizer {
  MethodChannel.events.clear()
  dictation.onMethodCall(MethodCall("listen", mapOf("session" to ++token)), result)
  return SpeechRecognizer.latest
 }
 fun finalText(): String? = MethodChannel.events.filter { it.first == "result" }
  .map { it.second as Map<*, *> }.lastOrNull { it["final"] == true }?.get("text") as String?
 // No partial: a final later than the old 500 ms endpoint must survive.
 var engine = start()
 engine.listener.onEndOfSpeech()
 check(engine.stopped)
 Handler.advance(1000)
 check(!engine.destroyed && finalText() == null)
 engine.listener.onResults(Bundle("late final"))
 check(engine.destroyed && finalText() == "late final")
 Handler.advance(3000)
 check(finalText() == "late final")
 // A speech deadline near expiry must not cut the grace period short.
 engine = start()
 Handler.advance(5900)
 engine.listener.onPartialResults(Bundle("partial"))
 engine.listener.onEndOfSpeech()
 Handler.advance(1000)
 check(!engine.destroyed && finalText() == null)
 Handler.advance(2000)
 check(engine.destroyed && finalText() == "partial")
 // Manual stop remains synchronous, even during the final-result wait.
 engine = start()
 engine.listener.onPartialResults(Bundle("stop text"))
 engine.listener.onEndOfSpeech()
 dictation.onMethodCall(MethodCall("stop"), result)
 check(engine.destroyed && finalText() == "stop text")
 engine.listener.onResults(Bundle("stale"))
 check(finalText() == "stop text")
 engine = start()
 engine.listener.onEndOfSpeech()
 engine.listener.onError(SpeechRecognizer.ERROR_NO_MATCH)
 check(engine.destroyed && Handler.jobs.isEmpty())
 println("dictation regressions passed")
}''',
        }
        for name, source in sources.items():
            (work / name).write_text(source)
        cache = Path(os.environ['USERPROFILE']) / '.gradle/caches/modules-2/files-2.1'
        jars = []
        for package, artifact, version in [
            ('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.3.20'),
            ('org.jetbrains.kotlin', 'kotlin-stdlib', '2.3.20'),
            ('org.jetbrains.kotlin', 'kotlin-script-runtime', '2.3.20'),
            ('org.jetbrains.kotlin', 'kotlin-reflect', '2.3.0'),
            ('org.jetbrains.kotlin', 'kotlin-daemon-embeddable', '2.3.20'),
            ('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.9.0'),
            ('org.jetbrains', 'annotations', '13.0'),
        ]:
            jars.extend(p for p in (cache / package / artifact / version).rglob('*.jar')
                        if not p.name.endswith(('-sources.jar', '-javadoc.jar')))
        cp = os.pathsep.join(str(p) for p in jars)
        java = Path(os.environ.get('JAVA_HOME', 'C:/Program Files/Java/jdk-26.0.1')) / 'bin/java.exe'
        classes = work / 'classes'
        kotlin = ROOT / 'android/app/src/main/kotlin/app/ondevicellm/ondevice_llm/OfflineDictation.kt'
        run(java, '-cp', cp, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
            '-no-stdlib', '-no-reflect', '-classpath', cp, '-d', classes,
            *[work / name for name in sources], kotlin)
        self.assertIn('dictation regressions passed',
                      run(java, '-cp', str(classes) + os.pathsep + cp, 'TestKt').stdout)


if __name__ == '__main__':
    unittest.main()
