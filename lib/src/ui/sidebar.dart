import 'dart:io';

import 'package:nvim/nvim.dart';
import 'package:visettings/visettings.dart';

import '../fs/file_ops.dart';
import 'prompts.dart';
import 'tree.dart';

class WorkspaceSidebar {
  final Nvim nvim;
  final int sidebarWidth;
  final Map<String, String> extraKeymaps;

  final WorkspaceTreeState treeState = WorkspaceTreeState();
  late final InputPrompt _inputPrompt = InputPrompt(nvim);
  late final ConfirmPrompt _confirmPrompt = ConfirmPrompt(nvim);
  late final ContextMenuPrompt _contextMenu = ContextMenuPrompt(nvim);

  static const Set<String> _nonEditorFiletypes = {
    'viworkspace',
    'viff',
    'viproblems',
    'viproblems-detail',
    'vibrainium-tabbar',
    'vibrainium-bottom-tabbar',
    'viworkspace-prompt',
    'viworkspace-confirm',
    'viworkspace-menu',
  };

  int? _nsId;
  int? _buf;
  int? _win;
  int? _lastActiveEditorWin;
  Set<int> _excludedWindows = const {};
  bool _highlightsInitialized = false;
  bool _autoSyncRegistered = false;

  String? _rootPath;
  RenderedWorkspaceTree? _rendered;

  WorkspaceSidebar({
    required this.nvim,
    this.sidebarWidth = 36,
    this.extraKeymaps = const {},
    bool bindRpc = true,
  }) {
    if (bindRpc) {
      nvim.rpc.onRequest = _handleRpc;
      nvim.rpc.onNotification = (method, params) async {
        await _handleRpc(method, params);
      };
    }
  }

  int? get bufferId => _buf;
  int? get windowId => _win;
  int? get lastActiveEditorWin => _lastActiveEditorWin;

  void attachWindow(
    int? win, {
    Set<int> excludedWins = const {},
    int? lastActiveEditorWin,
  }) {
    _win = win;
    _excludedWindows = excludedWins;
    if (lastActiveEditorWin != null && lastActiveEditorWin > 0) {
      _lastActiveEditorWin = lastActiveEditorWin;
    }
  }

  String? get rootPath => _rootPath;
  RenderedWorkspaceTree? get renderedTree => _rendered;
  ContextMenuPrompt get contextMenu => _contextMenu;

  Future<Object?> handleAction(String rawAction) async {
    final action = rawAction.startsWith('workspace.')
        ? rawAction.substring('workspace.'.length)
        : rawAction;

    if (action.startsWith('menu_select:')) {
      final idx = int.tryParse(action.substring('menu_select:'.length));
      if (idx != null) {
        await _contextMenu.selectIndex(idx);
      }
      return true;
    }

    switch (action) {
      case 'open':
        await open();
        return true;
      case 'close':
        await close();
        return true;
      case 'toggle':
        await toggle();
        return true;
      case 'refresh':
        await refresh();
        return true;
      case 'sync_active_file':
        await syncActiveFile(focusSidebar: false);
        return true;
      case 'reveal':
        await syncActiveFile(focusSidebar: true);
        return true;
      case 'reload':
        await reload();
        return true;
      case 'enter':
        await handleEnter();
        return true;
      case 'click':
        await _rememberActiveEditorWin();
        await _contextMenu.close();
        return true;
      case 'double_click':
        await _rememberActiveEditorWin();
        await _contextMenu.close();
        final win = _win;
        if (win != null && await nvim.winIsValid(win)) {
          await _syncCursorFromMouse(win);
        }
        await handleEnter();
        return true;
      case 'context_menu':
        await _rememberActiveEditorWin();
        await openContextMenu();
        return true;
      case 'menu_click':
        await _contextMenu.handleClick();
        return true;
      case 'menu_confirm':
        await _contextMenu.confirm();
        return true;
      case 'menu_close':
        await _contextMenu.cancel();
        return true;
      case 'new_file':
        await handleNewFile();
        return true;
      case 'new_folder':
        await handleNewFolder();
        return true;
      case 'rename':
        await handleRename();
        return true;
      case 'delete':
        await handleDelete();
        return true;
      case 'copy':
        await handleCopy(ClipboardMode.copy);
        return true;
      case 'cut':
        await handleCopy(ClipboardMode.cut);
        return true;
      case 'paste':
        await handlePaste();
        return true;
      case 'copy_filename':
        await handleCopyFilename();
        return true;
      case 'copy_relative_path':
        await handleCopyRelativePath();
        return true;
      case 'copy_absolute_path':
        await handleCopyAbsolutePath();
        return true;
      case 'toggle_hidden':
        await handleToggleHidden();
        return true;
      case 'toggle_exclude':
        await handleToggleExclude();
        return true;
      case 'prompt_submit':
        await _inputPrompt.submit();
        return true;
      case 'prompt_close':
        await _inputPrompt.close();
        await _focusSidebar();
        return true;
      case 'confirm_yes':
        await _confirmPrompt.confirm();
        return true;
      case 'confirm_no':
        await _confirmPrompt.close();
        await _focusSidebar();
        return true;
      default:
        return null;
    }
  }

