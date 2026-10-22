package app.ondevicellm.ondevice_llm

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/** Shared foreground/headless storage. Compare-and-set protects deletions,
 * edits and newer results from an obsolete in-flight search. */
object GoalWatchData {
    private const val PREFS = "goal_watches"
    private const val KEY = "items"

    @Synchronized fun load(context: Context): JSONArray {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val saved = prefs.getString(KEY, null)
        if (saved != null) return JSONArray(saved)
        val legacy = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.goal_watches_v1", "[]") ?: "[]"
        val items = JSONArray(legacy)
        write(context, items)
        return items
    }

    private fun write(context: Context, items: JSONArray) {
        check(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, items.toString()).commit()) { "Watch results could not be saved." }
    }

    @Synchronized fun put(context: Context, id: Int, value: String, expected: String?): Boolean {
        val items = load(context)
        val index = (0 until items.length()).firstOrNull { items.getJSONObject(it).optInt("id") == id }
        if (expected != null) {
            if (index == null || items.getJSONObject(index).toString() != JSONObject(expected).toString()) return false
            val schedule = ScheduledPrompts.find(context, id)
            if (schedule == null || !schedule.optBoolean("enabled", true)) return false
        }
        val next = JSONObject(value)
        require(next.getInt("id") == id)
        if (index == null) items.put(next) else items.put(index, next)
        write(context, items)
        return true
    }

    @Synchronized fun remove(context: Context, id: Int) {
        val items = load(context)
        for (i in items.length() - 1 downTo 0) {
            if (items.getJSONObject(i).optInt("id") == id) items.remove(i)
        }
        write(context, items)
    }

    @Synchronized fun enabled(context: Context): JSONArray {
        val schedules = ScheduledPrompts.load(context)
        val ids = (0 until schedules.length()).map { schedules.getJSONObject(it) }
            .filter { it.optString("kind") == "goal" && it.optBoolean("enabled", true) }
            .map { it.optInt("id") }.toSet()
        val items = load(context)
        return JSONArray().apply {
            for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                if (item.optInt("id") in ids) put(item)
            }
        }
    }

    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "watchList" -> result.success(load(context).toString())
            "watchPut" -> {
                val id = call.argument<Number>("id")?.toInt() ?: error("Missing watch id")
                result.success(put(context, id, call.argument<String>("value") ?: error("Missing watch"), call.argument<String>("expected")))
            }
            "watchRemove" -> { remove(context, (call.arguments as Number).toInt()); result.success(null) }
            "watchEnqueue" -> { GoalWatchJob.enqueue(context); result.success(null) }
            else -> return false
        }
        return true
    }
}

/** Android grants a network job lifetime to a bounded Dart fetch/diff.
 * It never starts MainActivity, loads a model or launches a phone action. */
class GoalWatchJob : JobService() {
    private var engine: FlutterEngine? = null
    private var active: JobParameters? = null
    private val handler = Handler(Looper.getMainLooper())
    private var timeout: Runnable? = null

    override fun onStartJob(params: JobParameters): Boolean {
        if (active != null) return false
        active = params
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            // The worker uses HTTP and our two channels only. No Activity
            // plugins, SQLite connection, microphone or native inference.
            val worker = FlutterEngine(applicationContext, null, false)
            engine = worker
            val messenger = worker.dartExecutor.binaryMessenger
            MethodChannel(messenger, "ondevice_llm/schedule").setMethodCallHandler { call, result ->
                try {
                    if (!GoalWatchData.handle(this, call, result)) result.notImplemented()
                } catch (error: Exception) {
                    result.error("watch_failed", error.message, null)
                }
            }
            MethodChannel(messenger, "ondevice_llm/goal_watch_background").setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "work" -> result.success(mapOf(
                            "watches" to GoalWatchData.enabled(this).toString(),
                            "settings" to getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                                .getString("flutter.inference_settings_v1", null),
                        ))
                        "changed" -> {
                            val id = call.argument<Number>("id")?.toInt() ?: -1
                            val item = ScheduledPrompts.find(this, id)
                            if (item != null && item.optBoolean("enabled", true) && item.optString("kind") == "goal") {
                                val fresh = call.argument<Number>("fresh")?.toInt() ?: 0
                                val figures = call.argument<Number>("figures")?.toInt() ?: 0
                                val locale = call.argument<String>("locale") ?: "en"
                                if (fresh + figures > 0) ScheduledPrompts.notify(this, item, when (locale.take(2)) {
                                    "fr" -> "$fresh nouveaux résultats, $figures valeurs modifiées. Touchez pour consulter."
                                    "es" -> "$fresh resultados nuevos, $figures cifras cambiadas. Toca para ver."
                                    else -> "$fresh new results, $figures changed figures. Tap to review."
                                })
                            }
                            result.success(null)
                        }
                        "finished" -> {
                            val retry = call.argument<Boolean>("retry") == true
                            result.success(null)
                            handler.post { finish(params, retry) }
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("watch_failed", error.message, null)
                    handler.post { finish(params, false) }
                }
            }
            timeout = Runnable { finish(params, true) }.also { handler.postDelayed(it, 90_000) }
            worker.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(), "package:ondevice_llm/main.dart", "goalWatchBackgroundMain",
            ))
            Log.i("GoalWatch", "Headless check started")
            return true
        } catch (error: Exception) {
            Log.w("GoalWatch", "Could not start headless check", error)
            release()
            active = null
            return false
        }
    }

    private fun finish(params: JobParameters, retry: Boolean) {
        if (active !== params) return
        release()
        active = null
        Log.i("GoalWatch", "Headless check finished; retry=$retry")
        jobFinished(params, retry)
    }

    private fun release() {
        timeout?.let { handler.removeCallbacks(it) }
        timeout = null
        engine?.destroy()
        engine = null
    }

    override fun onStopJob(params: JobParameters): Boolean {
        if (active === params) { release(); active = null }
        return true
    }

    override fun onDestroy() { release(); active = null; super.onDestroy() }

    companion object {
        const val ID = 1329873665
        fun enqueue(context: Context) {
            val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            check(scheduler.schedule(JobInfo.Builder(ID, ComponentName(context, GoalWatchJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setBackoffCriteria(30_000, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
                .build()) == JobScheduler.RESULT_SUCCESS) { "Watch check could not be scheduled." }
        }
    }
}
