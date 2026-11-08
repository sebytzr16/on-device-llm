package app.ondevicellm.ondevice_llm

import android.content.Context
import android.content.Intent
import android.test.AndroidTestCase
import android.app.Activity
import io.flutter.plugin.common.BinaryMessenger
import java.lang.reflect.Proxy
import java.util.ArrayDeque

@Suppress("DEPRECATION")
class ScheduledIntentSecurityTest : AndroidTestCase() {
    private var previousItems: String? = null
    private var previousToken: String? = null
    override fun setUp() {
        super.setUp()
        resetBudgets()
        val prefs = context.getSharedPreferences("scheduled_prompts", Context.MODE_PRIVATE)
        previousItems = prefs.getString("items", null)
        previousToken = prefs.getString("intent_token", null)
        prefs.edit()
            .putString("items", """[{"id":42,"prompt":"saved prompt","kind":"chat","enabled":true},
                {"id":43,"prompt":"disabled","enabled":false}]""").commit()
    }

    override fun tearDown() {
        resetBudgets()
        context.getSharedPreferences("scheduled_prompts", Context.MODE_PRIVATE).edit()
            .putString("items", previousItems).putString("intent_token", previousToken).commit()
        super.tearDown()
    }

    private fun intent(id: Int, trusted: Boolean = true) = Intent(ScheduledPrompts.ACTION_RUN)
        .putExtra(ScheduledPrompts.EXTRA_ID, id)
        .putExtra(ScheduledPrompts.EXTRA_PROMPT, "attacker prompt")
        .putExtra(ScheduledPrompts.EXTRA_KIND, "goal")
        .putExtra(ScheduledPrompts.EXTRA_TOKEN, if (trusted) ScheduledPrompts.token(context) else "forged")

    private fun resetBudgets() {
        for (name in listOf("runTimes", "draftTimes")) {
            val field = ScheduledPrompts::class.java.declaredFields.firstOrNull { it.name == name } ?: continue
            field.isAccessible = true
            (field.get(null) as ArrayDeque<*>).clear()
        }
    }

    private fun inbox(): ShareInbox {
        val activity = object : Activity() {
            fun attach() { attachBaseContext(context) }
        }
        activity.attach()
        val messenger = Proxy.newProxyInstance(BinaryMessenger::class.java.classLoader,
            arrayOf(BinaryMessenger::class.java)) { _, _, _ -> null } as BinaryMessenger
        return ShareInbox(activity, messenger)
    }

    @Suppress("UNCHECKED_CAST")
    private fun pending(inbox: ShareInbox): ArrayDeque<Intent> {
        val field = ShareInbox::class.java.getDeclaredField("pending")
        field.isAccessible = true
        return field.get(inbox) as ArrayDeque<Intent>
    }

    fun testForgedBurstCannotSpendTrustedBudgetAtIntake() {
        val inbox = inbox()
        repeat(50) { inbox.offer(intent(42, false), false) }
        assertTrue("Draft intake must stay bounded", pending(inbox).size <= 5)
        // Even after a rate window expires, unread drafts cannot grow the queue.
        resetBudgets()
        repeat(50) { inbox.offer(intent(42, false), false) }
        assertEquals(5, pending(inbox).size)
        val before = pending(inbox).size
        inbox.offer(intent(42), false)
        assertEquals("Valid notification survives forged burst", before + 1, pending(inbox).size)
        assertEquals("chat", ShareInbox.scheduledPayload(context, pending(inbox).last())["scheduled"])
    }

    fun testInvalidSavedSchedulesDoNotSpendTrustedBudgetAtIntake() {
        val inbox = inbox()
        repeat(10) { inbox.offer(intent(if (it % 2 == 0) 43 else 99), false) }
        assertTrue(pending(inbox).isEmpty())
        repeat(5) { inbox.offer(intent(42), false) }
        assertEquals(5, pending(inbox).size)
        inbox.offer(intent(42), false)
        assertEquals(5, pending(inbox).size)
    }

    fun testTrustedRunUsesSavedPromptAndKind() {
        val payload = ShareInbox.scheduledPayload(context, intent(42))
        assertEquals("saved prompt", payload["text"])
        assertEquals("chat", payload["scheduled"])
    }

    fun testDeletedDisabledAndMissingIdsCannotRun() {
        for (id in listOf(43, 99, -1)) {
            assertTrue(ShareInbox.scheduledPayload(context, intent(id)).isEmpty())
        }
    }

    fun testUntrustedIntentIsOnlyADraft() {
        val payload = ShareInbox.scheduledPayload(context, intent(42, false))
        assertEquals("attacker prompt", payload["text"])
        assertFalse(payload.containsKey("scheduled"))
    }

    fun testRateLimitAndWindowBoundary() {
        val now = 1_000_000_000_000L
        repeat(5) { assertTrue(ScheduledPrompts.allowScheduledRun(now)) }
        assertFalse(ScheduledPrompts.allowScheduledRun(now + 59_999L))
        assertTrue(ScheduledPrompts.allowScheduledRun(now + 60_000L))
    }
}
