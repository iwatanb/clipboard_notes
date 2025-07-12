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
          return ListTile(
            title: Text(preview),
            subtitle: Text(baseName),
            onTap: () => _openMemo(file.path),
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
