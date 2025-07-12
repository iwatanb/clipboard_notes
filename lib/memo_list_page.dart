import 'dart:io';
import 'package:flutter/material.dart';
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
        onPressed: _createNewMemo,
        tooltip: 'New Memo',
        child: const Icon(Icons.add),
      ),
    );
  }
}
