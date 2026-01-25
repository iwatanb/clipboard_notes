import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
// path_provider import removed; handled by caller
import 'package:provider/provider.dart';
import 'memo_store.dart';
import 'visual_whitespace_textfield.dart';

enum ItemMode { copy, delete, fold }

class MemoPage extends StatefulWidget {
  final String filePath;
  const MemoPage({super.key, required this.filePath});

  @override
  State<MemoPage> createState() => _MemoPageState();
}

class _MemoPageState extends State<MemoPage>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final GlobalKey<VisualWhitespaceTextFieldState> _editorKey =
      GlobalKey<VisualWhitespaceTextFieldState>();
  late String _path;
  List<String> _lines = [];
  List<String> _paragraphs = [];
  List<String> _sections = [];
  final Map<int, TextEditingController> _lineCtrls = {};
  final Map<int, TextEditingController> _paraCtrls = {};
  final Map<int, TextEditingController> _sectionCtrls = {};
  final Map<int, FocusNode> _lineFocusNodes = {};
  final Map<int, FocusNode> _paraFocusNodes = {};
  final Map<int, FocusNode> _sectionFocusNodes = {};
  String _lastText = '';
  // Dedicated TabController managed by this State
  late final TabController _tabController;

  // storage
  late File _memoFile;
  Timer? _saveTimer;

  // Flag to prevent recursive updates between whole-text and per-line edits
  bool _suppressTextListener = false;
  // Flag to avoid reacting to controller edits during bulk sync
  bool _suppressItemListener = false;
  // mode toggle: copy -> delete -> fold
  ItemMode _itemMode = ItemMode.copy;
  // Per-item folded state
  List<bool> _lineFolded = [];
  List<bool> _paragraphFolded = [];
  List<bool> _sectionFolded = [];
  // Search UI state
  bool _isSearchMode = false;
  final List<TextRange> _searchMatches = [];
  int _currentMatchIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _lastText = _controller.text;
    _path = widget.filePath;
    _controller.addListener(_onTextChanged);
    _searchController.addListener(_onSearchChanged);

    // Initialize TabController and listener
    _tabController = TabController(length: 4, vsync: this);
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

    // When user switches *to* Line(1) / Paragraph(2) / Section(3) tab, refresh the split views
    if (_tabController.index == 1 ||
        _tabController.index == 2 ||
        _tabController.index == 3) {
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
    final currentText = _controller.text;
    if (currentText == _lastText) return;
    _lastText = currentText;

    // Only rebuild Line / Paragraph views when those tabs are active.
    if (_tabController.index != 0) {
      _refreshViews();
    }

    // Always schedule save regardless of current tab
    _scheduleSave();

    if (_isSearchMode && _searchController.text.isNotEmpty) {
      _updateSearchMatches(_searchController.text);
    }
  }

  void _onSearchChanged() {
    if (!_isSearchMode) return;
    _updateSearchMatches(_searchController.text);
  }

  void _updateSearchMatches(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchMatches.clear();
        _currentMatchIndex = -1;
      });
      return;
    }

    final text = _controller.text;
    final matches = <TextRange>[];
    var startIndex = 0;
    while (startIndex < text.length) {
      final index = text.indexOf(trimmed, startIndex);
      if (index == -1) break;
      matches.add(TextRange(start: index, end: index + trimmed.length));
      startIndex = index + trimmed.length;
    }

    setState(() {
      _searchMatches
        ..clear()
        ..addAll(matches);
      _currentMatchIndex = matches.isEmpty ? -1 : 0;
    });
    _scrollToCurrentMatch();
  }

  void _selectMatch(int index) {
    if (_searchMatches.isEmpty) return;
    final count = _searchMatches.length;
    final wrapped = ((index % count) + count) % count;
    setState(() {
      _currentMatchIndex = wrapped;
    });
    final range = _searchMatches[wrapped];
    _controller.selection = TextSelection(
      baseOffset: range.start,
      extentOffset: range.end,
    );
    _scrollToCurrentMatch();
  }

  void _scrollToCurrentMatch() {
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _searchMatches.length) {
      return;
    }
    final range = _searchMatches[_currentMatchIndex];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editorKey.currentState?.scrollToRange(range);
    });
  }

  void _refreshViews() {
    setState(() {
      _lines = _controller.text.split('\n');
      _paragraphs = _controller.text.split(RegExp(r'\n{2,}'));
      _sections = _controller.text.split(RegExp(r'\n{3,}'));
      _syncLineControllers();
      _syncParagraphControllers();
      _syncSectionControllers();
      _syncFoldStates();
    });
  }

  void _syncFoldStates() {
    _lineFolded = _resizeBoolList(_lineFolded, _lines.length);
    _paragraphFolded = _resizeBoolList(_paragraphFolded, _paragraphs.length);
    _sectionFolded = _resizeBoolList(_sectionFolded, _sections.length);
  }

  List<bool> _resizeBoolList(List<bool> current, int length) {
    // create growable list to allow remove/insert during reorder
    final newList = List<bool>.filled(length, false, growable: true);
    final copyLen = math.min(current.length, length);
    for (var i = 0; i < copyLen; i++) {
      newList[i] = current[i];
    }
    return newList;
  }

  String _modeLabel(ItemMode mode) {
    switch (mode) {
      case ItemMode.copy:
        return 'Copy';
      case ItemMode.delete:
        return 'Delete';
      case ItemMode.fold:
        return 'Fold';
    }
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
      _lineFocusNodes.putIfAbsent(i, FocusNode.new);
      final index = i;
      _lineFocusNodes[index]!.onKeyEvent = (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace) {
          if (_handleLineBackspaceAtStart(index)) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      };
    }
    // Dispose controllers and focus nodes no longer needed
    final removed = _lineCtrls.keys.where((k) => k >= _lines.length).toList();
    for (final k in removed) {
      final ctrl = _lineCtrls[k]!;
      final focus = _lineFocusNodes[k];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ctrl.dispose();
        focus?.dispose();
      });
      _lineCtrls.remove(k);
      _lineFocusNodes.remove(k);
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
      _paraFocusNodes.putIfAbsent(i, FocusNode.new);
      final index = i;
      _paraFocusNodes[index]!.onKeyEvent = (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace) {
          if (_handleParagraphBackspaceAtStart(index)) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      };
    }
    final removed = _paraCtrls.keys
        .where((k) => k >= _paragraphs.length)
        .toList();
    for (final k in removed) {
      final ctrl = _paraCtrls[k]!;
      final focus = _paraFocusNodes[k];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ctrl.dispose();
        focus?.dispose();
      });
      _paraCtrls.remove(k);
      _paraFocusNodes.remove(k);
    }
    _suppressItemListener = false;
  }

  void _syncSectionControllers() {
    _suppressItemListener = true;
    for (var i = 0; i < _sections.length; i++) {
      final text = _sections[i];
      if (!_sectionCtrls.containsKey(i)) {
        _sectionCtrls[i] = TextEditingController(text: text);
        _sectionCtrls[i]!.addListener(() => _onSectionChanged(i));
      } else {
        final ctrl = _sectionCtrls[i]!;
        if (ctrl.text != text) ctrl.text = text;
      }
      _sectionFocusNodes.putIfAbsent(i, FocusNode.new);
      final index = i;
      _sectionFocusNodes[index]!.onKeyEvent = (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace) {
          if (_handleSectionBackspaceAtStart(index)) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      };
    }
    final removed = _sectionCtrls.keys
        .where((k) => k >= _sections.length)
        .toList();
    for (final k in removed) {
      final ctrl = _sectionCtrls[k]!;
      final focus = _sectionFocusNodes[k];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ctrl.dispose();
        focus?.dispose();
      });
      _sectionCtrls.remove(k);
      _sectionFocusNodes.remove(k);
    }
    _suppressItemListener = false;
  }

  void _onParagraphChanged(int index) {
    if (_suppressItemListener) return;
    if (index >= _paragraphs.length) return;
    _paragraphs[index] = _paraCtrls[index]!.text;
    _setWholeText(_paragraphs.join('\n\n'));
  }

  void _onSectionChanged(int index) {
    if (_suppressItemListener) return;
    if (index >= _sections.length) return;
    _sections[index] = _sectionCtrls[index]!.text;
    _setWholeText(_sections.join('\n\n\n'));
  }

  void _setWholeText(String text) {
    debugPrint('setWholeText triggered len=${text.length}');
    final prevSelection = _controller.selection;
    final int prevOffset = prevSelection.baseOffset;

    _suppressTextListener = true;
    _controller.text = text;
    _lastText = text;

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

  bool _handleLineBackspaceAtStart(int index) {
    if (index <= 0) return false;
    final ctrl = _lineCtrls[index];
    if (ctrl == null) return false;
    if (ctrl.selection.baseOffset != 0) return false;
    final updated = _removeNthNewline(_controller.text, index - 1);
    if (updated == null) return false;
    _setWholeText(updated);
    _focusLineItemStart(index);
    return true;
  }

  bool _handleParagraphBackspaceAtStart(int index) {
    if (index <= 0) return false;
    final ctrl = _paraCtrls[index];
    if (ctrl == null) return false;
    if (ctrl.selection.baseOffset != 0) return false;
    final updated = _removeDelimiterRun(
      _controller.text,
      RegExp(r'\n{2,}'),
      index - 1,
    );
    if (updated == null) return false;
    _setWholeText(updated);
    _focusParagraphItemStart(index);
    return true;
  }

  bool _handleSectionBackspaceAtStart(int index) {
    if (index <= 0) return false;
    final ctrl = _sectionCtrls[index];
    if (ctrl == null) return false;
    if (ctrl.selection.baseOffset != 0) return false;
    final updated = _removeDelimiterRun(
      _controller.text,
      RegExp(r'\n{3,}'),
      index - 1,
    );
    if (updated == null) return false;
    _setWholeText(updated);
    _focusSectionItemStart(index);
    return true;
  }

  void _focusLineItemStart(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index < 0 || index >= _lines.length) return;
      final focus = _lineFocusNodes[index];
      final ctrl = _lineCtrls[index];
      if (focus == null || ctrl == null) return;
      focus.requestFocus();
      ctrl.selection = const TextSelection.collapsed(offset: 0);
    });
  }

  void _focusParagraphItemStart(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index < 0 || index >= _paragraphs.length) return;
      final focus = _paraFocusNodes[index];
      final ctrl = _paraCtrls[index];
      if (focus == null || ctrl == null) return;
      focus.requestFocus();
      ctrl.selection = const TextSelection.collapsed(offset: 0);
    });
  }

  void _focusSectionItemStart(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index < 0 || index >= _sections.length) return;
      final focus = _sectionFocusNodes[index];
      final ctrl = _sectionCtrls[index];
      if (focus == null || ctrl == null) return;
      focus.requestFocus();
      ctrl.selection = const TextSelection.collapsed(offset: 0);
    });
  }

  String? _removeNthNewline(String text, int nth) {
    if (nth < 0) return null;
    var count = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        if (count == nth) {
          return text.substring(0, i) + text.substring(i + 1);
        }
        count += 1;
      }
    }
    return null;
  }

  String? _removeDelimiterRun(String text, RegExp regex, int runIndex) {
    if (runIndex < 0) return null;
    final matches = regex.allMatches(text).toList(growable: false);
    if (runIndex >= matches.length) return null;
    final match = matches[runIndex];
    if (match.start >= text.length) return null;
    if (text.codeUnitAt(match.start) != 0x0A) return null;
    return text.substring(0, match.start) + text.substring(match.start + 1);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _controller.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    for (final node in _lineFocusNodes.values) {
      node.dispose();
    }
    for (final node in _paraFocusNodes.values) {
      node.dispose();
    }
    for (final node in _sectionFocusNodes.values) {
      node.dispose();
    }
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

  void _enterSearchMode() {
    setState(() {
      _isSearchMode = true;
    });
    _searchFocusNode.requestFocus();
  }

  void _exitSearchMode() {
    setState(() {
      _isSearchMode = false;
      _searchController.clear();
      _searchMatches.clear();
      _currentMatchIndex = -1;
    });
    _searchFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _tabController.index == 0
            ? (_isSearchMode
                  ? TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Search in memo...',
                        border: InputBorder.none,
                      ),
                    )
                  : Text(_fileName, style: const TextStyle(fontSize: 16)))
            : null,
        actions: [
          if (_tabController.index == 0 && !_isSearchMode)
            IconButton(onPressed: _renameFile, icon: const Icon(Icons.edit)),
          if (_tabController.index == 0 && !_isSearchMode)
            const SizedBox(width: 48),
          if (_tabController.index == 0 && _isSearchMode)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  _searchMatches.isEmpty
                      ? '0/0'
                      : '${_currentMatchIndex + 1}/${_searchMatches.length}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          if (_tabController.index == 0 && _isSearchMode)
            IconButton(
              tooltip: 'Previous match',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: _searchMatches.isEmpty
                  ? null
                  : () => _selectMatch(_currentMatchIndex - 1),
            ),
          if (_tabController.index == 0 && _isSearchMode)
            IconButton(
              tooltip: 'Next match',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: _searchMatches.isEmpty
                  ? null
                  : () => _selectMatch(_currentMatchIndex + 1),
            ),
          if (_tabController.index == 0)
            IconButton(
              onPressed: _isSearchMode ? _exitSearchMode : _enterSearchMode,
              icon: Icon(_isSearchMode ? Icons.close : Icons.search),
            ),
          if (_tabController.index == 0) const SizedBox(width: 48),
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
                  children: [
                    const Text('mode', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Icon(
                      _itemMode == ItemMode.copy
                          ? Icons.content_copy
                          : _itemMode == ItemMode.delete
                          ? Icons.delete
                          : Icons.unfold_less,
                      size: 16,
                    ),
                  ],
                ),
              ),
              tooltip: 'Toggle mode',
              onPressed: () {
                setState(() {
                  _itemMode = ItemMode
                      .values[(_itemMode.index + 1) % ItemMode.values.length];
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Mode: ${_modeLabel(_itemMode)}'),
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
            Tab(icon: Icon(Icons.dashboard_customize), text: 'Section'),
          ],
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: TabBarView(
          controller: _tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // --- All Tab ---
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: VisualWhitespaceTextField(
                key: _editorKey,
                controller: _controller,
                highlightRanges: _searchMatches,
                activeHighlightIndex: _currentMatchIndex,
                highlightColor: const Color(0x80E5FF00),
                activeHighlightColor: const Color(0x8001FF02),
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
                  final folded = _lineFolded.removeAt(oldIndex);
                  _lines.insert(newIndex, line);
                  _lineFolded.insert(newIndex, folded);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _setWholeText(_lines.join('\n'));
                  });
                });
              },
              itemBuilder: (context, index) {
                final folded = _lineFolded[index];
                return Padding(
                  key: ValueKey('line_$index'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                        child: folded
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade400,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _lines[index].replaceAll('\n', ' '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              )
                            : VisualWhitespaceTextField(
                                controller: _lineCtrls[index]!,
                                focusNode: _lineFocusNodes[index],
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
                          _itemMode == ItemMode.copy
                              ? Icons.content_copy
                              : _itemMode == ItemMode.delete
                              ? Icons.delete
                              : (folded
                                    ? Icons.unfold_more
                                    : Icons.unfold_less),
                        ),
                        color: _itemMode == ItemMode.delete ? Colors.red : null,
                        tooltip: _itemMode == ItemMode.copy
                            ? 'Copy'
                            : _itemMode == ItemMode.delete
                            ? 'Delete'
                            : (folded ? 'Expand' : 'Fold'),
                        onPressed: () {
                          switch (_itemMode) {
                            case ItemMode.copy:
                              _copyLine(index);
                              break;
                            case ItemMode.delete:
                              _confirmDeleteLine(index);
                              break;
                            case ItemMode.fold:
                              setState(() {
                                _lineFolded[index] = !_lineFolded[index];
                              });
                              break;
                          }
                        },
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
                  final folded = _paragraphFolded.removeAt(oldIndex);
                  _paragraphs.insert(newIndex, p);
                  _paragraphFolded.insert(newIndex, folded);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _setWholeText(_paragraphs.join('\n\n'));
                  });
                });
              },
              itemBuilder: (context, index) {
                final folded = _paragraphFolded[index];
                return Padding(
                  key: ValueKey('para_$index'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
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
                        child: folded
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade400,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _paragraphs[index].replaceAll('\n', ' '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              )
                            : VisualWhitespaceTextField(
                                controller: _paraCtrls[index]!,
                                focusNode: _paraFocusNodes[index],
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
                          _itemMode == ItemMode.copy
                              ? Icons.content_copy
                              : _itemMode == ItemMode.delete
                              ? Icons.delete
                              : (folded
                                    ? Icons.unfold_more
                                    : Icons.unfold_less),
                        ),
                        color: _itemMode == ItemMode.delete ? Colors.red : null,
                        tooltip: _itemMode == ItemMode.copy
                            ? 'Copy'
                            : _itemMode == ItemMode.delete
                            ? 'Delete'
                            : (folded ? 'Expand' : 'Fold'),
                        onPressed: () {
                          switch (_itemMode) {
                            case ItemMode.copy:
                              _copyParagraph(index);
                              break;
                            case ItemMode.delete:
                              _confirmDeleteParagraph(index);
                              break;
                            case ItemMode.fold:
                              setState(() {
                                _paragraphFolded[index] =
                                    !_paragraphFolded[index];
                              });
                              break;
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),

            // --- Section Tab ---
            ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _sections.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final s = _sections.removeAt(oldIndex);
                  final folded = _sectionFolded.removeAt(oldIndex);
                  _sections.insert(newIndex, s);
                  _sectionFolded.insert(newIndex, folded);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _setWholeText(_sections.join('\n\n\n'));
                  });
                });
              },
              itemBuilder: (context, index) {
                final folded = _sectionFolded[index];
                return Padding(
                  key: ValueKey('section_$index'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
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
                        child: folded
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade400,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _sections[index].replaceAll('\n', ' '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              )
                            : VisualWhitespaceTextField(
                                controller: _sectionCtrls[index]!,
                                focusNode: _sectionFocusNodes[index],
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
                          _itemMode == ItemMode.copy
                              ? Icons.content_copy
                              : _itemMode == ItemMode.delete
                              ? Icons.delete
                              : (folded
                                    ? Icons.unfold_more
                                    : Icons.unfold_less),
                        ),
                        color: _itemMode == ItemMode.delete ? Colors.red : null,
                        tooltip: _itemMode == ItemMode.copy
                            ? 'Copy'
                            : _itemMode == ItemMode.delete
                            ? 'Delete'
                            : (folded ? 'Expand' : 'Fold'),
                        onPressed: () {
                          switch (_itemMode) {
                            case ItemMode.copy:
                              _copySection(index);
                              break;
                            case ItemMode.delete:
                              _confirmDeleteSection(index);
                              break;
                            case ItemMode.fold:
                              setState(() {
                                _sectionFolded[index] = !_sectionFolded[index];
                              });
                              break;
                          }
                        },
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
      _lineFolded.removeAt(index);
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
      _paragraphFolded.removeAt(index);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setWholeText(_paragraphs.join('\n\n'));
      });
    }
  }

  Future<void> _copySection(int index) async {
    final text = _sections[index];
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Section copied')));
  }

  Future<void> _confirmDeleteSection(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete section'),
        content: const Text('Are you sure you want to delete this section?'),
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
      _sections.removeAt(index);
      _sectionFolded.removeAt(index);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setWholeText(_sections.join('\n\n\n'));
      });
    }
  }

  // Cut functions removed as delete via swipe is preferred.
}
