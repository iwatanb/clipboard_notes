import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
// path_provider import removed; handled by caller
import 'package:provider/provider.dart';
import 'memo_store.dart';

class MemoPage extends StatefulWidget {
  final String filePath;
  const MemoPage({super.key, required this.filePath});

  @override
  State<MemoPage> createState() => _MemoPageState();
}

class _MemoPageState extends State<MemoPage> {
  late final TextEditingController _controller;
  List<String> _lines = [];
  List<String> _paragraphs = [];
  final Map<int, TextEditingController> _lineCtrls = {};
  final Map<int, TextEditingController> _paraCtrls = {};

  // storage
  late File _memoFile;
  Timer? _saveTimer;

  // Flag to prevent recursive updates between whole-text and per-line edits
  bool _suppressTextListener = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onTextChanged);

    _initStorage();
  }

  Future<void> _initStorage() async {
    _memoFile = File(widget.filePath);
    if (await _memoFile.exists()) {
      final text = await _memoFile.readAsString();
      if (text.isNotEmpty) {
        _setWholeText(text);
      }
    }
  }

  void _onTextChanged() {
    if (_suppressTextListener) return;
    _refreshViews();
  }

  void _refreshViews() {
    setState(() {
      _lines = _controller.text.split('\n');
      _paragraphs = _controller.text.split(RegExp(r'\n{2,}'));
      _syncLineControllers();
      _syncParagraphControllers();
    });
  }

  void _syncLineControllers() {
    // Ensure controllers for each line exist and contain correct text
    for (var i = 0; i < _lines.length; i++) {
      final lineText = _lines[i];
      if (!_lineCtrls.containsKey(i)) {
        _lineCtrls[i] = TextEditingController(text: lineText);
        _lineCtrls[i]!.addListener(() => _onLineChanged(i));
      } else {
        final ctrl = _lineCtrls[i]!;
        if (ctrl.text != lineText) {
          ctrl.text = lineText;
        }
      }
    }
    // Dispose controllers no longer needed
    _lineCtrls.keys.where((k) => k >= _lines.length).toList().forEach((k) {
      _lineCtrls[k]!.dispose();
      _lineCtrls.remove(k);
    });
  }

  void _syncParagraphControllers() {
    for (var i = 0; i < _paragraphs.length; i++) {
      final text = _paragraphs[i];
      if (!_paraCtrls.containsKey(i)) {
        _paraCtrls[i] = TextEditingController(text: text);
        _paraCtrls[i]!.addListener(() => _onParagraphChanged(i));
      } else {
        final ctrl = _paraCtrls[i]!;
        if (ctrl.text != text) ctrl.text = text;
      }
    }
    _paraCtrls.keys.where((k) => k >= _paragraphs.length).toList().forEach((k) {
      _paraCtrls[k]!.dispose();
      _paraCtrls.remove(k);
    });
  }

  void _onParagraphChanged(int index) {
    if (index >= _paragraphs.length) return;
    _paragraphs[index] = _paraCtrls[index]!.text;
    _setWholeText(_paragraphs.join('\n\n'));
  }

  void _setWholeText(String text) {
    _suppressTextListener = true;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _suppressTextListener = false;
    _refreshViews();

    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveToFile);
  }

  void _saveToFile() {
    final store = context.read<MemoStore>();
    store.writeMemo(widget.filePath, _controller.text);
  }

  void _onLineChanged(int index) {
    if (index >= _lines.length) return;
    _lines[index] = _lineCtrls[index]!.text;
    _setWholeText(_lines.join('\n'));
  }

  @override
  void dispose() {
    _controller.dispose();
    _saveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Memo'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.notes), text: 'All'),
              Tab(icon: Icon(Icons.list), text: 'Lines'),
              Tab(icon: Icon(Icons.article), text: 'Paragraph'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // --- All Tab ---
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter your notes here...',
                ),
              ),
            ),
            // --- Lines Tab ---
            ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _lines.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final line = _lines.removeAt(oldIndex);
                  _lines.insert(newIndex, line);
                  _setWholeText(_lines.join('\n'));
                });
              },
              itemBuilder: (context, index) {
                return Padding(
                  key: ValueKey('line_$index'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Editable line field
                      Expanded(
                        child: TextField(
                          controller: _lineCtrls[index],
                          minLines: 1,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_copy),
                        tooltip: 'Copy',
                        onPressed: () => _copyLine(index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_cut),
                        tooltip: 'Cut',
                        onPressed: () => _cutLine(index),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      ),
                    ],
                  ),
                );
              },
            ),

            // --- Paragraph Tab ---
            ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _paragraphs.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final p = _paragraphs.removeAt(oldIndex);
                  _paragraphs.insert(newIndex, p);
                  _setWholeText(_paragraphs.join('\n\n'));
                });
              },
              itemBuilder: (context, index) {
                return Padding(
                  key: ValueKey('para_$index'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _paraCtrls[index],
                          minLines: 2,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_copy),
                        tooltip: 'Copy',
                        onPressed: () => _copyParagraph(index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_cut),
                        tooltip: 'Cut',
                        onPressed: () => _cutParagraph(index),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyLine(int index) async {
    final text = _lines[index];
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Line copied')));
  }

  Future<void> _copyParagraph(int index) async {
    final text = _paragraphs[index];
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Paragraph copied')));
  }

  Future<void> _cutLine(int index) async {
    await _copyLine(index);
    setState(() {
      _lines.removeAt(index);
      _setWholeText(_lines.join('\n'));
    });
  }

  Future<void> _cutParagraph(int index) async {
    await _copyParagraph(index);
    setState(() {
      _paragraphs.removeAt(index);
      _setWholeText(_paragraphs.join('\n\n'));
    });
  }

  // _pasteAfter removed due to design change
}
