import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:daemon/utils/config.dart';

class AnalyzerWriter {
  Future<void> write(String content) async {
    final filename = _buildFilename();
    final blob = html.Blob([content], 'text/plain');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement;
    anchor.href = url;
    anchor.download = filename;
    anchor.style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> writeJson(String filename, String jsonContent) async {
    final blob = html.Blob([jsonContent], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement;
    anchor.href = url;
    anchor.download = filename;
    anchor.style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  String _buildFilename() {
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    return 'analyzer_sf${SUBFRAMES}_rng${RANGE}_cars${CARNUM}_rsu${RSUNUM}_broadcast${BROADCAST}_resettime${RESETTIME}_$ts.txt';
  }

  Future<Uint8List?> writeZip(String zipFileName, String jsonFilename, String jsonContent, String logFilename, String logContent) async {
    // create ZIP in-memory
    final archive = Archive();
    final jsonBytes = jsonContent.codeUnits;
    final logBytes = logContent.codeUnits;
    archive.addFile(ArchiveFile(jsonFilename, jsonBytes.length, jsonBytes));
    archive.addFile(ArchiveFile(logFilename, logBytes.length, logBytes));
    final encoder = ZipEncoder();
    final bytes = encoder.encode(archive) ?? [];
    // created zip bytes
    return Uint8List.fromList(bytes);
  }

  Future<String?> writeBytes(String filename, Uint8List bytes) async {
    final blob = html.Blob([bytes], 'application/octet-stream');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement;
    anchor.href = url;
    anchor.download = filename;
    anchor.style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
    // triggered download for $filename
    return filename;
  }
}
