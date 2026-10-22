package app.ondevicellm.ondevice_llm

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/// Scheduled prompts: once a day at the chosen time a notification offers a
/// saved prompt ("What's the news in Canada?"). Goal watches instead enqueue
/// a bounded background search/diff and alert on change. The list lives here
/// (it must survive a reboot); Dart reads and
/// replaces it through "ondevice_llm/schedule".
class ScheduledPrompts(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "ondevice_llm/schedule")
    private var permissionResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            // JSONException is a checked exception the channel does not
            // catch: report every failure to Dart instead of crashing.
            try {
                if (GoalWatchData.handle(activity, call, result)) return@setMethodCallHandler
                when (call.method) {
                    "list" -> result.success(load(activity).toString())
                    "save" -> {
                        val json = call.arguments as? String ?: "[]"
                        save(activity, JSONArray(json))
                        result.success(null)
                    }
                    "requestPermission" -> requestPermission(result)
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("schedule_failed", error.message ?: error.toString(), null)
            }
        }
    }

    /// Android 13+ asks before an app may post notifications.
    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("permission_pending", "Notification permission is already being requested.", null)
            return
        }
        permissionResult = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    fun onPermissionResult(granted: Boolean) {
        permissionResult?.success(granted)
        permissionResult = null
    }

    companion object {
        const val ACTION_RUN = "app.ondevicellm.ondevice_llm.RUN_SCHEDULED"
        const val EXTRA_PROMPT = "scheduled_prompt"
        const val EXTRA_KIND = "scheduled_kind"
        const val PERMISSION_REQUEST = 4712
        private const val PREFS = "scheduled_prompts"
        private const val KEY = "items"
        private const val CHANNEL_ID = "scheduled"

        fun load(context: Context): JSONArray {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY, null) ?: return JSONArray()
            // A corrupt saved list must surface as an error. Returning [] would
            // make an export omit every reminder and a save overwrite them.
            return JSONArray(raw)
        }

        /// Replaces the list and its alarms, restoring the old list if alarm
        /// registration fails. commit() reports a failed preferences write.
        fun save(context: Context, items: JSONArray) {
            val old = load(context)
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            for (i in 0 until old.length()) cancel(context, old.getJSONObject(i).optInt("id"))
            // Posted notifications go only for prompts deleted or turned off;
            // another prompt's unread notification stays.
            val kept = (0 until items.length()).map { items.getJSONObject(it) }
                .filter { it.optBoolean("enabled", true) }
                .map { it.optInt("id") }.toSet()
            for (i in 0 until old.length()) {
                val id = old.getJSONObject(i).optInt("id")
                if (id !in kept) dismiss(context, id)
            }
            if (!prefs.edit().putString(KEY, items.toString()).commit()) {
                scheduleAll(context)
                throw IllegalStateException("Scheduled prompts could not be saved.")
            }
            try {
                scheduleAll(context)
            } catch (error: Exception) {
                for (i in 0 until items.length()) cancel(context, items.getJSONObject(i).optInt("id"))
                prefs.edit().putString(KEY, old.toString()).commit()
                scheduleAll(context)
                throw error
            }
        }

        fun scheduleAll(context: Context) {
            val items = load(context)
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                if (!item.optBoolean("enabled", true)) continue
                val next = Calendar.getInstance().apply {
                    set(Calendar.HOUR_OF_DAY, item.optInt("hour"))
                    set(Calendar.MINUTE, item.optInt("minute"))
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                    if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
                }
                // Inexact on purpose: no exact-alarm permission, and a
                // briefing a few minutes late is fine.
                alarms.setInexactRepeating(
                    AlarmManager.RTC_WAKEUP,
                    next.timeInMillis,
                    AlarmManager.INTERVAL_DAY,
                    alarmIntent(context, item.optInt("id")),
                )
            }
        }

        private fun cancel(context: Context, id: Int) {
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
                .cancel(alarmIntent(context, id))
        }

        private fun dismiss(context: Context, id: Int) {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(id)
        }

        private fun alarmIntent(context: Context, id: Int): PendingIntent = PendingIntent.getBroadcast(
            context,
            id,
            Intent(context, ScheduledPromptReceiver::class.java).putExtra("id", id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        fun find(context: Context, id: Int): JSONObject? {
            val items = load(context)
            for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                if (item.optInt("id") == id) return item
            }
            return null
        }

        fun notify(context: Context, item: JSONObject, message: String? = null) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Scheduled prompts", NotificationManager.IMPORTANCE_DEFAULT),
            )
            val id = item.optInt("id")
            val open = Intent(context, MainActivity::class.java)
                .setAction(ACTION_RUN)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(EXTRA_PROMPT, item.optString("prompt"))
                .putExtra(EXTRA_KIND, item.optString("kind", "chat"))
            val tap = PendingIntent.getActivity(
                context,
                id,
                open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val goal = item.optString("kind") == "goal"
            val notification = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_schedule)
                .setContentTitle(item.optString("title").ifBlank { if (goal) "Scheduled goal" else "Scheduled prompt" })
                .setContentText(message ?: if (goal) "Tap to set up: ${item.optString("prompt")}" else "Tap to ask: ${item.optString("prompt")}")
                .setStyle(Notification.BigTextStyle().bigText(message ?: item.optString("prompt")))
                .setContentIntent(tap)
                .setAutoCancel(true)
                .build()
            try {
                manager.notify(id, notification)
            } catch (_: SecurityException) {
                // Notifications not allowed: nothing to show.
            }
        }
    }
}

/// The daily alarm: posts the prompt's notification.
class ScheduledPromptReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // A corrupt saved list must not crash a background receiver.
        val item = try {
            ScheduledPrompts.find(context, intent.getIntExtra("id", -1))
        } catch (_: Exception) {
            null
        } ?: return
        if (item.optBoolean("enabled", true)) {
            val watches = try { GoalWatchData.load(context) } catch (_: Exception) { JSONArray() }
            val watched = (0 until watches.length()).any { watches.getJSONObject(it).optInt("id") == item.optInt("id") }
            if (item.optString("kind") == "goal" && watched) {
                try { GoalWatchJob.enqueue(context) } catch (error: Exception) {
                    android.util.Log.w("GoalWatch", "Could not schedule a watch check", error)
                }
            } else ScheduledPrompts.notify(context, item)
        }
    }
}

/// Alarms do not survive a reboot or an app update; set them again.
class ScheduledPromptsBoot : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            try {
                ScheduledPrompts.scheduleAll(context)
            } catch (_: Exception) {
                // Corrupt list: the app reports it when the page opens.
            }
        }
    }
}
