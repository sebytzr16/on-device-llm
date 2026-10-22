package app.ondevicellm.ondevice_llm

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Bonjour/NSD advertises the endpoint only. Pairing remains authenticated. */
@Suppress("DEPRECATION")
class HostDiscovery(context: Context, messenger: BinaryMessenger) {
    private val manager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val main = Handler(Looper.getMainLooper())
    private var registration: NsdManager.RegistrationListener? = null
    private var discovery: NsdManager.DiscoveryListener? = null
    private var reply: MethodChannel.Result? = null
    private var epoch = 0
    private val found = linkedMapOf<String, Map<String, Any>>()
    private val pending = mutableListOf<NsdServiceInfo>()
    private var resolving = false
    private val type = "_odllm._tcp."

    init {
        MethodChannel(messenger, "ondevice_llm/discovery").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "advertise" -> {
                        val port = requireNotNull(call.argument<Int>("port"))
                        require(port in 1..65535)
                        unpublish()
                        val info = NsdServiceInfo().apply { serviceName = "OnDevice LLM"; serviceType = type; setPort(port) }
                        val listener = object : NsdManager.RegistrationListener {
                            override fun onServiceRegistered(info: NsdServiceInfo) { }
                            override fun onRegistrationFailed(info: NsdServiceInfo, error: Int) { }
                            override fun onServiceUnregistered(info: NsdServiceInfo) { }
                            override fun onUnregistrationFailed(info: NsdServiceInfo, error: Int) { }
                        }
                        registration = listener
                        manager.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
                        result.success(null)
                    }
                    "stop" -> { unpublish(); result.success(null) }
                    "browse" -> browse(result)
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("discovery", error.message, null) }
        }
    }
    private fun unpublish() {
        registration?.let { try { manager.unregisterService(it) } catch (_: Exception) { } }
        registration = null
    }
    private fun browse(result: MethodChannel.Result) {
        if (reply != null) { result.error("discovery", "Discovery is already running.", null); return }
        val generation = ++epoch
        reply = result; found.clear(); pending.clear(); resolving = false
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) { }
            override fun onDiscoveryStopped(type: String) { }
            override fun onStartDiscoveryFailed(type: String, error: Int) { main.post { finish(generation) } }
            override fun onStopDiscoveryFailed(type: String, error: Int) { }
            override fun onServiceLost(info: NsdServiceInfo) { main.post { if (generation == epoch) found.remove(info.serviceName) } }
            override fun onServiceFound(info: NsdServiceInfo) { main.post {
                if (generation == epoch && reply != null && info.serviceType.trimEnd('.') == type.trimEnd('.') && found.size + pending.size < 16) {
                    pending.add(info); resolve(generation)
                }
            } }
        }
        discovery = listener
        try { manager.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener) }
        catch (error: Exception) { discovery = null; reply = null; result.error("discovery", error.message, null); return }
        main.postDelayed({ finish(generation) }, 5000)
    }
    private fun resolve(generation: Int) {
        if (generation != epoch || reply == null || resolving || pending.isEmpty()) return
        resolving = true
        val info = pending.removeAt(0)
        val listener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, error: Int) { main.post {
                if (generation == epoch) { resolving = false; resolve(generation) }
            } }
            override fun onServiceResolved(info: NsdServiceInfo) { main.post {
                if (generation == epoch && reply != null) {
                    info.host?.hostAddress?.let { found[info.serviceName] = mapOf("name" to info.serviceName, "host" to it, "port" to info.port) }
                    resolving = false; resolve(generation)
                }
            } }
        }
        try { manager.resolveService(info, listener) } catch (_: Exception) { resolving = false; resolve(generation) }
    }
    private fun finish(generation: Int) {
        if (generation != epoch || reply == null) return
        val result = reply; reply = null
        discovery?.let { try { manager.stopServiceDiscovery(it) } catch (_: Exception) { } }
        discovery = null
        result?.success(found.values.toList())
        pending.clear()
    }
    fun close() { finish(epoch); ++epoch; unpublish() }
}
