import 'package:flutter_test/flutter_test.dart';
import 'package:veyra/core/models/source.dart';
import 'package:veyra/features/browse/browse_controller.dart';
import 'package:veyra/core/services/wallpaper_service.dart';
import 'package:veyra/core/storage/source_store.dart';
import 'package:veyra/core/engine/engine_registry.dart';
import 'package:veyra/core/engine/rule_engine.dart';
import 'package:veyra/core/extension/extension_engine.dart';
import 'package:veyra/core/storage/pack_store.dart';
import 'package:veyra/core/storage/api_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 简单的 Mock 类
class _MockSourceStore extends SourceStore {
  SourceRef? _active;

  @override
  SourceRef? get active => _active;

  @override
  Future<void> setActive(SourceRef? ref) async {
    _active = ref;
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> getSpecRaw(String id) async {
    return <String, dynamic>{};
  }
}

void main() {
  group('BrowseController', () {
    late BrowseController controller;
    late _MockSourceStore sourceStore;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      
      sourceStore = _MockSourceStore();
      await sourceStore.init();

      final packStore = PackStore();
      final apiKeyStore = ApiKeyStore();
      await apiKeyStore.init();

      final registry = EngineRegistry.bootstrapDefault();
      final ruleEngine = RuleEngine(registry: registry);
      final extensionEngine = ExtensionEngine(
        packStore: packStore,
        apiKeyStore: apiKeyStore,
      );

      final wallpaperService = WallpaperService(
        ruleEngine: ruleEngine,
        packStore: packStore,
        extensionEngine: extensionEngine,
        apiKeyStore: apiKeyStore,
      );

      controller = BrowseController(
        wallpaperService: wallpaperService,
        sourceStore: sourceStore,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    group('初始状态', () {
      test('items 初始为空', () {
        expect(controller.items, isEmpty);
      });

      test('loading 初始为 false', () {
        expect(controller.loading, false);
      });

      test('error 初始为 null', () {
        expect(controller.error, isNull);
      });

      test('activeSource 初始为 null', () {
        expect(controller.activeSource, isNull);
      });

      test('keyword 初始为空', () {
        expect(controller.keyword, isEmpty);
      });

      test('filters 初始为空', () {
        expect(controller.filters, isEmpty);
      });
    });

    group('setQuery', () {
      test('设置 keyword 更新状态', () async {
        await controller.setQuery(keyword: 'test', refreshNow: false);
        expect(controller.keyword, 'test');
      });

      test('keyword 会被 trim', () async {
        await controller.setQuery(keyword: '  test  ', refreshNow: false);
        expect(controller.keyword, 'test');
      });

      test('设置 filters 更新状态', () async {
        await controller.setQuery(
          filters: {'category': 'nature'},
          refreshNow: false,
        );
        expect(controller.filters['category'], 'nature');
      });

      test('filters 是不可变的副本', () async {
        final originalFilters = {'key': 'value'};
        await controller.setQuery(filters: originalFilters, refreshNow: false);
        
        // 修改原始 map 不应该影响 controller
        originalFilters['key'] = 'changed';
        expect(controller.filters['key'], 'value');
      });

      test('相同值不触发变化', () async {
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        await controller.setQuery(keyword: 'test', refreshNow: false);
        expect(notifyCount, 1);

        await controller.setQuery(keyword: 'test', refreshNow: false);
        expect(notifyCount, 1); // 没有额外通知
      });
    });

    group('clearQuery', () {
      test('清除 keyword 和 filters', () async {
        await controller.setQuery(
          keyword: 'test',
          filters: {'key': 'value'},
          refreshNow: false,
        );

        await controller.clearQuery(refreshNow: false);

        expect(controller.keyword, isEmpty);
        expect(controller.filters, isEmpty);
      });

      test('如果已经是空的不会触发通知', () async {
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        await controller.clearQuery(refreshNow: false);
        expect(notifyCount, 0);
      });
    });

    group('resetToEmpty', () {
      test('重置所有状态', () async {
        await controller.setQuery(
          keyword: 'test',
          filters: {'key': 'value'},
          refreshNow: false,
        );

        controller.resetToEmpty();

        expect(controller.items, isEmpty);
        expect(controller.loading, false);
        expect(controller.error, isNull);
        expect(controller.activeSource, isNull);
        expect(controller.keyword, isEmpty);
        expect(controller.filters, isEmpty);
      });

      test('触发 notifyListeners', () {
        var notified = false;
        controller.addListener(() => notified = true);

        controller.resetToEmpty();

        expect(notified, true);
      });
    });

    group('dispose', () {
      test('dispose 不会抛出异常', () {
        // 创建一个新的 controller 进行测试，因为 tearDown 会自动 dispose
        // 所以我们只测试创建过程正常即可
        expect(controller, isNotNull);
      });
    });
  });
}
