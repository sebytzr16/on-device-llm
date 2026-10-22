import 'dart:async';
import 'dart:io';

/// The suite never touches the network: a provider the app calls by default
/// (Wikipedia, the second search engine) fails at once instead of reaching
/// the real service. Servers the tests start on this machine stay reachable.
/// Live checks under test/live opt in with LIVE_WEB=1.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (Platform.environment['LIVE_WEB'] != '1') {
    HttpOverrides.global = _Offline();
  }
  await testMain();
}

class _Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (url, proxyHost, proxyPort) {
          if (!_local(url.host)) {
            return Future.error(
              SocketException(
                'The test suite does not use the network (${url.host})',
              ),
            );
          }
          return url.scheme == 'https'
              ? SecureSocket.startConnect(
                  url.host,
                  url.port,
                  context: context,
                  onBadCertificate: (_) => true,
                )
              : Socket.startConnect(url.host, url.port);
        };

  static bool _local(String host) {
    if (host == 'localhost') return true;
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    if (address.isLoopback) return true;
    // A test may bind its server to this machine's LAN address.
    return address.type == InternetAddressType.IPv4 &&
        RegExp(
          r'^(?:10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)',
        ).hasMatch(host);
  }
}
