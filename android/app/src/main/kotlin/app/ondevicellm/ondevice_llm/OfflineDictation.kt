package app.ondevicellm.ondevice_llm

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Strict local dictation. Deliberately never calls createSpeechRecognizer:
 * EXTRA_PREFER_OFFLINE on the default recognizer is only a preference.
 */
class OfflineDictation(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    companion object { const val PERMISSION_REQUEST = 7301 }

    private val channel = MethodChannel(messenger, "ondevice_llm/offline_dictation")
    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var session: Int? = null
    private data class Pending(val call: MethodCall, val result: MethodChannel.Result, val revision: Int)
    private var pending: Pending? = null
    private var revision = 0
    private var lastPartial = ""
    private var endpoint: Runnable? = null
    private var deadline: Runnable? = null

    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listen" -> {
                cancel()
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                    !SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)) {
                    result.error("offline_unavailable", "An on-device speech recognizer is unavailable.", null)
                    return
                }
                if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    pending = Pending(call, result, revision)
                    activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST)
                } else {
                    start(call, result, revision)
                }
            }
            "stop" -> {
                // stopListening alone need not release the service's recorder.
                // Keep the caption already received and release synchronously.
                revision++
                pending?.result?.error("cancelled", "Dictation cancelled.", null)
                pending = null
                finishSession()
                result.success(null)
            }
            "cancel" -> { cancel(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    fun onPermissionResult(granted: Boolean) {
        val request = pending ?: return
        pending = null
        if (!granted) {
            request.result.error("error_permission", "Microphone permission is needed for dictation.", null)
        } else {
            start(request.call, request.result, request.revision)
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result, expectedRevision: Int) {
        if (expectedRevision != revision) {
            result.error("cancelled", "Dictation cancelled.", null)
            return
        }
        val token = call.argument<Int>("session")
        if (token == null) {
            result.error("invalid_session", "Missing dictation session.", null)
            return
        }
        try {
            // Recheck after the permission dialog; services may have changed.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                !SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)) {
                result.error("offline_unavailable", "An on-device speech recognizer is unavailable.", null)
                return
            }
            session = token
            lastPartial = ""
            val engine = SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
            recognizer = engine
            engine.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    if (session == token) setDeadline(token, 6_000)
                }
                override fun onBeginningOfSpeech() {
                    if (session == token) setDeadline(token, 60_000)
                }
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {
                    if (session != token || recognizer !== engine) return
                    // Final results can arrive well after speech ends. Replace
                    // the speech deadline with a separate final-result grace period.
                    if (endpoint != null) return
                    deadline?.let { handler.removeCallbacks(it) }
                    deadline = null
                    endpoint = Runnable {
                        if (session == token && recognizer === engine) finishSession()
                    }.also { handler.postDelayed(it, 3_000) }
                    try { engine.stopListening() } catch (_: Exception) {}
                }
                override fun onEvent(eventType: Int, params: Bundle?) {}
                override fun onPartialResults(results: Bundle?) { transcript(token, results, false) }
                override fun onResults(results: Bundle?) { transcript(token, results, true) }
                override fun onError(error: Int) {
                    if (session != token) return
                    val code = when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "error_permission"
                        SpeechRecognizer.ERROR_NO_MATCH -> "error_no_match"
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "error_speech_timeout"
                        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
                        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "error_language_unavailable"
                        else -> "offline_recognition_failed"
                    }
                    channel.invokeMethod("error", mapOf("session" to token, "code" to code))
                    release()
                }
            })
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 2500L)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
                call.argument<String>("localeId")?.takeIf { it.isNotBlank() }?.let {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, it.replace('_', '-'))
                }
            }
            engine.startListening(intent)
            // Also bound the initial wait when a recognizer sends no events.
            setDeadline(token, 6_000)
            result.success(null)
        } catch (e: Exception) {
            release()
            result.error("offline_recognition_failed", e.message, null)
        }
    }

    private fun setDeadline(token: Int, milliseconds: Long) {
        deadline?.let { handler.removeCallbacks(it) }
        deadline = Runnable {
            if (session == token) {
                channel.invokeMethod("error", mapOf("session" to token, "code" to "error_speech_timeout"))
                release()
            }
        }.also { handler.postDelayed(it, milliseconds) }
    }

    private fun transcript(token: Int, result: Bundle?, isFinal: Boolean) {
        if (session != token) return
        val text = result?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: ""
        lastPartial = text
        if (isFinal) release()
        channel.invokeMethod("result", mapOf("session" to token, "text" to text, "final" to isFinal))
    }

    private fun finishSession() {
        val token = session
        val text = lastPartial
        release()
        if (token != null) {
            channel.invokeMethod("result", mapOf("session" to token, "text" to text, "final" to true))
        }
    }

    private fun release() {
        session = null
        lastPartial = ""
        endpoint?.let { handler.removeCallbacks(it) }
        endpoint = null
        deadline?.let { handler.removeCallbacks(it) }
        deadline = null
        val old = recognizer
        recognizer = null
        try { old?.cancel() } catch (_: Exception) {}
        try { old?.destroy() } catch (_: Exception) {}
    }

    fun cancel() {
        revision++
        session?.let {
            channel.invokeMethod("error", mapOf("session" to it, "code" to "cancelled"))
        }
        pending?.result?.error("cancelled", "Dictation cancelled.", null)
        pending = null
        release()
    }

    fun close() {
        cancel()
        channel.setMethodCallHandler(null)
    }
}