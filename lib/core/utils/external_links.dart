import 'package:url_launcher/url_launcher.dart';

Future<void> openExternalLink(String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    return;
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw StateError('Could not open this link.');
  }
}
