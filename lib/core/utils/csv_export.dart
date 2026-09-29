import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/ui_kit.dart';
import 'file_download.dart';

String _cell(Object? v) {
  final s = v?.toString() ?? '';
  return s.contains(RegExp('[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String toCsv(List<String> header, List<List<Object?>> rows) => [
  header.map(_cell).join(','),
  for (final r in rows) r.map(_cell).join(','),
].join('\n');

/// Downloads the CSV on web; copies it to the clipboard elsewhere.
Future<void> exportCsv(
  BuildContext context, {
  required String filename,
  required List<String> header,
  required List<List<Object?>> rows,
}) async {
  final csv = toCsv(header, rows);
  if (downloadTextFile(filename, csv)) {
    showSnack(context, 'Downloaded $filename');
    return;
  }
  await Clipboard.setData(ClipboardData(text: csv));
  if (context.mounted) {
    showSnack(context, 'CSV copied to clipboard (${rows.length} rows)');
  }
}
