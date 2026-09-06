package dev.assetpipeline.androidhost

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
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
class AmberHTTPDeniedTest {
    @Test fun libraryCannotGrantInternetAndAmberReceivesPermissionDenied() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        assertEquals(PackageManager.PERMISSION_DENIED, context.checkSelfPermission(android.Manifest.permission.INTERNET))
        val scenario = ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_APP_SLUG, "http-denied"))
        try {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            assertTrue(device.wait(Until.hasObject(By.text("HTTP permission denied correctly")), 5000L))
            scenario.onActivity { assertEquals(Pair(0, 0), CrystalBridge.debugPendingServices()) }
        } finally { scenario.close() }
    }
}
