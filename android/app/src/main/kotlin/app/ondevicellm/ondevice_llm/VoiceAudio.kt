package app.ondevicellm.ondevice_llm

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * Raw microphone frames and PCM playback for the on-device voice
 * (Whisper + Kokoro through sherpa-onnx). The microphone uses the voice
 * communication source with the platform echo canceller, and playback goes
 * through the same communication path, so the assistant's own voice is
 * removed from what the microphone hears and the user can talk over it
 * (barge-in). Nothing is recorded to disk and nothing leaves the device.
 *
 * Channel `ondevice_llm/voice_audio`:
 *  - `startMic` → frames of 512 16-bit mono samples at 16 kHz on the event
 *    channel `ondevice_llm/voice_audio/mic` (32 ms each, Silero's window).
 *  - `stopMic`.
 *  - `play {pcm, rate}` → completes with true when the chunk has been heard,
 *    false when `stopPlayback` cut it short.
 *  - `stopPlayback`.
 *  - `conversation {on}` → communication mode with the loudspeaker, which
 *    the echo canceller needs; off restores the previous mode.
 */
class VoiceAudio(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        const val PERMISSION_REQUEST = 4711
        private const val RATE = 16000
        private const val FRAME = 512
    }

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    @Volatile private var recording = false
    private var recorder: Thread? = null
    private var pendingStart: MethodChannel.Result? = null

    private val queue = LinkedBlockingQueue<Chunk>()
    @Volatile private var generation = 0
    private var player: Thread? = null
    private var track: AudioTrack? = null
    private var trackRate = 0
    private var trackCall = false
    private var savedMode: Int? = null
    /** Conversation playback on the call path (echo-cancelled, narrowband). */
    private var callPath = false

    private class Chunk(val pcm: ShortArray, val rate: Int, val generation: Int, val done: (Boolean) -> Unit)
    private data class Settle(val end: Long, val deadline: Long, val chunk: Chunk)
    /** Ends the player thread (after [close]). */
    private val poison = Chunk(ShortArray(0), 0, -1) {}
    @Volatile private var closed = false

    init {
        EventChannel(messenger, "ondevice_llm/voice_audio/mic").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        MethodChannel(messenger, "ondevice_llm/voice_audio").setMethodCallHandler { call, result ->
            when (call.method) {
                "startMic" -> {
                    if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        pendingStart?.success(false)
                        pendingStart = result
                        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST)
                    } else {
                        result.success(startMic())
                    }
                }
                "stopMic" -> { stopMic(); result.success(null) }
                "play" -> {
                    val bytes = call.argument<ByteArray>("pcm")
                    val rate = call.argument<Int>("rate") ?: 24000
                    if (bytes == null || bytes.size < 2) { result.success(true); return@setMethodCallHandler }
                    val pcm = ShortArray(bytes.size / 2)
                    for (i in pcm.indices) {
                        pcm[i] = ((bytes[2 * i].toInt() and 0xff) or (bytes[2 * i + 1].toInt() shl 8)).toShort()
                    }
                    ensurePlayer()
                    queue.put(Chunk(pcm, rate, generation) { ok -> main.post { result.success(ok) } })
                }
                "stopPlayback" -> { stopPlayback(); result.success(null) }
                "conversation" -> {
                    conversation(call.argument<Boolean>("on") == true, call.argument<Boolean>("call") ?: true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onPermissionResult(granted: Boolean) {
        val pending = pendingStart ?: return
        pendingStart = null
        pending.success(granted && startMic())
    }

    private fun startMic(): Boolean {
        if (recording) return true
        val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (min <= 0) return false
        // The call path cancels the answer's echo; otherwise the recognition
        // source gives Whisper the voice without call-style processing.
        val call = callPath
        val source = if (call) MediaRecorder.AudioSource.VOICE_COMMUNICATION
            else MediaRecorder.AudioSource.VOICE_RECOGNITION
        val record = try {
            AudioRecord(source, RATE,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, FRAME * 8))
        } catch (e: SecurityException) { return false }
        if (record.state != AudioRecord.STATE_INITIALIZED) { record.release(); return false }
        val effects = mutableListOf<android.media.audiofx.AudioEffect>()
        if (call && AcousticEchoCanceler.isAvailable()) AcousticEchoCanceler.create(record.audioSessionId)?.let { it.enabled = true; effects += it }
        if (call && NoiseSuppressor.isAvailable()) NoiseSuppressor.create(record.audioSessionId)?.let { it.enabled = true; effects += it }
        recording = true
        recorder = thread(name = "voice-mic") {
            val frame = ShortArray(FRAME)
            try {
                record.startRecording()
                while (recording) {
                    var filled = 0
                    while (filled < FRAME && recording) {
                        val n = record.read(frame, filled, FRAME - filled)
                        if (n < 0) { recording = false; break }
                        filled += n
                    }
                    if (filled < FRAME) break
                    val bytes = ByteArray(FRAME * 2)
                    for (i in 0 until FRAME) {
                        val v = frame[i].toInt()
                        bytes[2 * i] = (v and 0xff).toByte()
                        bytes[2 * i + 1] = (v shr 8).toByte()
                    }
                    main.post { sink?.success(bytes) }
                }
            } finally {
                try { record.stop() } catch (_: IllegalStateException) {}
                effects.forEach { it.release() }
                record.release()
            }
        }
        return true
    }

    private fun stopMic() {
        recording = false
        recorder?.join(500)
        recorder = null
    }

    private fun ensurePlayer() {
        if (closed || player?.isAlive == true) return
        player = thread(name = "voice-play", isDaemon = true) {
            // Written but not yet heard: where each chunk ends on the track.
            val settling = ArrayDeque<Settle>()
            try {
                while (true) {
                    // Gapless (audit C4): the next chunk is written while the
                    // one before still plays, so the track never runs dry
                    // between sentences.
                    val chunk = if (settling.isEmpty()) queue.take()
                        else queue.poll(15, TimeUnit.MILLISECONDS)
                    if (chunk === poison) break
                    if (chunk != null) {
                        if (chunk.generation != generation) chunk.done(false)
                        else {
                            val end = write(chunk, settling)
                            if (end < 0) chunk.done(false) else {
                                // Heard by then at the latest, should the head be reset.
                                val ms = chunk.pcm.size * 1000L / chunk.rate
                                val from = maxOf(System.currentTimeMillis(), settling.lastOrNull()?.deadline ?: 0L)
                                settling.addLast(Settle(end, from + ms + 500, chunk))
                            }
                        }
                    }
                    settle(settling)
                }
            } catch (_: InterruptedException) {
            } catch (e: Exception) {
                Log.w("VoiceAudio", "player stopped", e)
            } finally {
                settling.forEach { it.chunk.done(false) }
                settling.clear()
            }
        }
    }

    /** Calls back the chunks the head has passed, or that were cut. */
    private fun settle(settling: ArrayDeque<Settle>) {
        if (settling.isEmpty()) return
        val head = synchronized(this) { track?.let { it.playbackHeadPosition.toLong() and 0xffffffffL } }
        while (settling.isNotEmpty()) {
            val (end, deadline, chunk) = settling.first()
            when {
                chunk.generation != generation || head == null -> chunk.done(false)
                head >= end || System.currentTimeMillis() > deadline -> chunk.done(true)
                else -> return
            }
            settling.removeFirst()
        }
    }

    private fun trackFor(rate: Int): AudioTrack? {
        // Read-aloud plays as media; a conversation plays on the call path
        // the echo canceller listens to.
        val call = callPath
        track?.let {
            if (trackRate == rate && trackCall == call) return it
            return null // another format: the chunks on this one end first
        }
        val min = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val t = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(if (call) AudioAttributes.USAGE_VOICE_COMMUNICATION else AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(rate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(maxOf(min, rate / 5 * 2))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        track = t
        trackRate = rate
        trackCall = call
        written = 0
        underruns = 0
        return t
    }

    /** Frames written to the track since it last started from silence. */
    private var written = 0L
    private var underruns = 0

    /**
     * Writes the chunk (non-blocking, settling the ones before while the
     * buffer is full) and returns the head position at its end, or -1 when
     * it was cut.
     */
    private fun write(chunk: Chunk, settling: ArrayDeque<Settle>): Long {
        var t: AudioTrack? = null
        while (t == null) {
            if (chunk.generation != generation) return -1
            t = synchronized(this) { trackFor(chunk.rate) }
            if (t == null) {
                // A new format: the old track plays out, then is replaced.
                settle(settling)
                if (settling.isEmpty()) synchronized(this) { track?.release(); track = null }
                else Thread.sleep(15)
            }
        }
        val tr = checkNotNull(t)
        synchronized(this) {
            if (tr.playState != AudioTrack.PLAYSTATE_PLAYING) {
                // From silence (new, or paused and flushed by a stop): the
                // head counts from here.
                tr.play()
                written = tr.playbackHeadPosition.toLong() and 0xffffffffL
            }
        }
        if (tr.underrunCount > underruns) {
            if (settling.isNotEmpty()) Log.w("VoiceAudio", "underrun between sentences (${tr.underrunCount})")
            underruns = tr.underrunCount
        }
        var offset = 0
        // Non-blocking: a blocking write into a paused track waited out the
        // cut sentence, and the microphone stayed shut that long after a
        // tap to interrupt (the next question lost its first words).
        while (offset < chunk.pcm.size) {
            if (chunk.generation != generation) return -1
            val n = tr.write(chunk.pcm, offset, minOf(2048, chunk.pcm.size - offset),
                AudioTrack.WRITE_NON_BLOCKING)
            if (n < 0) return -1
            if (n == 0) { settle(settling); Thread.sleep(10) }
            offset += n
        }
        written += chunk.pcm.size
        return written
    }

    private fun stopPlayback() {
        generation++
        val pending = mutableListOf<Chunk>()
        queue.drainTo(pending)
        pending.forEach { if (it !== poison) it.done(false) }
        if (closed) queue.put(poison)
        synchronized(this) {
            track?.let { try { it.pause(); it.flush() } catch (_: IllegalStateException) {} }
        }
    }

    private fun conversation(on: Boolean, call: Boolean = true) {
        val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        callPath = on && call
        if (on && call) {
            if (savedMode == null) savedMode = audio.mode
            audio.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audio.availableCommunicationDevices
                    .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    ?.let { audio.setCommunicationDevice(it) }
            } else {
                @Suppress("DEPRECATION")
                audio.isSpeakerphoneOn = true
            }
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audio.clearCommunicationDevice()
            } else {
                @Suppress("DEPRECATION")
                audio.isSpeakerphoneOn = false
            }
            savedMode?.let { audio.mode = it }
            savedMode = null
        }
    }

    /** The window is no longer seen: silence, and the microphone off. */
    fun pause() {
        stopMic()
        stopPlayback()
    }

    fun close() {
        closed = true
        stopMic()
        stopPlayback() // every chunk answered false; the player thread ends
        player?.join(500)
        player = null
        conversation(false)
        synchronized(this) { track?.release(); track = null }
    }
}
