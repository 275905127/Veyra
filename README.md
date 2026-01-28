# Veyra

**一个基于插件扩展的 Flutter 壁纸聚合应用**

Veyra 是一个现代化的 Android 壁纸浏览应用，支持通过 JavaScript 插件扩展图源，让您可以轻松访问多个壁纸平台的内容。

## ✨ 特性

- 📱 **现代化 UI**: 使用 Material 3 设计，流畅的瀑布流布局
- 🔌 **插件化架构**: 通过 JavaScript 引擎包（Engine Pack）扩展图源
- 🎨 **强大的筛选**: 支持多种筛选条件（模式、枚举、文本、布尔值）
- 🔑 **灵活的 API Key 管理**: 按图源存储 API Key，支持需要认证的图源
- 🌐 **国际化支持**: 内置中英文支持
- 📝 **日志系统**: 完善的日志记录，方便调试

## 🚀 快速开始

### 环境要求

- Flutter SDK >= 3.3.0
- Dart SDK >= 3.3.0 < 4.0.0

### 安装

```bash
# 克隆项目
git clone https://github.com/yourusername/veyra.git
cd veyra

#安装依赖
flutter pub get

# 运行应用
flutter run
```

## 🔧 插件开发

Veyra 通过引擎包（Engine Pack）扩展图源。每个引擎包是一个包含 `manifest.json` 和 JavaScript 代码的 ZIP 文件。

### Manifest 格式

```json
{
  "id": "wallhaven_pack",
  "name": "Wallhaven Engine",
  "version": "1.0.0",
  "entry": "main.js",
  "domains": ["wallhaven.cc"],
  "apiKeys": [
    {
      "key": "wallhaven_key",
      "label": "Wallhaven API Key",
      "hint": "在 wallhaven.cc/settings/account 获取",
      "required": false
    }
  ],
  "sources": [
    {
      "id": "wallhaven",
      "name": "Wallhaven",
      "ref": "wallhaven"
    }
  ]
}
```

### JavaScript API

引擎包需要实现两个函数：

#### `buildRequests(params)`

构建网络请求。

**参数**:
- `params.page`: 页码（从1开始）
- `params.keyword`: 搜索关键词
- `params.mode`: 模式
- `params.filters`: 筛选条件
- API Keys 会自动注入到 params

**返回**: 请求数组
```javascript
[
  {
    "method": "GET",
    "url": "https://api.example.com/wallpapers",
    "headers": {"Authorization": "Bearer xxx"},
    "body": null
  }
]
```

#### `parseList(params, responses)`

解析响应数据。

**参数**:
- `params`: 与 buildRequests 相同
- `responses`: 响应数组
  ```javascript
  [
    {
      "statusCode": 200,
      "body": "{...}"  // JSON字符串
    }
  ]
  ```

**返回**: 壁纸数组
```javascript
[
  {
    "id": "unique-id",
    "thumbUrl": "https://...",
    "fullUrl": "https://...",
    "width": 1920,
    "height": 1080
  }
]
```

### 示例插件

查看 `examples/` 目录获取完整的插件示例。

## 📦 依赖

主要依赖：
- `provider`: 状态管理
- `dio`: 网络请求
- `flutter_js`: JavaScript 运行时
- `cached_network_image`: 图片缓存
- `flutter_staggered_grid_view`: 瀑布流布局
- `shared_preferences`: 本地存储
- `file_picker`: 文件选择
- `archive`: ZIP 解压

## 🏗️ 架构

```
lib/
├── app/              # 应用入口
├── core/             # 核心业务逻辑
│   ├── engine/       # 规则引擎
│   ├── exceptions/   # 异常定义
│   ├── extension/    # 扩展引擎（JS Runtime）
│   ├── models/       # 数据模型
│   ├── services/     # 业务服务
│   └── storage/      # 本地存储
├── features/         # 功能模块
│   ├── browse/       # 浏览壁纸
│   ├── manage/       # 管理图源
│   ├── settings/     # 设置
│   └── ...
└── l10n/             # 国际化资源
```

## 🛠️ 开发

```bash
# 代码分析
flutter analyze

# 运行测试
flutter test

# 构建 APK
flutter build apk --release
```

## 📝 更新日志

### v0.1.1 (2026-01-28)

- ✅ JS 运行时缓存优化，提升插件执行性能
- ✅ 请求取消支持，避免竞态和资源浪费
- ✅ 添加单元测试 (44 个测试用例)
- ✅ 升级 Lint 配置，启用更多代码规范检查
- ✅ Android 构建配置优化

### v0.1.0 (2026-01-28)

- ✅ 基础壁纸浏览功能
- ✅ 插件化图源扩展
- ✅ API Key 按图源管理
- ✅ 统一异常处理
- ✅ 内存泄漏修复
- ✅ 并发安全改进

## 🤝 贡献

欢迎贡献！请查看 [贡献指南](CONTRIBUTING.md)。

## 📄 许可证

MIT License

## 🙏 致谢

感谢所有开源项目的贡献者。