  Future<Object?> _handleRpc(String method, List<Object?> params) async {
    final action = (method == 'vibrainium_action' ||
                method == 'viworkspace_action') &&
            params.isNotEmpty
        ? params.first.toString()
        : method;
    return handleAction(action);
  }

  Future<bool> isOpen() async {
    final win = _win;
    if (win == null) return false;
    return nvim.winIsValid(win);
  }

  Future<void> toggle() async {
    if (await isOpen()) {
      await close();
    } else {
      await open();
    }
  }

  Future<void> open() async {
    await _rememberActiveEditorWin();
    await _ensureHighlights();
    await ensureAutoSync();
    if (!await isOpen()) {
      await _createSidebarWin();
    }
    await refresh();
    await syncActiveFile(focusSidebar: false);
  }

  Future<void> closeModals() async {
    await _inputPrompt.close();
    await _confirmPrompt.close();
    await _contextMenu.close();
  }

  Future<void> close() async {
    await closeModals();
    final win = _win;
    _win = null;
    if (win != null && await nvim.winIsValid(win)) {
      await nvim.winClose(win, force: true);
    }
  }

  Future<void> reload() async {
    final ok = await HotReloader.reload();
    if (ok) {
      await onHotReloaded();
    } else {
      await nvim.notify(
        '[viworkspace] Hot reload unavailable (running AOT or non-JIT)',
        level: 3,
      );
    }
  }

  Future<void> onHotReloaded() async {
    _highlightsInitialized = false;
    _autoSyncRegistered = false;
    final buf = _buf;
    if (buf != null && await nvim.bufIsValid(buf)) {
      await _bindSidebarKeys(buf);
    }
    if (await isOpen()) {
      await _ensureHighlights();
      await ensureAutoSync();
      await refresh();
      await syncActiveFile(focusSidebar: false);
    }
  }

  Future<void> ensureAutoSync() async {
    if (_autoSyncRegistered) return;
    _autoSyncRegistered = true;
    try {
      await nvim.execLua(r'''
local group = vim.api.nvim_create_augroup('VibrainiumWorkspaceAutoSync', { clear = true })
vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
  group = group,
  callback = function()
    if vim.bo.buftype ~= '' then
      return
    end
    pcall(function()
      require('vibrainium').action('workspace.sync_active_file')
    end)
  end,
})
''');
    } catch (_) {}
  }

