import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:viworkspace/viworkspace.dart';

class _FakeNvimServer {
  final StreamController<List<int>> _toClient = StreamController<List<int>>();
  final StreamController<List<int>> _fromClient = StreamController<List<int>>();
  late final RpcSession serverSession;
  late final RpcSession clientSession;

  String cwd;
  int _nextBuf = 1;
  int _nextWin = 100;
  int lastCreatedBuf = 0;
  final Map<int, List<String>> bufLines = {};
  final Map<int, Map<String, Object?>> bufOptions = {};
  final Map<int, Map<String, Object?>> bufVars = {};
  final Map<int, String> bufNames = {};
  final Map<int, Map<String, String>> bufKeymaps = {};
  final Map<String, String> bufModeKeymaps = {};
  final Set<int> validWins = {1};
  final Map<int, int> winBufs = {1: 0};
  final Map<int, Map<String, Object?>> winConfigs = {};
  final Map<int, Map<String, Object?>> winOptions = {};
  final Map<int, (int, int)> cursors = {};
  int currentWin = 1;
  int alternateWin = 0;
  Map<String, Object?>? mousePos;
  final List<String> commands = [];
  final List<String> notifications = [];
  final Map<String, String> registers = {};

  _FakeNvimServer({required this.cwd}) {
    serverSession = RpcSession(
      input: _fromClient.stream,
      output: (Uint8List b) => _toClient.add(b),
    );
    clientSession = RpcSession(
      input: _toClient.stream,
      output: (Uint8List b) => _fromClient.add(b),
    );

    serverSession.onRequest = _handleRequest;
  }

  Future<Object?> _handleRequest(String method, List<Object?> params) async {
    switch (method) {
      case 'nvim_create_namespace':
        return 1;
      case 'nvim_set_hl':
        return null;
      case 'nvim_create_buf':
        final id = _nextBuf++;
        lastCreatedBuf = id;
        bufLines[id] = [];
        bufKeymaps[id] = {};
        return MsgpackExt(0, MsgpackCodec.encode(id));
      case 'nvim_buf_is_valid':
        return bufLines.containsKey(params[0] as int);
      case 'nvim_buf_set_lines':
        final buf = params[0] as int;
        final lines = (params[4] as List).map((e) => e.toString()).toList();
        bufLines[buf] = lines;
        return null;
      case 'nvim_buf_get_lines':
        final buf = params[0] as int;
        return bufLines[buf] ?? const <String>[];
      case 'nvim_buf_get_name':
        final buf = params[0] as int;
        return bufNames[buf] ?? '';
      case 'nvim_get_current_buf':
        return winBufs[currentWin] ?? 0;
      case 'nvim_set_option_value':
        final name = params[0].toString();
        final value = params[1];
        final opts = (params[2] as Map).cast<String, Object?>();
        if (opts.containsKey('win')) {
          final win = opts['win'] as int;
          winOptions.putIfAbsent(win, () => {})[name] = value;
        }
        if (opts.containsKey('buf')) {
          final buf = opts['buf'] as int;
          bufOptions.putIfAbsent(buf, () => {})[name] = value;
        }
        return null;
      case 'nvim_buf_set_var':
        final buf = params[0] as int;
        bufVars.putIfAbsent(buf, () => {})[params[1].toString()] = params[2];
        return null;
      case 'nvim_buf_set_keymap':
        final buf = params[0] as int;
        final mode = params[1].toString();
        final lhs = params[2].toString();
        final rhs = params[3].toString();
        bufKeymaps.putIfAbsent(buf, () => {})[lhs] = rhs;
        bufModeKeymaps['$buf:$mode:$lhs'] = rhs;
        return null;
      case 'nvim_buf_clear_namespace':
        return null;
      case 'nvim_buf_set_extmark':
        return 1;
      case 'nvim_open_win':
        final buf = params[0] as int;
        final enter = params[1] as bool;
        final config = (params[2] as Map).cast<String, Object?>();
        final win = _nextWin++;
        validWins.add(win);
        winBufs[win] = buf;
        winConfigs[win] = config;
        cursors[win] = (1, 0);
        if (enter) {
          alternateWin = currentWin;
          currentWin = win;
        }
        return MsgpackExt(1, MsgpackCodec.encode(win));
      case 'nvim_win_get_config':
        return winConfigs[params[0] as int] ?? const <String, Object?>{};
      case 'nvim_win_set_config':
        final win = params[0] as int;
        final cfg = (params[1] as Map).cast<String, Object?>();
        winConfigs.putIfAbsent(win, () => {}).addAll(cfg);
        return null;
      case 'nvim_win_get_buf':
        return winBufs[params[0] as int] ?? 0;
      case 'nvim_win_is_valid':
        return validWins.contains(params[0] as int);
      case 'nvim_win_close':
        validWins.remove(params[0] as int);
        winBufs.remove(params[0] as int);
        return null;
      case 'nvim_win_get_cursor':
        final win = params[0] as int;
        final c = cursors[win] ?? (1, 0);
        return [c.$1, c.$2];
      case 'nvim_win_set_cursor':
        final win = params[0] as int;
        final pos = params[1] as List;
        cursors[win] = (pos[0] as int, pos[1] as int);
        return null;
      case 'nvim_get_current_win':
        return currentWin;
      case 'nvim_set_current_win':
        final target = params[0] as int;
        alternateWin = currentWin;
        currentWin = target;
        return null;
      case 'nvim_list_wins':
        return validWins.toList();
      case 'nvim_win_get_position':
        return [0, 0];
      case 'nvim_win_get_width':
        return 36;
      case 'nvim_win_get_height':
        return 30;
      case 'nvim_call_function':
        if (params[0] == 'getcwd') return cwd;
        if (params[0] == 'getmousepos') return mousePos;
        if (params[0] == 'line') return 1;
        if (params[0] == 'winnr') return alternateWin > 0 ? 99 : 0;
        if (params[0] == 'win_getid') return alternateWin;
        if (params[0] == 'setreg') {
          final args = params[1] as List;
          registers[args[0].toString()] = args[1].toString();
          return 0;
        }
        return null;
      case 'nvim_get_option_value':
        if (params[0] == 'columns') return 120;
        if (params[0] == 'lines') return 40;
        final opts = (params[1] as Map?)?.cast<String, Object?>() ?? const {};
        if (opts.containsKey('buf')) {
          final buf = opts['buf'] as int;
          return bufOptions[buf]?[params[0].toString()];
        }
        return null;
      case 'nvim_notify':
        notifications.add(params[0].toString());
        return null;
      case 'nvim_command':
        commands.add(params[0].toString());
        return null;
      default:
        return null;
    }
  }

