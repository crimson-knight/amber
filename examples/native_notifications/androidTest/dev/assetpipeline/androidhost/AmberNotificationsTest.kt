package dev.assetpipeline.androidhost

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.ContextThemeWrapper
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.click
import androidx.test.espresso.action.ViewActions.scrollTo
import androidx.test.espresso.matcher.ViewMatchers.withText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleCallback
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicReference
import java.io.File

@RunWith(AndroidJUnit4::class)
class AmberNotificationsTest {
    @Test fun realPermissionDenialGrantRecreationPostUpdateCancelAndTerminalCleanup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        val manager = context.getSystemService(NotificationManager::class.java)
        val latest = AtomicReference<MainActivity>()
        val id = 84621
        val channels = listOf("ap_contract_updates", "ap_contract_blocked")
        fun owned() = manager.activeNotifications.filter { it.tag == PlatformNotifications.TAG && it.id == id }
        fun text(value: String) {
            // Status is near the top; the most recent button can be below it.
            onView(withText(value)).perform(scrollTo())
            assertTrue(device.wait(Until.hasObject(By.text(value)), 10000L))
        }
        fun press(label: String) { onView(withText(label)).perform(scrollTo(), click()) }
        fun answerPermission(button: String) {
            val selector = By.res("com.android.permissioncontroller", button)
            assertNotNull("Real permission dialog was not shown", device.wait(Until.findObject(selector), 10000L))
            // A node can exist before the system dialog's entrance animation
            // accepts touch. Re-resolve it and require the dialog to disappear.
            repeat(3) {
                device.waitForIdle(2000L)
                device.findObject(selector)?.click()
                if (device.wait(Until.gone(selector), 3000L)) return
            }
            fail("Permission dialog did not accept the selected answer")
        }
        fun waitStatus(value: String) {
            fun contains(view: View): Boolean = (view is TextView && view.text.toString() == value) ||
                (view is ViewGroup && (0 until view.childCount).any { contains(view.getChildAt(it)) })
            val deadline = SystemClock.elapsedRealtime() + 10000
            var found = false
            do {
                instrumentation.runOnMainSync { found = latest.get()?.let { contains(it.window.decorView) } == true }
                if (found) break
                Thread.sleep(20)
            } while (SystemClock.elapsedRealtime() < deadline)
            assertTrue("Native status did not become: $value", found)
            text(value)
        }
        // Only contract-owned channels/notification are touched. Android retains
        // deleted channel settings, so do not use deletion as a reset assertion.
        manager.cancel(PlatformNotifications.TAG, id)
        manager.createNotificationChannel(NotificationChannel(channels[1], "Contract blocked", NotificationManager.IMPORTANCE_NONE))
        assertEquals(NotificationManager.IMPORTANCE_NONE, manager.getNotificationChannel(channels[1]).importance)
        assertFalse("Runner must reset only this emulator package before instrumentation", manager.areNotificationsEnabled())
        instrumentation.runOnMainSync {
            assertEquals(ServiceStatus.UNAVAILABLE, PlatformNotifications(context).requestPermission(123)!!.status)
        }
        val monitor = ActivityLifecycleMonitorRegistry.getInstance()
        val listener = ActivityLifecycleCallback { activity, stage ->
            if (activity is MainActivity && stage == Stage.CREATED) latest.set(activity)
        }
        instrumentation.runOnMainSync { monitor.addLifecycleCallback(listener) }
        val scenario = ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_APP_SLUG, "notifications-contract"))
        try {
            text("Local notifications ready")
            assertFalse(device.hasObject(By.res("com.android.permissioncontroller", "permission_allow_button")))
            press("Post while denied"); waitStatus("Permission denied correctly")
            assertTrue(owned().isEmpty())
            press("Request permission")
            val permissionSelector = By.res("com.android.permissioncontroller", "permission_allow_button")
            assertNotNull(device.wait(Until.findObject(permissionSelector), 10000L))
            device.waitForIdle(2000L)
            device.pressBack()
            assertTrue("Dismissal must return to the app", device.wait(Until.gone(permissionSelector), 5000L))
            waitStatus("Permission result: false")
            assertFalse(manager.areNotificationsEnabled())
            press("Request permission")
            answerPermission("permission_deny_button")
            waitStatus("Permission result: false")
            assertFalse(manager.areNotificationsEnabled())

            press("Request 64")
            assertNotNull(device.wait(Until.findObject(By.res("com.android.permissioncontroller", "permission_allow_button")), 10000L))
            // Recreate while the OS owns the permission dialog. The new Activity
            // must reconnect to the original flight without a second prompt.
            val previous = latest.get()
            // ActivityScenario.recreate first insists on RESUMED, which cannot
            // happen while the real system dialog owns focus. Invoke the actual
            // Activity API and observe a replacement before answering instead.
            instrumentation.runOnMainSync { previous.recreate() }
            val recreationDeadline = SystemClock.elapsedRealtime() + 10000L
            while (latest.get() === previous && SystemClock.elapsedRealtime() < recreationDeadline) Thread.sleep(20)
            assertNotSame("Host was not recreated with the permission flight pending", previous, latest.get())
            instrumentation.runOnMainSync { assertTrue(previous.isChangingConfigurations) }
            answerPermission("permission_allow_button")
            waitStatus("Permission granted: 32, cancelled: 32")
            assertTrue(manager.areNotificationsEnabled())
            scenario.onActivity { assertEquals(Pair(0, 0), CrystalBridge.debugPendingServices()) }
            press("Request permission"); waitStatus("Permission result: true")
            assertFalse(device.hasObject(By.res("com.android.permissioncontroller", "permission_allow_button")))

            press("Post notification"); waitStatus("Posted")
            assertEquals(1, owned().size)
            val notification = owned().single().notification
            assertEquals(channels[0], notification.channelId)
            assertEquals("Hello 雪 😀", notification.extras.getString(Notification.EXTRA_TITLE))
            assertNotNull(notification.smallIcon)
            assertTrue(notification.contentIntent.isImmutable)
            assertEquals(Notification.VISIBILITY_PRIVATE, notification.visibility)
            assertNull(manager.getNotificationChannel(channels[0]).sound)
            press("Update notification"); waitStatus("Updated")
            assertEquals(1, owned().size)
            assertEquals("Updated 雪 😀", owned().single().notification.extras.getString(Notification.EXTRA_TITLE))
            device.openNotification()
            assertTrue("Posted notification did not appear in the real system shade", device.wait(Until.hasObject(By.text("Updated 雪 😀")), 10000L))
            val screenshot = File(context.getExternalFilesDir(null), "notification-shade.png")
            assertTrue(device.takeScreenshot(screenshot))
            device.pressBack()
            assertTrue(device.wait(Until.gone(By.text("Updated 雪 😀")), 5000L))
            val focusDeadline = SystemClock.elapsedRealtime() + 5000L
            var focused = false
            do {
                instrumentation.runOnMainSync { focused = latest.get().hasWindowFocus() }
                if (focused) break
                Thread.sleep(20)
            } while (SystemClock.elapsedRealtime() < focusDeadline)
            assertTrue("Notification shade did not return input focus to the host", focused)
            press("Post maximum text"); waitStatus("Maximum posted")
            assertEquals("T".repeat(1024), owned().single().notification.extras.getString(Notification.EXTRA_TITLE))
            assertEquals("B".repeat(1024), owned().single().notification.extras.getString(Notification.EXTRA_TEXT))
            assertEquals("B".repeat(1024), owned().single().notification.extras.getString(Notification.EXTRA_BIG_TEXT))
            press("Post blocked channel"); waitStatus("Blocked channel respected")
            assertEquals(NotificationManager.IMPORTANCE_NONE, manager.getNotificationChannel(channels[1]).importance)
            press("Post unknown channel"); waitStatus("Unknown channel rejected")
            assertNull(manager.getNotificationChannel("unknown"))
            press("Cancel notification"); waitStatus("Cancelled"); assertTrue(owned().isEmpty())
            press("Cancel notification"); waitStatus("Cancelled"); assertTrue(owned().isEmpty())
            scenario.onActivity { assertEquals(Pair(0, 0), CrystalBridge.debugPendingServices()) }
            instrumentation.sendStatus(2, Bundle().apply { putString("notification_contract", "dismiss denial grant recreation coalescing no-host post update shade maximum-text blocked cancel") })
        } finally {
            scenario.close()
            instrumentation.runOnMainSync { monitor.removeLifecycleCallback(listener) }
            manager.cancel(PlatformNotifications.TAG, id)
            channels.forEach(manager::deleteNotificationChannel)
        }
        instrumentation.runOnMainSync {
            assertEquals(CrystalBridge.NativeDebugCounts(0, 0), CrystalBridge.debugCounts())
            val owner = Any()
            val themed = ContextThemeWrapper(context, com.google.android.material.R.style.Theme_Material3_DayNight_NoActionBar)
            CrystalBridge.attachHost(owner); CrystalBridge.foregroundHost(owner)
            assertNotNull(CrystalBridge.renderStudy(themed, "notifications-close"))
            assertEquals(Pair(32, 32), CrystalBridge.debugPendingServices())
            CrystalBridge.detachHost(owner); CrystalBridge.closeSession()
        }
        val deadline = SystemClock.elapsedRealtime() + 10000
        var pending = Pair(-1, -1)
        do {
            instrumentation.runOnMainSync { pending = CrystalBridge.debugPendingServices() }
            if (pending == Pair(0, 0)) break
            Thread.sleep(20)
        } while (SystemClock.elapsedRealtime() < deadline)
        assertEquals(Pair(0, 0), pending)
        instrumentation.runOnMainSync { assertEquals(CrystalBridge.NativeDebugCounts(0, 0), CrystalBridge.debugCounts()) }
    }
}
