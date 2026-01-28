// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SEn extends S {
  SEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Veyra';

  @override
  String get tabBrowse => 'Browse';

  @override
  String get tabManage => 'Manage';

  @override
  String get tabSettings => 'Settings';

  @override
  String get actionSearch => 'Search';

  @override
  String get actionRefresh => 'Refresh';

  @override
  String get actionImport => 'Import';

  @override
  String get browseTitle => 'Wallpapers';

  @override
  String get manageTitle => 'Manage';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get manageSourceTypeRule => 'Rule source';

  @override
  String get manageSourceTypeExtension => 'Engine-pack source';

  @override
  String get managePackDomains => 'Domains';

  @override
  String get managePackUninstall => 'Uninstall';

  @override
  String get snackInstalled => 'Installed';

  @override
  String get snackUninstalled => 'Uninstalled';

  @override
  String get manageSectionSources => 'Sources';

  @override
  String get manageSectionPacks => 'Engine packs';

  @override
  String get emptyNoSourcesTitle => 'No sources';

  @override
  String get emptyNoSourcesBody =>
      'Import engine packs in “Manage”, or add a source spec.';

  @override
  String get emptyNoPacksTitle => 'No engine packs';

  @override
  String get emptyNoPacksBody =>
      'Tap “Import” to install a .zip / .enginepack.';

  @override
  String get errorGenericTitle => 'Something went wrong';

  @override
  String get errorRetry => 'Retry';

  @override
  String get settingsSectionGeneral => 'General';

  @override
  String get settingsClearCache => 'Clear cache';

  @override
  String get settingsSectionDebug => 'Debug';

  @override
  String get settingsEnableLogs => 'Enable logs';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsVersion => 'Version';
}
