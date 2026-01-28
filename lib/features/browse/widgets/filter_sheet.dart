import 'package:flutter/material.dart';

import '../../../core/models/engine_pack.dart';
import '../../../core/storage/api_key_store.dart';
import '../../../core/storage/pack_store.dart';

class FilterSheet extends StatefulWidget {
  final String sourceId;
  final Map<String, dynamic> specRaw;
  final Map<String, dynamic> initialFilters;
  final PackStore packStore;
  final ApiKeyStore apiKeyStore;

  const FilterSheet({
    super.key,
    required this.sourceId,
    required this.specRaw,
    required this.initialFilters,
    required this.packStore,
    required this.apiKeyStore,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late Map<String, dynamic> _filters;
  List<ApiKeySpec> _apiKeySpecs = <ApiKeySpec>[];
  final Map<String, TextEditingController> _apiKeyControllers =
      <String, TextEditingController>{};
  bool _apiKeysLoaded = false;
  bool _isApiKeyExpanded = false;

  @override
  void initState() {
    super.initState();
    _filters = Map<String, dynamic>.from(widget.initialFilters);
    _loadApiKeySpecs();
  }

  Future<void> _loadApiKeySpecs() async {
    // 获取 pack 的 API Key 声明
    final packId =
        (widget.specRaw['packId'] ?? widget.specRaw['pack'] ?? '').toString().trim();
    if (packId.isEmpty) {
      if (mounted) setState(() => _apiKeysLoaded = true);
      return;
    }

    try {
      final packs = await widget.packStore.list();
      final pack = packs.firstWhere(
        (p) => p.id == packId,
        orElse: () => const EnginePack(
          id: '',
          name: '',
          version: '',
          entry: '',
          domains: <String>[],
        ),
      );

      if (pack.apiKeys.isNotEmpty) {
        _apiKeySpecs = pack.apiKeys;
        bool hasEmptyKey = false;

        // 为每个 API Key 创建 controller 并加载现有值
        for (final spec in _apiKeySpecs) {
          final controller = TextEditingController();
          _apiKeyControllers[spec.key] = controller;

          // 加载已保存的值
          final savedValue =
              await widget.apiKeyStore.getApiKey(widget.sourceId, spec.key);
          controller.text = savedValue ?? '';
          if (savedValue == null || savedValue.isEmpty) {
            hasEmptyKey = true;
          }
        }

        // 如果有必填项为空，默认展开
        if (hasEmptyKey) {
          _isApiKeyExpanded = true;
        }
      }
    } catch (e) {
      // 忽略错误
    }

    if (mounted) {
      setState(() => _apiKeysLoaded = true);
    }
  }

  @override
  void dispose() {
    for (final controller in _apiKeyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modes = (widget.specRaw['modes'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
        const <String, String>{};

    final defaultMode =
        (widget.specRaw['defaultMode'] ?? widget.specRaw['mode'] ?? '')
            .toString()
            .trim();

    final currentMode =
        ((_filters['mode'] ?? defaultMode) ?? '').toString().trim();

    final schema = (widget.specRaw['filters'] as List?) ?? const [];

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          elevation: 4,
          shadowColor: Colors.black54,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
            Column(
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        '筛选',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          final keepMode = _filters['mode'];
                          _filters = <String, dynamic>{};
                          if (keepMode != null &&
                              keepMode.toString().trim().isNotEmpty) {
                            _filters['mode'] = keepMode.toString().trim();
                          }
                          setState(() {});
                        },
                        child: const Text('重置'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // 底部留出空间给按钮
                    children: [
                      // 🔐 API Keys Section
                      if (_apiKeysLoaded && _apiKeySpecs.isNotEmpty)
                        Card(
                          elevation: 0,
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          margin: const EdgeInsets.only(bottom: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: ExpansionTile(
                            initiallyExpanded: _isApiKeyExpanded,
                            shape: const Border(), // 去除自带边框
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                            leading: const Icon(Icons.vpn_key_outlined),
                            title: const Text('连接配置'),
                            subtitle: const Text('API Keys & Tokens'),
                            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: _apiKeySpecs.map((spec) {
                              final controller = _apiKeyControllers[spec.key]!;
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: TextField(
                                  controller: controller,
                                  obscureText: true, // 隐藏 key
                                  decoration: InputDecoration(
                                    labelText: spec.label,
                                    hintText: spec.hint ?? '',
                                    helperText: spec.required ? '必填' : null,
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Theme.of(context).colorScheme.surface,
                                    isDense: true,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                      // 🏷️ Mode Selection (Chips)
                      if (modes.isNotEmpty) ...[
                        _SectionTitle(title: '浏览模式'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: modes.entries.map((e) {
                             final isSelected = currentMode == e.key;
                             return ChoiceChip(
                               label: Text(e.value),
                               selected: isSelected,
                               onSelected: (selected) {
                                 if (selected) {
                                   setState(() => _filters['mode'] = e.key);
                                 }
                               },
                             );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Dynamic Filters
                      if (schema.isNotEmpty) ...[
                        _SectionTitle(title: '筛选条件'),
                        const SizedBox(height: 16),
                        for (final f in schema) ..._buildField(f),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // 💾 Apply Button
            Positioned(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom, // 避让键盘
              child: FilledButton(
                onPressed: _apply,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('应用', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ); 
    },
    );
  }

  Future<void> _apply() async {
    // 保存 API Keys
    for (final spec in _apiKeySpecs) {
      final controller = _apiKeyControllers[spec.key];
      if (controller != null) {
        final value = controller.text.trim();
        if (value.isNotEmpty) {
          await widget.apiKeyStore.setApiKey(
            widget.sourceId,
            spec.key,
            value,
          );
        } else {
          await widget.apiKeyStore.removeApiKey(
            widget.sourceId,
            spec.key,
          );
        }
      }
    }
    
    if (!mounted) return;
    Navigator.of(context).pop(_filters);
  }

  // 构建单个筛选字段
  List<Widget> _buildField(dynamic raw) {
    if (raw is! Map) return const <Widget>[];
    final m = raw.cast<String, dynamic>();

    final key = (m['key'] ?? '').toString().trim();
    final type = (m['type'] ?? '').toString().trim();
    final label = (m['label'] ?? key).toString().trim();

    if (key.isEmpty || type.isEmpty) return const <Widget>[];

    switch (type) {
      case 'text':
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                filled: true,
                isDense: true,
              ),
              controller: TextEditingController(text: (_filters[key] ?? '').toString())
                ..selection = TextSelection.collapsed(offset: (_filters[key] ?? '').toString().length),
              onChanged: (v) {
                 final t = v.trim();
                 if (t.isEmpty) _filters.remove(key);
                 else _filters[key] = t;
                 // Note: not calling setState to avoid rebuild on every char
                 // But we need to keep the value in _filters
              },
            ),
          ),
        ];

      case 'bool':
        final bool def = (m['default'] as bool?) ?? false;
        final bool cur = _filters.containsKey(key) ? ((_filters[key] as bool?) ?? def) : def;

        return [
          SwitchListTile(
            title: Text(label),
            value: cur,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
            onChanged: (v) {
              setState(() => _filters[key] = v);
            },
          ),
          const SizedBox(height: 16),
        ];

      case 'enum':
        return _buildEnumField(key, label, m);

      default:
        return const <Widget>[];
    }
  }

  List<Widget> _buildEnumField(String key, String label, Map<String, dynamic> m) {
    final rawOptions = (m['options'] as List?) ?? const [];
    final List<Map<String, String>> options = [];
    
    for (final o in rawOptions) {
      if (o is String) {
        final v = o.trim();
        if (v.isNotEmpty) options.add({'value': v, 'label': v});
      } else if (o is Map) {
         final v = (o['value'] ?? '').toString().trim();
         final l = (o['label'] ?? v).toString().trim();
         if (v.isNotEmpty) options.add({'value': v, 'label': l.isEmpty ? v : l});
      }
    }
    if (options.isEmpty) return const [];

    final cur = (_filters[key] ?? '').toString().trim();

    // UI Configuration
    final rootUi = (widget.specRaw['filterUi'] is Map)
        ? (widget.specRaw['filterUi'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final enumDefaults = (rootUi['enum'] is Map)
        ? (rootUi['enum'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final fieldUi = (m['ui'] is Map)
        ? (m['ui'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    
    String pickStr(String k, String def) => (fieldUi[k] ?? enumDefaults[k] ?? def).toString();

    // 智能选择 UI：如果选项少且没有强制指定 layout，用 Chips
    final bool forceDropdown = pickStr('layout', '') == 'dropdown';
    final bool forceGrid = pickStr('layout', '') == 'grid';

    if (!forceDropdown && !forceGrid && options.length <= 6) {
      // 🏷️ Use Chips
      return [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final val = opt['value']!;
            final isSelected = cur == val;
            return ChoiceChip(
              label: Text(opt['label']!),
              selected: isSelected,
              onSelected: (selected) {
                 setState(() {
                   if (selected) _filters[key] = val;
                   else _filters.remove(key); // Optional: allow deselect? Usually radio behavior.
                 });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ];
    }

    // 🔽 Dropdown (for many options)
    return [
       DropdownButtonFormField<String>(
         decoration: InputDecoration(
           labelText: label,
           border: const OutlineInputBorder(),
           filled: true,
           isDense: true,
         ),
         value: cur.isEmpty ? null : cur,
         items: options.map((e) => DropdownMenuItem(
           value: e['value'],
           child: Text(e['label']!),
         )).toList(),
         onChanged: (v) {
           setState(() {
             if (v == null || v.isEmpty) _filters.remove(key);
             else _filters[key] = v;
           });
         },
       ),
       const SizedBox(height: 16),
    ];
  }

  // 浮动保存按钮不需要在这里构建，我们在 DraggableScrollableSheet 外部或者作为一个覆盖层
  // 但为了简单，我们把它放在 BuildContext 里，通过 Stack 浮动在列表之上。
  // 不过 DraggableScrollableSheet 的 child 本身就是一个 ScrollView。
  // 我们可以在 Column 底部加一个 Container。
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
