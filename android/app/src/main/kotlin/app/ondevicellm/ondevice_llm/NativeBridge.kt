package app.ondevicellm.ondevice_llm

import android.util.Log
import java.util.concurrent.atomic.AtomicLong

/// Frees the native models of a window that closed. Closing the app with Back
/// destroys the window's Flutter engine and Dart isolates, but Android keeps
/// the process, and with it a model nothing can reach any more; the next
/// launch then loaded a second copy on top (report 2026-09-28). Each
/// window tags the runtimes it creates with its own owner id. Dart opens the
/// bridge with dlopen and reports which library it chose; loading that same
/// library here shares Dart's copy, so the release reaches its runtimes.
object NativeBridge {
    private const val TAG = "OnDeviceLLM"
    private val owners = AtomicLong()
    private val libraries = mutableSetOf<String>()

    fun newOwner(): Long = owners.incrementAndGet()

    /// [file] is the library Dart opened, e.g. libondevice_llm_opencl.so.
    fun opened(file: String) {
        if (!file.startsWith("lib") || !file.endsWith(".so")) return
        synchronized(libraries) { libraries.add(file.removePrefix("lib").removeSuffix(".so")) }
    }

    /// Runs off the main thread: a load in progress is cancelled first, and
    /// freeing a few gigabytes takes a moment.
    fun release(owner: Long) {
        val names = synchronized(libraries) { libraries.toList() }
        if (names.isEmpty()) return
        Thread({
            for (name in names) {
                try {
                    System.loadLibrary(name)
                    val freed = releaseOwner(owner)
                    if (freed > 0) Log.i(TAG, "Freed $freed model(s) of a closed window")
                } catch (e: Throwable) {
                    Log.w(TAG, "Could not free the models of a closed window", e)
                }
            }
        }, "native-release").start()
    }

    @JvmStatic private external fun releaseOwner(owner: Long): Int
}
