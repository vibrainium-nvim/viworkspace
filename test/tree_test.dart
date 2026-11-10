import 'dart:io';

import 'package:test/test.dart';
import 'package:viworkspace/viworkspace.dart';

void main() {
  group('WorkspaceTreeState', () {
    late Directory tempRoot;
    late Directory workspaceDir;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('viworkspace_tree_test_');
      workspaceDir = Directory('${tempRoot.path}/my_project');
      await workspaceDir.create();
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('renders non-collapsible workspace header, sorts dirs before files, and hides dotfiles by default', () async {
      await Directory('${workspaceDir.path}/src').create();
      await Directory('${workspaceDir.path}/alpha').create();
      await Directory('${workspaceDir.path}/.git').create();
      await File('${workspaceDir.path}/zebra.dart').writeAsString('');
      await File('${workspaceDir.path}/app.lua').writeAsString('');
      await File('${workspaceDir.path}/.env').writeAsString('');

      final state = WorkspaceTreeState();
      final rendered = await state.build(workspaceDir);

      expect(WorkspaceIcons.chevronCollapsed, '');
      expect(WorkspaceIcons.chevronExpanded, '');
      expect(rendered.lines, [
        '❖ my_project',
        '  alpha',
        '  src',
        '   app.lua',
        '   zebra.dart',
      ]);
      expect(rendered.nodes.first, isA<WorkspaceHeaderNode>());

      // Toggle hidden files on (`.`)
      state.toggleHidden();
      final withHidden = await state.build(workspaceDir);
      expect(withHidden.lines, [
        '❖ my_project',
        '  .git',
        '  alpha',
        '  src',
        '   .env',
        '   app.lua',
        '   zebra.dart',
      ]);
    });

    test('expands and collapses directories and renders clipboard tags', () async {
      final srcDir = Directory('${workspaceDir.path}/src');
      await srcDir.create();
      final nestedFile = File('${srcDir.path}/main.dart');
      await nestedFile.writeAsString('void main() {}');

      final state = WorkspaceTreeState();
      state.toggleDir(srcDir.path);
      state.clipboard = ClipboardEntry(
        path: nestedFile.path,
        mode: ClipboardMode.cut,
      );

      final rendered = await state.build(workspaceDir);
      expect(rendered.lines, [
        '❖ my_project',
        '  src',
        '     main.dart [cut]',
      ]);
    });

    test('applies .vibrainium/settings.json workspace.exclude wildcards and toggles ignoreExclude independently of showHidden', () async {
      await Directory('${workspaceDir.path}/.vibrainium').create();
      await File('${workspaceDir.path}/.vibrainium/settings.json').writeAsString('''
{
  "workspace.exclude": [
    "build/",
    "*.g.dart",
    "lib/generated/**"
  ]
}
''');
      await Directory('${workspaceDir.path}/build').create();
      await Directory('${workspaceDir.path}/lib').create();
      await Directory('${workspaceDir.path}/lib/generated').create();
      await File('${workspaceDir.path}/lib/generated/schema.dart').writeAsString('');
      await File('${workspaceDir.path}/lib/user.dart').writeAsString('');
      await File('${workspaceDir.path}/lib/user.g.dart').writeAsString('');
      await File('${workspaceDir.path}/.hidden_file').writeAsString('');

      final state = WorkspaceTreeState();
      state.expandDir('${workspaceDir.path}/lib');

      // By default: dotfiles and workspace.exclude patterns are hidden
      final initial = await state.build(workspaceDir);
      expect(initial.lines, [
        '❖ my_project',
        '  lib',
        '     user.dart',
      ]);

      // Toggle ignoreExclude (`e`): workspace.exclude entries appear, dotfiles remain hidden
      state.toggleIgnoreExclude();
      final withExcluded = await state.build(workspaceDir);
      expect(withExcluded.lines, [
        '❖ my_project',
        '  build',
        '  lib',
        '    generated',
        '     user.dart',
        '     user.g.dart',
      ]);

      // Toggle ignoreExclude back off, and toggle showHidden (`.`): dotfiles appear, excluded entries stay hidden
      state.toggleIgnoreExclude();
      state.toggleHidden();
      final onlyHiddenShown = await state.build(workspaceDir);
      expect(onlyHiddenShown.lines, [
        '❖ my_project',
        '  .vibrainium',
        '  lib',
        '     user.dart',
        '  󰈙 .hidden_file',
      ]);
    });

    test('revealFile expands ancestor folders and highlights the active file', () async {
      await Directory('${workspaceDir.path}/lib/src/ui').create(recursive: true);
      final targetFile = File('${workspaceDir.path}/lib/src/ui/sidebar.dart');
      await targetFile.writeAsString('');

      final state = WorkspaceTreeState();
      expect(
        state.revealFile(workspaceDir.path, '/outside/other.dart'),
        isFalse,
      );
      expect(state.expandedDirs, isEmpty);

      expect(
        state.revealFile(workspaceDir.path, targetFile.path),
        isTrue,
      );
      expect(
        state.activeFilePath,
        FileOps.normalizePath(targetFile.path),
      );

      final rendered = await state.build(workspaceDir);
      expect(rendered.lines, [
        '❖ my_project',
        '  lib',
        '    src',
        '      ui',
        '         sidebar.dart',
      ]);
      expect(
        rendered.highlights.any(
          (h) => h.line == 4 && h.group == 'ViworkspaceActiveFile',
        ),
        isTrue,
      );
    });

    test('regex search expands first match, collapses auto-expanded dirs on next/prev while keeping pre-expanded dirs, and displays match index', () async {
      await Directory('${workspaceDir.path}/alpha/sub_a').create(recursive: true);
      await Directory('${workspaceDir.path}/beta/sub_b').create(recursive: true);
      await Directory('${workspaceDir.path}/gamma').create(recursive: true);

      final fileA = File('${workspaceDir.path}/alpha/sub_a/widget_test.dart');
      final fileB = File('${workspaceDir.path}/beta/sub_b/router_test.dart');
      final fileG = File('${workspaceDir.path}/gamma/keep_open.dart');
      await fileA.writeAsString('');
      await fileB.writeAsString('');
      await fileG.writeAsString('');

      final state = WorkspaceTreeState();
      // Manually expand `gamma` before starting search
      state.expandDir('${workspaceDir.path}/gamma');

      // Search with regex `.*_test\.dart$`
      final firstMatch = await state.updateSearch(workspaceDir, r'.*_test\.dart$');
      expect(firstMatch, FileOps.normalizePath(fileA.path));
      expect(state.searchMatches.length, 2);
      expect(state.currentMatchIndex, 0);

      // `alpha` and `alpha/sub_a` are auto-expanded; `beta` is still collapsed; `gamma` stays expanded
      final renderedFirst = await state.build(workspaceDir);
      expect(renderedFirst.lines, [
        '❖ my_project',
        '  alpha',
        '    sub_a',
        '       widget_test.dart',
        '  beta',
        '  gamma',
        '     keep_open.dart',
      ]);
      expect(
        renderedFirst.highlights.any(
          (h) => h.line == 3 && h.group == 'ViworkspaceSearchCurrent',
        ),
        isTrue,
      );

      // Step to next match (`[2/2]`): `alpha/sub_a` auto-collapses, `beta/sub_b` auto-expands, `gamma` stays expanded
      final secondMatch = state.stepSearchMatch(workspaceDir.path, 1);
      expect(secondMatch, FileOps.normalizePath(fileB.path));
      expect(state.currentMatchIndex, 1);

      final renderedSecond = await state.build(workspaceDir);
      expect(renderedSecond.lines, [
        '❖ my_project',
        '  alpha',
        '  beta',
        '    sub_b',
        '       router_test.dart',
        '  gamma',
        '     keep_open.dart',
      ]);

      // Step previous (`-1`) wraps back to `[1/2]` and collapses `beta/sub_b`
      final prevMatch = state.stepSearchMatch(workspaceDir.path, -1);
      expect(prevMatch, FileOps.normalizePath(fileA.path));
      expect(state.currentMatchIndex, 0);
      expect(
        state.isDirExpanded('${workspaceDir.path}/beta'),
        isFalse,
      );
      expect(
        state.isDirExpanded('${workspaceDir.path}/alpha/sub_a'),
        isTrue,
      );

      // Relative path regex when `/` is present in query and directory match support
      final dirMatch = await state.updateSearch(workspaceDir, r'^beta/sub_b$');
      expect(
        dirMatch,
        FileOps.normalizePath('${workspaceDir.path}/beta/sub_b'),
      );
      expect(state.searchMatches.length, 1);
      expect(state.isDirExpanded('${workspaceDir.path}/beta'), isTrue);
      expect(state.isDirExpanded('${workspaceDir.path}/alpha'), isFalse);

      // Incomplete regex `[` does not throw
      await state.updateSearch(workspaceDir, '[');
      expect(state.searchMatches, isEmpty);
      expect(state.currentMatchIndex, -1);
    });
  });

  group('WorkspaceIcons.iconForFile', () {
    test('maps exact filenames and dotfiles case-insensitively', () {
      expect(
        WorkspaceIcons.iconForFile('.gitignore'),
        ('', 'ViworkspaceIconGit'),
      );
      expect(
        WorkspaceIcons.iconForFile('.gitattributes'),
        ('', 'ViworkspaceIconGit'),
      );
      expect(
        WorkspaceIcons.iconForFile('Dockerfile'),
        ('󰡨', 'ViworkspaceIconDocker'),
      );
      expect(
        WorkspaceIcons.iconForFile('docker-compose.yml'),
        ('󰡨', 'ViworkspaceIconDocker'),
      );
      expect(
        WorkspaceIcons.iconForFile('Makefile'),
        ('', 'ViworkspaceIconBuild'),
      );
      expect(
        WorkspaceIcons.iconForFile('CMakeLists.txt'),
        ('', 'ViworkspaceIconBuild'),
      );
      expect(
        WorkspaceIcons.iconForFile('.env'),
        ('', 'ViworkspaceIconConfig'),
      );
      expect(
        WorkspaceIcons.iconForFile('.env.staging'),
        ('', 'ViworkspaceIconConfig'),
      );
      expect(
        WorkspaceIcons.iconForFile('LICENSE'),
        ('', 'ViworkspaceIconLicense'),
      );
      expect(
        WorkspaceIcons.iconForFile('LICENSE.md'),
        ('', 'ViworkspaceIconLicense'),
      );
      expect(
        WorkspaceIcons.iconForFile('package-lock.json'),
        ('󰌾', 'ViworkspaceMuted'),
      );
      expect(
        WorkspaceIcons.iconForFile('pubspec.yaml'),
        ('', 'ViworkspaceIconDart'),
      );
      expect(
        WorkspaceIcons.iconForFile('Cargo.toml'),
        ('', 'ViworkspaceIconRust'),
      );
      expect(
        WorkspaceIcons.iconForFile('go.mod'),
        ('', 'ViworkspaceIconGo'),
      );
      expect(
        WorkspaceIcons.iconForFile('Gemfile'),
        ('', 'ViworkspaceIconRuby'),
      );
    });

    test('maps expanded language, config, media, archive, security, and binary extensions', () {
      expect(
        WorkspaceIcons.iconForFile('Component.tsx'),
        ('', 'ViworkspaceIconWeb'),
      );
      expect(
        WorkspaceIcons.iconForFile('App.vue'),
        ('󰡄', 'ViworkspaceIconWeb'),
      );
      expect(
        WorkspaceIcons.iconForFile('styles.scss'),
        ('', 'ViworkspaceIconCss'),
      );
      expect(
        WorkspaceIcons.iconForFile('Main.kt'),
        ('', 'ViworkspaceIconJvm'),
      );
      expect(
        WorkspaceIcons.iconForFile('App.java'),
        ('', 'ViworkspaceIconJvm'),
      );
      expect(
        WorkspaceIcons.iconForFile('ViewController.swift'),
        ('', 'ViworkspaceIconC'),
      );
      expect(
        WorkspaceIcons.iconForFile('main.zig'),
        ('', 'ViworkspaceIconC'),
      );
      expect(
        WorkspaceIcons.iconForFile('server.ex'),
        ('', 'ViworkspaceIconRuby'),
      );
      expect(
        WorkspaceIcons.iconForFile('Parser.hs'),
        ('', 'ViworkspaceIconLua'),
      );
      expect(
        WorkspaceIcons.iconForFile('query.sql'),
        ('', 'ViworkspaceIconData'),
      );
      expect(
        WorkspaceIcons.iconForFile('schema.prisma'),
        ('', 'ViworkspaceIconData'),
      );
      expect(
        WorkspaceIcons.iconForFile('flake.nix'),
        ('', 'ViworkspaceIconConfig'),
      );
      expect(
        WorkspaceIcons.iconForFile('main.tf'),
        ('', 'ViworkspaceIconConfig'),
      );
      expect(
        WorkspaceIcons.iconForFile('manual.pdf'),
        ('', 'ViworkspaceIconDocs'),
      );
      expect(
        WorkspaceIcons.iconForFile('logo.svg'),
        ('󰜡', 'ViworkspaceIconMedia'),
      );
      expect(
        WorkspaceIcons.iconForFile('banner.png'),
        ('', 'ViworkspaceIconMedia'),
      );
      expect(
        WorkspaceIcons.iconForFile('theme.mp3'),
        ('', 'ViworkspaceIconMedia'),
      );
      expect(
        WorkspaceIcons.iconForFile('demo.mp4'),
        ('', 'ViworkspaceIconMedia'),
      );
      expect(
        WorkspaceIcons.iconForFile('JetBrainsMono.ttf'),
        ('', 'ViworkspaceIconMedia'),
      );
      expect(
        WorkspaceIcons.iconForFile('release.tar.gz'),
        ('', 'ViworkspaceIconArchive'),
      );
      expect(
        WorkspaceIcons.iconForFile('id_ed25519.pem'),
        ('󰌆', 'ViworkspaceIconSecurity'),
      );
      expect(
        WorkspaceIcons.iconForFile('libfoo.dylib'),
        ('', 'ViworkspaceIconBinary'),
      );
      expect(
        WorkspaceIcons.iconForFile('changes.patch'),
        ('', 'ViworkspaceIconGit'),
      );
      expect(
        WorkspaceIcons.iconForFile('unknown.customext'),
        (WorkspaceIcons.defaultFile, 'ViworkspaceIconDefault'),
      );
    });
  });
}
