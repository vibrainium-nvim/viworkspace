import 'package:nvim/nvim.dart';

/// Floating single-line input prompt for creating files/folders and renaming.
class InputPrompt {
  final Nvim nvim;
  int? _buf;
  int? _win;
  Future<void> Function(String value)? _onSubmit;

  InputPrompt(this.nvim);

  bool get isOpen => _win != null;
  int? get windowId => _win;
  int? get bufferId => _buf;

  Future<void> open({
    required String title,
    String initialValue = '',
    required Future<void> Function(String value) onSubmit,
  }) async {
    await nvim.activateOverlay(close);
    await close();
    nvim.setOverlayCloser(close);
    _onSubmit = onSubmit;

    final buf = await nvim.createBuf(listed: false, scratch: true);
    _buf = buf;

    await nvim.bufSetOption(buf, 'modifiable', true);
    await nvim.bufSetOption(buf, 'buftype', 'nofile');
    await nvim.bufSetOption(buf, 'bufhidden', 'wipe');
    await nvim.bufSetOption(buf, 'filetype', 'viworkspace-prompt');
    await nvim.bufSetLines(buf, lines: [initialValue]);

    final editorWidth = await nvim.getEditorWidth();
    final editorHeight = await nvim.getEditorHeight();
    final width = (editorWidth * 0.45).round().clamp(36, 64);
    const height = 1;
    final row = ((editorHeight - height) / 2).floor().clamp(1, editorHeight);
    final col = ((editorWidth - width) / 2).floor().clamp(1, editorWidth);

    final win = await nvim.openWin(buf, true, {
      'relative': 'editor',
      'row': row,
      'col': col,
      'width': width,
      'height': height,
      'style': 'minimal',
      'border': 'rounded',
      'title': ' $title — <CR> confirm, q cancel ',
      'title_pos': 'center',
    });
    _win = win;

    if (initialValue.isNotEmpty) {
      await nvim.winSetCursor(win, 1, initialValue.length);
    }

    await nvim.bufSetKeymap(
      buf,
      'n',
      '<CR>',
      "<Cmd>lua require('vibrainium').action('workspace.prompt_submit')<CR>",
    );
    await nvim.bufSetKeymap(
      buf,
      'i',
      '<CR>',
      "<Esc><Cmd>lua require('vibrainium').action('workspace.prompt_submit')<CR>",
    );
    await nvim.bufSetKeymap(
      buf,
      'n',
      'q',
      "<Cmd>lua require('vibrainium').action('workspace.prompt_close')<CR>",
    );
    // <C-c> closes the prompt in both normal and insert mode.
    // In insert mode, <Esc> transitions to normal mode without closing.
    // In normal mode, 'q' (or <C-c>) closes the prompt, while <Esc> stays in normal mode.
    for (final mode in ['n', 'i']) {
      await nvim.bufSetKeymap(
        buf,
        mode,
        '<C-c>',
        mode == 'i'
            ? "<Esc><Cmd>lua require('vibrainium').action('workspace.prompt_close')<CR>"
            : "<Cmd>lua require('vibrainium').action('workspace.prompt_close')<CR>",
      );
    }

    try {
      await nvim.execLua(
        '''
local buf = ...
local grp = vim.api.nvim_create_augroup('ViworkspaceInputPrompt', { clear = true })
vim.api.nvim_create_autocmd({ 'WinLeave', 'BufLeave' }, {
  group = grp,
  buffer = buf,
  once = true,
  callback = function()
    vim.schedule(function()
      require('vibrainium').action('workspace.prompt_close', buf)
    end)
  end,
})
''',
        [buf],
      );
    } catch (_) {}

    await nvim.command('startinsert!');
  }

  Future<void> submit() async {
    final buf = _buf;
    if (buf == null || !await nvim.bufIsValid(buf)) {
      await close();
      return;
    }
    final lines = await nvim.bufGetLines(buf);
    final text = lines.isEmpty ? '' : lines.first.trim();
    final callback = _onSubmit;
    await close();
    if (text.isEmpty) {
      return;
    }
    if (callback != null) {
      await callback(text);
    }
  }

  Future<void> close() async {
    nvim.clearOverlayCloser(close);
    final win = _win;
    final buf = _buf;
    _win = null;
    _buf = null;
    _onSubmit = null;
    if (buf != null) {
      try {
        await nvim.execLua(
          "pcall(vim.api.nvim_del_augroup_by_name, 'ViworkspaceInputPrompt')",
        );
      } catch (_) {}
    }
    if (win != null) {
      try {
        await nvim.command('stopinsert');
      } catch (_) {}
      try {
        if (await nvim.winIsValid(win)) {
          await nvim.winClose(win, force: true);
        }
      } catch (_) {}
    }
  }
}

