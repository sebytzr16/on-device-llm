package app.ondevicellm.ondevice_llm

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.ArrayDeque
import java.util.UUID

/// "Share to OnDevice LLM": keeps the last ACTION_SEND / SEND_MULTIPLE
/// intent until Dart takes it, then copies the shared files into the app's
/// cache (off the main thread, 64 MB each, at most 8) and hands over the
/// text, subject and file paths. Nothing is sent anywhere.
class ShareInbox(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "ondevice_llm/share")
    private val pending = ArrayDeque<Intent>()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "take" -> take(result)
                else -> result.notImplemented()
            }
        }
    }

    /// Called for the launch intent and every later one (singleTop).
    fun offer(intent: Intent?, notify: Boolean) {
        val action = intent?.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE &&
            action != ScheduledPrompts.ACTION_RUN && action != Intent.ACTION_PROCESS_TEXT &&
            action != Intent.ACTION_ASSIST && action != Launchers.ACTION_LAUNCH) return
        // Reopened from Recents, Android replays the launch intent: that share
        // (or scheduled prompt) was already handled.
        if (((intent?.flags ?: 0) and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        pending.addLast(intent ?: return)
        if (notify) channel.invokeMethod("arrived", null)
    }

    private fun take(result: MethodChannel.Result) {
        val intent = pending.pollFirst()
        // Taken once: a recreated activity must not see it again.
        if (intent != null && pending.isEmpty()) activity.intent = Intent(Intent.ACTION_MAIN)
        if (intent == null) {
            result.success(null)
            return
        }
        Thread {
            val payload = try {
                read(intent)
            } catch (e: Exception) {
                mapOf("error" to (e.message ?: "Could not read the shared item."))
            }
            activity.runOnUiThread { result.success(payload) }
        }.start()
    }

    private fun read(intent: Intent): Map<String, Any?> {
        // A scheduled prompt's notification was tapped: its text and kind.
        if (intent.action == ScheduledPrompts.ACTION_RUN) {
            return mapOf(
                "text" to intent.getStringExtra(ScheduledPrompts.EXTRA_PROMPT),
                "scheduled" to (intent.getStringExtra(ScheduledPrompts.EXTRA_KIND) ?: "chat"),
            )
        }
        // Text selected in another app ("Ask OnDevice LLM").
        if (intent.action == Intent.ACTION_PROCESS_TEXT) {
            return mapOf(
                "text" to intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString(),
                "selection" to true,
            )
        }
        // The assistant gesture, the quick-settings tile or the widget.
        if (intent.action == Intent.ACTION_ASSIST) return mapOf("launch" to "voice")
        if (intent.action == Launchers.ACTION_LAUNCH) {
            return mapOf("launch" to (intent.getStringExtra(Launchers.EXTRA_MODE) ?: "chat"))
        }
        val uris = mutableListOf<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val list = if (Build.VERSION.SDK_INT >= 33)
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            list?.let { uris.addAll(it) }
        } else {
            val one = if (Build.VERSION.SDK_INT >= 33)
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            one?.let { uris.add(it) }
        }
        // Each delivery keeps its files while Dart imports them.
        val dir by lazy {
            File(activity.cacheDir, "shared/${UUID.randomUUID()}").apply { mkdirs() }
        }
        val files = mutableListOf<Map<String, Any?>>()
        val skipped = mutableListOf<String>()
        for ((i, uri) in uris.take(8).withIndex()) {
            val name = displayName(uri) ?: "shared-$i"
            val target = File(dir, "$i-" + name.replace(Regex("[^A-Za-z0-9._-]"), "_"))
            var copied = 0L
            activity.contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        copied += n
                        if (copied > MAX_BYTES) break
                        output.write(buffer, 0, n)
                    }
                }
            }
            if (copied == 0L || copied > MAX_BYTES) {
                target.delete()
                skipped.add(name)
            } else {
                files.add(mapOf(
                    "name" to name,
                    "path" to target.absolutePath,
                    "mime" to activity.contentResolver.getType(uri),
                ))
            }
        }
        return mapOf(
            "text" to intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
            "subject" to intent.getStringExtra(Intent.EXTRA_SUBJECT),
            "files" to files,
            "skipped" to skipped,
            "more" to (uris.size > 8),
        )
    }

    private fun displayName(uri: Uri): String? = try {
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
    } catch (_: Exception) {
        uri.lastPathSegment
    }

    companion object {
        const val MAX_BYTES = 64L * 1024 * 1024
    }
}
