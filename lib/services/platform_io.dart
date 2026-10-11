import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

bool get isMobile => Platform.isAndroid || Platform.isIOS;

/// Ask the user for a text file (JSON). null = cancelled.
Future<String?> pickTextFile({List<String> extensions = const ['json']}) async {
  final group = XTypeGroup(
    label: extensions.join('/').toUpperCase(),
    extensions: extensions,
    mimeTypes: const ['application/json', 'text/plain', 'application/octet-stream'],
  );
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  return file.readAsString();
}

/// Save bytes under a suggested name. Desktop: native "save as" dialog. Android / iOS: write the file and
/// open the system share sheet (save to Files / Drive / send). Returns false when the user cancelled.
Future<bool> saveBytes(String suggestedName, Uint8List bytes, {String label = 'File', String mime = 'application/octet-stream'}) async {
  if (isMobile) {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$suggestedName';
    await File(path).writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(path, mimeType: mime, name: suggestedName)]);
    return true;
  }
  final ext = suggestedName.contains('.') ? suggestedName.split('.').last : '';
  final loc = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [XTypeGroup(label: label, extensions: ext.isEmpty ? null : [ext])],
  );
  if (loc == null) return false;
  await File(loc.path).writeAsBytes(bytes, flush: true);
  return true;
}

Future<void> openExternal(String url) async {
  final uri = Uri.parse(url);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