  Future<String?> _resolveActiveEditorFilePath() async {
    await _rememberActiveEditorWin();

    final candidates = <int?>[
      await nvim.getCurrentWin(),
      _lastActiveEditorWin,
      await nvim.getAlternateWin(),
    ];

    int? editorWin;
    for (final candidate in candidates) {
      if (await _isEligibleEditorWin(candidate)) {
        editorWin = candidate;
        break;
      }
    }

    if (editorWin == null) {
      final wins = await nvim.listWins();
      for (final w in wins) {
        if (await _isEligibleEditorWin(w)) {
          editorWin = w;
          break;
        }
      }
    }

    var buf = 0;
    if (editorWin != null) {
      _lastActiveEditorWin = editorWin;
      buf = await nvim.winGetBuf(editorWin);
    }
    if (buf <= 0) {
      try {
        buf = await nvim.getCurrentBuf();
      } catch (_) {}
    }
    if (buf <= 0) return null;

    final name = (await nvim.bufGetName(buf)).trim();
    if (name.isEmpty) return null;
    return FileOps.normalizePath(name);
  }

  /// Expands parent directories for the active editor buffer's file, highlights
  /// it in the tree, and positions the sidebar cursor on that file's row.
  Future<bool> syncActiveFile({bool focusSidebar = false}) async {
    final win = _win;
    if (win == null || !await nvim.winIsValid(win)) return false;

    final root = _rootPath ??= FileOps.normalizePath(await nvim.getCwd());
    final activePath = await _resolveActiveEditorFilePath();
    if (activePath == null) return false;

    final revealed = treeState.revealFile(root, activePath);
    if (!revealed) return false;

    await render();
    final rendered = _rendered;
    if (rendered != null) {
      final idx = rendered.nodes.indexWhere((n) => switch (n) {
            WorkspaceFileNode(:final path) => path == activePath,
            _ => false,
          });
      if (idx >= 0) {
        await nvim.winSetCursor(win, idx + 1, 0);
      }
    }
    if (focusSidebar) {
      await nvim.setCurrentWin(win);
    }
    return true;
  }

  Future<void> refresh({bool rescanCwd = false}) async {
    if (_rootPath == null || rescanCwd) {
      _rootPath = FileOps.normalizePath(await nvim.getCwd());
    }
    await render();
  }

  Future<WorkspaceNode?> _nodeUnderCursor() async {
    final win = _win;
    final rendered = _rendered;
    if (win == null || rendered == null || !await nvim.winIsValid(win)) {
      return null;
    }
    final (row1, _) = await nvim.winGetCursor(win);
    final idx = row1 - 1;
    if (idx < 0 || idx >= rendered.nodes.length) return null;
    return rendered.nodes[idx];
  }

  String _targetDirectoryForNode(WorkspaceNode? node) {
    final fallback = _rootPath ?? '.';
    return switch (node) {
      WorkspaceDirectoryNode(:final path) => path,
      WorkspaceFileNode(:final path) => FileOps.dirname(path),
      WorkspaceHeaderNode(:final rootPath) => rootPath,
      null => fallback,
    };
  }

  Future<void> handleEnter() async {
    final node = await _nodeUnderCursor();
    if (node == null) return;

    switch (node) {
      case WorkspaceHeaderNode():
        // Workspace header is never collapsible
        break;
      case WorkspaceDirectoryNode(:final path):
        treeState.toggleDir(path);
        await render();
      case WorkspaceFileNode(:final path):
        await _openFileInMainWindow(path);
    }
  }

