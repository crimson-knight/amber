package dev.assetpipeline.androidhost

import android.content.Context
import android.content.Intent
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
class AmberStorageTest {
    @Test fun nativeAdapterCompletesStorageContractsAndReleasesOperations() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val intent = Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_APP_SLUG, "storage-contract")
        val scenario = ActivityScenario.launch<MainActivity>(intent)
        try {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            assertTrue(device.wait(Until.hasObject(By.text("Storage contract passed: 78 checks")), 15000L))
            scenario.onActivity {
                assertEquals(Pair(0, 0), CrystalBridge.debugPendingServices())
            }
        } finally { scenario.close() }
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertEquals(Pair(0, 0), CrystalBridge.debugPendingServices())
            assertEquals(CrystalBridge.NativeDebugCounts(0, 0), CrystalBridge.debugCounts())
        }
    }
}
