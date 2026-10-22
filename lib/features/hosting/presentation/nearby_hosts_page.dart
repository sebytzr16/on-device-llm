import 'package:flutter/material.dart';
import '../../../core/l10n/l10n.dart';
import '../host_discovery.dart';
import '../../../core/design/app_design.dart';

class NearbyHostsPage extends StatefulWidget {
  const NearbyHostsPage({super.key});
  @override
  State<NearbyHostsPage> createState() => _NearbyHostsPageState();
}

class _NearbyHostsPageState extends State<NearbyHostsPage> {
  late Future<List<DiscoveredHost>> _hosts;
  @override
  void initState() {
    super.initState();
    _hosts = HostDiscovery.browse();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(t.nearbyHosts)),
      body: SafeArea(
        child: FutureBuilder<List<DiscoveredHost>>(
          future: _hosts,
          builder: (context, snapshot) => ListView(
            padding: const EdgeInsets.all(AppDesign.lg),
            children: [
              Text(t.nearbyHostsHint),
              const SizedBox(height: AppDesign.xl),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (snapshot.hasError)
                  Text('${snapshot.error}')
                else if (snapshot.data?.isEmpty != false)
                  Text(t.nearbyHostsNone),
                for (final host in snapshot.data ?? const <DiscoveredHost>[])
                  ListTile(
                    leading: const Icon(Icons.lan_outlined),
                    title: Text(host.name),
                    subtitle: Text(host.endpoint),
                    onTap: () => Navigator.pop(context, host),
                  ),
                TextButton(
                  onPressed: () =>
                      setState(() => _hosts = HostDiscovery.browse()),
                  child: Text(t.retry),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