  Future<(int, int)> _syncCursorFromMouse(int win) async {
    await _rememberActiveEditorWin();
    final mousePos = await nvim.getMousePos();
    final maxLine = (_rendered?.nodes.length ?? 1).clamp(1, 999999);
    if (mousePos != null) {
      if (mousePos.winId == win && mousePos.line >= 1) {
        final targetLine = mousePos.line.clamp(1, maxLine);
        final currentWin = await nvim.getCurrentWin();
        if (currentWin != win) {
          await nvim.setCurrentWin(win);
        }
        await nvim.winSetCursor(win, targetLine, 0);
        final winRow = mousePos.winRow > 0 ? mousePos.winRow : targetLine;
        return (targetLine, winRow);
      }
      if (mousePos.screenRow > 0) {
        final (winTop0, _) = await nvim.winGetPosition(win);
        final topLine = await nvim.winGetTopLine(win);
        final winRow = (mousePos.screenRow - winTop0).clamp(1, 999);
        final targetLine = (topLine + winRow - 1).clamp(1, maxLine);
        final currentWin = await nvim.getCurrentWin();
        if (currentWin != win) {
          await nvim.setCurrentWin(win);
        }
        await nvim.winSetCursor(win, targetLine, 0);
        return (targetLine, winRow);
      }
    }
    final (row1, _) = await nvim.winGetCursor(win);
    return (row1, row1);
  }

  Future<void> openContextMenu() async {
    final win = _win;
    if (win == null || !await nvim.winIsValid(win)) return;
    await _contextMenu.close();
    final (_, winRow) = await _syncCursorFromMouse(win);
    final node = await _nodeUnderCursor();

    final items = <ContextMenuItem>[
      if (node is WorkspaceFileNode)
        ContextMenuItem(
          label: 'Open File',
          shortcut: '<CR>',
          onSelect: () async {
            await _focusSidebar();
            await handleEnter();
          },
        ),
      ContextMenuItem(
        label: 'New File',
        shortcut: 'n',
        onSelect: () async {
          await _focusSidebar();
          await handleNewFile();
        },
      ),
      ContextMenuItem(
        label: 'New Folder',
        shortcut: 'N',
        onSelect: () async {
          await _focusSidebar();
          await handleNewFolder();
        },
      ),
      if (node is WorkspaceDirectoryNode || node is WorkspaceFileNode) ...[
        ContextMenuItem(
          label: 'Rename',
          shortcut: 'r',
          onSelect: () async {
            await _focusSidebar();
            await handleRename();
          },
        ),
        ContextMenuItem(
          label: 'Copy',
          shortcut: 'c',
          onSelect: () async {
            await _focusSidebar();
            await handleCopy(ClipboardMode.copy);
          },
        ),
        ContextMenuItem(
          label: 'Cut',
          shortcut: 'x',
          onSelect: () async {
            await _focusSidebar();
            await handleCopy(ClipboardMode.cut);
          },
        ),
      ],
      ContextMenuItem(
        label: 'Paste',
        shortcut: 'p',
        onSelect: () async {
          await _focusSidebar();
          await handlePaste();
        },
      ),
      if (node is WorkspaceDirectoryNode || node is WorkspaceFileNode) ...[
        ContextMenuItem(
          label: 'Copy Filename',
          shortcut: 'y',
          onSelect: () async {
            await _focusSidebar();
            await handleCopyFilename();
          },
        ),
        ContextMenuItem(
          label: 'Copy Relative Path',
          shortcut: 'Y',
          onSelect: () async {
            await _focusSidebar();
            await handleCopyRelativePath();
          },
        ),
        ContextMenuItem(
          label: 'Copy Absolute Path',
          shortcut: 'gy',
          onSelect: () async {
            await _focusSidebar();
            await handleCopyAbsolutePath();
          },
        ),
        ContextMenuItem(
          label: 'Delete',
          shortcut: 'd',
          onSelect: () async {
            await _focusSidebar();
            await handleDelete();
          },
        ),
      ],
      ContextMenuItem(
        label: treeState.showHidden ? 'Hide Hidden Files' : 'Show Hidden Files',
        shortcut: '.',
        onSelect: () async {
          await _focusSidebar();
          await handleToggleHidden();
        },
      ),
      ContextMenuItem(
        label: treeState.ignoreExclude
            ? 'Hide Excluded Files'
            : 'Show Excluded Files',
        shortcut: 'e',
        onSelect: () async {
          await _focusSidebar();
          await handleToggleExclude();
        },
      ),
      ContextMenuItem(
        label: 'Refresh',
        shortcut: 'R',
        onSelect: () async {
          await _focusSidebar();
          await refresh();
        },
      ),
    ];

    final title = switch (node) {
      WorkspaceDirectoryNode(:final name) => name,
      WorkspaceFileNode(:final name) => name,
      WorkspaceHeaderNode(:final name) => name,
      null => 'Workspace',
    };

    await _contextMenu.open(
      items: items,
      title: title,
      anchorWin: win,
      row: winRow,
      col: 2,
      onCancel: _focusSidebar,
    );
  }

