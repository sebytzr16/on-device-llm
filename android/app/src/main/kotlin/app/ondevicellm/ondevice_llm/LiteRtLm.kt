package app.ondevicellm.ondevice_llm

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.ExperimentalApi
import com.google.ai.edge.litertlm.ExperimentalFlags
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.ModelInfo
import com.google.ai.edge.litertlm.ResponseFormat
import com.google.ai.edge.litertlm.SamplerConfig
import com.google.ai.edge.litertlm.ThinkingConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

@OptIn(ExperimentalApi::class)
class LiteRtLm(messenger: BinaryMessenger, private val cacheDir: File) : AutoCloseable {
    private val methods = MethodChannel(messenger, "ondevice_llm/litert")
    private val tokens = EventChannel(messenger, "ondevice_llm/litert/tokens")
    private val main = Handler(Looper.getMainLooper())
    private val dispatcher = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val operations = Mutex()
    private var sink: EventChannel.EventSink? = null
    private var engine: Engine? = null
    private var active: Generation? = null
    private var info = emptyMap<String, Any?>()
    @Volatile private var closed = false

    private class Generation(
        val id: Int,
        val conversation: Conversation,
        val target: EventChannel.EventSink,
    ) {
        lateinit var job: Job

        /// A Stop or an unload asked this generation to end.
        @Volatile var stopping = false
    }

    /// What the model file says about itself; null when it cannot be read.
    private class ModelFacts(val vision: Boolean?)

