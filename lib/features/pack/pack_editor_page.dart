import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
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
  final FocusNode _editorFocus = FocusNode(debugLabel: 'pack_editor_focus');

  final TextEditingController _findCtrl = TextEditingController();
  final TextEditingController _replaceCtrl = TextEditingController();
  final FocusNode _findFocus = FocusNode(debugLabel: 'pack_find_focus');

  // ✅ 让 flutter_code_editor 自己做错误标注（波浪线/边栏错误）
  // 注：DefaultLocalAnalyzer 会做本地轻量分析（括号/配对等），并驱动 errors UI。
  final Analyzer _analyzer = DefaultLocalAnalyzer();

  // =========================
  // Page state
  // =========================
  bool _loading = true;
  bool _saving = false;

  bool _showFind = false;
  bool _caseSensitive = false;

  // =========================
  // Files
  // =========================
  String _currentFileName = 'main.js';
  List<String> _fileList = const <String>[];

  // =========================
  // Dirty tracking
  // =========================
  bool _dirty = false;
  String _loadedSnapshot = '';

  // =========================
  // Editor UX
  // =========================
  double _fontSize = 13.5;
  double _baseScaleFontSize = 13.5;

  // For auto indent/pair
  String _lastText = '';
  TextSelection _lastSel = const TextSelection.collapsed(offset: 0);
  bool _mutating = false;

  Timer? _dirtyDebounce;

  static const String _kIndent = '  ';

  static const List<String> _kSymbols = [
    '(',
    ')',
    '{',
    '}',
    '[',
    ']',
    '=',
    ':',
    ';',
    '.',
    ',',
    "'",
    '"',
    '`',
    '!',
    '?',
    '&',
    '|',
    '=>',
    'const',
    'let',
    'await',
    'return',
  ];

  // Only show “reasonable” editable files by default
  static const Set<String> _kTextExt = {
    '.js',
    '.mjs',
    '.cjs',
    '.ts',
    '.json',
    '.txt',
    '.md',
    '.css',
    '.html',
    '.yml',
    '.yaml',
  };

  @override
  void initState() {
    super.initState();

    _code = CodeController(
      text: '',
      language: javascript,
      analyzer: _analyzer, // ✅ 关键：启用分析器（驱动错误波浪线/边栏错误）
    );

    _code.addListener(_onCodeChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _dirtyDebounce?.cancel();

    _code.removeListener(_onCodeChanged);
    _code.dispose();

    _editorFocus.dispose();
    _findFocus.dispose();

    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  // =========================
  // Bootstrap
  // =========================

  Future<void> _bootstrap() async {
    try {
      final pc = context.read<PackController>();

      // 1) read manifest to decide entry
      final manifest = await pc.packStore.readManifest(widget.packId);
      final entry = (manifest['entry'] ?? 'main.js').toString().trim();
      _currentFileName = entry.isEmpty ? 'main.js' : entry;

      // 2) scan file list
      final files = await _scanPackFiles();
      // Ensure manifest + entry always on top
      final normalized = _normalizeFileList(files, entryFile: _currentFileName);

      if (!mounted) return;
      setState(() => _fileList = normalized);

      // 3) load current file
      _applyLanguageFor(_currentFileName);
      await _loadFileContent(_currentFileName);
    } catch (e) {
      if (!mounted) return;
      _snack('初始化失败: $e');
      setState(() => _loading = false);
    }
  }

  Future<List<String>> _scanPackFiles() async {
    final pc = context.read<PackController>();
    final dir = await pc.packStore.getPackDir(widget.packId);

    final out = <String>[];

    void walk(Directory d, String prefix) {
      final entities = d.listSync(followLinks: false);
      for (final ent in entities) {
        final name = ent.uri.pathSegments.isEmpty ? '' : ent.uri.pathSegments.last;
        if (name.isEmpty) continue;

        // Skip backups + hidden folders
        if (name == '.bak') continue;
        if (name.startsWith('.')) {
          if (ent is File && name == 'manifest.json') {
            out.add(prefix.isEmpty ? name : '$prefix/$name');
          }
          continue;
        }

        if (ent is Directory) {
          walk(ent, prefix.isEmpty ? name : '$prefix/$name');
          continue;
        }

        if (ent is File) {
          final rel = prefix.isEmpty ? name : '$prefix/$name';
          if (_looksEditable(rel)) out.add(rel);
        }
      }
    }

    walk(dir, '');

    // Fallback minimal list
    if (!out.contains('manifest.json')) out.add('manifest.json');
    return out;
  }

  bool _looksEditable(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.bak')) return false;
    final ext = _extOf(lower);
    if (ext.isEmpty) return true; // extensionless: still show
    return _kTextExt.contains(ext);
  }

  String _extOf(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return '';
    return path.substring(i);
  }

  List<String> _normalizeFileList(List<String> files, {required String entryFile}) {
    final set = <String>{...files};

    // Always keep these
    set.add('manifest.json');
    if (entryFile.isNotEmpty) set.add(entryFile);

    final list = set.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Pin manifest + entry
    list.remove('manifest.json');
    list.remove(entryFile);

    final pinned = <String>['manifest.json'];
    if (entryFile.isNotEmpty) pinned.add(entryFile);

    // Avoid duplication if entry == manifest
    final pinnedUnique = <String>[];
    for (final p in pinned) {
      if (p.isEmpty) continue;
      if (!pinnedUnique.contains(p)) pinnedUnique.add(p);
    }

    return <String>[
      ...pinnedUnique,
      ...list,
    ];
  }

  // =========================
  // File load / save / switch
  // =========================

  Future<void> _switchFile(String fileName) async {
    if (fileName == _currentFileName) {
      if (mounted) Navigator.pop(context); // close drawer
      return;
    }

    // If dirty, ask whether save
    if (_dirty) {
      final decision = await showDialog<_DirtyDecision>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('未保存更改'),
          content: Text('文件 "$_currentFileName" 有未保存的修改。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, _DirtyDecision.cancel),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, _DirtyDecision.discard),
              child: const Text('放弃更改', style: TextStyle(color: Colors.red)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _DirtyDecision.save),
              child: const Text('保存并切换'),
            ),
          ],
        ),
      );

      if (decision == null || decision == _DirtyDecision.cancel) return;

      if (decision == _DirtyDecision.save) {
        final ok = await _save();
        if (!ok) return; // save failed, do not switch
      }
      // discard -> continue switching
    }

    if (!mounted) return;

    setState(() {
      _currentFileName = fileName;
      _loading = true;
    });

    _applyLanguageFor(fileName);
    await _loadFileContent(fileName);

    if (!mounted) return;
    Navigator.pop(context); // close drawer
  }

  void _applyLanguageFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.json')) {
      // ✅ setLanguage 会刷新 analyzer 与语言绑定（更稳）
      _code.setLanguage(json, _analyzer);
    } else {
      _code.setLanguage(javascript, _analyzer);
    }
  }

  Future<void> _loadFileContent(String fileName) async {
    try {
      final pc = context.read<PackController>();
      final code = await pc.packStore.readText(widget.packId, fileName);

      if (!mounted) return;

      _mutating = true;
      _code.text = code;
      _code.selection = const TextSelection.collapsed(offset: 0);

      _loadedSnapshot = code;
      _setDirty(false);

      _lastText = _code.text;
      _lastSel = _code.selection;
    } catch (e) {
      if (!mounted) return;
      _snack('加载 $fileName 失败: $e');
    } finally {
      _mutating = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _save() async {
    if (_saving) return false;
    setState(() => _saving = true);

    try {
      final pc = context.read<PackController>();
      await pc.packStore.writeTextWithBackup(
        widget.packId,
        _currentFileName,
        _code.text,
        keep: 5,
      );

      if (!mounted) return true;

      _loadedSnapshot = _code.text;
      _setDirty(false);
      _snack('已保存 $_currentFileName');
      return true;
    } catch (e) {
      if (!mounted) return false;
      _snack('保存失败: $e');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // =========================
  // Dirty + editor change
  // =========================

  void _setDirty(bool v) {
    if (_dirty == v) return;
    setState(() => _dirty = v);
  }

  void _onCodeChanged() {
    if (_mutating) return;

    final newText = _code.text;
    final newSel = _code.selection;

    // Dirty detection (debounced to reduce rebuild pressure)
    _dirtyDebounce?.cancel();
    _dirtyDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      final isDirtyNow = (_code.text != _loadedSnapshot);
      if (_dirty != isDirtyNow) setState(() => _dirty = isDirtyNow);
    });

    // Auto behaviors only when “one char inserted”
    if (newText != _lastText) {
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
    final extra = trimmed.endsWith('{') ? _kIndent : '';
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
    if (start < 0 || end < 0 || start > end || end > _code.text.length) return false;
    _mutating = true;
    try {
      _code.selection = TextSelection(baseOffset: start, extentOffset: end);
    } finally {
      _mutating = false;
    }
    _editorFocus.requestFocus();
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

    final i = t.indexOf(q, from.clamp(0, t.length));
    if (i >= 0) {
      _selectRange(i, i + q.length);
      return;
    }

    final w = t.indexOf(q, 0);
    if (w >= 0) {
      _selectRange(w, w + q.length);
      return;
    }

    _snack('找不到');
  }

  void _findPrev() {
    final q0 = _findCtrl.text;
    if (q0.isEmpty) return;

    final text = _code.text;
    final q = _norm(q0);
    final t = _norm(text);

    final sel = _code.selection;
    final from = sel.isCollapsed ? sel.baseOffset : sel.baseOffset;

    final cut = from.clamp(0, t.length);
    final sub = t.substring(0, cut);

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

    _snack('找不到');
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

    final out = _caseSensitive ? text.replaceAll(q0, rep) : _replaceAllCaseInsensitive(text, q0, rep);

    if (out == text) {
      _snack('没有可替换项');
      return;
    }

    _mutating = true;
    try {
      _code.text = out;
      _code.selection = const TextSelection.collapsed(offset: 0);
    } finally {
      _mutating = false;
    }

    _snack('替换完成');
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

  void _toggleFind() {
    setState(() => _showFind = !_showFind);
    if (_showFind) {
      Future.microtask(() => _findFocus.requestFocus());
    } else {
      Future.microtask(() => _editorFocus.requestFocus());
    }
  }

  // =========================
  // Indent / insert helpers
  // =========================

  void _indentSelection({bool outdent = false}) {
    final text = _code.text;
    final sel = _code.selection;

    final start = sel.start;
    final end = sel.end;

    final int lineStart = text.lastIndexOf('\n', (start - 1).clamp(0, text.length)) + 1;

    int lineEnd = end;
    if (lineEnd < text.length) {
      final nextNl = text.indexOf('\n', lineEnd);
      if (nextNl >= 0) lineEnd = nextNl;
    }

    final block = text.substring(lineStart, lineEnd);
    final lines = block.split('\n');

    final newLines = <String>[];
    int delta = 0;

    for (final line in lines) {
      if (!outdent) {
        newLines.add(_kIndent + line);
        delta += _kIndent.length;
      } else {
        if (line.startsWith(_kIndent)) {
          newLines.add(line.substring(_kIndent.length));
          delta -= _kIndent.length;
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
      _code.text = text.substring(0, lineStart) + replaced + text.substring(lineEnd);

      final newStart = (start + (!outdent ? _kIndent.length : 0)).clamp(0, _code.text.length);
      final newEnd = (end + delta).clamp(0, _code.text.length);

      _code.selection = TextSelection(baseOffset: newStart, extentOffset: newEnd);
    } finally {
      _mutating = false;
    }

    _editorFocus.requestFocus();
  }

  void _insertTab() => _insertText(_kIndent);

  void _insertText(String text) {
    if (_mutating) return;

    _mutating = true;
    try {
      final sel = _code.selection;
      final start = sel.start < 0 ? 0 : sel.start;
      final end = sel.end < 0 ? 0 : sel.end;

      final before = _code.text.substring(0, start);
      final after = _code.text.substring(end);

      _code.text = before + text + after;
      _code.selection = TextSelection.collapsed(offset: start + text.length);
    } finally {
      _mutating = false;
    }

    _editorFocus.requestFocus();
  }

  void _resetCode() {
    _mutating = true;
    try {
      _code.text = _loadedSnapshot;
      _code.selection = TextSelection.collapsed(offset: _code.text.length);
    } finally {
      _mutating = false;
    }
    _setDirty(false);
  }

  // =========================
  // Back navigation guard
  // =========================

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;

    final decision = await showDialog<_DirtyDecision>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未保存更改'),
        content: const Text('有未保存的修改，确定要退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DirtyDecision.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DirtyDecision.discard),
            child: const Text('退出', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _DirtyDecision.save),
            child: const Text('保存并退出'),
          ),
        ],
      ),
    );

    if (decision == null || decision == _DirtyDecision.cancel) return false;
    if (decision == _DirtyDecision.discard) return true;

    return _save();
  }

  // =========================
  // UI helpers
  // =========================

  // ✅ 精确测量行号宽度，避免“10”被折成“1\n0”
  double _measureLineNumberGutterWidth({
    required BuildContext context,
    required TextStyle style,
    required int lineCount,
  }) {
    final digits = math.max(1, lineCount).toString().length;
    final sample = List.filled(digits, '8').join(); // “8888”最宽，保守估算
    final tp = TextPainter(
      text: TextSpan(text: sample, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();

    // 左右留白 + 轻微冗余，彻底杜绝折行
    return tp.width + 18.0;
  }

  // ✅ 缩放加速曲线：scale 变化“更灵敏”
  double _applyZoomCurve(double base, double rawScale) {
    // rawScale 通常在 0.9~1.1 附近抖动；这里做“非线性放大”
    final d = (rawScale - 1.0);
    final boosted = 1.0 + d * 2.6; // 灵敏度系数（越大越敏）
    // 额外再给一点曲线，让小幅度 pinch 也明显
    final curved = boosted >= 1 ? math.pow(boosted, 1.15).toDouble() : math.pow(boosted, 1.05).toDouble();
    return (base * curved).clamp(10.0, 32.0);
  }

  @override
  Widget build(BuildContext context) {
    final title = _dirty ? '$_currentFileName *' : _currentFileName;
    final cs = Theme.of(context).colorScheme;

    final int lineCount = _code.text.isEmpty ? 1 : _code.text.split('\n').length;

    final gutterTextStyle = TextStyle(
      fontFamily: 'monospace',
      color: cs.onSurfaceVariant.withValues(alpha: 0.45),
      height: 1.35,
      fontSize: _fontSize,
    );

    final gutterWidth = _measureLineNumberGutterWidth(
      context: context,
      style: gutterTextStyle,
      lineCount: lineCount,
    );

    final shortcuts = <ShortcutActivator, Intent>{
      // Save
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): const _SaveIntent(),
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): const _SaveIntent(),
      // Find
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): const _FindIntent(),
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): const _FindIntent(),
      // Indent / Outdent
      const SingleActivator(LogicalKeyboardKey.bracketRight, control: true): const _IndentIntent(false),
      const SingleActivator(LogicalKeyboardKey.bracketLeft, control: true): const _IndentIntent(true),
      const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true): const _IndentIntent(false),
      const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true): const _IndentIntent(true),
    };

    final actions = <Type, Action<Intent>>{
      _SaveIntent: CallbackAction<_SaveIntent>(
        onInvoke: (_) {
          if (!_loading && !_saving) _save();
          return null;
        },
      ),
      _FindIntent: CallbackAction<_FindIntent>(
        onInvoke: (_) {
          _toggleFind();
          return null;
        },
      ),
      _IndentIntent: CallbackAction<_IndentIntent>(
        onInvoke: (i) {
          _indentSelection(outdent: i.outdent);
          return null;
        },
      ),
    };

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscardIfDirty();
        if (!context.mounted) return;
        if (ok) Navigator.pop(context);
      },
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: actions,
          child: Focus(
            autofocus: true,
            child: Scaffold(
              drawer: Drawer(
                width: 280,
                child: Column(
                  children: [
                    DrawerHeader(
                      decoration: BoxDecoration(color: cs.surfaceContainer),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.folder_zip, size: 48, color: Colors.orange),
                            const SizedBox(height: 8),
                            Text(
                              widget.packId,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _fileList.isEmpty
                          ? const Center(child: Text('没有可编辑文件'))
                          : ListView.builder(
                              itemCount: _fileList.length,
                              itemBuilder: (context, index) {
                                final f = _fileList[index];
                                final isSelected = f == _currentFileName;
                                final isJson = f.toLowerCase().endsWith('.json');
                                return ListTile(
                                  leading: Icon(
                                    isJson ? Icons.data_object : Icons.javascript,
                                    color: isSelected ? cs.primary : null,
                                  ),
                                  title: Text(
                                    f,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? cs.primary : null,
                                    ),
                                  ),
                                  selected: isSelected,
                                  onTap: () => _switchFile(f),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              appBar: AppBar(
                title: Text(title, style: const TextStyle(fontSize: 16)),
                actions: [
                  IconButton(
                    tooltip: '查找替换 (Ctrl/⌘+F)',
                    icon: const Icon(Icons.search),
                    onPressed: _toggleFind,
                  ),
                  IconButton(
                    tooltip: '还原更改',
                    icon: const Icon(Icons.restart_alt),
                    onPressed: _dirty ? _resetCode : null,
                  ),
                  IconButton(
                    tooltip: '保存 (Ctrl/⌘+S)',
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    onPressed: (_loading || _saving) ? null : _save,
                  ),
                ],
              ),
              body: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        if (_showFind) _buildFindBar(context),
                        const Divider(height: 1),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onScaleStart: (_) => _baseScaleFontSize = _fontSize,
                            onScaleUpdate: (details) {
                              // ✅ 更灵敏缩放
                              setState(() {
                                _fontSize = _applyZoomCurve(_baseScaleFontSize, details.scale);
                              });
                            },
                            child: CodeTheme(
                              data: CodeThemeData(styles: atomOneDarkTheme),
                              child: CodeField(
                                controller: _code,
                                focusNode: _editorFocus,
                                expands: true,
                                wrap: false,

                                // ✅ 关键：打开 gutter errors（波浪线/错误提示由 analyzer 驱动）
                                gutterStyle: GutterStyle(
                                  width: gutterWidth,
                                  showFoldingHandles: false,
                                  showLineNumbers: true,
                                  showErrors: true, // ✅ 错误波浪线/错误 UI
                                  background: Colors.transparent,
                                  margin: 0,
                                  textAlign: TextAlign.end,
                                  textStyle: gutterTextStyle,
                                ),

                                textStyle: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: _fontSize,
                                  height: 1.35,
                                ),

                                // ✅ 可选：对特定行号做自定义（这里保持默认，但确保不换行）
                                lineNumberBuilder: (line, style) {
                                  final s = (style ?? gutterTextStyle).copyWith(
                                    fontFamily: 'monospace',
                                  );
                                  return TextSpan(text: '$line', style: s);
                                },
                              ),
                            ),
                          ),
                        ),
                        _buildAccessoryBar(context),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccessoryBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          _AccessoryBtn(
            label: 'Tab',
            icon: Icons.keyboard_tab,
            onTap: _insertTab,
            width: 60,
          ),
          VerticalDivider(width: 1, color: cs.outlineVariant),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: _kSymbols.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final s = _kSymbols[index];
                return Center(
                  child: InkWell(
                    onTap: () => _insertText(s),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        s,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          VerticalDivider(width: 1, color: cs.outlineVariant),
          IconButton(
            icon: const Icon(Icons.keyboard_hide_outlined),
            onPressed: () => _editorFocus.unfocus(),
            tooltip: '收起键盘',
          ),
        ],
      ),
    );
  }

  Widget _buildFindBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      focusNode: _findFocus,
                      controller: _findCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(),
                        hintText: '查找...',
                      ),
                      onSubmitted: (_) => _findNext(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: _findPrev,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '上一个',
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: _findNext,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '下一个',
                ),
                IconButton(
                  icon: Icon(_caseSensitive ? Icons.text_fields : Icons.text_fields_outlined),
                  onPressed: () => setState(() => _caseSensitive = !_caseSensitive),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: _caseSensitive ? '大小写敏感：开' : '大小写敏感：关',
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _toggleFind,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _replaceCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(),
                        hintText: '替换为...',
                      ),
                      onSubmitted: (_) => _replaceOne(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(onPressed: _replaceOne, child: const Text('替换')),
                TextButton(onPressed: _replaceAll, child: const Text('全部')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _DirtyDecision { cancel, discard, save }

class _AccessoryBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final double? width;

  const _AccessoryBtn({
    required this.label,
    this.icon,
    required this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: width,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: icon != null
            ? Icon(icon, size: 20, color: cs.onSurface)
            : Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }
}

// Keyboard intents
class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _FindIntent extends Intent {
  const _FindIntent();
}

class _IndentIntent extends Intent {
  final bool outdent;
  const _IndentIntent(this.outdent);
}