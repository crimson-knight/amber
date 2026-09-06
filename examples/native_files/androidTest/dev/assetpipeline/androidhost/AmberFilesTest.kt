package dev.assetpipeline.androidhost

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Process
import android.os.SystemClock
import android.view.ContextThemeWrapper
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
class AmberFilesTest {
    @Test fun nativeAdapterCompletesBinaryFileContractsAndLeavesRestartEvidence() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val intent = Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_APP_SLUG, "files-contract")
        val scenario = ActivityScenario.launch<MainActivity>(intent)
        try {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            assertTrue(device.wait(Until.hasObject(By.text("File contract passed: 88 checks")), 30000L))
            scenario.onActivity { assertEquals(Pair(0, 0), CrystalBridge.debugPendingServices()) }
            InstrumentationRegistry.getInstrumentation().sendStatus(2, Bundle().apply { putInt("persisted_process", Process.myPid()) })
        } finally { scenario.close() }
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertEquals(Pair(0, 0), CrystalBridge.debugPendingServices())
            assertEquals(CrystalBridge.NativeDebugCounts(0, 0), CrystalBridge.debugCounts())
            // Enqueue and close in one main-loop turn so all accepted replies
            // remain pending, even if the serial worker finishes a read quickly.
            val owner = Any()
            val themed = ContextThemeWrapper(context, com.google.android.material.R.style.Theme_Material3_DayNight_NoActionBar)
            CrystalBridge.attachHost(owner)
            CrystalBridge.foregroundHost(owner)
            assertNotNull(CrystalBridge.renderStudy(themed, "files-close"))
            assertEquals(Pair(32, 32), CrystalBridge.debugPendingServices())
            CrystalBridge.detachHost(owner)
            CrystalBridge.closeSession()
        }
        val deadline = SystemClock.elapsedRealtime() + 10000
        var pending = Pair(-1, -1)
        do {
            InstrumentationRegistry.getInstrumentation().runOnMainSync { pending = CrystalBridge.debugPendingServices() }
            if (pending == Pair(0, 0)) break
            Thread.sleep(20)
        } while (SystemClock.elapsedRealtime() < deadline)
        assertEquals("Terminal close did not drain file operations", Pair(0, 0), pending)
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertEquals(CrystalBridge.NativeDebugCounts(0, 0), CrystalBridge.debugCounts())
        }
    }
}

