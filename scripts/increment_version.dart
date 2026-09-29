// ignore_for_file: avoid_print
import 'dart:io';

void main() async {
  final file = File('pubspec.yaml');
  if (!await file.exists()) {
    print('Error: pubspec.yaml not found');
    exit(1);
  }

  final lines = await file.readAsLines();
  final newLines = <String>[];
  bool versionUpdated = false;

  for (final line in lines) {
    if (line.trim().startsWith('version:') && !versionUpdated) {
      final parts = line.split(':');
      if (parts.length > 1) {
        final versionString = parts[1].trim();
        // Expected format: x.y.z+n
        final versionParts = versionString.split('+');
        final semver = versionParts[0].split('.');

        if (semver.length == 3) {
          int major = int.parse(semver[0]);
          int minor = int.parse(semver[1]);
          int patch = int.parse(semver[2]);
          int build = versionParts.length > 1
              ? int.tryParse(versionParts[1]) ?? 0
              : 0;

          // Increment logic
          patch++;
          if (patch >= 10) {
            patch = 1;
            minor++;
          }
          build++;

          final newVersion = '$major.$minor.$patch+$build';
          newLines.add('version: $newVersion');
          print('Updated version to: $newVersion');
          versionUpdated = true;
          continue;
        }
      }
    }
    newLines.add(line);
  }

  if (versionUpdated) {
    await file.writeAsString('${newLines.join('\n')}\n');
  } else {
    print('Error: Could not find version in pubspec.yaml');
    exit(1);
  }
}
