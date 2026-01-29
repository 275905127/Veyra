import 'package:flutter/material.dart';
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
  final TextEditingController _ctrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
    _load();
  }

  void _onChanged() {
    if (_loading) return;
    if (_dirty) return;
    _dirty = true;
    // 不 setState，避免频繁 rebuild
  }

  Future<void> _load() async {
    try {
      final pc = context.read<PackController>();
      final code = await pc.loadEntryCode(widget.packId);
      _ctrl.text = code;
      _dirty = false;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final pc = context.read<PackController>();
      await pc.saveEntryCode(widget.packId, _ctrl.text);
      _dirty = false;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty || _saving) return true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未保存'),
        content: const Text('你有未保存的修改，要放弃吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final ok = await _confirmDiscardIfDirty();
        if (ok && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('编辑 ${widget.packId}/main.js'),
          actions: [
            IconButton(
              tooltip: '保存',
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              onPressed: (_saving || _loading) ? null : _save,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _ctrl,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.25,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
      ),
    );
  }
}