  Future<void> handleNewFile() async {
    final node = await _nodeUnderCursor();
    final targetDir = _targetDirectoryForNode(node);

    await _inputPrompt.open(
      title: 'New File',
      onSubmit: (value) async {
        try {
          final createdPath = await FileOps.createFile(targetDir, value);
          treeState.expandDir(targetDir);
          await render();
          await _focusSidebar(selectPath: createdPath);
        } catch (e) {
          await nvim.notify('Create file failed: $e', level: 4);
          await _focusSidebar();
        }
      },
    );
  }

  Future<void> handleNewFolder() async {
    final node = await _nodeUnderCursor();
    final targetDir = _targetDirectoryForNode(node);

    await _inputPrompt.open(
      title: 'New Folder',
      onSubmit: (value) async {
        try {
          final createdPath = await FileOps.createFolder(targetDir, value);
          treeState.expandDir(targetDir);
          await render();
          await _focusSidebar(selectPath: createdPath);
        } catch (e) {
          await nvim.notify('Create folder failed: $e', level: 4);
          await _focusSidebar();
        }
      },
    );
  }

  Future<void> handleRename() async {
    final node = await _nodeUnderCursor();
    final (String path, String currentName) = switch (node) {
      WorkspaceDirectoryNode(:final path, :final name) => (path, name),
      WorkspaceFileNode(:final path, :final name) => (path, name),
      _ => ('', ''),
    };
    if (path.isEmpty) return;

    await _inputPrompt.open(
      title: 'Rename',
      initialValue: currentName,
      onSubmit: (newName) async {
        try {
          final renamedPath = await FileOps.rename(path, newName);
          if (node is WorkspaceDirectoryNode && treeState.isDirExpanded(path)) {
            treeState.expandedDirs.remove(FileOps.normalizePath(path));
            treeState.expandDir(renamedPath);
          }
          await render();
          await _focusSidebar(selectPath: renamedPath);
        } catch (e) {
          await nvim.notify('Rename failed: $e', level: 4);
          await _focusSidebar();
        }
      },
    );
  }

  Future<void> handleDelete() async {
    final node = await _nodeUnderCursor();
    final (String path, String name) = switch (node) {
      WorkspaceDirectoryNode(:final path, :final name) => (path, name),
      WorkspaceFileNode(:final path, :final name) => (path, name),
      _ => ('', ''),
    };
    if (path.isEmpty) return;

    await _confirmPrompt.open(
      message: 'Delete "$name"?',
      onConfirm: () async {
        try {
          await FileOps.delete(path);
          treeState.expandedDirs.remove(FileOps.normalizePath(path));
          if (treeState.clipboard != null &&
              FileOps.normalizePath(treeState.clipboard!.path) ==
                  FileOps.normalizePath(path)) {
            treeState.clipboard = null;
          }
          await render();
          await _focusSidebar();
        } catch (e) {
          await nvim.notify('Delete failed: $e', level: 4);
          await _focusSidebar();
        }
      },
    );
  }

  Future<void> handleCopy(ClipboardMode mode) async {
    final node = await _nodeUnderCursor();
    final path = switch (node) {
      WorkspaceDirectoryNode(:final path) => path,
      WorkspaceFileNode(:final path) => path,
      _ => '',
    };
    if (path.isEmpty) return;

    treeState.clipboard = ClipboardEntry(path: path, mode: mode);
    await render();
  }