/// Floating confirmation modal for destructive actions (e.g. delete).
class ConfirmPrompt {
  final Nvim nvim;
  int? _buf;
  int? _win;
  Future<void> Function()? _onConfirm;

  ConfirmPrompt(this.nvim);

  bool get isOpen => _win != null;
  int? get windowId => _win;
  int? get bufferId => _buf;

  Future<void> open({
    required String message,
    required Future<void> Function() onConfirm,
  }) async {
    await nvim.activateOverlay(close);
    await close();
    nvim.setOverlayCloser(close);
    _onConfirm = onConfirm;

    final buf = await nvim.createBuf(listed: false, scratch: true);
    _buf = buf;
    final line = ' $message (y/n) ';

    await nvim.bufSetOption(buf, 'modifiable', true);
    await nvim.bufSetLines(buf, lines: [line]);
    await nvim.bufSetOption(buf, 'modifiable', false);
    await nvim.bufSetOption(buf, 'buftype', 'nofile');
    await nvim.bufSetOption(buf, 'bufhidden', 'wipe');
    await nvim.bufSetOption(buf, 'filetype', 'viworkspace-confirm');

    final editorWidth = await nvim.getEditorWidth();
    final editorHeight = await nvim.getEditorHeight();
    final width = (line.length + 4).clamp(32, 68);
    const height = 1;
    final row = ((editorHeight - height) / 2).floor().clamp(1, editorHeight);
    final col = ((editorWidth - width) / 2).floor().clamp(1, editorWidth);

    final win = await nvim.openWin(buf, true, {
      'relative': 'editor',
      'row': row,
      'col': col,
      'width': width,
      'height': height,
      'style': 'minimal',
      'border': 'rounded',
      'title': ' Confirm ',
      'title_pos': 'center',
    });
    _win = win;
    await nvim.command('stopinsert');

    for (final key in ['y', 'Y', '<CR>']) {
      await nvim.bufSetKeymap(
        buf,
        'n',
        key,
        "<Cmd>lua require('vibrainium').action('workspace.confirm_yes')<CR>",
      );
    }
    for (final key in ['n', 'N', 'q', '<Esc>', '<C-c>']) {
      await nvim.bufSetKeymap(
        buf,
        'n',
        key,
        "<Cmd>lua require('vibrainium').action('workspace.confirm_no')<CR>",
      );
    }
    for (final key in ['<Esc>', '<C-c>']) {
      await nvim.bufSetKeymap(
        buf,
        'i',
        key,
        "<Cmd>lua require('vibrainium').action('workspace.confirm_no')<CR>",
      );
    }
    await nvim.bufSetKeymap(
      buf,
      'n',
      '<LeftMouse>',
      "<Cmd>lua local m = vim.fn.getmousepos(); if m.winid ~= $win then require('vibrainium').action('workspace.confirm_no') end<CR>",
    );

    try {
      await nvim.execLua(
        '''
local buf = ...
local grp = vim.api.nvim_create_augroup('ViworkspaceConfirmPrompt', { clear = true })
vim.api.nvim_create_autocmd({ 'WinLeave', 'BufLeave' }, {
  group = grp,
  buffer = buf,
  once = true,
  callback = function()
    vim.schedule(function()
      require('vibrainium').action('workspace.confirm_no', buf)
    end)
  end,
})
''',
        [buf],
      );
    } catch (_) {}
  }

  Future<void> confirm() async {
    final callback = _onConfirm;
    await close();
    if (callback != null) {
      await callback();
    }
  }

  Future<void> close() async {
    nvim.clearOverlayCloser(close);
    final win = _win;
    final buf = _buf;
    _win = null;
    _buf = null;
    _onConfirm = null;
    if (buf != null) {
      try {
        await nvim.execLua(
          "pcall(vim.api.nvim_del_augroup_by_name, 'ViworkspaceConfirmPrompt')",
        );
      } catch (_) {}
    }
    if (win != null) {
      try {
        if (await nvim.winIsValid(win)) {
          await nvim.winClose(win, force: true);
        }
      } catch (_) {}
    }
  }
}

/// A single entry in the workspace right-click [ContextMenuPrompt].
class ContextMenuItem extends NvimContextMenuItem {
  const ContextMenuItem({
    required super.label,
    super.displayLabel,
    required super.shortcut,
    super.isSubmenu = false,
    required super.onSelect,
  });
}

