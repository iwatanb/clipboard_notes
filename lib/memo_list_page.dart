import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'memo_page.dart';
import 'memo_store.dart';

class MemoListPage extends StatefulWidget {
  const MemoListPage({super.key});

  @override
  State<MemoListPage> createState() => _MemoListPageState();
}

class _MemoListPageState extends State<MemoListPage> {
  void _openMemo(String path) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MemoPage(filePath: path)));
  }

  Future<void> _createNewMemo() async {
    final store = context.read<MemoStore>();
    final path = await store.createMemo();
    if (!mounted) return;
    _openMemo(path);
  }

  void _showLoadingDialog(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickTextFileContent() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.single;
    var loadingShown = false;
    try {
      if (!mounted) return null;
      _showLoadingDialog('読み込み中...');
      loadingShown = true;
      if (picked.path != null) {
        return await File(picked.path!).readAsString();
      }
      if (picked.bytes != null) {
        return utf8.decode(picked.bytes!, allowMalformed: true);
      }
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ファイルの読み込みに失敗しました')),
      );
      return null;
    } finally {
      if (loadingShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
    return null;
  }

  Future<void> _showCreateMemoOptions() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.note_add),
                title: const Text('新しい空のメモを作成'),
                onTap: () => Navigator.pop(context, 'new'),
              ),
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: const Text('テキストファイルからインポート'),
                onTap: () => Navigator.pop(context, 'import'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted) return;

    if (result == 'new') {
      await _createNewMemo();
    } else if (result == 'import') {
      final content = await _pickTextFileContent();
      if (!mounted) return;
      if (content == null) return;
      try {
        final store = context.read<MemoStore>();
        final path = await store.createMemoFromFile(content);
        if (!mounted) return;
        _openMemo(path);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('インポートに失敗しました')),
        );
      }
    }
  }

  String _displayName(File file) {
    try {
      final firstLine = file.readAsLinesSync().firstWhere(
        (l) => l.trim().isNotEmpty,
        orElse: () => '',
      );
      if (firstLine.isNotEmpty) {
        return firstLine.length > 30
            ? '${firstLine.substring(0, 30)}…'
            : firstLine;
      }
    } catch (_) {}
    final base = file.uri.pathSegments.last;
    return base.endsWith('.txt')
        ? base.replaceAll(RegExp(r'\.txt$'), '')
        : base;
  }

  @override
  Widget build(BuildContext context) {
    final files = context.watch<MemoStore>().files;

    return Scaffold(
      appBar: AppBar(title: const Text('Memos')),
      body: ListView.builder(
        itemCount: files.length,
        itemBuilder: (context, index) {
          final File file = files[index];
          final preview = _displayName(file);
          final baseName = file.uri.pathSegments.last.replaceAll(
            RegExp(r'\.txt$'),
            '',
          );
          return Dismissible(
            key: ValueKey(file.path),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Memo'),
                      content: const Text(
                        'Are you sure you want to delete this memo?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            },
            onDismissed: (_) async {
              await context.read<MemoStore>().deleteMemo(file.path);
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Memo deleted')));
              }
            },
            child: ListTile(
              title: Text(preview),
              subtitle: Text(baseName),
              onTap: () => _openMemo(file.path),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateMemoOptions,
        tooltip: 'New Memo',
        child: const Icon(Icons.add),
      ),
    );
  }
}
