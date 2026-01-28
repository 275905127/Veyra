// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class SZh extends S {
  SZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'Veyra';

  @override
  String get tabBrowse => '浏览';

  @override
  String get tabManage => '管理';

  @override
  String get tabSettings => '设置';

  @override
  String get actionSearch => '搜索';

  @override
  String get actionRefresh => '刷新';

  @override
  String get actionImport => '导入';

  @override
  String get browseTitle => '壁纸';

  @override
  String get manageTitle => '管理';

  @override
  String get settingsTitle => '设置';

  @override
  String get manageSourceTypeRule => '规则图源';

  @override
  String get manageSourceTypeExtension => '引擎包图源';

  @override
  String get managePackDomains => '域名';

  @override
  String get managePackUninstall => '卸载';

  @override
  String get snackInstalled => '已安装';

  @override
  String get snackUninstalled => '已卸载';

  @override
  String get manageSectionSources => '图源';

  @override
  String get manageSectionPacks => '引擎包';

  @override
  String get emptyNoSourcesTitle => '暂无图源';

  @override
  String get emptyNoSourcesBody => '请在“管理”中导入引擎包，或添加图源配置。';

  @override
  String get emptyNoPacksTitle => '暂无引擎包';

  @override
  String get emptyNoPacksBody => '点击右上角“导入”，安装一个 .zip / .enginepack。';

  @override
  String get errorGenericTitle => '出错了';

  @override
  String get errorRetry => '重试';

  @override
  String get settingsSectionGeneral => '常用';

  @override
  String get settingsClearCache => '清理缓存';

  @override
  String get settingsSectionDebug => '验证与调试';

  @override
  String get settingsEnableLogs => '启用日志';

  @override
  String get settingsSectionAbout => '关于';

  @override
  String get settingsVersion => '版本';
}
