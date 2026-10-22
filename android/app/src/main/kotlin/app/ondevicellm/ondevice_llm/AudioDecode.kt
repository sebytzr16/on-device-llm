package app.ondevicellm.ondevice_llm

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/** One decode pass with bounded PCM buffers, streamed to disk. */
class AudioDecode(messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())
    private val jobs = ConcurrentHashMap<String, AtomicBoolean>()
    init {
        MethodChannel(messenger, "ondevice_llm/audio").setMethodCallHandler { call, result ->
            val input = call.argument<String>("path")
            val id = call.argument<String>("id") ?: call.argument<String>("out") ?: ""
            if (call.method == "cancel") { jobs[id]?.set(true); result.success(null); return@setMethodCallHandler }
            if (call.method != "decode16k" && call.method != "duration") { result.notImplemented(); return@setMethodCallHandler }
            val output = call.argument<String>("out")
            val limit = (call.argument<Int>("maxSeconds") ?: 3600).coerceIn(1, 3600)
            if (input == null || (call.method == "decode16k" && output == null)) { result.error("audio", "Missing path.", null); return@setMethodCallHandler }
            val cancelled = AtomicBoolean(false)
            jobs[id] = cancelled
            thread(name = "audio-decode") {
                try {
                    val value = if (call.method == "duration") mapOf("seconds" to duration(File(input)))
                        else decode(File(input).canonicalFile, File(output!!), limit, cancelled)
                    main.post { result.success(value) }
                } catch (e: Exception) {
                    if (output != null) File(output).delete()
                    main.post { result.error("audio", e.message ?: "Could not decode this recording.", null) }
                } finally { jobs.remove(id, cancelled) }
            }
        }
    }
    private fun duration(input: File): Double {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(input.path)
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true && f.containsKey(MediaFormat.KEY_DURATION))
                    return f.getLong(MediaFormat.KEY_DURATION) / 1_000_000.0
            }
            return 0.0
        } finally { extractor.release() }
    }
    private fun decode(input: File, output: File, maxSeconds: Int, cancelled: AtomicBoolean): Map<String, Any> {
        require(input.isFile) { "The recording is missing." }
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var started = false
        val target = 16_000
        var outCount = 0L
        var sourceCount = 0L
        var previous = 0f
        var truncated = false
        try {
            extractor.setDataSource(input.path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: throw IllegalArgumentException("This file has no audio track.")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var floatPcm = false
            require(rate > 0 && channels in 1..32) { "Invalid audio format." }
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start(); started = true
            output.parentFile?.mkdirs()
            RandomAccessFile(output, "rw").use { file ->
                file.setLength(0); file.write(ByteArray(44))
                val pcm = ByteBuffer.allocate(64 * 1024).order(ByteOrder.LITTLE_ENDIAN)
                fun write(sample: Float) {
                    pcm.putShort((sample.coerceIn(-1f, 1f) * 32767).toInt().toShort())
                    outCount++
                    if (!pcm.hasRemaining()) { file.write(pcm.array()); pcm.clear() }
                }
                val info = MediaCodec.BufferInfo()
                var inputDone = false
                var outputDone = false
                var lastOutput = System.nanoTime()
                while (!outputDone) {
                    check(!cancelled.get()) { "Audio import cancelled." }
                    check(System.nanoTime() - lastOutput < 60_000_000_000L) { "Audio decoder stopped making progress." }
                    if (!inputDone) {
                        val i = decoder.dequeueInputBuffer(10_000)
                        if (i >= 0) {
                            val n = extractor.readSampleData(decoder.getInputBuffer(i)!!, 0)
                            if (n < 0) {
                                decoder.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputDone = true
                            } else {
                                decoder.queueInputBuffer(i, 0, n, extractor.sampleTime, 0); extractor.advance()
                            }
                        }
                    }
                    val o = decoder.dequeueOutputBuffer(info, 10_000)
                    if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        lastOutput = System.nanoTime()
                        val f = decoder.outputFormat
                        val nextRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        require(sourceCount == 0L || nextRate == rate) { "Audio sample rate changes mid-recording." }
                        rate = nextRate; channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        val encoding = if (f.containsKey(MediaFormat.KEY_PCM_ENCODING)) f.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                        require(encoding == AudioFormat.ENCODING_PCM_16BIT || encoding == AudioFormat.ENCODING_PCM_FLOAT) { "Unsupported decoded PCM encoding." }
                        floatPcm = encoding == AudioFormat.ENCODING_PCM_FLOAT
                        require(rate > 0 && channels in 1..32) { "Invalid decoded audio format." }
                    } else if (o >= 0) {
                        lastOutput = System.nanoTime()
                        val buf = decoder.getOutputBuffer(o)!!.order(ByteOrder.nativeOrder())
                        buf.position(info.offset); buf.limit(info.offset + info.size)
                        val frames = info.size / (channels * if (floatPcm) 4 else 2)
                        for (k in 0 until frames) {
                            if (k % 1024 == 0) check(!cancelled.get()) { "Audio import cancelled." }
                            if (sourceCount >= maxSeconds.toLong() * rate) { truncated = true; outputDone = true; break }
                            var sum = 0f
                            for (c in 0 until channels) sum += if (floatPcm) buf.float else buf.short / 32768f
                            val current = sum / channels
                            while (sourceCount > 0 && outCount.toDouble() * rate / target < sourceCount) {
                                val fraction = (outCount.toDouble() * rate / target - (sourceCount - 1)).toFloat()
                                write(previous + (current - previous) * fraction.coerceIn(0f, 1f))
                            }
                            previous = current; sourceCount++
                        }
                        decoder.releaseOutputBuffer(o, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                }
                val expected = sourceCount * target / rate
                while (outCount < expected) write(previous)
                if (pcm.position() > 0) file.write(pcm.array(), 0, pcm.position())
                // Fractional source frames can produce one extra interpolated
                // sample. The canonical length is floor(source * 16000/rate).
                outCount = expected
                file.setLength(44 + outCount * 2)
                file.seek(0)
                val h = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
                h.put("RIFF".toByteArray()); h.putInt(36 + (outCount * 2).toInt()); h.put("WAVE".toByteArray())
                h.put("fmt ".toByteArray()); h.putInt(16); h.putShort(1); h.putShort(1)
                h.putInt(target); h.putInt(target * 2); h.putShort(2); h.putShort(16)
                h.put("data".toByteArray()); h.putInt((outCount * 2).toInt())
                file.write(h.array())
            }
        } finally {
            if (started) try { codec?.stop() } catch (_: Exception) {}
            codec?.release(); extractor.release()
        }
        return mapOf("path" to output.path, "seconds" to outCount / target.toDouble(), "truncated" to truncated)
    }
}
