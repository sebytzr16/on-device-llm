package app.ondevicellm.ondevice_llm

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Durable OS transfers use an isolated staging path, never a loadable GGUF.
 * The existing Dart checksum/header verifier is the only promotion authority. */
class BackgroundDownloads(context: Context, messenger: BinaryMessenger) {
    private val app = context.applicationContext
    private val manager = app.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val prefs = app.getSharedPreferences("model_system_downloads_v1", Context.MODE_PRIVATE)
    private val root: File get() = File(requireNotNull(app.getExternalFilesDir(null)), "models").apply { mkdirs() }

    init {
        MethodChannel(messenger, "ondevice_llm/downloads").setMethodCallHandler { call, result ->
            try {
                val id = requireNotNull(call.argument<String>("id"))
                require(id.isNotBlank() && id.length <= 300)
                val key = MessageDigest.getInstance("SHA-256").digest(id.toByteArray()).joinToString("") { "%02x".format(it) }
                when (call.method) {
                    "enqueue" -> {
                        val name = requireNotNull(call.argument<String>("fileName"))
                        require(name == File(name).name && !name.contains('/') && !name.contains('\\') && listOf(".gguf", ".onnx", ".txt", ".tar.bz2").any { name.endsWith(it, true) })
                        val url = requireNotNull(call.argument<String>("url"))
                        val uri = Uri.parse(url)
                        require(uri.scheme in listOf("http", "https") && !uri.host.isNullOrBlank())
                        val hash = requireNotNull(call.argument<String>("sha256")).lowercase()
                        val size = requireNotNull(call.argument<Number>("size")).toLong()
                        require(hash.matches(Regex("[a-f0-9]{64}")) && size > 8)
                        val previous = record(key)
                        require(prefs.all.entries.none { (otherKey, value) ->
                            otherKey != key && value is String && JSONObject(value).optString("fileName") == name
                        }) { "Another transfer already targets this filename." }
                        if (previous != null) {
                            require(previous.getString("fileName") == name && previous.getString("sha256") == hash && previous.getLong("size") == size && previous.getString("url") == url) {
                                "A different transfer already uses this model id. Cancel it first."
                            }
                            if (status(previous)["status"] != "failed") {
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            remove(key, previous)
                        }
                        val target = staging(key)
                        require(!File(root, name).exists()) { "A model already exists at this path." }
                        if (target.exists()) require(target.delete()) { "Cannot clear interrupted staging file." }
                        val request = DownloadManager.Request(uri)
                            .setDestinationUri(Uri.fromFile(target))
                            .setTitle(name)
                            .setDescription(app.getString(R.string.model_download_description))
                            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                            .setAllowedOverRoaming(false)
                            .addRequestHeader("Accept-Encoding", "identity")
                        val job = manager.enqueue(request)
                        val data = JSONObject().put("job", job).put("fileName", name).put("url", url).put("sha256", hash).put("size", size).put("key", key)
                        if (!prefs.edit().putString(key, data.toString()).commit()) {
                            manager.remove(job)
                            error("Cannot save download recovery information.")
                        }
                        result.success(null)
                    }
                    "query" -> result.success(record(key)?.let { status(it) } ?: mapOf("status" to "failed", "received" to 0, "error" to "System download not found. Tap Resume."))
                    "stage" -> {
                        val data = requireNotNull(record(key)) { "System download not found." }
                        val source = staging(key)
                        val part = File(root, data.getString("fileName") + ".part")
                        // If the process died after the move, the verified-size .part
                        // is already ready for Dart to hash on the next launch.
                        if (source.exists()) {
                            require(status(data)["status"] == "complete") { "System download is incomplete." }
                            if (source.length() != data.getLong("size")) {
                                remove(key, data)
                                error("Downloaded file differs from its verified size. Tap Resume.")
                            }
                            require(!part.exists()) { "A resumable partial already exists." }
                            require(source.renameTo(part)) { "Cannot stage completed download." }
                        } else {
                            require(part.exists() && part.length() == data.getLong("size")) { "Downloaded file is missing." }
                        }
                        remove(key, data)
                        result.success(null)
                    }
                    "cancel" -> {
                        record(key)?.let { remove(key, it) }
                        staging(key).delete()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("download", error.message ?: "System download failed", null)
            }
        }
    }

    private fun record(key: String): JSONObject? = prefs.getString(key, null)?.let { JSONObject(it) }
    private fun staging(key: String) = File(root, ".system-$key.download")
    private fun remove(key: String, record: JSONObject) {
        manager.remove(record.getLong("job"))
        require(prefs.edit().remove(key).commit()) { "Cannot remove download recovery information." }
    }

    private fun status(record: JSONObject): Map<String, Any> {
        manager.query(DownloadManager.Query().setFilterById(record.getLong("job"))).use { cursor ->
            if (!cursor.moveToFirst()) return mapOf("status" to "failed", "received" to 0, "error" to "System download was removed. Tap Resume.")
            val state = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val bytes = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)).coerceAtLeast(0)
            val reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            return when (state) {
                DownloadManager.STATUS_SUCCESSFUL -> mapOf("status" to "complete", "received" to bytes)
                DownloadManager.STATUS_FAILED -> mapOf("status" to "failed", "received" to bytes, "error" to "System download failed ($reason). Tap Resume.")
                DownloadManager.STATUS_RUNNING -> mapOf("status" to "running", "received" to bytes)
                else -> mapOf("status" to "waiting", "received" to bytes)
            }
        }
    }
}
