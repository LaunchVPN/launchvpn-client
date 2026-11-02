// Lives in the plugin's package to read its package-private EXTRA_ACTION, so a
// plugin update that renames the key fails here instead of on a device.
package io.flutter.plugins.quickactions

import android.app.Application
import android.content.ComponentName
import android.content.Intent
import com.launchvpn.app.MainActivity
import com.launchvpn.app.vpn.VpnController
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29, 34], application = Application::class)
class OpenAppStartIntentTest {
    private val context get() = RuntimeEnvironment.getApplication()

    @Test fun openingTheAppForAStartAsksDartToConnect() {
        val intent = VpnController.buildShortcutStartIntent(context)

        assertEquals(ComponentName(context, MainActivity::class.java), intent.component)
        assertEquals("startVpn", intent.getStringExtra(QuickActions.EXTRA_ACTION))
    }

    @Test fun aFreshLaunchKeepsTheStart() {
        val intent = VpnController.buildShortcutStartIntent(context)

        VpnController.dropReplayedStart(intent, restored = false)

        assertEquals("startVpn", intent.getStringExtra(QuickActions.EXTRA_ACTION))
    }

    @Test fun reopeningFromRecentsDoesNotConnectAgain() {
        val intent = VpnController.buildShortcutStartIntent(context)
            .addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)

        VpnController.dropReplayedStart(intent, restored = false)

        assertNull(intent.getStringExtra(QuickActions.EXTRA_ACTION))
    }

    @Test fun restoringAfterProcessDeathDoesNotConnectAgain() {
        val intent = VpnController.buildShortcutStartIntent(context)

        VpnController.dropReplayedStart(intent, restored = true)

        assertNull(intent.getStringExtra(QuickActions.EXTRA_ACTION))
    }
}
