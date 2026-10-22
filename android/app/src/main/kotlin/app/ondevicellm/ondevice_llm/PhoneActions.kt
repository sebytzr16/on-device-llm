package app.ondevicellm.ondevice_llm

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.AlarmClock
import android.provider.CalendarContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Opens the phone's own app with an action the assistant prepared: the
 * Calendar editor for an event or reminder, the Clock app for an alarm or
 * timer, the messaging or email app for a draft. Every one of them shows
 * its own screen (no EXTRA_SKIP_UI), so the user saves or sends there;
 * nothing happens without that.
 */
class PhoneActions(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "ondevice_llm/phone_actions")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "launch") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val args = call.arguments as? Map<*, *>
            val intent = args?.let { intentFor(it) }
            if (intent == null) {
                result.success(false)
                return@setMethodCallHandler
            }
            try {
                activity.startActivity(intent)
                result.success(true)
            } catch (_: ActivityNotFoundException) {
                result.success(false)
            } catch (_: SecurityException) {
                result.success(false)
            }
        }
    }

    private fun str(a: Map<*, *>, key: String) = (a[key] as? String)?.trim().orEmpty()

    private fun intentFor(a: Map<*, *>): Intent? = when (a["kind"]) {
        "event" -> Intent(Intent.ACTION_INSERT).apply {
            data = CalendarContract.Events.CONTENT_URI
            putExtra(CalendarContract.Events.TITLE, str(a, "title"))
            (a["begin"] as? Number)?.let {
                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, it.toLong())
            }
            (a["end"] as? Number)?.let {
                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, it.toLong())
            }
            if (a["allDay"] == true) {
                putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, true)
            }
            str(a, "location").takeIf { it.isNotEmpty() }?.let {
                putExtra(CalendarContract.Events.EVENT_LOCATION, it)
            }
            str(a, "description").takeIf { it.isNotEmpty() }?.let {
                putExtra(CalendarContract.Events.DESCRIPTION, it)
            }
            putExtra(CalendarContract.Events.HAS_ALARM, 1)
        }
        "alarm" -> Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_HOUR, (a["hour"] as? Number)?.toInt() ?: return null)
            putExtra(AlarmClock.EXTRA_MINUTES, (a["minute"] as? Number)?.toInt() ?: 0)
            str(a, "label").takeIf { it.isNotEmpty() }?.let {
                putExtra(AlarmClock.EXTRA_MESSAGE, it)
            }
            val days = (a["days"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }
            if (!days.isNullOrEmpty()) {
                putExtra(AlarmClock.EXTRA_DAYS, ArrayList(days))
            }
            putExtra(AlarmClock.EXTRA_SKIP_UI, false)
        }
        "timer" -> Intent(AlarmClock.ACTION_SET_TIMER).apply {
            putExtra(AlarmClock.EXTRA_LENGTH, (a["seconds"] as? Number)?.toInt() ?: return null)
            str(a, "label").takeIf { it.isNotEmpty() }?.let {
                putExtra(AlarmClock.EXTRA_MESSAGE, it)
            }
            putExtra(AlarmClock.EXTRA_SKIP_UI, false)
        }
        "message" -> messageIntent(a)
        else -> null
    }

    private fun messageIntent(a: Map<*, *>): Intent {
        val to = str(a, "to")
        val body = str(a, "body")
        val subject = str(a, "subject")
        val email = str(a, "channel") == "email" || to.contains('@')
        val sms = str(a, "channel") == "sms" ||
            (to.isNotEmpty() && to.matches(Regex("[+0-9 ()./-]{3,}")))
        return when {
            email -> Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("mailto:" + Uri.encode(to))
                putExtra(Intent.EXTRA_EMAIL, if (to.isEmpty()) arrayOf() else arrayOf(to))
                if (subject.isNotEmpty()) putExtra(Intent.EXTRA_SUBJECT, subject)
                putExtra(Intent.EXTRA_TEXT, body)
            }
            sms -> Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("smsto:" + Uri.encode(to.replace(" ", "")))
                putExtra("sms_body", body)
            }
            // No channel: the share sheet lets the user pick any app.
            else -> Intent.createChooser(
                Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    if (subject.isNotEmpty()) putExtra(Intent.EXTRA_SUBJECT, subject)
                    putExtra(Intent.EXTRA_TEXT, body)
                },
                null,
            )
        }
    }
}