  Future<void> dispose() async {
    await clientSession.close();
    await serverSession.close();
    await _toClient.close();
    await _fromClient.close();
  }
}

void main() {
  group('WorkspaceSidebar RPC integration', () {
    late Directory tempRoot;
    late Directory workspaceDir;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('viworkspace_sidebar_');
      workspaceDir = Directory('${tempRoot.path}/demo_ws');
      await workspaceDir.create();
      await Directory('${workspaceDir.path}/lib').create();
      await File('${workspaceDir.path}/lib/main.dart').writeAsString('');
      await File('${workspaceDir.path}/.gitignore').writeAsString('');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('binds exact shortcuts and supports expand/open, new_file, new_folder, rename, copy/paste, delete, and toggle_hidden', () async {
      final launched = <(String, List<String>)>[];
      final server = _FakeNvimServer(cwd: workspaceDir.path);
      final sidebar = WorkspaceSidebar(
        nvim: Nvim(server.clientSession),
        processRunner: (exe, args) async {
          launched.add((exe, args));
          return ProcessResult(1, 0, '', '');
        },
      );

      await server.serverSession.request('vibrainium_action', ['workspace.open']);
      expect(await sidebar.isOpen(), isTrue);
      expect(server.winConfigs[100]!['win'], -1);
      expect(server.winConfigs[100]!['split'], 'left');
      expect(server.winConfigs[100]!['style'], 'minimal');
      expect(server.winOptions[100]!['number'], isFalse);
      expect(server.winOptions[100]!['relativenumber'], isFalse);
      expect(server.winOptions[100]!['signcolumn'], 'no');
      expect(server.winOptions[100]!['foldcolumn'], '0');
      expect(server.winOptions[100]!['statuscolumn'], '');

      expect(
        server.bufKeymaps[1]!.keys.toSet(),
        {
          '<CR>',
          'o',
          'O',
          'a',
          'A',
          '/',
          'n',
          'N',
          '<Esc>',
          'r',
          'D',
          'd',
          'c',
          'x',
          'p',
          'y',
          'Y',
          'gy',
          'm',
          'M',
          '.',
          'e',
          'R',
          'q',
          '<LeftMouse>',
          '<2-LeftMouse>',
          '<LeftDrag>',
          '<2-LeftDrag>',
          '<3-LeftDrag>',
          '<4-LeftDrag>',
          '<2-LeftRelease>',
          '<3-LeftRelease>',
          '<4-LeftRelease>',
          '<3-LeftMouse>',
          '<4-LeftMouse>',
          'v',
          'V',
          '<C-v>',
        },
      );
      expect(
        server.bufModeKeymaps['1:n:<LeftMouse>'],
        "<LeftMouse><Cmd>lua require('vibrainium').action('workspace.click')<CR>",
      );
      expect(
        server.bufModeKeymaps['1:x:<LeftMouse>'],
        "<C-\\><C-n><LeftMouse><Cmd>lua require('vibrainium').action('workspace.click')<CR>",
      );
      expect(
        server.bufModeKeymaps['1:n:<2-LeftMouse>'],
        "<LeftMouse><Cmd>lua require('vibrainium').action('workspace.double_click')<CR>",
      );
      expect(
        server.bufModeKeymaps['1:x:<2-LeftMouse>'],
        "<C-\\><C-n><LeftMouse><Cmd>lua require('vibrainium').action('workspace.double_click')<CR>",
      );
      expect(server.bufModeKeymaps['1:n:<2-LeftRelease>'], '<Nop>');
      expect(server.bufModeKeymaps['1:x:<2-LeftRelease>'], '<Nop>');
      expect(server.bufModeKeymaps['1:n:<LeftDrag>'], '<Nop>');
      expect(server.bufModeKeymaps['1:x:<LeftDrag>'], '<Nop>');
      expect(server.bufModeKeymaps['1:n:<2-LeftDrag>'], '<Nop>');
      expect(server.bufModeKeymaps['1:x:<2-LeftDrag>'], '<Nop>');
      expect(server.bufModeKeymaps['1:n:v'], '<Nop>');
      expect(server.bufModeKeymaps['1:n:V'], '<Nop>');
      expect(server.bufModeKeymaps['1:n:<C-v>'], '<Nop>');
      expect(
        server.bufVars[1]!['vibrainium_right_mouse_action'],
        'workspace.context_menu',
      );

      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
      ]);

      // <CR> on line 1 (workspace header) does not collapse anything
      server.cursors[100] = (1, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.enter']);
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
      ]);

      // <CR> on line 2 (`lib`) expands `lib`
      server.cursors[100] = (2, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.enter']);
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '     main.dart',
      ]);

      // <CR> on line 3 (`main.dart`) opens the file in main window
      server.cursors[100] = (3, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.enter']);
      expect(
        server.commands.any((c) => c.endsWith('/lib/main.dart')),
        isTrue,
      );

      // `.` toggles hidden files on
      await server.serverSession.request('vibrainium_action', ['workspace.toggle_hidden']);
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '     main.dart',
        '   .gitignore',
      ]);

      // `.` toggles hidden files back off
      await server.serverSession.request('vibrainium_action', ['workspace.toggle_hidden']);

      // `n` on `lib` creates a new file inside `lib`
      server.cursors[100] = (2, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.new_file']);
      server.bufLines[server.lastCreatedBuf] = ['util.dart'];
      await server.serverSession.request('vibrainium_action', ['workspace.prompt_submit']);
      expect(
        await File('${workspaceDir.path}/lib/util.dart').exists(),
        isTrue,
      );
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '     main.dart',
        '     util.dart',
      ]);

      // `N` on workspace header creates a new folder at root
      server.cursors[100] = (1, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.new_folder']);
      server.bufLines[server.lastCreatedBuf] = ['test'];
      await server.serverSession.request('vibrainium_action', ['workspace.prompt_submit']);
      expect(await Directory('${workspaceDir.path}/test').exists(), isTrue);

      // `r` on `util.dart` renames it to `helper.dart`
      final utilIdx =
          server.bufLines[1]!.indexWhere((l) => l.contains('util.dart'));
      server.cursors[100] = (utilIdx + 1, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.rename']);
      server.bufLines[server.lastCreatedBuf] = ['helper.dart'];
      await server.serverSession.request('vibrainium_action', ['workspace.prompt_submit']);
      expect(
        await File('${workspaceDir.path}/lib/helper.dart').exists(),
        isTrue,
      );

      // `c` on `helper.dart` then `p` on `test` folder copies `helper.dart` into `test/`
      final helperIdx =
          server.bufLines[1]!.indexWhere((l) => l.contains('helper.dart'));
      server.cursors[100] = (helperIdx + 1, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.copy_filename']);
      expect(server.registers['+'], 'helper.dart');
      expect(server.registers['"'], 'helper.dart');

      await server.serverSession.request('vibrainium_action', ['workspace.copy_relative_path']);
      expect(server.registers['+'], 'lib/helper.dart');

      await server.serverSession.request('vibrainium_action', ['workspace.copy_absolute_path']);
      expect(
        server.registers['+'],
        FileOps.normalizePath('${workspaceDir.path}/lib/helper.dart'),
      );

      await server.serverSession.request('vibrainium_action', ['workspace.open_external']);
      expect(
        launched.last.$2,
        contains(FileOps.normalizePath('${workspaceDir.path}/lib/helper.dart')),
      );

      await server.serverSession.request('vibrainium_action', ['workspace.reveal_in_finder']);
      expect(
        launched.last.$2,
        contains(FileOps.normalizePath('${workspaceDir.path}/lib/helper.dart')),
      );

      await server.serverSession.request('vibrainium_action', ['workspace.copy']);
      expect(
        server.bufLines[1]![helperIdx],
        contains('helper.dart [copy]'),
      );

      final testDirIdx =
          server.bufLines[1]!.indexWhere((l) => l.contains('test'));
      server.cursors[100] = (testDirIdx + 1, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.paste']);
      expect(
        await File('${workspaceDir.path}/test/helper.dart').exists(),
        isTrue,
      );

      // `d` on `test/helper.dart` and confirm deletes it
      final pastedIdx =
          server.bufLines[1]!.lastIndexWhere((l) => l.contains('helper.dart'));
      server.cursors[100] = (pastedIdx + 1, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.delete']);
      await server.serverSession.request('vibrainium_action', ['workspace.confirm_yes']);
      expect(
        await File('${workspaceDir.path}/test/helper.dart').exists(),
        isFalse,
      );

      await server.dispose();
    });

    test('hides workspace.exclude patterns from .vibrainium/settings.json and toggles with workspace.toggle_exclude', () async {
      await Directory('${workspaceDir.path}/.vibrainium').create();
      await File('${workspaceDir.path}/.vibrainium/settings.json').writeAsString('''
{
  "workspace.exclude": ["build", "*.g.dart"]
}
''');
      await Directory('${workspaceDir.path}/build').create();
      await File('${workspaceDir.path}/lib/model.g.dart').writeAsString('');

      final server = _FakeNvimServer(cwd: workspaceDir.path);
      final sidebar = WorkspaceSidebar(nvim: Nvim(server.clientSession));

      await server.serverSession.request('vibrainium_action', ['workspace.open']);
      expect(await sidebar.isOpen(), isTrue);
      expect(server.winConfigs[100]!['win'], -1);
      expect(server.winConfigs[100]!['split'], 'left');
      expect(server.winConfigs[100]!['style'], 'minimal');
      expect(server.winOptions[100]!['number'], isFalse);
      expect(server.winOptions[100]!['relativenumber'], isFalse);
      expect(server.winOptions[100]!['signcolumn'], 'no');
      expect(server.winOptions[100]!['foldcolumn'], '0');
      expect(server.winOptions[100]!['statuscolumn'], '');

      // Expand `lib`
      server.cursors[100] = (2, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.enter']);

      // `build` and `lib/model.g.dart` are excluded
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '     main.dart',
      ]);

      // `e` -> `workspace.toggle_exclude` shows excluded entries
      await server.serverSession.request('vibrainium_action', ['workspace.toggle_exclude']);
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  build',
        '  lib',
        '     main.dart',
        '     model.g.dart',
      ]);

      // `e` again hides them
      await server.serverSession.request('vibrainium_action', ['workspace.toggle_exclude']);
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '     main.dart',
      ]);

      await server.dispose();
    });

    test('supports mouse single-click, double-click, and right-click context menu', () async {
      final launchedFromMenu = <(String, List<String>)>[];
      final server = _FakeNvimServer(cwd: workspaceDir.path);
      final sidebar = WorkspaceSidebar(
        nvim: Nvim(server.clientSession),
        processRunner: (exe, args) async {
          launchedFromMenu.add((exe, args));
          return ProcessResult(1, 0, '', '');
        },
      );

      await server.serverSession.request('vibrainium_action', ['workspace.open']);
      expect(await sidebar.isOpen(), isTrue);
      expect(server.winConfigs[100]!['win'], -1);
      expect(server.winConfigs[100]!['split'], 'left');
      expect(server.winConfigs[100]!['style'], 'minimal');
      expect(server.winOptions[100]!['number'], isFalse);
      expect(server.winOptions[100]!['relativenumber'], isFalse);
      expect(server.winOptions[100]!['signcolumn'], 'no');
      expect(server.winOptions[100]!['foldcolumn'], '0');
      expect(server.winOptions[100]!['statuscolumn'], '');

      // 1. Single-click (`workspace.click`) on `lib` does NOT expand it
      server.cursors[100] = (2, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.click']);
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
      ]);

      // 2. Double-click (`workspace.double_click`) on `lib` expands it
      server.cursors[100] = (2, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.double_click']);
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '     main.dart',
      ]);

      // 3. Single-click on `main.dart` does NOT open the file
      server.cursors[100] = (3, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.click']);
      expect(server.commands, isEmpty);

      // 4. Double-click on `main.dart` opens the file in main window
      server.cursors[100] = (3, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.double_click']);
      expect(
        server.commands.any((c) => c.endsWith('/lib/main.dart')),
        isTrue,
      );

      // 5. Right-click (`workspace.context_menu`) on `lib` opens context menu without Expand/Collapse Folder
      server.cursors[100] = (2, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.context_menu']);
      expect(sidebar.contextMenu.isOpen, isTrue);
      final menuBuf = sidebar.contextMenu.bufferId!;
      final menuWin = sidebar.contextMenu.windowId!;
      expect(
        server.bufLines[menuBuf]!.any((l) => l.contains('Expand Folder') || l.contains('Collapse Folder')),
        isFalse,
      );
      expect(
        sidebar.contextMenu.items.map((i) => i.label),
        containsAll([
          'Open Externally',
          'Reveal in Finder',
          'Copy Filename',
          'Copy Relative Path',
          'Copy Absolute Path',
        ]),
      );
      expect(
        server.bufKeymaps[menuBuf]!.keys,
        containsAll(['<LeftMouse>', '<2-LeftMouse>', '<CR>', 'q', '<Esc>', '<C-c>', 'o', 'O', 'y', 'Y', 'gy']),
      );
      expect(server.bufKeymaps[menuBuf]!.keys, isNot(contains('<RightMouse>')));
      expect(
        server.bufVars[menuBuf]!['vibrainium_right_mouse_action'],
        'workspace.context_menu',
      );

      // Single-click back in sidebar (`workspace.click`) dismisses context menu
      await server.serverSession.request('vibrainium_action', ['workspace.click']);
      expect(sidebar.contextMenu.isOpen, isFalse);
      expect(server.validWins.contains(menuWin), isFalse);

      // 6. Right-click on `lib` and click "New File" via `workspace.menu_confirm`
      server.cursors[100] = (2, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.context_menu']);
      expect(sidebar.contextMenu.isOpen, isTrue);
      final menuWin2 = sidebar.contextMenu.windowId!;
      final newFileRow = sidebar.contextMenu.rowIndexWhere((i) => i.label == 'New File') + 1;
      server.cursors[menuWin2] = (newFileRow, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.menu_confirm']);
      expect(sidebar.contextMenu.isOpen, isFalse);

      // Input prompt is now open for creating a file inside `lib`
      server.bufLines[server.lastCreatedBuf] = ['from_menu.dart'];
      await server.serverSession.request('vibrainium_action', ['workspace.prompt_submit']);
      expect(
        await File('${workspaceDir.path}/lib/from_menu.dart').exists(),
        isTrue,
      );

      // 6b. Right-click on `from_menu.dart` and select `Copy Filename`, `Copy Relative Path`, `Copy Absolute Path`
      final fromMenuIdx = server.bufLines[1]!.indexWhere((l) => l.contains('from_menu.dart'));
      server.cursors[100] = (fromMenuIdx + 1, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.context_menu']);
      final copyNameIdx = sidebar.contextMenu.items.indexWhere((i) => i.label == 'Copy Filename');
      await server.serverSession.request('vibrainium_action', ['workspace.menu_select:$copyNameIdx']);
      expect(server.registers['+'], 'from_menu.dart');

      await server.serverSession.request('vibrainium_action', ['workspace.context_menu']);
      final copyRelIdx = sidebar.contextMenu.items.indexWhere((i) => i.label == 'Copy Relative Path');
      await server.serverSession.request('vibrainium_action', ['workspace.menu_select:$copyRelIdx']);
      expect(server.registers['+'], 'lib/from_menu.dart');

      await server.serverSession.request('vibrainium_action', ['workspace.context_menu']);
      final copyAbsIdx = sidebar.contextMenu.items.indexWhere((i) => i.label == 'Copy Absolute Path');
      await server.serverSession.request('vibrainium_action', ['workspace.menu_select:$copyAbsIdx']);
      expect(
        server.registers['+'],
        FileOps.normalizePath('${workspaceDir.path}/lib/from_menu.dart'),
      );

      await server.serverSession.request('vibrainium_action', ['workspace.context_menu']);
      final openExtIdx = sidebar.contextMenu.items.indexWhere((i) => i.label == 'Open Externally');
      await server.serverSession.request('vibrainium_action', ['workspace.menu_select:$openExtIdx']);
      expect(
        launchedFromMenu.last.$2,
        contains(FileOps.normalizePath('${workspaceDir.path}/lib/from_menu.dart')),
      );

      await server.serverSession.request('vibrainium_action', ['workspace.context_menu']);
      final revealIdx = sidebar.contextMenu.items.indexWhere((i) => i.label == 'Reveal in Finder');
      await server.serverSession.request('vibrainium_action', ['workspace.menu_select:$revealIdx']);
      expect(
        launchedFromMenu.last.$2,
        contains(FileOps.normalizePath('${workspaceDir.path}/lib/from_menu.dart')),
      );

      // 7. Right-click on workspace header and trigger `Show Hidden Files` via shortcut (`menu_select`)
      server.cursors[100] = (1, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.context_menu']);
      expect(sidebar.contextMenu.isOpen, isTrue);
      final toggleHiddenIdx = sidebar.contextMenu.items.indexWhere(
        (i) => i.label.contains('Hidden Files'),
      );
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.menu_select:$toggleHiddenIdx'],
      );
      expect(sidebar.contextMenu.isOpen, isFalse);
      expect(
        server.bufLines[1]!.any((l) => l.contains('.gitignore')),
        isTrue,
      );

      // 8. Right-clicking on `main.dart` (row 4) while cursor is on row 1 uses getmousepos
      //    to update cursor and show `main.dart` in the popup title
      server.cursors[100] = (1, 0);
      server.mousePos = {
        'winid': 100,
        'winrow': 4,
        'wincol': 6,
        'line': 4,
        'column': 6,
        'screenrow': 4,
        'screencol': 6,
      };
      await server.serverSession.request('vibrainium_action', ['workspace.context_menu']);
      expect(sidebar.contextMenu.isOpen, isTrue);
      expect(server.cursors[100], (4, 0));
      final mainMenuWin = sidebar.contextMenu.windowId!;
      expect(server.winConfigs[mainMenuWin]!['title'], ' main.dart ');

      // 9. Right-clicking on `lib` (row 2) while `main.dart` context menu is still open
      //    switches context menu to `lib`
      server.mousePos = {
        'winid': mainMenuWin,
        'winrow': 1,
        'wincol': 4,
        'line': 1,
        'column': 4,
        'screenrow': 2,
        'screencol': 6,
      };
      await server.serverSession.request('vibrainium_action', ['workspace.context_menu']);
      expect(sidebar.contextMenu.isOpen, isTrue);
      expect(server.cursors[100], (2, 0));
      final libMenuWin = sidebar.contextMenu.windowId!;
      expect(server.winConfigs[libMenuWin]!['title'], ' lib ');

      // 10. Left-clicking outside the open context menu (`menu_click` with winid=100)
      //     closes the context menu without executing any item
      server.mousePos = {
        'winid': 100,
        'winrow': 1,
        'wincol': 2,
        'line': 1,
        'column': 2,
        'screenrow': 1,
        'screencol': 2,
      };
      await server.serverSession.request('vibrainium_action', ['workspace.menu_click']);
      expect(sidebar.contextMenu.isOpen, isFalse);
      // `lib` remains expanded (Collapse Folder was NOT executed)
      expect(
        server.bufLines[1]!.any((l) => l.contains('  lib')),
        isTrue,
      );

      await server.dispose();
    });

    test('double-clicking a file opens it in the active editor panel instead of side panel or inactive splits', () async {
      final server = _FakeNvimServer(cwd: workspaceDir.path);
      // Set up window layout:
      // - win 10: a non-editor side panel (`buftype: nofile`) listed first
      // - win 1: inactive editor panel
      // - win 2: active editor panel
      server.validWins
        ..clear()
        ..addAll([10, 1, 2]);
      server.winBufs[10] = 50;
      server.bufOptions[50] = {'buftype': 'nofile', 'filetype': 'vivcs'};
      server.winBufs[1] = 51;
      server.bufOptions[51] = {'buftype': '', 'filetype': 'dart'};
      server.winBufs[2] = 52;
      server.bufOptions[52] = {'buftype': '', 'filetype': 'dart'};
      server.currentWin = 2;

      final sidebar = WorkspaceSidebar(nvim: Nvim(server.clientSession));
      await server.serverSession.request('vibrainium_action', ['workspace.open']);
      final sidebarWin = sidebar.windowId!;

      // Expand `lib` (row 2) via double-click
      server.mousePos = {
        'winid': sidebarWin,
        'winrow': 2,
        'wincol': 4,
        'line': 2,
        'column': 4,
        'screenrow': 2,
        'screencol': 4,
      };
      await server.serverSession.request('vibrainium_action', ['workspace.double_click']);

      // Now double-click `main.dart` (row 3) while sidebarWin is focused;
      // should open in active editor panel (win 2), NOT in sidebarWin or win 10 or win 1
      server.mousePos = {
        'winid': sidebarWin,
        'winrow': 3,
        'wincol': 6,
        'line': 3,
        'column': 6,
        'screenrow': 3,
        'screencol': 6,
      };
      await server.serverSession.request('vibrainium_action', ['workspace.double_click']);

      expect(server.currentWin, 2);
      expect(
        server.commands.any((c) => c.endsWith('/lib/main.dart')),
        isTrue,
      );

      await server.dispose();
    });

    test('synchronizes active editor file by expanding parent folders and moving sidebar cursor without stealing focus', () async {
      await Directory('${workspaceDir.path}/lib/src/ui').create(recursive: true);
      final deepFile = File('${workspaceDir.path}/lib/src/ui/view.dart');
      await deepFile.writeAsString('class View {}');

      final server = _FakeNvimServer(cwd: workspaceDir.path);
      server.winBufs[1] = 10;
      server.bufOptions[10] = {'buftype': '', 'filetype': 'dart'};
      server.bufNames[10] = deepFile.path;
      server.currentWin = 1;

      final sidebar = WorkspaceSidebar(nvim: Nvim(server.clientSession));
      await server.serverSession.request('vibrainium_action', ['workspace.open']);
      final sidebarWin = sidebar.windowId!;

      // Opening the workspace sidebar auto-expands `lib/src/ui` and selects `view.dart`
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '    src',
        '      ui',
        '         view.dart',
        '     main.dart',
      ]);
      expect(server.cursors[sidebarWin], (5, 0));

      // Collapse `lib` and return focus to editor window 1
      server.cursors[sidebarWin] = (2, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.enter']);
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
      ]);
      server.currentWin = 1;

      // Trigger `workspace.sync_active_file` (as BufEnter/WinEnter autocmd does)
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.sync_active_file'],
      );
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '    src',
        '      ui',
        '         view.dart',
        '     main.dart',
      ]);
      expect(server.cursors[sidebarWin], (5, 0));
      // Editor window 1 keeps focus during auto-sync
      expect(server.currentWin, 1);

      // `workspace.reveal` also focuses the sidebar window
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.reveal'],
      );
      expect(server.currentWin, sidebarWin);
      expect(server.cursors[sidebarWin], (5, 0));

      // Simulate daemon reconnect (`attachWindow(null)`) and concurrent sync_active_file calls with explicit path
      sidebar.attachWindow(null);
      sidebar.treeState.expandedDirs.clear();
      server.currentWin = 1;
      await Future.wait([
        server.serverSession.request(
          'vibrainium_action',
          ['workspace.sync_active_file', deepFile.path],
        ),
        server.serverSession.request(
          'vibrainium_action',
          ['workspace.sync_active_file', deepFile.path],
        ),
      ]);
      expect(sidebar.windowId, sidebarWin);
      expect(server.cursors[sidebarWin], (5, 0));

      await server.dispose();
    });

    test('double-clicking a file reuses dashboard/nofile main pane and tracks active editor pane across sync_active_file', () async {
      final server = _FakeNvimServer(cwd: workspaceDir.path);
      // Initial main pane (win 1) holds a dashboard (`buftype: nofile`, `filetype: snacks_dashboard`)
      server.validWins
        ..clear()
        ..add(1);
      server.winBufs[1] = 10;
      server.bufOptions[10] = {'buftype': 'nofile', 'filetype': 'snacks_dashboard'};
      server.currentWin = 1;

      final sidebar = WorkspaceSidebar(nvim: Nvim(server.clientSession));
      await server.serverSession.request('vibrainium_action', ['workspace.open']);
      final sidebarWin = sidebar.windowId!;

      // Expand `lib` (row 2)
      server.mousePos = {
        'winid': sidebarWin,
        'winrow': 2,
        'wincol': 4,
        'line': 2,
        'column': 4,
        'screenrow': 2,
        'screencol': 4,
      };
      await server.serverSession.request('vibrainium_action', ['workspace.double_click']);

      // Double-clicking `main.dart` (row 3) reuses win 1 instead of running `botright vsplit`
      server.commands.clear();
      server.mousePos = {
        'winid': sidebarWin,
        'winrow': 3,
        'wincol': 6,
        'line': 3,
        'column': 6,
        'screenrow': 3,
        'screencol': 6,
      };
      await server.serverSession.request('vibrainium_action', ['workspace.double_click']);
      expect(server.currentWin, 1);
      expect(server.commands.any((c) => c.contains('vsplit')), isFalse);
      expect(
        server.commands.any((c) => c.endsWith('/lib/main.dart')),
        isTrue,
      );

      // Now simulate two editor splits (win 1 and win 2) where user switches to win 2
      // and `workspace.sync_active_file` runs with an explicit file path argument,
      // followed by alternateWin pointing to a non-editor window (win 99).
      server.validWins.addAll([2, 99]);
      server.winBufs[1] = 11;
      server.bufOptions[11] = {'buftype': '', 'filetype': 'dart'};
      server.winBufs[2] = 12;
      server.bufOptions[12] = {'buftype': '', 'filetype': 'dart'};
      server.winBufs[99] = 13;
      server.bufOptions[13] = {'buftype': 'nofile', 'filetype': 'vibrainium-tabbar'};
      server.alternateWin = 1;
      server.currentWin = 2;

      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.sync_active_file', '${workspaceDir.path}/README.md'],
      );
      expect(sidebar.lastActiveEditorWin, 2);

      // Simulate focus moving through non-editor tabbar (99) to sidebarWin
      server.currentWin = 99;
      server.currentWin = sidebarWin;
      server.commands.clear();
      await server.serverSession.request('vibrainium_action', ['workspace.double_click']);

      expect(server.currentWin, 2);
      expect(server.commands.any((c) => c.contains('vsplit')), isFalse);
      expect(
        server.commands.any((c) => c.endsWith('/lib/main.dart')),
        isTrue,
      );

      // Opening and cancelling a floating modal (workspace.new_file -> workspace.prompt_close)
      // while in sidebar with a stale alternateWin (1) preserves lastActiveEditorWin == 2
      server.currentWin = sidebarWin;
      server.alternateWin = 1;
      await server.serverSession.request('vibrainium_action', ['workspace.new_file']);
      await server.serverSession.request('vibrainium_action', ['workspace.prompt_close']);
      server.commands.clear();
      await server.serverSession.request('vibrainium_action', ['workspace.double_click']);
      expect(server.currentWin, 2);
      expect(sidebar.lastActiveEditorWin, 2);

      await server.dispose();
    });

    test('supports selecting a file for compare and comparing with a second file', () async {
      final secondFile = File('${workspaceDir.path}/lib/second.dart');
      await secondFile.writeAsString('void main() { print("v2"); }\n');

      final server = _FakeNvimServer(cwd: workspaceDir.path);
      final sidebar = WorkspaceSidebar(nvim: Nvim(server.clientSession));

      await server.serverSession.request('vibrainium_action', ['workspace.open']);
      final sidebarWin = sidebar.windowId!;

      // Expand `lib` (row 2)
      server.cursors[sidebarWin] = (2, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.enter']);

      // Select `main.dart` (row 3) for compare
      server.cursors[sidebarWin] = (3, 0);
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.select_for_compare'],
      );
      expect(
        sidebar.viff.selectedCompareFilePath,
        endsWith('/lib/main.dart'),
      );

      // Compare `second.dart` (row 4) with selected `main.dart`
      server.cursors[sidebarWin] = (4, 0);
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.compare_with_selected'],
      );
      expect(sidebar.viff.activeTarget, isA<TwoFilesDiffTarget>());
      expect(sidebar.viff.hunks, isNotEmpty);

      await server.dispose();
    });

    test('supports persistent bottom search bar (/), live match expansion, cycling matches in bar and normal mode (n/N), and clearing search (<Esc>)', () async {
      await Directory('${workspaceDir.path}/pkg_a/deep').create(recursive: true);
      await Directory('${workspaceDir.path}/pkg_b/deep').create(recursive: true);
      final targetA = File('${workspaceDir.path}/pkg_a/deep/item_1.dart');
      final targetB = File('${workspaceDir.path}/pkg_b/deep/item_2.dart');
      await targetA.writeAsString('');
      await targetB.writeAsString('');

      final server = _FakeNvimServer(cwd: workspaceDir.path);
      final sidebar = WorkspaceSidebar(nvim: Nvim(server.clientSession));

      await server.serverSession.request('vibrainium_action', ['workspace.open']);
      final sidebarWin = sidebar.windowId!;

      // Persistent bottom search split is automatically created below the sidebar window
      expect(sidebar.searchPrompt.isOpen, isTrue);
      final searchBuf = sidebar.searchPrompt.bufferId!;
      final searchWin = sidebar.searchPrompt.windowId!;
      expect(server.winConfigs[searchWin]!['split'], 'below');
      expect(server.winConfigs[searchWin]!['win'], sidebarWin);
      expect(server.winConfigs[searchWin]!['height'], 1);
      expect(server.winOptions[searchWin]!['winfixheight'], isTrue);
      expect(sidebar.searchPrompt.countLabel, '');

      // Initially all top-level folders are collapsed and tree has no search rows
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '  pkg_a',
        '  pkg_b',
      ]);

      // Press `/` -> `workspace.search` focuses the persistent bottom search bar
      await server.serverSession.request('vibrainium_action', ['workspace.search']);
      expect(server.currentWin, searchWin);

      // Type regex `item_\d\.dart$` into persistent search bar buffer and fire `workspace.search_change`
      server.bufLines[searchBuf] = [r'item_\d\.dart$'];
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.search_change'],
      );

      // First match (`pkg_a/deep/item_1.dart`) is auto-expanded and selected; search bar shows `[1/2]`
      expect(sidebar.searchPrompt.countLabel, '[1/2]');
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '  pkg_a',
        '    deep',
        '       item_1.dart',
        '  pkg_b',
      ]);
      expect(server.cursors[sidebarWin], (5, 0));

      // Navigate to next match while still inside search bar (`<C-n>` -> `workspace.search_next`):
      // `pkg_a/deep` collapses back, `pkg_b/deep` expands, and cursor moves to `item_2.dart` (`[2/2]`)
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.search_next'],
      );
      expect(sidebar.searchPrompt.countLabel, '[2/2]');
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '  pkg_a',
        '  pkg_b',
        '    deep',
        '       item_2.dart',
      ]);
      expect(server.cursors[sidebarWin], (6, 0));

      // Press `<CR>` in search bar (`workspace.search_submit`): keeps persistent search bar open and focuses sidebar on current match
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.search_submit'],
      );
      expect(sidebar.searchPrompt.isOpen, isTrue);
      expect(server.validWins.contains(searchWin), isTrue);
      expect(server.currentWin, sidebarWin);
      expect(server.cursors[sidebarWin], (6, 0));

      // Press `N` in sidebar normal mode (`workspace.search_prev`): wraps back to match 1,
      // collapsing `pkg_b/deep` and expanding `pkg_a/deep`, and updates persistent search bar to `[1/2]`
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.search_prev'],
      );
      expect(sidebar.searchPrompt.countLabel, '[1/2]');
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '  pkg_a',
        '    deep',
        '       item_1.dart',
        '  pkg_b',
      ]);
      expect(server.cursors[sidebarWin], (5, 0));

      // Press `<Esc>` in sidebar normal mode (`workspace.clear_search`): clears search text & count while keeping persistent search bar open
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.clear_search'],
      );
      expect(sidebar.searchPrompt.isOpen, isTrue);
      expect(server.bufLines[searchBuf], ['']);
      expect(sidebar.searchPrompt.countLabel, '');
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '  pkg_a',
        '    deep',
        '       item_1.dart',
        '  pkg_b',
      ]);

      await server.dispose();
    });

    test('opens new_file, new_folder, and rename input dialogs in insert mode on show and exits insert mode on close/submit', () async {
      final server = _FakeNvimServer(cwd: workspaceDir.path);
      final sidebar = WorkspaceSidebar(nvim: Nvim(server.clientSession));

      await server.serverSession.request('vibrainium_action', ['workspace.open']);
      final sidebarWin = sidebar.windowId!;

      // Expand `lib` so `main.dart` is visible on row 3
      server.cursors[sidebarWin] = (2, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.enter']);

      // 1. `new_file` enters insert mode on show, does NOT bind <Esc> to close, binds 'q' in normal mode and <C-c> to close
      server.commands.clear();
      await server.serverSession.request('vibrainium_action', ['workspace.new_file']);
      expect(sidebar.inputPrompt.isOpen, isTrue);
      final newFileWin = sidebar.inputPrompt.windowId!;
      final newFileBuf = sidebar.inputPrompt.bufferId!;
      expect(server.currentWin, newFileWin);
      expect(server.commands.last, 'startinsert!');
      expect(server.winConfigs[newFileWin]!['title'], contains('q cancel'));
      expect(server.bufModeKeymaps['$newFileBuf:i:<Esc>'], isNull);
      expect(server.bufModeKeymaps['$newFileBuf:n:<Esc>'], isNull);
      expect(
        server.bufModeKeymaps['$newFileBuf:n:q'],
        "<Cmd>lua require('vibrainium').action('workspace.prompt_close')<CR>",
      );
      expect(
        server.bufModeKeymaps['$newFileBuf:i:<C-c>'],
        "<Esc><Cmd>lua require('vibrainium').action('workspace.prompt_close')<CR>",
      );
      expect(
        server.bufModeKeymaps['$newFileBuf:n:<C-c>'],
        "<Cmd>lua require('vibrainium').action('workspace.prompt_close')<CR>",
      );

      // Cancelling via normal mode 'q' (`workspace.prompt_close`) calls `stopinsert` and returns focus to sidebar
      server.commands.clear();
      await server.serverSession.request('vibrainium_action', ['workspace.prompt_close']);
      expect(sidebar.inputPrompt.isOpen, isFalse);
      expect(server.commands, contains('stopinsert'));
      expect(server.currentWin, sidebarWin);

      // 2. `new_folder` enters insert mode on show and exits insert mode on submit
      server.cursors[sidebarWin] = (1, 0);
      server.commands.clear();
      await server.serverSession.request('vibrainium_action', ['workspace.new_folder']);
      expect(sidebar.inputPrompt.isOpen, isTrue);
      expect(server.currentWin, sidebar.inputPrompt.windowId);
      expect(server.commands.last, 'startinsert!');

      server.bufLines[sidebar.inputPrompt.bufferId!] = ['assets'];
      server.commands.clear();
      await server.serverSession.request('vibrainium_action', ['workspace.prompt_submit']);
      expect(sidebar.inputPrompt.isOpen, isFalse);
      expect(server.commands, contains('stopinsert'));
      expect(await Directory('${workspaceDir.path}/assets').exists(), isTrue);

      // 3. `rename` enters insert mode on show with cursor placed at end of initial filename
      final mainRow =
          server.bufLines[1]!.indexWhere((l) => l.contains('main.dart')) + 1;
      server.cursors[sidebarWin] = (mainRow, 0);
      server.commands.clear();
      await server.serverSession.request('vibrainium_action', ['workspace.rename']);
      expect(sidebar.inputPrompt.isOpen, isTrue);
      final renameWin = sidebar.inputPrompt.windowId!;
      final renameBuf = sidebar.inputPrompt.bufferId!;
      expect(server.currentWin, renameWin);
      expect(server.bufLines[renameBuf], ['main.dart']);
      expect(server.cursors[renameWin], (1, 'main.dart'.length));
      expect(server.commands.last, 'startinsert!');

      await server.serverSession.request('vibrainium_action', ['workspace.prompt_close']);

      // 4. Triggering `New File` from right-click context menu also enters insert mode on show
      server.cursors[sidebarWin] = (mainRow, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.context_menu']);
      final newFileMenuIdx =
          sidebar.contextMenu.items.indexWhere((i) => i.label == 'New File');
      server.commands.clear();
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.menu_select:$newFileMenuIdx'],
      );
      expect(sidebar.inputPrompt.isOpen, isTrue);
      expect(server.currentWin, sidebar.inputPrompt.windowId);
      expect(server.commands.last, 'startinsert!');

      await server.dispose();
    });

    test('does not move sidebar cursor on background sync_active_file when sidebar is focused', () async {
      final deepFile = File('${workspaceDir.path}/lib/main.dart');
      final server = _FakeNvimServer(cwd: workspaceDir.path);
      server.winBufs[1] = 10;
      server.bufOptions[10] = {'buftype': '', 'filetype': 'dart'};
      server.bufNames[10] = deepFile.path;
      server.currentWin = 1;

      final sidebar = WorkspaceSidebar(nvim: Nvim(server.clientSession));
      await server.serverSession.request('vibrainium_action', ['workspace.open']);
      final sidebarWin = sidebar.windowId!;

      // Opening sidebar auto-expands `lib` and places cursor on `main.dart` (row 3)
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '     main.dart',
      ]);
      expect(server.cursors[sidebarWin], (3, 0));

      // Focus sidebar window and place cursor on header row (1)
      server.currentWin = sidebarWin;
      server.cursors[sidebarWin] = (1, 0);

      // Background sync_active_file arrives (focusSidebar: false) while sidebar is focused
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.sync_active_file', deepFile.path],
      );

      // Sidebar cursor remains at row 1, NOT yanked to row 3 (main.dart)
      expect(server.cursors[sidebarWin], (1, 0));

      // Explicit reveal (focusSidebar: true) DOES move cursor to row 3
      await server.serverSession.request(
        'vibrainium_action',
        ['workspace.reveal', deepFile.path],
      );
      expect(server.cursors[sidebarWin], (3, 0));

      await server.dispose();
    });

    test('supports two rapid single clicks acting as double-click and debounces immediate duplicate event', () async {
      final server = _FakeNvimServer(cwd: workspaceDir.path);
      final sidebar = WorkspaceSidebar(nvim: Nvim(server.clientSession));

      await server.serverSession.request('vibrainium_action', ['workspace.open']);
      final sidebarWin = sidebar.windowId!;
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
      ]);

      // 1. Two rapid single clicks on row 2 within 400ms acts as double-click and expands `lib`
      server.cursors[sidebarWin] = (2, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.click']);
      await server.serverSession.request('vibrainium_action', ['workspace.click']);
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '     main.dart',
      ]);

      // 2. An immediate duplicate `double_click` event (as sent by certain terminals right after rapid clicks) is debounced
      // so it does NOT collapse `lib` back
      await server.serverSession.request('vibrainium_action', ['workspace.double_click']);
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '     main.dart',
      ]);

      await server.dispose();
    });

    test('opens context menu reliably on cross-window right-click, empty space click, stale menu_close, and active prompt overlays', () async {
      final server = _FakeNvimServer(cwd: workspaceDir.path);
      final sidebar = WorkspaceSidebar(nvim: Nvim(server.clientSession));

      await server.serverSession.request('vibrainium_action', ['workspace.open']);
      final sidebarWin = sidebar.windowId!;

      // Expand `lib` so row 3 is `main.dart`
      server.cursors[sidebarWin] = (2, 0);
      await server.serverSession.request('vibrainium_action', ['workspace.enter']);
      expect(server.bufLines[1], [
        '❖ demo_ws',
        '  lib',
        '     main.dart',
      ]);

      // 1. Focus editor window 1 while sidebar cursor is on row 1, then right-click row 3 in Explorer
      //    using synchronous action coordinates from NvimMouseRouter (with mousePos = null).
      server.currentWin = 1;
      server.cursors[sidebarWin] = (1, 0);
      server.mousePos = null;
      await server.serverSession.request('vibrainium_action', [
        'workspace.context_menu',
        sidebarWin,
        3,
        3,
        6,
        3,
        6,
      ]);
      expect(sidebar.contextMenu.isOpen, isTrue);
      expect(server.cursors[sidebarWin], (3, 0));
      final firstMenuBuf = sidebar.contextMenu.bufferId!;

      // 2. Right-click empty area below tree lines (`line == 0, winRow == 12`) clamps to last line and reopens menu
      await server.serverSession.request('vibrainium_action', [
        'workspace.context_menu',
        sidebarWin,
        0,
        12,
        4,
        12,
        4,
      ]);
      expect(sidebar.contextMenu.isOpen, isTrue);
      expect(server.cursors[sidebarWin], (3, 0));
      final secondMenuBuf = sidebar.contextMenu.bufferId!;
      expect(secondMenuBuf, isNot(firstMenuBuf));

      // 3. Delayed WinLeave `workspace.menu_close` from `firstMenuBuf` does NOT close `secondMenuBuf`
      await server.serverSession.request('vibrainium_action', [
        'workspace.menu_close',
        firstMenuBuf,
      ]);
      expect(sidebar.contextMenu.isOpen, isTrue);

      // Matching `secondMenuBuf` DOES close it
      await server.serverSession.request('vibrainium_action', [
        'workspace.menu_close',
        secondMenuBuf,
      ]);
      expect(sidebar.contextMenu.isOpen, isFalse);

      // 4. Right-clicking Explorer while `InputPrompt` is open closes `InputPrompt` and opens `contextMenu`
      await server.serverSession.request('vibrainium_action', ['workspace.new_file']);
      expect(sidebar.inputPrompt.isOpen, isTrue);
      await server.serverSession.request('vibrainium_action', [
        'workspace.context_menu',
        sidebarWin,
        2,
        2,
        4,
        2,
        4,
      ]);
      expect(sidebar.inputPrompt.isOpen, isFalse);
      expect(sidebar.contextMenu.isOpen, isTrue);

      await server.dispose();
    });
  });
}
