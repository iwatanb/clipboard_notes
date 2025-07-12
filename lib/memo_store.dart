import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class MemoStore extends ChangeNotifier {
  late final Directory _docDir;
  final List<File> _files = [];

  List<File> get files => List.unmodifiable(_files);

  MemoStore() {
    _init();
  }

  Future<void> _init() async {
    _docDir = await getApplicationDocumentsDirectory();
    _refreshFiles();
  }

  void _refreshFiles() {
    _files
      ..clear()
      ..addAll(
        _docDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.txt'))
            .toList()
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          ),
      );
    notifyListeners();
  }

  Future<String> createMemo() async {
    final path =
        '${_docDir.path}/memo_${DateTime.now().millisecondsSinceEpoch}.txt';
    final file = File(path);
    await file.writeAsString('');
    _refreshFiles();
    return path;
  }

  Future<String> readMemo(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return file.readAsString();
    }
    return '';
  }

  Future<void> writeMemo(String path, String text) async {
    final file = File(path);
    await file.writeAsString(text);
    _refreshFiles(); // first line might have changed
  }

  Future<void> deleteMemo(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      _refreshFiles();
    }
  }

  Future<String?> renameMemo(String oldPath, String newBaseName) async {
    final oldFile = File(oldPath);
    if (!await oldFile.exists()) return null;
    final newPath = '${oldFile.parent.path}/$newBaseName';
    if (await File(newPath).exists()) return null; // duplicate
    final newFile = await oldFile.rename(newPath);
    _refreshFiles();
    return newFile.path;
  }
}
