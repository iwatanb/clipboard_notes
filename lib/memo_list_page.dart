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
    return file.uri.pathSegments.last;
  }

  @override
  Widget build(BuildContext context) {
    final files = context.watch<MemoStore>().files;

    return Scaffold(
      appBar: AppBar(title: const Text('Memos')),
      body: ListView.builder(
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index] as File;
          return ListTile(
            title: Text(_displayName(file)),
            subtitle: Text(file.uri.pathSegments.last),
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