/// Floating context menu for right-click actions in the workspace sidebar.
class ContextMenuPrompt extends NvimContextMenu<ContextMenuItem> {
  ContextMenuPrompt(Nvim nvim)
      : super(
          nvim: nvim,
          actionPrefix: 'workspace',
          filetype: 'viworkspace-menu',
          augroupName: 'ViworkspaceContextMenu',
          rightClickAction: 'workspace.context_menu',
        );

  Future<void> open({
    List<ContextMenuItem>? items,
    List<NvimContextMenuRow<ContextMenuItem>>? rows,
    String title = 'Actions',
    int? anchorWin,
    int row = 1,
    int col = 2,
    Future<void> Function()? onCancel,
  }) =>
      openMenu(
        items: items,
        rows: rows,
        title: title,
        anchorWin: anchorWin,
        row: row,
        col: col,
        maxWidth: 60,
        onCancel: onCancel,
      );
}

/// Persistent 1-line regex search bar split docked at the bottom of the workspace sidebar.
class SearchPrompt {
  final Nvim nvim;
  int? _nsId;
  int? _buf;
  int? _win;
  String _countLabel = '';

  SearchPrompt(this.nvim);

  bool get isOpen => _win != null;
  int? get windowId => _win;
  int? get bufferId => _buf;
  String get countLabel => _countLabel;

  static String formatMatchCount({
    required String query,
    required int currentMatchIndex,
    required int totalMatches,
  }) {
    if (query.isEmpty) {
      return '';
    }
    final displayIdx =
        (totalMatches > 0 && currentMatchIndex >= 0) ? currentMatchIndex + 1 : 0;
    return '[$displayIdx/$totalMatches]';
  }

  Future<int> ensureBuffer({String initialQuery = ''}) async {
    _nsId ??= await nvim.createNamespace('viworkspace_search');
    var buf = _buf;
    if (buf == null || !await nvim.bufIsValid(buf)) {
      buf = await nvim.createBuf(listed: false, scratch: true);
      _buf = buf;

      await nvim.bufSetOption(buf, 'modifiable', true);
      await nvim.bufSetOption(buf, 'buftype', 'nofile');
      await nvim.bufSetOption(buf, 'bufhidden', 'hide');
      await nvim.bufSetOption(buf, 'swapfile', false);
      await nvim.bufSetOption(buf, 'filetype', 'viworkspace-search');
      await nvim.bufSetLines(buf, lines: [initialQuery]);
      await _bindKeys(buf);
    }
    return buf;
  }

  Future<void> _bindKeys(int buf) async {
    await nvim.bufSetKeymap(
      buf,
      'n',
      '<CR>',
      "<Cmd>lua require('vibrainium').action('workspace.search_submit')<CR>",
    );
    await nvim.bufSetKeymap(
      buf,
      'i',
      '<CR>',
      "<Esc><Cmd>lua require('vibrainium').action('workspace.search_submit')<CR>",
    );
    await nvim.bufSetKeymap(
      buf,
      'n',
      'q',
      "<Cmd>lua require('vibrainium').action('workspace.search_close')<CR>",
    );

    for (final mode in ['n', 'i']) {
      for (final key in ['<C-n>', '<Down>', '<Tab>']) {
        await nvim.bufSetKeymap(
          buf,
          mode,
          key,
          "<Cmd>lua require('vibrainium').action('workspace.search_next')<CR>",
        );
      }
      for (final key in ['<C-p>', '<Up>', '<S-Tab>']) {
        await nvim.bufSetKeymap(
          buf,
          mode,
          key,
          "<Cmd>lua require('vibrainium').action('workspace.search_prev')<CR>",
        );
      }
      for (final key in ['<Esc>', '<C-c>']) {
        await nvim.bufSetKeymap(
          buf,
          mode,
          key,
          mode == 'i'
              ? "<Esc><Cmd>lua require('vibrainium').action('workspace.search_close')<CR>"
              : "<Cmd>lua require('vibrainium').action('workspace.search_close')<CR>",
        );
      }
    }

    try {
      await nvim.execLua(
        '''
local buf = ...
local grp = vim.api.nvim_create_augroup('ViworkspaceSearchPrompt', { clear = true })
vim.api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, {
  group = grp,
  buffer = buf,
  callback = function()
    vim.schedule(function()
      require('vibrainium').action('workspace.search_change')
    end)
  end,
})
''',
        [buf],
      );
    } catch (_) {}
  }

