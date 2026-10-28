import 'dart:convert';
import 'dart:io';

import 'package:visettings/visettings.dart';

import '../fs/file_ops.dart';
import 'icons.dart';

sealed class WorkspaceNode {
  const WorkspaceNode();
}

/// Top non-collapsible workspace row: `❖ <workspace_name>`.
class WorkspaceHeaderNode extends WorkspaceNode {
  final String rootPath;
  final String name;

  const WorkspaceHeaderNode({
    required this.rootPath,
    required this.name,
  });
}

class WorkspaceDirectoryNode extends WorkspaceNode {
  final String path;
  final String name;
  final int depth;
  final bool expanded;

  const WorkspaceDirectoryNode({
    required this.path,
    required this.name,
    required this.depth,
    required this.expanded,
  });
}

class WorkspaceFileNode extends WorkspaceNode {
  final String path;
  final String name;
  final int depth;

  const WorkspaceFileNode({
    required this.path,
    required this.name,
    required this.depth,
  });
}

class WorkspaceHighlightSpan {
  final int line;
  final int colStart;
  final int colEnd;
  final String group;

  const WorkspaceHighlightSpan({
    required this.line,
    required this.colStart,
    required this.colEnd,
    required this.group,
  });
}

class RenderedWorkspaceTree {
  final List<String> lines;
  final List<WorkspaceNode> nodes;
  final List<WorkspaceHighlightSpan> highlights;

  const RenderedWorkspaceTree({
    required this.lines,
    required this.nodes,
    required this.highlights,
  });
}

class WorkspaceTreeState {
  final Set<String> expandedDirs = {};
  bool showHidden = false;
  bool ignoreExclude = false;
  VibrainiumSettings settings = const VibrainiumSettings();
  ClipboardEntry? clipboard;
  String? activeFilePath;

  bool isDirExpanded(String dirPath) =>
      expandedDirs.contains(FileOps.normalizePath(dirPath));

  void toggleDir(String dirPath) {
    final norm = FileOps.normalizePath(dirPath);
    if (!expandedDirs.remove(norm)) {
      expandedDirs.add(norm);
    }
  }

  void expandDir(String dirPath) {
    expandedDirs.add(FileOps.normalizePath(dirPath));
  }

  /// Marks [filePath] as the active file and expands all ancestor directories
  /// between [rootPath] and [filePath]'s parent directory.
  /// Returns `true` if [filePath] is inside [rootPath].
  bool revealFile(String rootPath, String filePath) {
    if (filePath.trim().isEmpty) return false;
    final normRoot = FileOps.normalizePath(rootPath);
    final normFile = FileOps.normalizePath(filePath);
    final rootPrefix = normRoot.endsWith('/') ? normRoot : '$normRoot/';
    if (!normFile.startsWith(rootPrefix)) {
      return false;
    }

    activeFilePath = normFile;
    var currentDir = FileOps.normalizePath(FileOps.dirname(normFile));
    while (currentDir.length > normRoot.length &&
        currentDir.startsWith(rootPrefix)) {
      expandedDirs.add(currentDir);
      final parent = FileOps.normalizePath(FileOps.dirname(currentDir));
      if (parent == currentDir) break;
      currentDir = parent;
    }
    return true;
  }

  void toggleHidden() {
    showHidden = !showHidden;
  }

  void toggleIgnoreExclude() {
    ignoreExclude = !ignoreExclude;
  }

  /// Builds the flattened [RenderedWorkspaceTree] for [rootDir].
  Future<RenderedWorkspaceTree> build(Directory rootDir) async {
    final lines = <String>[];
    final nodes = <WorkspaceNode>[];
    final highlights = <WorkspaceHighlightSpan>[];

    void addLine(
      String text,
      WorkspaceNode node, [
      List<(int, int, String)> lineHighlights = const [],
    ]) {
      final lineIdx = lines.length;
      lines.add(text);
      nodes.add(node);
      for (final (start, end, group) in lineHighlights) {
        highlights.add(WorkspaceHighlightSpan(
          line: lineIdx,
          colStart: start,
          colEnd: end,
          group: group,
        ));
      }
    }

    final rootPath = FileOps.normalizePath(rootDir.path);
    final settingsFile = File(VibrainiumSettings.settingsFilePath(rootPath));
    if (await settingsFile.exists()) {
      settings = await VibrainiumSettings.load(rootPath);
    }

    final rootName = FileOps.basename(rootPath);
    final headerText = '${WorkspaceIcons.workspace} $rootName';
    addLine(
      headerText,
      WorkspaceHeaderNode(rootPath: rootPath, name: rootName),
      [(0, _byteLen(headerText), 'ViworkspaceHeader')],
    );

    if (await rootDir.exists()) {
      await _renderDirectoryChildren(
        rootPath: rootPath,
        dir: rootDir,
        depth: 0,
        addLine: addLine,
      );
    }

    return RenderedWorkspaceTree(
      lines: lines,
      nodes: nodes,
      highlights: highlights,
    );
  }