  Future<void> handlePaste() async {
    final entry = treeState.clipboard;
    if (entry == null) {
      await nvim.notify('Clipboard is empty');
      return;
    }
    final node = await _nodeUnderCursor();
    final targetDir = _targetDirectoryForNode(node);

    try {
      final destPath = await FileOps.paste(entry, targetDir);
      if (entry.mode == ClipboardMode.cut) {
        treeState.clipboard = null;
      }
      treeState.expandDir(targetDir);
      await render();
      await _focusSidebar(selectPath: destPath);
    } catch (e) {
      await nvim.notify('Paste failed: $e', level: 4);
    }
  }

  (String path, String name)? _pathAndNameForNode(WorkspaceNode? node) {
    return switch (node) {
      WorkspaceDirectoryNode(:final path, :final name) => (path, name),
      WorkspaceFileNode(:final path, :final name) => (path, name),
      WorkspaceHeaderNode(:final rootPath, :final name) => (rootPath, name),
      null => null,
    };
  }

  Future<void> handleCopyFilename() async {
    final info = _pathAndNameForNode(await _nodeUnderCursor());
    if (info == null) return;
    final (_, name) = info;
    await nvim.copyToClipboard(name);
    await nvim.notify('Copied filename: $name');
  }

  Future<void> handleCopyRelativePath() async {
    final info = _pathAndNameForNode(await _nodeUnderCursor());
    if (info == null) return;
    final (path, _) = info;
    final root = _rootPath ?? await nvim.getCwd();
    final relPath = FileOps.relativePath(root, path);
    await nvim.copyToClipboard(relPath);
    await nvim.notify('Copied relative path: $relPath');
  }

  Future<void> handleCopyAbsolutePath() async {
    final info = _pathAndNameForNode(await _nodeUnderCursor());
    if (info == null) return;
    final (path, _) = info;
    final absPath = FileOps.normalizePath(path);
    await nvim.copyToClipboard(absPath);
    await nvim.notify('Copied absolute path: $absPath');
  }

  Future<void> handleToggleHidden() async {
    treeState.toggleHidden();
    await render();
  }

  Future<void> handleToggleExclude() async {
    treeState.toggleIgnoreExclude();
    await render();
  }

  Future<void> _focusSidebar({String? selectPath}) async {
    final win = _win;
    if (win == null || !await nvim.winIsValid(win)) return;
    await nvim.setCurrentWin(win);
    if (selectPath != null && _rendered != null) {
      final normTarget = FileOps.normalizePath(selectPath);
      final idx = _rendered!.nodes.indexWhere((n) => switch (n) {
            WorkspaceDirectoryNode(:final path) => path == normTarget,
            WorkspaceFileNode(:final path) => path == normTarget,
            WorkspaceHeaderNode() => false,
          });
      if (idx >= 0) {
        await nvim.winSetCursor(win, idx + 1, 0);
      }
    }
  }

  Future<bool> _isEligibleEditorWin(int? w) async {
    if (w == null || w <= 0) return false;
    if (w == _win || _excludedWindows.contains(w)) return false;
    if (!await nvim.winIsValid(w)) return false;

    final config = await nvim.winGetConfig(w);
    final relative = config['relative']?.toString() ?? '';
    if (relative.isNotEmpty) return false;

    final buf = await nvim.winGetBuf(w);
    if (buf > 0) {
      final filetype =
          (await nvim.bufGetOption(buf, 'filetype'))?.toString() ?? '';
      if (_nonEditorFiletypes.contains(filetype)) return false;
      final buftype =
          (await nvim.bufGetOption(buf, 'buftype'))?.toString() ?? '';
      if (buftype.isNotEmpty) return false;
    }
    return true;
  }

  Future<void> _rememberActiveEditorWin() async {
    final current = await nvim.getCurrentWin();
    if (await _isEligibleEditorWin(current)) {
      _lastActiveEditorWin = current;
      return;
    }
    final alt = await nvim.getAlternateWin();
    if (await _isEligibleEditorWin(alt)) {
      _lastActiveEditorWin = alt;
    }
  }

