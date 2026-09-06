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
class AmberNotificationsDeniedTest {
    @Test fun allPublicOperationsFailDeferredWithoutExplicitOptIn() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_APP_SLUG, "notifications-denied")).use { scenario ->
            assertTrue(device.wait(Until.hasObject(By.text("Notifications require explicit app opt-in")), 10000L))
            assertFalse(device.hasObject(By.res("com.android.permissioncontroller", "permission_allow_button")))
            scenario.onActivity { assertEquals(Pair(0, 0), CrystalBridge.debugPendingServices()) }
        }
        InstrumentationRegistry.getInstrumentation().runOnMainSync { assertEquals(CrystalBridge.NativeDebugCounts(0, 0), CrystalBridge.debugCounts()) }
    }
}
