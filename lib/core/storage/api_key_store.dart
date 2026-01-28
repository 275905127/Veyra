import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// API Key 存储（按图源 ID 存储）
///
/// 每个图源可以有多个 API Key
/// 存储格式：apikey.<sourceId>.<keyName> = value
///
/// 例如：
///   apikey.wallhaven.apikey = "xxxx"
///   apikey.pixiv.cookie = "PHPSESSID=xxx;"
class ApiKeyStore extends ChangeNotifier {
  static const String _prefix = 'apikey.';

  SharedPreferences? _sp;

  Future<void> init() async {
    _sp ??= await SharedPreferences.getInstance();
    
    // 数据迁移：将旧的全局 API Key 迁移到对应图源
    await _migrateOldKeys();
  }

  /// 迁移旧的全局 API Key 到图源级
  Future<void> _migrateOldKeys() async {
    final sp = _sp;
    if (sp == null) return;

    // 迁移 wallhaven_v1 -> wallhaven.wallhaven_key
    final oldWallhaven = sp.getString('${_prefix}wallhaven_v1');
    if (oldWallhaven != null && oldWallhaven.isNotEmpty) {
      await setApiKey('wallhaven', 'wallhaven_key', oldWallhaven);
      await sp.remove('${_prefix}wallhaven_v1');
    }

    // 迁移 pixiv_ajax_v1 -> pixiv.pixiv_cookie
    final oldPixiv = sp.getString('${_prefix}pixiv_ajax_v1');
    if (oldPixiv != null && oldPixiv.isNotEmpty) {
      await setApiKey('pixiv', 'pixiv_cookie', oldPixiv);
      await sp.remove('${_prefix}pixiv_ajax_v1');
    }
  }

  String _key(String sourceId, String keyName) => '$_prefix$sourceId.$keyName';

  /// 获取某个图源的某个 API Key
  Future<String?> getApiKey(String sourceId, String keyName) async {
    _sp ??= await SharedPreferences.getInstance();
    return _sp!.getString(_key(sourceId, keyName));
  }

  /// 设置某个图源的某个 API Key
  Future<void> setApiKey(String sourceId, String keyName, String value) async {
    _sp ??= await SharedPreferences.getInstance();
    final v = value.trim();
    if (v.isEmpty) {
      await _sp!.remove(_key(sourceId, keyName));
    } else {
      await _sp!.setString(_key(sourceId, keyName), v);
    }
    notifyListeners();
  }

  /// 删除某个图源的某个 API Key
  Future<void> removeApiKey(String sourceId, String keyName) async {
    _sp ??= await SharedPreferences.getInstance();
    await _sp!.remove(_key(sourceId, keyName));
    notifyListeners();
  }

  /// 获取某个图源的所有 API Keys
  Future<Map<String, String>> getAllKeys(String sourceId) async {
    _sp ??= await SharedPreferences.getInstance();
    final result = <String, String>{};
    final prefix = '$_prefix$sourceId.';
    
    for (final key in _sp!.getKeys()) {
      if (key.startsWith(prefix)) {
        final keyName = key.substring(prefix.length);
        final value = _sp!.getString(key);
        if (value != null && value.isNotEmpty) {
          result[keyName] = value;
        }
      }
    }
    
    return result;
  }

  /// 清空某个图源的所有 API Keys
  Future<void> clearAllKeys(String sourceId) async {
    _sp ??= await SharedPreferences.getInstance();
    final prefix = '$_prefix$sourceId.';
    final keysToRemove = _sp!.getKeys().where((k) => k.startsWith(prefix)).toList();
    
    for (final key in keysToRemove) {
      await _sp!.remove(key);
    }
    
    if (keysToRemove.isNotEmpty) {
      notifyListeners();
    }
  }
}