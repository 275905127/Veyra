import 'package:flutter_test/flutter_test.dart';
import 'package:veyra/core/storage/api_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ApiKeyStore', () {
    late ApiKeyStore store;

    setUp(() async {
      // 设置 SharedPreferences 的 mock 值
      SharedPreferences.setMockInitialValues({});
      store = ApiKeyStore();
      await store.init();
    });

    group('基本操作', () {
      test('setApiKey 和 getApiKey 正常工作', () async {
        await store.setApiKey('source1', 'api_key', 'test_value');
        
        final result = await store.getApiKey('source1', 'api_key');
        expect(result, 'test_value');
      });

      test('getApiKey 对不存在的 key 返回 null', () async {
        final result = await store.getApiKey('nonexistent', 'key');
        expect(result, isNull);
      });

      test('setApiKey 空值时删除 key', () async {
        await store.setApiKey('source1', 'key', 'value');
        expect(await store.getApiKey('source1', 'key'), 'value');

        await store.setApiKey('source1', 'key', '');
        expect(await store.getApiKey('source1', 'key'), isNull);
      });

      test('setApiKey 会 trim 空白字符', () async {
        await store.setApiKey('source1', 'key', '  trimmed  ');
        
        final result = await store.getApiKey('source1', 'key');
        expect(result, 'trimmed');
      });

      test('removeApiKey 删除指定 key', () async {
        await store.setApiKey('source1', 'key', 'value');
        await store.removeApiKey('source1', 'key');
        
        expect(await store.getApiKey('source1', 'key'), isNull);
      });
    });

    group('批量操作', () {
      test('getAllKeys 返回指定图源的所有 keys', () async {
        await store.setApiKey('source1', 'key1', 'value1');
        await store.setApiKey('source1', 'key2', 'value2');
        await store.setApiKey('source2', 'key3', 'value3');

        final keys = await store.getAllKeys('source1');
        
        expect(keys.length, 2);
        expect(keys['key1'], 'value1');
        expect(keys['key2'], 'value2');
        expect(keys.containsKey('key3'), false);
      });

      test('getAllKeys 对空图源返回空 Map', () async {
        final keys = await store.getAllKeys('empty_source');
        expect(keys, isEmpty);
      });

      test('clearAllKeys 清除指定图源的所有 keys', () async {
        await store.setApiKey('source1', 'key1', 'value1');
        await store.setApiKey('source1', 'key2', 'value2');
        await store.setApiKey('source2', 'key3', 'value3');

        await store.clearAllKeys('source1');

        expect(await store.getAllKeys('source1'), isEmpty);
        expect(await store.getApiKey('source2', 'key3'), 'value3');
      });
    });

    group('图源隔离', () {
      test('不同图源的相同 key 名互不影响', () async {
        await store.setApiKey('source1', 'api_key', 'value1');
        await store.setApiKey('source2', 'api_key', 'value2');

        expect(await store.getApiKey('source1', 'api_key'), 'value1');
        expect(await store.getApiKey('source2', 'api_key'), 'value2');
      });

      test('删除一个图源的 key 不影响其他图源', () async {
        await store.setApiKey('source1', 'key', 'value1');
        await store.setApiKey('source2', 'key', 'value2');

        await store.removeApiKey('source1', 'key');

        expect(await store.getApiKey('source1', 'key'), isNull);
        expect(await store.getApiKey('source2', 'key'), 'value2');
      });
    });

    group('ChangeNotifier', () {
      test('setApiKey 触发 notifyListeners', () async {
        var notified = false;
        store.addListener(() => notified = true);

        await store.setApiKey('source', 'key', 'value');
        
        expect(notified, true);
      });

      test('removeApiKey 触发 notifyListeners', () async {
        await store.setApiKey('source', 'key', 'value');
        
        var notified = false;
        store.addListener(() => notified = true);

        await store.removeApiKey('source', 'key');
        
        expect(notified, true);
      });

      test('clearAllKeys 仅在有数据删除时触发 notifyListeners', () async {
        await store.setApiKey('source', 'key', 'value');
        
        var notifyCount = 0;
        store.addListener(() => notifyCount++);

        await store.clearAllKeys('source');
        expect(notifyCount, 1);

        // 再次清空应该不触发（已经空了）
        await store.clearAllKeys('source');
        expect(notifyCount, 1);
      });
    });
  });
}
