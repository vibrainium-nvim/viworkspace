import 'dart:io';

import 'package:test/test.dart';
import 'package:viworkspace/viworkspace.dart';

void main() {
  group('FileOps', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('viworkspace_ops_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates files, folders, renames, and deletes', () async {
      final createdFile = await FileOps.createFile(tempDir.path, 'hello.dart');
      expect(await File(createdFile).exists(), isTrue);

      final createdFolder = await FileOps.createFolder(tempDir.path, 'sub/nested');
      expect(await Directory(createdFolder).exists(), isTrue);

      final renamedFile = await FileOps.rename(createdFile, 'world.dart');
      expect(await File(createdFile).exists(), isFalse);
      expect(await File(renamedFile).exists(), isTrue);

      await FileOps.delete(renamedFile);
      expect(await File(renamedFile).exists(), isFalse);

      await FileOps.delete('${tempDir.path}/sub');
      expect(await Directory('${tempDir.path}/sub').exists(), isFalse);
    });

    test('copies and cuts files and directories, resolving same-folder copy collisions', () async {
      final srcFile = await FileOps.createFile(tempDir.path, 'note.md');
      await File(srcFile).writeAsString('# Title');

      final copySameDir = await FileOps.paste(
        ClipboardEntry(path: srcFile, mode: ClipboardMode.copy),
        tempDir.path,
      );
      expect(FileOps.basename(copySameDir), 'note_copy.md');
      expect(await File(copySameDir).readAsString(), '# Title');

      final destDir = await FileOps.createFolder(tempDir.path, 'archive');
      final movedPath = await FileOps.paste(
        ClipboardEntry(path: copySameDir, mode: ClipboardMode.cut),
        destDir,
      );
      expect(await File(copySameDir).exists(), isFalse);
      expect(await File(movedPath).exists(), isTrue);
      expect(await File(movedPath).readAsString(), '# Title');
    });

    test('duplicates files and directories with non-colliding names', () async {
      final srcFile = await FileOps.createFile(tempDir.path, 'data.json');
      await File(srcFile).writeAsString('{"key": 1}');

      final dup1 = await FileOps.duplicate(srcFile);
      expect(FileOps.basename(dup1), 'data_copy.json');
      expect(await File(dup1).exists(), isTrue);
      expect(await File(dup1).readAsString(), '{"key": 1}');

      final dup2 = await FileOps.duplicate(srcFile);
      expect(FileOps.basename(dup2), 'data_copy2.json');
      expect(await File(dup2).exists(), isTrue);

      final srcDir = await FileOps.createFolder(tempDir.path, 'pkg');
      await FileOps.createFile(srcDir, 'index.dart');
      final dupDir = await FileOps.duplicate(srcDir);
      expect(FileOps.basename(dupDir), 'pkg_copy');
      expect(await Directory(dupDir).exists(), isTrue);
      expect(await File('$dupDir/index.dart').exists(), isTrue);
    });

    test('computes relativePath from workspace root', () {
      expect(
        FileOps.relativePath('/workspace/project', '/workspace/project/lib/src/main.dart'),
        'lib/src/main.dart',
      );
      expect(
        FileOps.relativePath('/workspace/project/', '/workspace/project/lib'),
        'lib',
      );
      expect(
        FileOps.relativePath('/workspace/project', '/workspace/project'),
        '.',
      );
    });

    test('openExternal and revealInFinder invoke OS launcher and reject missing paths', () async {
      final createdFile = await FileOps.createFile(tempDir.path, 'doc.pdf');
      final calls = <(String, List<String>)>[];

      Future<ProcessResult> fakeRunner(String exe, List<String> args) async {
        calls.add((exe, args));
        return ProcessResult(1, 0, '', '');
      }

      await FileOps.openExternal(createdFile, runProcess: fakeRunner);
      expect(calls, hasLength(1));
      if (Platform.isMacOS) {
        expect(calls.last.$1, 'open');
        expect(calls.last.$2, [FileOps.normalizePath(createdFile)]);
      }

      await FileOps.revealInFinder(createdFile, runProcess: fakeRunner);
      expect(calls, hasLength(2));
      if (Platform.isMacOS) {
        expect(calls.last.$1, 'open');
        expect(calls.last.$2, ['-R', FileOps.normalizePath(createdFile)]);
      }

      expect(
        () => FileOps.openExternal('${tempDir.path}/missing.txt', runProcess: fakeRunner),
        throwsStateError,
      );
      expect(
        () => FileOps.revealInFinder('${tempDir.path}/missing.txt', runProcess: fakeRunner),
        throwsStateError,
      );
    });
  });
}
