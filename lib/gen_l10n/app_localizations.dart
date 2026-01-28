import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of S
/// returned by `S.of(context)`.
///
/// Applications need to include `S.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen_l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: S.localizationsDelegates,
///   supportedLocales: S.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the S.supportedLocales
/// property.
abstract class S {
  S(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static S of(BuildContext context) {
    return Localizations.of<S>(context, S)!;
  }

  static const LocalizationsDelegate<S> delegate = _SDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Veyra'**
  String get appName;

  /// No description provided for @tabBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get tabBrowse;

  /// No description provided for @tabManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get tabManage;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @actionSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get actionSearch;

  /// No description provided for @actionRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get actionRefresh;

  /// No description provided for @actionImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get actionImport;

  /// No description provided for @browseTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallpapers'**
  String get browseTitle;

  /// No description provided for @manageTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manageTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @manageSourceTypeRule.
  ///
  /// In en, this message translates to:
  /// **'Rule source'**
  String get manageSourceTypeRule;

  /// No description provided for @manageSourceTypeExtension.
  ///
  /// In en, this message translates to:
  /// **'Engine-pack source'**
  String get manageSourceTypeExtension;

  /// No description provided for @managePackDomains.
  ///
  /// In en, this message translates to:
  /// **'Domains'**
  String get managePackDomains;

  /// No description provided for @managePackUninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get managePackUninstall;

  /// No description provided for @snackInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get snackInstalled;

  /// No description provided for @snackUninstalled.
  ///
  /// In en, this message translates to:
  /// **'Uninstalled'**
  String get snackUninstalled;

  /// No description provided for @manageSectionSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get manageSectionSources;

  /// No description provided for @manageSectionPacks.
  ///
  /// In en, this message translates to:
  /// **'Engine packs'**
  String get manageSectionPacks;

  /// No description provided for @emptyNoSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'No sources'**
  String get emptyNoSourcesTitle;

  /// No description provided for @emptyNoSourcesBody.
  ///
  /// In en, this message translates to:
  /// **'Import engine packs in “Manage”, or add a source spec.'**
  String get emptyNoSourcesBody;

  /// No description provided for @emptyNoPacksTitle.
  ///
  /// In en, this message translates to:
  /// **'No engine packs'**
  String get emptyNoPacksTitle;

  /// No description provided for @emptyNoPacksBody.
  ///
  /// In en, this message translates to:
  /// **'Tap “Import” to install a .zip / .enginepack.'**
  String get emptyNoPacksBody;

  /// No description provided for @errorGenericTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGenericTitle;

  /// No description provided for @errorRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get errorRetry;

  /// No description provided for @settingsSectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsSectionGeneral;

  /// No description provided for @settingsClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get settingsClearCache;

  /// No description provided for @settingsSectionDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get settingsSectionDebug;

  /// No description provided for @settingsEnableLogs.
  ///
  /// In en, this message translates to:
  /// **'Enable logs'**
  String get settingsEnableLogs;

  /// No description provided for @settingsSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return SEn();
    case 'zh':
      return SZh();
  }

  throw FlutterError(
      'S.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