    init {
        tokens.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                val detached = sink
                sink = null
                if (detached == null) return
                // A hot restart detaches the sink but leaves its generation
                // running: stop what the detached sink owned so the next
                // listen finds the engine free.
                scope.launch {
                    operations.withLock {
                        active?.takeIf { it.target === detached }?.let { stop(it) }
                    }
                }
            }
        })
        methods.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("load", "unload", "generate", "cancel", "info")) {
            result.notImplemented()
            return
        }
        val target = sink
        scope.launch {
            operations.withLock {
                try {
                    check(!closed)
                    val reply = when (call.method) {
                        "load" -> load(call)
                        "unload" -> unload()
                        "info" -> info
                        "cancel" -> {
                            val request = active
                            if (request != null && request.id == call.argument<Int>("id")) {
                                stop(request)
                            }
                            null
                        }
                        else -> {
                            requireNotNull(target)
                            generate(call, target)
                            null
                        }
                    }
                    main.post { if (!closed) result.success(if (reply is Unit) null else reply) }
                } catch (error: Exception) {
                    main.post {
                        if (!closed) result.error("litert_${call.method}", error.message, null)
                    }
                } catch (error: LinkageError) {
                    main.post {
                        if (!closed) result.error("litert_${call.method}", error.message, null)
                    }
                }
            }
        }
    }

    private suspend fun load(call: MethodCall): Map<String, Any?> {
        unload()
        val path = requireNotNull(call.argument<String>("path"))
        require(File(path).isFile && path.endsWith(".litertlm", ignoreCase = true))
        val requested = call.argument<String>("backend") ?: "auto"
        require(requested in setOf("auto", "gpu", "cpu"))
        // The file's own metadata says which modalities it takes in; the
        // caller only says whether the user allows photos.
        val facts = modelFacts(path)
        val vision = call.argument<Boolean>("vision") == true && facts.vision != false
        var backend: Backend = if (requested == "cpu") Backend.CPU() else Backend.GPU()
        engine = try {
            initialize(path, backend, vision)
        } catch (gpuError: Throwable) {
            if (requested != "auto" || (gpuError !is Exception && gpuError !is LinkageError)) {
                throw gpuError
            }
            backend = Backend.CPU()
            try {
                initialize(path, backend, vision)
            } catch (cpuError: Exception) {
                cpuError.addSuppressed(gpuError)
                throw cpuError
            }
        }
        info = mapOf(
            "backend" to if (backend is Backend.GPU) "gpu" else "cpu",
            "supportsVision" to vision,
            // The file's own answer, which stays true when the user's photo
            // switch narrows what a chat sends; null when the metadata could
            // not be read, so the capability is unknown rather than assumed.
            "visionCapable" to facts.vision,
            "supportsAudio" to false,
            "supportsTools" to false,
            // The file's own maximum can exceed what the runtime allocates
            // (the GPU context is sized at initialize): the effective window
            // is unknown until a decode reports it.
            "contextSize" to null,
        )
        return info
    }

    /// The input modalities from the model file. Null when the metadata
    /// cannot be read, so the caller's own answer stands instead of a guess.
    private fun modelFacts(path: String): ModelFacts {
        var model: ModelInfo? = null
        return try {
            model = ModelInfo.from(path)
            ModelFacts(vision = model.inputModalities().vision)
        } catch (error: Exception) {
            Log.w("LiteRtLm", "Could not read the model metadata", error)
            ModelFacts(null)
        } catch (error: LinkageError) {
            Log.w("LiteRtLm", "Could not read the model metadata", error)
            ModelFacts(null)
        } finally {
            runCatching { model?.close() }
        }
    }

    @Suppress("DEPRECATION")
    private fun initialize(path: String, backend: Backend, vision: Boolean): Engine {
        ExperimentalFlags.enableBenchmark = true
        ExperimentalFlags.enableSpeculativeDecoding = backend is Backend.GPU
        return Engine(
            EngineConfig(
                modelPath = path,
                backend = backend,
                visionBackend = backend.takeIf { vision },
                cacheDir = cacheDir.absolutePath,
            )
        ).also { it.initialize() }
    }

    private suspend fun unload() {
        // A generation that has not ended keeps the runtime busy: closing the
        // engine under it tore down a live runtime, so the unload reports it
        // instead and the next one closes the engine once it did end.
        check(active?.let { stop(it) } != false) {
            "The running generation did not settle"
        }
        val loaded = engine
        engine = null
        info = emptyMap()
        loaded?.close()
    }

    /// Asks the runtime to stop [request] and waits for its terminal event;
    /// true when it ended. LiteRT-LM ends the flow itself once it cancels
    /// (onDone, or onError with the cancellation), and closing the
    /// conversation or the engine before that left inference running into a
    /// torn-down runtime. A request that outlasts the wait stays busy, and
    /// its own terminal event closes it.
    private suspend fun stop(request: Generation): Boolean {
        request.stopping = true
        runCatching { request.conversation.cancelProcess() }.onFailure {
            Log.w("LiteRtLm", "Could not cancel the generation", it)
        }
        if (withTimeoutOrNull(CANCEL_TIMEOUT_MS) { request.job.join() } != null) {
            return true
        }
        Log.w("LiteRtLm", "The cancelled generation did not settle; it stays busy")
        return false
    }

    private fun generate(call: MethodCall, target: EventChannel.EventSink) {
        val loaded = checkNotNull(engine)
        check(active == null)
        val id = requireNotNull(call.argument<Int>("id"))
        val messages = requireNotNull(call.argument<List<Map<String, Any?>>>("messages"))
        val userIndex = messages.indexOfLast { it["role"] == "user" }
        require(userIndex >= 0)
        val system = messages.filter { it["role"] == "system" }.joinToString("\n\n") {
            it["content"] as? String ?: ""
        }
        val vision = info["supportsVision"] == true
        val initial = messages.take(userIndex).mapNotNull { message ->
            when (message["role"]) {
                "user" -> Message.user(contents(message, vision))
                "assistant" -> Message.model(contents(message, vision))
                else -> null
            }
        }
        val prefix = call.argument<String>("assistantPrefix").orEmpty()
        val prompt = contents(messages[userIndex], vision, prefix)
        val maxTokens = requireNotNull(call.argument<Int>("maxTokens"))
        val thinking = call.argument<Boolean>("thinking") == true
        val requestedThinking = call.argument<Int>("thinkingBudget") ?: 0
        // The app's Unlimited reasoning (zero) must not reach the runtime as
        // an unbounded budget: LiteRT-LM counts reasoning against
        // maxOutputToken, so an answer of maxTokens with unlimited thinking
        // leaves the reasoning the whole allowance before an answer appears.
        val thinkingBudget = when {
            !thinking -> 0
            requestedThinking > 0 -> requestedThinking
            else -> unlimitedThinkingBudget(maxTokens)
        }
        // LiteRT-LM counts reasoning against maxOutputToken: the answer's
        // allowance alone would let thinking use it up before an answer.
        val outputCap = maxTokens + thinkingBudget
        // Constrained decoding only when the caller asks for it; a JSON
        // schema, when given, is what the reply must match.
        val json = call.argument<String>("responseFormat") == "json"
        val jsonSchema = call.argument<String>("jsonSchema").orEmpty().trim()
        val topK = call.argument<Int>("topK") ?: 40
        // The Android GPU executor only accepts up to 64 candidates.
        val effectiveTopK = if (info["backend"] == "gpu") {
            if (topK <= 0) 64 else topK.coerceAtMost(64)
        } else {
            if (topK <= 0) 40 else topK
        }
        val conversation = loaded.createConversation(
            ConversationConfig(
                systemInstruction = system.takeIf { it.isNotBlank() }?.let { Contents.of(it) },
                initialMessages = initial,
                samplerConfig = SamplerConfig(
                    topK = effectiveTopK,
                    topP = call.argument<Double>("topP") ?: 0.95,
                    temperature = call.argument<Double>("temperature") ?: 0.7,
                ),
                automaticToolCalling = false,
                maxOutputToken = outputCap,
                thinkingConfig = ThinkingConfig(
                    enableThinking = thinking,
                    thinkingTokenBudget = if (thinking) thinkingBudget else -1,
                ),
                enableResponseFormat = json,
            )
        )
        val request = Generation(id, conversation, target)
        active = request
        request.job = scope.launch(start = CoroutineStart.UNDISPATCHED) {
            var terminal: Map<String, Any?>
            try {
                conversation.sendMessageAsync(
                    prompt,
                    maxOutputToken = outputCap,
                    responseFormat = if (json) {
                        ResponseFormat.json(jsonSchema.ifEmpty { ANY_JSON_OBJECT })
                    } else {
                        null
                    },
                )
                    .buffer(Channel.UNLIMITED)
                    .collect { message ->
                        message.channels["thought"]?.takeIf { it.isNotEmpty() }?.let {
                            emit(target, id, mapOf("type" to "thought", "text" to it))
                        }
                        for (part in message.contents.contents.filterIsInstance<Content.Text>()) {
                            if (part.text.isNotEmpty()) {
                                emit(target, id, mapOf("type" to "text", "text" to part.text))
                            }
                        }
                    }
                val stats = runCatching { conversation.getBenchmarkInfo() }.getOrNull()
                val totalTokens = runCatching { conversation.getTokenCount() }.getOrNull()
                // The window the runtime actually allocated: the load could
                // not know it, so the previews before this turn stay unknown.
                val contextSize = stats?.maxNumTokens?.takeIf { it > 0 }
                if (contextSize != null) info = info + ("contextSize" to contextSize)
                terminal = mapOf(
                    "type" to "done",
                    "finishReason" to when {
                        request.stopping -> "cancelled"
                        (stats?.lastDecodeTokenCount ?: 0) >= outputCap -> "length"
                        else -> "eog"
                    },
                    "metrics" to mapOf(
                        "contextSize" to contextSize,
                        "firstTokenMs" to stats?.timeToFirstTokenInSecond?.times(1000),
                        "tokensPerSecond" to stats?.lastDecodeTokensPerSecond?.takeIf { it.isFinite() },
                        "tokens" to stats?.lastDecodeTokenCount,
                        "promptTokens" to if (stats != null && totalTokens != null) {
                            (totalTokens - stats.lastDecodeTokenCount).coerceAtLeast(0)
                        } else stats?.lastPrefillTokenCount,
                    ),
                )
            } catch (error: CancellationException) {
                terminal = mapOf("type" to "done", "finishReason" to "cancelled")
            } catch (error: Exception) {
                terminal = mapOf("type" to "error", "message" to error.message)
            } catch (error: LinkageError) {
                terminal = mapOf("type" to "error", "message" to error.message)
            } finally {
                val closeError = runCatching { conversation.close() }.exceptionOrNull()
                active = null
                if (closeError != null && !closed) {
                    emit(target, id, mapOf("type" to "error", "message" to closeError.message))
                }
            }
            emit(target, id, terminal)
        }
    }

    /// What the app's Unlimited reasoning becomes: half of the room the
    /// window the runtime last reported leaves after the answer's own
    /// allowance, and the answer's allowance itself before one is measured.
    private fun unlimitedThinkingBudget(maxTokens: Int): Int {
        val window = info["contextSize"] as? Int ?: return maxTokens
        return ((window - maxTokens) / 2).coerceAtLeast(1)
    }

    private fun contents(
        message: Map<String, Any?>,
        vision: Boolean,
        prefix: String = "",
    ): Contents {
        val text = message["content"] as? String ?: ""
        val images = if (vision) (message["images"] as? List<*>).orEmpty().filterIsInstance<String>()
            else emptyList()
        val segments = text.split("<__media__>")
        val parts = buildList<Content> {
            for ((index, segment) in segments.withIndex()) {
                if (index > 0) images.getOrNull(index - 1)?.let { add(Content.ImageFile(it)) }
                if (segment.isNotEmpty()) add(Content.Text(segment))
            }
            for (path in images.drop(segments.size - 1)) add(Content.ImageFile(path))
            if (prefix.isNotEmpty()) {
                add(Content.Text("\nContinue this partial answer without repeating it:\n$prefix"))
            }
            if (isEmpty()) add(Content.Text(""))
        }
        return Contents.of(parts)
    }

    private fun emit(target: EventChannel.EventSink, id: Int, event: Map<String, Any?>) {
        main.post { if (!closed && sink === target) target.success(event + ("id" to id)) }
    }

    private companion object {
        /// How long a cancelled generation may take to reach its terminal
        /// event before its conversation is closed anyway.
        const val CANCEL_TIMEOUT_MS = 5_000L

        /// The schema a JSON reply is held to when the caller names none.
        const val ANY_JSON_OBJECT = "{\"type\":\"object\"}"
    }

    override fun close() {
        if (closed) return
        closed = true
        methods.setMethodCallHandler(null)
        tokens.setStreamHandler(null)
        sink = null
        scope.launch {
            try {
                operations.withLock {
                    runCatching { unload() }.onFailure {
                        Log.w("LiteRtLm", "Failed to close the engine", it)
                    }
                }
            } finally {
                scope.cancel()
                dispatcher.close()
            }
        }
    }
}