  Future<void> _openFileInMainWindow(String fullPath) async {
    await _rememberActiveEditorWin();

    int? targetWin;
    final candidates = <int?>[
      await nvim.getAlternateWin(),
      _lastActiveEditorWin,
      await nvim.getCurrentWin(),
    ];
    for (final candidate in candidates) {
      if (await _isEligibleEditorWin(candidate)) {
        targetWin = candidate;
        break;
      }
    }

    if (targetWin == null) {
      final wins = await nvim.listWins();
      for (final w in wins) {
        if (await _isEligibleEditorWin(w)) {
          targetWin = w;
          break;
        }
      }
    }

    if (targetWin != null) {
      _lastActiveEditorWin = targetWin;
      await nvim.setCurrentWin(targetWin);
    } else {
      await nvim.command('botright vsplit');
      final newWin = await nvim.getCurrentWin();
      if (newWin > 0) {
        _lastActiveEditorWin = newWin;
        await nvim.winSetOption(newWin, 'winfixwidth', false);
        await nvim.winSetOption(newWin, 'winfixheight', false);
        await nvim.winSetOption(newWin, 'number', true);
        await nvim.winSetOption(newWin, 'signcolumn', 'auto');
      }
    }
    final escaped = fullPath.replaceAll(' ', r'\ ');
    await nvim.command('edit $escaped');
    treeState.activeFilePath = FileOps.normalizePath(fullPath);
    await render();
  }

  Future<void> render() async {
    final buf = _buf;
    final nsId = _nsId;
    final root = _rootPath;
    if (buf == null ||
        nsId == null ||
        root == null ||
        !await nvim.bufIsValid(buf)) {
      return;
    }

    treeState.settings = await VibrainiumSettings.load(root);
    final rendered = await treeState.build(Directory(root));
    _rendered = rendered;

    await nvim.bufSetOption(buf, 'modifiable', true);
    await nvim.bufSetLines(buf, lines: rendered.lines);
    await nvim.bufSetOption(buf, 'modifiable', false);

    await nvim.bufClearNamespace(buf, nsId);
    for (final hl in rendered.highlights) {
      await nvim.bufSetExtmark(buf, nsId, hl.line, hl.colStart, {
        'end_col': hl.colEnd,
        'hl_group': hl.group,
      });
    }
  }

  Future<void> _ensureHighlights() async {
    _nsId ??= await nvim.createNamespace('viworkspace_sidebar');
    if (_highlightsInitialized) return;
    _highlightsInitialized = true;

    const groups = <String, Map<String, Object?>>{
      'ViworkspaceHeader': {'bold': true, 'link': 'Title'},
      'ViworkspaceDirectory': {'bold': true, 'link': 'Directory'},
      'ViworkspaceActiveFile': {'bold': true, 'link': 'CursorLineNr'},
      'ViworkspaceClipboard': {'italic': true, 'link': 'WarningMsg'},
      'ViworkspaceMuted': {'link': 'Comment'},
      'ViworkspaceIconDefault': {'link': 'Normal'},
      'ViworkspaceIconDart': {'link': 'Function'},
      'ViworkspaceIconLua': {'link': 'Identifier'},
      'ViworkspaceIconMarkdown': {'link': 'Special'},
      'ViworkspaceIconConfig': {'link': 'Constant'},
      'ViworkspaceIconShell': {'link': 'Statement'},
      'ViworkspaceIconPython': {'link': 'Type'},
      'ViworkspaceIconRust': {'link': 'Special'},
      'ViworkspaceIconGo': {'link': 'Function'},
      'ViworkspaceIconJs': {'link': 'Constant'},
      'ViworkspaceIconTs': {'link': 'Type'},
      'ViworkspaceIconHtml': {'link': 'Statement'},
      'ViworkspaceIconCss': {'link': 'Special'},
      'ViworkspaceIconC': {'link': 'Function'},
      'ViworkspaceIconGit': {'link': 'Special'},
      'ViworkspaceIconDocker': {'link': 'Function'},
      'ViworkspaceIconBuild': {'link': 'Statement'},
      'ViworkspaceIconLicense': {'link': 'Constant'},
      'ViworkspaceIconRuby': {'link': 'Statement'},
      'ViworkspaceIconJvm': {'link': 'Type'},
      'ViworkspaceIconWeb': {'link': 'Special'},
      'ViworkspaceIconData': {'link': 'Constant'},
      'ViworkspaceIconDocs': {'link': 'Special'},
      'ViworkspaceIconMedia': {'link': 'Constant'},
      'ViworkspaceIconArchive': {'link': 'Statement'},
      'ViworkspaceIconSecurity': {'link': 'WarningMsg'},
      'ViworkspaceIconBinary': {'link': 'Comment'},
    };

    for (final entry in groups.entries) {
      await nvim.setHl(0, entry.key, entry.value);
    }
  }

