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

  Future<bool> _confirmDelete() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Memo'),
            content: const Text('Are you sure you want to delete this memo?'),
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
  }

  Future<void> _deleteMemo(String path) async {
    await context.read<MemoStore>().deleteMemo(path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memo deleted')),
      );
    }
  }

  Future<void> _renameMemo({
    required String path,
    required String currentBaseName,
  }) async {
    final controller = TextEditingController(text: currentBaseName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Memo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'New name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final trimmed = newName?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final baseName = trimmed.endsWith('.txt') ? trimmed : '$trimmed.txt';
    final newPath = await context.read<MemoStore>().renameMemo(path, baseName);
    if (!mounted) return;
    if (newPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rename failed')),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final files = context.watch<MemoStore>().files;

    return Scaffold(
      appBar: AppBar(title: const Text('Memos')),
      body: SafeArea(
        bottom: true,
        child: ListView.builder(
          itemCount: files.length,
          itemBuilder: (context, index) {
            final File file = files[index];
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
              confirmDismiss: (_) => _confirmDelete(),
              onDismissed: (_) async => _deleteMemo(file.path),
              child: ListTile(
                title: Text(baseName),
                onTap: () => _openMemo(file.path),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'rename') {
                      await _renameMemo(
                        path: file.path,
                        currentBaseName: baseName,
                      );
                    } else if (value == 'delete') {
                      final confirmed = await _confirmDelete();
                      if (!confirmed) return;
                      await _deleteMemo(file.path);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text('名前変更'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('削除'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateMemoOptions,
        tooltip: 'New Memo',
        child: const Icon(Icons.add),
      ),
    );
  }
}
