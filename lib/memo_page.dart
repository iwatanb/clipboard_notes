import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MemoPage extends StatefulWidget {
  const MemoPage({super.key});

  @override
  State<MemoPage> createState() => _MemoPageState();
}

class _MemoPageState extends State<MemoPage> {
  late final TextEditingController _controller;
  List<String> _lines = [];
  final Map<int, TextEditingController> _lineCtrls = {};

  // Flag to prevent recursive updates between whole-text and per-line edits
  bool _suppressTextListener = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_suppressTextListener) return;
    _refreshLines();
  }

  void _refreshLines() {
    setState(() {
      _lines = _controller.text.split('\n');
      _syncLineControllers();
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

  void _onLineChanged(int index) {
    if (index >= _lines.length) return;
    _lines[index] = _lineCtrls[index]!.text;
    _updateWholeText();
  }

  void _updateWholeText() {
    _suppressTextListener = true;
    _controller.text = _lines.join('\n');
    // keep cursor at end for simplicity
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _suppressTextListener = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Memo'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.notes), text: 'All'),
              Tab(icon: Icon(Icons.list), text: 'Lines'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // --- Edit Tab ---
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
            ListView.builder(
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                return Padding(
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
                      IconButton(
                        icon: const Icon(Icons.content_paste),
                        tooltip: 'Paste',
                        onPressed: () => _pasteAfter(index),
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

  Future<void> _cutLine(int index) async {
    await _copyLine(index);
    setState(() {
      _lines.removeAt(index);
      _updateWholeText();
      _syncLineControllers();
    });
  }

  Future<void> _pasteAfter(int index) async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text == null || data!.text!.isEmpty) return;
    setState(() {
      _lines.insert(index + 1, data.text!);
      _updateWholeText();
      _syncLineControllers();
    });
  }
}