  Future<int> ensureBuffer() async {
    await _ensureHighlights();
    var buf = _buf;
    if (buf == null || !await nvim.bufIsValid(buf)) {
      buf = await nvim.createBuf(listed: false, scratch: true);
      _buf = buf;
      await nvim.bufSetOption(buf, 'buftype', 'nofile');
      await nvim.bufSetOption(buf, 'bufhidden', 'hide');
      await nvim.bufSetOption(buf, 'swapfile', false);
      await nvim.bufSetOption(buf, 'filetype', 'viworkspace');
      await _bindSidebarKeys(buf);
    }
    return buf;
  }

  Future<void> _createSidebarWin() async {
    final buf = await ensureBuffer();

    final win = await nvim.openWin(buf, true, {
      'split': 'left',
      'width': sidebarWidth,
      'style': 'minimal',
    });
    _win = win;

    await nvim.winSetOption(win, 'number', false);
    await nvim.winSetOption(win, 'relativenumber', false);
    await nvim.winSetOption(win, 'signcolumn', 'no');
    await nvim.winSetOption(win, 'foldcolumn', '0');
    await nvim.winSetOption(win, 'statuscolumn', '');
    await nvim.winSetOption(win, 'wrap', false);
    await nvim.winSetOption(win, 'cursorline', true);
    await nvim.winSetOption(win, 'winfixwidth', true);
  }

  Future<void> _bindSidebarKeys(int buf) async {
    const mappings = <String, String>{
      '<CR>': 'enter',
      'n': 'new_file',
      'N': 'new_folder',
      'r': 'rename',
      'd': 'delete',
      'c': 'copy',
      'x': 'cut',
      'p': 'paste',
      'y': 'copy_filename',
      'Y': 'copy_relative_path',
      'gy': 'copy_absolute_path',
      '.': 'toggle_hidden',
      'e': 'toggle_exclude',
      'R': 'refresh',
      'q': 'close',
    };

    for (final entry in mappings.entries) {
      await nvim.bufSetKeymap(
        buf,
        'n',
        entry.key,
        "<Cmd>lua require('vibrainium').action('workspace.${entry.value}')<CR>",
      );
    }

    const mouseMappings = <String, String>{
      '<LeftMouse>': 'click',
      '<2-LeftMouse>': 'double_click',
      '<RightMouse>': 'context_menu',
    };

    for (final entry in mouseMappings.entries) {
      await nvim.bufSetKeymap(
        buf,
        'n',
        entry.key,
        "<LeftMouse><Cmd>lua require('vibrainium').action('workspace.${entry.value}')<CR>",
      );
    }

    for (final entry in extraKeymaps.entries) {
      await nvim.bufSetKeymap(
        buf,
        'n',
        entry.key,
        "<Cmd>lua require('vibrainium').action('${entry.value}')<CR>",
      );
    }
  }
}
