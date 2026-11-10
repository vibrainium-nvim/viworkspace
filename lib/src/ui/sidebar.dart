import 'dart:io';

import 'package:viff/viff.dart';

import '../fs/file_ops.dart';
import 'prompts.dart';
import 'tree.dart';

class WorkspaceSidebar {
  final Nvim nvim;
  final int sidebarWidth;
  final Map<String, String> extraKeymaps;
  final FileProcessRunner? processRunner;
  late final ViffController viff;

  final WorkspaceTreeState treeState = WorkspaceTreeState();
  late final InputPrompt _inputPrompt = InputPrompt(nvim);
  late final ConfirmPrompt _confirmPrompt = ConfirmPrompt(nvim);
  late final ContextMenuPrompt _contextMenu = ContextMenuPrompt(nvim);
  late final SearchPrompt _searchPrompt = SearchPrompt(nvim);

  static const Set<String> _nonEditorFiletypes = {
    'viworkspace',
    'viff',
    'viff-picker',
    'viff-menu',
    'vivcs',
    'vivcs-picker',
    'vivcs-menu',
    'viproblems',
    'viproblems-detail',
    'vibrainium-tabbar',
    'vibrainium-bottom-tabbar',
    'viworkspace-prompt',
    'viworkspace-confirm',
    'viworkspace-menu',
    'viworkspace-search',
    'visearch-padding',
    'visearch-prompt',
    'visearch-results',
    'visearch-preview',
    'visearch-dropdown',
  };

  int? _nsId;
  int? _buf;
  int? _win;
  int? _lastActiveEditorWin;
  int? _lastSeenAlternateWin;
  Set<int> _excludedWindows = const {};
  bool _highlightsInitialized = false;
  bool _autoSyncRegistered = false;
  DateTime? _lastClickTime;
  int? _lastClickRow;
  DateTime? _lastSimulatedDoubleClickTime;

  String? _rootPath;
  RenderedWorkspaceTree? _rendered;
  Future<void>? _renderQueue;

