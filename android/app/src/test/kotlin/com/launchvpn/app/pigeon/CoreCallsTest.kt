package com.launchvpn.app.pigeon

import android.app.Application
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class CoreCallsTest {
    private val measurement = """{"method":"pingBatch","payload":{}}"""
    private val other = """{"method":"testXray","payload":{}}"""

    @Test fun measurementsOverlap() {
        val inside = CountDownLatch(2)
        val release = CountDownLatch(1)
        val calls = CoreCalls {
            inside.countDown()
            release.await(5, TimeUnit.SECONDS)
            "ok"
        }

        val threads = List(2) { thread { calls.invoke(measurement) } }

        assertTrue("measurements ran one at a time", inside.await(2, TimeUnit.SECONDS))
        release.countDown()
        threads.forEach(Thread::join)
    }

    @Test fun anotherCallWaitsForMeasurementsInFlight() {
        val measuring = CountDownLatch(1)
        val release = CountDownLatch(1)
        val otherRan = CountDownLatch(1)
        val calls = CoreCalls { request ->
            if (request == measurement) {
                measuring.countDown()
                release.await(5, TimeUnit.SECONDS)
            } else {
                otherRan.countDown()
            }
            "ok"
        }

        val probe = thread { calls.invoke(measurement) }
        measuring.await(2, TimeUnit.SECONDS)
        var result: Result<String>? = null
        val call = thread { result = calls.invoke(other) }

        assertFalse("ran beside a measurement", otherRan.await(300, TimeUnit.MILLISECONDS))
        release.countDown()
        probe.join()
        call.join()
        assertEquals("ok", result?.getOrNull())
    }
}
