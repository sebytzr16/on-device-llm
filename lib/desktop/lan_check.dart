import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why a phone on the same Wi-Fi may not reach this PC's server: Windows
/// blocks inbound connections on networks marked Public, a firewall rule
/// may block (or not yet allow) the app, and VPN clients often hide the LAN.
class LanCheck {
  /// Connected networks Windows treats as Public.
  final List<String> publicNetworks;

  /// The firewall verdict for this app on the connected network categories:
  /// true allowed, false blocked, null no rule (Windows asks on first use).
  final bool? firewall;

  /// VPN adapters with an address.
  final List<String> vpns;

  /// The firewall applies its Public profile right now.
  final bool onPublic;

  const LanCheck({
    this.publicNetworks = const [],
    this.firewall,
    this.vpns = const [],
    this.onPublic = false,
  });

  bool get clear => publicNetworks.isEmpty && firewall == true && vpns.isEmpty;

  static final vpnName = RegExp(
    r'nordlynx|openvpn|wireguard|tailscale|zerotier|vpn|tap-',
    caseSensitive: false,
  );

  static Future<LanCheck> run() async {
    if (!Platform.isWindows) return const LanCheck(firewall: true);
    final vpns = <String>[
      for (final i in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      ))
        if (vpnName.hasMatch(i.name) &&
            i.addresses.any((a) => !a.isLinkLocal && !a.isLoopback))
          i.name,
    ];
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    // The firewall's COM API answers in about a second; the NetSecurity
    // cmdlets take half a minute to match rules by program.
    final script =
        '''
\$fw = New-Object -ComObject HNetCfg.FwPolicy2
\$r = @(\$fw.Rules | Where-Object { \$_.ApplicationName -and \$_.ApplicationName -ieq '$exe' -and \$_.Direction -eq 1 -and \$_.Enabled } | ForEach-Object { @{ action = \$_.Action; profiles = \$_.Profiles } })
\$p = @(Get-NetConnectionProfile | ForEach-Object { @{ alias = "\$(\$_.InterfaceAlias)"; category = "\$(\$_.NetworkCategory)" } })
@{ current = \$fw.CurrentProfileTypes; profiles = \$p; rules = \$r } | ConvertTo-Json -Depth 4 -Compress
''';
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        _encode(script),
      ]);
      final json = jsonDecode('${result.stdout}'.trim()) as Map;
      return parse(json, vpns: vpns);
    } catch (_) {
      return LanCheck(vpns: vpns);
    }
  }

  /// [json]: current (profile bitmask: 1 domain, 2 private, 4 public),
  /// profiles ({alias, category}) and the app's inbound rules ({action:
  /// 0 block / 1 allow, profiles bitmask}).
  static LanCheck parse(Map json, {List<String> vpns = const []}) {
    List<Map> list(Object? v) => v is List
        ? v.whereType<Map>().toList()
        : v is Map
        ? [v]
        : const [];
    final public = [
      for (final p in list(json['profiles']))
        if ('${p['category']}'.toLowerCase() == 'public') '${p['alias']}',
    ];
    final current = (json['current'] as num?)?.toInt() ?? 0;
    final rules = list(
      json['rules'],
    ).where((r) => ((r['profiles'] as num?)?.toInt() ?? 0) & current != 0);
    final blocked = rules.any((r) => r['action'] == 0);
    final allowed = rules.any((r) => r['action'] == 1);
    return LanCheck(
      publicNetworks: public,
      firewall: blocked
          ? false
          : allowed
          ? true
          : null,
      vpns: vpns,
      onPublic: current & 4 != 0,
    );
  }

  /// Removes inbound block rules for this app (each renamed to a GUID
  /// first: Windows names its TCP and UDP rules alike, and removing by a
  /// shared name may drop the wrong one, P3-34) and allows it on private and
  /// domain networks, and on public ones when [public] (the network in use
  /// is one). Windows asks the user to approve (UAC).
  static Future<void> allowInFirewall({bool public = false}) async {
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    final fix =
        '''
\$fw = New-Object -ComObject HNetCfg.FwPolicy2
@(\$fw.Rules | Where-Object { \$_.ApplicationName -ieq '$exe' -and \$_.Direction -eq 1 -and \$_.Action -eq 0 }) | ForEach-Object { \$id = [guid]::NewGuid().ToString(); \$_.Name = \$id; \$fw.Rules.Remove(\$id) }
New-NetFirewallRule -DisplayName 'OnDevice LLM local server' -Direction Inbound -Action Allow -Program '$exe' -Profile Private,Domain${public ? ',Public' : ''} | Out-Null
''';
    await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden "
          "-ArgumentList '-NoProfile','-EncodedCommand','${_encode(fix)}'",
    ]);
  }

  static String _encode(String script) {
    final units = script.codeUnits;
    final bytes = <int>[
      for (final u in units) ...[u & 0xff, u >> 8],
    ];
    return base64Encode(bytes);
  }
}

final lanCheckProvider = FutureProvider.autoDispose<LanCheck>(
  (ref) => LanCheck.run(),
);
