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

class _MemoPageState extends State<MemoPage>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late String _path;
  List<String> _lines = [];
  List<String> _paragraphs = [];
  final Map<int, TextEditingController> _lineCtrls = {};
  final Map<int, TextEditingController> _paraCtrls = {};
  // Dedicated TabController managed by this State
  late final TabController _tabController;

  // storage
  late File _memoFile;
  Timer? _saveTimer;

  // Flag to prevent recursive updates between whole-text and per-line edits
  bool _suppressTextListener = false;
  // Flag to avoid reacting to controller edits during bulk sync
  bool _suppressItemListener = false;
  // Toggle for delete mode (when true shows delete buttons instead of copy)
  bool _deleteMode = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _path = widget.filePath;
    _controller.addListener(_onTextChanged);

    // Initialize TabController and listener
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);

    _initStorage();
  }

  Future<void> _initStorage() async {
    _memoFile = File(_path);
    if (await _memoFile.exists()) {
      final text = await _memoFile.readAsString();
      if (text.isNotEmpty) {
        _setWholeText(text);
      }
    }
  }

  // Called when tab index changes
  void _onTabChanged() {
    // Wait until the animation completes
    if (_tabController.indexIsChanging) return;

    // When user switches *to* Line(1) or Paragraph(2) tab, refresh the split views
    if (_tabController.index == 1 || _tabController.index == 2) {
      _refreshViews();
    }
    // Rebuild to update AppBar contents based on current tab
    setState(() {});
  }

  void _onTextChanged() {
    debugPrint(
      'onTextChanged tab=${_tabController.index} len=${_controller.text.length}',
    );
    if (_suppressTextListener) return;

    // Only rebuild Line / Paragraph views when those tabs are active.
    if (_tabController.index != 0) {
      _refreshViews();
    }

    // Always schedule save regardless of current tab
    _scheduleSave();
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
    _suppressItemListener = true;
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
    final removed = _lineCtrls.keys.where((k) => k >= _lines.length).toList();
    for (final k in removed) {
      final ctrl = _lineCtrls[k]!;
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
      _lineCtrls.remove(k);
    }
    _suppressItemListener = false;
  }

  void _syncParagraphControllers() {
    _suppressItemListener = true;
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
    final removed = _paraCtrls.keys
        .where((k) => k >= _paragraphs.length)
        .toList();
    for (final k in removed) {
      final ctrl = _paraCtrls[k]!;
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
      _paraCtrls.remove(k);
    }
    _suppressItemListener = false;
  }

  void _onParagraphChanged(int index) {
    if (_suppressItemListener) return;
    if (index >= _paragraphs.length) return;
    _paragraphs[index] = _paraCtrls[index]!.text;
    _setWholeText(_paragraphs.join('\n\n'));
  }

  void _setWholeText(String text) {
    debugPrint('setWholeText triggered len=${text.length}');
    final prevSelection = _controller.selection;
    final int prevOffset = prevSelection.baseOffset;

    _suppressTextListener = true;
    _controller.text = text;

    // Restore cursor position if it was valid
    if (prevOffset >= 0 && prevOffset <= _controller.text.length) {
      _controller.selection = TextSelection.collapsed(offset: prevOffset);
    } else {
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }

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
    store.writeMemo(_path, _controller.text);
  }

  void _onLineChanged(int index) {
    if (_suppressItemListener) return;
    if (index >= _lines.length) return;
    _lines[index] = _lineCtrls[index]!.text;
    _setWholeText(_lines.join('\n'));
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _controller.dispose();
    _saveTimer?.cancel();
    super.dispose();
  }

  String get _fileName {
    final base = File(_path).uri.pathSegments.last;
    return base.endsWith('.txt')
        ? base.replaceAll(RegExp(r'\.txt$'), '')
        : base;
  }

  Future<void> _renameFile() async {
    final TextEditingController nameCtrl = TextEditingController(
      text: _fileName,
    );
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename memo'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter new file name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, nameCtrl.text.trim()),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
    if (result == null || result.isEmpty) return;
    final store = context.read<MemoStore>();
    final newPath = await store.renameMemo(
      _path,
      '${result.replaceAll(RegExp(r'\.txt$'), '')}.txt',
    );
    if (newPath != null) {
      setState(() {
        _path = newPath;
        _memoFile = File(newPath);
      });
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rename failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _tabController.index == 0 ? Text(_fileName) : null,
        actions: [
          if (_tabController.index == 0)
            IconButton(onPressed: _renameFile, icon: const Icon(Icons.edit)),
          if (_tabController.index != 0)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('mode', style: TextStyle(fontSize: 14)),
                    SizedBox(width: 4),
                    Icon(Icons.autorenew, size: 16),
                  ],
                ),
              ),
              tooltip: 'Toggle mode',
              onPressed: () {
                setState(() {
                  _deleteMode = !_deleteMode;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _deleteMode ? 'Delete mode ON' : 'Delete mode OFF',
                    ),
                    duration: const Duration(milliseconds: 800),
                  ),
                );
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.notes), text: 'All'),
            Tab(icon: Icon(Icons.list), text: 'Line'),
            Tab(icon: Icon(Icons.article), text: 'Paragraph'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
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
              style: const TextStyle(fontSize: 14),
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
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _setWholeText(_lines.join('\n'));
                });
              });
            },
            itemBuilder: (context, index) {
              return Padding(
                key: ValueKey('line_$index'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Number label + drag handle column (fixed width)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ReorderableDragStartListener(
                        index: index,
                        child: SizedBox(
                          width: 48,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${index + 1}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const Icon(Icons.drag_handle_rounded, size: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Editable line field
                    Expanded(
                      child: TextField(
                        controller: _lineCtrls[index],
                        minLines: 1,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(fontSize: 14),
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
                      icon: Icon(
                        _deleteMode ? Icons.delete : Icons.content_copy,
                      ),
                      color: _deleteMode ? Colors.red : null,
                      tooltip: _deleteMode ? 'Delete' : 'Copy',
                      onPressed: _deleteMode
                          ? () => _confirmDeleteLine(index)
                          : () => _copyLine(index),
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
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _setWholeText(_paragraphs.join('\n\n'));
                });
              });
            },
            itemBuilder: (context, index) {
              return Padding(
                key: ValueKey('para_$index'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Number label + drag handle column (fixed width)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ReorderableDragStartListener(
                        index: index,
                        child: SizedBox(
                          width: 48,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${index + 1}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const Icon(Icons.drag_handle_rounded, size: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _paraCtrls[index],
                        minLines: 2,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(fontSize: 14),
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
                      icon: Icon(
                        _deleteMode ? Icons.delete : Icons.content_copy,
                      ),
                      color: _deleteMode ? Colors.red : null,
                      tooltip: _deleteMode ? 'Delete' : 'Copy',
                      onPressed: _deleteMode
                          ? () => _confirmDeleteParagraph(index)
                          : () => _copyParagraph(index),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
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

  Future<void> _confirmDeleteLine(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete line'),
        content: const Text('Are you sure you want to delete this line?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _lines.removeAt(index);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setWholeText(_lines.join('\n'));
      });
    }
  }

  Future<void> _confirmDeleteParagraph(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete paragraph'),
        content: const Text('Are you sure you want to delete this paragraph?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _paragraphs.removeAt(index);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setWholeText(_paragraphs.join('\n\n'));
      });
    }
  }

  // Cut functions removed as delete via swipe is preferred.
}
