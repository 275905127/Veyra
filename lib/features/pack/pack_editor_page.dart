import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math; // 用于计算位数

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

  // 状态管理
  bool _loading = true;
  bool _saving = false;
  bool _showFind = false;
  bool _caseSensitive = false;
  
  // 文件管理
  String _currentFileName = 'main.js'; 
  // ignore: prefer_final_fields
  List<String> _fileList = ['manifest.json', 'main.js'];

  // 编辑器状态
  bool _dirty = false;
  String _loadedSnapshot = '';
  
  // 缩放状态
  double _fontSize = 14.0;
  double _baseScaleFontSize = 14.0;

  // 辅助变量
  String _lastText = '';
  // ignore: unused_field
  TextSelection _lastSel = const TextSelection.collapsed(offset: 0);
  bool _mutating = false;

  static const List<String> _kSymbols = [
    '(', ')', '{', '}', '[', ']', 
    '=', ':', ';', '.', ',', 
    "'", '"', '`', 
    '!', '?', '&', '|',
    '=>', 'const', 'let', 'await', 'return'
  ];

  @override
  void initState() {
    super.initState();
    _code = CodeController(
      text: '', 
      language: javascript,
    );
    _code.addListener(_onCodeChanged);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchFileListAndLoad();
    });
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

  // =========================
  // File & Loading Logic
  // =========================

  Future<void> _fetchFileListAndLoad() async {
    try {
      // 占位：如果 PackController 支持 listFiles，请在此处调用
      // final pc = context.read<PackController>();
      // final files = await pc.listFiles(widget.packId);
      // if (files.isNotEmpty) setState(() => _fileList = files);
      
      await _loadFileContent(_currentFileName);

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('初始化失败: $e')));
      setState(() => _loading = false);
    }
  }

  Future<void> _switchFile(String fileName) async {
    if (_dirty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('未保存更改'),
          content: Text('文件 "$_currentFileName" 有未保存的修改。要保存吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('放弃更改', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存并切换'),
            ),
          ],
        ),
      );
      
      if (confirm == null) return;
      if (confirm) {
        await _save();
      }
    }

    if (!mounted) return;
    setState(() {
      _currentFileName = fileName;
      _loading = true;
    });
    
    if (fileName.endsWith('.json')) {
      _code.language = json;
    } else {
      _code.language = javascript;
    }

    await _loadFileContent(fileName);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _loadFileContent(String fileName) async {
    try {
      final pc = context.read<PackController>();
      // 暂时假设 loadEntryCode 只加载 main.js，实际应根据 fileName 加载
      final code = await pc.loadEntryCode(widget.packId); 
      
      if (!mounted) return;

      _mutating = true;
      _code.text = code;
      _code.selection = const TextSelection.collapsed(offset: 0);
      _loadedSnapshot = code;
      _dirty = false;

      _lastText = _code.text;
      _lastSel = _code.selection;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载 $fileName 失败: $e')));
    } finally {
      _mutating = false;
      if (mounted) {
        setState(() => _loading = false);
      }
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

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已保存 $_currentFileName')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  // =========================
  // Editor Logic 
  // =========================

  void _onCodeChanged() {
    if (_mutating) return;
    final newText = _code.text;
    final newSel = _code.selection;

    if (newText != _lastText) {
      setState(() => _dirty = (newText != _loadedSnapshot));
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
      case '(': return ')';
      case '[': return ']';
      case '{': return '}';
      case '"': return '"';
      case "'": return "'";
      case '`': return '`';
      default: return null;
    }
  }

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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('找不到')));
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('找不到')));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有可替换项')));
      return;
    }
    _mutating = true;
    try {
      _code.text = out;
      _code.selection = const TextSelection.collapsed(offset: 0);
    } finally {
      _mutating = false;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('替换完成')));
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

  void _indentSelection({bool outdent = false}) {
    final text = _code.text;
    final sel = _code.selection;
    final start = sel.start;
    final end = sel.end;
    int lineStart = text.lastIndexOf('\n', (start - 1).clamp(0, text.length)) + 1;
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
      _code.text = text.substring(0, lineStart) + replaced + text.substring(lineEnd);
      final newStart = (start + (!outdent ? indent.length : 0)).clamp(0, _code.text.length);
      final newEnd = (end + delta).clamp(0, _code.text.length);
      _code.selection = TextSelection(baseOffset: newStart, extentOffset: newEnd);
    } finally {
      _mutating = false;
    }
    _focus.requestFocus();
  }

  void _insertTab() {
    _insertText('  ');
  }

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
    _focus.requestFocus();
  }

  void _checkSyntax() {
    final diags = _basicJsDiagnostics(_code.text);
    if (diags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('语法检查：未发现明显问题')));
      return;
    }
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: diags.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final d = diags[i];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.error_outline, color: Colors.orange),
              title: Text(d.message),
              subtitle: Text('line ${d.line}, col ${d.col}'),
              onTap: () {
                Navigator.pop(ctx);
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
    bool inS = false; bool inD = false; bool inT = false;
    bool inLineC = false; bool inBlockC = false; bool esc = false;
    int line = 1; int col = 1;

    void push(String ch) => stack.add(_Open(ch, line, col));
    void popExpect(String ch) {
      if (stack.isEmpty) { 
        out.add(_Diag('多余的闭合符号: $ch', line, col)); 
        return; 
      }
      final top = stack.removeLast();
      final ok = (top.ch == '(' && ch == ')') || (top.ch == '[' && ch == ']') || (top.ch == '{' && ch == '}');
      if (!ok) { 
        out.add(_Diag('括号不匹配: ${top.ch} (L${top.line}) vs $ch', line, col)); 
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
    if (inBlockC) out.add(_Diag('块注释未闭合', line, col));
    while (stack.isNotEmpty) { 
      final o = stack.removeLast(); 
      out.add(_Diag('括号未闭合: ${o.ch}', o.line, o.col)); 
    }
    return out;
  }

  void _toggleFind() {
    setState(() => _showFind = !_showFind);
    if (_showFind) { 
      Future.microtask(() => _focus.requestFocus()); 
    }
  }

  void _resetCode() {
     _mutating = true;
     try {
       _code.text = _loadedSnapshot;
       _code.selection = TextSelection.collapsed(offset: _code.text.length);
     } finally {
       _mutating = false;
     }
     _dirty = false;
     setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final title = _dirty ? '$_currentFileName *' : _currentFileName;
    final cs = Theme.of(context).colorScheme;

    // ✅ 动态行号宽度计算 (Dynamic Gutter Width)
    // 算法：计算行数的位数 (e.g. 100行=3位)，乘以字符宽度，加上很少的 padding
    int lineCount = 1;
    if (_code.text.isNotEmpty) {
      // 简单的行数估算，避免过于昂贵的 split 操作
      lineCount = _code.text.split('\n').length; 
    }
    int digits = lineCount.toString().length;
    // 等宽字体宽度约为 font size 的 0.6 倍，加上 12px 的内边距 (左右各6)
    double charWidth = _fontSize * 0.62; 
    double gutterWidth = (digits * charWidth) + 16.0;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscardIfDirty();
        if (!mounted) return;
        if (ok) Navigator.pop(context);
      },
      child: Scaffold(
        drawer: Drawer(
          width: 250,
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
                      Text(widget.packId, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _fileList.length,
                  itemBuilder: (context, index) {
                    final f = _fileList[index];
                    final isSelected = f == _currentFileName;
                    return ListTile(
                      leading: Icon(
                        f.endsWith('.json') ? Icons.data_object : Icons.javascript,
                        color: isSelected ? cs.primary : null,
                      ),
                      title: Text(f, style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? cs.primary : null,
                      )),
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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16)),
            ],
          ),
          actions: [
             PopupMenuButton<String>(
               icon: const Icon(Icons.more_vert),
               onSelected: (v) {
                 if (v == 'find') { _toggleFind(); }
                 if (v == 'syntax') { _checkSyntax(); }
                 if (v == 'format') { _indentSelection(); }
                 if (v == 'reset') { _resetCode(); }
               },
               itemBuilder: (ctx) => [
                 const PopupMenuItem(value: 'find', child: ListTile(dense: true, leading: Icon(Icons.search), title: Text('查找替换'))),
                 const PopupMenuItem(value: 'syntax', child: ListTile(dense: true, leading: Icon(Icons.rule), title: Text('语法检查'))),
                 const PopupMenuItem(value: 'format', child: ListTile(dense: true, leading: Icon(Icons.format_indent_increase), title: Text('代码缩进'))),
                 const PopupMenuItem(value: 'reset', child: ListTile(dense: true, leading: Icon(Icons.restart_alt), title: Text('还原更改'))),
               ],
             ),
             IconButton(
               tooltip: '保存',
               icon: _saving 
                   ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
                      onScaleStart: (details) {
                        _baseScaleFontSize = _fontSize;
                      },
                      onScaleUpdate: (details) {
                        setState(() {
                          _fontSize = (_baseScaleFontSize * details.scale).clamp(10.0, 32.0);
                        });
                      },
                      child: CodeTheme(
                        data: CodeThemeData(styles: atomOneDarkTheme), 
                        child: CodeField(
                          controller: _code,
                          focusNode: _focus,
                          expands: true,
                          wrap: false,
                          // ✅ 紧凑型 Gutter (MT Manager Style)
                          gutterStyle: GutterStyle(
                            width: gutterWidth, // 使用动态计算的宽度
                            margin: 0, // 去除外部边距，紧凑
                            textAlign: TextAlign.end, // 数字右对齐
                            textStyle: TextStyle(
                              // 使用更低调的颜色
                              color: cs.onSurfaceVariant.withValues(alpha: 0.4), 
                              height: 1.35,
                              fontSize: _fontSize, // 行号随代码缩放
                            ),
                          ),
                          textStyle: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: _fontSize,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ),

                  _buildAccessoryBar(context),
                ],
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
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                         color: cs.surfaceContainerHigh,
                         borderRadius: BorderRadius.circular(6),
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
            onPressed: () => _focus.unfocus(),
            tooltip: '收起',
          ),
        ],
      ),
    );
  }

  Widget _buildFindBar(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
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
                IconButton(icon: const Icon(Icons.keyboard_arrow_up), onPressed: _findPrev, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: _findNext, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                IconButton(
                  icon: Icon(_caseSensitive ? Icons.text_fields : Icons.text_fields_outlined), 
                  onPressed: () => setState(() => _caseSensitive = !_caseSensitive),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints()
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: _toggleFind, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              ],
            ),
            const SizedBox(height: 4),
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

class _AccessoryBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final double? width;

  const _AccessoryBtn({required this.label, this.icon, required this.onTap, this.width});

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
          : Text(label, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _Open { final String ch; final int line; final int col; _Open(this.ch, this.line, this.col); }
class _Diag { final String message; final int line; final int col; _Diag(this.message, this.line, this.col); }
