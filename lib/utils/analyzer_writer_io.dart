import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'dart:typed_data';

class AnalyzerWriter {
  Future<void> write(String content) async {
    // Use current working directory to ensure saved files end up in project root instead of script location
    final path = Directory.current.path;
    final file = File('$path/analyzer_log.txt');
    final sink = file.openWrite(mode: FileMode.writeOnlyAppend);

    sink.write(content);
    await sink.flush();
    await sink.close();
  }

  Future<void> writeJson(String filename, String jsonContent) async {
    final path = Directory.current.path;
    final file = File('$path/$filename');
    await file.writeAsString(jsonContent, flush: true);
  }

  Future<Uint8List?> writeZip(String zipFileName, String jsonFilename, String jsonContent, String logFilename, String logContent) async {
    // Create zip bytes in-memory and return them; writing to file is performed by writeBytes
    final archive = Archive();
    final jsonBytes = jsonContent.codeUnits;
    final logBytes = logContent.codeUnits;
    archive.addFile(ArchiveFile(jsonFilename, jsonBytes.length, jsonBytes));
    archive.addFile(ArchiveFile(logFilename, logBytes.length, logBytes));
    final encoder = ZipEncoder();
    final bytes = encoder.encode(archive);
    if (bytes != null) {
      return Uint8List.fromList(bytes);
    }
    return null;
  }

  Future<String> writeBytes(String filename, Uint8List bytes) async {
    String basePath = Directory.current.path;
    // Prefer user's Desktop if available for easy discovery
    try {
      final envHome = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (envHome != null) {
        final desktop = Directory('$envHome/Desktop');
        if (await desktop.exists()) {
          basePath = desktop.path;
        }
      }
    } catch (_) {
      // ignore platform errors and fallback to Directory.current
    }
    final exportsDir = Directory('$basePath/analyzer_exports');
    if (!await exportsDir.exists()) await exportsDir.create(recursive: true);
    final file = File('${exportsDir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    // File written to exports dir
    return file.path;
  }
}
