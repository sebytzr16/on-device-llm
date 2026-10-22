import 'dart:io';
import 'package:flutter/services.dart';

class DiscoveredHost {
  final String name, endpoint;
  const DiscoveredHost(this.name, this.endpoint);
  static DiscoveredHost? parse(Map<Object?, Object?> value) {
    final address = value['host'], port = value['port'], name = value['name'];
    if (address is! String ||
        port is! num ||
        name is! String ||
        !port.isFinite ||
        port.toInt() != port ||
        port < 1 ||
        port > 65535) {
      return null;
    }
    final ip = InternetAddress.tryParse(address);
    if (ip == null || ip.isLoopback || ip.isMulticast || ip.isLinkLocal) {
      return null;
    }
    final bytes = ip.rawAddress;
    final local = bytes.length == 4
        ? bytes[0] == 10 ||
              bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31 ||
              bytes[0] == 192 && bytes[1] == 168
        : bytes[0] & 0xfe == 0xfc;
    if (!local) return null;
    return DiscoveredHost(
      name.substring(0, name.length.clamp(0, 100)),
      Uri(
        scheme: 'http',
        host: ip.address,
        port: port.toInt(),
        path: '/v1/',
      ).toString(),
    );
  }
}

/// Discovery shares a local endpoint only, never pairing keys or chat data.
class HostDiscovery {
  static const channel = MethodChannel('ondevice_llm/discovery');
  static bool get supported => Platform.isAndroid || Platform.isIOS;
  static Future<void> advertise(int port) =>
      channel.invokeMethod<void>('advertise', {'port': port});
  static Future<void> stop() => channel.invokeMethod<void>('stop');
  static Future<List<DiscoveredHost>> browse() async {
    final result =
        await channel.invokeListMethod<dynamic>('browse') ?? const [];
    final hosts = <String, DiscoveredHost>{};
    for (final item in result.take(16)) {
      if (item is Map) {
        final host = DiscoveredHost.parse(item);
        if (host != null) hosts[host.endpoint] = host;
      }
    }
    return hosts.values.toList();
  }
}
