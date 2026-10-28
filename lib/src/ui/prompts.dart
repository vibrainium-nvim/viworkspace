import 'package:nvim/nvim.dart';

/// Floating single-line input prompt for creating files/folders and renaming.
class InputPrompt {
  final Nvim nvim;
  int? _buf;
  int? _win;
  Future<void> Function(String value)? _onSubmit;

  InputPrompt(this.nvim);

  bool get isOpen => _win != null;

  Future<void> open({
    required String title,
    String initialValue = '',
    required Future<void> Function(String value) onSubmit,
  }) async {
    await close();
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
      'title': ' $title — <CR> confirm, q/<Esc> cancel ',
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
    await nvim.bufSetKeymap(
      buf,
      'n',
      '<Esc>',
      "<Cmd>lua require('vibrainium').action('workspace.prompt_close')<CR>",
    );
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
    final win = _win;
    _win = null;
    _buf = null;
    _onSubmit = null;
    if (win != null) {
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
  int? _win;
  Future<void> Function()? _onConfirm;

  ConfirmPrompt(this.nvim);

  bool get isOpen => _win != null;

  Future<void> open({
    required String message,
    required Future<void> Function() onConfirm,
  }) async {
    await close();
    _onConfirm = onConfirm;

    final buf = await nvim.createBuf(listed: false, scratch: true);
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

    for (final key in ['y', 'Y', '<CR>']) {
      await nvim.bufSetKeymap(
        buf,
        'n',
        key,
        "<Cmd>lua require('vibrainium').action('workspace.confirm_yes')<CR>",
      );
    }
    for (final key in ['n', 'N', 'q', '<Esc>']) {
      await nvim.bufSetKeymap(
        buf,
        'n',
        key,
        "<Cmd>lua require('vibrainium').action('workspace.confirm_no')<CR>",
      );
    }
  }

  Future<void> confirm() async {
    final callback = _onConfirm;
    await close();
    if (callback != null) {
      await callback();
    }
  }

  Future<void> close() async {
    final win = _win;
    _win = null;
    _onConfirm = null;
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
class ContextMenuItem {
  final String label;
  final String shortcut;
  final Future<void> Function() onSelect;

  const ContextMenuItem({
    required this.label,
    required this.shortcut,
    required this.onSelect,
  });
}

/// Floating context menu for right-click actions in the workspace sidebar.
class ContextMenuPrompt {
  final Nvim nvim;
  int? _buf;
  int? _win;
  List<ContextMenuItem> _items = const [];
  Future<void> Function()? _onCancel;

  ContextMenuPrompt(this.nvim);

  bool get isOpen => _win != null;
  int? get windowId => _win;
  int? get bufferId => _buf;
  List<ContextMenuItem> get items => List.unmodifiable(_items);

  Future<void> open({
    required List<ContextMenuItem> items,
    String title = 'Actions',
    int? anchorWin,
    int row = 1,
    int col = 2,
    Future<void> Function()? onCancel,
  }) async {
    await close();
    if (items.isEmpty) return;

    _items = items;
    _onCancel = onCancel;

    final buf = await nvim.createBuf(listed: false, scratch: true);
    _buf = buf;

    var maxLabelLen = 0;
    var maxShortcutLen = 0;
    for (final item in items) {
      if (item.label.length > maxLabelLen) {
        maxLabelLen = item.label.length;
      }
      if (item.shortcut.length > maxShortcutLen) {
        maxShortcutLen = item.shortcut.length;
      }
    }

    final innerWidth = (maxLabelLen + maxShortcutLen + 4).clamp(22, 48);
    final lines = <String>[];
    for (final item in items) {
      final padCount =
          (innerWidth - 2 - item.label.length - item.shortcut.length)
              .clamp(1, innerWidth);
      lines.add(' ${item.label}${' ' * padCount}${item.shortcut} ');
    }

    await nvim.bufSetOption(buf, 'modifiable', true);
    await nvim.bufSetLines(buf, lines: lines);
    await nvim.bufSetOption(buf, 'modifiable', false);
    await nvim.bufSetOption(buf, 'buftype', 'nofile');
    await nvim.bufSetOption(buf, 'bufhidden', 'wipe');
    await nvim.bufSetOption(buf, 'filetype', 'viworkspace-menu');

    final config = <String, Object?>{
      if (anchorWin != null) ...{
        'relative': 'win',
        'win': anchorWin,
        'row': row,
        'col': col,
      } else ...{
        'relative': 'editor',
        'row': row,
        'col': col,
      },
      'width': innerWidth,
      'height': lines.length,
      'style': 'minimal',
      'border': 'rounded',
      'title': ' $title ',
      'title_pos': 'center',
    };

    final win = await nvim.openWin(buf, true, config);
    _win = win;

    await nvim.winSetOption(win, 'cursorline', true);
    await nvim.winSetOption(win, 'wrap', false);
    await nvim.winSetCursor(win, 1, 0);

    await nvim.bufSetKeymap(
      buf,
      'n',
      '<LeftMouse>',
      "<LeftMouse><Cmd>lua require('vibrainium').action('workspace.menu_click')<CR>",
    );
    await nvim.bufSetKeymap(
      buf,
      'n',
      '<2-LeftMouse>',
      "<LeftMouse><Cmd>lua require('vibrainium').action('workspace.menu_click')<CR>",
    );
    await nvim.bufSetKeymap(
      buf,
      'n',
      '<CR>',
      "<Cmd>lua require('vibrainium').action('workspace.menu_confirm')<CR>",
    );
    await nvim.bufSetKeymap(
      buf,
      'n',
      '<RightMouse>',
      "<Cmd>lua require('vibrainium').action('workspace.context_menu')<CR>",
    );
    for (final key in ['q', '<Esc>']) {
      await nvim.bufSetKeymap(
        buf,
        'n',
        key,
        "<Cmd>lua require('vibrainium').action('workspace.menu_close')<CR>",
      );
    }

    for (var i = 0; i < items.length; i++) {
      final key = items[i].shortcut;
      if (key.isEmpty || key == '<CR>' || key == 'q' || key == '<Esc>') {
        continue;
      }
      await nvim.bufSetKeymap(
        buf,
        'n',
        key,
        "<Cmd>lua require('vibrainium').action('workspace.menu_select:$i')<CR>",
      );
    }
  }

  Future<void> handleClick() async {
    final win = _win;
    if (win == null || !await nvim.winIsValid(win)) {
      await close();
      return;
    }
    final mousePos = await nvim.getMousePos();
    if (mousePos != null) {
      if (mousePos.winId != win) {
        await close();
        return;
      }
      if (mousePos.line >= 1 && mousePos.line <= _items.length) {
        await selectIndex(mousePos.line - 1);
        return;
      }
    }
    await confirm();
  }

  Future<void> confirm() async {
    final win = _win;
    if (win == null || !await nvim.winIsValid(win)) {
      await close();
      return;
    }
    final (row, _) = await nvim.winGetCursor(win);
    await selectIndex(row - 1);
  }

  Future<void> selectIndex(int index) async {
    final items = _items;
    await close();
    if (index >= 0 && index < items.length) {
      await items[index].onSelect();
    }
  }

  Future<void> cancel() async {
    final callback = _onCancel;
    await close();
    if (callback != null) {
      await callback();
    }
  }

  Future<void> close() async {
    final win = _win;
    _win = null;
    _buf = null;
    _items = const [];
    _onCancel = null;
    if (win != null) {
      try {
        if (await nvim.winIsValid(win)) {
          await nvim.winClose(win, force: true);
        }
      } catch (_) {}
    }
  }
}
