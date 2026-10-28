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
  });
}
