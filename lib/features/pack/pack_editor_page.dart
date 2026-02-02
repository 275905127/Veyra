import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:provider/provider.dart';

import '../../core/di/injection.dart';
import '../../core/extension/extension_engine.dart';
import '../source/source_controller.dart';
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
  // ===== Editor core =====
  late final DefaultLocalAnalyzer _analyzer;
  late final CodeController _code;
  final FocusNode _focus = FocusNode();

  final TextEditingController _findCtrl = TextEditingController();
  final TextEditingController _replaceCtrl = TextEditingController();

  // ===== UI state =====
  bool _loading = true;
  bool _saving = false;
  bool _showFind = false;
  bool _caseSensitive = false;

  // ===== Files =====
  String _currentFileName = 'main.js';
  List<String> _fileList = <String>['manifest.json', 'main.js'];

  // ===== Dirty tracking =====
  bool _dirty = false;
  String _loadedSnapshot = '';

  // ===== Zoom =====
  double _fontSize = 13.5;
  double _baseScaleFontSize = 13.5;
  double _lastScale = 1.0;

  // 缩放更灵敏：用“增量”而不是绝对 scale
  // 手指微动也能触发，但有轻微阈值避免抖动
  static const double _kScaleEpsilon = 0.015; // 越小越灵敏
  static const double _kZoomSpeed = 14.0; // 越大缩放越快（线性增益）
  static const double _kMinFont = 10.0;
  static const double _kMaxFont = 32.0;

  // ===== Helpers =====
  String _lastText = '';
  TextSelection _lastSel = const TextSelection.collapsed(offset: 0);
  bool _mutating = false;

  Timer? _debounceSyntaxTimer;
  final ValueNotifier<String?> _inlineError = ValueNotifier<String?>(null);

  static const List<String> _kSymbols = <String>[
    '(', ')', '{', '}', '[', ']',
    '=', ':', ';', '.', ',',
    "'", '"', '`',
    '!', '?', '&', '|',
    '=>', 'const', 'let', 'await', 'return',
  ];

  @override
  void initState() {
    super.initState();

    _analyzer = DefaultLocalAnalyzer();

    _code = CodeController(
      text: '',
      language: javascript,
      // ✅ 让编辑器具备 error underline（你的版本若支持）
      analyzer: _analyzer,
    );

    _code.addListener(_onCodeChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchFileListAndLoad();
    });
  }

  @override
  void dispose() {
    _debounceSyntaxTimer?.cancel();
    _inlineError.dispose();
    _code.removeListener(_onCodeChanged);
    _code.dispose();
    _focus.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  // =========================
  // File & Loading
  // =========================

  Future<void> _fetchFileListAndLoad() async {
    try {
      // 你当前工程里 PackStore 没有“列文件”API，这里维持默认 + 尝试读 entry/manifest
      // 如果你后面补了 listFiles(packId)，这里可以替换成真实列表。
      await _loadFileContent(_currentFileName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('初始化失败: $e')),
      );
      setState(() => _loading = false);
    }
  }

  Future<void> _loadFileContent(String fileName) async {
    setState(() {
      _loading = true;
      _inlineError.value = null;
    });

    final pc = context.read<PackController>();
    final text = await pc.packStore.readText(widget.packId, fileName);

    // 设置语言（不要用 setLanguage 传多参，避免你遇到的参数错误）
    final lang = fileName.endsWith('.json') ? json : javascript;
    _code.language = lang;

    _mutating = true;
    _code.text = text;
    _code.selection = const TextSelection.collapsed(offset: 0);
    _mutating = false;

    _loadedSnapshot = text;
    _lastText = text;
    _lastSel = _code.selection;
    _dirty = false;

    setState(() {
      _currentFileName = fileName;
      _loading = false;
    });

    // 初次加载也跑一次轻量检查（用于顶部提示，不影响 squiggle）
    _scheduleLightSyntaxCheck();
  }

  Future<void> _switchFile(String fileName) async {
    if (fileName == _currentFileName) return;

    if (_dirty) {
      final ok = await _confirmDiscard();
      if (ok != true) return;
    }
    if (!mounted) return;
    await _loadFileContent(fileName);
  }

  Future<bool?> _confirmDiscard() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未保存的更改'),
        content: const Text('当前文件有未保存的修改，要放弃并切换文件吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('放弃')),
        ],
      ),
    );
  }

  // =========================
  // Dirty tracking
  // =========================

  void _onCodeChanged() {
    if (_mutating) return;

    final t = _code.text;
    final sel = _code.selection;

    // dirty
    final nowDirty = t != _loadedSnapshot;
    if (nowDirty != _dirty) {
      setState(() => _dirty = nowDirty);
    }

    _lastText = t;
    _lastSel = sel;

    // ✅ 轻量语法检查：防止频繁阻塞（squiggle 由 analyzer 自己做）
    _scheduleLightSyntaxCheck();
  }

  void _scheduleLightSyntaxCheck() {
    _debounceSyntaxTimer?.cancel();
    _debounceSyntaxTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final err = _lightSyntaxCheck(_currentFileName, _code.text);
      _inlineError.value = err;
    });
  }

  String? _lightSyntaxCheck(String fileName, String text) {
    // 只做最轻量的“即时提示”，不替代 analyzer
    if (fileName.endsWith('.json')) {
      try {
        jsonDecode(text);
        return null;
      } catch (e) {
        return 'JSON 解析失败：$e';
      }
    }

    // JS 不做完整 AST（太重），只做常见括号/花括号/方括号配对检查
    int p = 0, b = 0, c = 0;
    for (int i = 0; i < text.length; i++) {
      final ch = text.codeUnitAt(i);
      if (ch == 40) p++; // (
      if (ch == 41) p--; // )
      if (ch == 91) b++; // [
      if (ch == 93) b--; // ]
      if (ch == 123) c++; // {
      if (ch == 125) c--; // }
      if (p < 0 || b < 0 || c < 0) return '括号疑似不匹配（在第 ${i + 1} 个字符附近）';
    }
    if (p != 0 || b != 0 || c != 0) return '括号疑似不匹配（未闭合）';
    return null;
  }

  // =========================
  // Save (and live apply)
  // =========================

  Future<void> _save() async {
    if (_saving || _loading) return;

    setState(() => _saving = true);
    try {
      final pc = context.read<PackController>();

      await pc.packStore.writeTextWithBackup(
        widget.packId,
        _currentFileName,
        _code.text,
      );

      _loadedSnapshot = _code.text;
      if (_dirty) setState(() => _dirty = false);

      // ✅ 保存后实时生效：清 JS runtime cache（确保 main.js 立刻重载）
      getIt<ExtensionEngine>().clearRuntimeCache(widget.packId);

      // ✅ manifest 或 entry 改了：让列表/源注册立即刷新
      // 这里用 load() 兜底，避免你工程里 Editor API 不全导致“保存没效果”
      await context.read<PackController>().load();
      await context.read<SourceController>().load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存并立即生效 ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // =========================
  // Find / Replace
  // =========================

  void _toggleFind() {
    setState(() {
      _showFind = !_showFind;
    });
    if (_showFind) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (!mounted) return;
        FocusScope.of(context).requestFocus();
      });
    }
  }

  void _findNext() {
    final query = _findCtrl.text;
    if (query.isEmpty) return;

    final text = _code.text;
    final start = math.max(0, _code.selection.end);
    final source = _caseSensitive ? text : text.toLowerCase();
    final q = _caseSensitive ? query : query.toLowerCase();

    int idx = source.indexOf(q, start);
    if (idx < 0 && start > 0) {
      idx = source.indexOf(q, 0);
    }
    if (idx < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到')),
      );
      return;
    }

    _mutating = true;
    _code.selection = TextSelection(baseOffset: idx, extentOffset: idx + query.length);
    _mutating = false;
    _focus.requestFocus();
  }

  void _replaceOne() {
    final query = _findCtrl.text;
    if (query.isEmpty) return;

    final sel = _code.selection;
    if (sel.isCollapsed) {
      _findNext();
      return;
    }

    final selected = _code.text.substring(sel.start, sel.end);
    final hit = _caseSensitive ? selected == query : selected.toLowerCase() == query.toLowerCase();
    if (!hit) {
      _findNext();
      return;
    }

    _replaceRange(sel.start, sel.end, _replaceCtrl.text);
    _findNext();
  }

  void _replaceAll() {
    final query = _findCtrl.text;
    if (query.isEmpty) return;

    final text = _code.text;
    final source = _caseSensitive ? text : text.toLowerCase();
    final q = _caseSensitive ? query : query.toLowerCase();

    int count = 0;
    int idx = source.indexOf(q, 0);
    if (idx < 0) return;

    final buf = StringBuffer();
    int last = 0;
    while (idx >= 0) {
      buf.write(text.substring(last, idx));
      buf.write(_replaceCtrl.text);
      last = idx + query.length;
      count++;
      idx = source.indexOf(q, last);
    }
    buf.write(text.substring(last));

    _mutating = true;
    _code.text = buf.toString();
    _code.selection = TextSelection.collapsed(offset: math.min(_code.text.length, last));
    _mutating = false;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('替换完成：$count 处')),
    );
  }

  void _replaceRange(int start, int end, String replacement) {
    final text = _code.text;
    final newText = text.replaceRange(start, end, replacement);
    _mutating = true;
    _code.text = newText;
    _code.selection = TextSelection.collapsed(offset: start + replacement.length);
    _mutating = false;
  }

  // =========================
  // Formatting helpers
  // =========================

  void _indentSelection() {
    final sel = _code.selection;
    if (sel.isCollapsed) return;

    final text = _code.text;
    final start = sel.start;
    final end = sel.end;

    final before = text.substring(0, start);
    final mid = text.substring(start, end);
    final after = text.substring(end);

    final lines = mid.split('\n');
    final indented = lines.map((l) => l.isEmpty ? l : '  $l').join('\n');

    _mutating = true;
    _code.text = before + indented + after;
    _code.selection = TextSelection(baseOffset: start, extentOffset: start + indented.length);
    _mutating = false;
  }

  void _resetCode() {
    _mutating = true;
    _code.text = _loadedSnapshot;
    _code.selection = const TextSelection.collapsed(offset: 0);
    _mutating = false;
    setState(() => _dirty = false);
  }

  void _checkSyntax() {
    final err = _lightSyntaxCheck(_currentFileName, _code.text);
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未发现明显语法问题 ✅')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }

  // =========================
  // Accessory bar insert
  // =========================

  void _insertTab() => _insertText('  ');

  void _insertText(String s) {
    final text = _code.text;
    final sel = _code.selection;
    final start = math.max(0, sel.start);
    final end = math.max(0, sel.end);

    final newText = text.replaceRange(start, end, s);
    final newOffset = start + s.length;

    _mutating = true;
    _code.text = newText;
    _code.selection = TextSelection.collapsed(offset: newOffset);
    _mutating = false;

    _focus.requestFocus();
  }

  // =========================
  // UI
  // =========================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = '${widget.packId} / $_currentFileName${_dirty ? ' *' : ''}';

    // gutter width: line count -> digits
    final lineCount = '\n'.allMatches(_code.text).length + 1;
    final digits = math.max(2, lineCount.toString().length);
    final gutterWidth = (digits * (_fontSize * 0.62) + 20).clamp(44.0, 84.0);

    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.folder_open),
                title: Text('文件'),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _fileList.length,
                  itemBuilder: (context, i) {
                    final f = _fileList[i];
                    final isSelected = f == _currentFileName;
                    return ListTile(
                      leading: Icon(
                        f.endsWith('.json') ? Icons.data_object : Icons.javascript,
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
                      onTap: () {
                        Navigator.pop(context);
                        _switchFile(f);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            ValueListenableBuilder<String?>(
              valueListenable: _inlineError,
              builder: (_, err, __) {
                if (err == null) return const SizedBox.shrink();
                return Text(
                  err,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.error),
                );
              },
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'find') _toggleFind();
              if (v == 'syntax') _checkSyntax();
              if (v == 'format') _indentSelection();
              if (v == 'reset') _resetCode();
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'find',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.search),
                  title: Text('查找替换'),
                ),
              ),
              PopupMenuItem(
                value: 'syntax',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.rule),
                  title: Text('语法检查'),
                ),
              ),
              PopupMenuItem(
                value: 'format',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.format_indent_increase),
                  title: Text('代码缩进'),
                ),
              ),
              PopupMenuItem(
                value: 'reset',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.restart_alt),
                  title: Text('还原更改'),
                ),
              ),
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
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (_) {
                      _baseScaleFontSize = _fontSize;
                      _lastScale = 1.0;
                    },
                    onScaleUpdate: (details) {
                      // ✅ 更灵敏：用增量 scale，且阈值更低
                      final ds = details.scale / _lastScale;
                      _lastScale = details.scale;

                      // 微抖过滤
                      if ((ds - 1.0).abs() < _kScaleEpsilon) return;

                      // 线性增益：ds>1 放大，ds<1 缩小
                      final delta = (ds - 1.0) * _kZoomSpeed;

                      setState(() {
                        _fontSize = (_fontSize + delta).clamp(_kMinFont, _kMaxFont);
                      });
                    },
                    child: CodeTheme(
                      data: CodeThemeData(styles: atomOneDarkTheme),
                      child: CodeField(
                        controller: _code,
                        // ✅ 你的版本如果要求 analyzer，这里也给（不再用 Analyzer 类型）
                        analyzer: _analyzer,
                        focusNode: _focus,
                        expands: true,
                        wrap: false,
                        gutterStyle: GutterStyle(
                          width: gutterWidth,
                          // ✅ 去掉折叠手柄 & 背景，避免“上下分割”的观感
                          showFoldingHandles: false,
                          background: Colors.transparent,
                          margin: 0,
                          textAlign: TextAlign.end,
                          textStyle: TextStyle(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.40),
                            height: 1.35,
                            fontSize: _fontSize,
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
    );
  }

  Widget _buildFindBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _findCtrl,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '查找',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _findNext(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _replaceCtrl,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '替换为',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _replaceOne(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '区分大小写',
            onPressed: () => setState(() => _caseSensitive = !_caseSensitive),
            icon: Icon(_caseSensitive ? Icons.text_fields : Icons.title),
          ),
          IconButton(
            tooltip: '下一个',
            onPressed: _findNext,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          IconButton(
            tooltip: '替换',
            onPressed: _replaceOne,
            icon: const Icon(Icons.find_replace),
          ),
          IconButton(
            tooltip: '全部替换',
            onPressed: _replaceAll,
            icon: const Icon(Icons.playlist_add_check),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: _toggleFind,
            icon: const Icon(Icons.close),
          ),
        ],
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
              padding: const EdgeInsets.symmetric(horizontal: 6),
              itemCount: _kSymbols.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
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
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        s,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: cs.onSurface,
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
            tooltip: '撤销',
            onPressed: () => _code.undo(),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: '重做',
            onPressed: () => _code.redo(),
            icon: const Icon(Icons.redo),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _AccessoryBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final double width;

  const _AccessoryBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      height: 48,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}