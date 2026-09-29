import 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart'
    as impl;

/// Saves [content] as a file in the browser. Returns false on platforms
/// without a download mechanism (callers then copy to the clipboard).
bool downloadTextFile(
  String filename,
  String content, {
  String mime = 'text/csv',
}) => impl.downloadTextFile(filename, content, mime: mime);