  Future<void> _renderDirectoryChildren({
    required String rootPath,
    required Directory dir,
    required int depth,
    required void Function(
      String text,
      WorkspaceNode node, [
      List<(int, int, String)> lineHighlights,
    ]) addLine,
  }) async {
    List<FileSystemEntity> entities;
    try {
      entities = await dir.list(followLinks: false).toList();
    } catch (_) {
      return;
    }

    final subDirs = <(String, Directory)>[];
    final files = <(String, FileSystemEntity)>[];

    for (final entity in entities) {
      final name = FileOps.basename(entity.path);
      if (!showHidden && name.startsWith('.')) {
        continue;
      }
      final isDir = entity is Directory;
      if (!ignoreExclude) {
        final normEntityPath = FileOps.normalizePath(entity.path);
        final relPath = normEntityPath.startsWith('$rootPath/')
            ? normEntityPath.substring(rootPath.length + 1)
            : name;
        if (settings.isWorkspaceExcluded(
          relPath,
          name: name,
          isDirectory: isDir,
        )) {
          continue;
        }
      }
      if (isDir) {
        subDirs.add((name, entity));
      } else {
        files.add((name, entity));
      }
    }

    subDirs.sort(
      (a, b) => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()),
    );
    files.sort(
      (a, b) => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()),
    );

    final indent = '  ' * depth;
    final activeClip = clipboard;

    for (final (name, subDir) in subDirs) {
      final normPath = FileOps.normalizePath(subDir.path);
      final expanded = isDirExpanded(normPath);
      final chevron = expanded
          ? WorkspaceIcons.chevronExpanded
          : WorkspaceIcons.chevronCollapsed;
      final folderIcon = expanded
          ? WorkspaceIcons.folderOpen
          : WorkspaceIcons.folderClosed;
      final mainPart = '$indent$chevron $folderIcon $name';
      final clipTag = (activeClip != null &&
              FileOps.normalizePath(activeClip.path) == normPath)
          ? ' [${activeClip.mode.label}]'
          : '';
      final fullLine = '$mainPart$clipTag';

      final mainBytes = _byteLen(mainPart);
      final spans = <(int, int, String)>[
        (0, mainBytes, 'ViworkspaceDirectory'),
      ];
      if (clipTag.isNotEmpty) {
        spans.add((
          mainBytes,
          mainBytes + _byteLen(clipTag),
          'ViworkspaceClipboard',
        ));
      }

      addLine(
        fullLine,
        WorkspaceDirectoryNode(
          path: normPath,
          name: name,
          depth: depth,
          expanded: expanded,
        ),
        spans,
      );

      if (expanded) {
        await _renderDirectoryChildren(
          rootPath: rootPath,
          dir: subDir,
          depth: depth + 1,
          addLine: addLine,
        );
      }
    }

    for (final (name, fileEntity) in files) {
      final normPath = FileOps.normalizePath(fileEntity.path);
      final (icon, iconGroup) = WorkspaceIcons.iconForFile(name);
      final prefix = '$indent  ';
      final iconPart = icon;
      final namePart = ' $name';
      final clipTag = (activeClip != null &&
              FileOps.normalizePath(activeClip.path) == normPath)
          ? ' [${activeClip.mode.label}]'
          : '';
      final fullLine = '$prefix$iconPart$namePart$clipTag';

      final prefixBytes = _byteLen(prefix);
      final iconBytes = _byteLen(iconPart);
      final nameBytes = _byteLen(namePart);
      final isActiveFile = activeFilePath != null &&
          FileOps.normalizePath(activeFilePath!) == normPath;

      final spans = <(int, int, String)>[
        (prefixBytes, prefixBytes + iconBytes, iconGroup),
        if (isActiveFile)
          (
            prefixBytes + iconBytes,
            prefixBytes + iconBytes + nameBytes,
            'ViworkspaceActiveFile',
          ),
      ];
      if (clipTag.isNotEmpty) {
        final clipStart = prefixBytes + iconBytes + nameBytes;
        spans.add((
          clipStart,
          clipStart + _byteLen(clipTag),
          'ViworkspaceClipboard',
        ));
      }

      addLine(
        fullLine,
        WorkspaceFileNode(
          path: normPath,
          name: name,
          depth: depth,
        ),
        spans,
      );
    }
  }

  static int _byteLen(String s) => utf8.encode(s).length;
}
