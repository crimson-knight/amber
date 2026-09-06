package dev.assetpipeline.androidhost

import android.content.Context
import android.content.Intent
import android.widget.EditText
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.lifecycle.Lifecycle
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.click
import androidx.test.espresso.action.ViewActions.closeSoftKeyboard
import androidx.test.espresso.action.ViewActions.replaceText
import androidx.test.espresso.action.ViewActions.scrollTo
import androidx.test.espresso.action.ViewActions.typeText
import androidx.test.espresso.matcher.ViewMatchers.isAssignableFrom
import androidx.test.espresso.matcher.ViewMatchers.withText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AmberNativeApplicationTest {
    private fun awaitText(text: String) {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        assertTrue("Native application did not display: $text", device.wait(Until.hasObject(By.text(text)), 5000L))
    }

    @Test
    fun sharedAmberUseCaseValidatesInputAndRetainsStateAcrossRecreation() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val intent = Intent(context, MainActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_APP_SLUG, "amber-counter")
        }
        val scenario = ActivityScenario.launch<MainActivity>(intent)
        try {
            onView(withText("Session: Foreground / starts 1 / backgrounds 0")).perform(scrollTo())
            awaitText("Session: Foreground / starts 1 / backgrounds 0")
            onView(withText("Increment")).perform(scrollTo(), click())
            awaitText("Count: 1")
            onView(isAssignableFrom(EditText::class.java)).perform(scrollTo(), typeText("Android"), closeSoftKeyboard())
            onView(withText("Rename")).perform(scrollTo(), click())
            awaitText("Name accepted by shared schema.")
            onView(withText("Name: Android")).perform(scrollTo())
            awaitText("Name: Android")

            onView(isAssignableFrom(EditText::class.java)).perform(scrollTo(), replaceText("x"), closeSoftKeyboard())
            onView(withText("Rename")).perform(scrollTo(), click())
            awaitText("Name rejected by shared schema.")
            scenario.moveToState(Lifecycle.State.CREATED)
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                assertEquals(HostSession.State.BACKGROUND, CrystalBridge.debugSessionState())
            }
            scenario.moveToState(Lifecycle.State.RESUMED)
            onView(withText("Session: Foreground / starts 1 / backgrounds 1")).perform(scrollTo())
            awaitText("Session: Foreground / starts 1 / backgrounds 1")
            scenario.recreate()
            onView(withText("Session: Foreground / starts 1 / backgrounds 2")).perform(scrollTo())
            awaitText("Session: Foreground / starts 1 / backgrounds 2")
            onView(withText("Name: Android")).perform(scrollTo())
            awaitText("Name: Android")
            onView(withText("Count: 1")).perform(scrollTo())
            awaitText("Count: 1")
        } finally {
            scenario.close()
        }
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertEquals(CrystalBridge.NativeDebugCounts(0, 0), CrystalBridge.debugCounts())
        }
    }
}
