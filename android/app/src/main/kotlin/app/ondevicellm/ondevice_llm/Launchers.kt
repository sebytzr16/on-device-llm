package app.ondevicellm.ondevice_llm

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.TileService
import android.widget.RemoteViews

/// Ways into the app from outside it: the quick-settings tile and the home
/// screen widget open MainActivity with [ACTION_LAUNCH] and a [EXTRA_MODE]
/// ("voice" starts a voice conversation, "chat" a new chat); ShareInbox
/// hands the mode to Dart. Nothing runs in the background.
object Launchers {
    const val ACTION_LAUNCH = "app.ondevicellm.ondevice_llm.LAUNCH"
    const val EXTRA_MODE = "mode"

    fun intent(context: Context, mode: String): Intent =
        Intent(context, MainActivity::class.java)
            .setAction(ACTION_LAUNCH)
            .putExtra(EXTRA_MODE, mode)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    fun pending(context: Context, mode: String, code: Int): PendingIntent =
        PendingIntent.getActivity(
            context,
            code,
            intent(context, mode),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}

/// Quick settings tile: talk to the model.
class VoiceTileService : TileService() {
    override fun onClick() {
        super.onClick()
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(Launchers.pending(this, "voice", 41))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(Launchers.intent(this, "voice"))
        }
    }
}

/// Home screen widget: "Ask" opens a new chat, "Talk" a voice conversation.
class AskWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.ask_widget)
            views.setOnClickPendingIntent(R.id.widget_ask, Launchers.pending(context, "chat", 42))
            views.setOnClickPendingIntent(R.id.widget_talk, Launchers.pending(context, "voice", 43))
            manager.updateAppWidget(id, views)
        }
    }
}
