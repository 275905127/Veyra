import 'package:flutter/material.dart';
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
  late CodeController _controller;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _controller = CodeController(
      text: '',
      language: javascript,
    );

    _load();
  }

  Future<void> _load() async {
    try {
      final pc = context.read<PackController>();
      final code = await pc.loadEntryCode(widget.packId);

      if (!mounted) return;
      _controller.text = code;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载失败: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      final pc = context.read<PackController>();
      await pc.saveEntryCode(widget.packId, _controller.text);

      if (!mounted) return;
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('编辑 ${widget.packId}/main.js'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _loading || _saving ? null : _save,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CodeTheme(
              data: const CodeThemeData(
                styles: {
                  'root': TextStyle(
                    backgroundColor: Colors.transparent,
                    color: Colors.white,
                  ),
                  'comment': TextStyle(color: Colors.grey),
                  'keyword': TextStyle(color: Colors.lightBlue),
                  'string': TextStyle(color: Colors.greenAccent),
                  'number': TextStyle(color: Colors.orange),
                },
              ),
              child: CodeField(
                controller: _controller,
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
    );
  }
}