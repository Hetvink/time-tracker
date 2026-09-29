import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool downloadTextFile(
  String filename,
  String content, {
  String mime = 'text/csv',
}) {
  final blob = web.Blob(
    [content.toJS].toJS,
    web.BlobPropertyBag(type: '$mime;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..click();
  web.URL.revokeObjectURL(url);
  return true;
}
