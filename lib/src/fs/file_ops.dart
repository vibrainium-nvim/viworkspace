import 'dart:io';

enum ClipboardMode {
  copy('copy'),
  cut('cut');

  final String label;
  const ClipboardMode(this.label);
}

class ClipboardEntry {
  final String path;
  final ClipboardMode mode;

  const ClipboardEntry({
    required this.path,
    required this.mode,
  });
}

/// File system operations for `viworkspace`: create file/folder, rename, delete, copy/cut/paste.
class FileOps {
  static String normalizePath(String path) {
    final sep = Platform.pathSeparator;
    var clean = path.replaceAll('\\', '/');
    while (clean.length > 1 && clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (sep == '\\') {
      clean = clean.replaceAll('/', '\\');
    }
    return clean;
  }

  static String basename(String path) {
    final clean = path.replaceAll('\\', '/');
    final trimmed = clean.endsWith('/') && clean.length > 1
        ? clean.substring(0, clean.length - 1)
        : clean;
    final idx = trimmed.lastIndexOf('/');
    return idx < 0 ? trimmed : trimmed.substring(idx + 1);
  }

  static String dirname(String path) {
    final clean = path.replaceAll('\\', '/');
    final trimmed = clean.endsWith('/') && clean.length > 1
        ? clean.substring(0, clean.length - 1)
        : clean;
    final idx = trimmed.lastIndexOf('/');
    if (idx <= 0) return idx == 0 ? '/' : '.';
    return trimmed.substring(0, idx);
  }

  static String join(String dir, String child) {
    final cleanDir = dir.endsWith('/') && dir.length > 1
        ? dir.substring(0, dir.length - 1)
        : dir;
    final cleanChild = child.startsWith('/') ? child.substring(1) : child;
    return '$cleanDir/$cleanChild';
  }

  /// Returns [targetPath] relative to [rootPath] (or `.` when equal).
  static String relativePath(String rootPath, String targetPath) {
    final normRoot = normalizePath(rootPath).replaceAll('\\', '/');
    final normTarget = normalizePath(targetPath).replaceAll('\\', '/');
    if (normTarget == normRoot) {
      return '.';
    }
    final prefix = normRoot.endsWith('/') ? normRoot : '$normRoot/';
    if (normTarget.startsWith(prefix)) {
      return normTarget.substring(prefix.length);
    }
    return normTarget;
  }

  /// Creates a new file at `[targetDir]/[relativePath]`, creating parent directories if needed.
  static Future<String> createFile(String targetDir, String relativePath) async {
    final trimmed = relativePath.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('File name cannot be empty');
    }
    final fullPath = join(targetDir, trimmed);
    final file = File(fullPath);
    if (await file.exists() || await Directory(fullPath).exists()) {
      throw StateError('Already exists: $trimmed');
    }
    await file.parent.create(recursive: true);
    await file.create();
    return fullPath;
  }

  /// Creates a new directory at `[targetDir]/[relativePath]`.
  static Future<String> createFolder(String targetDir, String relativePath) async {
    final trimmed = relativePath.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Folder name cannot be empty');
    }
    final fullPath = join(targetDir, trimmed);
    final dir = Directory(fullPath);
    if (await dir.exists() || await File(fullPath).exists()) {
      throw StateError('Already exists: $trimmed');
    }
    await dir.create(recursive: true);
    return fullPath;
  }

  /// Renames a file or directory at [sourcePath] to [newName] inside its parent directory.
  static Future<String> rename(String sourcePath, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('New name cannot be empty');
    }
    final parentDir = dirname(sourcePath);
    final destPath = join(parentDir, trimmed);
    if (destPath == sourcePath) return sourcePath;

    if (await File(destPath).exists() || await Directory(destPath).exists()) {
      throw StateError('Target already exists: $trimmed');
    }

    final type = await FileSystemEntity.type(sourcePath, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(destPath).parent.create(recursive: true);
      await Directory(sourcePath).rename(destPath);
    } else if (type == FileSystemEntityType.file ||
        type == FileSystemEntityType.link) {
      await File(destPath).parent.create(recursive: true);
      await File(sourcePath).rename(destPath);
    } else {
      throw StateError('Source does not exist: $sourcePath');
    }
    return destPath;
  }

  /// Deletes a file, link, or directory (recursively) at [targetPath].
  static Future<void> delete(String targetPath) async {
    final type = await FileSystemEntity.type(targetPath, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(targetPath).delete(recursive: true);
      case FileSystemEntityType.file:
        await File(targetPath).delete();
      case FileSystemEntityType.link:
        await Link(targetPath).delete();
      default:
        throw StateError('Path not found: $targetPath');
    }
  }

  /// Pastes [entry] (copy or cut) into [targetDir] and returns the resulting destination path.
  static Future<String> paste(ClipboardEntry entry, String targetDir) async {
    final sourcePath = entry.path;
    final type = await FileSystemEntity.type(sourcePath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw StateError('Clipboard source no longer exists: $sourcePath');
    }

    final baseName = basename(sourcePath);
    var destPath = join(targetDir, baseName);

    if (entry.mode == ClipboardMode.cut) {
      if (destPath == sourcePath) {
        return destPath;
      }
      if (await File(destPath).exists() || await Directory(destPath).exists()) {
        throw StateError('Destination already exists: $baseName');
      }
      if (type == FileSystemEntityType.directory) {
        await Directory(sourcePath).rename(destPath);
      } else {
        await File(sourcePath).rename(destPath);
      }
      return destPath;
    }

    destPath = await _nonCollidingCopyPath(targetDir, baseName);
    if (type == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(sourcePath), Directory(destPath));
    } else {
      await File(sourcePath).copy(destPath);
    }
    return destPath;
  }

  static Future<String> _nonCollidingCopyPath(
    String targetDir,
    String baseName,
  ) async {
    var candidate = join(targetDir, baseName);
    if (!await File(candidate).exists() &&
        !await Directory(candidate).exists()) {
      return candidate;
    }

    final dotIdx = baseName.lastIndexOf('.');
    final stem = dotIdx > 0 ? baseName.substring(0, dotIdx) : baseName;
    final ext = dotIdx > 0 ? baseName.substring(dotIdx) : '';

    var counter = 1;
    while (true) {
      final suffix = counter == 1 ? '_copy' : '_copy$counter';
      candidate = join(targetDir, '$stem$suffix$ext');
      if (!await File(candidate).exists() &&
          !await Directory(candidate).exists()) {
        return candidate;
      }
      counter++;
    }
  }

  static Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = basename(entity.path);
      final newPath = join(destination.path, name);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }
}
