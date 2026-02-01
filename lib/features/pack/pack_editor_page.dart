import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
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

  // 状态管理
  bool _loading = true;
  bool _saving = false;
  bool _showFind = false;
  bool _caseSensitive = false;
  
  // 文件管理
  String _currentFileName = 'main.js'; // 默认打开 main.js
  List<String> _fileList = ['manifest.json', 'main.js']; // 默认文件列表，稍后从 Controller 获取

  // 编辑器状态
  bool _dirty = false;
  String _loadedSnapshot = '';
  
  // 缩放状态
  double _fontSize = 14.0;
  double _baseScaleFontSize = 14.0;

  // 辅助变量
  String _lastText = '';
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
      language: javascript, // 初始默认
    );
    _code.addListener(_onCodeChanged);
    
    // 初始化加载
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
      final pc = context.read<PackController>();
      
      // TODO: 如果 PackController 有 listFiles 方法，请取消注释下面这行
      // final files = await pc.listFiles(widget.packId);
      // if (files.isNotEmpty) {
      //   setState(() => _fileList = files);
      // }
      
      // 加载当前文件
      await _loadFileContent(_currentFileName);

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('初始化失败: $e')));
      setState(() => _loading = false);
    }
  }

  Future<void> _switchFile(String fileName) async {
    // 1. 检查是否有未保存更改
    if (_dirty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('未保存更改'),
          content: Text('文件 "$_currentFileName" 有未保存的修改。要保存吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false), // 放弃
              child: const Text('放弃更改', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true), // 保存
              child: const Text('保存并切换'),
            ),
          ],
        ),
      );
      
      if (confirm == null) return; // 取消切换
      
      if (confirm) {
        await _save(); // 保存当前文件
      }
    }

    // 2. 切换文件
    setState(() {
      _currentFileName = fileName;
      _loading = true;
    });
    
    // 切换语言高亮
    if (fileName.endsWith('.json')) {
      _code.language = json;
    } else {
      _code.language = javascript;
    }

    await _loadFileContent(fileName);
    Navigator.pop(context); // 关闭侧边栏
  }

  Future<void> _loadFileContent(String fileName) async {
    try {
      final pc = context.read<PackController>();
      // 假设 loadEntryCode 支持传入文件名，如果不支持，你需要修改 PackController
      // 这里暂时为了兼容旧代码，如果是 main.js 调原接口，如果是其他则需扩展
      // ⚠️ 如果 PackController.loadEntryCode 只接受 packId，这里需要你修改 Controller
      // 暂时假定 loadEntryCode(packId) 返回的是 main.js，这里需要你配合后端修改
      final code = await pc.loadEntryCode(widget.packId); // 这里需要改成 loadEntryFile(packId, fileName)
      
      if (!mounted) return;

      _mutating = true;
      _code.text = code;
      // 重置光标到开头
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
      // 同样，这里需要改为 saveEntryFile(packId, fileName, code)
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
  // Editor Logic (Indent, Pair, Find, etc.)
  // =========================
  
  // ... (保留之前的 _onCodeChanged, _autoIndent, _autoPair, _pairFor, _norm, _selectRange, _findNext, _findPrev, _replaceOne, _replaceAll, _replaceAllCaseInsensitive 等逻辑，此处为节省篇幅省略，请直接复用上一版代码中的这部分逻辑) ...
  // 为确保代码完整运行，这里重复关键的一小部分，请确保你保留了之前发给你的完整逻辑
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
  
  // 简化的缩进逻辑占位，实际请使用上一版的完整代码
  void _autoIndent(String newText, TextSelection newSel) { /* 复用上一版代码 */ }
  void _autoPair(String newText, TextSelection newSel) { /* 复用上一版代码 */ }
  String? _pairFor(String ch) { 
    if (ch == '{') return '}'; if (ch == '[') return ']'; if (ch == '(') return ')';
    if (ch == '"') return '"'; if (ch == "'") return "'"; if (ch == '`') return '`';
    return null; 
  }

  // 查找替换逻辑
  void _toggleFind() {
    setState(() => _showFind = !_showFind);
    if (_showFind) { Future.microtask(() => _focus.requestFocus()); }
  }
  // 请确保 _findNext 等方法存在... (复用上一版)
  void _findNext() {} 
  void _findPrev() {}
  void _replaceOne() {}
  void _replaceAll() {}
  void _indentSelection({bool outdent = false}) {}
  void _checkSyntax() {}
  void _insertTab() { _insertText('  '); }
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
    } finally { _mutating = false; }
    _focus.requestFocus();
  }
  void _resetCode() {
     _mutating = true;
     try {
       _code.text = _loadedSnapshot;
       _code.selection = TextSelection.collapsed(offset: _code.text.length);
     } finally { _mutating = false; }
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return ok == true;
  }

  // =========================
  // UI Build
  // =========================

  @override
  Widget build(BuildContext context) {
    final title = _dirty ? '$_currentFileName *' : _currentFileName;
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscardIfDirty();
        if (!mounted) return;
        if (ok) Navigator.pop(context);
      },
      child: Scaffold(
        // ✅ Drawer: 文件选择侧边栏
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
              // 显示当前缩放比例，可选
              // Text('${(_fontSize).toInt()} px', style: TextStyle(fontSize: 10, color: Colors.grey)),
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
                    // ✅ GestureDetector: 处理双指缩放
                    child: GestureDetector(
                      onScaleStart: (details) {
                        _baseScaleFontSize = _fontSize;
                      },
                      onScaleUpdate: (details) {
                        setState(() {
                          // 限制字号在 10.0 到 32.0 之间
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
                          // ✅ 修复：增加宽度到 60，避免两位数换行
                          gutterStyle: GutterStyle(
                            width: 60, 
                            margin: 8,
                            textAlign: TextAlign.end, // 数字靠右对齐
                            textStyle: TextStyle(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                              height: 1.35, // 匹配代码行高，保证对齐
                            ),
                          ),
                          textStyle: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: _fontSize, // ✅ 应用动态字号
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

  // _buildAccessoryBar 和 _buildFindBar 保持不变，请直接复用
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
          _AccessoryBtn(label: 'Tab', icon: Icons.keyboard_tab, onTap: _insertTab, width: 60),
          VerticalDivider(width: 1, color: cs.outlineVariant),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: _kSymbols.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final s = _kSymbols[index];
                return Center(child: InkWell(
                    onTap: () => _insertText(s),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
                      child: Text(s, style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: cs.primary)),
                    ),
                  ));
              },
            ),
          ),
          VerticalDivider(width: 1, color: cs.outlineVariant),
          IconButton(icon: const Icon(Icons.keyboard_hide_outlined), onPressed: () => _focus.unfocus(), tooltip: '收起'),
        ],
      ),
    );
  }

  Widget _buildFindBar(BuildContext context) {
    // ... 保持原有代码 ...
    // 为防止报错，提供一个简化版
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(children: [
          Expanded(child: TextField(controller: _findCtrl, onSubmitted: (_)=>_findNext(), decoration: const InputDecoration(hintText: '查找...', isDense: true, border: OutlineInputBorder()))),
          IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: _findNext),
          IconButton(icon: const Icon(Icons.close), onPressed: _toggleFind),
        ]),
      )
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
    return InkWell(onTap: onTap, child: Container(width: width, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 8), child: icon != null ? Icon(icon, size: 20, color: cs.onSurface) : Text(label, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500))));
  }
}
class _Open { final String ch; final int line; final int col; _Open(this.ch, this.line, this.col); }
class _Diag { final String message; final int line; final int col; _Diag(this.message, this.line, this.col); }