  WorkspaceSidebar({
    required this.nvim,
    this.sidebarWidth = 36,
    this.extraKeymaps = const {},
    this.processRunner,
    ViffController? viff,
    bool bindRpc = true,
  }) {
    this.viff = viff ?? ViffController(nvim: nvim);
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
      if (_lastActiveEditorWin != lastActiveEditorWin) {
        _lastSeenAlternateWin = null;
      }
      _lastActiveEditorWin = lastActiveEditorWin;
    }
    viff.updateWindowContext(
      excludedWins: {
        if (_win != null) _win!,
        ..._excludedWindows,
      },
      lastActiveEditorWin: _lastActiveEditorWin,
    );
  }

  String? get rootPath => _rootPath;
  RenderedWorkspaceTree? get renderedTree => _rendered;
  InputPrompt get inputPrompt => _inputPrompt;
  ContextMenuPrompt get contextMenu => _contextMenu;
  SearchPrompt get searchPrompt => _searchPrompt;

  Future<Object?> handleAction(
    String rawAction, [
    List<Object?> params = const [],
  ]) async {
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

    final extraArg = params.length > 1 ? params[1]?.toString() : null;
    final winArg =
        params.length > 2 ? int.tryParse(params[2]?.toString() ?? '') : null;

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
        await syncActiveFile(
          filePath: extraArg,
          editorWin: winArg,
          focusSidebar: false,
        );
        return true;
      case 'reveal':
        await syncActiveFile(
          filePath: extraArg,
          editorWin: winArg,
          focusSidebar: true,
        );
        return true;
      case 'reload':
        await reload();
        return true;
      case 'enter':
        await handleEnter();
        return true;
      case 'click':
        await handleClick(doubleClick: false);
        return true;
      case 'double_click':
        await handleClick(doubleClick: true);
        return true;
      case 'context_menu':
        await _rememberActiveEditorWin();
        final clickedPos = NvimMouseRouter.parseActionParams(params);
        await openContextMenu(mousePos: clickedPos);
        return true;
      case 'menu_click':
        await _contextMenu.handleClick();
        return true;
      case 'menu_confirm':
        await _contextMenu.confirm();
        return true;
      case 'menu_tab':
        await _contextMenu.handleTab(true);
        return true;
      case 'menu_stab':
        await _contextMenu.handleTab(false);
        return true;
      case 'menu_left':
        await _contextMenu.handleHorizontalNav(false);
        return true;
      case 'menu_right':
        await _contextMenu.handleRightKey();
        return true;
      case 'menu_close':
        final expectedBuf =
            params.length > 1 ? int.tryParse(params[1]?.toString() ?? '') : null;
        await _contextMenu.cancel(expectedBufId: expectedBuf);
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
      case 'duplicate':
        await handleDuplicate();
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
      case 'open_external':
        await handleOpenExternal();
        return true;
      case 'reveal_in_finder':
        await handleRevealInFinder();
        return true;
      case 'toggle_hidden':
        await handleToggleHidden();
        return true;
      case 'toggle_exclude':
        await handleToggleExclude();
        return true;
      case 'select_for_compare':
        await handleSelectForCompare();
        return true;
      case 'compare_with_selected':
        await handleCompareWithSelected();
        return true;
      case 'search':
        await handleSearch();
        return true;
      case 'search_change':
        await handleSearchChange();
        return true;
      case 'search_next':
        await handleSearchStep(1);
        return true;
      case 'search_prev':
        await handleSearchStep(-1);
        return true;
      case 'search_submit':
        await handleSearchSubmit();
        return true;
      case 'search_close':
        await handleSearchClose();
        return true;
      case 'clear_search':
        await handleClearSearch();
        return true;
      case 'prompt_submit':
        await _inputPrompt.submit();
        return true;
      case 'prompt_close':
        final expectedPromptBuf =
            params.length > 1 ? int.tryParse(params[1]?.toString() ?? '') : null;
        if (expectedPromptBuf != null &&
            _inputPrompt.bufferId != expectedPromptBuf) {
          return true;
        }
        final pWin = _inputPrompt.windowId;
        var wasFocused = false;
        if (pWin != null) {
          try {
            wasFocused = (await nvim.getCurrentWin()) == pWin;
          } catch (_) {}
        }
        await _inputPrompt.close();
        if (wasFocused) {
          await _focusSidebar();
        }
        return true;
      case 'confirm_yes':
        await _confirmPrompt.confirm();
        return true;
      case 'confirm_no':
        final expectedConfirmBuf =
            params.length > 1 ? int.tryParse(params[1]?.toString() ?? '') : null;
        if (expectedConfirmBuf != null &&
            _confirmPrompt.bufferId != expectedConfirmBuf) {
          return true;
        }
        final cWin = _confirmPrompt.windowId;
        var wasFocused = false;
        if (cWin != null) {
          try {
            wasFocused = (await nvim.getCurrentWin()) == cWin;
          } catch (_) {}
        }
        await _confirmPrompt.close();
        if (wasFocused) {
          await _focusSidebar();
        }
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
    return handleAction(action, params);
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
    await ensureSearchWin();
    await refresh();
    await syncActiveFile(focusSidebar: true);
  }

  Future<int?> ensureSearchWin() async {
    final win = await _ensureSidebarWinAttached();
    if (win == null) return null;
    await _ensureHighlights();
    return _searchPrompt.ensureWindow(
      sidebarWin: win,
      query: treeState.searchQuery,
      currentMatchIndex: treeState.currentMatchIndex,
      totalMatches: treeState.searchMatches.length,
    );
  }

  Future<void> closeSearchWin() async {
    await _searchPrompt.close();
  }

  Future<void> closeModals() async {
    await _inputPrompt.close();
    await _confirmPrompt.close();
    await _contextMenu.close();
  }

  Future<void> close() async {
    await closeModals();
    await closeSearchWin();
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
        '[Vibrainium] Hot reload unavailable (running AOT or non-JIT)',
        level: 3,
      );
    }
  }

  Future<void> onHotReloaded() async {
    _highlightsInitialized = false;
    _autoSyncRegistered = false;
    nvim.resetRightMouseRouterForHotReload();
    final buf = _buf;
    if (buf != null && await nvim.bufIsValid(buf)) {
      await _bindSidebarKeys(buf);
    }
    await _searchPrompt.onHotReloaded();
    if (await isOpen()) {
      await _ensureHighlights();
      await ensureAutoSync();
      await ensureSearchWin();
      await refresh();
      await syncActiveFile(focusSidebar: true);
    }
  }

  Future<void> ensureAutoSync() async {
    if (_autoSyncRegistered) return;
    _autoSyncRegistered = true;
    try {
      await nvim.execLua(r'''
local group = vim.api.nvim_create_augroup('VibrainiumWorkspaceAutoSync', { clear = true })
local pending = false
local last_win = nil
local last_name = ''
local last_key_was_mouse = false
pcall(vim.on_key, function(k)
  if k and #k > 0 then
    local ok_t, name = pcall(vim.fn.keytrans, k)
    if ok_t and name and name ~= '' then
      last_key_was_mouse = name:find('Mouse', 1, true) ~= nil
    end
  end
end, vim.api.nvim_create_namespace('vibrainium_mouse_tracker'))
local function capture_current_editor()
  local ok, win = pcall(vim.api.nvim_get_current_win)
  if not ok or not win or win <= 0 then
    return false
  end
  local ok_cfg, cfg = pcall(vim.api.nvim_win_get_config, win)
  if ok_cfg and cfg and cfg.relative and cfg.relative ~= '' then
    return false
  end
  local ok_buf, buf = pcall(vim.api.nvim_win_get_buf, win)
  if not ok_buf or not buf or buf <= 0 then
    return false
  end
  if vim.bo[buf].buftype ~= '' then
    return false
  end
  last_win = win
  last_name = vim.api.nvim_buf_get_name(buf) or ''
  return true
end
vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter', 'BufWinEnter', 'BufModifiedSet', 'BufDelete', 'BufWipeout', 'WinClosed', 'WinResized' }, {
  group = group,
  callback = function()
    capture_current_editor()
    if pending then
      return
    end
    pending = true
    vim.schedule(function()
      pending = false
      local ok, win = pcall(vim.api.nvim_get_current_win)
      if not ok or not win or win <= 0 then
        return
      end
      local ok_buf, buf = pcall(vim.api.nvim_win_get_buf, win)
      if ok_buf and buf and buf > 0 then
        local ft = vim.bo[buf].filetype or ''
        if ft == 'vibrainium-tabbar' or ft == 'vibrainium-bottom-tabbar' then
          local trigger = last_key_was_mouse and 'mouse' or 'key'
          pcall(function()
            require('vibrainium').action('panel_tabbar.win_enter', trigger)
          end)
          return
        end
      end
      pcall(function()
        require('vibrainium').action('editor_tab.sync')
      end)
      if capture_current_editor() and last_win and last_win > 0 and last_name ~= '' then
        pcall(function()
          require('vibrainium').action('workspace.sync_active_file', last_name, last_win)
        end)
      end
    end)
  end,
})
''');
    } catch (_) {}
  }

  Future<int?> _ensureSidebarWinAttached() async {
    final existing = _win;
    if (existing != null && await nvim.winIsValid(existing)) {
      return existing;
    }
    try {
      final wins = await nvim.listWins();
      for (final w in wins) {
        final b = await nvim.winGetBuf(w);
        if (b <= 0) continue;
        final ft = (await nvim.bufGetOption(b, 'filetype'))?.toString() ?? '';
        if (ft == 'viworkspace') {
          _win = w;
          _buf = b;
          await _ensureHighlights();
          await _bindSidebarKeys(b);
          return w;
        }
      }
    } catch (_) {}
    return null;
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
  Future<bool> syncActiveFile({
    String? filePath,
    int? editorWin,
    bool focusSidebar = false,
  }) async {
    await _rememberActiveEditorWin();
    if (editorWin != null && await _isEligibleEditorWin(editorWin)) {
      if (_lastActiveEditorWin != editorWin) {
        _lastSeenAlternateWin = null;
      }
      _lastActiveEditorWin = editorWin;
    }
    final win = await _ensureSidebarWinAttached();
    if (win == null) return false;

    final root = _rootPath ??= FileOps.normalizePath(await nvim.getCwd());
    final rawPath = (filePath != null && filePath.trim().isNotEmpty)
        ? FileOps.normalizePath(filePath.trim())
        : await _resolveActiveEditorFilePath();
    if (rawPath == null || rawPath.isEmpty) return false;

    final revealed = treeState.revealFile(root, rawPath);
    if (!revealed) return false;

    final curWin = await nvim.getCurrentWin();
    final shouldMoveCursor = focusSidebar || curWin != win;
    await render(selectPath: shouldMoveCursor ? rawPath : null);
    if (focusSidebar && await nvim.winIsValid(win)) {
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
        await render(selectPath: path);
      case WorkspaceFileNode(:final path):
        await _openFileInMainWindow(path);
    }
  }

  Future<void> handleClick({required bool doubleClick}) async {
    await _rememberActiveEditorWin();
    await _contextMenu.close();
    final win = _win;
    if (win == null || !await nvim.winIsValid(win)) return;

    final synced = await _syncCursorFromMouse(win);
    if (synced == null) return;
    final (row1, _) = synced;
    final now = DateTime.now();

    if (!doubleClick) {
      if (_lastClickRow == row1 &&
          _lastClickTime != null &&
          now.difference(_lastClickTime!) <=
              const Duration(milliseconds: 400)) {
        _lastClickTime = null;
        _lastClickRow = null;
        _lastSimulatedDoubleClickTime = now;
        await handleEnter();
        return;
      }

      _lastClickRow = row1;
      _lastClickTime = now;
      return;
    }

    _lastClickTime = null;
    _lastClickRow = null;
    if (_lastSimulatedDoubleClickTime != null &&
        now.difference(_lastSimulatedDoubleClickTime!) <=
            const Duration(milliseconds: 250)) {
      _lastSimulatedDoubleClickTime = null;
      return;
    }
    _lastSimulatedDoubleClickTime = null;
    await handleEnter();
  }

  Future<(int, int)?> _syncCursorFromMouse(
    int win, {
    MousePosition? mousePos,
  }) async {
    await _rememberActiveEditorWin();
    final resolvedMouse = mousePos ?? await nvim.getMousePos();
    final maxLine = (_rendered?.nodes.length ?? 1).clamp(1, 999999);
    if (resolvedMouse != null) {
      if (resolvedMouse.winId == win &&
          (resolvedMouse.line >= 1 || resolvedMouse.winRow >= 1)) {
        final targetLine = resolvedMouse.line >= 1
            ? resolvedMouse.line.clamp(1, maxLine)
            : maxLine;
        final currentWin = await nvim.getCurrentWin();
        if (currentWin != win) {
          await nvim.setCurrentWin(win);
        }
        await nvim.winSetCursor(win, targetLine, 0);
        final winRow =
            resolvedMouse.winRow > 0 ? resolvedMouse.winRow : targetLine;
        return (targetLine, winRow);
      }
      if (resolvedMouse.winId > 0 &&
          resolvedMouse.winId != win &&
          await nvim.winIsValid(resolvedMouse.winId)) {
        return null;
      }
      if (resolvedMouse.screenRow > 0 && resolvedMouse.screenCol > 0) {
        final (winTop0, winLeft0) = await nvim.winGetPosition(win);
        final winWidth = await nvim.winGetWidth(win);
        final winHeight = await nvim.winGetHeight(win);
        final sRow0 = resolvedMouse.screenRow - 1;
        final sCol0 = resolvedMouse.screenCol - 1;
        if (sRow0 >= winTop0 &&
            sRow0 < winTop0 + winHeight &&
            sCol0 >= winLeft0 &&
            sCol0 < winLeft0 + winWidth) {
          final topLine = await nvim.winGetTopLine(win);
          final winRow = (resolvedMouse.screenRow - winTop0).clamp(1, 999);
          final targetLine = (topLine + winRow - 1).clamp(1, maxLine);
          final currentWin = await nvim.getCurrentWin();
          if (currentWin != win) {
            await nvim.setCurrentWin(win);
          }
          await nvim.winSetCursor(win, targetLine, 0);
          return (targetLine, winRow);
        }
        if (resolvedMouse.winId > 0 && resolvedMouse.winId != win) {
          return null;
        }
      }
    }
    final (row1, _) = await nvim.winGetCursor(win);
    return (row1, row1);
  }

  Future<void> openContextMenu({MousePosition? mousePos}) async {
    final win = await _ensureSidebarWinAttached();
    if (win == null || !await nvim.winIsValid(win)) return;
    await _contextMenu.close();
    final synced = await _syncCursorFromMouse(win, mousePos: mousePos);
    if (synced == null) return;
    final (_, winRow) = synced;
    final node = await _nodeUnderCursor();

    final rows = <NvimContextMenuRow<ContextMenuItem>>[
      if (node is WorkspaceFileNode) ...[
        NvimContextMenuRow.single(ContextMenuItem(
          label: 'Open File',
          shortcut: '<CR>',
          onSelect: () async {
            await _focusSidebar();
            await handleEnter();
          },
        )),
        NvimContextMenuRow.single(ContextMenuItem(
          label: 'Select for Compare',
          shortcut: 'm',
          onSelect: () async {
            await _focusSidebar();
            await handleSelectForCompare();
          },
        )),
        if (viff.selectedCompareFilePath != null &&
            viff.selectedCompareFilePath != node.path)
          NvimContextMenuRow.single(ContextMenuItem(
            label:
                'Compare with Selected (${FileOps.basename(viff.selectedCompareFilePath!)})',
            shortcut: 'M',
            onSelect: () async {
              await _focusSidebar();
              await handleCompareWithSelected();
            },
          )),
      ],
      if (node != null)
        NvimContextMenuRow([
          ContextMenuItem(
            label: 'Open Externally',
            displayLabel: 'Open',
            shortcut: 'o',
            onSelect: () async {
              await _focusSidebar();
              await handleOpenExternal();
            },
          ),
          ContextMenuItem(
            label: 'Reveal in Finder',
            displayLabel: 'In Finder',
            shortcut: 'O',
            onSelect: () async {
              await _focusSidebar();
              await handleRevealInFinder();
            },
          ),
        ]),
      NvimContextMenuRow.single(ContextMenuItem(
        label: 'Search',
        shortcut: '/',
        onSelect: () async {
          await _focusSidebar();
          await handleSearch();
        },
      )),
      NvimContextMenuRow(
        [
          ContextMenuItem(
            label: 'New File',
            displayLabel: 'File',
            shortcut: 'a',
            onSelect: () async {
              await _focusSidebar();
              await handleNewFile();
            },
          ),
          ContextMenuItem(
            label: 'New Folder',
            displayLabel: 'Folder',
            shortcut: 'A',
            onSelect: () async {
              await _focusSidebar();
              await handleNewFolder();
            },
          ),
        ],
        prefix: 'New: ',
      ),
      if (node is WorkspaceDirectoryNode || node is WorkspaceFileNode) ...[
        NvimContextMenuRow([
          ContextMenuItem(
            label: 'Rename',
            shortcut: 'r',
            onSelect: () async {
              await _focusSidebar();
              await handleRename();
            },
          ),
          ContextMenuItem(
            label: 'Duplicate',
            shortcut: 'D',
            onSelect: () async {
              await _focusSidebar();
              await handleDuplicate();
            },
          ),
        ]),
        NvimContextMenuRow([
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
          ContextMenuItem(
            label: 'Paste',
            shortcut: 'p',
            onSelect: () async {
              await _focusSidebar();
              await handlePaste();
            },
          ),
        ]),
        NvimContextMenuRow(
          [
            ContextMenuItem(
              label: 'Copy Filename',
              displayLabel: 'Name',
              shortcut: 'y',
              onSelect: () async {
                await _focusSidebar();
                await handleCopyFilename();
              },
            ),
            ContextMenuItem(
              label: 'Copy Relative Path',
              displayLabel: 'Rel Path',
              shortcut: 'Y',
              onSelect: () async {
                await _focusSidebar();
                await handleCopyRelativePath();
              },
            ),
            ContextMenuItem(
              label: 'Copy Absolute Path',
              displayLabel: 'Abs',
              shortcut: 'gy',
              onSelect: () async {
                await _focusSidebar();
                await handleCopyAbsolutePath();
              },
            ),
          ],
          prefix: 'Copy: ',
        ),
        NvimContextMenuRow.single(ContextMenuItem(
          label: 'Delete',
          shortcut: 'd',
          onSelect: () async {
            await _focusSidebar();
            await handleDelete();
          },
        )),
      ] else ...[
        NvimContextMenuRow.single(ContextMenuItem(
          label: 'Paste',
          shortcut: 'p',
          onSelect: () async {
            await _focusSidebar();
            await handlePaste();
          },
        )),
      ],
      NvimContextMenuRow([
        ContextMenuItem(
          label:
              treeState.showHidden ? 'Hide Hidden Files' : 'Show Hidden Files',
          displayLabel: treeState.showHidden ? 'Hide Hidden' : 'Hidden',
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
          displayLabel: treeState.ignoreExclude ? 'Hide Excluded' : 'Excluded',
          shortcut: 'e',
          onSelect: () async {
            await _focusSidebar();
            await handleToggleExclude();
          },
        ),
      ]),
      NvimContextMenuRow.single(ContextMenuItem(
        label: 'Refresh',
        shortcut: 'R',
        onSelect: () async {
          await _focusSidebar();
          await refresh();
        },
      )),
    ];

    final title = switch (node) {
      WorkspaceDirectoryNode(:final name) => name,
      WorkspaceFileNode(:final name) => name,
      WorkspaceHeaderNode(:final name) => name,
      null => 'Workspace',
    };

    await _contextMenu.open(
      rows: rows,
      title: title,
      anchorWin: win,
      row: winRow,
      col: 2,
      onCancel: _focusSidebar,
    );
  }

  Future<void> handleNewFile() async {
    await _rememberActiveEditorWin();
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
    await _rememberActiveEditorWin();
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
    await _rememberActiveEditorWin();
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

  Future<void> handleDuplicate() async {
    await _rememberActiveEditorWin();
    final node = await _nodeUnderCursor();
    final (String path, _) = switch (node) {
      WorkspaceDirectoryNode(:final path, :final name) => (path, name),
      WorkspaceFileNode(:final path, :final name) => (path, name),
      _ => ('', ''),
    };
    if (path.isEmpty) return;

    try {
      final dupPath = await FileOps.duplicate(path);
      final parentDir = FileOps.dirname(path);
      treeState.expandDir(parentDir);
      await render();
      await _focusSidebar(selectPath: dupPath);
    } catch (e) {
      await nvim.notify('Duplicate failed: $e', level: 4);
      await _focusSidebar();
    }
  }

  Future<void> handleDelete() async {
    await _rememberActiveEditorWin();
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

  Future<void> handleOpenExternal() async {
    final info = _pathAndNameForNode(await _nodeUnderCursor());
    if (info == null) return;
    final (path, _) = info;
    try {
      await FileOps.openExternal(path, runProcess: processRunner);
    } catch (e) {
      await nvim.notify('Open externally failed: $e', level: 4);
    }
  }

  Future<void> handleRevealInFinder() async {
    final info = _pathAndNameForNode(await _nodeUnderCursor());
    if (info == null) return;
    final (path, _) = info;
    try {
      await FileOps.revealInFinder(path, runProcess: processRunner);
    } catch (e) {
      await nvim.notify('Reveal in Finder failed: $e', level: 4);
    }
  }

  Future<void> handleToggleHidden() async {
    treeState.toggleHidden();
    await render();
  }

  Future<void> handleToggleExclude() async {
    treeState.toggleIgnoreExclude();
    await render();
  }

  Future<void> handleSearch() async {
    await _rememberActiveEditorWin();
    final win = await _ensureSidebarWinAttached();
    await _searchPrompt.focus(
      sidebarWin: win,
      query: treeState.searchQuery,
      currentMatchIndex: treeState.currentMatchIndex,
      totalMatches: treeState.searchMatches.length,
    );
  }

  Future<void> handleSearchChange() async {
    final query = await _searchPrompt.readQuery();
    final root = _rootPath ??= FileOps.normalizePath(await nvim.getCwd());
    final matchPath = await treeState.updateSearch(Directory(root), query);
    await _searchPrompt.updateStatus(
      query: treeState.searchQuery,
      currentMatchIndex: treeState.currentMatchIndex,
      totalMatches: treeState.searchMatches.length,
    );
    await render(selectPath: matchPath);
  }

  Future<void> handleSearchStep(int delta) async {
    final root = _rootPath ??= FileOps.normalizePath(await nvim.getCwd());
    if (_searchPrompt.isOpen) {
      final query = await _searchPrompt.readQuery();
      if (query != treeState.searchQuery) {
        await treeState.updateSearch(Directory(root), query);
      }
    }
    if (treeState.searchQuery.isEmpty) {
      return;
    }
    String? matchPath;
    if (treeState.searchMatches.isEmpty) {
      matchPath =
          await treeState.updateSearch(Directory(root), treeState.searchQuery);
    } else {
      matchPath = treeState.stepSearchMatch(root, delta);
    }
    await _searchPrompt.updateStatus(
      query: treeState.searchQuery,
      currentMatchIndex: treeState.currentMatchIndex,
      totalMatches: treeState.searchMatches.length,
    );
    await render(selectPath: matchPath);
  }

  Future<void> handleSearchSubmit() async {
    final root = _rootPath ??= FileOps.normalizePath(await nvim.getCwd());
    if (_searchPrompt.isOpen) {
      final query = await _searchPrompt.readQuery();
      if (query != treeState.searchQuery) {
        await treeState.updateSearch(Directory(root), query);
      }
    }
    final matchPath = treeState.currentMatchPath;
    await nvim.command('stopinsert');
    await _searchPrompt.updateStatus(
      query: treeState.searchQuery,
      currentMatchIndex: treeState.currentMatchIndex,
      totalMatches: treeState.searchMatches.length,
    );
    await render(selectPath: matchPath);
    await _focusSidebar(selectPath: matchPath);
  }

  Future<void> handleSearchClose() async {
    await nvim.command('stopinsert');
    await _focusSidebar(selectPath: treeState.currentMatchPath);
  }

  Future<void> handleClearSearch() async {
    if (treeState.searchQuery.isEmpty &&
        treeState.searchExpandedDirs.isEmpty &&
        (await _searchPrompt.readQuery()).isEmpty) {
      return;
    }
    treeState.clearSearch(collapseAutoExpanded: false);
    await _searchPrompt.setQuery(
      '',
      currentMatchIndex: -1,
      totalMatches: 0,
    );
    await render();
  }

  Future<void> handleSelectForCompare() async {
    final node = await _nodeUnderCursor();
    if (node is! WorkspaceFileNode) {
      await nvim.notify('Select a file to compare');
      return;
    }
    viff.selectedCompareFilePath = FileOps.normalizePath(node.path);
    await nvim.notify('Selected for compare: ${node.name}');
  }

  Future<void> handleCompareWithSelected() async {
    final leftPath = viff.selectedCompareFilePath;
    if (leftPath == null || leftPath.isEmpty) {
      await nvim.notify('No file selected for compare (press m on a file first)');
      return;
    }
    final node = await _nodeUnderCursor();
    if (node is! WorkspaceFileNode) {
      await nvim.notify('Select a target file to compare with');
      return;
    }
    final rightPath = FileOps.normalizePath(node.path);
    await _rememberActiveEditorWin();
    viff.updateWindowContext(
      excludedWins: {
        if (_win != null) _win!,
        ..._excludedWindows,
      },
      lastActiveEditorWin: _lastActiveEditorWin,
    );
    final root = _rootPath ?? await nvim.getCwd();
    await viff.compareFiles(leftPath, rightPath, workspaceRoot: root);
    if (viff.rightWindowId != null) {
      _lastActiveEditorWin = viff.rightWindowId;
    }
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
    try {
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
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isReplaceableMainWin(int? w) async {
    if (w == null || w <= 0) return false;
    if (w == _win || _excludedWindows.contains(w)) return false;
    try {
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
        if (buftype == 'terminal' ||
            buftype == 'quickfix' ||
            buftype == 'prompt') {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _rememberActiveEditorWin() async {
    try {
      final current = await nvim.getCurrentWin();
      final alt = await nvim.getAlternateWin();
      if (await _isEligibleEditorWin(current)) {
        _lastActiveEditorWin = current;
        _lastSeenAlternateWin = alt;
        return;
      }
      if (await _isEligibleEditorWin(alt)) {
        if (_lastActiveEditorWin == null ||
            !await _isEligibleEditorWin(_lastActiveEditorWin) ||
            (_lastSeenAlternateWin != null && alt != _lastSeenAlternateWin)) {
          _lastActiveEditorWin = alt;
        }
        _lastSeenAlternateWin = alt;
      }
    } catch (_) {}
  }

  Future<void> _openFileInMainWindow(String fullPath) async {
    await _rememberActiveEditorWin();

    int? targetWin;
    final candidates = <int?>[
      _lastActiveEditorWin,
      await nvim.getAlternateWin(),
      await nvim.getCurrentWin(),
    ];
    for (final candidate in candidates) {
      if (await _isEligibleEditorWin(candidate)) {
        targetWin = candidate;
        break;
      }
    }

    List<int>? allWins;
    if (targetWin == null) {
      allWins = await nvim.listWins();
      final activePath = treeState.activeFilePath;
      if (activePath != null && activePath.isNotEmpty) {
        for (final w in allWins) {
          if (await _isEligibleEditorWin(w)) {
            final b = await nvim.winGetBuf(w);
            if (b > 0) {
              final name = (await nvim.bufGetName(b)).trim();
              if (name.isNotEmpty &&
                  FileOps.normalizePath(name) == activePath) {
                targetWin = w;
                break;
              }
            }
          }
        }
      }
      if (targetWin == null) {
        for (final w in allWins) {
          if (await _isEligibleEditorWin(w)) {
            targetWin = w;
            break;
          }
        }
      }
    }

    if (targetWin == null) {
      for (final candidate in candidates) {
        if (await _isReplaceableMainWin(candidate)) {
          targetWin = candidate;
          break;
        }
      }
    }

    if (targetWin == null) {
      allWins ??= await nvim.listWins();
      for (final w in allWins) {
        if (await _isReplaceableMainWin(w)) {
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
    final normPath = FileOps.normalizePath(fullPath);
    treeState.activeFilePath = normPath;
    await render(selectPath: normPath);
  }

  Future<void> render({String? selectPath}) {
    final prev = _renderQueue;
    final next = (prev ?? Future<void>.value()).then(
      (_) => _doRender(selectPath: selectPath),
      onError: (_) => _doRender(selectPath: selectPath),
    );
    _renderQueue = next;
    return next;
  }

  Future<void> _doRender({String? selectPath}) async {
    final buf = _buf;
    final nsId = _nsId;
    final root = _rootPath;
    if (buf == null ||
        nsId == null ||
        root == null ||
        !await nvim.bufIsValid(buf)) {
      return;
    }

    final win = _win;
    int? savedRow;
    if (win != null && await nvim.winIsValid(win)) {
      try {
        final (r, _) = await nvim.winGetCursor(win);
        savedRow = r;
      } catch (_) {}
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

    if (win != null &&
        rendered.nodes.isNotEmpty &&
        await nvim.winIsValid(win)) {
      int? targetRow;
      if (selectPath != null) {
        final normTarget = FileOps.normalizePath(selectPath);
        final idx = rendered.nodes.indexWhere((n) => switch (n) {
              WorkspaceDirectoryNode(:final path) => path == normTarget,
              WorkspaceFileNode(:final path) => path == normTarget,
              WorkspaceHeaderNode() => false,
            });
        if (idx >= 0) {
          targetRow = idx + 1;
        }
      }
      targetRow ??= savedRow?.clamp(1, rendered.nodes.length);
      if (targetRow != null && targetRow >= 1) {
        await nvim.winSetCursor(win, targetRow, 0);
      }
    }
  }

  Future<void> _ensureHighlights() async {
    _nsId ??= await nvim.createNamespace('viworkspace_sidebar');
    if (_highlightsInitialized) return;
    _highlightsInitialized = true;

    const groups = <String, Map<String, Object?>>{
      'ViworkspaceHeader': {'bold': true, 'link': 'Title'},
      'ViworkspaceDirectory': {'bold': true, 'link': 'Directory'},
      'ViworkspaceActiveFile': {'bold': true, 'link': 'Directory'},
      'ViworkspaceClipboard': {'italic': true, 'link': 'WarningMsg'},
      'ViworkspaceSearchCount': {'bold': true, 'link': 'DiagnosticInfo'},
      'ViworkspaceSearchMatch': {'link': 'Search'},
      'ViworkspaceSearchCurrent': {'bold': true, 'link': 'IncSearch'},
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

    try {
      await nvim.execLua(r'''
local function set_fg_only(group, target, is_bold)
  local ok, base = pcall(vim.api.nvim_get_hl, 0, { name = target, link = false })
  local spec = { bold = is_bold, cterm = { bold = is_bold } }
  if ok and type(base) == 'table' then
    spec.fg = base.fg
    spec.ctermfg = base.ctermfg
  end
  spec.bg = nil
  spec.ctermbg = nil
  pcall(vim.api.nvim_set_hl, 0, group, spec)
end
set_fg_only('ViworkspaceHeader', 'Title', true)
set_fg_only('ViworkspaceDirectory', 'Directory', true)
set_fg_only('ViworkspaceActiveFile', 'Directory', true)
''');
    } catch (_) {}
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
      'win': -1,
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
      'o': 'open_external',
      'O': 'reveal_in_finder',
      'a': 'new_file',
      'A': 'new_folder',
      '/': 'search',
      'n': 'search_next',
      'N': 'search_prev',
      '<Esc>': 'clear_search',
      'r': 'rename',
      'D': 'duplicate',
      'd': 'delete',
      'c': 'copy',
      'x': 'cut',
      'p': 'paste',
      'y': 'copy_filename',
      'Y': 'copy_relative_path',
      'gy': 'copy_absolute_path',
      'm': 'select_for_compare',
      'M': 'compare_with_selected',
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
    };

    for (final entry in mouseMappings.entries) {
      await nvim.bufSetKeymap(
        buf,
        'n',
        entry.key,
        "<LeftMouse><Cmd>lua require('vibrainium').action('workspace.${entry.value}')<CR>",
      );
      // Cancel visual mode if active before executing the action.
      await nvim.bufSetKeymap(
        buf,
        'x',
        entry.key,
        "<C-\\><C-n><LeftMouse><Cmd>lua require('vibrainium').action('workspace.${entry.value}')<CR>",
      );
    }

    // In Vim/Neovim, an unmapped `<2-LeftRelease>` or mouse drag automatically
    // engages Visual mode (`-- VISUAL --`). Disable drag and multi-click release/press
    // events in the sidebar buffer across normal, visual, and select modes.
    const ignoredMouseEvents = <String>[
      '<LeftDrag>',
      '<2-LeftDrag>',
      '<3-LeftDrag>',
      '<4-LeftDrag>',
      '<2-LeftRelease>',
      '<3-LeftRelease>',
      '<4-LeftRelease>',
      '<3-LeftMouse>',
      '<4-LeftMouse>',
    ];

    for (final key in ignoredMouseEvents) {
      await nvim.bufSetKeymap(buf, 'n', key, '<Nop>');
      await nvim.bufSetKeymap(buf, 'x', key, '<Nop>');
    }

    // Disable keyboard visual mode entry keys in the sidebar tree.
    for (final key in const ['v', 'V', '<C-v>']) {
      await nvim.bufSetKeymap(buf, 'n', key, '<Nop>');
    }

    await nvim.registerRightClickBuffer(buf, 'workspace.context_menu');

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
