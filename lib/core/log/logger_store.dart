import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel { debug, info, warn, error }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;
  final String? details;

  LogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.details,
  });
}

class LoggerStore extends ChangeNotifier {
  static const String _kEnabled = 'logger.enabled';
  static const int _kMaxEntries = 800;

  SharedPreferences? _sp;

  bool _enabled = false;
  bool get enabled => _enabled;

  final List<LogEntry> _items = <LogEntry>[];
  List<LogEntry> get items => List.unmodifiable(_items);

  Future<void> init() async {
    _sp ??= await SharedPreferences.getInstance();
    _enabled = _sp!.getBool(_kEnabled) ?? false;
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final sp = await _ensure();
    await sp.setBool(_kEnabled, v);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  void d(String tag, String msg, {String? details}) => _add(LogLevel.debug, tag, msg, details);
  void i(String tag, String msg, {String? details}) => _add(LogLevel.info, tag, msg, details);
  void w(String tag, String msg, {String? details}) => _add(LogLevel.warn, tag, msg, details);
  void e(String tag, String msg, {String? details}) => _add(LogLevel.error, tag, msg, details);

  void _add(LogLevel level, String tag, String msg, String? details) {
    if (!_enabled) return;

    _items.add(
      LogEntry(
        time: DateTime.now(),
        level: level,
        tag: tag,
        message: msg,
        details: details,
      ),
    );

    if (_items.length > _kMaxEntries) {
      _items.removeRange(0, _items.length - _kMaxEntries);
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print('[${level.name}] $tag: $msg${details == null ? '' : '\n$details'}');
    }

    notifyListeners();
  }

  Future<SharedPreferences> _ensure() async {
    _sp ??= await SharedPreferences.getInstance();
    return _sp!;
  }
}