  /// Ensures the persistent 1-line bottom search split window exists below [sidebarWin].
  Future<int?> ensureWindow({
    required int? sidebarWin,
    String query = '',
    int currentMatchIndex = -1,
    int totalMatches = 0,
  }) async {
    if (sidebarWin == null || !await nvim.winIsValid(sidebarWin)) {
      return null;
    }
    final buf = await ensureBuffer(initialQuery: query);
    var win = _win;
    if (win == null || !await nvim.winIsValid(win)) {
      win = await nvim.openWin(buf, false, {
        'win': sidebarWin,
        'split': 'below',
        'height': 1,
        'style': 'minimal',
      });
      _win = win;
      await nvim.winSetOption(win, 'number', false);
      await nvim.winSetOption(win, 'relativenumber', false);
      await nvim.winSetOption(win, 'signcolumn', 'no');
      await nvim.winSetOption(win, 'foldcolumn', '0');
      await nvim.winSetOption(win, 'statuscolumn', '  ');
      await nvim.winSetOption(win, 'wrap', false);
      await nvim.winSetOption(win, 'cursorline', false);
      await nvim.winSetOption(win, 'winfixheight', true);
      await nvim.winSetOption(win, 'winfixwidth', true);
    } else {
      final currentBuf = await nvim.winGetBuf(win);
      if (currentBuf != buf) {
        await nvim.winSetBuf(win, buf);
      }
    }
    await updateStatus(
      query: query,
      currentMatchIndex: currentMatchIndex,
      totalMatches: totalMatches,
    );
    return win;
  }

  /// Focuses the persistent bottom search bar and enters insert mode.
  Future<void> focus({
    required int? sidebarWin,
    String query = '',
    int currentMatchIndex = -1,
    int totalMatches = 0,
  }) async {
    final win = await ensureWindow(
      sidebarWin: sidebarWin,
      query: query,
      currentMatchIndex: currentMatchIndex,
      totalMatches: totalMatches,
    );
    if (win == null || !await nvim.winIsValid(win)) return;
    await nvim.setCurrentWin(win);
    final currentText = await readQuery();
    if (currentText.isNotEmpty) {
      await nvim.winSetCursor(win, 1, currentText.length);
    }
    await nvim.command('startinsert!');
  }

  Future<String> readQuery() async {
    final buf = _buf;
    if (buf == null || !await nvim.bufIsValid(buf)) return '';
    final lines = await nvim.bufGetLines(buf);
    return lines.isEmpty ? '' : lines.first;
  }

  Future<void> setQuery(
    String query, {
    int currentMatchIndex = -1,
    int totalMatches = 0,
  }) async {
    final buf = _buf;
    if (buf != null && await nvim.bufIsValid(buf)) {
      await nvim.bufSetOption(buf, 'modifiable', true);
      await nvim.bufSetLines(buf, lines: [query]);
    }
    await updateStatus(
      query: query,
      currentMatchIndex: currentMatchIndex,
      totalMatches: totalMatches,
    );
  }

  Future<void> updateStatus({
    required String query,
    required int currentMatchIndex,
    required int totalMatches,
  }) async {
    _countLabel = formatMatchCount(
      query: query,
      currentMatchIndex: currentMatchIndex,
      totalMatches: totalMatches,
    );
    final buf = _buf;
    final nsId = _nsId;
    if (buf == null || nsId == null || !await nvim.bufIsValid(buf)) return;
    await nvim.bufClearNamespace(buf, nsId);
    if (query.isEmpty) {
      await nvim.bufSetExtmark(buf, nsId, 0, 0, {
        'virt_text': [
          ['Search (Regex)...', 'ViworkspaceMuted'],
        ],
        'virt_text_pos': 'eol',
      });
    } else {
      await nvim.bufSetExtmark(buf, nsId, 0, 0, {
        'virt_text': [
          [' $_countLabel ', 'ViworkspaceSearchCount'],
        ],
        'virt_text_pos': 'right_align',
      });
    }
  }

  Future<void> onHotReloaded() async {
    final buf = _buf;
    if (buf != null && await nvim.bufIsValid(buf)) {
      await _bindKeys(buf);
    }
  }

  Future<void> close() async {
    final win = _win;
    _win = null;
    if (win != null) {
      try {
        if (await nvim.winIsValid(win)) {
          await nvim.winClose(win, force: true);
        }
      } catch (_) {}
    }
  }
}
