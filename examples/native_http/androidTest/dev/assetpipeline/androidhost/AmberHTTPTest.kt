package dev.assetpipeline.androidhost

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.os.Bundle
import java.io.File
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AmberHTTPTest {
    @Test fun realTlsBinaryPayloadErrorsStorageIndependenceAndCancellation() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val scenario = ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_APP_SLUG, "http-contract"))
        try {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            assertTrue("TLS/HTTP contract did not reach cancellation", device.wait(Until.hasObject(By.text("HTTP cancellation ready")), 20000L))
            scenario.onActivity { assertEquals(Pair(4, 4), CrystalBridge.debugPendingServices()) }
            // The server withholds the rest of these bodies for twenty seconds.
            // A real mounted button dispatches cancellation back into Crystal.
            val start = SystemClock.elapsedRealtime()
            device.findObject(By.text("Cancel HTTP requests")).click()
            assertTrue(device.wait(Until.hasObject(By.text("HTTP contract passed")), 3000L))
            assertTrue("Cancellation waited for the server body", SystemClock.elapsedRealtime() - start < 3000)
            val screenshot = File(context.getExternalFilesDir(null), "http-contract.png")
            assertTrue(device.takeScreenshot(screenshot))
            InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
                putString("http_checks", device.findObject(By.textStartsWith("Checks: ")).text)
                putString("http_screenshot", screenshot.absolutePath)
            })
            scenario.onActivity { assertEquals(Pair(0, 0), CrystalBridge.debugPendingServices()) }
            scenario.recreate()
            assertTrue(device.wait(Until.hasObject(By.text("HTTP contract passed")), 3000L))
        } finally { scenario.close() }
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertEquals(Pair(0, 0), CrystalBridge.debugPendingServices())
            assertEquals(CrystalBridge.NativeDebugCounts(0, 0), CrystalBridge.debugCounts())
        }
        val closing = ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_APP_SLUG, "http-close"))
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        try {
            assertTrue(device.wait(Until.hasObject(By.text("HTTP close ready")), 3000L))
            closing.onActivity { assertEquals(Pair(4, 4), CrystalBridge.debugPendingServices()) }
        } finally { closing.close() }
        InstrumentationRegistry.getInstrumentation().runOnMainSync { CrystalBridge.closeSession() }
        val deadline = SystemClock.elapsedRealtime() + 3000
        var pending = Pair(-1, -1)
        do {
            InstrumentationRegistry.getInstrumentation().runOnMainSync { pending = CrystalBridge.debugPendingServices() }
            if (pending == Pair(0, 0)) break
            Thread.sleep(20)
        } while (SystemClock.elapsedRealtime() < deadline)
        assertEquals("Terminal close did not drain network operations", Pair(0, 0), pending)
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertEquals(CrystalBridge.NativeDebugCounts(0, 0), CrystalBridge.debugCounts())
        }
    }
}
