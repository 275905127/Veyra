/// API Key 规范
class ApiKeySpec {
  /// Key 名称（例如：wallhaven_key）
  final String key;

  /// 显示标签（例如：Wallhaven API Key）
  final String label;

  /// 提示信息（例如：在 wallhaven.cc/settings/account 获取）
  final String? hint;

  /// 是否必填
  final bool required;

  const ApiKeySpec({
    required this.key,
    required this.label,
    this.hint,
    this.required = false,
  });

  factory ApiKeySpec.fromMap(Map<String, dynamic> m) => ApiKeySpec(
        key: (m['key'] ?? '').toString(),
        label: (m['label'] ?? '').toString(),
        hint: (m['hint'] as String?)?.trim(),
        required: (m['required'] as bool?) ?? false,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'key': key,
        'label': label,
        if (hint != null) 'hint': hint,
        'required': required,
      };
}

class EnginePack {
  final String id;
  final String name;
  final String version;
  final String entry;
  final List<String> domains;
  
  /// API Keys 声明（从 manifest.apiKeys 读取）
  final List<ApiKeySpec> apiKeys;

  const EnginePack({
    required this.id,
    required this.name,
    required this.version,
    required this.entry,
    required this.domains,
    this.apiKeys = const <ApiKeySpec>[],
  });

  /// 从 manifest.json 构造（引擎包规范）
  ///
  /// 支持两种 domains 写法：
  /// 1) manifest['permissions']['domains']
  /// 2) manifest['domains']
  factory EnginePack.fromManifest(Map<String, dynamic> m) {
    final perms = (m['permissions'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

    final domains1 = (perms['domains'] as List?)?.map((e) => e.toString()).toList();
    final domains2 = (m['domains'] as List?)?.map((e) => e.toString()).toList();

    final domains = (domains1 ?? domains2 ?? const <String>[])
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false);

    // 读取 apiKeys 声明
    final apiKeysList = (m['apiKeys'] as List?) ?? const [];
    final apiKeys = apiKeysList
        .whereType<Map>()
        .map((e) => ApiKeySpec.fromMap(e.cast<String, dynamic>()))
        .toList(growable: false);

    return EnginePack(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      version: (m['version'] ?? '0.0.0').toString(),
      entry: (m['entry'] ?? 'main.js').toString(),
      domains: domains,
      apiKeys: apiKeys,
    );
  }

  /// 持久化到 SharedPreferences 用
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'version': version,
        'entry': entry,
        'domains': domains,
        'apiKeys': apiKeys.map((e) => e.toMap()).toList(),
      };

  /// 从持久化 Map 反序列化
  factory EnginePack.fromMap(Map<String, dynamic> m) {
    final apiKeysList = (m['apiKeys'] as List?) ?? const [];
    final apiKeys = apiKeysList
        .whereType<Map>()
        .map((e) => ApiKeySpec.fromMap(e.cast<String, dynamic>()))
        .toList(growable: false);

    return EnginePack(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      version: (m['version'] ?? '0.0.0').toString(),
      entry: (m['entry'] ?? 'main.js').toString(),
      domains: (m['domains'] as List?)?.map((e) => e.toString()).toList(growable: false) ?? const <String>[],
      apiKeys: apiKeys,
    );
  }
}