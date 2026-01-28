import 'package:flutter/foundation.dart';
import 'package:veyra/core/log/logger_store.dart';
import 'package:veyra/core/models/engine_pack.dart';
import 'package:veyra/core/models/source.dart';
import 'package:veyra/core/storage/api_key_store.dart';
import 'package:veyra/core/storage/pack_store.dart';
import 'package:veyra/core/storage/source_store.dart';

/// Mock PackStore for testing
class MockPackStore extends PackStore {
  final List<EnginePack> _packs;
  
  MockPackStore([List<EnginePack>? packs]) : _packs = packs ?? [];

  @override
  Future<List<EnginePack>> list() async => _packs;
}

/// Mock SourceStore for testing
class MockSourceStore extends SourceStore {
  final Map<String, Map<String, dynamic>> _specs;
  SourceRef? _activeRef;

  MockSourceStore([Map<String, Map<String, dynamic>>? specs]) 
      : _specs = specs ?? {};

  @override
  SourceRef? get active => _activeRef;

  @override
  Future<Map<String, dynamic>> getSpecRaw(String id) async {
    return _specs[id] ?? const <String, dynamic>{};
  }

  @override
  Future<void> setActive(SourceRef? ref) async {
    _activeRef = ref;
    notifyListeners();
  }
}

/// Mock ApiKeyStore for testing
class MockApiKeyStore extends ChangeNotifier implements ApiKeyStore {
  final Map<String, Map<String, String>> _keys = {};

  @override
  Future<void> init() async {}

  @override
  Future<String?> getApiKey(String sourceId, String keyName) async {
    return _keys[sourceId]?[keyName];
  }

  @override
  Future<void> setApiKey(String sourceId, String keyName, String value) async {
    _keys.putIfAbsent(sourceId, () => {});
    if (value.trim().isEmpty) {
      _keys[sourceId]!.remove(keyName);
    } else {
      _keys[sourceId]![keyName] = value.trim();
    }
    notifyListeners();
  }

  @override
  Future<void> removeApiKey(String sourceId, String keyName) async {
    _keys[sourceId]?.remove(keyName);
    notifyListeners();
  }

  @override
  Future<Map<String, String>> getAllKeys(String sourceId) async {
    return Map<String, String>.from(_keys[sourceId] ?? {});
  }

  @override
  Future<void> clearAllKeys(String sourceId) async {
    _keys.remove(sourceId);
    notifyListeners();
  }
}

/// Mock LoggerStore for testing (captures logs for verification)
class MockLoggerStore extends LoggerStore {
  final List<LogEntry> capturedLogs = [];

  @override
  Future<void> init() async {}

  @override
  void i(String tag, String message, {String? details}) {
    capturedLogs.add(LogEntry(level: 'I', tag: tag, message: message, details: details));
  }

  @override
  void d(String tag, String message, {String? details}) {
    capturedLogs.add(LogEntry(level: 'D', tag: tag, message: message, details: details));
  }

  @override
  void w(String tag, String message, {String? details}) {
    capturedLogs.add(LogEntry(level: 'W', tag: tag, message: message, details: details));
  }

  @override
  void e(String tag, String message, {String? details}) {
    capturedLogs.add(LogEntry(level: 'E', tag: tag, message: message, details: details));
  }

  void clearLogs() {
    capturedLogs.clear();
  }
}

class LogEntry {
  final String level;
  final String tag;
  final String message;
  final String? details;

  LogEntry({
    required this.level,
    required this.tag,
    required this.message,
    this.details,
  });

  @override
  String toString() => '[$level] $tag: $message${details != null ? ' ($details)' : ''}';
}
