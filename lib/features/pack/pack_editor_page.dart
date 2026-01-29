import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:provider/provider.dart';

import 'pack_controller.dart';

class PackEditorPage extends StatefulWidget {
  final String packId;

  const PackEditorPage({
    super.key,
    required this.packId,
  });

  @override
  State<PackEditorPage> createState() => _PackEditorPageState();
}

class _PackEditorPageState extends State<PackEditorPage> {
  late final CodeController _code;
  final FocusNode _focus = FocusNode();

  final TextEditingController _findCtrl = TextEditingController();
  final TextEditingController _replaceCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  bool _showFind = false;
  bool _caseSensitive = false;

  bool _dirty = false;
  String _loadedSnapshot = '';

  // listener helpers
  String _lastText = '';
  TextSelection _lastSel = const TextSelection.collapsed(offset: 0);
  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    _code = CodeController(text: '', language: javascript);
    _code.addListener(_onCodeChanged);
    _load();
  }

  @override
  void dispose() {
    _code.removeListener(_onCodeChanged);
    _code.dispose();
    _focus.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pc = context.read<PackController>();
      final code = await pc.loadEntryCode(widget.packId);
      if (!mounted) return;

      _mutating = true;
      _code.text = code;
      _code.selection = TextSelection.collapsed(offset: _code.text.length);

      _loadedSnapshot = code;
      _dirty = false;

      _lastText = _code.text;
      _lastSel = _code.selection;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载失败: $e')));
    } finally {
      _mutating = false;
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final pc = context.read<PackController>();
      await pc.saveEntryCode(widget.packId, _code.text);
      if (!mounted) return;

      _loadedSnapshot = _code.text;
      _dirty = false;

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未保存更改'),
        content: const Text('有未保存的修改，确定要退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // =========================
  // Editor Enhancements
  // =========================

  void _onCodeChanged() {
    if (_mutating) return;

    final newText = _code.text;
    final newSel = _code.selection;

    if (newText != _lastText) {
      _dirty = (newText != _loadedSnapshot);
      _autoIndent(newText, newSel);
      _autoPair(newText, newSel);
    }

    _lastText = _code.text;
    _lastSel = _code.selection;
  }

  void _autoIndent(String newText, TextSelection newSel) {
    if (_mutating) return;
    if (!newSel.isCollapsed) return;

    final oldText = _lastText;
    final oldSel = _lastSel;
    if (!oldSel.isCollapsed) return;

    final o = oldSel.baseOffset;
    final n = newSel.baseOffset;

    if (n != o + 1) return;
    if (o < 0 || o > oldText.length) return;
    if (n < 0 || n > newText.length) return;

    if (o >= newText.length) return;
    if (newText[o] != '\n') return;

    final prevLineStart = newText.lastIndexOf('\n', o - 1) + 1;
    final prevLine = newText.substring(prevLineStart, o);

    final indent = RegExp(r'^[ \t]+').firstMatch(prevLine)?.group(0) ?? '';
    final trimmed = prevLine.trimRight();
    final extra = trimmed.endsWith('{') ? '  ' : '';

    final insert = indent + extra;
    if (insert.isEmpty) return;

    _mutating = true;
    try {
      final before = newText.substring(0, n);
      final after = newText.substring(n);
      _code.text = before + insert + after;
      _code.selection = TextSelection.collapsed(offset: n + insert.length);
    } finally {
      _mutating = false;
    }
  }

  void _autoPair(String newText, TextSelection newSel) {
    if (_mutating) return;
    if (!newSel.isCollapsed) return;

    final oldSel = _lastSel;
    if (!oldSel.isCollapsed) return;

    final o = oldSel.baseOffset;
    final n = newSel.baseOffset;

    if (n != o + 1) return;
    if (o < 0 || o >= newText.length) return;

    final inserted = newText[o];
    final pair = _pairFor(inserted);
    if (pair == null) return;

    final nextChar = (n < newText.length) ? newText[n] : '';
    if (nextChar == pair) return;

    if ((inserted == '"' || inserted == "'" || inserted == '`') && o - 1 >= 0) {
      final prev = newText[o - 1];
      if (RegExp(r'[A-Za-z0-9_\\]').hasMatch(prev)) return;
    }

    _mutating = true;
    try {
      final before = newText.substring(0, n);
      final after = newText.substring(n);
      _code.text = before + pair + after;
      _code.selection = TextSelection.collapsed(offset: n);
    } finally {
      _mutating = false;
    }
  }

  String? _pairFor(String ch) {
    switch (ch) {
      case '(':
        return ')';
      case '[':
        return ']';
      case '{':
        return '}';
      case '"':
        return '"';
      case "'":
        return "'";
      case '`':
        return '`';
      default:
        return null;
    }
  }

  // =========================
  // Find / Replace
  // =========================

  String _norm(String s) => _caseSensitive ? s : s.toLowerCase();

  bool _selectRange(int start, int end) {
    if (start < 0 || end < 0 || start > end || end > _code.text.length) {
      return false;
    }
    _mutating = true;
    try {
      _code.selection = TextSelection(baseOffset: start, extentOffset: end);
    } finally {
      _mutating = false;
    }
    _focus.requestFocus();
    return true;
  }

  void _findNext() {
    final q0 = _findCtrl.text;
    if (q0.isEmpty) return;
    final text = _code.text;
    final q = _norm(q0);
    final t = _norm(text);

    final sel = _code.selection;
    final from = sel.isCollapsed ? sel.baseOffset : sel.extentOffset;
    final i = t.indexOf(q, from);
    if (i >= 0) {
      _selectRange(i, i + q.length);
      return;
    }
    final w = t.indexOf(q, 0);
    if (w >= 0) {
      _selectRange(w, w + q.length);
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('找不到')));
  }

  void _findPrev() {
    final q0 = _findCtrl.text;
    if (q0.isEmpty) return;
    final text = _code.text;
    final q = _norm(q0);
    final t = _norm(text);

    final sel = _code.selection;
    final from = sel.isCollapsed ? sel.baseOffset : sel.baseOffset;
    final sub = t.substring(0, from.clamp(0, t.length));
    final i = sub.lastIndexOf(q);
    if (i >= 0) {
      _selectRange(i, i + q.length);
      return;
    }
    final w = t.lastIndexOf(q);
    if (w >= 0) {
      _selectRange(w, w + q.length);
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('找不到')));
  }

  void _replaceOne() {
    final q0 = _findCtrl.text;
    if (q0.isEmpty) return;

    final sel = _code.selection;
    if (sel.isCollapsed) {
      _findNext();
      return;
    }

    final text = _code.text;
    final selected = text.substring(sel.start, sel.end);
    final match = _caseSensitive ? (selected == q0) : (_norm(selected) == _norm(q0));
    if (!match) {
      _findNext();
      return;
    }

    final rep = _replaceCtrl.text;
    _mutating = true;
    try {
      final before = text.substring(0, sel.start);
      final after = text.substring(sel.end);
      _code.text = before + rep + after;
      final caret = sel.start + rep.length;
      _code.selection = TextSelection.collapsed(offset: caret);
    } finally {
      _mutating = false;
    }
  }

  void _replaceAll() {
    final q0 = _findCtrl.text;
    if (q0.isEmpty) return;

    final rep = _replaceCtrl.text;
    final text = _code.text;

    final out = _caseSensitive
        ? text.replaceAll(q0, rep)
        : _replaceAllCaseInsensitive(text, q0, rep);

    if (out == text) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有可替换项')));
      return;
    }

    _mutating = true;
    try {
      _code.text = out;
      _code.selection = const TextSelection.collapsed(offset: 0);
    } finally {
      _mutating = false;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('替换完成')));
  }

  String _replaceAllCaseInsensitive(String text, String needle, String rep) {
    final tl = text.toLowerCase();
    final nl = needle.toLowerCase();
    int i = 0;
    final sb = StringBuffer();
    while (true) {
      final k = tl.indexOf(nl, i);
      if (k < 0) {
        sb.write(text.substring(i));
        break;
      }
      sb.write(text.substring(i, k));
      sb.write(rep);
      i = k + needle.length;
    }
    return sb.toString();
  }

  // =========================
  // Indent / Outdent
  // =========================

  void _indentSelection({bool outdent = false}) {
    final text = _code.text;
    final sel = _code.selection;

    final start = sel.start;
    final end = sel.end;

    int lineStart =
        text.lastIndexOf('\n', (start - 1).clamp(0, text.length)) + 1;
    int lineEnd = end;
    if (lineEnd < text.length) {
      final nextNl = text.indexOf('\n', lineEnd);
      if (nextNl >= 0) lineEnd = nextNl;
    }

    final block = text.substring(lineStart, lineEnd);
    final lines = block.split('\n');

    const indent = '  ';
    final newLines = <String>[];
    int delta = 0;

    for (final line in lines) {
      if (!outdent) {
        newLines.add(indent + line);
        delta += indent.length;
      } else {
        if (line.startsWith(indent)) {
          newLines.add(line.substring(indent.length));
          delta -= indent.length;
        } else if (line.startsWith('\t')) {
          newLines.add(line.substring(1));
          delta -= 1;
        } else if (line.startsWith(' ')) {
          final cut = line.startsWith('  ') ? 2 : 1;
          newLines.add(line.substring(cut));
          delta -= cut;
        } else {
          newLines.add(line);
        }
      }
    }

    final replaced = newLines.join('\n');

    _mutating = true;
    try {
      _code.text =
          text.substring(0, lineStart) + replaced + text.substring(lineEnd);

      final newStart =
          (start + (!outdent ? indent.length : 0)).clamp(0, _code.text.length);
      final newEnd = (end + delta).clamp(0, _code.text.length);
      _code.selection = TextSelection(baseOffset: newStart, extentOffset: newEnd);
    } finally {
      _mutating = false;
    }
    _focus.requestFocus();
  }

  void _insertTab() {
    final text = _code.text;
    final sel = _code.selection;
    const tab = '  ';

    if (!sel.isCollapsed) {
      _indentSelection(outdent: false);
      return;
    }

    _mutating = true;
    try {
      final i = sel.baseOffset.clamp(0, text.length);
      _code.text = text.substring(0, i) + tab + text.substring(i);
      _code.selection = TextSelection.collapsed(offset: i + tab.length);
    } finally {
      _mutating = false;
    }
    _focus.requestFocus();
  }

  // =========================
  // Syntax check (basic)
  // =========================

  void _checkSyntax() {
    final diags = _basicJsDiagnostics(_code.text);
    if (diags.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('语法检查：未发现明显问题')));
      return;
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: diags.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final d = diags[i];
            return ListTile(
              dense: true,
              title: Text(d.message),
              subtitle: Text('line ${d.line}, col ${d.col}'),
              onTap: () {
                Navigator.pop(context);
                final offset = _offsetFromLineCol(_code.text, d.line, d.col);
                _selectRange(offset, offset);
              },
            );
          },
        ),
      ),
    );
  }

  int _offsetFromLineCol(String text, int line1, int col1) {
    int line = 1;
    int col = 1;
    for (int i = 0; i < text.length; i++) {
      if (line == line1 && col == col1) return i;
      final ch = text[i];
      if (ch == '\n') {
        line++;
        col = 1;
      } else {
        col++;
      }
    }
    return text.length;
  }

  List<_Diag> _basicJsDiagnostics(String src) {
    final out = <_Diag>[];
    final stack = <_Open>[];

    bool inS = false; // '
    bool inD = false; // "
    bool inT = false; // `
    bool inLineC = false; // //
    bool inBlockC = false; // /*
    bool esc = false;

    int line = 1;
    int col = 1;

    void push(String ch) => stack.add(_Open(ch, line, col));
    void popExpect(String ch) {
      if (stack.isEmpty) {
        out.add(_Diag('多余的闭合符号: $ch', line, col));
        return;
      }
      final top = stack.removeLast();
      final ok = (top.ch == '(' && ch == ')') ||
          (top.ch == '[' && ch == ']') ||
          (top.ch == '{' && ch == '}');
      if (!ok) {
        out.add(_Diag(
          '括号不匹配: ${top.ch} 在 line ${top.line}, col ${top.col}；这里是 $ch',
          line,
          col,
        ));
      }
    }

    for (int i = 0; i < src.length; i++) {
      final ch = src[i];
      final next = (i + 1 < src.length) ? src[i + 1] : '';

      if (ch == '\n') {
        line++;
        col = 1;
        inLineC = false;
        esc = false;
        continue;
      }

      if (!inS && !inD && !inT) {
        if (!inBlockC && !inLineC && ch == '/' && next == '/') {
          inLineC = true;
          col++;
          continue;
        }
        if (!inBlockC && !inLineC && ch == '/' && next == '*') {
          inBlockC = true;
          col++;
          continue;
        }
      }
      if (inLineC) {
        col++;
        continue;
      }
      if (inBlockC) {
        if (ch == '*' && next == '/') {
          inBlockC = false;
          col++;
        }
        col++;
        continue;
      }

      if (inS || inD || inT) {
        if (esc) {
          esc = false;
          col++;
          continue;
        }
        if (ch == '\\') {
          esc = true;
          col++;
          continue;
        }
        if (inS && ch == "'") inS = false;
        else if (inD && ch == '"') inD = false;
        else if (inT && ch == '`') inT = false;
        col++;
        continue;
      } else {
        if (ch == "'") {
          inS = true;
          col++;
          continue;
        }
        if (ch == '"') {
          inD = true;
          col++;
          continue;
        }
        if (ch == '`') {
          inT = true;
          col++;
          continue;
        }
      }

      if (ch == '(' || ch == '[' || ch == '{') {
        push(ch);
      } else if (ch == ')' || ch == ']' || ch == '}') {
        popExpect(ch);
      }

      col++;
    }

    if (inBlockC) out.add(_Diag('块注释未闭合 /*', line, col));
    if (inS) out.add(_Diag("单引号字符串未闭合 '", line, col));
    if (inD) out.add(_Diag('双引号字符串未闭合 "', line, col));
    if (inT) out.add(_Diag('模板字符串未闭合 `', line, col));

    while (stack.isNotEmpty) {
      final o = stack.removeLast();
      out.add(_Diag('括号未闭合: ${o.ch}', o.line, o.col));
    }

    return out;
  }

  // =========================
  // UI helpers
  // =========================

  void _toggleFind() {
    setState(() => _showFind = !_showFind);
    if (_showFind) {
      Future.microtask(() => _focus.requestFocus());
    }
  }

  void _toggleReplace() {
    if (!_showFind) {
      setState(() => _showFind = true);
      Future.microtask(() => _focus.requestFocus());
    }
  }

  // =========================
  // Shortcuts
  // =========================

  Map<ShortcutActivator, Intent> _shortcuts() {
    final isApple = Platform.isMacOS || Platform.isIOS;
    final primary = isApple ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control;

    return <ShortcutActivator, Intent>{
      SingleActivator(primary, key: LogicalKeyboardKey.keyS): const _SaveIntent(),
      SingleActivator(primary, key: LogicalKeyboardKey.keyF): const _FindIntent(),
      SingleActivator(primary, key: LogicalKeyboardKey.keyH): const _ReplaceIntent(),
      const SingleActivator(LogicalKeyboardKey.escape): const _EscIntent(),

      const SingleActivator(LogicalKeyboardKey.tab): const _TabIntent(),
      const SingleActivator(LogicalKeyboardKey.tab, shift: true): const _ShiftTabIntent(),

      // optional: F3 / Shift+F3 next/prev
      const SingleActivator(LogicalKeyboardKey.f3): const _FindNextIntent(),
      const SingleActivator(LogicalKeyboardKey.f3, shift: true): const _FindPrevIntent(),
    };
  }

  Map<Type, Action<Intent>> _actions() {
    return <Type, Action<Intent>>{
      _SaveIntent: CallbackAction<_SaveIntent>(
        onInvoke: (_) {
          if (!_loading && !_saving) _save();
          return null;
        },
      ),
      _FindIntent: CallbackAction<_FindIntent>(
        onInvoke: (_) {
          if (_loading) return null;
          if (!_showFind) _toggleFind();
          return null;
        },
      ),
      _ReplaceIntent: CallbackAction<_ReplaceIntent>(
        onInvoke: (_) {
          if (_loading) return null;
          _toggleReplace();
          return null;
        },
      ),
      _EscIntent: CallbackAction<_EscIntent>(
        onInvoke: (_) {
          if (_showFind) {
            setState(() => _showFind = false);
            _focus.requestFocus();
          }
          return null;
        },
      ),
      _TabIntent: CallbackAction<_TabIntent>(
        onInvoke: (_) {
          if (_loading) return null;
          _insertTab();
          return null;
        },
      ),
      _ShiftTabIntent: CallbackAction<_ShiftTabIntent>(
        onInvoke: (_) {
          if (_loading) return null;
          _indentSelection(outdent: true);
          return null;
        },
      ),
      _FindNextIntent: CallbackAction<_FindNextIntent>(
        onInvoke: (_) {
          if (_loading) return null;
          if (_showFind) _findNext();
          return null;
        },
      ),
      _FindPrevIntent: CallbackAction<_FindPrevIntent>(
        onInvoke: (_) {
          if (_loading) return null;
          if (_showFind) _findPrev();
          return null;
        },
      ),
    };
  }

  // =========================
  // Build
  // =========================

  @override
  Widget build(BuildContext context) {
    final title = _dirty ? '编辑 ${widget.packId}/main.js *' : '编辑 ${widget.packId}/main.js';

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscardIfDirty();
        if (!mounted) return;
        if (ok) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              tooltip: '查找/替换',
              icon: Icon(_showFind ? Icons.close : Icons.search),
              onPressed: _loading ? null : _toggleFind,
            ),
            IconButton(
              tooltip: '语法检查',
              icon: const Icon(Icons.rule),
              onPressed: _loading ? null : _checkSyntax,
            ),
            IconButton(
              tooltip: '保存 (Ctrl/⌘+S)',
              icon: const Icon(Icons.save),
              onPressed: _loading || _saving ? null : _save,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Shortcuts(
                shortcuts: _shortcuts(),
                child: Actions(
                  actions: _actions(),
                  child: Focus(
                    autofocus: true,
                    child: Column(
                      children: [
                        if (_showFind) _buildFindBar(context),
                        _buildToolbar(context),
                        const Divider(height: 1),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Scrollbar(
                              interactive: true,
                              child: CodeField(
                                focusNode: _focus,
                                controller: _code,
                                expands: true,
                                lineNumberStyle: const LineNumberStyle(
                                  textStyle: TextStyle(color: Colors.grey),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          TextButton.icon(
            onPressed: _insertTab,
            icon: const Icon(Icons.keyboard_tab, size: 18),
            label: const Text('Tab'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _indentSelection(outdent: false),
            icon: const Icon(Icons.format_indent_increase, size: 18),
            label: const Text('缩进'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _indentSelection(outdent: true),
            icon: const Icon(Icons.format_indent_decrease, size: 18),
            label: const Text('反缩进'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () {
              _mutating = true;
              try {
                _code.text = '';
                _code.selection = const TextSelection.collapsed(offset: 0);
              } finally {
                _mutating = false;
              }
              _dirty = true;
              _focus.requestFocus();
              setState(() {});
            },
            icon: const Icon(Icons.delete_sweep, size: 18),
            label: const Text('清空'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () {
              _mutating = true;
              try {
                _code.text = _loadedSnapshot;
                _code.selection =
                    TextSelection.collapsed(offset: _code.text.length);
              } finally {
                _mutating = false;
              }
              _dirty = false;
              _focus.requestFocus();
              setState(() {});
            },
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('还原'),
          ),
        ],
      ),
    );
  }

  Widget _buildFindBar(BuildContext context) {
    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _findCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: '查找 (Ctrl/⌘+F)',
                    ),
                    onSubmitted: (_) => _findNext(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '上一个 (Shift+F3)',
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: _findPrev,
                ),
                IconButton(
                  tooltip: '下一个 (F3)',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: _findNext,
                ),
                IconButton(
                  tooltip: '大小写',
                  icon: Icon(
                    _caseSensitive ? Icons.text_fields : Icons.text_fields_outlined,
                  ),
                  onPressed: () => setState(() => _caseSensitive = !_caseSensitive),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replaceCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: '替换为 (Ctrl/⌘+H)',
                    ),
                    onSubmitted: (_) => _replaceOne(),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _replaceOne,
                  child: const Text('替换'),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: _replaceAll,
                  child: const Text('全部替换'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Open {
  final String ch;
  final int line;
  final int col;
  _Open(this.ch, this.line, this.col);
}

class _Diag {
  final String message;
  final int line;
  final int col;
  _Diag(this.message, this.line, this.col);
}

// ===== intents =====
class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _FindIntent extends Intent {
  const _FindIntent();
}

class _ReplaceIntent extends Intent {
  const _ReplaceIntent();
}

class _EscIntent extends Intent {
  const _EscIntent();
}

class _TabIntent extends Intent {
  const _TabIntent();
}

class _ShiftTabIntent extends Intent {
  const _ShiftTabIntent();
}

class _FindNextIntent extends Intent {
  const _FindNextIntent();
}

class _FindPrevIntent extends Intent {
  const _FindPrevIntent();
}