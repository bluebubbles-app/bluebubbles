import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/conversation.dart';

class MessageTransferService {
  static const format = 'bluebubbles-message-backup';
  static const version = 1;

  Future<void> exportMessages(List<Conversation> conversations) async {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': version,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'conversations': conversations.map((item) => item.toJson()).toList(),
    });
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.').first;
    final file = File('${directory.path}/bluebubbles-$timestamp.json');
    await file.writeAsString(payload, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'BlueBubbles message export',
    );
  }

  Future<List<Conversation>?> importMessages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final selected = result.files.single;
    final bytes = selected.bytes ?? await _readPath(selected.path);
    if (bytes == null) {
      throw const FormatException('The selected file could not be read.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('This is not a BlueBubbles backup.');
    }
    final root = Map<String, Object?>.from(decoded);
    if (root['format'] != format || root['version'] != version) {
      throw const FormatException('Unsupported BlueBubbles backup format.');
    }
    final items = root['conversations'];
    if (items is! List) {
      throw const FormatException('The backup contains no conversations.');
    }
    return items
        .whereType<Map>()
        .map(
          (item) => Conversation.fromJson(
            Map<String, Object?>.from(item),
          ),
        )
        .toList();
  }

  Future<Uint8List?> _readPath(String? path) async {
    if (path == null) return null;
    return File(path).readAsBytes();
  }
}
