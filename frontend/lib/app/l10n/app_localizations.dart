import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
    Locale('zh'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'OmniNest'**
  String get appName;

  /// No description provided for @mobileNavHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get mobileNavHome;

  /// No description provided for @mobileNavFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get mobileNavFiles;

  /// No description provided for @mobileNavMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get mobileNavMusic;

  /// No description provided for @mobileNavVisual.
  ///
  /// In en, this message translates to:
  /// **'Visual'**
  String get mobileNavVisual;

  /// No description provided for @mobileNavReader.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get mobileNavReader;

  /// No description provided for @mobileActivityCenter.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get mobileActivityCenter;

  /// No description provided for @mobileOfflineBanner.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Some actions are unavailable.'**
  String get mobileOfflineBanner;

  /// No description provided for @fullscreenEnterShortcut.
  ///
  /// In en, this message translates to:
  /// **'Full screen (F11)'**
  String get fullscreenEnterShortcut;

  /// No description provided for @fullscreenExitShortcut.
  ///
  /// In en, this message translates to:
  /// **'Exit full screen (F11)'**
  String get fullscreenExitShortcut;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search files, books, videos…'**
  String get searchHint;

  /// No description provided for @searchEmptyQuery.
  ///
  /// In en, this message translates to:
  /// **'Enter keywords to start searching'**
  String get searchEmptyQuery;

  /// No description provided for @searchEmptyResult.
  ///
  /// In en, this message translates to:
  /// **'No matching results found'**
  String get searchEmptyResult;

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed'**
  String get searchFailed;

  /// No description provided for @searchScopeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get searchScopeAll;

  /// No description provided for @searchGroupFile.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get searchGroupFile;

  /// No description provided for @searchGroupBook.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get searchGroupBook;

  /// No description provided for @searchGroupVideo.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get searchGroupVideo;

  /// No description provided for @searchGroupMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get searchGroupMusic;

  /// No description provided for @searchGroupPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get searchGroupPhoto;

  /// No description provided for @tasksTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasksTitle;

  /// No description provided for @tasksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tasks'**
  String get tasksEmpty;

  /// No description provided for @tasksEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'System tasks will appear here'**
  String get tasksEmptyHint;

  /// No description provided for @tasksFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tasksFilterAll;

  /// No description provided for @tasksFilterPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get tasksFilterPending;

  /// No description provided for @tasksFilterRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get tasksFilterRunning;

  /// No description provided for @tasksFilterCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get tasksFilterCompleted;

  /// No description provided for @tasksFilterFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get tasksFilterFailed;

  /// No description provided for @tasksRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get tasksRetry;

  /// No description provided for @tasksStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get tasksStatusPending;

  /// No description provided for @tasksStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get tasksStatusRunning;

  /// No description provided for @tasksStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get tasksStatusCompleted;

  /// No description provided for @tasksStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get tasksStatusFailed;

  /// No description provided for @tasksRetryCount.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get tasksRetryCount;

  /// No description provided for @tasksRetryProgress.
  ///
  /// In en, this message translates to:
  /// **'Retries: {current}/{maximum}'**
  String tasksRetryProgress(Object current, Object maximum);

  /// No description provided for @tasksStatusRetryWait.
  ///
  /// In en, this message translates to:
  /// **'Waiting to retry'**
  String get tasksStatusRetryWait;

  /// No description provided for @tasksStatusNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get tasksStatusNeedsAttention;

  /// No description provided for @tasksStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get tasksStatusCancelled;

  /// No description provided for @tasksPhasePlanning.
  ///
  /// In en, this message translates to:
  /// **'Planning resource deletion'**
  String get tasksPhasePlanning;

  /// No description provided for @tasksPhaseDeletingObjects.
  ///
  /// In en, this message translates to:
  /// **'Deleting object data'**
  String get tasksPhaseDeletingObjects;

  /// No description provided for @tasksPhaseVerifyingReferences.
  ///
  /// In en, this message translates to:
  /// **'Checking resource references'**
  String get tasksPhaseVerifyingReferences;

  /// No description provided for @tasksPhaseFinalizingDatabase.
  ///
  /// In en, this message translates to:
  /// **'Cleaning up business data'**
  String get tasksPhaseFinalizingDatabase;

  /// No description provided for @tasksPhaseWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for progress'**
  String get tasksPhaseWaiting;

  /// No description provided for @tasksTimeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get tasksTimeJustNow;

  /// No description provided for @tasksTimeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String tasksTimeMinutesAgo(Object count);

  /// No description provided for @tasksTimeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} hr ago'**
  String tasksTimeHoursAgo(Object count);

  /// No description provided for @tasksTimeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String tasksTimeDaysAgo(Object count);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String settingsLoadFailed(Object error);

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get settingsLanguageChinese;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsNotification.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotification;

  /// No description provided for @settingsNotificationEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable notifications'**
  String get settingsNotificationEnable;

  /// No description provided for @settingsNotificationEnableHint.
  ///
  /// In en, this message translates to:
  /// **'Receive push notifications'**
  String get settingsNotificationEnableHint;

  /// No description provided for @settingsEmailNotification.
  ///
  /// In en, this message translates to:
  /// **'Email notifications'**
  String get settingsEmailNotification;

  /// No description provided for @settingsEmailNotificationHint.
  ///
  /// In en, this message translates to:
  /// **'Receive important notifications via email'**
  String get settingsEmailNotificationHint;

  /// No description provided for @settingsSyncOffline.
  ///
  /// In en, this message translates to:
  /// **'Sync and offline'**
  String get settingsSyncOffline;

  /// No description provided for @settingsSyncOfflineHint.
  ///
  /// In en, this message translates to:
  /// **'Manage online sync status and offline content'**
  String get settingsSyncOfflineHint;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security and devices'**
  String get settingsSecurity;

  /// No description provided for @settingsSecurityHint.
  ///
  /// In en, this message translates to:
  /// **'Manage your password and active sessions'**
  String get settingsSecurityHint;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About OmniNest'**
  String get settingsAbout;

  /// No description provided for @settingsAboutHint.
  ///
  /// In en, this message translates to:
  /// **'Version 0.1.0'**
  String get settingsAboutHint;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Initial Setup'**
  String get setupTitle;

  /// No description provided for @setupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create the super administrator account for this OmniNest instance.'**
  String get setupSubtitle;

  /// No description provided for @setupUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup is not ready'**
  String get setupUnavailableTitle;

  /// No description provided for @setupUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Configure OMNINEST_SETUP_TOKEN with at least 32 characters on the server, then restart the backend.'**
  String get setupUnavailableMessage;

  /// No description provided for @setupToken.
  ///
  /// In en, this message translates to:
  /// **'Setup token'**
  String get setupToken;

  /// No description provided for @setupTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the setup token configured on the server'**
  String get setupTokenHint;

  /// No description provided for @setupInstanceName.
  ///
  /// In en, this message translates to:
  /// **'Instance name'**
  String get setupInstanceName;

  /// No description provided for @setupInstanceNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter an instance name'**
  String get setupInstanceNameRequired;

  /// No description provided for @setupDefaultLocale.
  ///
  /// In en, this message translates to:
  /// **'Default locale'**
  String get setupDefaultLocale;

  /// No description provided for @setupDefaultTimezone.
  ///
  /// In en, this message translates to:
  /// **'Default time zone'**
  String get setupDefaultTimezone;

  /// No description provided for @setupDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get setupDisplayName;

  /// No description provided for @setupEmail.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get setupEmail;

  /// No description provided for @setupConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get setupConfirmPassword;

  /// No description provided for @setupPasswordLength.
  ///
  /// In en, this message translates to:
  /// **'The super administrator password must be between 6 and 32 characters'**
  String get setupPasswordLength;

  /// No description provided for @setupPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get setupPasswordMismatch;

  /// No description provided for @setupCreateAdmin.
  ///
  /// In en, this message translates to:
  /// **'Create super administrator'**
  String get setupCreateAdmin;

  /// No description provided for @setupRetryStatus.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get setupRetryStatus;

  /// No description provided for @setupStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to read setup status'**
  String get setupStatusFailed;

  /// No description provided for @setupCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create super administrator'**
  String get setupCreateFailed;

  /// No description provided for @setupSecureNotice.
  ///
  /// In en, this message translates to:
  /// **'The setup token is only used for initialization and is not stored on this device.'**
  String get setupSecureNotice;

  /// No description provided for @setupLanguageSelector.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get setupLanguageSelector;

  /// No description provided for @setupSectionInstance.
  ///
  /// In en, this message translates to:
  /// **'Instance'**
  String get setupSectionInstance;

  /// No description provided for @setupSectionAdmin.
  ///
  /// In en, this message translates to:
  /// **'Administrator account'**
  String get setupSectionAdmin;

  /// No description provided for @setupFeatureFiles.
  ///
  /// In en, this message translates to:
  /// **'Files · multi-provider storage'**
  String get setupFeatureFiles;

  /// No description provided for @setupFeatureMedia.
  ///
  /// In en, this message translates to:
  /// **'Video · music · photos'**
  String get setupFeatureMedia;

  /// No description provided for @setupFeatureReader.
  ///
  /// In en, this message translates to:
  /// **'Reader · offline sync'**
  String get setupFeatureReader;

  /// No description provided for @adminSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get adminSearchHint;

  /// No description provided for @adminNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching data found.'**
  String get adminNoMatch;

  /// No description provided for @notificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationTitle;

  /// No description provided for @notificationTitleWithCount.
  ///
  /// In en, this message translates to:
  /// **'Notifications ({count})'**
  String notificationTitleWithCount(Object count);

  /// No description provided for @notificationNoTitle.
  ///
  /// In en, this message translates to:
  /// **'No title'**
  String get notificationNoTitle;

  /// No description provided for @notificationEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get notificationEmpty;

  /// No description provided for @notificationEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'New notifications will appear here'**
  String get notificationEmptyHint;

  /// No description provided for @notificationMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get notificationMarkAllRead;

  /// No description provided for @notificationDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete notification'**
  String get notificationDelete;

  /// No description provided for @notificationClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear notifications'**
  String get notificationClearAll;

  /// No description provided for @notificationClearConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear all notifications?'**
  String get notificationClearConfirmTitle;

  /// No description provided for @notificationClearConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes every notification for the current account.'**
  String get notificationClearConfirmMessage;

  /// No description provided for @notificationDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete notification. Try again.'**
  String get notificationDeleteFailed;

  /// No description provided for @notificationClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to clear notifications. Try again.'**
  String get notificationClearFailed;

  /// No description provided for @notificationTypeCompleted.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get notificationTypeCompleted;

  /// No description provided for @notificationTypeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get notificationTypeFailed;

  /// No description provided for @notificationTypeShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get notificationTypeShare;

  /// No description provided for @notificationTypeTaskCompleted.
  ///
  /// In en, this message translates to:
  /// **'Task Completed'**
  String get notificationTypeTaskCompleted;

  /// No description provided for @notificationTypeTaskCompletedDesc.
  ///
  /// In en, this message translates to:
  /// **'Async task completed successfully'**
  String get notificationTypeTaskCompletedDesc;

  /// No description provided for @notificationTypeTaskFailed.
  ///
  /// In en, this message translates to:
  /// **'Task Failed'**
  String get notificationTypeTaskFailed;

  /// No description provided for @notificationTypeTaskFailedDesc.
  ///
  /// In en, this message translates to:
  /// **'Async task execution failed'**
  String get notificationTypeTaskFailedDesc;

  /// No description provided for @notificationTypeShareAccess.
  ///
  /// In en, this message translates to:
  /// **'Share Access'**
  String get notificationTypeShareAccess;

  /// No description provided for @notificationTypeShareAccessDesc.
  ///
  /// In en, this message translates to:
  /// **'Someone accessed your share link'**
  String get notificationTypeShareAccessDesc;

  /// No description provided for @notificationTypeSystemMessage.
  ///
  /// In en, this message translates to:
  /// **'System Message'**
  String get notificationTypeSystemMessage;

  /// No description provided for @notificationTypeSystemMessageDesc.
  ///
  /// In en, this message translates to:
  /// **'System-level notification'**
  String get notificationTypeSystemMessageDesc;

  /// No description provided for @notificationTypeMetadataScrape.
  ///
  /// In en, this message translates to:
  /// **'Metadata Scrape'**
  String get notificationTypeMetadataScrape;

  /// No description provided for @notificationTypeMetadataScrapeDesc.
  ///
  /// In en, this message translates to:
  /// **'Media metadata scraping completed'**
  String get notificationTypeMetadataScrapeDesc;

  /// No description provided for @notificationTypeShareVisited.
  ///
  /// In en, this message translates to:
  /// **'Share Visited'**
  String get notificationTypeShareVisited;

  /// No description provided for @notificationTypeShareVisitedDesc.
  ///
  /// In en, this message translates to:
  /// **'Your share link was visited'**
  String get notificationTypeShareVisitedDesc;

  /// No description provided for @notificationTypeStorageWarning.
  ///
  /// In en, this message translates to:
  /// **'Storage Warning'**
  String get notificationTypeStorageWarning;

  /// No description provided for @notificationTypeStorageWarningDesc.
  ///
  /// In en, this message translates to:
  /// **'Storage usage is running high'**
  String get notificationTypeStorageWarningDesc;

  /// No description provided for @notificationTypeNewDeviceLogin.
  ///
  /// In en, this message translates to:
  /// **'New Device Login'**
  String get notificationTypeNewDeviceLogin;

  /// No description provided for @notificationTypeNewDeviceLoginDesc.
  ///
  /// In en, this message translates to:
  /// **'New device login detected'**
  String get notificationTypeNewDeviceLoginDesc;

  /// No description provided for @notificationTypePasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password Changed'**
  String get notificationTypePasswordChanged;

  /// No description provided for @notificationTypePasswordChangedDesc.
  ///
  /// In en, this message translates to:
  /// **'Account password was changed'**
  String get notificationTypePasswordChangedDesc;

  /// No description provided for @notificationTypesHeader.
  ///
  /// In en, this message translates to:
  /// **'Notification Types'**
  String get notificationTypesHeader;

  /// No description provided for @notificationTimeNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get notificationTimeNow;

  /// No description provided for @notificationTimeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{n} min ago'**
  String notificationTimeMinutes(Object n);

  /// No description provided for @notificationTimeHours.
  ///
  /// In en, this message translates to:
  /// **'{n} hr ago'**
  String notificationTimeHours(Object n);

  /// No description provided for @notificationTimeDays.
  ///
  /// In en, this message translates to:
  /// **'{n} days ago'**
  String notificationTimeDays(Object n);

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileBackTooltip.
  ///
  /// In en, this message translates to:
  /// **'Back to Portal'**
  String get profileBackTooltip;

  /// No description provided for @profileAvatarFormatError.
  ///
  /// In en, this message translates to:
  /// **'Only JPG, PNG, WebP formats are supported'**
  String get profileAvatarFormatError;

  /// No description provided for @profileAvatarSizeError.
  ///
  /// In en, this message translates to:
  /// **'Avatar size cannot exceed 5MB'**
  String get profileAvatarSizeError;

  /// No description provided for @profileAvatarSuccess.
  ///
  /// In en, this message translates to:
  /// **'Avatar updated successfully'**
  String get profileAvatarSuccess;

  /// No description provided for @profileAvatarFailed.
  ///
  /// In en, this message translates to:
  /// **'Avatar upload failed, please retry'**
  String get profileAvatarFailed;

  /// No description provided for @profileEditAvatar.
  ///
  /// In en, this message translates to:
  /// **'Change avatar'**
  String get profileEditAvatar;

  /// No description provided for @profileUnknownUser.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get profileUnknownUser;

  /// No description provided for @profileEmailNotSet.
  ///
  /// In en, this message translates to:
  /// **'Email not set'**
  String get profileEmailNotSet;

  /// No description provided for @profileRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get profileRole;

  /// No description provided for @profileRoleSuperAdmin.
  ///
  /// In en, this message translates to:
  /// **'Super Admin'**
  String get profileRoleSuperAdmin;

  /// No description provided for @profileRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get profileRoleAdmin;

  /// No description provided for @profileRoleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get profileRoleMember;

  /// No description provided for @profileUnreadNotifications.
  ///
  /// In en, this message translates to:
  /// **'Unread notifications'**
  String get profileUnreadNotifications;

  /// No description provided for @profileLastLogin.
  ///
  /// In en, this message translates to:
  /// **'Last login'**
  String get profileLastLogin;

  /// No description provided for @profileToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get profileToday;

  /// No description provided for @profileAccountStatus.
  ///
  /// In en, this message translates to:
  /// **'Account status'**
  String get profileAccountStatus;

  /// No description provided for @profileStatusNormal.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get profileStatusNormal;

  /// No description provided for @profileAccountInfo.
  ///
  /// In en, this message translates to:
  /// **'Account Info'**
  String get profileAccountInfo;

  /// No description provided for @profileSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get profileSectionAccount;

  /// No description provided for @profileSectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance & language'**
  String get profileSectionAppearance;

  /// No description provided for @profileSectionNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get profileSectionNotifications;

  /// No description provided for @profileSectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security & devices'**
  String get profileSectionSecurity;

  /// No description provided for @profileSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get profileSectionAbout;

  /// No description provided for @profileManageBackdrop.
  ///
  /// In en, this message translates to:
  /// **'Manage background'**
  String get profileManageBackdrop;

  /// No description provided for @profileUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get profileUsername;

  /// No description provided for @profileEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get profileEmail;

  /// No description provided for @profileUserId.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get profileUserId;

  /// No description provided for @profileChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get profileChangePassword;

  /// No description provided for @profileChangePasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update your account password'**
  String get profileChangePasswordSubtitle;

  /// No description provided for @profileWeatherCity.
  ///
  /// In en, this message translates to:
  /// **'Weather City'**
  String get profileWeatherCity;

  /// No description provided for @profileWeatherCityHint.
  ///
  /// In en, this message translates to:
  /// **'Set the weather display city, leave empty to use GPS or system default'**
  String get profileWeatherCityHint;

  /// No description provided for @profileWeatherCityPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter city name, e.g. Beijing, Shanghai'**
  String get profileWeatherCityPlaceholder;

  /// No description provided for @profileWeatherCitySave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get profileWeatherCitySave;

  /// No description provided for @profileWeatherCityNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set (GPS / System default)'**
  String get profileWeatherCityNotSet;

  /// No description provided for @profileWeatherCitySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save city preference: {error}'**
  String profileWeatherCitySaveFailed(Object error);

  /// No description provided for @profileNotificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification Settings'**
  String get profileNotificationSettings;

  /// No description provided for @profileNotificationMasterSwitch.
  ///
  /// In en, this message translates to:
  /// **'Master Switch'**
  String get profileNotificationMasterSwitch;

  /// No description provided for @profileNotificationMasterSwitchHint.
  ///
  /// In en, this message translates to:
  /// **'Disable to stop all notifications'**
  String get profileNotificationMasterSwitchHint;

  /// No description provided for @profileNotificationTypesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load notification types'**
  String get profileNotificationTypesLoadFailed;

  /// No description provided for @profileNotificationSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save notification preferences. Try again.'**
  String get profileNotificationSaveFailed;

  /// No description provided for @profileNotificationSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get profileNotificationSound;

  /// No description provided for @profileNotificationSoundHint.
  ///
  /// In en, this message translates to:
  /// **'Play sound on notification'**
  String get profileNotificationSoundHint;

  /// No description provided for @profileNotificationPreview.
  ///
  /// In en, this message translates to:
  /// **'Notification Preview'**
  String get profileNotificationPreview;

  /// No description provided for @profileNotificationPreviewHint.
  ///
  /// In en, this message translates to:
  /// **'Show message content in notifications'**
  String get profileNotificationPreviewHint;

  /// No description provided for @profileNotificationTypes.
  ///
  /// In en, this message translates to:
  /// **'Notification Types ({count})'**
  String profileNotificationTypes(Object count);

  /// No description provided for @profileLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String profileLoadFailed(Object error);

  /// No description provided for @profileSessionManagement.
  ///
  /// In en, this message translates to:
  /// **'Session Management'**
  String get profileSessionManagement;

  /// No description provided for @profileSessionManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View and manage current login sessions'**
  String get profileSessionManagementSubtitle;

  /// No description provided for @profileActiveSessions.
  ///
  /// In en, this message translates to:
  /// **'Active Sessions'**
  String get profileActiveSessions;

  /// No description provided for @profileNoSessions.
  ///
  /// In en, this message translates to:
  /// **'No active sessions'**
  String get profileNoSessions;

  /// No description provided for @profileSessionDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get profileSessionDevice;

  /// No description provided for @profileSessionIp.
  ///
  /// In en, this message translates to:
  /// **'IP Address'**
  String get profileSessionIp;

  /// No description provided for @profileSessionLastActive.
  ///
  /// In en, this message translates to:
  /// **'Last Active'**
  String get profileSessionLastActive;

  /// No description provided for @profileSessionExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get profileSessionExpires;

  /// No description provided for @profileRevokeSession.
  ///
  /// In en, this message translates to:
  /// **'Revoke Session'**
  String get profileRevokeSession;

  /// No description provided for @profileRevokeSessionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Revoke Session?'**
  String get profileRevokeSessionConfirm;

  /// No description provided for @profileRevokeSessionMessage.
  ///
  /// In en, this message translates to:
  /// **'The device will be forcibly signed out and will need to sign in again.'**
  String get profileRevokeSessionMessage;

  /// No description provided for @profileSessionRevoked.
  ///
  /// In en, this message translates to:
  /// **'Session revoked'**
  String get profileSessionRevoked;

  /// No description provided for @profileSessionRevokeFailed.
  ///
  /// In en, this message translates to:
  /// **'Revocation failed, please retry'**
  String get profileSessionRevokeFailed;

  /// No description provided for @profileSessionsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load sessions'**
  String get profileSessionsLoadFailed;

  /// No description provided for @profileSessionCurrentDevice.
  ///
  /// In en, this message translates to:
  /// **'Current Device'**
  String get profileSessionCurrentDevice;

  /// No description provided for @changePasswordOldPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get changePasswordOldPassword;

  /// No description provided for @changePasswordNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get changePasswordNewPassword;

  /// No description provided for @changePasswordEnterNew.
  ///
  /// In en, this message translates to:
  /// **'Please enter new password'**
  String get changePasswordEnterNew;

  /// No description provided for @changePasswordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get changePasswordMinLength;

  /// No description provided for @changePasswordMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at most 128 characters'**
  String get changePasswordMaxLength;

  /// No description provided for @changePasswordConfirmNew.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get changePasswordConfirmNew;

  /// No description provided for @changePasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get changePasswordMismatch;

  /// No description provided for @changePasswordCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get changePasswordCancel;

  /// No description provided for @changePasswordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get changePasswordConfirm;

  /// No description provided for @changePasswordSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully'**
  String get changePasswordSuccess;

  /// No description provided for @changePasswordWrongOld.
  ///
  /// In en, this message translates to:
  /// **'Incorrect current password'**
  String get changePasswordWrongOld;

  /// No description provided for @changePasswordFailed.
  ///
  /// In en, this message translates to:
  /// **'Password change failed, please retry'**
  String get changePasswordFailed;

  /// No description provided for @changePasswordEnterField.
  ///
  /// In en, this message translates to:
  /// **'Please enter {field}'**
  String changePasswordEnterField(Object field);

  /// No description provided for @loginWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get loginWelcome;

  /// No description provided for @loginDescription.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your OmniNest account.'**
  String get loginDescription;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Consolidate family media, reading, files, and automation tasks into one stable personal space.'**
  String get loginSubtitle;

  /// No description provided for @loginFeatureMedia.
  ///
  /// In en, this message translates to:
  /// **'Media Center'**
  String get loginFeatureMedia;

  /// No description provided for @loginFeatureReader.
  ///
  /// In en, this message translates to:
  /// **'Book Library'**
  String get loginFeatureReader;

  /// No description provided for @loginFeatureFiles.
  ///
  /// In en, this message translates to:
  /// **'File Manager'**
  String get loginFeatureFiles;

  /// No description provided for @loginFeatureAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin Console'**
  String get loginFeatureAdmin;

  /// No description provided for @loginUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get loginUsername;

  /// No description provided for @loginUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'Please enter username'**
  String get loginUsernameHint;

  /// No description provided for @loginPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPassword;

  /// No description provided for @loginShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get loginShowPassword;

  /// No description provided for @loginHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get loginHidePassword;

  /// No description provided for @loginPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Please enter password'**
  String get loginPasswordHint;

  /// No description provided for @loginSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in...'**
  String get loginSigningIn;

  /// No description provided for @loginSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get loginSignIn;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed, please try again later'**
  String get loginFailed;

  /// No description provided for @loginConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to backend, please confirm the service is running'**
  String get loginConnectionError;

  /// No description provided for @loginRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Login request failed, please check your account or network'**
  String get loginRequestFailed;

  /// No description provided for @coreRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get coreRetry;

  /// No description provided for @coreStartupFailed.
  ///
  /// In en, this message translates to:
  /// **'Startup failed'**
  String get coreStartupFailed;

  /// No description provided for @coreStartupFailedHint.
  ///
  /// In en, this message translates to:
  /// **'A runtime dependency could not be initialized. Retry, then check the local media components and application logs if the problem continues.'**
  String get coreStartupFailedHint;

  /// No description provided for @coreCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get coreCancel;

  /// No description provided for @coreConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get coreConfirm;

  /// No description provided for @coreSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get coreSave;

  /// No description provided for @coreClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get coreClose;

  /// No description provided for @coreBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get coreBack;

  /// No description provided for @coreDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get coreDelete;

  /// No description provided for @coreClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get coreClear;

  /// No description provided for @coreChooseDate.
  ///
  /// In en, this message translates to:
  /// **'Choose date'**
  String get coreChooseDate;

  /// No description provided for @corePlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get corePlay;

  /// No description provided for @corePause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get corePause;

  /// No description provided for @corePrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get corePrevious;

  /// No description provided for @coreNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get coreNext;

  /// No description provided for @coreShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get coreShowPassword;

  /// No description provided for @coreHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get coreHidePassword;

  /// No description provided for @coreSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get coreSearchHint;

  /// No description provided for @coreProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get coreProfile;

  /// No description provided for @coreStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get coreStorage;

  /// No description provided for @coreAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get coreAdmin;

  /// No description provided for @coreSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get coreSignOut;

  /// No description provided for @coreMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get coreMenu;

  /// No description provided for @coreMore.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get coreMore;

  /// No description provided for @coreTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get coreTheme;

  /// No description provided for @coreThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get coreThemeLight;

  /// No description provided for @coreThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get coreThemeDark;

  /// No description provided for @coreLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get coreLanguage;

  /// No description provided for @coreRoleSuperAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get coreRoleSuperAdmin;

  /// No description provided for @coreRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Mod'**
  String get coreRoleAdmin;

  /// No description provided for @coreRoleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get coreRoleMember;

  /// No description provided for @filesAllFiles.
  ///
  /// In en, this message translates to:
  /// **'All Files'**
  String get filesAllFiles;

  /// No description provided for @filesRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get filesRecent;

  /// No description provided for @filesFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get filesFavorites;

  /// No description provided for @filesRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Recycle Bin'**
  String get filesRecycleBin;

  /// No description provided for @filesSharedWithMe.
  ///
  /// In en, this message translates to:
  /// **'Shared With Me'**
  String get filesSharedWithMe;

  /// No description provided for @filesMyShares.
  ///
  /// In en, this message translates to:
  /// **'My Shares'**
  String get filesMyShares;

  /// No description provided for @filesShareManagement.
  ///
  /// In en, this message translates to:
  /// **'Share Link Management'**
  String get filesShareManagement;

  /// No description provided for @filesStorageStats.
  ///
  /// In en, this message translates to:
  /// **'Storage Statistics'**
  String get filesStorageStats;

  /// No description provided for @filesUploadQueue.
  ///
  /// In en, this message translates to:
  /// **'Upload Queue'**
  String get filesUploadQueue;

  /// No description provided for @filesOfflineDownloads.
  ///
  /// In en, this message translates to:
  /// **'Offline Downloads'**
  String get filesOfflineDownloads;

  /// No description provided for @filesExternalStorage.
  ///
  /// In en, this message translates to:
  /// **'External Storage'**
  String get filesExternalStorage;

  /// No description provided for @filesImportTasks.
  ///
  /// In en, this message translates to:
  /// **'Import Tasks'**
  String get filesImportTasks;

  /// No description provided for @filesAllFilesDesc.
  ///
  /// In en, this message translates to:
  /// **'Browse root or specified directory to manage folders, files and paths.'**
  String get filesAllFilesDesc;

  /// No description provided for @filesRecentDesc.
  ///
  /// In en, this message translates to:
  /// **'View recently opened or downloaded files sorted by access time.'**
  String get filesRecentDesc;

  /// No description provided for @filesFavoritesDesc.
  ///
  /// In en, this message translates to:
  /// **'View starred files in one place, ideal for frequently used materials.'**
  String get filesFavoritesDesc;

  /// No description provided for @filesRecycleBinDesc.
  ///
  /// In en, this message translates to:
  /// **'View soft-deleted files, supports restore or permanent delete.'**
  String get filesRecycleBinDesc;

  /// No description provided for @filesSharedWithMeDesc.
  ///
  /// In en, this message translates to:
  /// **'View files shared to your account by other users.'**
  String get filesSharedWithMeDesc;

  /// No description provided for @filesMySharesDesc.
  ///
  /// In en, this message translates to:
  /// **'View share links created by you.'**
  String get filesMySharesDesc;

  /// No description provided for @filesShareManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage active, expired or revoked share links.'**
  String get filesShareManagementDesc;

  /// No description provided for @filesStorageStatsDesc.
  ///
  /// In en, this message translates to:
  /// **'View capacity, quota, file type distribution and space usage.'**
  String get filesStorageStatsDesc;

  /// No description provided for @filesUploadQueueDesc.
  ///
  /// In en, this message translates to:
  /// **'View multipart upload sessions, resume progress and upload status.'**
  String get filesUploadQueueDesc;

  /// No description provided for @filesOfflineDownloadsDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage HTTP, BT and magnet offline download tasks.'**
  String get filesOfflineDownloadsDesc;

  /// No description provided for @filesExternalStorageDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage OneDrive, WebDAV and other third-party storage mounts.'**
  String get filesExternalStorageDesc;

  /// No description provided for @filesImportTasksDesc.
  ///
  /// In en, this message translates to:
  /// **'View external storage file import progress, supports cancelling queued tasks.'**
  String get filesImportTasksDesc;

  /// No description provided for @filesSharedSpace.
  ///
  /// In en, this message translates to:
  /// **'Shared Space'**
  String get filesSharedSpace;

  /// No description provided for @filesSharedSpaceDesc.
  ///
  /// In en, this message translates to:
  /// **'All users shared file space'**
  String get filesSharedSpaceDesc;

  /// No description provided for @filesSharedSpaceUsage.
  ///
  /// In en, this message translates to:
  /// **'Shared Space Usage'**
  String get filesSharedSpaceUsage;

  /// No description provided for @filesSharedSpaceEmpty.
  ///
  /// In en, this message translates to:
  /// **'No files in shared space'**
  String get filesSharedSpaceEmpty;

  /// No description provided for @filesMoveToShared.
  ///
  /// In en, this message translates to:
  /// **'Move to Shared Space'**
  String get filesMoveToShared;

  /// No description provided for @filesMoveToSharedConfirm.
  ///
  /// In en, this message translates to:
  /// **'Move to Shared Space'**
  String get filesMoveToSharedConfirm;

  /// No description provided for @filesMoveToSharedMessage.
  ///
  /// In en, this message translates to:
  /// **'Move \"{name}\" to shared space? All users will see it.'**
  String filesMoveToSharedMessage(Object name);

  /// No description provided for @filesMoveToPersonal.
  ///
  /// In en, this message translates to:
  /// **'Move to Personal Space'**
  String get filesMoveToPersonal;

  /// No description provided for @filesMoveToPersonalConfirm.
  ///
  /// In en, this message translates to:
  /// **'Move to Personal Space'**
  String get filesMoveToPersonalConfirm;

  /// No description provided for @filesMoveToPersonalMessage.
  ///
  /// In en, this message translates to:
  /// **'Move \"{name}\" to personal space?'**
  String filesMoveToPersonalMessage(Object name);

  /// No description provided for @filesMoveToPersonalLabel.
  ///
  /// In en, this message translates to:
  /// **'Move back'**
  String get filesMoveToPersonalLabel;

  /// No description provided for @filesCount.
  ///
  /// In en, this message translates to:
  /// **'files'**
  String get filesCount;

  /// No description provided for @filesCategoryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filesCategoryAll;

  /// No description provided for @filesCategoryImage.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get filesCategoryImage;

  /// No description provided for @filesCategoryVideo.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get filesCategoryVideo;

  /// No description provided for @filesCategoryAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get filesCategoryAudio;

  /// No description provided for @filesCategoryDocument.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get filesCategoryDocument;

  /// No description provided for @filesCategoryNovel.
  ///
  /// In en, this message translates to:
  /// **'Novels'**
  String get filesCategoryNovel;

  /// No description provided for @filesCategoryComic.
  ///
  /// In en, this message translates to:
  /// **'Comics'**
  String get filesCategoryComic;

  /// No description provided for @filesCategoryArchive.
  ///
  /// In en, this message translates to:
  /// **'Archives'**
  String get filesCategoryArchive;

  /// No description provided for @filesCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get filesCategoryOther;

  /// No description provided for @filesGroupFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get filesGroupFiles;

  /// No description provided for @filesGroupSharing.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get filesGroupSharing;

  /// No description provided for @filesGroupTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get filesGroupTransfer;

  /// No description provided for @filesGroupStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get filesGroupStorage;

  /// No description provided for @filesNavFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get filesNavFiles;

  /// No description provided for @filesNavRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get filesNavRecent;

  /// No description provided for @filesNavShared.
  ///
  /// In en, this message translates to:
  /// **'Shared'**
  String get filesNavShared;

  /// No description provided for @filesNavRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Recycle Bin'**
  String get filesNavRecycleBin;

  /// No description provided for @filesOpenFileMenu.
  ///
  /// In en, this message translates to:
  /// **'Open file menu'**
  String get filesOpenFileMenu;

  /// No description provided for @filesSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get filesSearch;

  /// No description provided for @filesRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get filesRefresh;

  /// No description provided for @filesSearchFiles.
  ///
  /// In en, this message translates to:
  /// **'Search Files'**
  String get filesSearchFiles;

  /// No description provided for @filesSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Enter filename, path or type'**
  String get filesSearchHint;

  /// No description provided for @filesStorageUsage.
  ///
  /// In en, this message translates to:
  /// **'Storage Usage'**
  String get filesStorageUsage;

  /// No description provided for @filesWaitingStats.
  ///
  /// In en, this message translates to:
  /// **'Waiting for statistics'**
  String get filesWaitingStats;

  /// No description provided for @filesUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get filesUnlimited;

  /// No description provided for @filesUnlimitedQuota.
  ///
  /// In en, this message translates to:
  /// **'Unlimited quota'**
  String get filesUnlimitedQuota;

  /// No description provided for @filesUsedPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% used · {remaining} remaining'**
  String filesUsedPercent(Object percent, Object remaining);

  /// No description provided for @filesUsedOf.
  ///
  /// In en, this message translates to:
  /// **'{used} / {total}'**
  String filesUsedOf(Object total, Object used);

  /// No description provided for @filesStorageSpace.
  ///
  /// In en, this message translates to:
  /// **'Storage Space'**
  String get filesStorageSpace;

  /// No description provided for @filesFolders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get filesFolders;

  /// No description provided for @filesFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get filesFiles;

  /// No description provided for @filesCapacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity'**
  String get filesCapacity;

  /// No description provided for @filesCurrentView.
  ///
  /// In en, this message translates to:
  /// **'Current View'**
  String get filesCurrentView;

  /// No description provided for @filesCurrentViewTotal.
  ///
  /// In en, this message translates to:
  /// **'Current View Total'**
  String get filesCurrentViewTotal;

  /// No description provided for @filesSoftDeleted.
  ///
  /// In en, this message translates to:
  /// **'Soft Deleted Files'**
  String get filesSoftDeleted;

  /// No description provided for @filesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No files'**
  String get filesEmpty;

  /// No description provided for @filesRecycleBinEmpty.
  ///
  /// In en, this message translates to:
  /// **'Recycle bin is empty'**
  String get filesRecycleBinEmpty;

  /// No description provided for @filesUploadFile.
  ///
  /// In en, this message translates to:
  /// **'Upload File'**
  String get filesUploadFile;

  /// No description provided for @filesLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more ({loaded} / {total} loaded)'**
  String filesLoadMore(Object loaded, Object total);

  /// No description provided for @filesDropToUpload.
  ///
  /// In en, this message translates to:
  /// **'Drop files here to upload'**
  String get filesDropToUpload;

  /// No description provided for @filesUploadProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing {count} files · Progress {progress}'**
  String filesUploadProcessing(Object count, Object progress);

  /// No description provided for @filesViewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get filesViewAll;

  /// No description provided for @filesCollapseQueue.
  ///
  /// In en, this message translates to:
  /// **'Collapse upload queue'**
  String get filesCollapseQueue;

  /// No description provided for @filesExpandQueue.
  ///
  /// In en, this message translates to:
  /// **'Expand upload queue'**
  String get filesExpandQueue;

  /// No description provided for @filesMoreInQueue.
  ///
  /// In en, this message translates to:
  /// **'{count} more tasks in upload queue'**
  String filesMoreInQueue(Object count);

  /// No description provided for @filesSortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort By'**
  String get filesSortBy;

  /// No description provided for @filesSortName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get filesSortName;

  /// No description provided for @filesSortTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get filesSortTime;

  /// No description provided for @filesSortSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get filesSortSize;

  /// No description provided for @filesNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get filesNewFolder;

  /// No description provided for @filesCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get filesCreate;

  /// No description provided for @filesFolderName.
  ///
  /// In en, this message translates to:
  /// **'Folder Name'**
  String get filesFolderName;

  /// No description provided for @filesRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get filesRename;

  /// No description provided for @filesSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get filesSave;

  /// No description provided for @filesFileName.
  ///
  /// In en, this message translates to:
  /// **'Filename'**
  String get filesFileName;

  /// No description provided for @filesFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get filesFolder;

  /// No description provided for @filesMoveToRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Move to Recycle Bin'**
  String get filesMoveToRecycleBin;

  /// No description provided for @filesPurge.
  ///
  /// In en, this message translates to:
  /// **'Permanently Delete'**
  String get filesPurge;

  /// No description provided for @filesMoveToEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Move to…'**
  String get filesMoveToEllipsis;

  /// No description provided for @filesDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get filesDownload;

  /// No description provided for @filesShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get filesShare;

  /// No description provided for @filesOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get filesOpen;

  /// No description provided for @filesPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get filesPreview;

  /// No description provided for @filesRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get filesRestore;

  /// No description provided for @filesMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More Actions'**
  String get filesMoreActions;

  /// No description provided for @filesFileActions.
  ///
  /// In en, this message translates to:
  /// **'File Actions'**
  String get filesFileActions;

  /// No description provided for @filesDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to Recycle Bin?'**
  String filesDeleteConfirmTitle(Object name);

  /// No description provided for @filesDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be removed from the file list and associated records in video, music and other modules will be cleaned up.'**
  String filesDeleteConfirmMessage(Object name);

  /// No description provided for @filesPurgeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently Delete?'**
  String filesPurgeConfirmTitle(Object name);

  /// No description provided for @filesPurgeConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be permanently deleted from the recycle bin. This action cannot be undone.'**
  String filesPurgeConfirmMessage(Object name);

  /// No description provided for @filesSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String filesSelectedCount(Object count);

  /// No description provided for @filesSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get filesSelectAll;

  /// No description provided for @filesDeselect.
  ///
  /// In en, this message translates to:
  /// **'Deselect'**
  String get filesDeselect;

  /// No description provided for @filesBatchRestore.
  ///
  /// In en, this message translates to:
  /// **'Batch Restore'**
  String get filesBatchRestore;

  /// No description provided for @filesBatchPurge.
  ///
  /// In en, this message translates to:
  /// **'Batch Purge'**
  String get filesBatchPurge;

  /// No description provided for @filesBatchMove.
  ///
  /// In en, this message translates to:
  /// **'Batch Move'**
  String get filesBatchMove;

  /// No description provided for @filesBatchDelete.
  ///
  /// In en, this message translates to:
  /// **'Batch Delete'**
  String get filesBatchDelete;

  /// No description provided for @filesBatchAddFavorite.
  ///
  /// In en, this message translates to:
  /// **'Batch Favorite'**
  String get filesBatchAddFavorite;

  /// No description provided for @filesBatchRemoveFavorite.
  ///
  /// In en, this message translates to:
  /// **'Batch Unfavorite'**
  String get filesBatchRemoveFavorite;

  /// No description provided for @filesBatchRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch Restore?'**
  String get filesBatchRestoreTitle;

  /// No description provided for @filesBatchRestoreMessage.
  ///
  /// In en, this message translates to:
  /// **'Will restore {count} selected files.'**
  String filesBatchRestoreMessage(Object count);

  /// No description provided for @filesBatchPurgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch Permanently Delete?'**
  String get filesBatchPurgeTitle;

  /// No description provided for @filesBatchPurgeMessage.
  ///
  /// In en, this message translates to:
  /// **'{count} selected files will be permanently deleted. This action cannot be undone.'**
  String filesBatchPurgeMessage(Object count);

  /// No description provided for @filesBatchDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch Move to Recycle Bin?'**
  String get filesBatchDeleteTitle;

  /// No description provided for @filesBatchDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'{count} selected files will be moved to the recycle bin.'**
  String filesBatchDeleteMessage(Object count);

  /// No description provided for @filesDownloadLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Download link copied to clipboard'**
  String get filesDownloadLinkCopied;

  /// No description provided for @filesDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to get download link'**
  String get filesDownloadFailed;

  /// No description provided for @filesMovedFile.
  ///
  /// In en, this message translates to:
  /// **'Moved \"{name}\"'**
  String filesMovedFile(Object name);

  /// No description provided for @filesMovedCount.
  ///
  /// In en, this message translates to:
  /// **'Moved {count} files'**
  String filesMovedCount(Object count);

  /// No description provided for @filesUploadComplete.
  ///
  /// In en, this message translates to:
  /// **'{count} files uploaded'**
  String filesUploadComplete(Object count);

  /// No description provided for @filesUploadBatchSummary.
  ///
  /// In en, this message translates to:
  /// **'{completed} uploaded, {conflicts} conflicted, {failed} failed, {paused} paused'**
  String filesUploadBatchSummary(
    Object completed,
    Object conflicts,
    Object failed,
    Object paused,
  );

  /// No description provided for @filesSelectTargetFolder.
  ///
  /// In en, this message translates to:
  /// **'Select Target Folder'**
  String get filesSelectTargetFolder;

  /// No description provided for @filesRootDirectory.
  ///
  /// In en, this message translates to:
  /// **'Root Directory'**
  String get filesRootDirectory;

  /// No description provided for @filesGoToParent.
  ///
  /// In en, this message translates to:
  /// **'Go to parent folder'**
  String get filesGoToParent;

  /// No description provided for @filesFolderEmpty.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get filesFolderEmpty;

  /// No description provided for @filesMoveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to \"{name}\"'**
  String filesMoveToFolder(Object name);

  /// No description provided for @filesStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get filesStatusQueued;

  /// No description provided for @filesStatusUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get filesStatusUploading;

  /// No description provided for @filesStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get filesStatusPaused;

  /// No description provided for @filesStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get filesStatusFailed;

  /// No description provided for @filesStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get filesStatusCompleted;

  /// No description provided for @filesStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get filesStatusCancelled;

  /// No description provided for @filesStatusCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling'**
  String get filesStatusCancelling;

  /// No description provided for @filesOfflineEmpty.
  ///
  /// In en, this message translates to:
  /// **'No offline download tasks'**
  String get filesOfflineEmpty;

  /// No description provided for @filesNewOfflineDownload.
  ///
  /// In en, this message translates to:
  /// **'New Offline Download'**
  String get filesNewOfflineDownload;

  /// No description provided for @filesDownloadLink.
  ///
  /// In en, this message translates to:
  /// **'Download Link'**
  String get filesDownloadLink;

  /// No description provided for @filesOfflineDownloadHint.
  ///
  /// In en, this message translates to:
  /// **'Supports HTTP, BT torrent and magnet links'**
  String get filesOfflineDownloadHint;

  /// No description provided for @filesNewTask.
  ///
  /// In en, this message translates to:
  /// **'New Task'**
  String get filesNewTask;

  /// No description provided for @filesCancelTask.
  ///
  /// In en, this message translates to:
  /// **'Cancel Task'**
  String get filesCancelTask;

  /// No description provided for @filesTaskEnded.
  ///
  /// In en, this message translates to:
  /// **'Task Ended'**
  String get filesTaskEnded;

  /// No description provided for @filesCancelOfflineConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel Offline Download?'**
  String get filesCancelOfflineConfirm;

  /// No description provided for @filesCancelOfflineMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" download will stop. Unfinished data won\'t be imported.'**
  String filesCancelOfflineMessage(Object name);

  /// No description provided for @filesNoExternalStorage.
  ///
  /// In en, this message translates to:
  /// **'No external storage'**
  String get filesNoExternalStorage;

  /// No description provided for @filesAddMount.
  ///
  /// In en, this message translates to:
  /// **'Add Mount'**
  String get filesAddMount;

  /// No description provided for @filesEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get filesEdit;

  /// No description provided for @filesBrowseRemote.
  ///
  /// In en, this message translates to:
  /// **'Browse Remote Files'**
  String get filesBrowseRemote;

  /// No description provided for @filesDisableMount.
  ///
  /// In en, this message translates to:
  /// **'Disable Mount'**
  String get filesDisableMount;

  /// No description provided for @filesDisableMountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Disable External Mount?'**
  String get filesDisableMountConfirm;

  /// No description provided for @filesDisableMountMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will no longer participate in file mount and sync.'**
  String filesDisableMountMessage(Object name);

  /// No description provided for @filesDeleteMount.
  ///
  /// In en, this message translates to:
  /// **'Delete Mount'**
  String get filesDeleteMount;

  /// No description provided for @filesDeleteMountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete External Mount?'**
  String get filesDeleteMountConfirm;

  /// No description provided for @filesDeleteMountMessage.
  ///
  /// In en, this message translates to:
  /// **'Will permanently delete \"{name}\" and its rclone configuration. This action cannot be undone.'**
  String filesDeleteMountMessage(Object name);

  /// No description provided for @filesCloseBrowse.
  ///
  /// In en, this message translates to:
  /// **'Close Browse'**
  String get filesCloseBrowse;

  /// No description provided for @filesDirectoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'This directory is empty'**
  String get filesDirectoryEmpty;

  /// No description provided for @filesEnterFolder.
  ///
  /// In en, this message translates to:
  /// **'Enter Folder'**
  String get filesEnterFolder;

  /// No description provided for @filesImportFile.
  ///
  /// In en, this message translates to:
  /// **'Import This File'**
  String get filesImportFile;

  /// No description provided for @filesImportFolder.
  ///
  /// In en, this message translates to:
  /// **'Import Entire Folder'**
  String get filesImportFolder;

  /// No description provided for @filesImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import External Content?'**
  String get filesImportConfirm;

  /// No description provided for @filesImportMessage.
  ///
  /// In en, this message translates to:
  /// **'Import \"{name}\" to current file directory.'**
  String filesImportMessage(Object name);

  /// No description provided for @filesImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get filesImport;

  /// No description provided for @filesNoImportTasks.
  ///
  /// In en, this message translates to:
  /// **'No import tasks'**
  String get filesNoImportTasks;

  /// No description provided for @filesCancelImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel Import Task?'**
  String get filesCancelImportConfirm;

  /// No description provided for @filesCancelImportMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" import will be cancelled.'**
  String filesCancelImportMessage(Object name);

  /// No description provided for @filesDeleteRecord.
  ///
  /// In en, this message translates to:
  /// **'Delete Record'**
  String get filesDeleteRecord;

  /// No description provided for @filesDeleteImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete Import Record?'**
  String get filesDeleteImportConfirm;

  /// No description provided for @filesDeleteImportMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" import record will be deleted.'**
  String filesDeleteImportMessage(Object name);

  /// No description provided for @filesNoSharedFiles.
  ///
  /// In en, this message translates to:
  /// **'No shared files'**
  String get filesNoSharedFiles;

  /// No description provided for @filesFromUser.
  ///
  /// In en, this message translates to:
  /// **'From {userId}'**
  String filesFromUser(Object userId);

  /// No description provided for @filesLongTerm.
  ///
  /// In en, this message translates to:
  /// **'Long term'**
  String get filesLongTerm;

  /// No description provided for @filesHasExpiry.
  ///
  /// In en, this message translates to:
  /// **'Has expiry'**
  String get filesHasExpiry;

  /// No description provided for @filesShareMgmt.
  ///
  /// In en, this message translates to:
  /// **'Share Management'**
  String get filesShareMgmt;

  /// No description provided for @filesShareMgmtDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage share links created by you. Revocable.'**
  String get filesShareMgmtDesc;

  /// No description provided for @filesNoShareLinks.
  ///
  /// In en, this message translates to:
  /// **'No share links'**
  String get filesNoShareLinks;

  /// No description provided for @filesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String filesLoadFailed(Object error);

  /// No description provided for @filesAccessUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get filesAccessUnlimited;

  /// No description provided for @filesShareActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get filesShareActive;

  /// No description provided for @filesShareRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get filesShareRevoked;

  /// No description provided for @filesShareExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get filesShareExpired;

  /// No description provided for @filesShareExhausted.
  ///
  /// In en, this message translates to:
  /// **'Exhausted'**
  String get filesShareExhausted;

  /// No description provided for @filesRevokeShare.
  ///
  /// In en, this message translates to:
  /// **'Revoke Share'**
  String get filesRevokeShare;

  /// No description provided for @filesRevokeShareConfirm.
  ///
  /// In en, this message translates to:
  /// **'Revoke Share?'**
  String get filesRevokeShareConfirm;

  /// No description provided for @filesRevokeShareMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" share link will be invalidated. People with the link can no longer access.'**
  String filesRevokeShareMessage(Object name);

  /// No description provided for @filesClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get filesClose;

  /// No description provided for @filesWaitingUpload.
  ///
  /// In en, this message translates to:
  /// **'Waiting to upload'**
  String get filesWaitingUpload;

  /// No description provided for @filesDirectUploading.
  ///
  /// In en, this message translates to:
  /// **'Direct uploading'**
  String get filesDirectUploading;

  /// No description provided for @filesMultipartUploading.
  ///
  /// In en, this message translates to:
  /// **'Multipart uploading'**
  String get filesMultipartUploading;

  /// No description provided for @filesUploadPausedMsg.
  ///
  /// In en, this message translates to:
  /// **'Paused, can resume'**
  String get filesUploadPausedMsg;

  /// No description provided for @filesUploadPausePending.
  ///
  /// In en, this message translates to:
  /// **'Stopping the current transfer'**
  String get filesUploadPausePending;

  /// No description provided for @filesResumingUpload.
  ///
  /// In en, this message translates to:
  /// **'Resuming upload'**
  String get filesResumingUpload;

  /// No description provided for @filesUploadRetrying.
  ///
  /// In en, this message translates to:
  /// **'Cleanup complete. Retrying upload'**
  String get filesUploadRetrying;

  /// No description provided for @filesUploadDone.
  ///
  /// In en, this message translates to:
  /// **'Upload complete'**
  String get filesUploadDone;

  /// No description provided for @filesUploadedParts.
  ///
  /// In en, this message translates to:
  /// **'Uploaded {current}/{total} parts'**
  String filesUploadedParts(Object current, Object total);

  /// No description provided for @filesCleanupConflict.
  ///
  /// In en, this message translates to:
  /// **'Clean up same-name file in recycle bin?'**
  String get filesCleanupConflict;

  /// No description provided for @filesCleanupMessage.
  ///
  /// In en, this message translates to:
  /// **'Same-name file exists in recycle bin. Will auto re-upload after cleanup.'**
  String get filesCleanupMessage;

  /// No description provided for @filesCleanupAndRetry.
  ///
  /// In en, this message translates to:
  /// **'Clean up and retry'**
  String get filesCleanupAndRetry;

  /// No description provided for @filesDeleteUploadTask.
  ///
  /// In en, this message translates to:
  /// **'Delete Upload Task?'**
  String get filesDeleteUploadTask;

  /// No description provided for @filesDeleteUploadTaskMessage.
  ///
  /// In en, this message translates to:
  /// **'The upload task will be removed from the queue. Unfinished server sessions will be cancelled.'**
  String get filesDeleteUploadTaskMessage;

  /// No description provided for @filesDeleteTask.
  ///
  /// In en, this message translates to:
  /// **'Delete Task'**
  String get filesDeleteTask;

  /// No description provided for @filesEditExternalStorage.
  ///
  /// In en, this message translates to:
  /// **'Edit External Storage'**
  String get filesEditExternalStorage;

  /// No description provided for @filesAddExternalStorage.
  ///
  /// In en, this message translates to:
  /// **'Add External Storage'**
  String get filesAddExternalStorage;

  /// No description provided for @externalStorageSpace.
  ///
  /// In en, this message translates to:
  /// **'Space Usage'**
  String get externalStorageSpace;

  /// No description provided for @externalMkdir.
  ///
  /// In en, this message translates to:
  /// **'Create Directory'**
  String get externalMkdir;

  /// No description provided for @externalMkdirHint.
  ///
  /// In en, this message translates to:
  /// **'Enter directory path, e.g. /photos/2024'**
  String get externalMkdirHint;

  /// No description provided for @externalDeleteFile.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get externalDeleteFile;

  /// No description provided for @externalRenameFile.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get externalRenameFile;

  /// No description provided for @externalDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this remote file? This cannot be undone.'**
  String get externalDeleteConfirm;

  /// No description provided for @externalSpaceUsedOf.
  ///
  /// In en, this message translates to:
  /// **'{used} / {total}'**
  String externalSpaceUsedOf(Object used, Object total);

  /// No description provided for @filesStorageType.
  ///
  /// In en, this message translates to:
  /// **'Storage Type'**
  String get filesStorageType;

  /// No description provided for @filesDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get filesDisplayName;

  /// No description provided for @filesDisplayNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. My Cloud Storage'**
  String get filesDisplayNameHint;

  /// No description provided for @filesConnectionCredentials.
  ///
  /// In en, this message translates to:
  /// **'Connection Credentials'**
  String get filesConnectionCredentials;

  /// No description provided for @filesExistingSecretPreserved.
  ///
  /// In en, this message translates to:
  /// **'Passwords, secrets, and tokens are never returned. Leave them blank to keep the saved values.'**
  String get filesExistingSecretPreserved;

  /// No description provided for @filesKeepExistingSecretHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to keep the saved value'**
  String get filesKeepExistingSecretHint;

  /// No description provided for @filesS3Provider.
  ///
  /// In en, this message translates to:
  /// **'S3 Provider'**
  String get filesS3Provider;

  /// No description provided for @filesEndpointRequired.
  ///
  /// In en, this message translates to:
  /// **'Endpoint (required)'**
  String get filesEndpointRequired;

  /// No description provided for @filesEndpointHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. http://omninest-minio:9000'**
  String get filesEndpointHint;

  /// No description provided for @filesRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get filesRegion;

  /// No description provided for @filesRegionHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. us-east-1 (optional)'**
  String get filesRegionHint;

  /// No description provided for @filesServiceType.
  ///
  /// In en, this message translates to:
  /// **'Service Type'**
  String get filesServiceType;

  /// No description provided for @filesWebdavUrl.
  ///
  /// In en, this message translates to:
  /// **'WebDAV URL'**
  String get filesWebdavUrl;

  /// No description provided for @filesUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get filesUsername;

  /// No description provided for @filesPasswordOrApp.
  ///
  /// In en, this message translates to:
  /// **'Password / App Password'**
  String get filesPasswordOrApp;

  /// No description provided for @filesDirectoryPath.
  ///
  /// In en, this message translates to:
  /// **'Directory Path'**
  String get filesDirectoryPath;

  /// No description provided for @filesClientIdOptional.
  ///
  /// In en, this message translates to:
  /// **'Client ID (optional)'**
  String get filesClientIdOptional;

  /// No description provided for @filesClientSecretOptional.
  ///
  /// In en, this message translates to:
  /// **'Client Secret (optional)'**
  String get filesClientSecretOptional;

  /// No description provided for @filesUnknownStorageType.
  ///
  /// In en, this message translates to:
  /// **'Unknown Storage Type'**
  String get filesUnknownStorageType;

  /// No description provided for @filesAdvancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Advanced Options'**
  String get filesAdvancedOptions;

  /// No description provided for @filesMaxAccessCount.
  ///
  /// In en, this message translates to:
  /// **'Max Access Count'**
  String get filesMaxAccessCount;

  /// No description provided for @filesNoLimit.
  ///
  /// In en, this message translates to:
  /// **'No limit'**
  String get filesNoLimit;

  /// No description provided for @filesExpiryTime.
  ///
  /// In en, this message translates to:
  /// **'Expiry Time'**
  String get filesExpiryTime;

  /// No description provided for @filesNeverExpire.
  ///
  /// In en, this message translates to:
  /// **'Never expire'**
  String get filesNeverExpire;

  /// No description provided for @filesCreateShareLink.
  ///
  /// In en, this message translates to:
  /// **'Create Share Link'**
  String get filesCreateShareLink;

  /// No description provided for @filesCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Creation failed'**
  String get filesCreateFailed;

  /// No description provided for @filesSetPassword.
  ///
  /// In en, this message translates to:
  /// **'Set Password'**
  String get filesSetPassword;

  /// No description provided for @filesPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password required to access'**
  String get filesPasswordRequired;

  /// No description provided for @filesNoPasswordAnyone.
  ///
  /// In en, this message translates to:
  /// **'No password, anyone can access'**
  String get filesNoPasswordAnyone;

  /// No description provided for @filesRandomGenerate.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get filesRandomGenerate;

  /// No description provided for @filesCustomPassword.
  ///
  /// In en, this message translates to:
  /// **'Custom Password'**
  String get filesCustomPassword;

  /// No description provided for @filesEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get filesEnterPassword;

  /// No description provided for @filesEnterCustomPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter custom password'**
  String get filesEnterCustomPassword;

  /// No description provided for @filesCopiedClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get filesCopiedClipboard;

  /// No description provided for @filesPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get filesPasswordLabel;

  /// No description provided for @filesSharePasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password: {password}'**
  String filesSharePasswordLabel(Object password);

  /// No description provided for @filesCopyLinkWithPassword.
  ///
  /// In en, this message translates to:
  /// **'Copy link (with password)'**
  String get filesCopyLinkWithPassword;

  /// No description provided for @filesCopyLinkOnly.
  ///
  /// In en, this message translates to:
  /// **'Copy link only'**
  String get filesCopyLinkOnly;

  /// No description provided for @filesCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get filesCopyLink;

  /// No description provided for @filesCannotLoadImage.
  ///
  /// In en, this message translates to:
  /// **'Cannot load image'**
  String get filesCannotLoadImage;

  /// No description provided for @filesImageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Image load failed'**
  String get filesImageLoadFailed;

  /// No description provided for @filesCannotGetImageUrl.
  ///
  /// In en, this message translates to:
  /// **'Cannot get image URL'**
  String get filesCannotGetImageUrl;

  /// No description provided for @filesCannotLoadVideo.
  ///
  /// In en, this message translates to:
  /// **'Cannot load video'**
  String get filesCannotLoadVideo;

  /// No description provided for @filesCannotGetVideoUrl.
  ///
  /// In en, this message translates to:
  /// **'Cannot get video URL'**
  String get filesCannotGetVideoUrl;

  /// No description provided for @filesCannotLoadAudio.
  ///
  /// In en, this message translates to:
  /// **'Cannot load audio'**
  String get filesCannotLoadAudio;

  /// No description provided for @filesCannotGetAudioUrl.
  ///
  /// In en, this message translates to:
  /// **'Cannot get audio URL'**
  String get filesCannotGetAudioUrl;

  /// No description provided for @filesCannotLoadFile.
  ///
  /// In en, this message translates to:
  /// **'Cannot load file'**
  String get filesCannotLoadFile;

  /// No description provided for @filesCannotGetFileUrl.
  ///
  /// In en, this message translates to:
  /// **'Cannot get file URL'**
  String get filesCannotGetFileUrl;

  /// No description provided for @filesPdfUnsupported.
  ///
  /// In en, this message translates to:
  /// **'PDF preview is not supported on this platform. Please download to view.'**
  String get filesPdfUnsupported;

  /// No description provided for @filesType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get filesType;

  /// No description provided for @filesUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get filesUnknown;

  /// No description provided for @filesSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get filesSizeLabel;

  /// No description provided for @filesPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get filesPath;

  /// No description provided for @filesShareAccessError.
  ///
  /// In en, this message translates to:
  /// **'Cannot access share link'**
  String get filesShareAccessError;

  /// No description provided for @filesRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get filesRetry;

  /// No description provided for @filesSavedToMyFiles.
  ///
  /// In en, this message translates to:
  /// **'File saved to my files'**
  String get filesSavedToMyFiles;

  /// No description provided for @filesFileExists.
  ///
  /// In en, this message translates to:
  /// **'File already exists'**
  String get filesFileExists;

  /// No description provided for @filesGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get filesGotIt;

  /// No description provided for @filesSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {message}'**
  String filesSaveFailed(Object message);

  /// No description provided for @filesPasswordAccess.
  ///
  /// In en, this message translates to:
  /// **'This share requires password access'**
  String get filesPasswordAccess;

  /// No description provided for @filesEnterSharePassword.
  ///
  /// In en, this message translates to:
  /// **'Enter share password to view the file'**
  String get filesEnterSharePassword;

  /// No description provided for @filesAccess.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get filesAccess;

  /// No description provided for @filesSaveToMyFiles.
  ///
  /// In en, this message translates to:
  /// **'Save to my files'**
  String get filesSaveToMyFiles;

  /// No description provided for @filesDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get filesDelete;

  /// No description provided for @filesCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get filesCancel;

  /// No description provided for @filesConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get filesConfirm;

  /// No description provided for @filesOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get filesOpenTooltip;

  /// No description provided for @filesConflictMsg.
  ///
  /// In en, this message translates to:
  /// **'A file with the same name \"{name}\" exists in the recycle bin. Clean up and retry.'**
  String filesConflictMsg(Object name);

  /// No description provided for @filesStatusConflict.
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get filesStatusConflict;

  /// No description provided for @filesStatusCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get filesStatusCreated;

  /// No description provided for @filesLocalUpload.
  ///
  /// In en, this message translates to:
  /// **'Local Upload'**
  String get filesLocalUpload;

  /// No description provided for @filesUploadTaskCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tasks'**
  String filesUploadTaskCount(Object count);

  /// No description provided for @filesNoLocalUpload.
  ///
  /// In en, this message translates to:
  /// **'No local uploads'**
  String get filesNoLocalUpload;

  /// No description provided for @filesFailedTasks.
  ///
  /// In en, this message translates to:
  /// **'Failed Tasks'**
  String get filesFailedTasks;

  /// No description provided for @filesNoFailedTasks.
  ///
  /// In en, this message translates to:
  /// **'No failed tasks'**
  String get filesNoFailedTasks;

  /// No description provided for @filesNoUploadTasks.
  ///
  /// In en, this message translates to:
  /// **'No upload tasks'**
  String get filesNoUploadTasks;

  /// No description provided for @filesPauseUpload.
  ///
  /// In en, this message translates to:
  /// **'Pause Upload'**
  String get filesPauseUpload;

  /// No description provided for @filesResumeUpload.
  ///
  /// In en, this message translates to:
  /// **'Resume Upload'**
  String get filesResumeUpload;

  /// No description provided for @filesCleanAndRetry.
  ///
  /// In en, this message translates to:
  /// **'Clean up and retry'**
  String get filesCleanAndRetry;

  /// No description provided for @filesOfflineQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get filesOfflineQueued;

  /// No description provided for @filesOfflineRunning.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get filesOfflineRunning;

  /// No description provided for @filesOfflineCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling'**
  String get filesOfflineCancelling;

  /// No description provided for @filesOfflineCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get filesOfflineCancelled;

  /// No description provided for @filesImportQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get filesImportQueued;

  /// No description provided for @filesImportScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning source content'**
  String get filesImportScanning;

  /// No description provided for @filesImportTransferring.
  ///
  /// In en, this message translates to:
  /// **'Transferring from external storage'**
  String get filesImportTransferring;

  /// No description provided for @filesImportWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing to the file library'**
  String get filesImportWriting;

  /// No description provided for @filesImportWaitingWorker.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the background worker'**
  String get filesImportWaitingWorker;

  /// No description provided for @filesImportFileProgress.
  ///
  /// In en, this message translates to:
  /// **'{completed}/{total} files completed'**
  String filesImportFileProgress(int completed, int total);

  /// No description provided for @filesImportCurrentFile.
  ///
  /// In en, this message translates to:
  /// **'Current: {name}'**
  String filesImportCurrentFile(Object name);

  /// No description provided for @filesImportRunning.
  ///
  /// In en, this message translates to:
  /// **'Importing'**
  String get filesImportRunning;

  /// No description provided for @filesImportCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling'**
  String get filesImportCancelling;

  /// No description provided for @filesImportCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get filesImportCancelled;

  /// No description provided for @filesS3Compatible.
  ///
  /// In en, this message translates to:
  /// **'S3 Compatible Storage'**
  String get filesS3Compatible;

  /// No description provided for @filesAliyunDrive.
  ///
  /// In en, this message translates to:
  /// **'Aliyun Drive'**
  String get filesAliyunDrive;

  /// No description provided for @filesLocalStorage.
  ///
  /// In en, this message translates to:
  /// **'Local Directory'**
  String get filesLocalStorage;

  /// No description provided for @portalSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get portalSearch;

  /// No description provided for @portalOpenReadingItem.
  ///
  /// In en, this message translates to:
  /// **'Open Reading'**
  String get portalOpenReadingItem;

  /// No description provided for @portalOpenPhoto.
  ///
  /// In en, this message translates to:
  /// **'View Photo'**
  String get portalOpenPhoto;

  /// No description provided for @portalEnterSystem.
  ///
  /// In en, this message translates to:
  /// **'Enter System'**
  String get portalEnterSystem;

  /// No description provided for @portalVisualCompactTitle.
  ///
  /// In en, this message translates to:
  /// **'Desktop Portal switched to one column'**
  String get portalVisualCompactTitle;

  /// No description provided for @portalVisualCompactBody.
  ///
  /// In en, this message translates to:
  /// **'The current window is narrow, so content covers and status information are stacked.'**
  String get portalVisualCompactBody;

  /// No description provided for @portalVisualEyebrowRecentContent.
  ///
  /// In en, this message translates to:
  /// **'Recent Content'**
  String get portalVisualEyebrowRecentContent;

  /// No description provided for @portalVisualEyebrowCompact.
  ///
  /// In en, this message translates to:
  /// **'OmniNest Portal'**
  String get portalVisualEyebrowCompact;

  /// No description provided for @portalVisualStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Needs Attention'**
  String get portalVisualStatusTitle;

  /// No description provided for @portalVisualLastReadingLocation.
  ///
  /// In en, this message translates to:
  /// **'Last reading position'**
  String get portalVisualLastReadingLocation;

  /// No description provided for @portalVisualSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get portalVisualSync;

  /// No description provided for @portalFileManager.
  ///
  /// In en, this message translates to:
  /// **'File Manager'**
  String get portalFileManager;

  /// No description provided for @portalFileManagerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Network storage, folders, recycle bin and object preview.'**
  String get portalFileManagerSubtitle;

  /// No description provided for @portalMovieCenter.
  ///
  /// In en, this message translates to:
  /// **'Media Library'**
  String get portalMovieCenter;

  /// No description provided for @portalMovieCenterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage movies, TV series, and anime with metadata sync and direct playback.'**
  String get portalMovieCenterSubtitle;

  /// No description provided for @portalReaderCenter.
  ///
  /// In en, this message translates to:
  /// **'Reader Center'**
  String get portalReaderCenter;

  /// No description provided for @portalReaderCenterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Books, comics, and reading progress continuation.'**
  String get portalReaderCenterSubtitle;

  /// No description provided for @portalMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get portalMusic;

  /// No description provided for @portalMusicSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lossless music, play queue and playlist management.'**
  String get portalMusicSubtitle;

  /// No description provided for @portalPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get portalPhotos;

  /// No description provided for @portalPhotosSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Albums, auto backup and memory timeline.'**
  String get portalPhotosSubtitle;

  /// No description provided for @portalAdmin.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get portalAdmin;

  /// No description provided for @portalAdminSubtitle.
  ///
  /// In en, this message translates to:
  /// **'User permissions, system config, tasks and status.'**
  String get portalAdminSubtitle;

  /// No description provided for @portalDescriptionAdmin.
  ///
  /// In en, this message translates to:
  /// **'Switch between media, reading, files and system admin from one entry; each subsystem has its own workspace.'**
  String get portalDescriptionAdmin;

  /// No description provided for @portalDescriptionMember.
  ///
  /// In en, this message translates to:
  /// **'Switch between media, reading and file management from one entry; each subsystem has its own workspace.'**
  String get portalDescriptionMember;

  /// No description provided for @portalNoFiles.
  ///
  /// In en, this message translates to:
  /// **'No files'**
  String get portalNoFiles;

  /// No description provided for @portalNoPlayHistory.
  ///
  /// In en, this message translates to:
  /// **'No play history'**
  String get portalNoPlayHistory;

  /// No description provided for @portalNoReadingHistory.
  ///
  /// In en, this message translates to:
  /// **'No reading history'**
  String get portalNoReadingHistory;

  /// No description provided for @portalNoPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos'**
  String get portalNoPhotos;

  /// No description provided for @portalPhotoCount.
  ///
  /// In en, this message translates to:
  /// **'{count} photos'**
  String portalPhotoCount(Object count);

  /// No description provided for @portalAlbumCount.
  ///
  /// In en, this message translates to:
  /// **'{count} albums'**
  String portalAlbumCount(Object count);

  /// No description provided for @portalMovieBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} movies'**
  String portalMovieBadge(Object count);

  /// No description provided for @portalReaderBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} reading'**
  String portalReaderBadge(Object count);

  /// No description provided for @portalMusicBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks'**
  String portalMusicBadge(Object count);

  /// No description provided for @portalPhotoBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} photos'**
  String portalPhotoBadge(Object count);

  /// No description provided for @portalRelativeNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get portalRelativeNow;

  /// No description provided for @portalRelativeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{n} min ago'**
  String portalRelativeMinutes(Object n);

  /// No description provided for @portalRelativeHours.
  ///
  /// In en, this message translates to:
  /// **'{n} hr ago'**
  String portalRelativeHours(Object n);

  /// No description provided for @portalRelativeYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get portalRelativeYesterday;

  /// No description provided for @portalRelativeDays.
  ///
  /// In en, this message translates to:
  /// **'{n} days ago'**
  String portalRelativeDays(Object n);

  /// No description provided for @portalRelativeMonths.
  ///
  /// In en, this message translates to:
  /// **'{n} months ago'**
  String portalRelativeMonths(Object n);

  /// No description provided for @portalRelativeYears.
  ///
  /// In en, this message translates to:
  /// **'{n} years ago'**
  String portalRelativeYears(Object n);

  /// No description provided for @portalStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get portalStorageTitle;

  /// No description provided for @portalStorageUnlimited.
  ///
  /// In en, this message translates to:
  /// **'{used} GiB / Unlimited'**
  String portalStorageUnlimited(Object used);

  /// No description provided for @portalTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get portalTaskTitle;

  /// No description provided for @portalTaskRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get portalTaskRunning;

  /// No description provided for @portalTaskQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get portalTaskQueued;

  /// No description provided for @portalTaskFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get portalTaskFailed;

  /// No description provided for @portalNowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now Playing'**
  String get portalNowPlaying;

  /// No description provided for @portalNoPlayRecord.
  ///
  /// In en, this message translates to:
  /// **'No play record'**
  String get portalNoPlayRecord;

  /// No description provided for @portalImmersivePlayback.
  ///
  /// In en, this message translates to:
  /// **'Immersive playback'**
  String get portalImmersivePlayback;

  /// No description provided for @portalExitImmersivePlayback.
  ///
  /// In en, this message translates to:
  /// **'Exit immersive playback'**
  String get portalExitImmersivePlayback;

  /// No description provided for @portalMusicVisualizerOpenSystem.
  ///
  /// In en, this message translates to:
  /// **'Open Music'**
  String get portalMusicVisualizerOpenSystem;

  /// No description provided for @portalMusicVisualizerSeek.
  ///
  /// In en, this message translates to:
  /// **'Playback progress'**
  String get portalMusicVisualizerSeek;

  /// No description provided for @portalMusicVisualizerVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get portalMusicVisualizerVolume;

  /// No description provided for @portalMusicVisualizerEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit visuals'**
  String get portalMusicVisualizerEdit;

  /// No description provided for @portalMusicVisualizerSave.
  ///
  /// In en, this message translates to:
  /// **'Save visuals'**
  String get portalMusicVisualizerSave;

  /// No description provided for @portalMusicVisualizerResetDefault.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults'**
  String get portalMusicVisualizerResetDefault;

  /// No description provided for @portalMusicVisualizerLyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get portalMusicVisualizerLyrics;

  /// No description provided for @portalMusicVisualizerPlayer.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get portalMusicVisualizerPlayer;

  /// No description provided for @portalMusicVisualizerLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get portalMusicVisualizerLow;

  /// No description provided for @portalMusicVisualizerMid.
  ///
  /// In en, this message translates to:
  /// **'Mid'**
  String get portalMusicVisualizerMid;

  /// No description provided for @portalMusicVisualizerHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get portalMusicVisualizerHigh;

  /// No description provided for @portalMusicVisualizerCurrentFont.
  ///
  /// In en, this message translates to:
  /// **'Current line size'**
  String get portalMusicVisualizerCurrentFont;

  /// No description provided for @portalMusicVisualizerInactiveOpacity.
  ///
  /// In en, this message translates to:
  /// **'Inactive opacity'**
  String get portalMusicVisualizerInactiveOpacity;

  /// No description provided for @portalMusicVisualizerVisibleLines.
  ///
  /// In en, this message translates to:
  /// **'Visible lines'**
  String get portalMusicVisualizerVisibleLines;

  /// No description provided for @musicVisualizerLyricActiveColor.
  ///
  /// In en, this message translates to:
  /// **'Current line color'**
  String get musicVisualizerLyricActiveColor;

  /// No description provided for @musicVisualizerLyricReadColor.
  ///
  /// In en, this message translates to:
  /// **'Played line color'**
  String get musicVisualizerLyricReadColor;

  /// No description provided for @musicVisualizerLyricUnreadColor.
  ///
  /// In en, this message translates to:
  /// **'Upcoming line color'**
  String get musicVisualizerLyricUnreadColor;

  /// No description provided for @musicVisualizerLyricBreathing.
  ///
  /// In en, this message translates to:
  /// **'Lyric breathing'**
  String get musicVisualizerLyricBreathing;

  /// No description provided for @musicVisualizerLyricLineSpacing.
  ///
  /// In en, this message translates to:
  /// **'Line spacing'**
  String get musicVisualizerLyricLineSpacing;

  /// No description provided for @musicVisualizerLyricGlowIntensity.
  ///
  /// In en, this message translates to:
  /// **'Glow intensity'**
  String get musicVisualizerLyricGlowIntensity;

  /// No description provided for @musicVisualizerLyricGlowColor.
  ///
  /// In en, this message translates to:
  /// **'Glow color'**
  String get musicVisualizerLyricGlowColor;

  /// No description provided for @musicVisualizerLyricPosition.
  ///
  /// In en, this message translates to:
  /// **'Lyric position'**
  String get musicVisualizerLyricPosition;

  /// No description provided for @musicVisualizerLyricPositionLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get musicVisualizerLyricPositionLeft;

  /// No description provided for @musicVisualizerLyricPositionCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get musicVisualizerLyricPositionCenter;

  /// No description provided for @musicVisualizerLyricPositionRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get musicVisualizerLyricPositionRight;

  /// No description provided for @musicVisualizerAudioBarStyle.
  ///
  /// In en, this message translates to:
  /// **'Audio bar style'**
  String get musicVisualizerAudioBarStyle;

  /// No description provided for @musicVisualizerAudioBarSpectrum.
  ///
  /// In en, this message translates to:
  /// **'Spectrum bars'**
  String get musicVisualizerAudioBarSpectrum;

  /// No description provided for @musicVisualizerAudioBarLine.
  ///
  /// In en, this message translates to:
  /// **'Light trace'**
  String get musicVisualizerAudioBarLine;

  /// No description provided for @musicVisualizerAudioBarDots.
  ///
  /// In en, this message translates to:
  /// **'Pulse dots'**
  String get musicVisualizerAudioBarDots;

  /// No description provided for @musicVisualizerColorHue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get musicVisualizerColorHue;

  /// No description provided for @musicVisualizerColorSaturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get musicVisualizerColorSaturation;

  /// No description provided for @musicVisualizerColorBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get musicVisualizerColorBrightness;

  /// No description provided for @portalMusicVisualizerLyricGlow.
  ///
  /// In en, this message translates to:
  /// **'Lyric glow'**
  String get portalMusicVisualizerLyricGlow;

  /// No description provided for @portalMusicVisualizerOriginalCover.
  ///
  /// In en, this message translates to:
  /// **'Original cover'**
  String get portalMusicVisualizerOriginalCover;

  /// No description provided for @portalMusicVisualizerCoverBorder.
  ///
  /// In en, this message translates to:
  /// **'Cover border'**
  String get portalMusicVisualizerCoverBorder;

  /// No description provided for @portalMusicVisualizerProgressControl.
  ///
  /// In en, this message translates to:
  /// **'Progress bar'**
  String get portalMusicVisualizerProgressControl;

  /// No description provided for @musicVisualizerPlayerVisible.
  ///
  /// In en, this message translates to:
  /// **'Show bottom player'**
  String get musicVisualizerPlayerVisible;

  /// No description provided for @musicVisualizerAudioBar.
  ///
  /// In en, this message translates to:
  /// **'Show audio bars'**
  String get musicVisualizerAudioBar;

  /// No description provided for @musicVisualizerFrequencyResponse.
  ///
  /// In en, this message translates to:
  /// **'Audio bar frequency response'**
  String get musicVisualizerFrequencyResponse;

  /// No description provided for @musicVisualizerCoverSize.
  ///
  /// In en, this message translates to:
  /// **'Cover size'**
  String get musicVisualizerCoverSize;

  /// No description provided for @musicVisualizerCoverRadius.
  ///
  /// In en, this message translates to:
  /// **'Cover radius'**
  String get musicVisualizerCoverRadius;

  /// No description provided for @musicVisualizerCoverTilt.
  ///
  /// In en, this message translates to:
  /// **'Cover tilt'**
  String get musicVisualizerCoverTilt;

  /// No description provided for @musicVisualizerHeroCoverOpacity.
  ///
  /// In en, this message translates to:
  /// **'Hero cover opacity'**
  String get musicVisualizerHeroCoverOpacity;

  /// No description provided for @portalReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get portalReading;

  /// No description provided for @portalNoReadingBook.
  ///
  /// In en, this message translates to:
  /// **'No books being read'**
  String get portalNoReadingBook;

  /// No description provided for @portalRecentPhotos.
  ///
  /// In en, this message translates to:
  /// **'Recent Photos'**
  String get portalRecentPhotos;

  /// No description provided for @portalNewPhotoCount.
  ///
  /// In en, this message translates to:
  /// **'{count} new photos'**
  String portalNewPhotoCount(Object count);

  /// No description provided for @portalQuickUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get portalQuickUpload;

  /// No description provided for @portalQuickDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get portalQuickDownload;

  /// No description provided for @portalQuickNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get portalQuickNew;

  /// No description provided for @portalQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get portalQuickActions;

  /// No description provided for @portalQuickSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get portalQuickSearch;

  /// No description provided for @portalQuickScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get portalQuickScan;

  /// No description provided for @portalQuickPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get portalQuickPlay;

  /// No description provided for @portalMobileGreetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get portalMobileGreetingMorning;

  /// No description provided for @portalMobileGreetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get portalMobileGreetingAfternoon;

  /// No description provided for @portalMobileGreetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get portalMobileGreetingEvening;

  /// No description provided for @portalMobileContinueUsing.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get portalMobileContinueUsing;

  /// No description provided for @portalMobileNoContinue.
  ///
  /// In en, this message translates to:
  /// **'Nothing waiting to resume'**
  String get portalMobileNoContinue;

  /// No description provided for @portalMobileSystemSummary.
  ///
  /// In en, this message translates to:
  /// **'System summary'**
  String get portalMobileSystemSummary;

  /// No description provided for @portalMobileSyncOnline.
  ///
  /// In en, this message translates to:
  /// **'Sync service online'**
  String get portalMobileSyncOnline;

  /// No description provided for @portalMobileSyncOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline, waiting to sync'**
  String get portalMobileSyncOffline;

  /// No description provided for @portalMobileTaskSummary.
  ///
  /// In en, this message translates to:
  /// **'{active} active, {failed} failed'**
  String portalMobileTaskSummary(Object active, Object failed);

  /// No description provided for @portalMobileStorageUsed.
  ///
  /// In en, this message translates to:
  /// **'{used} used'**
  String portalMobileStorageUsed(Object used);

  /// No description provided for @portalMobileViewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get portalMobileViewAll;

  /// No description provided for @portalContinueWatching.
  ///
  /// In en, this message translates to:
  /// **'Continue Watching'**
  String get portalContinueWatching;

  /// No description provided for @portalNoWatchingContent.
  ///
  /// In en, this message translates to:
  /// **'No content being watched'**
  String get portalNoWatchingContent;

  /// No description provided for @portalPressBackAgain.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get portalPressBackAgain;

  /// No description provided for @portalLoadMovieFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load media library info'**
  String get portalLoadMovieFailed;

  /// No description provided for @portalLoadMusicFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load music info'**
  String get portalLoadMusicFailed;

  /// No description provided for @portalLoadStorageFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load storage info'**
  String get portalLoadStorageFailed;

  /// No description provided for @portalLoadReadingFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load reading info'**
  String get portalLoadReadingFailed;

  /// No description provided for @portalLoadPhotoFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load photo info'**
  String get portalLoadPhotoFailed;

  /// No description provided for @portalDockFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get portalDockFiles;

  /// No description provided for @portalDockMovies.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get portalDockMovies;

  /// No description provided for @portalDockMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get portalDockMusic;

  /// No description provided for @portalDockPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get portalDockPhotos;

  /// No description provided for @portalDockReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get portalDockReading;

  /// No description provided for @portalWeatherTitle.
  ///
  /// In en, this message translates to:
  /// **'Weather'**
  String get portalWeatherTitle;

  /// No description provided for @portalWeatherUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get portalWeatherUpdated;

  /// No description provided for @portalWeatherDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get portalWeatherDisconnected;

  /// No description provided for @portalWeatherFeelsLike.
  ///
  /// In en, this message translates to:
  /// **'{text} · Feels like {feelsLike}°'**
  String portalWeatherFeelsLike(Object text, Object feelsLike);

  /// No description provided for @portalWeatherSunrise.
  ///
  /// In en, this message translates to:
  /// **'Sunrise {time}'**
  String portalWeatherSunrise(Object time);

  /// No description provided for @portalWeatherSunset.
  ///
  /// In en, this message translates to:
  /// **'Sunset {time}'**
  String portalWeatherSunset(Object time);

  /// No description provided for @portalWeatherConfigApiKey.
  ///
  /// In en, this message translates to:
  /// **'Please configure API Key'**
  String get portalWeatherConfigApiKey;

  /// No description provided for @portalWeatherWeeklyStats.
  ///
  /// In en, this message translates to:
  /// **'Weekly Stats'**
  String get portalWeatherWeeklyStats;

  /// No description provided for @portalWeatherStatReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get portalWeatherStatReading;

  /// No description provided for @portalWeatherStatPlaying.
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get portalWeatherStatPlaying;

  /// No description provided for @portalWeatherStatPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get portalWeatherStatPhotos;

  /// No description provided for @portalWeatherUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get portalWeatherUnknown;

  /// No description provided for @portalWeatherLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get portalWeatherLoading;

  /// No description provided for @portalWeatherDefaultLocation.
  ///
  /// In en, this message translates to:
  /// **'Beijing'**
  String get portalWeatherDefaultLocation;

  /// No description provided for @portalWeatherTipMask.
  ///
  /// In en, this message translates to:
  /// **'Poor air quality, wear a mask'**
  String get portalWeatherTipMask;

  /// No description provided for @portalWeatherTipRain.
  ///
  /// In en, this message translates to:
  /// **'Rain expected, bring an umbrella'**
  String get portalWeatherTipRain;

  /// No description provided for @portalWeatherTipIce.
  ///
  /// In en, this message translates to:
  /// **'Roads may be slippery, watch your step'**
  String get portalWeatherTipIce;

  /// No description provided for @portalWeatherTipUV.
  ///
  /// In en, this message translates to:
  /// **'Strong UV, protect from sun'**
  String get portalWeatherTipUV;

  /// No description provided for @portalWeatherTipCold.
  ///
  /// In en, this message translates to:
  /// **'Feels cold, dress warmly'**
  String get portalWeatherTipCold;

  /// No description provided for @portalWeatherTipHot.
  ///
  /// In en, this message translates to:
  /// **'Hot weather, stay hydrated'**
  String get portalWeatherTipHot;

  /// No description provided for @portalWeatherTipFog.
  ///
  /// In en, this message translates to:
  /// **'Foggy, drive safely'**
  String get portalWeatherTipFog;

  /// No description provided for @portalWeatherTipNice.
  ///
  /// In en, this message translates to:
  /// **'Nice weather, great for outdoor activities'**
  String get portalWeatherTipNice;

  /// No description provided for @portalWeatherHumidity.
  ///
  /// In en, this message translates to:
  /// **'Humidity'**
  String get portalWeatherHumidity;

  /// No description provided for @portalWeatherWind.
  ///
  /// In en, this message translates to:
  /// **'Wind'**
  String get portalWeatherWind;

  /// No description provided for @portalWeatherVisibility.
  ///
  /// In en, this message translates to:
  /// **'Visibility'**
  String get portalWeatherVisibility;

  /// No description provided for @portalWeatherPressure.
  ///
  /// In en, this message translates to:
  /// **'Pressure'**
  String get portalWeatherPressure;

  /// No description provided for @portalWeatherUV.
  ///
  /// In en, this message translates to:
  /// **'UV Index'**
  String get portalWeatherUV;

  /// No description provided for @portalWeatherPrecip.
  ///
  /// In en, this message translates to:
  /// **'Precip'**
  String get portalWeatherPrecip;

  /// No description provided for @portalWeatherAdvice.
  ///
  /// In en, this message translates to:
  /// **'Advice'**
  String get portalWeatherAdvice;

  /// No description provided for @portalWeatherSunriseLabel.
  ///
  /// In en, this message translates to:
  /// **'Sunrise'**
  String get portalWeatherSunriseLabel;

  /// No description provided for @portalWeatherSunsetLabel.
  ///
  /// In en, this message translates to:
  /// **'Sunset'**
  String get portalWeatherSunsetLabel;

  /// No description provided for @portalWeatherDebugTooltip.
  ///
  /// In en, this message translates to:
  /// **'Debug weather visuals'**
  String get portalWeatherDebugTooltip;

  /// No description provided for @portalWeatherDebugLive.
  ///
  /// In en, this message translates to:
  /// **'Live weather'**
  String get portalWeatherDebugLive;

  /// No description provided for @portalWeatherDebugDawn.
  ///
  /// In en, this message translates to:
  /// **'Dawn'**
  String get portalWeatherDebugDawn;

  /// No description provided for @portalWeatherDebugSunny.
  ///
  /// In en, this message translates to:
  /// **'Sunny'**
  String get portalWeatherDebugSunny;

  /// No description provided for @portalWeatherDebugSunnyNight.
  ///
  /// In en, this message translates to:
  /// **'Clear night'**
  String get portalWeatherDebugSunnyNight;

  /// No description provided for @portalWeatherDebugDusk.
  ///
  /// In en, this message translates to:
  /// **'Dusk'**
  String get portalWeatherDebugDusk;

  /// No description provided for @portalWeatherDebugPartlyCloudy.
  ///
  /// In en, this message translates to:
  /// **'Partly cloudy'**
  String get portalWeatherDebugPartlyCloudy;

  /// No description provided for @portalWeatherDebugPartlyCloudyNight.
  ///
  /// In en, this message translates to:
  /// **'Partly cloudy night'**
  String get portalWeatherDebugPartlyCloudyNight;

  /// No description provided for @portalWeatherDebugCloudy.
  ///
  /// In en, this message translates to:
  /// **'Cloudy'**
  String get portalWeatherDebugCloudy;

  /// No description provided for @portalWeatherDebugCloudyNight.
  ///
  /// In en, this message translates to:
  /// **'Cloudy night'**
  String get portalWeatherDebugCloudyNight;

  /// No description provided for @portalWeatherDebugLightRain.
  ///
  /// In en, this message translates to:
  /// **'Light rain'**
  String get portalWeatherDebugLightRain;

  /// No description provided for @portalWeatherDebugLightRainLeft.
  ///
  /// In en, this message translates to:
  /// **'Light rain left'**
  String get portalWeatherDebugLightRainLeft;

  /// No description provided for @portalWeatherDebugHeavyRain.
  ///
  /// In en, this message translates to:
  /// **'Heavy rain'**
  String get portalWeatherDebugHeavyRain;

  /// No description provided for @portalWeatherDebugHeavyRainRight.
  ///
  /// In en, this message translates to:
  /// **'Heavy rain right'**
  String get portalWeatherDebugHeavyRainRight;

  /// No description provided for @portalWeatherDebugRainNight.
  ///
  /// In en, this message translates to:
  /// **'Night rain'**
  String get portalWeatherDebugRainNight;

  /// No description provided for @portalWeatherDebugStorm.
  ///
  /// In en, this message translates to:
  /// **'Storm'**
  String get portalWeatherDebugStorm;

  /// No description provided for @portalWeatherDebugLightSnow.
  ///
  /// In en, this message translates to:
  /// **'Light snow'**
  String get portalWeatherDebugLightSnow;

  /// No description provided for @portalWeatherDebugHeavySnow.
  ///
  /// In en, this message translates to:
  /// **'Heavy snow'**
  String get portalWeatherDebugHeavySnow;

  /// No description provided for @portalWeatherDebugSnowNight.
  ///
  /// In en, this message translates to:
  /// **'Night snow'**
  String get portalWeatherDebugSnowNight;

  /// No description provided for @portalWeatherDebugFog.
  ///
  /// In en, this message translates to:
  /// **'Fog'**
  String get portalWeatherDebugFog;

  /// No description provided for @portalWeatherDebugHaze.
  ///
  /// In en, this message translates to:
  /// **'Haze'**
  String get portalWeatherDebugHaze;

  /// No description provided for @portalWeatherDebugDust.
  ///
  /// In en, this message translates to:
  /// **'Dust'**
  String get portalWeatherDebugDust;

  /// No description provided for @portalWeatherDebugHeat.
  ///
  /// In en, this message translates to:
  /// **'Heat'**
  String get portalWeatherDebugHeat;

  /// No description provided for @portalWeatherDebugCold.
  ///
  /// In en, this message translates to:
  /// **'Cold'**
  String get portalWeatherDebugCold;

  /// No description provided for @portalWeatherDebugTimeDawn.
  ///
  /// In en, this message translates to:
  /// **'Dawn'**
  String get portalWeatherDebugTimeDawn;

  /// No description provided for @portalWeatherDebugTimeDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get portalWeatherDebugTimeDay;

  /// No description provided for @portalWeatherDebugTimeDusk.
  ///
  /// In en, this message translates to:
  /// **'Dusk'**
  String get portalWeatherDebugTimeDusk;

  /// No description provided for @portalWeatherDebugTimeNight.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get portalWeatherDebugTimeNight;

  /// No description provided for @portalLocalBackdropShort.
  ///
  /// In en, this message translates to:
  /// **'Backdrops'**
  String get portalLocalBackdropShort;

  /// No description provided for @portalLocalBackdropTitle.
  ///
  /// In en, this message translates to:
  /// **'Local backdrops'**
  String get portalLocalBackdropTitle;

  /// No description provided for @portalLocalBackdropSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use local videos, GIFs, or images as the backdrop on this device. Assets are never uploaded.'**
  String get portalLocalBackdropSubtitle;

  /// No description provided for @portalLocalBackdropLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load local backdrops'**
  String get portalLocalBackdropLoadFailed;

  /// No description provided for @portalLocalBackdropAddFiles.
  ///
  /// In en, this message translates to:
  /// **'Add files'**
  String get portalLocalBackdropAddFiles;

  /// No description provided for @portalLocalBackdropScanDirectory.
  ///
  /// In en, this message translates to:
  /// **'Scan folder'**
  String get portalLocalBackdropScanDirectory;

  /// No description provided for @portalLocalBackdropClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get portalLocalBackdropClearAll;

  /// No description provided for @portalLocalBackdropClearAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear all local backdrops?'**
  String get portalLocalBackdropClearAllTitle;

  /// No description provided for @portalLocalBackdropClearAllMessage.
  ///
  /// In en, this message translates to:
  /// **'This only clears the backdrop index in this device\'s SQLite database. Your original local files are not deleted.'**
  String get portalLocalBackdropClearAllMessage;

  /// No description provided for @portalLocalBackdropClearAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get portalLocalBackdropClearAllConfirm;

  /// No description provided for @portalLocalBackdropCount.
  ///
  /// In en, this message translates to:
  /// **'{count} backdrops'**
  String portalLocalBackdropCount(Object count);

  /// No description provided for @portalLocalBackdropEmpty.
  ///
  /// In en, this message translates to:
  /// **'No local backdrops yet. Add video backdrops, GIFs, images, or scan a folder that contains them.'**
  String get portalLocalBackdropEmpty;

  /// No description provided for @portalLocalBackdropFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No backdrops in this category'**
  String get portalLocalBackdropFilterEmpty;

  /// No description provided for @portalLocalBackdropEmptyScan.
  ///
  /// In en, this message translates to:
  /// **'No usable backdrop files found. MP4, WEBM, MOV, M4V, GIF, JPG, PNG, and WEBP are supported.'**
  String get portalLocalBackdropEmptyScan;

  /// No description provided for @portalLocalBackdropScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Scan failed. Check folder permissions.'**
  String get portalLocalBackdropScanFailed;

  /// No description provided for @portalLocalBackdropMissing.
  ///
  /// In en, this message translates to:
  /// **'File missing'**
  String get portalLocalBackdropMissing;

  /// No description provided for @portalLocalBackdropRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove backdrop'**
  String get portalLocalBackdropRemove;

  /// No description provided for @portalLocalBackdropEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable local backdrop'**
  String get portalLocalBackdropEnable;

  /// No description provided for @portalLocalBackdropEnableHint.
  ///
  /// In en, this message translates to:
  /// **'Used by Digital Gallery and Music. Local asset paths are never synced to the server.'**
  String get portalLocalBackdropEnableHint;

  /// No description provided for @portalLocalBackdropSeparateDevices.
  ///
  /// In en, this message translates to:
  /// **'Separate desktop and mobile'**
  String get portalLocalBackdropSeparateDevices;

  /// No description provided for @portalLocalBackdropSeparateDevicesHint.
  ///
  /// In en, this message translates to:
  /// **'Off uses one shared selection. On keeps a separate backdrop for each device class.'**
  String get portalLocalBackdropSeparateDevicesHint;

  /// No description provided for @portalLocalBackdropCurrentDesktop.
  ///
  /// In en, this message translates to:
  /// **'Currently configuring the desktop backdrop'**
  String get portalLocalBackdropCurrentDesktop;

  /// No description provided for @portalLocalBackdropCurrentMobile.
  ///
  /// In en, this message translates to:
  /// **'Currently configuring the mobile backdrop'**
  String get portalLocalBackdropCurrentMobile;

  /// No description provided for @portalLocalBackdropFit.
  ///
  /// In en, this message translates to:
  /// **'Display mode'**
  String get portalLocalBackdropFit;

  /// No description provided for @portalLocalBackdropFitCover.
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get portalLocalBackdropFitCover;

  /// No description provided for @portalLocalBackdropFitContain.
  ///
  /// In en, this message translates to:
  /// **'Fit'**
  String get portalLocalBackdropFitContain;

  /// No description provided for @portalLocalBackdropFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get portalLocalBackdropFilterAll;

  /// No description provided for @portalLocalBackdropFilterJpeg.
  ///
  /// In en, this message translates to:
  /// **'JPG'**
  String get portalLocalBackdropFilterJpeg;

  /// No description provided for @portalLocalBackdropFilterPng.
  ///
  /// In en, this message translates to:
  /// **'PNG'**
  String get portalLocalBackdropFilterPng;

  /// No description provided for @portalLocalBackdropFilterWebp.
  ///
  /// In en, this message translates to:
  /// **'WEBP'**
  String get portalLocalBackdropFilterWebp;

  /// No description provided for @portalLocalBackdropFilterGif.
  ///
  /// In en, this message translates to:
  /// **'GIF'**
  String get portalLocalBackdropFilterGif;

  /// No description provided for @portalLocalBackdropFilterMp4.
  ///
  /// In en, this message translates to:
  /// **'MP4'**
  String get portalLocalBackdropFilterMp4;

  /// No description provided for @portalLocalBackdropFilterWebm.
  ///
  /// In en, this message translates to:
  /// **'WEBM'**
  String get portalLocalBackdropFilterWebm;

  /// No description provided for @portalLocalBackdropFilterMov.
  ///
  /// In en, this message translates to:
  /// **'MOV'**
  String get portalLocalBackdropFilterMov;

  /// No description provided for @portalLocalBackdropFilterM4v.
  ///
  /// In en, this message translates to:
  /// **'M4V'**
  String get portalLocalBackdropFilterM4v;

  /// No description provided for @portalLocalBackdropDim.
  ///
  /// In en, this message translates to:
  /// **'Dim'**
  String get portalLocalBackdropDim;

  /// No description provided for @portalLocalBackdropBlur.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get portalLocalBackdropBlur;

  /// No description provided for @portalLocalBackdropVideoMuted.
  ///
  /// In en, this message translates to:
  /// **'Mute video'**
  String get portalLocalBackdropVideoMuted;

  /// No description provided for @portalLocalBackdropRetryPlayback.
  ///
  /// In en, this message translates to:
  /// **'Retry playback'**
  String get portalLocalBackdropRetryPlayback;

  /// No description provided for @portalLocalBackdropLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'Backdrop paths are stored only in SQLite on this device. Use short loops with common codecs; playback pauses when the page is hidden or the app enters the background. Web uses the default theme backdrop.'**
  String get portalLocalBackdropLocalOnly;

  /// No description provided for @adminOpenMenu.
  ///
  /// In en, this message translates to:
  /// **'Open admin menu'**
  String get adminOpenMenu;

  /// No description provided for @adminStorageOverview.
  ///
  /// In en, this message translates to:
  /// **'Storage Overview'**
  String get adminStorageOverview;

  /// No description provided for @adminPercentUsed.
  ///
  /// In en, this message translates to:
  /// **'{percent}% used'**
  String adminPercentUsed(Object percent);

  /// No description provided for @adminSystemMonitoring.
  ///
  /// In en, this message translates to:
  /// **'System Monitoring'**
  String get adminSystemMonitoring;

  /// No description provided for @adminMonitoringSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View service status, resource usage, component health, alerts and admin operation records.'**
  String get adminMonitoringSubtitle;

  /// No description provided for @adminRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get adminRunning;

  /// No description provided for @adminAttentionItems.
  ///
  /// In en, this message translates to:
  /// **'{count} items to watch'**
  String adminAttentionItems(Object count);

  /// No description provided for @adminServiceStatus.
  ///
  /// In en, this message translates to:
  /// **'Service Status'**
  String get adminServiceStatus;

  /// No description provided for @adminUptime.
  ///
  /// In en, this message translates to:
  /// **'Uptime {uptime}'**
  String adminUptime(Object uptime);

  /// No description provided for @adminComponents.
  ///
  /// In en, this message translates to:
  /// **'Components'**
  String get adminComponents;

  /// No description provided for @adminAlerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get adminAlerts;

  /// No description provided for @adminSystemCpu.
  ///
  /// In en, this message translates to:
  /// **'System CPU'**
  String get adminSystemCpu;

  /// No description provided for @adminMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get adminMemory;

  /// No description provided for @adminDiskUsage.
  ///
  /// In en, this message translates to:
  /// **'Disk Usage'**
  String get adminDiskUsage;

  /// No description provided for @adminDataDirectoryDisk.
  ///
  /// In en, this message translates to:
  /// **'Data directory disk'**
  String get adminDataDirectoryDisk;

  /// No description provided for @adminRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get adminRequests;

  /// No description provided for @adminComponentHealth.
  ///
  /// In en, this message translates to:
  /// **'Component Health'**
  String get adminComponentHealth;

  /// No description provided for @adminComponentHealthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Current snapshot of database, Redis, RabbitMQ, MinIO and index components.'**
  String get adminComponentHealthSubtitle;

  /// No description provided for @adminNoComponentHealth.
  ///
  /// In en, this message translates to:
  /// **'No component health data.'**
  String get adminNoComponentHealth;

  /// No description provided for @adminRecentAlerts.
  ///
  /// In en, this message translates to:
  /// **'Recent System Alerts'**
  String get adminRecentAlerts;

  /// No description provided for @adminRecentAlertsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Generated by snapshot rules, can be connected to real alert table later.'**
  String get adminRecentAlertsSubtitle;

  /// No description provided for @adminNoAlerts.
  ///
  /// In en, this message translates to:
  /// **'No system alerts.'**
  String get adminNoAlerts;

  /// No description provided for @adminRecentOperations.
  ///
  /// In en, this message translates to:
  /// **'Recent Operations'**
  String get adminRecentOperations;

  /// No description provided for @adminRecentOperationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'From audit logs, useful for troubleshooting config and admin actions.'**
  String get adminRecentOperationsSubtitle;

  /// No description provided for @adminNoOperations.
  ///
  /// In en, this message translates to:
  /// **'No admin operation records.'**
  String get adminNoOperations;

  /// No description provided for @adminTrendCharts.
  ///
  /// In en, this message translates to:
  /// **'Real-time Trend Charts'**
  String get adminTrendCharts;

  /// No description provided for @adminTrendChartsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Currently showing 55-minute sampling trends, can be replaced with real time-series storage later.'**
  String get adminTrendChartsSubtitle;

  /// No description provided for @adminNoTrendData.
  ///
  /// In en, this message translates to:
  /// **'No trend data.'**
  String get adminNoTrendData;

  /// No description provided for @adminAnalyticsDataHint.
  ///
  /// In en, this message translates to:
  /// **'Data will be collected automatically once the system is running.'**
  String get adminAnalyticsDataHint;

  /// No description provided for @adminRealtime.
  ///
  /// In en, this message translates to:
  /// **'Realtime'**
  String get adminRealtime;

  /// No description provided for @adminLogCenter.
  ///
  /// In en, this message translates to:
  /// **'Log Center'**
  String get adminLogCenter;

  /// No description provided for @adminLogCenterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unified view of operation audit and login logs.'**
  String get adminLogCenterSubtitle;

  /// No description provided for @adminAuditCount.
  ///
  /// In en, this message translates to:
  /// **'{count} audit records'**
  String adminAuditCount(Object count);

  /// No description provided for @adminTabAudit.
  ///
  /// In en, this message translates to:
  /// **'Operation Audit'**
  String get adminTabAudit;

  /// No description provided for @adminTabLoginLog.
  ///
  /// In en, this message translates to:
  /// **'Login Log'**
  String get adminTabLoginLog;

  /// No description provided for @adminRecentAudit.
  ///
  /// In en, this message translates to:
  /// **'Recent Audit'**
  String get adminRecentAudit;

  /// No description provided for @adminRecentAuditSubtitle.
  ///
  /// In en, this message translates to:
  /// **'From audit_logs, sorted by creation time descending.'**
  String get adminRecentAuditSubtitle;

  /// No description provided for @adminNoAuditLogs.
  ///
  /// In en, this message translates to:
  /// **'No audit logs.'**
  String get adminNoAuditLogs;

  /// No description provided for @adminNoLoginLogs.
  ///
  /// In en, this message translates to:
  /// **'No login logs.'**
  String get adminNoLoginLogs;

  /// No description provided for @adminLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String adminLoadFailed(Object error);

  /// No description provided for @adminLoginLog.
  ///
  /// In en, this message translates to:
  /// **'Login Log'**
  String get adminLoginLog;

  /// No description provided for @adminLoginLogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'From auth_login_audit, records all login attempts.'**
  String get adminLoginLogSubtitle;

  /// No description provided for @adminLoginSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get adminLoginSuccess;

  /// No description provided for @adminLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get adminLoginFailed;

  /// No description provided for @adminFilterAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get adminFilterAction;

  /// No description provided for @adminFilterStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get adminFilterStatus;

  /// No description provided for @adminFilterPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get adminFilterPlatform;

  /// No description provided for @adminCleanup.
  ///
  /// In en, this message translates to:
  /// **'Clean up'**
  String get adminCleanup;

  /// No description provided for @adminRetentionDays.
  ///
  /// In en, this message translates to:
  /// **'Keep {days} days'**
  String adminRetentionDays(Object days);

  /// No description provided for @adminCleanupConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm cleanup'**
  String get adminCleanupConfirmTitle;

  /// No description provided for @adminCleanupConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Records outside the retention period will be deleted permanently.'**
  String get adminCleanupConfirmMessage;

  /// No description provided for @adminCleanupCompleted.
  ///
  /// In en, this message translates to:
  /// **'Cleaned up {count} records'**
  String adminCleanupCompleted(Object count);

  /// No description provided for @adminBackgroundTasks.
  ///
  /// In en, this message translates to:
  /// **'Background Tasks'**
  String get adminBackgroundTasks;

  /// No description provided for @adminBackgroundTasksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track indexing, transcoding, sync, backup and cleanup tasks.'**
  String get adminBackgroundTasksSubtitle;

  /// No description provided for @adminTotalTasks.
  ///
  /// In en, this message translates to:
  /// **'Total Tasks'**
  String get adminTotalTasks;

  /// No description provided for @adminRecentTasks.
  ///
  /// In en, this message translates to:
  /// **'Recent tasks'**
  String get adminRecentTasks;

  /// No description provided for @adminRunningTasks.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get adminRunningTasks;

  /// No description provided for @adminExecuting.
  ///
  /// In en, this message translates to:
  /// **'Executing'**
  String get adminExecuting;

  /// No description provided for @adminFailedTasks.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get adminFailedTasks;

  /// No description provided for @adminRetryable.
  ///
  /// In en, this message translates to:
  /// **'Retryable'**
  String get adminRetryable;

  /// No description provided for @adminTaskList.
  ///
  /// In en, this message translates to:
  /// **'Task List'**
  String get adminTaskList;

  /// No description provided for @adminTaskStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get adminTaskStatusRunning;

  /// No description provided for @adminTaskStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get adminTaskStatusCompleted;

  /// No description provided for @adminTaskStatusDlq.
  ///
  /// In en, this message translates to:
  /// **'Dead letter'**
  String get adminTaskStatusDlq;

  /// No description provided for @adminTaskErrorSummary.
  ///
  /// In en, this message translates to:
  /// **'Error summary'**
  String get adminTaskErrorSummary;

  /// No description provided for @adminTaskUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated at'**
  String get adminTaskUpdatedAt;

  /// No description provided for @adminTaskName.
  ///
  /// In en, this message translates to:
  /// **'Task name'**
  String get adminTaskName;

  /// No description provided for @adminTaskExecutionStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get adminTaskExecutionStatus;

  /// No description provided for @adminTaskListSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Failed, cancelled and DLQ status support re-queue.'**
  String get adminTaskListSubtitle;

  /// No description provided for @adminNoBackgroundTasks.
  ///
  /// In en, this message translates to:
  /// **'No background tasks.'**
  String get adminNoBackgroundTasks;

  /// No description provided for @adminNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get adminNotSet;

  /// No description provided for @adminProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get adminProgress;

  /// No description provided for @adminRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get adminRetry;

  /// No description provided for @adminRoleManagement.
  ///
  /// In en, this message translates to:
  /// **'Role Management'**
  String get adminRoleManagement;

  /// No description provided for @adminRoleManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Maintain roles, permission sets and resource access boundaries.'**
  String get adminRoleManagementSubtitle;

  /// No description provided for @adminPermissionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} permissions'**
  String adminPermissionCount(Object count);

  /// No description provided for @adminRoles.
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get adminRoles;

  /// No description provided for @adminSystemRoles.
  ///
  /// In en, this message translates to:
  /// **'System roles'**
  String get adminSystemRoles;

  /// No description provided for @adminPermissionBindings.
  ///
  /// In en, this message translates to:
  /// **'Permission Bindings'**
  String get adminPermissionBindings;

  /// No description provided for @adminRolePermissions.
  ///
  /// In en, this message translates to:
  /// **'Role permissions'**
  String get adminRolePermissions;

  /// No description provided for @adminPermissionModules.
  ///
  /// In en, this message translates to:
  /// **'Permission Modules'**
  String get adminPermissionModules;

  /// No description provided for @adminBusinessDomains.
  ///
  /// In en, this message translates to:
  /// **'Business domains'**
  String get adminBusinessDomains;

  /// No description provided for @adminRolePermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Role Permissions'**
  String get adminRolePermissionsTitle;

  /// No description provided for @adminRolePermissionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Built-in roles cannot be deleted, SUPER_ADMIN permissions maintained by system.'**
  String get adminRolePermissionsSubtitle;

  /// No description provided for @adminNoRoles.
  ///
  /// In en, this message translates to:
  /// **'No role data.'**
  String get adminNoRoles;

  /// No description provided for @adminPermissionCountInline.
  ///
  /// In en, this message translates to:
  /// **'{count} permissions'**
  String adminPermissionCountInline(Object count);

  /// No description provided for @adminConfigurePermissions.
  ///
  /// In en, this message translates to:
  /// **'Configure Permissions'**
  String get adminConfigurePermissions;

  /// No description provided for @adminConfigureRolePermissions.
  ///
  /// In en, this message translates to:
  /// **'Configure {name} Permissions'**
  String adminConfigureRolePermissions(Object name);

  /// No description provided for @adminSecurityWarning.
  ///
  /// In en, this message translates to:
  /// **'Security Warning'**
  String get adminSecurityWarning;

  /// No description provided for @adminSecurityWarningMessage.
  ///
  /// In en, this message translates to:
  /// **'Only grant permissions that are actually needed. Over-privileged roles may lead to unauthorized data access or system misuse.'**
  String get adminSecurityWarningMessage;

  /// No description provided for @adminConfigCenter.
  ///
  /// In en, this message translates to:
  /// **'Config Center'**
  String get adminConfigCenter;

  /// No description provided for @adminConfigCenterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage business policies and external service integrations.'**
  String get adminConfigCenterSubtitle;

  /// No description provided for @adminConfigRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh settings'**
  String get adminConfigRefresh;

  /// No description provided for @adminConfigGroupItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count} settings'**
  String adminConfigGroupItemCount(int count);

  /// No description provided for @adminConfigGroupMedia.
  ///
  /// In en, this message translates to:
  /// **'Media Import'**
  String get adminConfigGroupMedia;

  /// No description provided for @adminConfigGroupReader.
  ///
  /// In en, this message translates to:
  /// **'Reader'**
  String get adminConfigGroupReader;

  /// No description provided for @adminConfigGroupMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get adminConfigGroupMusic;

  /// No description provided for @adminConfigGroupPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos and Backup'**
  String get adminConfigGroupPhotos;

  /// No description provided for @adminConfigGroupStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage and Shared Space'**
  String get adminConfigGroupStorage;

  /// No description provided for @adminConfigGroupUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get adminConfigGroupUpload;

  /// No description provided for @adminConfigGroupSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get adminConfigGroupSecurity;

  /// No description provided for @adminConfigGroupWeather.
  ///
  /// In en, this message translates to:
  /// **'Weather'**
  String get adminConfigGroupWeather;

  /// No description provided for @adminConfigGroupOther.
  ///
  /// In en, this message translates to:
  /// **'Other Settings'**
  String get adminConfigGroupOther;

  /// No description provided for @adminConfigProviderPhotoAi.
  ///
  /// In en, this message translates to:
  /// **'Image analysis'**
  String get adminConfigProviderPhotoAi;

  /// No description provided for @adminConfigProviderMusicBrainz.
  ///
  /// In en, this message translates to:
  /// **'MusicBrainz'**
  String get adminConfigProviderMusicBrainz;

  /// No description provided for @adminConfigProviderTmdb.
  ///
  /// In en, this message translates to:
  /// **'TMDB'**
  String get adminConfigProviderTmdb;

  /// No description provided for @adminConfigProviderOpenSubtitles.
  ///
  /// In en, this message translates to:
  /// **'OpenSubtitles'**
  String get adminConfigProviderOpenSubtitles;

  /// No description provided for @adminConfigProviderGoogleBooks.
  ///
  /// In en, this message translates to:
  /// **'Google Books'**
  String get adminConfigProviderGoogleBooks;

  /// No description provided for @adminConfigProviderOpenLibrary.
  ///
  /// In en, this message translates to:
  /// **'Open Library'**
  String get adminConfigProviderOpenLibrary;

  /// No description provided for @adminConfigProviderNetease.
  ///
  /// In en, this message translates to:
  /// **'NetEase Cloud Music'**
  String get adminConfigProviderNetease;

  /// No description provided for @adminConfigProviderQqMusic.
  ///
  /// In en, this message translates to:
  /// **'QQ Music'**
  String get adminConfigProviderQqMusic;

  /// No description provided for @adminConfigProviderQWeather.
  ///
  /// In en, this message translates to:
  /// **'QWeather'**
  String get adminConfigProviderQWeather;

  /// No description provided for @adminConfigManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get adminConfigManage;

  /// No description provided for @adminConfigSecretConfigured.
  ///
  /// In en, this message translates to:
  /// **'Sensitive credential configured; its value is never shown'**
  String get adminConfigSecretConfigured;

  /// No description provided for @adminConfigNeedsSetup.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get adminConfigNeedsSetup;

  /// No description provided for @adminConfigCurrentValue.
  ///
  /// In en, this message translates to:
  /// **'Current value: {value}'**
  String adminConfigCurrentValue(Object value);

  /// No description provided for @adminConfigClearCredential.
  ///
  /// In en, this message translates to:
  /// **'Clear credential'**
  String get adminConfigClearCredential;

  /// No description provided for @adminConfigClearCredentialConfirm.
  ///
  /// In en, this message translates to:
  /// **'The related integration will stop working after this credential is cleared. Continue?'**
  String get adminConfigClearCredentialConfirm;

  /// No description provided for @adminConfigCredentialClearedReason.
  ///
  /// In en, this message translates to:
  /// **'Integration credential cleared by administrator'**
  String get adminConfigCredentialClearedReason;

  /// No description provided for @adminConfigMediaAutoImport.
  ///
  /// In en, this message translates to:
  /// **'Automatically import discovered media'**
  String get adminConfigMediaAutoImport;

  /// No description provided for @adminConfigPhotoBackup.
  ///
  /// In en, this message translates to:
  /// **'Automatic photo backup'**
  String get adminConfigPhotoBackup;

  /// No description provided for @adminConfigDefaultQuota.
  ///
  /// In en, this message translates to:
  /// **'Default quota for new users'**
  String get adminConfigDefaultQuota;

  /// No description provided for @adminConfigQuotaWarning.
  ///
  /// In en, this message translates to:
  /// **'Quota warning threshold'**
  String get adminConfigQuotaWarning;

  /// No description provided for @adminConfigSharedSpace.
  ///
  /// In en, this message translates to:
  /// **'Shared space'**
  String get adminConfigSharedSpace;

  /// No description provided for @adminConfigSharedSpaceLimit.
  ///
  /// In en, this message translates to:
  /// **'Shared space capacity limit'**
  String get adminConfigSharedSpaceLimit;

  /// No description provided for @adminConfigLocalMedia.
  ///
  /// In en, this message translates to:
  /// **'Local read-only media'**
  String get adminConfigLocalMedia;

  /// No description provided for @adminConfigWeather.
  ///
  /// In en, this message translates to:
  /// **'Weather feature'**
  String get adminConfigWeather;

  /// No description provided for @adminConfigMusicBrainzEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable MusicBrainz'**
  String get adminConfigMusicBrainzEnabled;

  /// No description provided for @adminConfigTmdbEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable TMDB'**
  String get adminConfigTmdbEnabled;

  /// No description provided for @adminConfigTmdbApiKey.
  ///
  /// In en, this message translates to:
  /// **'TMDB API Key'**
  String get adminConfigTmdbApiKey;

  /// No description provided for @adminConfigTmdbAccessToken.
  ///
  /// In en, this message translates to:
  /// **'TMDB Access Token'**
  String get adminConfigTmdbAccessToken;

  /// No description provided for @adminConfigTmdbLanguage.
  ///
  /// In en, this message translates to:
  /// **'Metadata language'**
  String get adminConfigTmdbLanguage;

  /// No description provided for @adminConfigTmdbAdult.
  ///
  /// In en, this message translates to:
  /// **'Include adult content'**
  String get adminConfigTmdbAdult;

  /// No description provided for @adminConfigOpenSubtitlesApiKey.
  ///
  /// In en, this message translates to:
  /// **'OpenSubtitles API Key'**
  String get adminConfigOpenSubtitlesApiKey;

  /// No description provided for @adminConfigPhotoAiEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable image analysis'**
  String get adminConfigPhotoAiEnabled;

  /// No description provided for @adminConfigNeteaseEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable NetEase Cloud Music'**
  String get adminConfigNeteaseEnabled;

  /// No description provided for @adminConfigQqEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable QQ Music'**
  String get adminConfigQqEnabled;

  /// No description provided for @adminConfigQWeatherProjectId.
  ///
  /// In en, this message translates to:
  /// **'Project ID'**
  String get adminConfigQWeatherProjectId;

  /// No description provided for @adminConfigQWeatherCredentialId.
  ///
  /// In en, this message translates to:
  /// **'Credential ID'**
  String get adminConfigQWeatherCredentialId;

  /// No description provided for @adminConfigQWeatherPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Ed25519 private key'**
  String get adminConfigQWeatherPrivateKey;

  /// No description provided for @adminConfigTmdbTimeout.
  ///
  /// In en, this message translates to:
  /// **'TMDB request timeout'**
  String get adminConfigTmdbTimeout;

  /// No description provided for @adminConfigTmdbStrategy.
  ///
  /// In en, this message translates to:
  /// **'TMDB search strategy'**
  String get adminConfigTmdbStrategy;

  /// No description provided for @adminConfigTmdbLimit.
  ///
  /// In en, this message translates to:
  /// **'TMDB result limit'**
  String get adminConfigTmdbLimit;

  /// No description provided for @adminConfigMediaTranscode.
  ///
  /// In en, this message translates to:
  /// **'Enable media transcoding'**
  String get adminConfigMediaTranscode;

  /// No description provided for @adminConfigReaderGoogleBooksEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable Google Books'**
  String get adminConfigReaderGoogleBooksEnabled;

  /// No description provided for @adminConfigReaderGoogleBooksUrl.
  ///
  /// In en, this message translates to:
  /// **'Google Books service URL'**
  String get adminConfigReaderGoogleBooksUrl;

  /// No description provided for @adminConfigReaderGoogleBooksLanguage.
  ///
  /// In en, this message translates to:
  /// **'Google Books language'**
  String get adminConfigReaderGoogleBooksLanguage;

  /// No description provided for @adminConfigReaderGoogleBooksLimit.
  ///
  /// In en, this message translates to:
  /// **'Google Books result limit'**
  String get adminConfigReaderGoogleBooksLimit;

  /// No description provided for @adminConfigReaderGoogleBooksTimeout.
  ///
  /// In en, this message translates to:
  /// **'Google Books request timeout'**
  String get adminConfigReaderGoogleBooksTimeout;

  /// No description provided for @adminConfigReaderGoogleBooksApiKey.
  ///
  /// In en, this message translates to:
  /// **'Google Books API Key'**
  String get adminConfigReaderGoogleBooksApiKey;

  /// No description provided for @adminConfigReaderOpenLibraryEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable Open Library'**
  String get adminConfigReaderOpenLibraryEnabled;

  /// No description provided for @adminConfigReaderOpenLibraryUrl.
  ///
  /// In en, this message translates to:
  /// **'Open Library service URL'**
  String get adminConfigReaderOpenLibraryUrl;

  /// No description provided for @adminConfigReaderOpenLibraryLanguage.
  ///
  /// In en, this message translates to:
  /// **'Open Library language'**
  String get adminConfigReaderOpenLibraryLanguage;

  /// No description provided for @adminConfigReaderAutoImport.
  ///
  /// In en, this message translates to:
  /// **'Enable reader auto-import'**
  String get adminConfigReaderAutoImport;

  /// No description provided for @adminConfigMusicBrainzBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'MusicBrainz service URL'**
  String get adminConfigMusicBrainzBaseUrl;

  /// No description provided for @adminConfigMusicAutoImport.
  ///
  /// In en, this message translates to:
  /// **'Enable music auto-import'**
  String get adminConfigMusicAutoImport;

  /// No description provided for @adminConfigMusicBrainzUserAgent.
  ///
  /// In en, this message translates to:
  /// **'MusicBrainz User-Agent'**
  String get adminConfigMusicBrainzUserAgent;

  /// No description provided for @adminConfigMusicBrainzCoverUrl.
  ///
  /// In en, this message translates to:
  /// **'MusicBrainz cover service URL'**
  String get adminConfigMusicBrainzCoverUrl;

  /// No description provided for @adminConfigMusicOnlineEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable online music'**
  String get adminConfigMusicOnlineEnabled;

  /// No description provided for @adminConfigTmdbBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'TMDB service URL'**
  String get adminConfigTmdbBaseUrl;

  /// No description provided for @adminConfigPhotoAiEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Image analysis service URL'**
  String get adminConfigPhotoAiEndpoint;

  /// No description provided for @adminConfigNeteaseBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'NetEase Music service URL'**
  String get adminConfigNeteaseBaseUrl;

  /// No description provided for @adminConfigNeteaseHosts.
  ///
  /// In en, this message translates to:
  /// **'NetEase playback hosts'**
  String get adminConfigNeteaseHosts;

  /// No description provided for @adminConfigQqUUrl.
  ///
  /// In en, this message translates to:
  /// **'QQ Music U endpoint'**
  String get adminConfigQqUUrl;

  /// No description provided for @adminConfigQqCUrl.
  ///
  /// In en, this message translates to:
  /// **'QQ Music C endpoint'**
  String get adminConfigQqCUrl;

  /// No description provided for @adminConfigQqHosts.
  ///
  /// In en, this message translates to:
  /// **'QQ Music playback hosts'**
  String get adminConfigQqHosts;

  /// No description provided for @adminConfigQWeatherBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'QWeather service URL'**
  String get adminConfigQWeatherBaseUrl;

  /// No description provided for @adminConfigWeatherLocation.
  ///
  /// In en, this message translates to:
  /// **'Weather location'**
  String get adminConfigWeatherLocation;

  /// No description provided for @adminConfigPhotoAiTimeout.
  ///
  /// In en, this message translates to:
  /// **'Image analysis request timeout'**
  String get adminConfigPhotoAiTimeout;

  /// No description provided for @adminConfigPhotoGeoRate.
  ///
  /// In en, this message translates to:
  /// **'Photo geocoding rate'**
  String get adminConfigPhotoGeoRate;

  /// No description provided for @adminConfigUploadRateEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable upload rate limiting'**
  String get adminConfigUploadRateEnabled;

  /// No description provided for @adminConfigSecurityRateLimit.
  ///
  /// In en, this message translates to:
  /// **'Default security rate limit'**
  String get adminConfigSecurityRateLimit;

  /// No description provided for @adminConfigClamavEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable ClamAV'**
  String get adminConfigClamavEnabled;

  /// No description provided for @adminConfigClamavHost.
  ///
  /// In en, this message translates to:
  /// **'ClamAV host'**
  String get adminConfigClamavHost;

  /// No description provided for @adminConfigClamavPort.
  ///
  /// In en, this message translates to:
  /// **'ClamAV port'**
  String get adminConfigClamavPort;

  /// No description provided for @adminConfigUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get adminConfigUnlimited;

  /// No description provided for @adminConfigUnlimitedDescription.
  ///
  /// In en, this message translates to:
  /// **'No capacity check is applied when unlimited is selected.'**
  String get adminConfigUnlimitedDescription;

  /// No description provided for @adminConfigQuotaUnlimitedDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter a value directly, or move the slider to the far right or enable unlimited to remove the cap.'**
  String get adminConfigQuotaUnlimitedDescription;

  /// No description provided for @adminConfigQuotaSliderUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Far right: unlimited'**
  String get adminConfigQuotaSliderUnlimited;

  /// No description provided for @adminConfigQuotaSliderMinimum.
  ///
  /// In en, this message translates to:
  /// **'1 GB'**
  String get adminConfigQuotaSliderMinimum;

  /// No description provided for @adminConfigQuotaInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a quota greater than 0 GB, or enable unlimited.'**
  String get adminConfigQuotaInvalid;

  /// No description provided for @adminConfigQuotaWholeGb.
  ///
  /// In en, this message translates to:
  /// **'The default user quota must be a whole number of GB.'**
  String get adminConfigQuotaWholeGb;

  /// No description provided for @adminConfigEndpointDescription.
  ///
  /// In en, this message translates to:
  /// **'Base address used by server requests; adjust it for your deployment.'**
  String get adminConfigEndpointDescription;

  /// No description provided for @adminConfigWeatherLocationDescription.
  ///
  /// In en, this message translates to:
  /// **'City, coordinates, or a provider-specific location identifier used for weather queries.'**
  String get adminConfigWeatherLocationDescription;

  /// No description provided for @adminConfigUnknownItem.
  ///
  /// In en, this message translates to:
  /// **'Unknown setting'**
  String get adminConfigUnknownItem;

  /// No description provided for @adminConfigMediaAutoImportDescription.
  ///
  /// In en, this message translates to:
  /// **'Allows discovered titles to enter the media import flow according to Media rules.'**
  String get adminConfigMediaAutoImportDescription;

  /// No description provided for @adminConfigPhotoBackupDescription.
  ///
  /// In en, this message translates to:
  /// **'Controls whether new photos enter the automatic backup flow.'**
  String get adminConfigPhotoBackupDescription;

  /// No description provided for @adminConfigDefaultQuotaDescription.
  ///
  /// In en, this message translates to:
  /// **'Storage assigned to newly created users, in GB.'**
  String get adminConfigDefaultQuotaDescription;

  /// No description provided for @adminConfigQuotaWarningDescription.
  ///
  /// In en, this message translates to:
  /// **'Shows a capacity warning when usage reaches this percentage.'**
  String get adminConfigQuotaWarningDescription;

  /// No description provided for @adminConfigSharedSpaceDescription.
  ///
  /// In en, this message translates to:
  /// **'Controls whether users can access the shared space.'**
  String get adminConfigSharedSpaceDescription;

  /// No description provided for @adminConfigSharedSpaceLimitDescription.
  ///
  /// In en, this message translates to:
  /// **'Limits the total capacity available to the shared space.'**
  String get adminConfigSharedSpaceLimitDescription;

  /// No description provided for @adminConfigLocalMediaDescription.
  ///
  /// In en, this message translates to:
  /// **'Can only disable local media authorized at deployment; it cannot expand mount access.'**
  String get adminConfigLocalMediaDescription;

  /// No description provided for @adminConfigWeatherDescription.
  ///
  /// In en, this message translates to:
  /// **'Controls whether clients can request weather data.'**
  String get adminConfigWeatherDescription;

  /// No description provided for @adminConfigProviderToggleDescription.
  ///
  /// In en, this message translates to:
  /// **'Controls whether this integration may be used.'**
  String get adminConfigProviderToggleDescription;

  /// No description provided for @adminConfigCredentialDescription.
  ///
  /// In en, this message translates to:
  /// **'Used for server-side authentication and never shown again after saving.'**
  String get adminConfigCredentialDescription;

  /// No description provided for @adminConfigProviderIdentifierDescription.
  ///
  /// In en, this message translates to:
  /// **'Project or credential identifier supplied by the external service console.'**
  String get adminConfigProviderIdentifierDescription;

  /// No description provided for @adminConfigTmdbLanguageDescription.
  ///
  /// In en, this message translates to:
  /// **'Preferred language for titles, descriptions, and image metadata returned by TMDB.'**
  String get adminConfigTmdbLanguageDescription;

  /// No description provided for @adminConfigTmdbAdultDescription.
  ///
  /// In en, this message translates to:
  /// **'Search results may include adult content when enabled.'**
  String get adminConfigTmdbAdultDescription;

  /// No description provided for @adminConfigInternalNumericDescription.
  ///
  /// In en, this message translates to:
  /// **'Internal request or result bound used by this provider.'**
  String get adminConfigInternalNumericDescription;

  /// No description provided for @adminConfigTmdbStrategyDescription.
  ///
  /// In en, this message translates to:
  /// **'Controls the normalized and fallback queries used for TMDB matching.'**
  String get adminConfigTmdbStrategyDescription;

  /// No description provided for @adminConfigMediaTranscodeDescription.
  ///
  /// In en, this message translates to:
  /// **'Allows the media pipeline to generate playback derivatives.'**
  String get adminConfigMediaTranscodeDescription;

  /// No description provided for @adminConfigReaderAutoImportDescription.
  ///
  /// In en, this message translates to:
  /// **'Allows recognized reader files to enter the import flow automatically.'**
  String get adminConfigReaderAutoImportDescription;

  /// No description provided for @adminConfigMusicAutoImportDescription.
  ///
  /// In en, this message translates to:
  /// **'Allows recognized music files to enter the import flow automatically.'**
  String get adminConfigMusicAutoImportDescription;

  /// No description provided for @adminConfigPhotoGeoRateDescription.
  ///
  /// In en, this message translates to:
  /// **'Maximum geocoding requests permitted per second.'**
  String get adminConfigPhotoGeoRateDescription;

  /// No description provided for @adminConfigUploadRateDescription.
  ///
  /// In en, this message translates to:
  /// **'Controls whether upload traffic is subject to the server rate policy.'**
  String get adminConfigUploadRateDescription;

  /// No description provided for @adminConfigSecurityRateLimitDescription.
  ///
  /// In en, this message translates to:
  /// **'Default request limit applied by security controls.'**
  String get adminConfigSecurityRateLimitDescription;

  /// No description provided for @adminConfigMusicBrainzUserAgentDescription.
  ///
  /// In en, this message translates to:
  /// **'Identification string sent with MusicBrainz requests.'**
  String get adminConfigMusicBrainzUserAgentDescription;

  /// No description provided for @adminConfigHostSuffixesDescription.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated host suffixes accepted for provider media requests.'**
  String get adminConfigHostSuffixesDescription;

  /// No description provided for @adminConfigItems.
  ///
  /// In en, this message translates to:
  /// **'Config Items'**
  String get adminConfigItems;

  /// No description provided for @adminAllConfigs.
  ///
  /// In en, this message translates to:
  /// **'All configs'**
  String get adminAllConfigs;

  /// No description provided for @adminHotUpdate.
  ///
  /// In en, this message translates to:
  /// **'Hot Update'**
  String get adminHotUpdate;

  /// No description provided for @adminEffectiveImmediately.
  ///
  /// In en, this message translates to:
  /// **'Effective immediately'**
  String get adminEffectiveImmediately;

  /// No description provided for @adminRestartRequired.
  ///
  /// In en, this message translates to:
  /// **'Restart Required'**
  String get adminRestartRequired;

  /// No description provided for @adminEffectiveAfterRestart.
  ///
  /// In en, this message translates to:
  /// **'Effective after restart'**
  String get adminEffectiveAfterRestart;

  /// No description provided for @adminConfigItemList.
  ///
  /// In en, this message translates to:
  /// **'Config Items'**
  String get adminConfigItemList;

  /// No description provided for @adminConfigItemListSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Settings take effect by hot update, on the next task, or after restart.'**
  String get adminConfigItemListSubtitle;

  /// No description provided for @adminNoConfigItems.
  ///
  /// In en, this message translates to:
  /// **'No config items.'**
  String get adminNoConfigItems;

  /// No description provided for @adminAllCategories.
  ///
  /// In en, this message translates to:
  /// **'All Categories'**
  String get adminAllCategories;

  /// No description provided for @adminAllScopes.
  ///
  /// In en, this message translates to:
  /// **'All Scopes'**
  String get adminAllScopes;

  /// No description provided for @adminHotReload.
  ///
  /// In en, this message translates to:
  /// **'Hot Reload'**
  String get adminHotReload;

  /// No description provided for @adminNextTask.
  ///
  /// In en, this message translates to:
  /// **'Next Task'**
  String get adminNextTask;

  /// No description provided for @adminNeedsRestart.
  ///
  /// In en, this message translates to:
  /// **'Needs Restart'**
  String get adminNeedsRestart;

  /// No description provided for @adminEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get adminEdit;

  /// No description provided for @adminConfigValue.
  ///
  /// In en, this message translates to:
  /// **'Config Value'**
  String get adminConfigValue;

  /// No description provided for @adminSensitiveValuePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter a new sensitive value; the current value is never displayed'**
  String get adminSensitiveValuePlaceholder;

  /// No description provided for @adminChangeReason.
  ///
  /// In en, this message translates to:
  /// **'Change Reason'**
  String get adminChangeReason;

  /// No description provided for @adminTrue.
  ///
  /// In en, this message translates to:
  /// **'True'**
  String get adminTrue;

  /// No description provided for @adminFalse.
  ///
  /// In en, this message translates to:
  /// **'False'**
  String get adminFalse;

  /// No description provided for @adminConfigHistory.
  ///
  /// In en, this message translates to:
  /// **'Change History'**
  String get adminConfigHistory;

  /// No description provided for @adminNoConfigHistory.
  ///
  /// In en, this message translates to:
  /// **'No change history'**
  String get adminNoConfigHistory;

  /// No description provided for @adminRollback.
  ///
  /// In en, this message translates to:
  /// **'Rollback'**
  String get adminRollback;

  /// No description provided for @adminNoReason.
  ///
  /// In en, this message translates to:
  /// **'No reason'**
  String get adminNoReason;

  /// No description provided for @adminDlq.
  ///
  /// In en, this message translates to:
  /// **'Dead Letter Queue'**
  String get adminDlq;

  /// No description provided for @adminDlqSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Failed tasks exhausted retries — re-queue manually'**
  String get adminDlqSubtitle;

  /// No description provided for @adminNoDlqTasks.
  ///
  /// In en, this message translates to:
  /// **'No DLQ tasks'**
  String get adminNoDlqTasks;

  /// No description provided for @adminNoErrorSummary.
  ///
  /// In en, this message translates to:
  /// **'No error summary'**
  String get adminNoErrorSummary;

  /// No description provided for @adminStorageManagement.
  ///
  /// In en, this message translates to:
  /// **'Storage Management'**
  String get adminStorageManagement;

  /// No description provided for @adminListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No data. Try adjusting the filters.'**
  String get adminListEmpty;

  /// No description provided for @adminListRowsPerPage.
  ///
  /// In en, this message translates to:
  /// **'Rows per page'**
  String get adminListRowsPerPage;

  /// No description provided for @adminListPageOf.
  ///
  /// In en, this message translates to:
  /// **'Page {current} of {total}'**
  String adminListPageOf(Object current, Object total);

  /// No description provided for @adminListPrevPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get adminListPrevPage;

  /// No description provided for @adminListNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get adminListNextPage;

  /// No description provided for @adminListActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get adminListActions;

  /// No description provided for @adminListIndex.
  ///
  /// In en, this message translates to:
  /// **'#'**
  String get adminListIndex;

  /// No description provided for @adminListSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String adminListSelectedCount(Object count);

  /// No description provided for @adminListSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get adminListSelectAll;

  /// No description provided for @adminListExpandFilters.
  ///
  /// In en, this message translates to:
  /// **'Expand filters'**
  String get adminListExpandFilters;

  /// No description provided for @adminListCollapseFilters.
  ///
  /// In en, this message translates to:
  /// **'Collapse filters'**
  String get adminListCollapseFilters;

  /// No description provided for @adminListSortAsc.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get adminListSortAsc;

  /// No description provided for @adminListSortDesc.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get adminListSortDesc;

  /// No description provided for @adminListExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get adminListExportCsv;

  /// No description provided for @adminLibrarySourcesSection.
  ///
  /// In en, this message translates to:
  /// **'Video library sources'**
  String get adminLibrarySourcesSection;

  /// No description provided for @statusHealthHealthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get statusHealthHealthy;

  /// No description provided for @statusHealthAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get statusHealthAvailable;

  /// No description provided for @statusHealthUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get statusHealthUnavailable;

  /// No description provided for @statusScopePersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal space'**
  String get statusScopePersonal;

  /// No description provided for @statusScopeShared.
  ///
  /// In en, this message translates to:
  /// **'Shared space'**
  String get statusScopeShared;

  /// No description provided for @statusProviderLocalFilesystem.
  ///
  /// In en, this message translates to:
  /// **'Local filesystem'**
  String get statusProviderLocalFilesystem;

  /// No description provided for @statusProviderMinio.
  ///
  /// In en, this message translates to:
  /// **'Object storage'**
  String get statusProviderMinio;

  /// No description provided for @statusManagementManaged.
  ///
  /// In en, this message translates to:
  /// **'Managed'**
  String get statusManagementManaged;

  /// No description provided for @statusScanReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get statusScanReady;

  /// No description provided for @statusScanDiscovering.
  ///
  /// In en, this message translates to:
  /// **'Discovering'**
  String get statusScanDiscovering;

  /// No description provided for @statusScanApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying'**
  String get statusScanApplying;

  /// No description provided for @statusScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusScanFailed;

  /// No description provided for @statusScanCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusScanCancelled;

  /// No description provided for @statusScanPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get statusScanPaused;

  /// No description provided for @statusScanPartial.
  ///
  /// In en, this message translates to:
  /// **'Partially applied'**
  String get statusScanPartial;

  /// No description provided for @statusScanQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get statusScanQueued;

  /// No description provided for @statusPhaseDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Discovery phase'**
  String get statusPhaseDiscovery;

  /// No description provided for @statusPhaseReview.
  ///
  /// In en, this message translates to:
  /// **'Review phase'**
  String get statusPhaseReview;

  /// No description provided for @statusPhaseApply.
  ///
  /// In en, this message translates to:
  /// **'Apply phase'**
  String get statusPhaseApply;

  /// No description provided for @adminLibrarySourceAdd.
  ///
  /// In en, this message translates to:
  /// **'Add library source'**
  String get adminLibrarySourceAdd;

  /// No description provided for @adminLibrarySourcesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No library sources yet. Create one on an enabled storage location.'**
  String get adminLibrarySourcesEmpty;

  /// No description provided for @adminLibrarySourcesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create movie, series and anime sources on enabled storage locations.'**
  String get adminLibrarySourcesSubtitle;

  /// No description provided for @adminLibraryReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a source to review the scan results and apply them.'**
  String get adminLibraryReviewSubtitle;

  /// No description provided for @adminStorageStatusHealthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get adminStorageStatusHealthy;

  /// No description provided for @adminStorageFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get adminStorageFilterAll;

  /// No description provided for @adminStorageFilterEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get adminStorageFilterEnabled;

  /// No description provided for @adminStorageFilterDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get adminStorageFilterDisabled;

  /// No description provided for @adminStorageFilterUnhealthy.
  ///
  /// In en, this message translates to:
  /// **'Unhealthy'**
  String get adminStorageFilterUnhealthy;

  /// No description provided for @adminStorageEmptyList.
  ///
  /// In en, this message translates to:
  /// **'No storage locations match the filter'**
  String get adminStorageEmptyList;

  /// No description provided for @adminStorageDetailHint.
  ///
  /// In en, this message translates to:
  /// **'Select a storage location to view details'**
  String get adminStorageDetailHint;

  /// No description provided for @adminStorageStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get adminStorageStatusDisabled;

  /// No description provided for @adminStorageDisableConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Disable storage location'**
  String get adminStorageDisableConfirmTitle;

  /// No description provided for @adminStorageDisableConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Scanning and media access stop for \"{name}\" until you enable it again.'**
  String adminStorageDisableConfirmBody(Object name);

  /// No description provided for @adminStorageDisableAction.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get adminStorageDisableAction;

  /// No description provided for @adminStorageEnableAction.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get adminStorageEnableAction;

  /// No description provided for @adminStorageDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete storage location'**
  String get adminStorageDeleteConfirmTitle;

  /// No description provided for @adminStorageDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes the \"{name}\" registration. Imported content is not affected.'**
  String adminStorageDeleteConfirmBody(Object name);

  /// No description provided for @adminStorageDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get adminStorageDeleteAction;

  /// No description provided for @adminStorageFieldPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get adminStorageFieldPath;

  /// No description provided for @adminStorageFieldScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get adminStorageFieldScope;

  /// No description provided for @adminStorageFieldProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get adminStorageFieldProvider;

  /// No description provided for @adminStorageFieldManagement.
  ///
  /// In en, this message translates to:
  /// **'Management'**
  String get adminStorageFieldManagement;

  /// No description provided for @adminStorageFieldNode.
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get adminStorageFieldNode;

  /// No description provided for @adminStorageParentDir.
  ///
  /// In en, this message translates to:
  /// **'Up one level'**
  String get adminStorageParentDir;

  /// No description provided for @adminStorageManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage MinIO buckets, capacity, and index maintenance.'**
  String get adminStorageManagementSubtitle;

  /// No description provided for @adminBucketConfig.
  ///
  /// In en, this message translates to:
  /// **'Bucket Config'**
  String get adminBucketConfig;

  /// No description provided for @adminMinioBuckets.
  ///
  /// In en, this message translates to:
  /// **'MinIO Buckets'**
  String get adminMinioBuckets;

  /// No description provided for @adminRecentRecords.
  ///
  /// In en, this message translates to:
  /// **'Recent records'**
  String get adminRecentRecords;

  /// No description provided for @adminWaitingToExecute.
  ///
  /// In en, this message translates to:
  /// **'Waiting to execute'**
  String get adminWaitingToExecute;

  /// No description provided for @adminObjectBuckets.
  ///
  /// In en, this message translates to:
  /// **'Object Buckets'**
  String get adminObjectBuckets;

  /// No description provided for @adminObjectBucketsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'From backend MinIO config.'**
  String get adminObjectBucketsSubtitle;

  /// No description provided for @adminNoBucketConfig.
  ///
  /// In en, this message translates to:
  /// **'No bucket config.'**
  String get adminNoBucketConfig;

  /// No description provided for @adminExternalStorageIntegration.
  ///
  /// In en, this message translates to:
  /// **'External Storage Integration'**
  String get adminExternalStorageIntegration;

  /// No description provided for @adminExternalStorageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect WebDAV, S3, SMB and mount cloud drives.'**
  String get adminExternalStorageSubtitle;

  /// No description provided for @adminNewConnection.
  ///
  /// In en, this message translates to:
  /// **'New Connection'**
  String get adminNewConnection;

  /// No description provided for @adminNewExternalStorage.
  ///
  /// In en, this message translates to:
  /// **'New External Storage'**
  String get adminNewExternalStorage;

  /// No description provided for @adminType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get adminType;

  /// No description provided for @adminLocalMount.
  ///
  /// In en, this message translates to:
  /// **'Local Mount'**
  String get adminLocalMount;

  /// No description provided for @adminDisplayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get adminDisplayNameLabel;

  /// No description provided for @adminCredentialsJson.
  ///
  /// In en, this message translates to:
  /// **'Credentials JSON'**
  String get adminCredentialsJson;

  /// No description provided for @adminEnterDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Please enter display name'**
  String get adminEnterDisplayName;

  /// No description provided for @adminCreatingLabel.
  ///
  /// In en, this message translates to:
  /// **'Creating'**
  String get adminCreatingLabel;

  /// No description provided for @adminConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get adminConnections;

  /// No description provided for @adminExternalSources.
  ///
  /// In en, this message translates to:
  /// **'External sources'**
  String get adminExternalSources;

  /// No description provided for @adminEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get adminEnabled;

  /// No description provided for @adminSyncable.
  ///
  /// In en, this message translates to:
  /// **'Syncable'**
  String get adminSyncable;

  /// No description provided for @adminDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get adminDisabled;

  /// No description provided for @adminPausedSync.
  ///
  /// In en, this message translates to:
  /// **'Paused sync'**
  String get adminPausedSync;

  /// No description provided for @adminConnectionList.
  ///
  /// In en, this message translates to:
  /// **'Connection List'**
  String get adminConnectionList;

  /// No description provided for @adminConnectionListSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Credentials managed by backend, frontend only shows connection metadata.'**
  String get adminConnectionListSubtitle;

  /// No description provided for @adminNoExternalStorage.
  ///
  /// In en, this message translates to:
  /// **'No external storage connections.'**
  String get adminNoExternalStorage;

  /// No description provided for @adminDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get adminDeactivate;

  /// No description provided for @adminActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get adminActivate;

  /// No description provided for @adminSessionManagement.
  ///
  /// In en, this message translates to:
  /// **'Session Management'**
  String get adminSessionManagement;

  /// No description provided for @adminSessionStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get adminSessionStatusActive;

  /// No description provided for @adminSessionStatusRevoked.
  ///
  /// In en, this message translates to:
  /// **'Force-signed out'**
  String get adminSessionStatusRevoked;

  /// No description provided for @adminSessionStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get adminSessionStatusExpired;

  /// No description provided for @adminSessionDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Session details'**
  String get adminSessionDetailTitle;

  /// No description provided for @adminSessionFieldDeviceId.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get adminSessionFieldDeviceId;

  /// No description provided for @adminSessionDeviceName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get adminSessionDeviceName;

  /// No description provided for @adminSessionLoginTime.
  ///
  /// In en, this message translates to:
  /// **'Signed in at'**
  String get adminSessionLoginTime;

  /// No description provided for @adminSessionExpiresAt.
  ///
  /// In en, this message translates to:
  /// **'Expires at'**
  String get adminSessionExpiresAt;

  /// No description provided for @adminSessionLastActive.
  ///
  /// In en, this message translates to:
  /// **'Last active at'**
  String get adminSessionLastActive;

  /// No description provided for @adminSessionIp.
  ///
  /// In en, this message translates to:
  /// **'IP address'**
  String get adminSessionIp;

  /// No description provided for @adminResourceType.
  ///
  /// In en, this message translates to:
  /// **'Resource type'**
  String get adminResourceType;

  /// No description provided for @adminLogContent.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get adminLogContent;

  /// No description provided for @adminLogTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get adminLogTime;

  /// No description provided for @adminConfigDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get adminConfigDescription;

  /// No description provided for @adminStorageOpenDetail.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get adminStorageOpenDetail;

  /// No description provided for @adminStorageColumnType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get adminStorageColumnType;

  /// No description provided for @adminStorageMountsSection.
  ///
  /// In en, this message translates to:
  /// **'Local mount locations'**
  String get adminStorageMountsSection;

  /// No description provided for @adminLibraryColumnName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get adminLibraryColumnName;

  /// No description provided for @adminLibraryColumnLocation.
  ///
  /// In en, this message translates to:
  /// **'Location · Root'**
  String get adminLibraryColumnLocation;

  /// No description provided for @adminLibraryColumnScanStatus.
  ///
  /// In en, this message translates to:
  /// **'Scan status'**
  String get adminLibraryColumnScanStatus;

  /// No description provided for @adminLibraryColumnLastScan.
  ///
  /// In en, this message translates to:
  /// **'Last scan'**
  String get adminLibraryColumnLastScan;

  /// No description provided for @adminLibraryManageInfoSection.
  ///
  /// In en, this message translates to:
  /// **'Library info'**
  String get adminLibraryManageInfoSection;

  /// No description provided for @adminLibraryManageReviewSection.
  ///
  /// In en, this message translates to:
  /// **'Discovery & review'**
  String get adminLibraryManageReviewSection;

  /// No description provided for @adminLibraryLastScanSummary.
  ///
  /// In en, this message translates to:
  /// **'Found {found} · Created {created} · Missing {missing}'**
  String adminLibraryLastScanSummary(
    Object found,
    Object created,
    Object missing,
  );

  /// No description provided for @adminLibraryScanNever.
  ///
  /// In en, this message translates to:
  /// **'Never scanned'**
  String get adminLibraryScanNever;

  /// No description provided for @adminLibraryDeleteSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete library source'**
  String get adminLibraryDeleteSourceTitle;

  /// No description provided for @adminLibraryDeleteSourceBody.
  ///
  /// In en, this message translates to:
  /// **'Delete library source \"{name}\"? This cannot be undone.'**
  String adminLibraryDeleteSourceBody(Object name);

  /// No description provided for @adminLibraryAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Access management'**
  String get adminLibraryAccessTitle;

  /// No description provided for @adminStorageColumnName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get adminStorageColumnName;

  /// No description provided for @adminStorageColumnMountKey.
  ///
  /// In en, this message translates to:
  /// **'Mount key'**
  String get adminStorageColumnMountKey;

  /// No description provided for @adminStorageColumnRoot.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get adminStorageColumnRoot;

  /// No description provided for @adminStorageColumnHealth.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get adminStorageColumnHealth;

  /// No description provided for @adminLibraryDiscoverUpdates.
  ///
  /// In en, this message translates to:
  /// **'Discover updates'**
  String get adminLibraryDiscoverUpdates;

  /// No description provided for @adminListTotalCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String adminListTotalCount(Object count);

  /// No description provided for @adminListRange.
  ///
  /// In en, this message translates to:
  /// **'Items {start}-{end}'**
  String adminListRange(Object start, Object end);

  /// No description provided for @adminListFirstPage.
  ///
  /// In en, this message translates to:
  /// **'First page'**
  String get adminListFirstPage;

  /// No description provided for @adminListLastPage.
  ///
  /// In en, this message translates to:
  /// **'Last page'**
  String get adminListLastPage;

  /// No description provided for @adminListJumpTo.
  ///
  /// In en, this message translates to:
  /// **'Go to'**
  String get adminListJumpTo;

  /// No description provided for @adminListPageUnit.
  ///
  /// In en, this message translates to:
  /// **''**
  String get adminListPageUnit;

  /// No description provided for @adminConfigGroupColumn.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get adminConfigGroupColumn;

  /// No description provided for @adminBatchRevokeSessions.
  ///
  /// In en, this message translates to:
  /// **'Force sign out selected'**
  String get adminBatchRevokeSessions;

  /// No description provided for @adminBatchRetryTasks.
  ///
  /// In en, this message translates to:
  /// **'Retry selected'**
  String get adminBatchRetryTasks;

  /// No description provided for @adminBatchClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get adminBatchClearSelection;

  /// No description provided for @adminBatchCompleted.
  ///
  /// In en, this message translates to:
  /// **'Batch finished: {success} succeeded, {failed} failed'**
  String adminBatchCompleted(Object success, Object failed);

  /// No description provided for @adminBatchConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm batch operation'**
  String get adminBatchConfirmTitle;

  /// No description provided for @adminBatchConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This applies to {count} selected items one by one; failed items are skipped.'**
  String adminBatchConfirmMessage(Object count);

  /// No description provided for @adminCsvExported.
  ///
  /// In en, this message translates to:
  /// **'Current page exported'**
  String get adminCsvExported;

  /// No description provided for @adminLoginFailureReason.
  ///
  /// In en, this message translates to:
  /// **'Failure reason'**
  String get adminLoginFailureReason;

  /// No description provided for @adminSessionRevokeReason.
  ///
  /// In en, this message translates to:
  /// **'Revoke reason'**
  String get adminSessionRevokeReason;

  /// No description provided for @adminSessionManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View all user active sessions, supports forced logout.'**
  String get adminSessionManagementSubtitle;

  /// No description provided for @adminActiveSessions.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get adminActiveSessions;

  /// No description provided for @adminRevokedSessions.
  ///
  /// In en, this message translates to:
  /// **'revoked'**
  String get adminRevokedSessions;

  /// No description provided for @adminActiveSessionCount.
  ///
  /// In en, this message translates to:
  /// **'Active Sessions'**
  String get adminActiveSessionCount;

  /// No description provided for @adminCurrentOnlineDevices.
  ///
  /// In en, this message translates to:
  /// **'Currently online devices'**
  String get adminCurrentOnlineDevices;

  /// No description provided for @adminRevokedCount.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get adminRevokedCount;

  /// No description provided for @adminBeenKicked.
  ///
  /// In en, this message translates to:
  /// **'Been kicked out'**
  String get adminBeenKicked;

  /// No description provided for @adminSessionList.
  ///
  /// In en, this message translates to:
  /// **'Session List'**
  String get adminSessionList;

  /// No description provided for @adminSessionListSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sorted by creation time descending.'**
  String get adminSessionListSubtitle;

  /// No description provided for @adminNoSessions.
  ///
  /// In en, this message translates to:
  /// **'No session records.'**
  String get adminNoSessions;

  /// No description provided for @adminConfirmKick.
  ///
  /// In en, this message translates to:
  /// **'Confirm Kick'**
  String get adminConfirmKick;

  /// No description provided for @adminConfirmKickMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure to revoke this session? Device: {device}'**
  String adminConfirmKickMessage(Object device);

  /// No description provided for @adminRevokeSession.
  ///
  /// In en, this message translates to:
  /// **'Kick Session'**
  String get adminRevokeSession;

  /// No description provided for @adminRevokedLabel.
  ///
  /// In en, this message translates to:
  /// **'revoked'**
  String get adminRevokedLabel;

  /// No description provided for @adminSessionAllStatuses.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get adminSessionAllStatuses;

  /// No description provided for @adminSessionActiveOnly.
  ///
  /// In en, this message translates to:
  /// **'Active only'**
  String get adminSessionActiveOnly;

  /// No description provided for @adminSessionRevokedOnly.
  ///
  /// In en, this message translates to:
  /// **'Revoked only'**
  String get adminSessionRevokedOnly;

  /// No description provided for @adminSessionExpiredOnly.
  ///
  /// In en, this message translates to:
  /// **'Expired only'**
  String get adminSessionExpiredOnly;

  /// No description provided for @adminExpiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get adminExpiredLabel;

  /// No description provided for @adminCurrentPage.
  ///
  /// In en, this message translates to:
  /// **'Current page'**
  String get adminCurrentPage;

  /// No description provided for @adminFilterTaskType.
  ///
  /// In en, this message translates to:
  /// **'Task type'**
  String get adminFilterTaskType;

  /// No description provided for @adminPageIndicator.
  ///
  /// In en, this message translates to:
  /// **'Page {page} / {totalPages}'**
  String adminPageIndicator(Object page, Object totalPages);

  /// No description provided for @adminTotalCount.
  ///
  /// In en, this message translates to:
  /// **'Total {count}'**
  String adminTotalCount(Object count);

  /// No description provided for @adminPreviousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get adminPreviousPage;

  /// No description provided for @adminNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get adminNextPage;

  /// No description provided for @adminUserManagement.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get adminUserManagement;

  /// No description provided for @adminUserManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage accounts, status, quota and role assignment.'**
  String get adminUserManagementSubtitle;

  /// No description provided for @adminAccountList.
  ///
  /// In en, this message translates to:
  /// **'Account List'**
  String get adminAccountList;

  /// No description provided for @adminAccountListSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Filter accounts by username, nickname, email and role.'**
  String get adminAccountListSubtitle;

  /// No description provided for @adminCreateUser.
  ///
  /// In en, this message translates to:
  /// **'Create User'**
  String get adminCreateUser;

  /// No description provided for @adminSearchUsers.
  ///
  /// In en, this message translates to:
  /// **'Search username, nickname or email'**
  String get adminSearchUsers;

  /// No description provided for @adminAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get adminAll;

  /// No description provided for @adminNoMatchingUsers.
  ///
  /// In en, this message translates to:
  /// **'No matching users.'**
  String get adminNoMatchingUsers;

  /// No description provided for @adminLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more (loaded {loaded} / {total})'**
  String adminLoadMore(Object loaded, Object total);

  /// No description provided for @adminTotalUsers.
  ///
  /// In en, this message translates to:
  /// **'Total Users'**
  String get adminTotalUsers;

  /// No description provided for @adminDatabaseAccounts.
  ///
  /// In en, this message translates to:
  /// **'Database accounts'**
  String get adminDatabaseAccounts;

  /// No description provided for @adminSuperAdmin.
  ///
  /// In en, this message translates to:
  /// **'Super Admin'**
  String get adminSuperAdmin;

  /// No description provided for @adminHighestPrivilege.
  ///
  /// In en, this message translates to:
  /// **'Highest privilege'**
  String get adminHighestPrivilege;

  /// No description provided for @adminSystemMaintenance.
  ///
  /// In en, this message translates to:
  /// **'System maintenance'**
  String get adminSystemMaintenance;

  /// No description provided for @adminMemberGuest.
  ///
  /// In en, this message translates to:
  /// **'Member / Guest'**
  String get adminMemberGuest;

  /// No description provided for @adminBusinessAccess.
  ///
  /// In en, this message translates to:
  /// **'Business access'**
  String get adminBusinessAccess;

  /// No description provided for @adminNotSetEmail.
  ///
  /// In en, this message translates to:
  /// **'Email not set'**
  String get adminNotSetEmail;

  /// No description provided for @adminDisable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get adminDisable;

  /// No description provided for @adminRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get adminRole;

  /// No description provided for @adminQuota.
  ///
  /// In en, this message translates to:
  /// **'Quota'**
  String get adminQuota;

  /// No description provided for @adminUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get adminUnlimited;

  /// No description provided for @adminBatchQuota.
  ///
  /// In en, this message translates to:
  /// **'Batch Set Quota'**
  String get adminBatchQuota;

  /// No description provided for @adminDeselect.
  ///
  /// In en, this message translates to:
  /// **'Deselect'**
  String get adminDeselect;

  /// No description provided for @adminSelectedUsers.
  ///
  /// In en, this message translates to:
  /// **'{count} users selected'**
  String adminSelectedUsers(Object count);

  /// No description provided for @adminBatchSetStorageQuota.
  ///
  /// In en, this message translates to:
  /// **'Batch Set Storage Quota ({count} users)'**
  String adminBatchSetStorageQuota(Object count);

  /// No description provided for @adminBatchQuotaHint.
  ///
  /// In en, this message translates to:
  /// **'Will set the same storage quota for all selected users. Super admins and users with insufficient space will be skipped.'**
  String get adminBatchQuotaHint;

  /// No description provided for @adminQuotaGib.
  ///
  /// In en, this message translates to:
  /// **'Quota (GiB)'**
  String get adminQuotaGib;

  /// No description provided for @adminQuotaHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 50'**
  String get adminQuotaHint;

  /// No description provided for @adminSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get adminSaving;

  /// No description provided for @adminSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get adminSave;

  /// No description provided for @adminValidQuotaRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid quota value'**
  String get adminValidQuotaRequired;

  /// No description provided for @adminNoUsersSelected.
  ///
  /// In en, this message translates to:
  /// **'No users selected'**
  String get adminNoUsersSelected;

  /// No description provided for @adminUsersQuotaUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated storage quota for {count} users'**
  String adminUsersQuotaUpdated(Object count);

  /// No description provided for @adminEditQuota.
  ///
  /// In en, this message translates to:
  /// **'Adjust Storage Quota for {name}'**
  String adminEditQuota(Object name);

  /// No description provided for @adminCurrentUsage.
  ///
  /// In en, this message translates to:
  /// **'Current usage: {used} / {quota}'**
  String adminCurrentUsage(Object used, Object quota);

  /// No description provided for @adminNewQuotaGib.
  ///
  /// In en, this message translates to:
  /// **'New Quota (GiB)'**
  String get adminNewQuotaGib;

  /// No description provided for @adminQuotaMinError.
  ///
  /// In en, this message translates to:
  /// **'New quota cannot be less than current used space ({used} GiB)'**
  String adminQuotaMinError(Object used);

  /// No description provided for @adminEditRoles.
  ///
  /// In en, this message translates to:
  /// **'Adjust Roles for {name}'**
  String adminEditRoles(Object name);

  /// No description provided for @adminSelectAtLeastOneRole.
  ///
  /// In en, this message translates to:
  /// **'Please select at least one role'**
  String get adminSelectAtLeastOneRole;

  /// No description provided for @adminCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating'**
  String get adminCreating;

  /// No description provided for @adminCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get adminCreate;

  /// No description provided for @adminUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get adminUsername;

  /// No description provided for @adminEnterUsername.
  ///
  /// In en, this message translates to:
  /// **'Please enter username'**
  String get adminEnterUsername;

  /// No description provided for @adminDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get adminDisplayName;

  /// No description provided for @adminEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get adminEmail;

  /// No description provided for @adminInitialPassword.
  ///
  /// In en, this message translates to:
  /// **'Initial Password'**
  String get adminInitialPassword;

  /// No description provided for @adminEnterInitialPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter initial password'**
  String get adminEnterInitialPassword;

  /// No description provided for @adminPasswordMinChars.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get adminPasswordMinChars;

  /// No description provided for @adminRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get adminRoleLabel;

  /// No description provided for @adminConsole.
  ///
  /// In en, this message translates to:
  /// **'Admin Console'**
  String get adminConsole;

  /// No description provided for @adminConsoleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Key metrics of users, permissions, runtime status and storage capacity.'**
  String get adminConsoleSubtitle;

  /// No description provided for @adminAccountOverview.
  ///
  /// In en, this message translates to:
  /// **'Account Overview'**
  String get adminAccountOverview;

  /// No description provided for @adminActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get adminActive;

  /// No description provided for @adminPermissionModel.
  ///
  /// In en, this message translates to:
  /// **'Permission Model'**
  String get adminPermissionModel;

  /// No description provided for @adminPermissionBindingsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} permission bindings'**
  String adminPermissionBindingsCount(Object count);

  /// No description provided for @adminTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get adminTasks;

  /// No description provided for @adminRunningLabel.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get adminRunningLabel;

  /// No description provided for @adminQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get adminQueued;

  /// No description provided for @adminCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get adminCompleted;

  /// No description provided for @adminNeedAttention.
  ///
  /// In en, this message translates to:
  /// **'Need attention'**
  String get adminNeedAttention;

  /// No description provided for @adminStorageAssets.
  ///
  /// In en, this message translates to:
  /// **'Storage Assets'**
  String get adminStorageAssets;

  /// No description provided for @adminFilesFolders.
  ///
  /// In en, this message translates to:
  /// **'{files} files · {folders} folders'**
  String adminFilesFolders(Object files, Object folders);

  /// No description provided for @adminObjects.
  ///
  /// In en, this message translates to:
  /// **'Objects'**
  String get adminObjects;

  /// No description provided for @adminHealthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get adminHealthy;

  /// No description provided for @adminFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get adminFiles;

  /// No description provided for @adminFolders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get adminFolders;

  /// No description provided for @adminExternalStorageLabel.
  ///
  /// In en, this message translates to:
  /// **'External Storage'**
  String get adminExternalStorageLabel;

  /// No description provided for @adminWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get adminWarning;

  /// No description provided for @adminActivityChart.
  ///
  /// In en, this message translates to:
  /// **'Activity Chart'**
  String get adminActivityChart;

  /// No description provided for @adminActivityChartSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Admin-side trend view generated from current system statistics.'**
  String get adminActivityChartSubtitle;

  /// No description provided for @adminHealthStatus.
  ///
  /// In en, this message translates to:
  /// **'Health Status'**
  String get adminHealthStatus;

  /// No description provided for @adminHealthStatusSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Health status from admin aggregation endpoint.'**
  String get adminHealthStatusSubtitle;

  /// No description provided for @adminUserLabel.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get adminUserLabel;

  /// No description provided for @adminTaskLabel.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get adminTaskLabel;

  /// No description provided for @adminStorageLabel.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get adminStorageLabel;

  /// No description provided for @adminAnalyticsPage.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get adminAnalyticsPage;

  /// No description provided for @adminAnalyticsPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Centralized view of account growth, capacity trends, task throughput and system load.'**
  String get adminAnalyticsPageSubtitle;

  /// No description provided for @adminAccountGrowth.
  ///
  /// In en, this message translates to:
  /// **'Account Growth'**
  String get adminAccountGrowth;

  /// No description provided for @adminTaskThroughput.
  ///
  /// In en, this message translates to:
  /// **'Task Throughput'**
  String get adminTaskThroughput;

  /// No description provided for @adminCompletedLabel.
  ///
  /// In en, this message translates to:
  /// **'completed'**
  String get adminCompletedLabel;

  /// No description provided for @adminExceptions.
  ///
  /// In en, this message translates to:
  /// **'exceptions'**
  String get adminExceptions;

  /// No description provided for @adminStorageOccupancy.
  ///
  /// In en, this message translates to:
  /// **'Storage Occupancy'**
  String get adminStorageOccupancy;

  /// No description provided for @adminObjectsLabel.
  ///
  /// In en, this message translates to:
  /// **'objects'**
  String get adminObjectsLabel;

  /// No description provided for @adminSystemLoad.
  ///
  /// In en, this message translates to:
  /// **'System Load'**
  String get adminSystemLoad;

  /// No description provided for @adminHotConfig.
  ///
  /// In en, this message translates to:
  /// **'Hot Config'**
  String get adminHotConfig;

  /// No description provided for @adminRestartItems.
  ///
  /// In en, this message translates to:
  /// **'Restart Items'**
  String get adminRestartItems;

  /// No description provided for @adminStatusEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get adminStatusEnabled;

  /// No description provided for @adminStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get adminStatusDisabled;

  /// No description provided for @adminRoleSuperAdmin.
  ///
  /// In en, this message translates to:
  /// **'Super Admin'**
  String get adminRoleSuperAdmin;

  /// No description provided for @adminRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get adminRoleAdmin;

  /// No description provided for @adminRoleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get adminRoleMember;

  /// No description provided for @adminRoleGuest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get adminRoleGuest;

  /// No description provided for @adminGroupOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get adminGroupOverview;

  /// No description provided for @adminGroupOperations.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get adminGroupOperations;

  /// No description provided for @adminGroupIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity & Permissions'**
  String get adminGroupIdentity;

  /// No description provided for @adminGroupConfiguration.
  ///
  /// In en, this message translates to:
  /// **'System Config'**
  String get adminGroupConfiguration;

  /// No description provided for @adminGroupStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get adminGroupStorage;

  /// No description provided for @adminNavOverview.
  ///
  /// In en, this message translates to:
  /// **'Console Home'**
  String get adminNavOverview;

  /// No description provided for @adminNavAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get adminNavAnalytics;

  /// No description provided for @adminNavMonitoring.
  ///
  /// In en, this message translates to:
  /// **'System Monitor'**
  String get adminNavMonitoring;

  /// No description provided for @adminNavLogs.
  ///
  /// In en, this message translates to:
  /// **'Log Center'**
  String get adminNavLogs;

  /// No description provided for @adminNavTasks.
  ///
  /// In en, this message translates to:
  /// **'Background Tasks'**
  String get adminNavTasks;

  /// No description provided for @adminNavSessions.
  ///
  /// In en, this message translates to:
  /// **'Session Management'**
  String get adminNavSessions;

  /// No description provided for @adminNavUsers.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get adminNavUsers;

  /// No description provided for @adminNavRoles.
  ///
  /// In en, this message translates to:
  /// **'Role Management'**
  String get adminNavRoles;

  /// No description provided for @adminNavConfig.
  ///
  /// In en, this message translates to:
  /// **'Config Center'**
  String get adminNavConfig;

  /// No description provided for @adminNavStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage Management'**
  String get adminNavStorage;

  /// No description provided for @adminNavExternalStorage.
  ///
  /// In en, this message translates to:
  /// **'External Storage'**
  String get adminNavExternalStorage;

  /// No description provided for @adminOverviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin Console'**
  String get adminOverviewTitle;

  /// No description provided for @adminOverviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Key metrics of users, permissions, runtime status and storage capacity.'**
  String get adminOverviewSubtitle;

  /// No description provided for @adminAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get adminAnalyticsTitle;

  /// No description provided for @adminAnalyticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Centralized view of account growth, capacity trends, task throughput and system load.'**
  String get adminAnalyticsSubtitle;

  /// No description provided for @adminMonitoringTitle.
  ///
  /// In en, this message translates to:
  /// **'System Monitor'**
  String get adminMonitoringTitle;

  /// No description provided for @adminMonitoringSubtitle2.
  ///
  /// In en, this message translates to:
  /// **'View health checks, service metrics, node status and alerts.'**
  String get adminMonitoringSubtitle2;

  /// No description provided for @adminLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'Log Center'**
  String get adminLogsTitle;

  /// No description provided for @adminLogsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unified view of application logs, error logs and login audit.'**
  String get adminLogsSubtitle;

  /// No description provided for @adminTasksTitle.
  ///
  /// In en, this message translates to:
  /// **'Background Tasks'**
  String get adminTasksTitle;

  /// No description provided for @adminTasksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track indexing, transcoding, sync, backup and cleanup tasks.'**
  String get adminTasksSubtitle;

  /// No description provided for @adminSessionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Session Management'**
  String get adminSessionsTitle;

  /// No description provided for @adminSessionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View and manage user active sessions, supports forced logout.'**
  String get adminSessionsSubtitle;

  /// No description provided for @adminUsersTitle.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get adminUsersTitle;

  /// No description provided for @adminUsersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage accounts, status, quota and role assignment.'**
  String get adminUsersSubtitle;

  /// No description provided for @adminRolesTitle.
  ///
  /// In en, this message translates to:
  /// **'Role Management'**
  String get adminRolesTitle;

  /// No description provided for @adminRolesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Maintain roles, permission sets and resource access boundaries.'**
  String get adminRolesSubtitle;

  /// No description provided for @adminConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Config Center'**
  String get adminConfigTitle;

  /// No description provided for @adminConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage system config items, feature flags and hot update release status.'**
  String get adminConfigSubtitle;

  /// No description provided for @adminStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage Management'**
  String get adminStorageTitle;

  /// No description provided for @adminStorageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage MinIO buckets, capacity, and index maintenance.'**
  String get adminStorageSubtitle;

  /// No description provided for @adminExternalStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'External Storage Integration'**
  String get adminExternalStorageTitle;

  /// No description provided for @adminRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get adminRefresh;

  /// No description provided for @adminRecalculate.
  ///
  /// In en, this message translates to:
  /// **'Recalculate'**
  String get adminRecalculate;

  /// No description provided for @adminRecalculateDone.
  ///
  /// In en, this message translates to:
  /// **'Updated storage for {count} users'**
  String adminRecalculateDone(Object count);

  /// No description provided for @adminRebuildIndex.
  ///
  /// In en, this message translates to:
  /// **'Rebuild Index'**
  String get adminRebuildIndex;

  /// No description provided for @adminRebuildIndexDone.
  ///
  /// In en, this message translates to:
  /// **'Cleared {count} index documents, re-indexing in progress'**
  String adminRebuildIndexDone(Object count);

  /// No description provided for @adminApiResponseFormat.
  ///
  /// In en, this message translates to:
  /// **'Admin response format is incorrect'**
  String get adminApiResponseFormat;

  /// No description provided for @adminNoResponse.
  ///
  /// In en, this message translates to:
  /// **'Server did not return admin result'**
  String get adminNoResponse;

  /// No description provided for @adminOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'Admin operation failed'**
  String get adminOperationFailed;

  /// No description provided for @adminUserListFormat.
  ///
  /// In en, this message translates to:
  /// **'User list format is incorrect'**
  String get adminUserListFormat;

  /// No description provided for @adminUserResponseFormat.
  ///
  /// In en, this message translates to:
  /// **'User response format is incorrect'**
  String get adminUserResponseFormat;

  /// No description provided for @adminNoUserResult.
  ///
  /// In en, this message translates to:
  /// **'Server did not return user result'**
  String get adminNoUserResult;

  /// No description provided for @adminUserOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'User operation failed'**
  String get adminUserOperationFailed;

  /// No description provided for @adminConsoleResponseFormat.
  ///
  /// In en, this message translates to:
  /// **'Admin console response format is incorrect'**
  String get adminConsoleResponseFormat;

  /// No description provided for @adminNoConsoleResult.
  ///
  /// In en, this message translates to:
  /// **'Server did not return admin console result'**
  String get adminNoConsoleResult;

  /// No description provided for @adminConsoleLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Admin console load failed'**
  String get adminConsoleLoadFailed;

  /// No description provided for @adminNoDetailDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'No detailed diagnostics available'**
  String get adminNoDetailDiagnostics;

  /// No description provided for @readerNavBookshelf.
  ///
  /// In en, this message translates to:
  /// **'Bookshelf'**
  String get readerNavBookshelf;

  /// No description provided for @readerNavLibrary.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get readerNavLibrary;

  /// No description provided for @readerNavComics.
  ///
  /// In en, this message translates to:
  /// **'Comics'**
  String get readerNavComics;

  /// No description provided for @readerSegmentAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get readerSegmentAll;

  /// No description provided for @readerSegmentBooks.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get readerSegmentBooks;

  /// No description provided for @readerSegmentComics.
  ///
  /// In en, this message translates to:
  /// **'Comics'**
  String get readerSegmentComics;

  /// No description provided for @readerNavBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get readerNavBookmarks;

  /// No description provided for @readerNavFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get readerNavFavorites;

  /// No description provided for @readerManageHint.
  ///
  /// In en, this message translates to:
  /// **'Management tools visible to super admins only'**
  String get readerManageHint;

  /// No description provided for @readerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search book titles, authors…'**
  String get readerSearchHint;

  /// No description provided for @readerSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get readerSearch;

  /// No description provided for @readerThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get readerThemeLight;

  /// No description provided for @readerThemeEyeCare.
  ///
  /// In en, this message translates to:
  /// **'Eye Care'**
  String get readerThemeEyeCare;

  /// No description provided for @readerThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get readerThemeDark;

  /// No description provided for @readerThemeGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get readerThemeGreen;

  /// No description provided for @readerSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reading Settings'**
  String get readerSettingsTitle;

  /// No description provided for @readerReadingMode.
  ///
  /// In en, this message translates to:
  /// **'Reading Mode'**
  String get readerReadingMode;

  /// No description provided for @readerModeScroll.
  ///
  /// In en, this message translates to:
  /// **'Scroll'**
  String get readerModeScroll;

  /// No description provided for @readerModePage.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get readerModePage;

  /// No description provided for @readerFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get readerFontSize;

  /// No description provided for @readerLineHeight.
  ///
  /// In en, this message translates to:
  /// **'Line Height'**
  String get readerLineHeight;

  /// No description provided for @readerFontFamily.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get readerFontFamily;

  /// No description provided for @readerFontSerif.
  ///
  /// In en, this message translates to:
  /// **'Serif'**
  String get readerFontSerif;

  /// No description provided for @readerFontSans.
  ///
  /// In en, this message translates to:
  /// **'Sans'**
  String get readerFontSans;

  /// No description provided for @readerFontSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get readerFontSystem;

  /// No description provided for @readerTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get readerTheme;

  /// No description provided for @readerImmersiveMode.
  ///
  /// In en, this message translates to:
  /// **'Immersive mode'**
  String get readerImmersiveMode;

  /// No description provided for @readerPreviousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get readerPreviousPage;

  /// No description provided for @readerNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get readerNextPage;

  /// No description provided for @readerPreviousChapter.
  ///
  /// In en, this message translates to:
  /// **'Previous chapter'**
  String get readerPreviousChapter;

  /// No description provided for @readerReadAloud.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get readerReadAloud;

  /// No description provided for @readerShortcutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get readerShortcutsTitle;

  /// No description provided for @readerShortcutNavigation.
  ///
  /// In en, this message translates to:
  /// **'Reading navigation'**
  String get readerShortcutNavigation;

  /// No description provided for @readerShortcutTurnPage.
  ///
  /// In en, this message translates to:
  /// **'Turn a page or move one viewport'**
  String get readerShortcutTurnPage;

  /// No description provided for @readerShortcutContents.
  ///
  /// In en, this message translates to:
  /// **'Open or close contents'**
  String get readerShortcutContents;

  /// No description provided for @readerShortcutBookmark.
  ///
  /// In en, this message translates to:
  /// **'Add or remove bookmark'**
  String get readerShortcutBookmark;

  /// No description provided for @readerShortcutSearch.
  ///
  /// In en, this message translates to:
  /// **'Search the current chapter'**
  String get readerShortcutSearch;

  /// No description provided for @readerShortcutAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Open annotations and notes'**
  String get readerShortcutAnnotations;

  /// No description provided for @readerShortcutImmersive.
  ///
  /// In en, this message translates to:
  /// **'Toggle immersive mode'**
  String get readerShortcutImmersive;

  /// No description provided for @readerShortcutFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Toggle fullscreen'**
  String get readerShortcutFullscreen;

  /// No description provided for @readerShortcutTypography.
  ///
  /// In en, this message translates to:
  /// **'Adjust or reset typography'**
  String get readerShortcutTypography;

  /// No description provided for @readerShortcutClose.
  ///
  /// In en, this message translates to:
  /// **'Close the current panel or go back'**
  String get readerShortcutClose;

  /// No description provided for @readerShortcutMode.
  ///
  /// In en, this message translates to:
  /// **'Switch comic reading mode'**
  String get readerShortcutMode;

  /// No description provided for @readerSearchCurrentChapter.
  ///
  /// In en, this message translates to:
  /// **'Search current chapter'**
  String get readerSearchCurrentChapter;

  /// No description provided for @readerNoSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No matching content found'**
  String get readerNoSearchResults;

  /// No description provided for @readerSearchResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count} matches'**
  String readerSearchResultCount(int count);

  /// No description provided for @readerReadingProgress.
  ///
  /// In en, this message translates to:
  /// **'Reading progress {percent}%'**
  String readerReadingProgress(int percent);

  /// No description provided for @readerResetTypography.
  ///
  /// In en, this message translates to:
  /// **'Reset typography'**
  String get readerResetTypography;

  /// No description provided for @readerComicModePage.
  ///
  /// In en, this message translates to:
  /// **'Page mode'**
  String get readerComicModePage;

  /// No description provided for @readerComicModeScroll.
  ///
  /// In en, this message translates to:
  /// **'Scroll mode'**
  String get readerComicModeScroll;

  /// No description provided for @readerComicFullWidth.
  ///
  /// In en, this message translates to:
  /// **'Use all available width in continuous mode'**
  String get readerComicFullWidth;

  /// No description provided for @readerComicFullWidthHint.
  ///
  /// In en, this message translates to:
  /// **'Turn off to limit page width on desktop and avoid excessive upscaling'**
  String get readerComicFullWidthHint;

  /// No description provided for @readerComicContentWidth.
  ///
  /// In en, this message translates to:
  /// **'Content width: {width} px'**
  String readerComicContentWidth(int width);

  /// No description provided for @readerComicPageGap.
  ///
  /// In en, this message translates to:
  /// **'Page spacing: {gap} px'**
  String readerComicPageGap(int gap);

  /// No description provided for @readerComicImageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Comic page failed to load'**
  String get readerComicImageLoadFailed;

  /// No description provided for @readerComicImageDecodeFailed.
  ///
  /// In en, this message translates to:
  /// **'Comic page failed to decode'**
  String get readerComicImageDecodeFailed;

  /// No description provided for @readerStatsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get readerStatsToday;

  /// No description provided for @readerStatsWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get readerStatsWeek;

  /// No description provided for @readerStatsStreak.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get readerStatsStreak;

  /// No description provided for @readerStatsBooks.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get readerStatsBooks;

  /// No description provided for @readerStatsMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String readerStatsMinutes(Object count);

  /// No description provided for @readerStatsHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String readerStatsHoursMinutes(Object hours, Object minutes);

  /// No description provided for @readerStatsHours.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String readerStatsHours(Object hours);

  /// No description provided for @readerStatsDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String readerStatsDays(Object count);

  /// No description provided for @readerNoContent.
  ///
  /// In en, this message translates to:
  /// **'No content'**
  String get readerNoContent;

  /// No description provided for @readerTtsPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get readerTtsPlay;

  /// No description provided for @readerTtsPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get readerTtsPause;

  /// No description provided for @readerTtsStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get readerTtsStop;

  /// No description provided for @readerAlreadyFirstChapter.
  ///
  /// In en, this message translates to:
  /// **'Already at the first chapter'**
  String get readerAlreadyFirstChapter;

  /// No description provided for @readerAlreadyLastChapter.
  ///
  /// In en, this message translates to:
  /// **'Already at the last chapter'**
  String get readerAlreadyLastChapter;

  /// No description provided for @readerRestoringProgress.
  ///
  /// In en, this message translates to:
  /// **'Restoring reading position…'**
  String get readerRestoringProgress;

  /// No description provided for @readerReturnToProgress.
  ///
  /// In en, this message translates to:
  /// **'Return to last position'**
  String get readerReturnToProgress;

  /// No description provided for @readerReturn.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get readerReturn;

  /// No description provided for @readerBookmarkRemoved.
  ///
  /// In en, this message translates to:
  /// **'Bookmark removed'**
  String get readerBookmarkRemoved;

  /// No description provided for @readerBookmarkAdded.
  ///
  /// In en, this message translates to:
  /// **'Bookmark added'**
  String get readerBookmarkAdded;

  /// No description provided for @readerBookmarkFailed.
  ///
  /// In en, this message translates to:
  /// **'Bookmark operation failed'**
  String get readerBookmarkFailed;

  /// No description provided for @readerHighlightAdded.
  ///
  /// In en, this message translates to:
  /// **'Highlight added'**
  String get readerHighlightAdded;

  /// No description provided for @readerAddAnnotation.
  ///
  /// In en, this message translates to:
  /// **'Add Annotation'**
  String get readerAddAnnotation;

  /// No description provided for @readerAnnotationHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your notes...'**
  String get readerAnnotationHint;

  /// No description provided for @readerAddBookmark.
  ///
  /// In en, this message translates to:
  /// **'Add bookmark'**
  String get readerAddBookmark;

  /// No description provided for @readerRemoveBookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove bookmark'**
  String get readerRemoveBookmark;

  /// No description provided for @readerChapterList.
  ///
  /// In en, this message translates to:
  /// **'Chapter List'**
  String get readerChapterList;

  /// No description provided for @readerOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed, please try again later'**
  String get readerOperationFailed;

  /// No description provided for @readerOperationSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Operation submitted'**
  String get readerOperationSubmitted;

  /// No description provided for @readerChapterLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'The chapter could not be loaded. Please try again.'**
  String get readerChapterLoadFailed;

  /// No description provided for @readerRemoveFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get readerRemoveFavorite;

  /// No description provided for @readerAddFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get readerAddFavorite;

  /// No description provided for @readerReadComic.
  ///
  /// In en, this message translates to:
  /// **'Read Comic'**
  String get readerReadComic;

  /// No description provided for @readerNoPages.
  ///
  /// In en, this message translates to:
  /// **'No pages available'**
  String get readerNoPages;

  /// No description provided for @readerContinueReading.
  ///
  /// In en, this message translates to:
  /// **'Continue Reading'**
  String get readerContinueReading;

  /// No description provided for @readerNavNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get readerNavNotes;

  /// No description provided for @readerStartReading.
  ///
  /// In en, this message translates to:
  /// **'Start Reading'**
  String get readerStartReading;

  /// No description provided for @readerAddedToBookshelf.
  ///
  /// In en, this message translates to:
  /// **'Added to Bookshelf'**
  String get readerAddedToBookshelf;

  /// No description provided for @readerAddToBookshelf.
  ///
  /// In en, this message translates to:
  /// **'Add to Bookshelf'**
  String get readerAddToBookshelf;

  /// No description provided for @readerNoDescription.
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get readerNoDescription;

  /// No description provided for @readerDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get readerDescription;

  /// No description provided for @readerCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get readerCollapse;

  /// No description provided for @readerExpandFull.
  ///
  /// In en, this message translates to:
  /// **'Show full text'**
  String get readerExpandFull;

  /// No description provided for @readerChapterListCount.
  ///
  /// In en, this message translates to:
  /// **'Chapter List ({count} chapters)'**
  String readerChapterListCount(Object count);

  /// No description provided for @readerTotalPages.
  ///
  /// In en, this message translates to:
  /// **'{count} pages total'**
  String readerTotalPages(Object count);

  /// No description provided for @readerPageCount.
  ///
  /// In en, this message translates to:
  /// **'{count} pages'**
  String readerPageCount(Object count);

  /// No description provided for @readerViewAllChapters.
  ///
  /// In en, this message translates to:
  /// **'View all {count} chapters'**
  String readerViewAllChapters(Object count);

  /// No description provided for @readerPageInfo.
  ///
  /// In en, this message translates to:
  /// **'Page Info'**
  String get readerPageInfo;

  /// No description provided for @readerTableOfContents.
  ///
  /// In en, this message translates to:
  /// **'Table of Contents'**
  String get readerTableOfContents;

  /// No description provided for @readerTotalChapters.
  ///
  /// In en, this message translates to:
  /// **'{count} chapters total'**
  String readerTotalChapters(Object count);

  /// No description provided for @readerDeleteCollection.
  ///
  /// In en, this message translates to:
  /// **'Delete Collection'**
  String get readerDeleteCollection;

  /// No description provided for @readerCollectionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String readerCollectionCount(Object count);

  /// No description provided for @readerCollectionEmpty.
  ///
  /// In en, this message translates to:
  /// **'No books in this collection'**
  String get readerCollectionEmpty;

  /// No description provided for @readerCollectionEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Long press a book on the bookshelf to add it to a collection.'**
  String get readerCollectionEmptyHint;

  /// No description provided for @readerConfirmDeleteCollection.
  ///
  /// In en, this message translates to:
  /// **'Delete collection'**
  String get readerConfirmDeleteCollection;

  /// No description provided for @readerConfirmDeleteCollectionMsg.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? Books in the collection will not be deleted.'**
  String readerConfirmDeleteCollectionMsg(Object name);

  /// No description provided for @readerDeletedCollection.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{name}\"'**
  String readerDeletedCollection(Object name);

  /// No description provided for @readerDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String readerDeleteFailed(Object error);

  /// No description provided for @readerNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes made'**
  String get readerNoChanges;

  /// No description provided for @readerMetadataSaved.
  ///
  /// In en, this message translates to:
  /// **'Metadata saved'**
  String get readerMetadataSaved;

  /// No description provided for @readerSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String readerSaveFailed(Object error);

  /// No description provided for @readerEditMetadata.
  ///
  /// In en, this message translates to:
  /// **'Edit Metadata'**
  String get readerEditMetadata;

  /// No description provided for @readerSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get readerSave;

  /// No description provided for @readerLabelTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get readerLabelTitle;

  /// No description provided for @readerLabelAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get readerLabelAuthor;

  /// No description provided for @readerLabelDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get readerLabelDescription;

  /// No description provided for @readerLabelPublisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get readerLabelPublisher;

  /// No description provided for @readerLabelReleaseDate.
  ///
  /// In en, this message translates to:
  /// **'Release Date'**
  String get readerLabelReleaseDate;

  /// No description provided for @readerLabelRating.
  ///
  /// In en, this message translates to:
  /// **'Rating (0-10)'**
  String get readerLabelRating;

  /// No description provided for @readerLabelGenres.
  ///
  /// In en, this message translates to:
  /// **'Genre Tags (comma separated)'**
  String get readerLabelGenres;

  /// No description provided for @readerLabelSerialStatus.
  ///
  /// In en, this message translates to:
  /// **'Serial Status'**
  String get readerLabelSerialStatus;

  /// No description provided for @readerStatusOngoing.
  ///
  /// In en, this message translates to:
  /// **'Ongoing'**
  String get readerStatusOngoing;

  /// No description provided for @readerStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get readerStatusCompleted;

  /// No description provided for @readerStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get readerStatusUnknown;

  /// No description provided for @readerSelectFromFile.
  ///
  /// In en, this message translates to:
  /// **'Select from Files'**
  String get readerSelectFromFile;

  /// No description provided for @readerUploadCover.
  ///
  /// In en, this message translates to:
  /// **'Upload New Cover'**
  String get readerUploadCover;

  /// No description provided for @readerNoImageFiles.
  ///
  /// In en, this message translates to:
  /// **'No image files available in the file system'**
  String get readerNoImageFiles;

  /// No description provided for @readerSelectCoverImage.
  ///
  /// In en, this message translates to:
  /// **'Select Cover Image'**
  String get readerSelectCoverImage;

  /// No description provided for @readerUnknownFile.
  ///
  /// In en, this message translates to:
  /// **'Unknown file'**
  String get readerUnknownFile;

  /// No description provided for @readerCoverUpdated.
  ///
  /// In en, this message translates to:
  /// **'Cover updated'**
  String get readerCoverUpdated;

  /// No description provided for @readerOperationFailedError.
  ///
  /// In en, this message translates to:
  /// **'Operation failed: {error}'**
  String readerOperationFailedError(Object error);

  /// No description provided for @readerCoverUploaded.
  ///
  /// In en, this message translates to:
  /// **'Cover uploaded'**
  String get readerCoverUploaded;

  /// No description provided for @readerUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {error}'**
  String readerUploadFailed(Object error);

  /// No description provided for @readerPageInfoFormat.
  ///
  /// In en, this message translates to:
  /// **'Page {current} / {total} pages'**
  String readerPageInfoFormat(Object current, Object total);

  /// No description provided for @readerPageNumber.
  ///
  /// In en, this message translates to:
  /// **'Page {page}'**
  String readerPageNumber(Object page);

  /// No description provided for @readerWordCount.
  ///
  /// In en, this message translates to:
  /// **'{count} characters'**
  String readerWordCount(Object count);

  /// No description provided for @readerWordCountWan.
  ///
  /// In en, this message translates to:
  /// **'{count} 万'**
  String readerWordCountWan(Object count);

  /// No description provided for @readerRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get readerRetry;

  /// No description provided for @readerRtl.
  ///
  /// In en, this message translates to:
  /// **'Right to Left (RTL)'**
  String get readerRtl;

  /// No description provided for @readerLtr.
  ///
  /// In en, this message translates to:
  /// **'Left to Right (LTR)'**
  String get readerLtr;

  /// No description provided for @readerChapterListBtn.
  ///
  /// In en, this message translates to:
  /// **'Chapter List'**
  String get readerChapterListBtn;

  /// No description provided for @readerPrevChapter.
  ///
  /// In en, this message translates to:
  /// **'Previous Chapter'**
  String get readerPrevChapter;

  /// No description provided for @readerNextChapter.
  ///
  /// In en, this message translates to:
  /// **'Next Chapter'**
  String get readerNextChapter;

  /// No description provided for @readerClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get readerClose;

  /// No description provided for @readerDeletedItem.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{name}\"'**
  String readerDeletedItem(Object name);

  /// No description provided for @readerDeleteItemFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed, please try again later'**
  String get readerDeleteItemFailed;

  /// No description provided for @readerRemovedFromBookshelf.
  ///
  /// In en, this message translates to:
  /// **'Removed from bookshelf'**
  String get readerRemovedFromBookshelf;

  /// No description provided for @readerSearchBooksHint.
  ///
  /// In en, this message translates to:
  /// **'Search book titles, authors…'**
  String get readerSearchBooksHint;

  /// No description provided for @readerCollectionCreated.
  ///
  /// In en, this message translates to:
  /// **'Collection \"{name}\" created'**
  String readerCollectionCreated(Object name);

  /// No description provided for @readerCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Create failed, please try again later'**
  String get readerCreateFailed;

  /// No description provided for @readerImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" imported successfully'**
  String readerImportSuccess(Object name);

  /// No description provided for @readerImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed, please try again later'**
  String get readerImportFailed;

  /// No description provided for @readerImportFailedWithReason.
  ///
  /// In en, this message translates to:
  /// **'Failed to import {name}: {reason}'**
  String readerImportFailedWithReason(Object name, Object reason);

  /// No description provided for @readerImportFromFile.
  ///
  /// In en, this message translates to:
  /// **'Import from device'**
  String get readerImportFromFile;

  /// No description provided for @readerImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get readerImporting;

  /// No description provided for @readerImportTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose EPUB import type'**
  String get readerImportTypeTitle;

  /// No description provided for @readerImportTypeDesc.
  ///
  /// In en, this message translates to:
  /// **'Fixed-layout or image-based EPUB files can be imported as comics. Text EPUB files should usually be imported as books.'**
  String get readerImportTypeDesc;

  /// No description provided for @readerImportNovel.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get readerImportNovel;

  /// No description provided for @readerImportLiterature.
  ///
  /// In en, this message translates to:
  /// **'Literature'**
  String get readerImportLiterature;

  /// No description provided for @readerImportAcademic.
  ///
  /// In en, this message translates to:
  /// **'Academic'**
  String get readerImportAcademic;

  /// No description provided for @readerImportTechnical.
  ///
  /// In en, this message translates to:
  /// **'Technical'**
  String get readerImportTechnical;

  /// No description provided for @readerImportPoetry.
  ///
  /// In en, this message translates to:
  /// **'Poetry'**
  String get readerImportPoetry;

  /// No description provided for @readerImportEssay.
  ///
  /// In en, this message translates to:
  /// **'Essay'**
  String get readerImportEssay;

  /// No description provided for @readerImportComic.
  ///
  /// In en, this message translates to:
  /// **'Comic'**
  String get readerImportComic;

  /// No description provided for @readerPendingImport.
  ///
  /// In en, this message translates to:
  /// **'Pending Import'**
  String get readerPendingImport;

  /// No description provided for @readerPendingImportCount.
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String readerPendingImportCount(Object count);

  /// No description provided for @readerPendingImportDesc.
  ///
  /// In en, this message translates to:
  /// **'These files have been uploaded but not yet imported to the Reader Center. EPUB files can be imported as books or comics.'**
  String get readerPendingImportDesc;

  /// No description provided for @readerNoPendingImport.
  ///
  /// In en, this message translates to:
  /// **'No files pending import'**
  String get readerNoPendingImport;

  /// No description provided for @readerNoPendingImportHint.
  ///
  /// In en, this message translates to:
  /// **'After uploading EPUB, CBZ and other reading files, they will appear here. Already imported files won\'t be shown again.'**
  String get readerNoPendingImportHint;

  /// No description provided for @readerReparse.
  ///
  /// In en, this message translates to:
  /// **'Re-parse'**
  String get readerReparse;

  /// No description provided for @readerReparseDesc.
  ///
  /// In en, this message translates to:
  /// **'Re-parse cover, metadata and chapters for imported content. Useful when parsing was incomplete or new parsing capabilities have been added.'**
  String get readerReparseDesc;

  /// No description provided for @readerNoImportedContent.
  ///
  /// In en, this message translates to:
  /// **'No imported content'**
  String get readerNoImportedContent;

  /// No description provided for @readerNoImportedContentHint.
  ///
  /// In en, this message translates to:
  /// **'After importing books, you can re-parse them here.'**
  String get readerNoImportedContentHint;

  /// No description provided for @readerNoFileNode.
  ///
  /// In en, this message translates to:
  /// **'This entry has no file node, cannot re-parse'**
  String get readerNoFileNode;

  /// No description provided for @readerReparseSuccess.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" re-parsed successfully'**
  String readerReparseSuccess(Object name);

  /// No description provided for @readerComicReparseStarted.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" re-parse has started. Refresh later to view the status.'**
  String readerComicReparseStarted(Object name);

  /// No description provided for @readerReparseFailed.
  ///
  /// In en, this message translates to:
  /// **'Re-parse failed, please try again later'**
  String get readerReparseFailed;

  /// No description provided for @readerComicImportStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Comic Parse Status'**
  String get readerComicImportStatusTitle;

  /// No description provided for @readerComicImportStatusValue.
  ///
  /// In en, this message translates to:
  /// **'Current status: {status}'**
  String readerComicImportStatusValue(Object status);

  /// No description provided for @readerComicSourceCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sources'**
  String readerComicSourceCount(Object count);

  /// No description provided for @readerComicCatalogCount.
  ///
  /// In en, this message translates to:
  /// **'{count} catalog entries'**
  String readerComicCatalogCount(Object count);

  /// No description provided for @readerComicCatalogPreview.
  ///
  /// In en, this message translates to:
  /// **'Catalog Structure'**
  String get readerComicCatalogPreview;

  /// No description provided for @readerComicPagePreview.
  ///
  /// In en, this message translates to:
  /// **'Page Preview'**
  String get readerComicPagePreview;

  /// No description provided for @readerComicCatalogPending.
  ///
  /// In en, this message translates to:
  /// **'Catalog parsing is still in progress. Refresh later to view the result.'**
  String get readerComicCatalogPending;

  /// No description provided for @readerComicPagesPending.
  ///
  /// In en, this message translates to:
  /// **'Pages are still being parsed. Refresh later to view previews.'**
  String get readerComicPagesPending;

  /// No description provided for @readerComicImportPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting to parse'**
  String get readerComicImportPending;

  /// No description provided for @readerComicImportParsing.
  ///
  /// In en, this message translates to:
  /// **'Parsing'**
  String get readerComicImportParsing;

  /// No description provided for @readerComicImportReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get readerComicImportReady;

  /// No description provided for @readerComicImportPartialFailed.
  ///
  /// In en, this message translates to:
  /// **'Partially Failed'**
  String get readerComicImportPartialFailed;

  /// No description provided for @readerComicImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Parse Failed'**
  String get readerComicImportFailed;

  /// No description provided for @readerComicEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No comics yet'**
  String get readerComicEmptyTitle;

  /// No description provided for @readerComicEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Import a CBZ, ZIP, or image-based EPUB to start reading.'**
  String get readerComicEmptyHint;

  /// No description provided for @readerComicParsingMessage.
  ///
  /// In en, this message translates to:
  /// **'The comic is being parsed…'**
  String get readerComicParsingMessage;

  /// No description provided for @readerComicPartialFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Some sources failed to parse. Retry or remove the failed sources.'**
  String get readerComicPartialFailedMessage;

  /// No description provided for @readerComicFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Parsing failed. Retry the failed source.'**
  String get readerComicFailedMessage;

  /// No description provided for @readerComicSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get readerComicSources;

  /// No description provided for @readerComicRetryCount.
  ///
  /// In en, this message translates to:
  /// **'Retried {count} times'**
  String readerComicRetryCount(Object count);

  /// No description provided for @readerRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Refresh failed, please try again later'**
  String get readerRefreshFailed;

  /// No description provided for @readerDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get readerDone;

  /// No description provided for @readerUnsupportedLink.
  ///
  /// In en, this message translates to:
  /// **'This link is not supported yet'**
  String get readerUnsupportedLink;

  /// No description provided for @readerUnknownAuthor.
  ///
  /// In en, this message translates to:
  /// **'Unknown author'**
  String get readerUnknownAuthor;

  /// No description provided for @readerUnknownBook.
  ///
  /// In en, this message translates to:
  /// **'Unknown book'**
  String get readerUnknownBook;

  /// No description provided for @readerReadingReport.
  ///
  /// In en, this message translates to:
  /// **'Reading Report'**
  String get readerReadingReport;

  /// No description provided for @readerWeeklyHours.
  ///
  /// In en, this message translates to:
  /// **'Read {hours} hours this week'**
  String readerWeeklyHours(Object hours);

  /// No description provided for @readerContinueBtn.
  ///
  /// In en, this message translates to:
  /// **'Continue Reading'**
  String get readerContinueBtn;

  /// No description provided for @readerBookshelfSection.
  ///
  /// In en, this message translates to:
  /// **'Bookshelf'**
  String get readerBookshelfSection;

  /// No description provided for @readerShowAllBooks.
  ///
  /// In en, this message translates to:
  /// **'Show all {count} more'**
  String readerShowAllBooks(Object count);

  /// No description provided for @readerViewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get readerViewAll;

  /// No description provided for @readerBookCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String readerBookCount(Object count);

  /// No description provided for @readerContinueCount.
  ///
  /// In en, this message translates to:
  /// **'{count} continue'**
  String readerContinueCount(Object count);

  /// No description provided for @readerRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get readerRefresh;

  /// No description provided for @readerAddBook.
  ///
  /// In en, this message translates to:
  /// **'Add Book'**
  String get readerAddBook;

  /// No description provided for @readerImportQueued.
  ///
  /// In en, this message translates to:
  /// **'File uploaded. Import is running in the background...'**
  String get readerImportQueued;

  /// No description provided for @readerImportQueuedShort.
  ///
  /// In en, this message translates to:
  /// **'Waiting to upload'**
  String get readerImportQueuedShort;

  /// No description provided for @readerImportRegistering.
  ///
  /// In en, this message translates to:
  /// **'Adding to library'**
  String get readerImportRegistering;

  /// No description provided for @readerCancelImport.
  ///
  /// In en, this message translates to:
  /// **'Stop import'**
  String get readerCancelImport;

  /// No description provided for @readerImportCancelled.
  ///
  /// In en, this message translates to:
  /// **'Import cancelled'**
  String get readerImportCancelled;

  /// No description provided for @readerMetadataManagement.
  ///
  /// In en, this message translates to:
  /// **'Metadata Management'**
  String get readerMetadataManagement;

  /// No description provided for @readerMetadataDesc.
  ///
  /// In en, this message translates to:
  /// **'Manually edit metadata for books/comics, including title, author, description, cover, etc. Visible to super admins only.'**
  String get readerMetadataDesc;

  /// No description provided for @readerNoBookEntries.
  ///
  /// In en, this message translates to:
  /// **'No book entries'**
  String get readerNoBookEntries;

  /// No description provided for @readerNoBookEntriesHint.
  ///
  /// In en, this message translates to:
  /// **'Import books to manage their metadata here.'**
  String get readerNoBookEntriesHint;

  /// No description provided for @readerStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get readerStatusPending;

  /// No description provided for @readerStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get readerStatusFailed;

  /// No description provided for @readerStatusManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get readerStatusManual;

  /// No description provided for @readerStatusMatched.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get readerStatusMatched;

  /// No description provided for @readerEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get readerEdit;

  /// No description provided for @readerScrapeQueue.
  ///
  /// In en, this message translates to:
  /// **'Scrape Queue'**
  String get readerScrapeQueue;

  /// No description provided for @readerScrapeQueueDesc.
  ///
  /// In en, this message translates to:
  /// **'Entries missing metadata (description, rating, genre, etc.) can be manually scraped. Visible to super admins only.'**
  String get readerScrapeQueueDesc;

  /// No description provided for @readerAllMetadataComplete.
  ///
  /// In en, this message translates to:
  /// **'All entries have complete metadata'**
  String get readerAllMetadataComplete;

  /// No description provided for @readerScrapeHint.
  ///
  /// In en, this message translates to:
  /// **'Newly imported books will be automatically scraped. You can also manually retry from the detail page.'**
  String get readerScrapeHint;

  /// No description provided for @readerScrapeSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Scrape task submitted: {id}…'**
  String readerScrapeSubmitted(Object id);

  /// No description provided for @readerScrapeSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Scrape task submission failed, please try again later'**
  String get readerScrapeSubmitFailed;

  /// No description provided for @readerSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting…'**
  String get readerSubmitting;

  /// No description provided for @readerBatchScrape.
  ///
  /// In en, this message translates to:
  /// **'Batch Scrape'**
  String get readerBatchScrape;

  /// No description provided for @readerBatchScrapeResult.
  ///
  /// In en, this message translates to:
  /// **'Submitted {success} / {total} scrape tasks'**
  String readerBatchScrapeResult(Object success, Object total);

  /// No description provided for @readerSubmittingLabel.
  ///
  /// In en, this message translates to:
  /// **'Submitting'**
  String get readerSubmittingLabel;

  /// No description provided for @readerScrapeLabel.
  ///
  /// In en, this message translates to:
  /// **'Scrape'**
  String get readerScrapeLabel;

  /// No description provided for @readerRemoveFromBookshelf.
  ///
  /// In en, this message translates to:
  /// **'Remove from Bookshelf'**
  String get readerRemoveFromBookshelf;

  /// No description provided for @readerDeleteBook.
  ///
  /// In en, this message translates to:
  /// **'Delete Book'**
  String get readerDeleteBook;

  /// No description provided for @readerDeleteBookHint.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete the book and its source file'**
  String get readerDeleteBookHint;

  /// No description provided for @readerDeleteSource.
  ///
  /// In en, this message translates to:
  /// **'Delete source'**
  String get readerDeleteSource;

  /// No description provided for @readerConfirmDeleteSource.
  ///
  /// In en, this message translates to:
  /// **'Delete source \"{name}\"? Its parsed pages will be removed from this comic, while the original file remains in Files.'**
  String readerConfirmDeleteSource(Object name);

  /// No description provided for @readerConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm Permanent Deletion'**
  String get readerConfirmDelete;

  /// No description provided for @readerConfirmDeleteMsg.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from the library? The source file will be kept.'**
  String readerConfirmDeleteMsg(Object name);

  /// No description provided for @readerFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'{field} cannot be empty'**
  String readerFieldRequired(Object field);

  /// No description provided for @readerHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get readerHistory;

  /// No description provided for @readerImports.
  ///
  /// In en, this message translates to:
  /// **'Imports'**
  String get readerImports;

  /// No description provided for @readerGroupPersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get readerGroupPersonal;

  /// No description provided for @readerGroupTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get readerGroupTools;

  /// No description provided for @readerGroupManagement.
  ///
  /// In en, this message translates to:
  /// **'Management'**
  String get readerGroupManagement;

  /// No description provided for @readerPercentRead.
  ///
  /// In en, this message translates to:
  /// **'{percent}% read'**
  String readerPercentRead(Object percent);

  /// No description provided for @readerSectionNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'{section} not yet available'**
  String readerSectionNotAvailable(Object section);

  /// No description provided for @readerSectionNotAvailableHint.
  ///
  /// In en, this message translates to:
  /// **'This entry has been reserved and will be connected to an independent content page later.'**
  String get readerSectionNotAvailableHint;

  /// No description provided for @readerNoBookmarks.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks yet'**
  String get readerNoBookmarks;

  /// No description provided for @readerNoBookmarksHint.
  ///
  /// In en, this message translates to:
  /// **'Add bookmarks while reading to quickly jump back here later.'**
  String get readerNoBookmarksHint;

  /// No description provided for @readerEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No content here yet'**
  String get readerEmptyHint;

  /// No description provided for @readerEmptyHintDesc.
  ///
  /// In en, this message translates to:
  /// **'After importing books from the file manager, they will automatically appear on the bookshelf.'**
  String get readerEmptyHintDesc;

  /// No description provided for @readerHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get readerHighlight;

  /// No description provided for @readerAnnotate.
  ///
  /// In en, this message translates to:
  /// **'Annotate'**
  String get readerAnnotate;

  /// No description provided for @readerRemoveHighlight.
  ///
  /// In en, this message translates to:
  /// **'Remove highlight'**
  String get readerRemoveHighlight;

  /// No description provided for @readerRemoveAnnotation.
  ///
  /// In en, this message translates to:
  /// **'Remove annotation'**
  String get readerRemoveAnnotation;

  /// No description provided for @readerCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get readerCopy;

  /// No description provided for @readerAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Annotations'**
  String get readerAnnotations;

  /// No description provided for @readerNoAnnotations.
  ///
  /// In en, this message translates to:
  /// **'No annotations yet'**
  String get readerNoAnnotations;

  /// No description provided for @readerEditAnnotation.
  ///
  /// In en, this message translates to:
  /// **'Edit annotation'**
  String get readerEditAnnotation;

  /// No description provided for @readerDeleteAnnotation.
  ///
  /// In en, this message translates to:
  /// **'Delete annotation'**
  String get readerDeleteAnnotation;

  /// No description provided for @readerSearchAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Search annotations'**
  String get readerSearchAnnotations;

  /// No description provided for @readerSearchAnnotationsHint.
  ///
  /// In en, this message translates to:
  /// **'Search annotations...'**
  String get readerSearchAnnotationsHint;

  /// No description provided for @readerThisChapter.
  ///
  /// In en, this message translates to:
  /// **'This chapter'**
  String get readerThisChapter;

  /// No description provided for @readerAllChapters.
  ///
  /// In en, this message translates to:
  /// **'All chapters'**
  String get readerAllChapters;

  /// No description provided for @readerPageTransition.
  ///
  /// In en, this message translates to:
  /// **'Page Transition'**
  String get readerPageTransition;

  /// No description provided for @readerTransitionSlide.
  ///
  /// In en, this message translates to:
  /// **'Slide'**
  String get readerTransitionSlide;

  /// No description provided for @readerTransitionCover.
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get readerTransitionCover;

  /// No description provided for @readerTransitionFade.
  ///
  /// In en, this message translates to:
  /// **'Fade'**
  String get readerTransitionFade;

  /// No description provided for @readerTransitionScroll.
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get readerTransitionScroll;

  /// No description provided for @videoSectionMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get videoSectionMovies;

  /// No description provided for @videoSectionTvShows.
  ///
  /// In en, this message translates to:
  /// **'TV Shows'**
  String get videoSectionTvShows;

  /// No description provided for @videoSectionAnime.
  ///
  /// In en, this message translates to:
  /// **'Anime'**
  String get videoSectionAnime;

  /// No description provided for @videoSectionCollections.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get videoSectionCollections;

  /// No description provided for @videoSectionRecent.
  ///
  /// In en, this message translates to:
  /// **'Recently Added'**
  String get videoSectionRecent;

  /// No description provided for @videoSectionContinueWatching.
  ///
  /// In en, this message translates to:
  /// **'Continue Watching'**
  String get videoSectionContinueWatching;

  /// No description provided for @videoSectionFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get videoSectionFavorites;

  /// No description provided for @videoSectionHistory.
  ///
  /// In en, this message translates to:
  /// **'Watch History'**
  String get videoSectionHistory;

  /// No description provided for @videoSeriesFeatured.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get videoSeriesFeatured;

  /// No description provided for @videoSectionMetadataManagement.
  ///
  /// In en, this message translates to:
  /// **'Metadata'**
  String get videoSectionMetadataManagement;

  /// No description provided for @videoSectionLibraryScan.
  ///
  /// In en, this message translates to:
  /// **'Media Library Management'**
  String get videoSectionLibraryScan;

  /// No description provided for @videoSidebarGroupLibrary.
  ///
  /// In en, this message translates to:
  /// **'Media Library'**
  String get videoSidebarGroupLibrary;

  /// No description provided for @videoSidebarGroupMine.
  ///
  /// In en, this message translates to:
  /// **'My Media'**
  String get videoSidebarGroupMine;

  /// No description provided for @videoSidebarGroupManagement.
  ///
  /// In en, this message translates to:
  /// **'Management Tools'**
  String get videoSidebarGroupManagement;

  /// No description provided for @videoRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get videoRefreshTooltip;

  /// No description provided for @videoBackToPortal.
  ///
  /// In en, this message translates to:
  /// **'Portal home'**
  String get videoBackToPortal;

  /// No description provided for @videoBackToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Back to library'**
  String get videoBackToLibrary;

  /// No description provided for @videoSearchMovies.
  ///
  /// In en, this message translates to:
  /// **'Search Movies'**
  String get videoSearchMovies;

  /// No description provided for @videoSearchMovieHint.
  ///
  /// In en, this message translates to:
  /// **'Enter movie name...'**
  String get videoSearchMovieHint;

  /// No description provided for @videoCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get videoCancel;

  /// No description provided for @videoSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get videoSearch;

  /// No description provided for @videoManageAdminOnly.
  ///
  /// In en, this message translates to:
  /// **'Management tools visible to admins only'**
  String get videoManageAdminOnly;

  /// No description provided for @videoBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get videoBrowse;

  /// No description provided for @videoMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get videoMore;

  /// No description provided for @videoClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get videoClose;

  /// No description provided for @videoSearchLibraryHint.
  ///
  /// In en, this message translates to:
  /// **'Search movie library...'**
  String get videoSearchLibraryHint;

  /// No description provided for @videoMovieLibrary.
  ///
  /// In en, this message translates to:
  /// **'Media Library'**
  String get videoMovieLibrary;

  /// No description provided for @videoMovieLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browse movies, TV series, and anime with filters and categories.'**
  String get videoMovieLibrarySubtitle;

  /// No description provided for @videoAnimeLibrary.
  ///
  /// In en, this message translates to:
  /// **'Anime Library'**
  String get videoAnimeLibrary;

  /// No description provided for @videoAnimeLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Japanese anime organized by series, click to view details, season/episode list and direct playback.'**
  String get videoAnimeLibrarySubtitle;

  /// No description provided for @videoRecentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Content added in the last 30 days is shown here.'**
  String get videoRecentSubtitle;

  /// No description provided for @videoFavoritesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Movies and TV shows starred by the current user are shown here.'**
  String get videoFavoritesSubtitle;

  /// No description provided for @videoSeasonProgress.
  ///
  /// In en, this message translates to:
  /// **'Season {season} - {current}/{total} episodes'**
  String videoSeasonProgress(Object season, Object current, Object total);

  /// No description provided for @videoDefaultVersion.
  ///
  /// In en, this message translates to:
  /// **'Default Version'**
  String get videoDefaultVersion;

  /// No description provided for @videoSelectVersion.
  ///
  /// In en, this message translates to:
  /// **'Select Version'**
  String get videoSelectVersion;

  /// No description provided for @videoPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get videoPlay;

  /// No description provided for @videoFavorited.
  ///
  /// In en, this message translates to:
  /// **'Favorited'**
  String get videoFavorited;

  /// No description provided for @videoFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get videoFavorite;

  /// No description provided for @videoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get videoSubtitle;

  /// No description provided for @videoAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get videoAudio;

  /// No description provided for @videoMovedToRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Media item and source file permanently deleted'**
  String get videoMovedToRecycleBin;

  /// No description provided for @videoDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get videoDelete;

  /// No description provided for @videoDeleteItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete media item?'**
  String get videoDeleteItemTitle;

  /// No description provided for @videoDeleteItemMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" and its source file will be permanently deleted. This cannot be undone.'**
  String videoDeleteItemMessage(Object title);

  /// No description provided for @videoSubtitleManagement.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Management'**
  String get videoSubtitleManagement;

  /// No description provided for @videoNoSubtitles.
  ///
  /// In en, this message translates to:
  /// **'No subtitles available'**
  String get videoNoSubtitles;

  /// No description provided for @videoSubtitleLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load subtitle info'**
  String get videoSubtitleLoadFailed;

  /// No description provided for @videoUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get videoUploading;

  /// No description provided for @videoUploadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upload Subtitle File'**
  String get videoUploadSubtitle;

  /// No description provided for @videoSubtitleUploaded.
  ///
  /// In en, this message translates to:
  /// **'Subtitle uploaded successfully'**
  String get videoSubtitleUploaded;

  /// No description provided for @videoDeleteSubtitleTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Subtitle?'**
  String get videoDeleteSubtitleTitle;

  /// No description provided for @videoDeleteSubtitleMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete subtitle \"{label}\"?'**
  String videoDeleteSubtitleMessage(Object label);

  /// No description provided for @videoSubtitleDeleted.
  ///
  /// In en, this message translates to:
  /// **'Subtitle deleted'**
  String get videoSubtitleDeleted;

  /// No description provided for @videoSubtitleLanguage.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Language'**
  String get videoSubtitleLanguage;

  /// No description provided for @videoSubtitleLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. chi, eng, jpn'**
  String get videoSubtitleLanguageHint;

  /// No description provided for @videoConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get videoConfirm;

  /// No description provided for @videoEmbedded.
  ///
  /// In en, this message translates to:
  /// **'Embedded'**
  String get videoEmbedded;

  /// No description provided for @videoExternal.
  ///
  /// In en, this message translates to:
  /// **'External'**
  String get videoExternal;

  /// No description provided for @videoDeleteSubtitleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete subtitle'**
  String get videoDeleteSubtitleTooltip;

  /// No description provided for @videoAudioManagement.
  ///
  /// In en, this message translates to:
  /// **'Audio Management'**
  String get videoAudioManagement;

  /// No description provided for @videoOriginalAudio.
  ///
  /// In en, this message translates to:
  /// **'Original Audio'**
  String get videoOriginalAudio;

  /// No description provided for @videoUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get videoUnknown;

  /// No description provided for @videoCompatibleAudioCache.
  ///
  /// In en, this message translates to:
  /// **'Compatible Audio Cache'**
  String get videoCompatibleAudioCache;

  /// No description provided for @videoNotExtracted.
  ///
  /// In en, this message translates to:
  /// **'Not extracted'**
  String get videoNotExtracted;

  /// No description provided for @videoLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed'**
  String get videoLoadFailed;

  /// No description provided for @videoAudioIncompatibleNotice.
  ///
  /// In en, this message translates to:
  /// **'Current audio codec {codec} is incompatible with web browsers. After extracting compatible audio, the web player will use cached audio.'**
  String videoAudioIncompatibleNotice(Object codec);

  /// No description provided for @videoCompatibleAudioReady.
  ///
  /// In en, this message translates to:
  /// **'Compatible audio ready'**
  String get videoCompatibleAudioReady;

  /// No description provided for @videoExtracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting...'**
  String get videoExtracting;

  /// No description provided for @videoExtractCompatibleAudio.
  ///
  /// In en, this message translates to:
  /// **'Extract Compatible Audio'**
  String get videoExtractCompatibleAudio;

  /// No description provided for @videoAudioExtractCreated.
  ///
  /// In en, this message translates to:
  /// **'Audio extraction task created'**
  String get videoAudioExtractCreated;

  /// No description provided for @videoCached.
  ///
  /// In en, this message translates to:
  /// **'Cached'**
  String get videoCached;

  /// No description provided for @videoIncompatible.
  ///
  /// In en, this message translates to:
  /// **'Incompatible'**
  String get videoIncompatible;

  /// No description provided for @videoCompatible.
  ///
  /// In en, this message translates to:
  /// **'Compatible'**
  String get videoCompatible;

  /// No description provided for @videoCast.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get videoCast;

  /// No description provided for @videoMediaGallery.
  ///
  /// In en, this message translates to:
  /// **'Media Gallery'**
  String get videoMediaGallery;

  /// No description provided for @videoTrailer.
  ///
  /// In en, this message translates to:
  /// **'Trailer'**
  String get videoTrailer;

  /// No description provided for @videoTechnicalInfo.
  ///
  /// In en, this message translates to:
  /// **'Technical Info'**
  String get videoTechnicalInfo;

  /// No description provided for @videoScrapeStatus.
  ///
  /// In en, this message translates to:
  /// **'Scrape Status'**
  String get videoScrapeStatus;

  /// No description provided for @videoNfoExport.
  ///
  /// In en, this message translates to:
  /// **'NFO Export'**
  String get videoNfoExport;

  /// No description provided for @videoExported.
  ///
  /// In en, this message translates to:
  /// **'Exported'**
  String get videoExported;

  /// No description provided for @videoNotExported.
  ///
  /// In en, this message translates to:
  /// **'Not exported'**
  String get videoNotExported;

  /// No description provided for @videoDetecting.
  ///
  /// In en, this message translates to:
  /// **'Detecting...'**
  String get videoDetecting;

  /// No description provided for @videoContainerFormat.
  ///
  /// In en, this message translates to:
  /// **'Container Format'**
  String get videoContainerFormat;

  /// No description provided for @videoDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get videoDuration;

  /// No description provided for @videoType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get videoType;

  /// No description provided for @videoMatched.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get videoMatched;

  /// No description provided for @videoPendingScrape.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get videoPendingScrape;

  /// No description provided for @videoSectionMovieAdmin.
  ///
  /// In en, this message translates to:
  /// **'Movie management'**
  String get videoSectionMovieAdmin;

  /// No description provided for @videoMovieAdminSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage metadata, scraping and transcoding for your library.'**
  String get videoMovieAdminSubtitle;

  /// No description provided for @videoMovieAdminEmpty.
  ///
  /// In en, this message translates to:
  /// **'No movies match the current filters.'**
  String get videoMovieAdminEmpty;

  /// No description provided for @videoLibraryFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get videoLibraryFilterAll;

  /// No description provided for @videoPreviousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get videoPreviousPage;

  /// No description provided for @videoNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get videoNextPage;

  /// No description provided for @videoTaskProgressDialog.
  ///
  /// In en, this message translates to:
  /// **'Task progress'**
  String get videoTaskProgressDialog;

  /// No description provided for @videoSnackViewProgress.
  ///
  /// In en, this message translates to:
  /// **'View progress'**
  String get videoSnackViewProgress;

  /// No description provided for @videoAdminLibrarySources.
  ///
  /// In en, this message translates to:
  /// **'Library sources'**
  String get videoAdminLibrarySources;

  /// No description provided for @videoSeriesEpisodeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} episodes'**
  String videoSeriesEpisodeCount(Object count);

  /// No description provided for @videoMatchFailed.
  ///
  /// In en, this message translates to:
  /// **'Match Failed'**
  String get videoMatchFailed;

  /// No description provided for @videoManualEdit.
  ///
  /// In en, this message translates to:
  /// **'Manual Edit'**
  String get videoManualEdit;

  /// No description provided for @videoOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get videoOverview;

  /// No description provided for @videoCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get videoCollapse;

  /// No description provided for @videoExpandAll.
  ///
  /// In en, this message translates to:
  /// **'Expand All'**
  String get videoExpandAll;

  /// No description provided for @videoRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Recommendations'**
  String get videoRecommendations;

  /// No description provided for @videoWatchRecord.
  ///
  /// In en, this message translates to:
  /// **'Watch Record'**
  String get videoWatchRecord;

  /// No description provided for @videoWatched.
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get videoWatched;

  /// No description provided for @videoWatching.
  ///
  /// In en, this message translates to:
  /// **'Watching'**
  String get videoWatching;

  /// No description provided for @videoNoWatchRecord.
  ///
  /// In en, this message translates to:
  /// **'No watch record'**
  String get videoNoWatchRecord;

  /// No description provided for @videoLastPlayed.
  ///
  /// In en, this message translates to:
  /// **'Last played: {time}'**
  String videoLastPlayed(Object time);

  /// No description provided for @videoJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get videoJustNow;

  /// No description provided for @videoMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} min ago'**
  String videoMinutesAgo(Object n);

  /// No description provided for @videoHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} hr ago'**
  String videoHoursAgo(Object n);

  /// No description provided for @videoDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} days ago'**
  String videoDaysAgo(Object n);

  /// No description provided for @videoHighRated.
  ///
  /// In en, this message translates to:
  /// **'Top Rated'**
  String get videoHighRated;

  /// No description provided for @videoNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest Releases'**
  String get videoNewest;

  /// No description provided for @videoViewMore.
  ///
  /// In en, this message translates to:
  /// **'View More'**
  String get videoViewMore;

  /// No description provided for @videoContinueSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shows unfinished movies and TV shows, click card to resume playback.'**
  String get videoContinueSubtitle;

  /// No description provided for @videoNoContinueRecord.
  ///
  /// In en, this message translates to:
  /// **'No continue watching records.'**
  String get videoNoContinueRecord;

  /// No description provided for @videoCollectionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Supports user-defined or auto-generated collections, such as movie universes, director filmographies and family collections.'**
  String get videoCollectionsSubtitle;

  /// No description provided for @videoNewCollection.
  ///
  /// In en, this message translates to:
  /// **'New Collection'**
  String get videoNewCollection;

  /// No description provided for @videoAllMedia.
  ///
  /// In en, this message translates to:
  /// **'All Media'**
  String get videoAllMedia;

  /// No description provided for @videoCustomCollection.
  ///
  /// In en, this message translates to:
  /// **'Custom Collection'**
  String get videoCustomCollection;

  /// No description provided for @videoCollectionName.
  ///
  /// In en, this message translates to:
  /// **'Collection Name'**
  String get videoCollectionName;

  /// No description provided for @videoDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get videoDescription;

  /// No description provided for @videoCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get videoCreate;

  /// No description provided for @videoCollectionNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Collection name cannot be empty'**
  String get videoCollectionNameEmpty;

  /// No description provided for @videoCollectionCreated.
  ///
  /// In en, this message translates to:
  /// **'Collection created'**
  String get videoCollectionCreated;

  /// No description provided for @videoCollectionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Collection is empty'**
  String get videoCollectionEmpty;

  /// No description provided for @videoLoadFailedWith.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String videoLoadFailedWith(Object error);

  /// No description provided for @videoRequestTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request timed out, please try again later'**
  String get videoRequestTimeout;

  /// No description provided for @videoConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to backend, please confirm the service is running'**
  String get videoConnectionError;

  /// No description provided for @videoOperationCancelled.
  ///
  /// In en, this message translates to:
  /// **'Operation cancelled'**
  String get videoOperationCancelled;

  /// No description provided for @videoServerError.
  ///
  /// In en, this message translates to:
  /// **'Server response error, please try again later'**
  String get videoServerError;

  /// No description provided for @videoCertificateError.
  ///
  /// In en, this message translates to:
  /// **'Certificate verification failed, please check service configuration'**
  String get videoCertificateError;

  /// No description provided for @videoRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Request failed, please try again later'**
  String get videoRequestFailed;

  /// No description provided for @videoOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed, please try again later'**
  String get videoOperationFailed;

  /// No description provided for @videoProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get videoProcessing;

  /// No description provided for @videoHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Complete playback records with filtering by watched, unwatched and time range.'**
  String get videoHistorySubtitle;

  /// No description provided for @videoClearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get videoClearHistory;

  /// No description provided for @videoNoWatchHistory.
  ///
  /// In en, this message translates to:
  /// **'No watch history.'**
  String get videoNoWatchHistory;

  /// No description provided for @videoMoreFilters.
  ///
  /// In en, this message translates to:
  /// **'More Filters'**
  String get videoMoreFilters;

  /// No description provided for @videoGenre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get videoGenre;

  /// No description provided for @videoYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get videoYear;

  /// No description provided for @videoRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get videoRating;

  /// No description provided for @videoSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get videoSort;

  /// No description provided for @videoClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get videoClear;

  /// No description provided for @videoSortDateAdded.
  ///
  /// In en, this message translates to:
  /// **'Date Added'**
  String get videoSortDateAdded;

  /// No description provided for @videoSortReleaseDate.
  ///
  /// In en, this message translates to:
  /// **'Release Date'**
  String get videoSortReleaseDate;

  /// No description provided for @videoSortTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get videoSortTitle;

  /// No description provided for @videoNoMediaItems.
  ///
  /// In en, this message translates to:
  /// **'No media items here yet.'**
  String get videoNoMediaItems;

  /// No description provided for @videoTaskSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Task Submitted'**
  String get videoTaskSubmitted;

  /// No description provided for @videoRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get videoRetry;

  /// No description provided for @videoSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting'**
  String get videoSubmitting;

  /// No description provided for @videoEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get videoEdit;

  /// No description provided for @videoNfo.
  ///
  /// In en, this message translates to:
  /// **'NFO'**
  String get videoNfo;

  /// No description provided for @videoEpisodeStatus.
  ///
  /// In en, this message translates to:
  /// **'Series - {count} episodes - {status}'**
  String videoEpisodeStatus(Object count, Object status);

  /// No description provided for @videoParse.
  ///
  /// In en, this message translates to:
  /// **'Parse'**
  String get videoParse;

  /// No description provided for @videoTranscode.
  ///
  /// In en, this message translates to:
  /// **'Video Transcode'**
  String get videoTranscode;

  /// No description provided for @videoAudioExtract.
  ///
  /// In en, this message translates to:
  /// **'Audio Extract'**
  String get videoAudioExtract;

  /// No description provided for @videoNoTasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks.'**
  String get videoNoTasks;

  /// No description provided for @videoMetadataScrape.
  ///
  /// In en, this message translates to:
  /// **'Metadata Scrape'**
  String get videoMetadataScrape;

  /// No description provided for @videoMediaScan.
  ///
  /// In en, this message translates to:
  /// **'Media Scan'**
  String get videoMediaScan;

  /// No description provided for @videoQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get videoQueued;

  /// No description provided for @videoRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get videoRunning;

  /// No description provided for @videoCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get videoCompleted;

  /// No description provided for @videoFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get videoFailed;

  /// No description provided for @videoCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get videoCancelled;

  /// No description provided for @videoDeadLetterQueue.
  ///
  /// In en, this message translates to:
  /// **'Dead Letter Queue'**
  String get videoDeadLetterQueue;

  /// No description provided for @videoIncrementalScan.
  ///
  /// In en, this message translates to:
  /// **'Incremental Scan'**
  String get videoIncrementalScan;

  /// No description provided for @videoScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning'**
  String get videoScanning;

  /// No description provided for @videoIncrementalScanComplete.
  ///
  /// In en, this message translates to:
  /// **'Incremental scan complete'**
  String get videoIncrementalScanComplete;

  /// No description provided for @videoFullScan.
  ///
  /// In en, this message translates to:
  /// **'Full Scan'**
  String get videoFullScan;

  /// No description provided for @videoFullScanComplete.
  ///
  /// In en, this message translates to:
  /// **'Full scan complete'**
  String get videoFullScanComplete;

  /// No description provided for @videoNfoPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'NFO - {title}'**
  String videoNfoPreviewTitle(Object title);

  /// No description provided for @videoSeriesLibrary.
  ///
  /// In en, this message translates to:
  /// **'Series Library'**
  String get videoSeriesLibrary;

  /// No description provided for @videoSeriesLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'TV series organized by series, click to view details, season/episode list and direct playback.'**
  String get videoSeriesLibrarySubtitle;

  /// No description provided for @videoNoSeries.
  ///
  /// In en, this message translates to:
  /// **'No series yet.'**
  String get videoNoSeries;

  /// No description provided for @videoNoSeasonInfo.
  ///
  /// In en, this message translates to:
  /// **'No season info'**
  String get videoNoSeasonInfo;

  /// No description provided for @videoEpisodeList.
  ///
  /// In en, this message translates to:
  /// **'Episode List'**
  String get videoEpisodeList;

  /// No description provided for @videoSeasonTab.
  ///
  /// In en, this message translates to:
  /// **'Season {number}'**
  String videoSeasonTab(Object number);

  /// No description provided for @videoNoEpisodesInSeason.
  ///
  /// In en, this message translates to:
  /// **'No episodes in this season'**
  String get videoNoEpisodesInSeason;

  /// No description provided for @videoMediaCenter.
  ///
  /// In en, this message translates to:
  /// **'Media Library'**
  String get videoMediaCenter;

  /// No description provided for @videoSeasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Season {number}'**
  String videoSeasonLabel(Object number);

  /// No description provided for @videoEpisodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Episode {number}'**
  String videoEpisodeLabel(Object number);

  /// No description provided for @videoPreviousEpisode.
  ///
  /// In en, this message translates to:
  /// **'Previous Episode'**
  String get videoPreviousEpisode;

  /// No description provided for @videoNextEpisode.
  ///
  /// In en, this message translates to:
  /// **'Next Episode'**
  String get videoNextEpisode;

  /// No description provided for @videoTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title cannot be empty'**
  String get videoTitleRequired;

  /// No description provided for @videoMetadataSaved.
  ///
  /// In en, this message translates to:
  /// **'Metadata saved'**
  String get videoMetadataSaved;

  /// No description provided for @videoEditMetadataDesc.
  ///
  /// In en, this message translates to:
  /// **'Edit title, overview, poster and backdrop for display. Saving will lock to manual metadata.'**
  String get videoEditMetadataDesc;

  /// No description provided for @videoCoverAssets.
  ///
  /// In en, this message translates to:
  /// **'Cover Assets'**
  String get videoCoverAssets;

  /// No description provided for @videoPosterFileId.
  ///
  /// In en, this message translates to:
  /// **'Poster File ID'**
  String get videoPosterFileId;

  /// No description provided for @videoBackdropFileId.
  ///
  /// In en, this message translates to:
  /// **'Backdrop File ID'**
  String get videoBackdropFileId;

  /// No description provided for @videoCoverIdHint.
  ///
  /// In en, this message translates to:
  /// **'Use file node ID to bind poster and backdrop; saving will immediately update Media Library display resources.'**
  String get videoCoverIdHint;

  /// No description provided for @videoBrandVersion.
  ///
  /// In en, this message translates to:
  /// **'Media Library v1.0'**
  String get videoBrandVersion;

  /// No description provided for @videoMetadataStatus.
  ///
  /// In en, this message translates to:
  /// **'Metadata Status'**
  String get videoMetadataStatus;

  /// No description provided for @videoManualLock.
  ///
  /// In en, this message translates to:
  /// **'Manual Lock'**
  String get videoManualLock;

  /// No description provided for @videoPendingRecognition.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get videoPendingRecognition;

  /// No description provided for @videoRecognitionFailed.
  ///
  /// In en, this message translates to:
  /// **'Recognition Failed'**
  String get videoRecognitionFailed;

  /// No description provided for @videoOriginalTitle.
  ///
  /// In en, this message translates to:
  /// **'Original Title'**
  String get videoOriginalTitle;

  /// No description provided for @videoReleaseDate.
  ///
  /// In en, this message translates to:
  /// **'Release Date'**
  String get videoReleaseDate;

  /// No description provided for @videoRuntimeMinutes.
  ///
  /// In en, this message translates to:
  /// **'Runtime (minutes)'**
  String get videoRuntimeMinutes;

  /// No description provided for @videoOverviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get videoOverviewLabel;

  /// No description provided for @videoSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get videoSaveChanges;

  /// No description provided for @videoBackdrop.
  ///
  /// In en, this message translates to:
  /// **'Backdrop'**
  String get videoBackdrop;

  /// No description provided for @videoFillScreen.
  ///
  /// In en, this message translates to:
  /// **'Fill Screen'**
  String get videoFillScreen;

  /// No description provided for @videoOriginalAspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Original Aspect Ratio'**
  String get videoOriginalAspectRatio;

  /// No description provided for @videoCompatibleAudioNotice.
  ///
  /// In en, this message translates to:
  /// **'Using compatible audio stream. Tap the audio button at the bottom to switch audio source.'**
  String get videoCompatibleAudioNotice;

  /// No description provided for @videoGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get videoGotIt;

  /// No description provided for @videoSubtitleTrack.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Track'**
  String get videoSubtitleTrack;

  /// No description provided for @videoNoSubtitlesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No subtitles available for this video'**
  String get videoNoSubtitlesAvailable;

  /// No description provided for @videoDisableSubtitles.
  ///
  /// In en, this message translates to:
  /// **'Disable Subtitles'**
  String get videoDisableSubtitles;

  /// No description provided for @videoAudioTrack.
  ///
  /// In en, this message translates to:
  /// **'Audio Track'**
  String get videoAudioTrack;

  /// No description provided for @videoCompatibleAudioAac.
  ///
  /// In en, this message translates to:
  /// **'Compatible Audio (AAC Cache)'**
  String get videoCompatibleAudioAac;

  /// No description provided for @videoCompatibleAudioDesc.
  ///
  /// In en, this message translates to:
  /// **'Pre-processed AAC audio stream, compatible with all web browsers'**
  String get videoCompatibleAudioDesc;

  /// No description provided for @videoOriginalAudioLabel.
  ///
  /// In en, this message translates to:
  /// **'Original Audio ({codec})'**
  String videoOriginalAudioLabel(Object codec);

  /// No description provided for @videoOriginalAudioDesc.
  ///
  /// In en, this message translates to:
  /// **'Real-time transcoded original audio, may require more processing time'**
  String get videoOriginalAudioDesc;

  /// No description provided for @videoPlaybackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback Speed'**
  String get videoPlaybackSpeed;

  /// No description provided for @videoAspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Aspect Ratio'**
  String get videoAspectRatio;

  /// No description provided for @videoPlaybackSettings.
  ///
  /// In en, this message translates to:
  /// **'Playback Settings'**
  String get videoPlaybackSettings;

  /// No description provided for @videoSubtitlesEnabled.
  ///
  /// In en, this message translates to:
  /// **'Subtitles Enabled'**
  String get videoSubtitlesEnabled;

  /// No description provided for @videoSubtitlesOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get videoSubtitlesOff;

  /// No description provided for @videoSubtitlesOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get videoSubtitlesOn;

  /// No description provided for @videoPlaybackInfo.
  ///
  /// In en, this message translates to:
  /// **'Playback Info'**
  String get videoPlaybackInfo;

  /// No description provided for @videoInfoMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get videoInfoMode;

  /// No description provided for @videoInfoContainer.
  ///
  /// In en, this message translates to:
  /// **'Container'**
  String get videoInfoContainer;

  /// No description provided for @videoInfoVideoCodec.
  ///
  /// In en, this message translates to:
  /// **'Video Codec'**
  String get videoInfoVideoCodec;

  /// No description provided for @videoInfoAudioCodec.
  ///
  /// In en, this message translates to:
  /// **'Audio Codec'**
  String get videoInfoAudioCodec;

  /// No description provided for @videoInfoAudioSource.
  ///
  /// In en, this message translates to:
  /// **'Audio Source'**
  String get videoInfoAudioSource;

  /// No description provided for @videoInfoSubtitleCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks'**
  String videoInfoSubtitleCount(Object count);

  /// No description provided for @videoInfoVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get videoInfoVolume;

  /// No description provided for @videoBackToDetail.
  ///
  /// In en, this message translates to:
  /// **'Back to Detail'**
  String get videoBackToDetail;

  /// No description provided for @videoStatusSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Current video is {container}/{video}/{audio}, browser does not support direct playback, streaming via server transcoding. Seek precision is limited, use desktop client for precise seeking.'**
  String videoStatusSubtitle(Object container, Object video, Object audio);

  /// No description provided for @videoLastPlayedTime.
  ///
  /// In en, this message translates to:
  /// **'Last played: {time}'**
  String videoLastPlayedTime(Object time);

  /// No description provided for @photosLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get photosLoading;

  /// No description provided for @photoThumbnailLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading thumbnail'**
  String get photoThumbnailLoading;

  /// No description provided for @photosTaskFailed.
  ///
  /// In en, this message translates to:
  /// **'Task failed'**
  String get photosTaskFailed;

  /// No description provided for @photosTaskStatusRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to refresh task status. Retrying automatically'**
  String get photosTaskStatusRefreshFailed;

  /// No description provided for @photosProcessedItems.
  ///
  /// In en, this message translates to:
  /// **'{count} items completed'**
  String photosProcessedItems(Object count);

  /// No description provided for @photosDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get photosDone;

  /// No description provided for @photosRunInBackground.
  ///
  /// In en, this message translates to:
  /// **'Run in background'**
  String get photosRunInBackground;

  /// No description provided for @photosSlideshow3s.
  ///
  /// In en, this message translates to:
  /// **'3s'**
  String get photosSlideshow3s;

  /// No description provided for @photosSlideshow5s.
  ///
  /// In en, this message translates to:
  /// **'5s'**
  String get photosSlideshow5s;

  /// No description provided for @photosSlideshow10s.
  ///
  /// In en, this message translates to:
  /// **'10s'**
  String get photosSlideshow10s;

  /// No description provided for @photosTabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get photosTabHome;

  /// No description provided for @photosTabFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get photosTabFavorites;

  /// No description provided for @photosTabTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get photosTabTimeline;

  /// No description provided for @photosTabAlbums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get photosTabAlbums;

  /// No description provided for @photosTabGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get photosTabGroups;

  /// No description provided for @photosTabGraph.
  ///
  /// In en, this message translates to:
  /// **'Graph'**
  String get photosTabGraph;

  /// No description provided for @photosSurfaceLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get photosSurfaceLibrary;

  /// No description provided for @photosSurfaceExplore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get photosSurfaceExplore;

  /// No description provided for @photosGraphKindAlbum.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get photosGraphKindAlbum;

  /// No description provided for @photosGraphKindTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get photosGraphKindTime;

  /// No description provided for @photosGraphKindLocation.
  ///
  /// In en, this message translates to:
  /// **'Places'**
  String get photosGraphKindLocation;

  /// No description provided for @photosGraphEmpty.
  ///
  /// In en, this message translates to:
  /// **'No photo relationships are available yet.'**
  String get photosGraphEmpty;

  /// No description provided for @photosGraphViewPhoto.
  ///
  /// In en, this message translates to:
  /// **'View photo'**
  String get photosGraphViewPhoto;

  /// No description provided for @photosGraphPhotoCount.
  ///
  /// In en, this message translates to:
  /// **'{count} photos'**
  String photosGraphPhotoCount(Object count);

  /// No description provided for @photosGroupByDate.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get photosGroupByDate;

  /// No description provided for @photosGroupByLocation.
  ///
  /// In en, this message translates to:
  /// **'Places'**
  String get photosGroupByLocation;

  /// No description provided for @photosGroupByFormat.
  ///
  /// In en, this message translates to:
  /// **'Formats'**
  String get photosGroupByFormat;

  /// No description provided for @photosGroupByTag.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get photosGroupByTag;

  /// No description provided for @photosEditTypeRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get photosEditTypeRotate;

  /// No description provided for @photosEditTypeCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get photosEditTypeCrop;

  /// No description provided for @photosEditTypeBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get photosEditTypeBrightness;

  /// No description provided for @photosEditTypeContrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get photosEditTypeContrast;

  /// No description provided for @photosEditTypeFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get photosEditTypeFilter;

  /// No description provided for @photosImportCompletedNotVisible.
  ///
  /// In en, this message translates to:
  /// **'Import finished, but the photos are not visible in this list yet. Refresh later.'**
  String get photosImportCompletedNotVisible;

  /// No description provided for @photosImportStillProcessing.
  ///
  /// In en, this message translates to:
  /// **'Photo import is still processing. Refresh the page later.'**
  String get photosImportStillProcessing;

  /// No description provided for @photosImportBackendFailed.
  ///
  /// In en, this message translates to:
  /// **'Photo import failed in the background. Check the task center for details.'**
  String get photosImportBackendFailed;

  /// No description provided for @photosSharedPoweredBy.
  ///
  /// In en, this message translates to:
  /// **'Powered by OmniNest'**
  String get photosSharedPoweredBy;

  /// No description provided for @photosTabMemories.
  ///
  /// In en, this message translates to:
  /// **'Memories'**
  String get photosTabMemories;

  /// No description provided for @photosClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get photosClose;

  /// No description provided for @photosDeletePhotoTitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently Delete Photo'**
  String get photosDeletePhotoTitle;

  /// No description provided for @photosDeletePhotoConfirm.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" and its source file will be permanently deleted. This cannot be undone.'**
  String photosDeletePhotoConfirm(Object title);

  /// No description provided for @photosCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get photosCancel;

  /// No description provided for @photosDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get photosDelete;

  /// No description provided for @photosDeletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete Permanently'**
  String get photosDeletePermanently;

  /// No description provided for @photosDeletedPhoto.
  ///
  /// In en, this message translates to:
  /// **'Permanently deleted \"{title}\" and its source file'**
  String photosDeletedPhoto(Object title);

  /// No description provided for @photosDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed, please try again later'**
  String get photosDeleteFailed;

  /// No description provided for @photosDeleteAlbumTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Album'**
  String get photosDeleteAlbumTitle;

  /// No description provided for @photosDeleteAlbumConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete album \"{name}\"? Photos in the album will not be deleted.'**
  String photosDeleteAlbumConfirm(Object name);

  /// No description provided for @photosDeletedAlbum.
  ///
  /// In en, this message translates to:
  /// **'Deleted album \"{name}\"'**
  String photosDeletedAlbum(Object name);

  /// No description provided for @photosNewAlbum.
  ///
  /// In en, this message translates to:
  /// **'New Album'**
  String get photosNewAlbum;

  /// No description provided for @photosAlbumName.
  ///
  /// In en, this message translates to:
  /// **'Album Name'**
  String get photosAlbumName;

  /// No description provided for @photosAlbumNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Travel Photos'**
  String get photosAlbumNameHint;

  /// No description provided for @photosAlbumDescription.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get photosAlbumDescription;

  /// No description provided for @photosAlbumDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Briefly describe this album'**
  String get photosAlbumDescriptionHint;

  /// No description provided for @photosAlbumCreated.
  ///
  /// In en, this message translates to:
  /// **'Album \"{name}\" created'**
  String photosAlbumCreated(Object name);

  /// No description provided for @photosCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Creation failed, please try again later'**
  String get photosCreateFailed;

  /// No description provided for @photosCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get photosCreate;

  /// No description provided for @photosBackToPortal.
  ///
  /// In en, this message translates to:
  /// **'Back to Portal'**
  String get photosBackToPortal;

  /// No description provided for @photosSearchPhotos.
  ///
  /// In en, this message translates to:
  /// **'Search Photos'**
  String get photosSearchPhotos;

  /// No description provided for @photosSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search photos...'**
  String get photosSearchHint;

  /// No description provided for @photosClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get photosClear;

  /// No description provided for @photosSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get photosSearch;

  /// No description provided for @photosAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get photosAll;

  /// No description provided for @photosNoFavorites.
  ///
  /// In en, this message translates to:
  /// **'No favorite photos yet'**
  String get photosNoFavorites;

  /// No description provided for @photosNoFavoritesHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the favorite button in photo details to add favorites.'**
  String get photosNoFavoritesHint;

  /// No description provided for @photosRecentPhotos.
  ///
  /// In en, this message translates to:
  /// **'Recent Photos'**
  String get photosRecentPhotos;

  /// No description provided for @photosNoPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos yet'**
  String get photosNoPhotos;

  /// No description provided for @photosNoPhotosHint.
  ///
  /// In en, this message translates to:
  /// **'Photos will appear here automatically after uploading.'**
  String get photosNoPhotosHint;

  /// No description provided for @photosAlbums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get photosAlbums;

  /// No description provided for @photosNoAlbums.
  ///
  /// In en, this message translates to:
  /// **'No albums yet'**
  String get photosNoAlbums;

  /// No description provided for @photosAlbumPhotoCount.
  ///
  /// In en, this message translates to:
  /// **'{count}'**
  String photosAlbumPhotoCount(Object count);

  /// No description provided for @photosViewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get photosViewAll;

  /// No description provided for @photosLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more ({loaded} / {total} loaded)'**
  String photosLoadMore(Object loaded, Object total);

  /// No description provided for @photosSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String photosSelectedCount(Object count);

  /// No description provided for @photosTag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get photosTag;

  /// No description provided for @photosMove.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get photosMove;

  /// No description provided for @photosExportZip.
  ///
  /// In en, this message translates to:
  /// **'Export ZIP'**
  String get photosExportZip;

  /// No description provided for @photosUpdateDate.
  ///
  /// In en, this message translates to:
  /// **'Update date taken'**
  String get photosUpdateDate;

  /// No description provided for @photosSaveZip.
  ///
  /// In en, this message translates to:
  /// **'Save ZIP'**
  String get photosSaveZip;

  /// No description provided for @photosDownloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Download handed off to the browser'**
  String get photosDownloadStarted;

  /// No description provided for @photosArchiveSaved.
  ///
  /// In en, this message translates to:
  /// **'ZIP saved to {path}'**
  String photosArchiveSaved(Object path);

  /// No description provided for @photosArchiveDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'ZIP download failed. Choose the same path to resume.'**
  String get photosArchiveDownloadFailed;

  /// No description provided for @photosDownloadPhoto.
  ///
  /// In en, this message translates to:
  /// **'Download original'**
  String get photosDownloadPhoto;

  /// No description provided for @photosDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed, please try again later'**
  String get photosDownloadFailed;

  /// No description provided for @photosDownloadSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String photosDownloadSaved(Object path);

  /// No description provided for @photosDownloadSourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Original file is unavailable for download'**
  String get photosDownloadSourceUnavailable;

  /// No description provided for @photosSlideshowBadge.
  ///
  /// In en, this message translates to:
  /// **'Slideshow · {current} / {total}'**
  String photosSlideshowBadge(int current, int total);

  /// No description provided for @photosBatchAddTag.
  ///
  /// In en, this message translates to:
  /// **'Batch Add Tags'**
  String get photosBatchAddTag;

  /// No description provided for @photosTagName.
  ///
  /// In en, this message translates to:
  /// **'Tag Name'**
  String get photosTagName;

  /// No description provided for @photosTagNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Travel'**
  String get photosTagNameHint;

  /// No description provided for @photosAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get photosAdd;

  /// No description provided for @photosTaskCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Task creation failed'**
  String get photosTaskCreateFailed;

  /// No description provided for @photosSelectAlbum.
  ///
  /// In en, this message translates to:
  /// **'Select Album'**
  String get photosSelectAlbum;

  /// No description provided for @photosBatchDelete.
  ///
  /// In en, this message translates to:
  /// **'Batch Delete'**
  String get photosBatchDelete;

  /// No description provided for @photosBatchDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'The selected {count} photos and their source files will be permanently deleted. This cannot be undone.'**
  String photosBatchDeleteConfirm(Object count);

  /// No description provided for @photosBatchDeleted.
  ///
  /// In en, this message translates to:
  /// **'Permanently deleted {count} photos and their source files'**
  String photosBatchDeleted(Object count);

  /// No description provided for @photosDeselect.
  ///
  /// In en, this message translates to:
  /// **'Deselect'**
  String get photosDeselect;

  /// No description provided for @photosNoTimelineData.
  ///
  /// In en, this message translates to:
  /// **'No timeline data'**
  String get photosNoTimelineData;

  /// No description provided for @photosNoTimelineHint.
  ///
  /// In en, this message translates to:
  /// **'Photos need capture time info to display timeline'**
  String get photosNoTimelineHint;

  /// No description provided for @photosYear.
  ///
  /// In en, this message translates to:
  /// **'{year}'**
  String photosYear(Object year);

  /// No description provided for @photosOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed, please try again later'**
  String get photosOperationFailed;

  /// No description provided for @photosImageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Image load failed'**
  String get photosImageLoadFailed;

  /// No description provided for @photosBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get photosBack;

  /// No description provided for @photosUnfavorite.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite'**
  String get photosUnfavorite;

  /// No description provided for @photosFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get photosFavorite;

  /// No description provided for @photosHideInfo.
  ///
  /// In en, this message translates to:
  /// **'Hide Info'**
  String get photosHideInfo;

  /// No description provided for @photosShowInfo.
  ///
  /// In en, this message translates to:
  /// **'Show Info'**
  String get photosShowInfo;

  /// No description provided for @photosEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get photosEdit;

  /// No description provided for @photosSlideshow.
  ///
  /// In en, this message translates to:
  /// **'Slideshow'**
  String get photosSlideshow;

  /// No description provided for @photosSlideshowUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No consecutive photos to play here'**
  String get photosSlideshowUnavailable;

  /// No description provided for @photosAddToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Add to Album'**
  String get photosAddToAlbum;

  /// No description provided for @photosPhotoInfo.
  ///
  /// In en, this message translates to:
  /// **'Photo Info'**
  String get photosPhotoInfo;

  /// No description provided for @photosBasicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic Info'**
  String get photosBasicInfo;

  /// No description provided for @photosFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get photosFormat;

  /// No description provided for @photosFileSize.
  ///
  /// In en, this message translates to:
  /// **'File Size'**
  String get photosFileSize;

  /// No description provided for @photosResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get photosResolution;

  /// No description provided for @photosDateTaken.
  ///
  /// In en, this message translates to:
  /// **'Date Taken'**
  String get photosDateTaken;

  /// No description provided for @photosCameraInfo.
  ///
  /// In en, this message translates to:
  /// **'Camera Info'**
  String get photosCameraInfo;

  /// No description provided for @photosBrand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get photosBrand;

  /// No description provided for @photosModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get photosModel;

  /// No description provided for @photosLens.
  ///
  /// In en, this message translates to:
  /// **'Lens'**
  String get photosLens;

  /// No description provided for @photosAperture.
  ///
  /// In en, this message translates to:
  /// **'Aperture'**
  String get photosAperture;

  /// No description provided for @photosShutterSpeed.
  ///
  /// In en, this message translates to:
  /// **'Shutter Speed'**
  String get photosShutterSpeed;

  /// No description provided for @photosFocalLength.
  ///
  /// In en, this message translates to:
  /// **'Focal Length'**
  String get photosFocalLength;

  /// No description provided for @photosShootingParams.
  ///
  /// In en, this message translates to:
  /// **'Shooting Parameters'**
  String get photosShootingParams;

  /// No description provided for @photosFlash.
  ///
  /// In en, this message translates to:
  /// **'Flash'**
  String get photosFlash;

  /// No description provided for @photosWhiteBalance.
  ///
  /// In en, this message translates to:
  /// **'White Balance'**
  String get photosWhiteBalance;

  /// No description provided for @photosMeteringMode.
  ///
  /// In en, this message translates to:
  /// **'Metering Mode'**
  String get photosMeteringMode;

  /// No description provided for @photosLocationInfo.
  ///
  /// In en, this message translates to:
  /// **'Location Info'**
  String get photosLocationInfo;

  /// No description provided for @photosPlace.
  ///
  /// In en, this message translates to:
  /// **'Place'**
  String get photosPlace;

  /// No description provided for @photosCoordinates.
  ///
  /// In en, this message translates to:
  /// **'Coordinates'**
  String get photosCoordinates;

  /// No description provided for @photosAIRecognition.
  ///
  /// In en, this message translates to:
  /// **'Image Analysis'**
  String get photosAIRecognition;

  /// No description provided for @photosAnalysisSubject.
  ///
  /// In en, this message translates to:
  /// **'Subjects'**
  String get photosAnalysisSubject;

  /// No description provided for @photosAnalysisScene.
  ///
  /// In en, this message translates to:
  /// **'Scenes'**
  String get photosAnalysisScene;

  /// No description provided for @photosAnalysisStyle.
  ///
  /// In en, this message translates to:
  /// **'Styles'**
  String get photosAnalysisStyle;

  /// No description provided for @photosAiCategoryPerson.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get photosAiCategoryPerson;

  /// No description provided for @photosAiCategoryCat.
  ///
  /// In en, this message translates to:
  /// **'Cats'**
  String get photosAiCategoryCat;

  /// No description provided for @photosAiCategoryDog.
  ///
  /// In en, this message translates to:
  /// **'Dogs'**
  String get photosAiCategoryDog;

  /// No description provided for @photosAiCategoryAnimal.
  ///
  /// In en, this message translates to:
  /// **'Animals'**
  String get photosAiCategoryAnimal;

  /// No description provided for @photosAiCategoryNature.
  ///
  /// In en, this message translates to:
  /// **'Nature'**
  String get photosAiCategoryNature;

  /// No description provided for @photosAiCategoryArchitecture.
  ///
  /// In en, this message translates to:
  /// **'Architecture'**
  String get photosAiCategoryArchitecture;

  /// No description provided for @photosAiCategoryIndoor.
  ///
  /// In en, this message translates to:
  /// **'Indoor'**
  String get photosAiCategoryIndoor;

  /// No description provided for @photosAiCategoryFood.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get photosAiCategoryFood;

  /// No description provided for @photosAiCategoryVehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicles'**
  String get photosAiCategoryVehicle;

  /// No description provided for @photosAiCategoryPlant.
  ///
  /// In en, this message translates to:
  /// **'Plants'**
  String get photosAiCategoryPlant;

  /// No description provided for @photosAiCategorySport.
  ///
  /// In en, this message translates to:
  /// **'Sports'**
  String get photosAiCategorySport;

  /// No description provided for @photosAiCategoryNight.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get photosAiCategoryNight;

  /// No description provided for @photosAiCategoryArt.
  ///
  /// In en, this message translates to:
  /// **'Art'**
  String get photosAiCategoryArt;

  /// No description provided for @photosAiCategoryDocument.
  ///
  /// In en, this message translates to:
  /// **'Documents and screens'**
  String get photosAiCategoryDocument;

  /// No description provided for @photosDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get photosDescription;

  /// No description provided for @photosDeleteTagFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete tag'**
  String get photosDeleteTagFailed;

  /// No description provided for @photosAddTag.
  ///
  /// In en, this message translates to:
  /// **'Add Tag'**
  String get photosAddTag;

  /// No description provided for @photosTagNameInput.
  ///
  /// In en, this message translates to:
  /// **'Enter tag name'**
  String get photosTagNameInput;

  /// No description provided for @photosAddTagFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to add tag'**
  String get photosAddTagFailed;

  /// No description provided for @photosNoAlbumsCreateFirst.
  ///
  /// In en, this message translates to:
  /// **'No albums yet, please create one first'**
  String get photosNoAlbumsCreateFirst;

  /// No description provided for @photosAddedToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Added to album'**
  String get photosAddedToAlbum;

  /// No description provided for @photosAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to add, please try again later'**
  String get photosAddFailed;

  /// No description provided for @photosNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes made'**
  String get photosNoChanges;

  /// No description provided for @photosEditSaved.
  ///
  /// In en, this message translates to:
  /// **'Edit saved'**
  String get photosEditSaved;

  /// No description provided for @photosSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed, please try again later'**
  String get photosSaveFailed;

  /// No description provided for @photosEditorCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get photosEditorCancel;

  /// No description provided for @photosEditorUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get photosEditorUndo;

  /// No description provided for @photosEditorRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get photosEditorRedo;

  /// No description provided for @photosEditorDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get photosEditorDone;

  /// No description provided for @photosEditorRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get photosEditorRemove;

  /// No description provided for @photosEditorBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get photosEditorBack;

  /// No description provided for @photosEditorMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get photosEditorMore;

  /// No description provided for @photosEditorDoneLoadingMsg.
  ///
  /// In en, this message translates to:
  /// **'Changes are being applied'**
  String get photosEditorDoneLoadingMsg;

  /// No description provided for @photosEditorImportStateHistoryMsg.
  ///
  /// In en, this message translates to:
  /// **'Initialize Editor'**
  String get photosEditorImportStateHistoryMsg;

  /// No description provided for @photosEditorLoadingDialogMsg.
  ///
  /// In en, this message translates to:
  /// **'Please wait...'**
  String get photosEditorLoadingDialogMsg;

  /// No description provided for @photosEditorCloseWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Close Image Editor?'**
  String get photosEditorCloseWarningTitle;

  /// No description provided for @photosEditorCloseWarningMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to close the Image Editor? Your changes will not be saved.'**
  String get photosEditorCloseWarningMessage;

  /// No description provided for @photosEditorCloseWarningConfirm.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get photosEditorCloseWarningConfirm;

  /// No description provided for @photosEditorPaintBottomNav.
  ///
  /// In en, this message translates to:
  /// **'Paint'**
  String get photosEditorPaintBottomNav;

  /// No description provided for @photosEditorPaintMoveAndZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get photosEditorPaintMoveAndZoom;

  /// No description provided for @photosEditorPaintFreestyle.
  ///
  /// In en, this message translates to:
  /// **'Freestyle'**
  String get photosEditorPaintFreestyle;

  /// No description provided for @photosEditorPaintArrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get photosEditorPaintArrow;

  /// No description provided for @photosEditorPaintLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get photosEditorPaintLine;

  /// No description provided for @photosEditorPaintRectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get photosEditorPaintRectangle;

  /// No description provided for @photosEditorPaintCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get photosEditorPaintCircle;

  /// No description provided for @photosEditorPaintDashLine.
  ///
  /// In en, this message translates to:
  /// **'Dash line'**
  String get photosEditorPaintDashLine;

  /// No description provided for @photosEditorPaintDashDotLine.
  ///
  /// In en, this message translates to:
  /// **'Dash-dot line'**
  String get photosEditorPaintDashDotLine;

  /// No description provided for @photosEditorPaintHexagon.
  ///
  /// In en, this message translates to:
  /// **'Hexagon'**
  String get photosEditorPaintHexagon;

  /// No description provided for @photosEditorPaintPolygon.
  ///
  /// In en, this message translates to:
  /// **'Polygon'**
  String get photosEditorPaintPolygon;

  /// No description provided for @photosEditorPaintBlur.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get photosEditorPaintBlur;

  /// No description provided for @photosEditorPaintPixelate.
  ///
  /// In en, this message translates to:
  /// **'Pixelate'**
  String get photosEditorPaintPixelate;

  /// No description provided for @photosEditorLineWidth.
  ///
  /// In en, this message translates to:
  /// **'Line width'**
  String get photosEditorLineWidth;

  /// No description provided for @photosEditorEraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get photosEditorEraser;

  /// No description provided for @photosEditorToggleFill.
  ///
  /// In en, this message translates to:
  /// **'Toggle fill'**
  String get photosEditorToggleFill;

  /// No description provided for @photosEditorChangeOpacity.
  ///
  /// In en, this message translates to:
  /// **'Change opacity'**
  String get photosEditorChangeOpacity;

  /// No description provided for @photosEditorOpacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get photosEditorOpacity;

  /// No description provided for @photosEditorColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get photosEditorColor;

  /// No description provided for @photosEditorStrokeWidth.
  ///
  /// In en, this message translates to:
  /// **'Stroke Width'**
  String get photosEditorStrokeWidth;

  /// No description provided for @photosEditorFill.
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get photosEditorFill;

  /// No description provided for @photosEditorTextInputHint.
  ///
  /// In en, this message translates to:
  /// **'Enter text'**
  String get photosEditorTextInputHint;

  /// No description provided for @photosEditorTextBottomNav.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get photosEditorTextBottomNav;

  /// No description provided for @photosEditorTextAlign.
  ///
  /// In en, this message translates to:
  /// **'Align text'**
  String get photosEditorTextAlign;

  /// No description provided for @photosEditorFontScale.
  ///
  /// In en, this message translates to:
  /// **'Font scale'**
  String get photosEditorFontScale;

  /// No description provided for @photosEditorTextBackgroundMode.
  ///
  /// In en, this message translates to:
  /// **'Background mode'**
  String get photosEditorTextBackgroundMode;

  /// No description provided for @photosEditorCropBottomNav.
  ///
  /// In en, this message translates to:
  /// **'Crop/ Rotate'**
  String get photosEditorCropBottomNav;

  /// No description provided for @photosEditorCropRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get photosEditorCropRotate;

  /// No description provided for @photosEditorCropFlip.
  ///
  /// In en, this message translates to:
  /// **'Flip'**
  String get photosEditorCropFlip;

  /// No description provided for @photosEditorCropTilt.
  ///
  /// In en, this message translates to:
  /// **'Tilt'**
  String get photosEditorCropTilt;

  /// No description provided for @photosEditorCropTiltHorizontal.
  ///
  /// In en, this message translates to:
  /// **'Horizontal'**
  String get photosEditorCropTiltHorizontal;

  /// No description provided for @photosEditorCropTiltVertical.
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get photosEditorCropTiltVertical;

  /// No description provided for @photosEditorCropRatio.
  ///
  /// In en, this message translates to:
  /// **'Ratio'**
  String get photosEditorCropRatio;

  /// No description provided for @photosEditorCropReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get photosEditorCropReset;

  /// No description provided for @photosEditorRatioFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get photosEditorRatioFree;

  /// No description provided for @photosEditorRatioOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get photosEditorRatioOriginal;

  /// No description provided for @photosEditorTuneBottomNav.
  ///
  /// In en, this message translates to:
  /// **'Tune'**
  String get photosEditorTuneBottomNav;

  /// No description provided for @photosEditorTuneBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get photosEditorTuneBrightness;

  /// No description provided for @photosEditorTuneContrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get photosEditorTuneContrast;

  /// No description provided for @photosEditorTuneSaturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get photosEditorTuneSaturation;

  /// No description provided for @photosEditorTuneExposure.
  ///
  /// In en, this message translates to:
  /// **'Exposure'**
  String get photosEditorTuneExposure;

  /// No description provided for @photosEditorTuneHue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get photosEditorTuneHue;

  /// No description provided for @photosEditorTuneTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get photosEditorTuneTemperature;

  /// No description provided for @photosEditorTuneFade.
  ///
  /// In en, this message translates to:
  /// **'Fade'**
  String get photosEditorTuneFade;

  /// No description provided for @photosEditorTuneTint.
  ///
  /// In en, this message translates to:
  /// **'Tint'**
  String get photosEditorTuneTint;

  /// No description provided for @photosEditorFilterBottomNav.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get photosEditorFilterBottomNav;

  /// No description provided for @photosEditorFilterNone.
  ///
  /// In en, this message translates to:
  /// **'No Filter'**
  String get photosEditorFilterNone;

  /// No description provided for @photosEditorBlurBottomNav.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get photosEditorBlurBottomNav;

  /// No description provided for @photosEditorEmojiBottomNav.
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get photosEditorEmojiBottomNav;

  /// No description provided for @photosEditorEmojiSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get photosEditorEmojiSearch;

  /// No description provided for @photosEditorEmojiRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get photosEditorEmojiRecent;

  /// No description provided for @photosEditorEmojiSmileys.
  ///
  /// In en, this message translates to:
  /// **'Smileys & People'**
  String get photosEditorEmojiSmileys;

  /// No description provided for @photosEditorEmojiAnimals.
  ///
  /// In en, this message translates to:
  /// **'Animals & Nature'**
  String get photosEditorEmojiAnimals;

  /// No description provided for @photosEditorEmojiFood.
  ///
  /// In en, this message translates to:
  /// **'Food & Drink'**
  String get photosEditorEmojiFood;

  /// No description provided for @photosEditorEmojiActivities.
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get photosEditorEmojiActivities;

  /// No description provided for @photosEditorEmojiTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel & Places'**
  String get photosEditorEmojiTravel;

  /// No description provided for @photosEditorEmojiObjects.
  ///
  /// In en, this message translates to:
  /// **'Objects'**
  String get photosEditorEmojiObjects;

  /// No description provided for @photosEditorEmojiSymbols.
  ///
  /// In en, this message translates to:
  /// **'Symbols'**
  String get photosEditorEmojiSymbols;

  /// No description provided for @photosEditorEmojiFlags.
  ///
  /// In en, this message translates to:
  /// **'Flags'**
  String get photosEditorEmojiFlags;

  /// No description provided for @photosEditorStickerBottomNav.
  ///
  /// In en, this message translates to:
  /// **'Stickers'**
  String get photosEditorStickerBottomNav;

  /// No description provided for @photosEditorLayerEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get photosEditorLayerEdit;

  /// No description provided for @photosEditorLayerRotateScale.
  ///
  /// In en, this message translates to:
  /// **'Rotate and Scale'**
  String get photosEditorLayerRotateScale;

  /// No description provided for @photosRolledBack.
  ///
  /// In en, this message translates to:
  /// **'Rolled back to specified version'**
  String get photosRolledBack;

  /// No description provided for @photosRollbackFailed.
  ///
  /// In en, this message translates to:
  /// **'Rollback failed'**
  String get photosRollbackFailed;

  /// No description provided for @photosEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit - {title}'**
  String photosEditTitle(Object title);

  /// No description provided for @photosVersionHistory.
  ///
  /// In en, this message translates to:
  /// **'Version History'**
  String get photosVersionHistory;

  /// No description provided for @photosSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get photosSave;

  /// No description provided for @photosCropDragHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to select crop area'**
  String get photosCropDragHint;

  /// No description provided for @photosConfirmCrop.
  ///
  /// In en, this message translates to:
  /// **'Confirm Crop'**
  String get photosConfirmCrop;

  /// No description provided for @photosEditVersionHistory.
  ///
  /// In en, this message translates to:
  /// **'Edit Version History'**
  String get photosEditVersionHistory;

  /// No description provided for @photosNoEditHistory.
  ///
  /// In en, this message translates to:
  /// **'No edit history'**
  String get photosNoEditHistory;

  /// No description provided for @photosRollback.
  ///
  /// In en, this message translates to:
  /// **'Rollback'**
  String get photosRollback;

  /// No description provided for @photosConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get photosConfirm;

  /// No description provided for @photosPhotoCount.
  ///
  /// In en, this message translates to:
  /// **'{count} photos'**
  String photosPhotoCount(Object count);

  /// No description provided for @photosSharedAlbumAccessError.
  ///
  /// In en, this message translates to:
  /// **'Cannot access shared album: {error}'**
  String photosSharedAlbumAccessError(Object error);

  /// No description provided for @photosSharedAlbumPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'This album requires password access'**
  String get photosSharedAlbumPasswordRequired;

  /// No description provided for @photosSharedAlbumPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter share password to view album content'**
  String get photosSharedAlbumPasswordHint;

  /// No description provided for @photosEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get photosEnterPassword;

  /// No description provided for @photosAccess.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get photosAccess;

  /// No description provided for @photosAlbumEmpty.
  ///
  /// In en, this message translates to:
  /// **'No photos in this album'**
  String get photosAlbumEmpty;

  /// No description provided for @photosAddPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add photos'**
  String get photosAddPhotos;

  /// No description provided for @photosPickerAddCount.
  ///
  /// In en, this message translates to:
  /// **'Add {count}'**
  String photosPickerAddCount(Object count);

  /// No description provided for @photosPickerAddSuccess.
  ///
  /// In en, this message translates to:
  /// **'Added {count} photos'**
  String photosPickerAddSuccess(Object count);

  /// No description provided for @photosPickerNoCandidates.
  ///
  /// In en, this message translates to:
  /// **'No photos available to add'**
  String get photosPickerNoCandidates;

  /// No description provided for @photosSharePhoto.
  ///
  /// In en, this message translates to:
  /// **'Share Photo'**
  String get photosSharePhoto;

  /// No description provided for @photosSharedItemPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'This share requires password access'**
  String get photosSharedItemPasswordRequired;

  /// No description provided for @photosLiveBadge.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get photosLiveBadge;

  /// No description provided for @photosLiveBadgeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Tap to play the motion photo, long-press the photo for a quick preview'**
  String get photosLiveBadgeTooltip;

  /// No description provided for @photosMotionPlayFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to play motion video'**
  String get photosMotionPlayFailed;

  /// No description provided for @photosShareEyebrow.
  ///
  /// In en, this message translates to:
  /// **'SHARE'**
  String get photosShareEyebrow;

  /// No description provided for @photosShareLinkEyebrow.
  ///
  /// In en, this message translates to:
  /// **'LINK'**
  String get photosShareLinkEyebrow;

  /// No description provided for @photosShareCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get photosShareCopy;

  /// No description provided for @photosShareCopied.
  ///
  /// In en, this message translates to:
  /// **'✓ Copied'**
  String get photosShareCopied;

  /// No description provided for @photosShareToEyebrow.
  ///
  /// In en, this message translates to:
  /// **'SHARE TO'**
  String get photosShareToEyebrow;

  /// No description provided for @photosShareToMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get photosShareToMessages;

  /// No description provided for @photosShareToMail.
  ///
  /// In en, this message translates to:
  /// **'Mail'**
  String get photosShareToMail;

  /// No description provided for @photosShareToInstagram.
  ///
  /// In en, this message translates to:
  /// **'Instagram'**
  String get photosShareToInstagram;

  /// No description provided for @photosShareToMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get photosShareToMore;

  /// No description provided for @photosShareOptionLocation.
  ///
  /// In en, this message translates to:
  /// **'Include location'**
  String get photosShareOptionLocation;

  /// No description provided for @photosShareOptionOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original quality'**
  String get photosShareOptionOriginal;

  /// No description provided for @photosShareManage.
  ///
  /// In en, this message translates to:
  /// **'Manage existing links'**
  String get photosShareManage;

  /// No description provided for @photosShareDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get photosShareDone;

  /// No description provided for @photosShareOptionsEyebrow.
  ///
  /// In en, this message translates to:
  /// **'OPTIONS'**
  String get photosShareOptionsEyebrow;

  /// No description provided for @photosShareExpiryOption.
  ///
  /// In en, this message translates to:
  /// **'Expiry'**
  String get photosShareExpiryOption;

  /// No description provided for @photosSharePasswordOption.
  ///
  /// In en, this message translates to:
  /// **'Password protection'**
  String get photosSharePasswordOption;

  /// No description provided for @photosSharePasswordNone.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get photosSharePasswordNone;

  /// No description provided for @photosSharePasswordOn.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get photosSharePasswordOn;

  /// No description provided for @photosShareCreatedHint.
  ///
  /// In en, this message translates to:
  /// **'Link created and copied to clipboard'**
  String get photosShareCreatedHint;

  /// No description provided for @photosShareAlbum.
  ///
  /// In en, this message translates to:
  /// **'Share Album'**
  String get photosShareAlbum;

  /// No description provided for @photosSharePassword.
  ///
  /// In en, this message translates to:
  /// **'Access Password (optional)'**
  String get photosSharePassword;

  /// No description provided for @photosSharePasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for no password'**
  String get photosSharePasswordHint;

  /// No description provided for @photosShareExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry'**
  String get photosShareExpiry;

  /// No description provided for @photosShareExpiry1d.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get photosShareExpiry1d;

  /// No description provided for @photosShareExpiry7d.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get photosShareExpiry7d;

  /// No description provided for @photosShareExpiry30d.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get photosShareExpiry30d;

  /// No description provided for @photosShareExpiryNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get photosShareExpiryNever;

  /// No description provided for @photosExistingShareLinks.
  ///
  /// In en, this message translates to:
  /// **'Existing Share Links'**
  String get photosExistingShareLinks;

  /// No description provided for @photosShareAccessCount.
  ///
  /// In en, this message translates to:
  /// **'Accessed {count} times'**
  String photosShareAccessCount(Object count);

  /// No description provided for @photosCreateLink.
  ///
  /// In en, this message translates to:
  /// **'Create Link'**
  String get photosCreateLink;

  /// No description provided for @photosShareLinkCreated.
  ///
  /// In en, this message translates to:
  /// **'Share link created: {token}'**
  String photosShareLinkCreated(Object token);

  /// No description provided for @photosShareLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create share link'**
  String get photosShareLinkFailed;

  /// No description provided for @photosRemoveFromAlbum.
  ///
  /// In en, this message translates to:
  /// **'Remove from Album'**
  String get photosRemoveFromAlbum;

  /// No description provided for @photosRemoveFromAlbumConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove \"{title}\" from the album? The photo itself will not be deleted.'**
  String photosRemoveFromAlbumConfirm(Object title);

  /// No description provided for @photosRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get photosRemove;

  /// No description provided for @photosRemovedFromAlbum.
  ///
  /// In en, this message translates to:
  /// **'Removed \"{title}\" from album'**
  String photosRemovedFromAlbum(Object title);

  /// No description provided for @photosAlbumPhotoCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} photos'**
  String photosAlbumPhotoCountLabel(Object count);

  /// No description provided for @photosDeleteAlbumTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete Album'**
  String get photosDeleteAlbumTooltip;

  /// No description provided for @photosAllPhotos.
  ///
  /// In en, this message translates to:
  /// **'All Photos'**
  String get photosAllPhotos;

  /// No description provided for @photosNoGroupData.
  ///
  /// In en, this message translates to:
  /// **'No group data'**
  String get photosNoGroupData;

  /// No description provided for @photosBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get photosBrightness;

  /// No description provided for @photosContrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get photosContrast;

  /// No description provided for @photosCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get photosCrop;

  /// No description provided for @photosRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get photosRotate;

  /// No description provided for @photosFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get photosFilter;

  /// No description provided for @photosFilterOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get photosFilterOriginal;

  /// No description provided for @photosFilterGrayscale.
  ///
  /// In en, this message translates to:
  /// **'Grayscale'**
  String get photosFilterGrayscale;

  /// No description provided for @photosFilterSepia.
  ///
  /// In en, this message translates to:
  /// **'Sepia'**
  String get photosFilterSepia;

  /// No description provided for @photosFilterBlur.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get photosFilterBlur;

  /// No description provided for @photosFilterSharpen.
  ///
  /// In en, this message translates to:
  /// **'Sharpen'**
  String get photosFilterSharpen;

  /// No description provided for @musicDeckTitle.
  ///
  /// In en, this message translates to:
  /// **'Music Space'**
  String get musicDeckTitle;

  /// No description provided for @musicDeckHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get musicDeckHome;

  /// No description provided for @musicDeckLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get musicDeckLibrary;

  /// No description provided for @musicDeckPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get musicDeckPlaylists;

  /// No description provided for @musicDeckFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get musicDeckFavorites;

  /// No description provided for @musicDeckRecent.
  ///
  /// In en, this message translates to:
  /// **'Recently played'**
  String get musicDeckRecent;

  /// No description provided for @musicDeckOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get musicDeckOffline;

  /// No description provided for @musicDeckLocalManagement.
  ///
  /// In en, this message translates to:
  /// **'Local resources'**
  String get musicDeckLocalManagement;

  /// No description provided for @musicDeckMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get musicDeckMore;

  /// No description provided for @musicDeckSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get musicDeckSources;

  /// No description provided for @musicDeckSourceLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get musicDeckSourceLocal;

  /// No description provided for @musicDeckSourceNetease.
  ///
  /// In en, this message translates to:
  /// **'NetEase'**
  String get musicDeckSourceNetease;

  /// No description provided for @musicDeckSourceQq.
  ///
  /// In en, this message translates to:
  /// **'QQ Music'**
  String get musicDeckSourceQq;

  /// No description provided for @musicDailyRecommendationSection.
  ///
  /// In en, this message translates to:
  /// **'Recommended today'**
  String get musicDailyRecommendationSection;

  /// No description provided for @musicDailyRecommendationTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily recommended tracks'**
  String get musicDailyRecommendationTitle;

  /// No description provided for @musicDailyRecommendationTrackCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks · Updated daily'**
  String musicDailyRecommendationTrackCount(Object count);

  /// No description provided for @musicDailyRecommendationEmpty.
  ///
  /// In en, this message translates to:
  /// **'Today\'s recommendations are unavailable. Try again later.'**
  String get musicDailyRecommendationEmpty;

  /// No description provided for @musicDailyRecommendationLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load daily recommendations. Try again.'**
  String get musicDailyRecommendationLoadFailed;

  /// No description provided for @musicDeckAccounts.
  ///
  /// In en, this message translates to:
  /// **'Platform accounts'**
  String get musicDeckAccounts;

  /// No description provided for @musicDeckManageAccounts.
  ///
  /// In en, this message translates to:
  /// **'Manage platform accounts'**
  String get musicDeckManageAccounts;

  /// No description provided for @musicDeckManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get musicDeckManage;

  /// No description provided for @musicLocalManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage local metadata, covers, lyrics, and storage scans.'**
  String get musicLocalManagementSubtitle;

  /// No description provided for @musicStartScan.
  ///
  /// In en, this message translates to:
  /// **'Scan storage'**
  String get musicStartScan;

  /// No description provided for @musicCreatePlaylist.
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get musicCreatePlaylist;

  /// No description provided for @musicPlaylistName.
  ///
  /// In en, this message translates to:
  /// **'Playlist name'**
  String get musicPlaylistName;

  /// No description provided for @musicPlaylistDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get musicPlaylistDescription;

  /// No description provided for @musicCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get musicCreate;

  /// No description provided for @musicEditPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Edit playlist'**
  String get musicEditPlaylist;

  /// No description provided for @musicDeletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get musicDeletePlaylist;

  /// No description provided for @musicDeleteLocalTrack.
  ///
  /// In en, this message translates to:
  /// **'Delete local track'**
  String get musicDeleteLocalTrack;

  /// No description provided for @musicDeleteLocalTrackTitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete local track?'**
  String get musicDeleteLocalTrackTitle;

  /// No description provided for @musicDeleteLocalTrackMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" and its source file will be permanently deleted. This cannot be undone.'**
  String musicDeleteLocalTrackMessage(Object title);

  /// No description provided for @musicDeleteLocalTrackSuccess.
  ///
  /// In en, this message translates to:
  /// **'Local track permanently deleted'**
  String get musicDeleteLocalTrackSuccess;

  /// No description provided for @musicDeleteLocalTrackFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed. Please try again later.'**
  String get musicDeleteLocalTrackFailed;

  /// No description provided for @musicDeletePlaylistTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this playlist?'**
  String get musicDeletePlaylistTitle;

  /// No description provided for @musicDeletePlaylistMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? Songs in the playlist will not be deleted.'**
  String musicDeletePlaylistMessage(Object name);

  /// No description provided for @musicPlaylistCoverPick.
  ///
  /// In en, this message translates to:
  /// **'Choose cover'**
  String get musicPlaylistCoverPick;

  /// No description provided for @musicPlaylistCoverChange.
  ///
  /// In en, this message translates to:
  /// **'Change cover'**
  String get musicPlaylistCoverChange;

  /// No description provided for @musicPlaylistCoverHint.
  ///
  /// In en, this message translates to:
  /// **'Uses the first song cover when no image is selected'**
  String get musicPlaylistCoverHint;

  /// No description provided for @musicPlaylistSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save playlist: {error}'**
  String musicPlaylistSaveFailed(Object error);

  /// No description provided for @musicPlaylistDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete playlist: {error}'**
  String musicPlaylistDeleteFailed(Object error);

  /// No description provided for @musicDeckConnectedSources.
  ///
  /// In en, this message translates to:
  /// **'Connected sources'**
  String get musicDeckConnectedSources;

  /// No description provided for @musicDeckSearchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter at least two characters to filter by song, artist, or album'**
  String get musicDeckSearchPrompt;

  /// No description provided for @musicDeckNoSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No matching songs'**
  String get musicDeckNoSearchResults;

  /// No description provided for @musicDeckSelectTrack.
  ///
  /// In en, this message translates to:
  /// **'Select a song to start listening'**
  String get musicDeckSelectTrack;

  /// No description provided for @musicDeckPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get musicDeckPrevious;

  /// No description provided for @musicDeckNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get musicDeckNext;

  /// No description provided for @musicDeckNowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get musicDeckNowPlaying;

  /// No description provided for @musicDeckLibraryReady.
  ///
  /// In en, this message translates to:
  /// **'Library ready'**
  String get musicDeckLibraryReady;

  /// No description provided for @musicDeckLibrarySummary.
  ///
  /// In en, this message translates to:
  /// **'{trackCount} songs · {albumCount} albums'**
  String musicDeckLibrarySummary(Object trackCount, Object albumCount);

  /// No description provided for @musicDeckTrackCount.
  ///
  /// In en, this message translates to:
  /// **'{count} songs'**
  String musicDeckTrackCount(Object count);

  /// No description provided for @musicDeckContinueListening.
  ///
  /// In en, this message translates to:
  /// **'Continue listening'**
  String get musicDeckContinueListening;

  /// No description provided for @musicDeckYourCollections.
  ///
  /// In en, this message translates to:
  /// **'Your playlists'**
  String get musicDeckYourCollections;

  /// No description provided for @musicDeckRecentEmpty.
  ///
  /// In en, this message translates to:
  /// **'Recently played content will appear here after you play a song.'**
  String get musicDeckRecentEmpty;

  /// No description provided for @musicDeckPartialSourceFailure.
  ///
  /// In en, this message translates to:
  /// **'Some online sources are temporarily unavailable. Local music and other sources remain usable.'**
  String get musicDeckPartialSourceFailure;

  /// No description provided for @musicDeckLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browse local music and known songs from your connected accounts.'**
  String get musicDeckLibrarySubtitle;

  /// No description provided for @musicDeckPlaylistsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local and connected-platform playlists share one organized space.'**
  String get musicDeckPlaylistsSubtitle;

  /// No description provided for @musicDeckFavoritesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local favorites and liked songs from connected platforms.'**
  String get musicDeckFavoritesSubtitle;

  /// No description provided for @musicDeckRecentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Continue with recently accessed local content.'**
  String get musicDeckRecentSubtitle;

  /// No description provided for @musicDeckLocalPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Local playlist'**
  String get musicDeckLocalPlaylist;

  /// No description provided for @musicDeckOfflineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage content downloaded to this device for offline playback.'**
  String get musicDeckOfflineSubtitle;

  /// No description provided for @musicDeckOfflineEmpty.
  ///
  /// In en, this message translates to:
  /// **'No music is available offline yet. Downloads will appear after download management is connected.'**
  String get musicDeckOfflineEmpty;

  /// No description provided for @musicDeckRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get musicDeckRetry;

  /// No description provided for @musicNavSongs.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get musicNavSongs;

  /// No description provided for @musicNavAlbums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get musicNavAlbums;

  /// No description provided for @musicNavArtists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get musicNavArtists;

  /// No description provided for @musicNavPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get musicNavPlaylists;

  /// No description provided for @musicNavFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get musicNavFavorites;

  /// No description provided for @musicSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get musicSearch;

  /// No description provided for @musicSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search Music'**
  String get musicSearchTitle;

  /// No description provided for @musicSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Enter song name, artist or album'**
  String get musicSearchHint;

  /// No description provided for @musicClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get musicClose;

  /// No description provided for @musicGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get musicGotIt;

  /// No description provided for @musicPlaybackError.
  ///
  /// In en, this message translates to:
  /// **'Audio playback failed, the codec may not be supported'**
  String get musicPlaybackError;

  /// No description provided for @musicCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get musicCancel;

  /// No description provided for @musicSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get musicSave;

  /// No description provided for @musicSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get musicSaving;

  /// No description provided for @musicEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get musicEdit;

  /// No description provided for @musicApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get musicApply;

  /// No description provided for @musicApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying'**
  String get musicApplying;

  /// No description provided for @musicNoLyrics.
  ///
  /// In en, this message translates to:
  /// **'No lyrics'**
  String get musicNoLyrics;

  /// No description provided for @musicNowPlayingArtwork.
  ///
  /// In en, this message translates to:
  /// **'Artwork'**
  String get musicNowPlayingArtwork;

  /// No description provided for @musicNowPlayingLyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get musicNowPlayingLyrics;

  /// No description provided for @musicEditMetadata.
  ///
  /// In en, this message translates to:
  /// **'Edit Metadata'**
  String get musicEditMetadata;

  /// No description provided for @musicTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title cannot be empty'**
  String get musicTitleRequired;

  /// No description provided for @musicMetadataSaved.
  ///
  /// In en, this message translates to:
  /// **'Metadata saved'**
  String get musicMetadataSaved;

  /// No description provided for @musicSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String musicSaveFailed(Object error);

  /// No description provided for @musicFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get musicFieldTitle;

  /// No description provided for @musicFieldArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get musicFieldArtist;

  /// No description provided for @musicFieldAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get musicFieldAlbum;

  /// No description provided for @musicFieldGenre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get musicFieldGenre;

  /// No description provided for @musicCoverImage.
  ///
  /// In en, this message translates to:
  /// **'Cover Image'**
  String get musicCoverImage;

  /// No description provided for @musicCoverSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected: {name}'**
  String musicCoverSelected(Object name);

  /// No description provided for @musicCoverPick.
  ///
  /// In en, this message translates to:
  /// **'Select Cover Image'**
  String get musicCoverPick;

  /// No description provided for @musicLyricsFile.
  ///
  /// In en, this message translates to:
  /// **'Lyrics File'**
  String get musicLyricsFile;

  /// No description provided for @musicLyricsPick.
  ///
  /// In en, this message translates to:
  /// **'Select Lyrics File (LRC / TXT / SRT / VTT)'**
  String get musicLyricsPick;

  /// No description provided for @musicQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'Play Queue'**
  String get musicQueueTitle;

  /// No description provided for @musicQueueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Play queue is empty'**
  String get musicQueueEmpty;

  /// No description provided for @musicShuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get musicShuffle;

  /// No description provided for @musicRepeatOff.
  ///
  /// In en, this message translates to:
  /// **'Sequential'**
  String get musicRepeatOff;

  /// No description provided for @musicRepeatAll.
  ///
  /// In en, this message translates to:
  /// **'Loop All'**
  String get musicRepeatAll;

  /// No description provided for @musicRepeatOne.
  ///
  /// In en, this message translates to:
  /// **'Loop Single'**
  String get musicRepeatOne;

  /// No description provided for @musicPlaylistsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your local playlists.'**
  String get musicPlaylistsSubtitle;

  /// No description provided for @musicPlaylistsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Create playlists to manage them here.'**
  String get musicPlaylistsEmptyHint;

  /// No description provided for @musicOpenPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Open Playlist'**
  String get musicOpenPlaylist;

  /// No description provided for @musicPlaylistEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add songs from the song list to see them here.'**
  String get musicPlaylistEmptyHint;

  /// No description provided for @musicAlbumNoTracks.
  ///
  /// In en, this message translates to:
  /// **'No tracks in this album.'**
  String get musicAlbumNoTracks;

  /// No description provided for @musicArtistNoTracks.
  ///
  /// In en, this message translates to:
  /// **'No tracks for this artist.'**
  String get musicArtistNoTracks;

  /// No description provided for @musicRemoveFromPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Remove from Playlist'**
  String get musicRemoveFromPlaylist;

  /// No description provided for @musicViewAll.
  ///
  /// In en, this message translates to:
  /// **'View All ({count})'**
  String musicViewAll(Object count);

  /// No description provided for @musicPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get musicPause;

  /// No description provided for @musicPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get musicPlay;

  /// No description provided for @musicNotPlaying.
  ///
  /// In en, this message translates to:
  /// **'Not playing'**
  String get musicNotPlaying;

  /// No description provided for @musicRecommendedArtist.
  ///
  /// In en, this message translates to:
  /// **'Recommended Artist'**
  String get musicRecommendedArtist;

  /// No description provided for @musicExploreMusic.
  ///
  /// In en, this message translates to:
  /// **'Explore Music'**
  String get musicExploreMusic;

  /// No description provided for @musicPlayNow.
  ///
  /// In en, this message translates to:
  /// **'Play Now'**
  String get musicPlayNow;

  /// No description provided for @musicTrendingArtists.
  ///
  /// In en, this message translates to:
  /// **'Trending Artists'**
  String get musicTrendingArtists;

  /// No description provided for @musicViewAllSimple.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get musicViewAllSimple;

  /// No description provided for @musicNoTracks.
  ///
  /// In en, this message translates to:
  /// **'No tracks yet'**
  String get musicNoTracks;

  /// No description provided for @musicTracksHint.
  ///
  /// In en, this message translates to:
  /// **'Tracks will appear here after music scanning.'**
  String get musicTracksHint;

  /// No description provided for @musicAddToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to Playlist'**
  String get musicAddToPlaylist;

  /// No description provided for @musicUnfavorite.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite'**
  String get musicUnfavorite;

  /// No description provided for @musicFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get musicFavorite;

  /// No description provided for @musicNoAlbums.
  ///
  /// In en, this message translates to:
  /// **'No albums yet'**
  String get musicNoAlbums;

  /// No description provided for @musicAlbumsHint.
  ///
  /// In en, this message translates to:
  /// **'Albums are automatically aggregated after music scanning.'**
  String get musicAlbumsHint;

  /// No description provided for @musicAlbumsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browse your local music library by album.'**
  String get musicAlbumsSubtitle;

  /// No description provided for @musicArtistsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Aggregate songs and albums by artist.'**
  String get musicArtistsSubtitle;

  /// No description provided for @musicNoArtists.
  ///
  /// In en, this message translates to:
  /// **'No artists yet'**
  String get musicNoArtists;

  /// No description provided for @musicArtistsHint.
  ///
  /// In en, this message translates to:
  /// **'Artists will appear after song tag parsing.'**
  String get musicArtistsHint;

  /// No description provided for @musicSidebarViewAll.
  ///
  /// In en, this message translates to:
  /// **'View All ({count})'**
  String musicSidebarViewAll(Object count);

  /// No description provided for @musicScanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan audio files in the file library, parse tags, albums, artists and covers.'**
  String get musicScanSubtitle;

  /// No description provided for @musicNoScanTask.
  ///
  /// In en, this message translates to:
  /// **'No new scan tasks.'**
  String get musicNoScanTask;

  /// No description provided for @musicScanStatus.
  ///
  /// In en, this message translates to:
  /// **'Task {id} · {status} · {progress}% · {files} files scanned'**
  String musicScanStatus(
    Object id,
    Object status,
    Object progress,
    Object files,
  );

  /// No description provided for @musicMetadataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review song titles, artists, albums and quality tags.'**
  String get musicMetadataSubtitle;

  /// No description provided for @musicNoMetadataHint.
  ///
  /// In en, this message translates to:
  /// **'After music scanning, you can complete MusicBrainz metadata here.'**
  String get musicNoMetadataHint;

  /// No description provided for @musicCandidate.
  ///
  /// In en, this message translates to:
  /// **'Candidate'**
  String get musicCandidate;

  /// No description provided for @musicBrainzCandidates.
  ///
  /// In en, this message translates to:
  /// **'MusicBrainz Candidates'**
  String get musicBrainzCandidates;

  /// No description provided for @musicCandidateFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch candidates'**
  String get musicCandidateFetchFailed;

  /// No description provided for @musicNoCandidates.
  ///
  /// In en, this message translates to:
  /// **'No candidates found'**
  String get musicNoCandidates;

  /// No description provided for @musicNoCandidatesHint.
  ///
  /// In en, this message translates to:
  /// **'Try improving the local title, artist or album, then retry.'**
  String get musicNoCandidatesHint;

  /// No description provided for @backupSkipNonWifi.
  ///
  /// In en, this message translates to:
  /// **'Not on WiFi, skipping backup'**
  String get backupSkipNonWifi;

  /// No description provided for @backupSkipNoPermission.
  ///
  /// In en, this message translates to:
  /// **'Photo library access not granted'**
  String get backupSkipNoPermission;

  /// No description provided for @backupSkipNoAlbums.
  ///
  /// In en, this message translates to:
  /// **'No albums'**
  String get backupSkipNoAlbums;

  /// No description provided for @backupSkipNoPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos'**
  String get backupSkipNoPhotos;

  /// No description provided for @backupNotificationChannel.
  ///
  /// In en, this message translates to:
  /// **'Photo Backup'**
  String get backupNotificationChannel;

  /// No description provided for @backupNotificationChannelDesc.
  ///
  /// In en, this message translates to:
  /// **'Photo auto-backup progress'**
  String get backupNotificationChannelDesc;

  /// No description provided for @backupNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo Backup In Progress'**
  String get backupNotificationTitle;

  /// No description provided for @backupNotificationProgress.
  ///
  /// In en, this message translates to:
  /// **'Processed {current}/{total}, {uploaded} uploaded'**
  String backupNotificationProgress(
    Object current,
    Object total,
    Object uploaded,
  );

  /// No description provided for @backupNotificationComplete.
  ///
  /// In en, this message translates to:
  /// **'Photo Backup Complete'**
  String get backupNotificationComplete;

  /// No description provided for @backupNotificationSummary.
  ///
  /// In en, this message translates to:
  /// **'{uploaded} uploaded, {skipped} skipped, {failed} failed'**
  String backupNotificationSummary(
    Object uploaded,
    Object skipped,
    Object failed,
  );

  /// No description provided for @photoRegenerateThumbnails.
  ///
  /// In en, this message translates to:
  /// **'Regenerate Thumbnails'**
  String get photoRegenerateThumbnails;

  /// No description provided for @photoRegenerateQueued.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail rebuild queued. Track progress in the task center.'**
  String get photoRegenerateQueued;

  /// No description provided for @photosActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Action failed. Try again later.'**
  String get photosActionFailed;

  /// No description provided for @photoImportCandidates.
  ///
  /// In en, this message translates to:
  /// **'Import Candidates'**
  String get photoImportCandidates;

  /// No description provided for @photoNoImportCandidates.
  ///
  /// In en, this message translates to:
  /// **'No pending photos to import'**
  String get photoNoImportCandidates;

  /// No description provided for @importFiles.
  ///
  /// In en, this message translates to:
  /// **'Import Files'**
  String get importFiles;

  /// No description provided for @importToPersonalSpace.
  ///
  /// In en, this message translates to:
  /// **'Personal Space'**
  String get importToPersonalSpace;

  /// No description provided for @importToSharedSpace.
  ///
  /// In en, this message translates to:
  /// **'Shared Space'**
  String get importToSharedSpace;

  /// No description provided for @importSpaceSelectorTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Import Destination'**
  String get importSpaceSelectorTitle;

  /// No description provided for @importSpaceSelectorDesc.
  ///
  /// In en, this message translates to:
  /// **'Select where to import files'**
  String get importSpaceSelectorDesc;

  /// No description provided for @importPersonalSpaceDesc.
  ///
  /// In en, this message translates to:
  /// **'Only you can see these files'**
  String get importPersonalSpaceDesc;

  /// No description provided for @importSharedSpaceDesc.
  ///
  /// In en, this message translates to:
  /// **'All users can see these files'**
  String get importSharedSpaceDesc;

  /// No description provided for @importUploading.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get importUploading;

  /// No description provided for @importComplete.
  ///
  /// In en, this message translates to:
  /// **'{count} files imported successfully'**
  String importComplete(Object count);

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailed;

  /// No description provided for @importRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Import completed, but the list could not be refreshed.'**
  String get importRefreshFailed;

  /// No description provided for @importProcessing.
  ///
  /// In en, this message translates to:
  /// **'{count} files uploaded; processing is still in progress.'**
  String importProcessing(Object count);

  /// No description provided for @importUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'Unsupported file format: {files}. Supported formats: {extensions}.'**
  String importUnsupportedFormat(Object files, Object extensions);

  /// No description provided for @readerPortal.
  ///
  /// In en, this message translates to:
  /// **'Portal'**
  String get readerPortal;

  /// No description provided for @readerCenter.
  ///
  /// In en, this message translates to:
  /// **'Reader Center'**
  String get readerCenter;

  /// No description provided for @readerSortRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get readerSortRecent;

  /// No description provided for @readerSortTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get readerSortTitle;

  /// No description provided for @readerTypeNovel.
  ///
  /// In en, this message translates to:
  /// **'Novel'**
  String get readerTypeNovel;

  /// No description provided for @readerTypeLiterature.
  ///
  /// In en, this message translates to:
  /// **'Literature'**
  String get readerTypeLiterature;

  /// No description provided for @readerTypeAcademic.
  ///
  /// In en, this message translates to:
  /// **'Academic'**
  String get readerTypeAcademic;

  /// No description provided for @readerTypeTechnical.
  ///
  /// In en, this message translates to:
  /// **'Technical'**
  String get readerTypeTechnical;

  /// No description provided for @readerTypePoetry.
  ///
  /// In en, this message translates to:
  /// **'Poetry'**
  String get readerTypePoetry;

  /// No description provided for @readerTypeEssay.
  ///
  /// In en, this message translates to:
  /// **'Essay'**
  String get readerTypeEssay;

  /// No description provided for @readerTypeComic.
  ///
  /// In en, this message translates to:
  /// **'Comic'**
  String get readerTypeComic;

  /// No description provided for @readerNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get readerNotStarted;

  /// No description provided for @readerUnknownTime.
  ///
  /// In en, this message translates to:
  /// **'Unknown time'**
  String get readerUnknownTime;

  /// No description provided for @readerChapterNumber.
  ///
  /// In en, this message translates to:
  /// **'Chapter {number}'**
  String readerChapterNumber(Object number);

  /// No description provided for @readerProgressLabel.
  ///
  /// In en, this message translates to:
  /// **'Progress {progress}'**
  String readerProgressLabel(Object progress);

  /// No description provided for @readerRestoreProgress.
  ///
  /// In en, this message translates to:
  /// **'Restore Reading Progress'**
  String get readerRestoreProgress;

  /// No description provided for @readerRestoreProgressConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restore to this version\'s reading progress? Current progress will be overwritten.'**
  String get readerRestoreProgressConfirm;

  /// No description provided for @readerConfirmRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get readerConfirmRestore;

  /// No description provided for @readerProgressRestored.
  ///
  /// In en, this message translates to:
  /// **'Reading progress restored'**
  String get readerProgressRestored;

  /// No description provided for @readerRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String readerRestoreFailed(Object error);

  /// No description provided for @readerVersionHistory.
  ///
  /// In en, this message translates to:
  /// **'Version History'**
  String get readerVersionHistory;

  /// No description provided for @readerNoVersionHistory.
  ///
  /// In en, this message translates to:
  /// **'No version history'**
  String get readerNoVersionHistory;

  /// No description provided for @readerVersionHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'Versions are automatically recorded when reading progress changes'**
  String get readerVersionHistoryHint;

  /// No description provided for @readerRestoreThisVersion.
  ///
  /// In en, this message translates to:
  /// **'Restore this version'**
  String get readerRestoreThisVersion;

  /// No description provided for @readerFeatureComingSoon.
  ///
  /// In en, this message translates to:
  /// **'This feature is coming soon'**
  String get readerFeatureComingSoon;

  /// No description provided for @videoImportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Import subtitle file'**
  String get videoImportSubtitle;

  /// No description provided for @videoImportedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Imported subtitle'**
  String get videoImportedSubtitle;

  /// No description provided for @videoLocalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local subtitle'**
  String get videoLocalSubtitle;

  /// No description provided for @videoSubtitleImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Subtitle loaded'**
  String get videoSubtitleImportSuccess;

  /// No description provided for @videoSubtitleImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to read the subtitle file'**
  String get videoSubtitleImportFailed;

  /// No description provided for @videoSubtitleFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Subtitle files must be 2 MB or smaller'**
  String get videoSubtitleFileTooLarge;

  /// No description provided for @videoSubtitleNoCues.
  ///
  /// In en, this message translates to:
  /// **'No supported timed captions were found in this file'**
  String get videoSubtitleNoCues;

  /// No description provided for @videoAudioTrackNumber.
  ///
  /// In en, this message translates to:
  /// **'Audio track {index}'**
  String videoAudioTrackNumber(int index);

  /// No description provided for @videoLanguageTrackNumber.
  ///
  /// In en, this message translates to:
  /// **'Language {index}'**
  String videoLanguageTrackNumber(int index);

  /// No description provided for @videoSubtitleTrackNumber.
  ///
  /// In en, this message translates to:
  /// **'Subtitle track {index}'**
  String videoSubtitleTrackNumber(int index);

  /// No description provided for @videoMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get videoMute;

  /// No description provided for @videoUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get videoUnmute;

  /// No description provided for @videoPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get videoPause;

  /// No description provided for @videoEnterFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Enter fullscreen'**
  String get videoEnterFullscreen;

  /// No description provided for @videoExitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit fullscreen'**
  String get videoExitFullscreen;

  /// No description provided for @videoSeekBackwardSeconds.
  ///
  /// In en, this message translates to:
  /// **'Back {seconds}s'**
  String videoSeekBackwardSeconds(int seconds);

  /// No description provided for @videoSeekForwardSeconds.
  ///
  /// In en, this message translates to:
  /// **'Forward {seconds}s'**
  String videoSeekForwardSeconds(int seconds);

  /// No description provided for @videoNoAudioTracks.
  ///
  /// In en, this message translates to:
  /// **'No audio tracks available'**
  String get videoNoAudioTracks;

  /// No description provided for @videoSelectAudioTrack.
  ///
  /// In en, this message translates to:
  /// **'Select audio track'**
  String get videoSelectAudioTrack;

  /// No description provided for @videoNoLanguages.
  ///
  /// In en, this message translates to:
  /// **'No languages available'**
  String get videoNoLanguages;

  /// No description provided for @videoSelectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select language'**
  String get videoSelectLanguage;

  /// No description provided for @videoVolumeValue.
  ///
  /// In en, this message translates to:
  /// **'Volume {volume}%'**
  String videoVolumeValue(int volume);

  /// No description provided for @videoVolumeMutedValue.
  ///
  /// In en, this message translates to:
  /// **'Volume {volume}% (muted)'**
  String videoVolumeMutedValue(int volume);

  /// No description provided for @videoSeasonEpisodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Season {season} · Episode {episode}'**
  String videoSeasonEpisodeLabel(int season, int episode);

  /// No description provided for @videoHeroFeatured.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get videoHeroFeatured;

  /// No description provided for @videoHeroMovie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get videoHeroMovie;

  /// No description provided for @videoHeroTv.
  ///
  /// In en, this message translates to:
  /// **'TV'**
  String get videoHeroTv;

  /// No description provided for @videoHeroWatchNow.
  ///
  /// In en, this message translates to:
  /// **'Play now'**
  String get videoHeroWatchNow;

  /// No description provided for @videoHeroFallbackOverview.
  ///
  /// In en, this message translates to:
  /// **'This local title is ready to play.'**
  String get videoHeroFallbackOverview;

  /// No description provided for @videoHeroCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Media Library'**
  String get videoHeroCenterTitle;

  /// No description provided for @videoHeroCenterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select a title to view its details and start playback.'**
  String get videoHeroCenterSubtitle;

  /// No description provided for @filePurgeDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete?'**
  String get filePurgeDeleteTitle;

  /// No description provided for @filePurgeDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete {name} and its stored file? This action cannot be undone.'**
  String filePurgeDeleteMessage(String name);

  /// No description provided for @filePurgeImpactTitle.
  ///
  /// In en, this message translates to:
  /// **'This file is still in use'**
  String get filePurgeImpactTitle;

  /// No description provided for @filePurgeImpactMessage.
  ///
  /// In en, this message translates to:
  /// **'This operation affects {fileCount} file nodes and {referenceCount} references in other modules. Continue with cascade deletion?'**
  String filePurgeImpactMessage(int fileCount, int referenceCount);

  /// No description provided for @filePurgeCascadeDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete all references'**
  String get filePurgeCascadeDelete;

  /// No description provided for @videoLocalLibrarySources.
  ///
  /// In en, this message translates to:
  /// **'Local direct media libraries'**
  String get videoLocalLibrarySources;

  /// No description provided for @videoLocalLibrarySourcesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reference read-only deployment mounts directly; original movies are not copied to MinIO.'**
  String get videoLocalLibrarySourcesSubtitle;

  /// No description provided for @videoLibrarySourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Media sources'**
  String get videoLibrarySourcesTitle;

  /// No description provided for @videoLibrarySourceCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sources'**
  String videoLibrarySourceCount(int count);

  /// No description provided for @videoLibraryLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading media library'**
  String get videoLibraryLoading;

  /// No description provided for @videoRefreshSources.
  ///
  /// In en, this message translates to:
  /// **'Refresh media library sources'**
  String get videoRefreshSources;

  /// No description provided for @videoAddLibrarySource.
  ///
  /// In en, this message translates to:
  /// **'Add source'**
  String get videoAddLibrarySource;

  /// No description provided for @videoEditLibrarySource.
  ///
  /// In en, this message translates to:
  /// **'Edit source'**
  String get videoEditLibrarySource;

  /// No description provided for @videoStorageLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Storage locations could not be loaded'**
  String get videoStorageLocationUnavailable;

  /// No description provided for @videoNoStorageLocation.
  ///
  /// In en, this message translates to:
  /// **'No local storage location is available'**
  String get videoNoStorageLocation;

  /// No description provided for @videoNoStorageLocationHint.
  ///
  /// In en, this message translates to:
  /// **'Ask a system administrator to configure and enable a read-only local mount in Storage Management.'**
  String get videoNoStorageLocationHint;

  /// No description provided for @videoLoadSourcesFailed.
  ///
  /// In en, this message translates to:
  /// **'Library sources could not be loaded'**
  String get videoLoadSourcesFailed;

  /// No description provided for @videoNoLibrarySources.
  ///
  /// In en, this message translates to:
  /// **'No local media library source has been configured.'**
  String get videoNoLibrarySources;

  /// No description provided for @videoLibraryType.
  ///
  /// In en, this message translates to:
  /// **'Library type'**
  String get videoLibraryType;

  /// No description provided for @videoLibraryTypeHint.
  ///
  /// In en, this message translates to:
  /// **'The type selects the scanner and hierarchy; existing sources cannot change it directly.'**
  String get videoLibraryTypeHint;

  /// No description provided for @videoLibraryTypeMovie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get videoLibraryTypeMovie;

  /// No description provided for @videoLibraryTypeTvSeries.
  ///
  /// In en, this message translates to:
  /// **'TV Series'**
  String get videoLibraryTypeTvSeries;

  /// No description provided for @videoLibraryTypeAnime.
  ///
  /// In en, this message translates to:
  /// **'Anime'**
  String get videoLibraryTypeAnime;

  /// No description provided for @videoLibraryTypeRoot.
  ///
  /// In en, this message translates to:
  /// **'Mixed root'**
  String get videoLibraryTypeRoot;

  /// No description provided for @videoStorageAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get videoStorageAvailable;

  /// No description provided for @videoStorageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get videoStorageUnavailable;

  /// No description provided for @videoStorageDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get videoStorageDisabled;

  /// No description provided for @videoDeleteLibrarySource.
  ///
  /// In en, this message translates to:
  /// **'Delete media source'**
  String get videoDeleteLibrarySource;

  /// No description provided for @videoDeleteLibrarySourceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete source “{name}”? Imported media is not deleted; deletion is rejected while media references remain.'**
  String videoDeleteLibrarySourceConfirm(String name);

  /// No description provided for @videoDeleteLibrarySourceDone.
  ///
  /// In en, this message translates to:
  /// **'Media source deleted'**
  String get videoDeleteLibrarySourceDone;

  /// No description provided for @videoUnknownStorageLocation.
  ///
  /// In en, this message translates to:
  /// **'Unknown storage location'**
  String get videoUnknownStorageLocation;

  /// No description provided for @videoSourceScanSummary.
  ///
  /// In en, this message translates to:
  /// **'Last discovery found {count} videos with {created} awaiting review'**
  String videoSourceScanSummary(int count, int created);

  /// No description provided for @videoSourceMissingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} unavailable'**
  String videoSourceMissingCount(int count);

  /// No description provided for @videoSourceDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get videoSourceDisabled;

  /// No description provided for @videoScanThisSource.
  ///
  /// In en, this message translates to:
  /// **'Discover updates'**
  String get videoScanThisSource;

  /// No description provided for @videoReviewLibrarySource.
  ///
  /// In en, this message translates to:
  /// **'Review discoveries and add selected media'**
  String get videoReviewLibrarySource;

  /// No description provided for @videoBrowseRelativeDirectory.
  ///
  /// In en, this message translates to:
  /// **'Browse safe directories'**
  String get videoBrowseRelativeDirectory;

  /// No description provided for @videoChooseThisDirectory.
  ///
  /// In en, this message translates to:
  /// **'Choose this directory'**
  String get videoChooseThisDirectory;

  /// No description provided for @videoDirectoryRoot.
  ///
  /// In en, this message translates to:
  /// **'Root directory'**
  String get videoDirectoryRoot;

  /// No description provided for @videoDiscoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Discovery and import'**
  String get videoDiscoveryTitle;

  /// No description provided for @videoReviewSelectionHint.
  ///
  /// In en, this message translates to:
  /// **'Select a series, season, or episode. Only confirmed selections are added to the library.'**
  String get videoReviewSelectionHint;

  /// No description provided for @videoLocalDiscoveryTask.
  ///
  /// In en, this message translates to:
  /// **'Local media discovery'**
  String get videoLocalDiscoveryTask;

  /// No description provided for @videoLocalImportTask.
  ///
  /// In en, this message translates to:
  /// **'Selected media import'**
  String get videoLocalImportTask;

  /// No description provided for @videoAwaitingReview.
  ///
  /// In en, this message translates to:
  /// **'Awaiting review'**
  String get videoAwaitingReview;

  /// No description provided for @videoDiscoveryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No discovery result yet. Discovering creates candidates without immediately adding them.'**
  String get videoDiscoveryEmpty;

  /// No description provided for @videoDiscoveryRunning.
  ///
  /// In en, this message translates to:
  /// **'Discovering media files. Leaving this screen does not stop the background task.'**
  String get videoDiscoveryRunning;

  /// No description provided for @videoDiscoveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Discovery failed. Check source health and try again.'**
  String get videoDiscoveryFailed;

  /// No description provided for @videoDiscoveryCancelled.
  ///
  /// In en, this message translates to:
  /// **'The discovery or import task was cancelled.'**
  String get videoDiscoveryCancelled;

  /// No description provided for @videoDiscoveryCandidates.
  ///
  /// In en, this message translates to:
  /// **'{count} candidates'**
  String videoDiscoveryCandidates(int count);

  /// No description provided for @videoDiscoverySelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String videoDiscoverySelected(int count);

  /// No description provided for @videoDiscoveryIssues.
  ///
  /// In en, this message translates to:
  /// **'{count} issues'**
  String videoDiscoveryIssues(int count);

  /// No description provided for @videoSelectAllCandidates.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get videoSelectAllCandidates;

  /// No description provided for @videoClearCandidateSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get videoClearCandidateSelection;

  /// No description provided for @videoAddSelectedToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Add to media library'**
  String get videoAddSelectedToLibrary;

  /// No description provided for @videoPauseImport.
  ///
  /// In en, this message translates to:
  /// **'Pause import'**
  String get videoPauseImport;

  /// No description provided for @videoCancelDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Cancel task'**
  String get videoCancelDiscovery;

  /// No description provided for @videoBackToParentNode.
  ///
  /// In en, this message translates to:
  /// **'Back to parent'**
  String get videoBackToParentNode;

  /// No description provided for @videoLoadTreeFailed.
  ///
  /// In en, this message translates to:
  /// **'Candidate tree could not be loaded'**
  String get videoLoadTreeFailed;

  /// No description provided for @videoNoCandidates.
  ///
  /// In en, this message translates to:
  /// **'There are no candidates at this level.'**
  String get videoNoCandidates;

  /// No description provided for @videoCandidateExisting.
  ///
  /// In en, this message translates to:
  /// **'Already in library'**
  String get videoCandidateExisting;

  /// No description provided for @videoCandidateChanged.
  ///
  /// In en, this message translates to:
  /// **'File changed'**
  String get videoCandidateChanged;

  /// No description provided for @videoCandidateUnmatched.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized'**
  String get videoCandidateUnmatched;

  /// No description provided for @videoCandidateNew.
  ///
  /// In en, this message translates to:
  /// **'New candidate'**
  String get videoCandidateNew;

  /// No description provided for @videoUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Unavailable items'**
  String get videoUnavailableTitle;

  /// No description provided for @videoLibraryRecordsExpand.
  ///
  /// In en, this message translates to:
  /// **'Show more records'**
  String get videoLibraryRecordsExpand;

  /// No description provided for @videoLibraryRecordsCollapse.
  ///
  /// In en, this message translates to:
  /// **'Show fewer records'**
  String get videoLibraryRecordsCollapse;

  /// No description provided for @photosPrevPhoto.
  ///
  /// In en, this message translates to:
  /// **'Previous photo'**
  String get photosPrevPhoto;

  /// No description provided for @photosNextPhoto.
  ///
  /// In en, this message translates to:
  /// **'Next photo'**
  String get photosNextPhoto;

  /// No description provided for @videoUnavailableEmpty.
  ///
  /// In en, this message translates to:
  /// **'No local media is currently missing or unreadable.'**
  String get videoUnavailableEmpty;

  /// No description provided for @videoUnavailableCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items need attention'**
  String videoUnavailableCount(int count);

  /// No description provided for @videoUnavailableLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unavailable items could not be loaded'**
  String get videoUnavailableLoadFailed;

  /// No description provided for @videoMissingPending.
  ///
  /// In en, this message translates to:
  /// **'Awaiting missing confirmation'**
  String get videoMissingPending;

  /// No description provided for @videoMissingConfirmed.
  ///
  /// In en, this message translates to:
  /// **'File missing'**
  String get videoMissingConfirmed;

  /// No description provided for @videoFileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'File unavailable'**
  String get videoFileUnavailable;

  /// No description provided for @videoSourceOffline.
  ///
  /// In en, this message translates to:
  /// **'Source offline'**
  String get videoSourceOffline;

  /// No description provided for @videoSourceDegraded.
  ///
  /// In en, this message translates to:
  /// **'Partially unavailable'**
  String get videoSourceDegraded;

  /// No description provided for @videoSourceName.
  ///
  /// In en, this message translates to:
  /// **'Source name'**
  String get videoSourceName;

  /// No description provided for @videoStorageLocation.
  ///
  /// In en, this message translates to:
  /// **'Storage location'**
  String get videoStorageLocation;

  /// No description provided for @videoSelectLibrarySource.
  ///
  /// In en, this message translates to:
  /// **'Select library source'**
  String get videoSelectLibrarySource;

  /// No description provided for @videoNoAvailableStorageLocation.
  ///
  /// In en, this message translates to:
  /// **'No storage location available'**
  String get videoNoAvailableStorageLocation;

  /// No description provided for @videoNoAvailableStorageLocationHint.
  ///
  /// In en, this message translates to:
  /// **'Add a local storage location and ensure it is enabled before creating a library source.'**
  String get videoNoAvailableStorageLocationHint;

  /// No description provided for @videoRelativeDirectory.
  ///
  /// In en, this message translates to:
  /// **'Relative directory'**
  String get videoRelativeDirectory;

  /// No description provided for @videoRelativeDirectoryHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a path within the storage location, for example Movies/4K'**
  String get videoRelativeDirectoryHint;

  /// No description provided for @videoSourceEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable this source'**
  String get videoSourceEnabled;

  /// No description provided for @videoSourceRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Enter a source name and relative directory'**
  String get videoSourceRequiredFields;

  /// No description provided for @videoNeverScanned.
  ///
  /// In en, this message translates to:
  /// **'Never scanned'**
  String get videoNeverScanned;

  /// No description provided for @adminAddLocalStorageLocation.
  ///
  /// In en, this message translates to:
  /// **'Add mount location'**
  String get adminAddLocalStorageLocation;

  /// No description provided for @adminLocalStorageLocations.
  ///
  /// In en, this message translates to:
  /// **'Local storage locations'**
  String get adminLocalStorageLocations;

  /// No description provided for @adminReadOnlyMediaMounts.
  ///
  /// In en, this message translates to:
  /// **'Read-only media mounts'**
  String get adminReadOnlyMediaMounts;

  /// No description provided for @adminLocalStorageLocationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only deployment allowlisted mount keys and relative directories are stored; host absolute paths are not persisted.'**
  String get adminLocalStorageLocationsSubtitle;

  /// No description provided for @adminNoLocalStorageLocations.
  ///
  /// In en, this message translates to:
  /// **'No read-only local storage location has been configured.'**
  String get adminNoLocalStorageLocations;

  /// No description provided for @adminDeleteLocalStorageLocation.
  ///
  /// In en, this message translates to:
  /// **'Delete storage location'**
  String get adminDeleteLocalStorageLocation;

  /// No description provided for @adminMountKey.
  ///
  /// In en, this message translates to:
  /// **'Mount key'**
  String get adminMountKey;

  /// No description provided for @adminMountKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Must match a key under file.local-media.mounts in application.yml'**
  String get adminMountKeyHint;

  /// No description provided for @adminRelativeRoot.
  ///
  /// In en, this message translates to:
  /// **'Relative root'**
  String get adminRelativeRoot;

  /// No description provided for @adminRelativeRootHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a directory inside the mount; use . for the mount root'**
  String get adminRelativeRootHint;

  /// No description provided for @adminLocalStorageSecurityHint.
  ///
  /// In en, this message translates to:
  /// **'Absolute paths are supplied by deployment configuration; this screen can only select a relative directory in an approved mount.'**
  String get adminLocalStorageSecurityHint;

  /// No description provided for @adminLocalStorageRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Enter a name, mount key, and relative root'**
  String get adminLocalStorageRequiredFields;

  /// No description provided for @adminCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get adminCancel;

  /// No description provided for @photosTaskNotFound.
  ///
  /// In en, this message translates to:
  /// **'This task is no longer available.'**
  String get photosTaskNotFound;

  /// No description provided for @photosTaskMonitorTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Status monitoring timed out. The background task may still be running.'**
  String get photosTaskMonitorTimedOut;

  /// No description provided for @photosRetryStatus.
  ///
  /// In en, this message translates to:
  /// **'Retry status'**
  String get photosRetryStatus;

  /// No description provided for @musicQrLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Netease Cloud Music login'**
  String get musicQrLoginTitle;

  /// No description provided for @musicQrLoginInstruction.
  ///
  /// In en, this message translates to:
  /// **'Open the Netease Cloud Music app and scan this QR code.'**
  String get musicQrLoginInstruction;

  /// No description provided for @musicQrWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for scan…'**
  String get musicQrWaiting;

  /// No description provided for @musicQrScanned.
  ///
  /// In en, this message translates to:
  /// **'Scanned — confirm on your phone'**
  String get musicQrScanned;

  /// No description provided for @musicQrExpired.
  ///
  /// In en, this message translates to:
  /// **'The QR code expired. Start login again to get a new code.'**
  String get musicQrExpired;

  /// No description provided for @musicQrStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to refresh login status. Check the connection and retry.'**
  String get musicQrStatusFailed;

  /// No description provided for @musicQrRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get musicQrRetry;

  /// No description provided for @musicQrUnknownStatus.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String musicQrUnknownStatus(String status);

  /// No description provided for @videoLibraryOverviewTab.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get videoLibraryOverviewTab;

  /// No description provided for @videoLibraryScanReviewTab.
  ///
  /// In en, this message translates to:
  /// **'Scan and review'**
  String get videoLibraryScanReviewTab;

  /// No description provided for @videoLibraryAccessTab.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get videoLibraryAccessTab;

  /// No description provided for @videoLibraryVisibilityPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get videoLibraryVisibilityPrivate;

  /// No description provided for @videoLibraryVisibilityPrivateHint.
  ///
  /// In en, this message translates to:
  /// **'Only the creator sees this library in media views. Administrators can still manage it here.'**
  String get videoLibraryVisibilityPrivateHint;

  /// No description provided for @videoLibraryVisibilitySelected.
  ///
  /// In en, this message translates to:
  /// **'Selected users'**
  String get videoLibraryVisibilitySelected;

  /// No description provided for @videoLibraryVisibilitySelectedHint.
  ///
  /// In en, this message translates to:
  /// **'Only the users selected below can browse and play this library.'**
  String get videoLibraryVisibilitySelectedHint;

  /// No description provided for @videoLibraryVisibilityMembers.
  ///
  /// In en, this message translates to:
  /// **'All members'**
  String get videoLibraryVisibilityMembers;

  /// No description provided for @videoLibraryVisibilityMembersHint.
  ///
  /// In en, this message translates to:
  /// **'Members and administrators with media read access are included. Guests are not included automatically.'**
  String get videoLibraryVisibilityMembersHint;

  /// No description provided for @videoLibraryAccessSearch.
  ///
  /// In en, this message translates to:
  /// **'Search username or display name'**
  String get videoLibraryAccessSearch;

  /// No description provided for @videoLibraryAccessNoUsers.
  ///
  /// In en, this message translates to:
  /// **'No matching users'**
  String get videoLibraryAccessNoUsers;

  /// No description provided for @videoLibraryAccessSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} users selected'**
  String videoLibraryAccessSelectedCount(int count);

  /// No description provided for @videoLibraryAccessSave.
  ///
  /// In en, this message translates to:
  /// **'Save access'**
  String get videoLibraryAccessSave;

  /// No description provided for @videoLibraryAccessSaved.
  ///
  /// In en, this message translates to:
  /// **'Access settings saved'**
  String get videoLibraryAccessSaved;

  /// No description provided for @videoLibraryAccessLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load access settings'**
  String get videoLibraryAccessLoadFailed;

  /// No description provided for @videoLibraryAccessUsersFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load users'**
  String get videoLibraryAccessUsersFailed;

  /// No description provided for @videoLibrarySourceVisibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Visibility'**
  String get videoLibrarySourceVisibilityLabel;

  /// No description provided for @videoLibrarySourceLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Storage location'**
  String get videoLibrarySourceLocationLabel;

  /// No description provided for @videoLibrarySourcePathLabel.
  ///
  /// In en, this message translates to:
  /// **'Relative folder'**
  String get videoLibrarySourcePathLabel;

  /// No description provided for @videoLibrarySourceTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Media type'**
  String get videoLibrarySourceTypeLabel;

  /// No description provided for @adminTrustedMountUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No configured mount is available. Check application.yml or the environment variables, then restart the backend.'**
  String get adminTrustedMountUnavailable;

  /// No description provided for @adminChooseRelativeFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose relative folder'**
  String get adminChooseRelativeFolder;

  /// No description provided for @adminUseCurrentFolder.
  ///
  /// In en, this message translates to:
  /// **'Use current folder'**
  String get adminUseCurrentFolder;

  /// No description provided for @adminOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get adminOpenFolder;

  /// No description provided for @adminNoSubfolders.
  ///
  /// In en, this message translates to:
  /// **'This folder has no browsable subfolders'**
  String get adminNoSubfolders;

  /// No description provided for @readerComicCatalogItems.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String readerComicCatalogItems(int count);

  /// No description provided for @readerComicExpandAll.
  ///
  /// In en, this message translates to:
  /// **'Expand all'**
  String get readerComicExpandAll;

  /// No description provided for @readerComicCollapseAll.
  ///
  /// In en, this message translates to:
  /// **'Collapse all'**
  String get readerComicCollapseAll;

  /// No description provided for @photosViewSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch view'**
  String get photosViewSwitch;

  /// No description provided for @photosViewGridDay.
  ///
  /// In en, this message translates to:
  /// **'Grid · By day'**
  String get photosViewGridDay;

  /// No description provided for @photosViewGridMonth.
  ///
  /// In en, this message translates to:
  /// **'Grid · By month'**
  String get photosViewGridMonth;

  /// No description provided for @photosViewTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get photosViewTimeline;

  /// No description provided for @photosViewGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get photosViewGroups;

  /// No description provided for @photosToggleSelection.
  ///
  /// In en, this message translates to:
  /// **'Toggle selection'**
  String get photosToggleSelection;

  /// No description provided for @photosTrashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} items · automatically deleted after 30 days'**
  String photosTrashSubtitle(Object count);

  /// No description provided for @photosEmptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash'**
  String get photosEmptyTrash;

  /// No description provided for @photosRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get photosRestore;

  /// No description provided for @photosDeleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete Forever'**
  String get photosDeleteForever;

  /// No description provided for @photosEmptyTrashConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash?'**
  String get photosEmptyTrashConfirmTitle;

  /// No description provided for @photosEmptyTrashConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'All {count} photos in the trash will be permanently deleted. This cannot be undone.'**
  String photosEmptyTrashConfirmBody(Object count);

  /// No description provided for @photosDeleteForeverConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Forever?'**
  String get photosDeleteForeverConfirmTitle;

  /// No description provided for @photosDeleteForeverConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This photo will be permanently deleted. This cannot be undone.'**
  String get photosDeleteForeverConfirmBody;

  /// No description provided for @photosMoveToTrashTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash?'**
  String get photosMoveToTrashTitle;

  /// No description provided for @photosMoveToTrashBody.
  ///
  /// In en, this message translates to:
  /// **'{count} photos will be moved to the Trash. You can restore them within 30 days.'**
  String photosMoveToTrashBody(Object count);

  /// No description provided for @photosMoveToTrashBodyOne.
  ///
  /// In en, this message translates to:
  /// **'This photo will be moved to the Trash. You can restore it within 30 days.'**
  String get photosMoveToTrashBodyOne;

  /// No description provided for @photosMoveToTrashAction.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get photosMoveToTrashAction;

  /// No description provided for @photosTrashRestored.
  ///
  /// In en, this message translates to:
  /// **'Photo restored'**
  String get photosTrashRestored;

  /// No description provided for @photosTrashPurged.
  ///
  /// In en, this message translates to:
  /// **'Deleted permanently'**
  String get photosTrashPurged;

  /// No description provided for @photosTrashMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved to Trash'**
  String get photosTrashMoved;

  /// No description provided for @photosBackToPhotos.
  ///
  /// In en, this message translates to:
  /// **'Back to Photos'**
  String get photosBackToPhotos;

  /// No description provided for @photosPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get photosPlay;

  /// No description provided for @photosPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get photosPause;

  /// No description provided for @photosFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get photosFullscreen;

  /// No description provided for @photosStripHide.
  ///
  /// In en, this message translates to:
  /// **'HIDE'**
  String get photosStripHide;

  /// No description provided for @photosStripShow.
  ///
  /// In en, this message translates to:
  /// **'STRIP'**
  String get photosStripShow;

  /// No description provided for @photosIso.
  ///
  /// In en, this message translates to:
  /// **'ISO'**
  String get photosIso;

  /// No description provided for @photosTagsSelectHint.
  ///
  /// In en, this message translates to:
  /// **'Select a tag to browse its photos'**
  String get photosTagsSelectHint;

  /// No description provided for @photosTagsPhotoCount.
  ///
  /// In en, this message translates to:
  /// **'{count} photos'**
  String photosTagsPhotoCount(int count);

  /// No description provided for @photosLocationsBack.
  ///
  /// In en, this message translates to:
  /// **'Back to Locations'**
  String get photosLocationsBack;

  /// No description provided for @photosDeleteShort.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get photosDeleteShort;

  /// No description provided for @photosSaturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get photosSaturation;

  /// No description provided for @photosModuleDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Lightbox'**
  String get photosModuleDisplayName;

  /// No description provided for @photosSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get photosSelectAll;

  /// No description provided for @photosDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get photosDeselectAll;

  /// No description provided for @photosFrameNavPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photosFrameNavPhotos;

  /// No description provided for @photosFrameNavLocations.
  ///
  /// In en, this message translates to:
  /// **'Locations'**
  String get photosFrameNavLocations;

  /// No description provided for @photosFrameNavTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get photosFrameNavTags;

  /// No description provided for @photosFrameNavTrash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get photosFrameNavTrash;

  /// No description provided for @photosFrameLocationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No locations yet'**
  String get photosFrameLocationsEmpty;

  /// No description provided for @photosFrameLocationsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Photos with location details will appear here'**
  String get photosFrameLocationsEmptyHint;

  /// No description provided for @photosFrameTagsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get photosFrameTagsEmpty;

  /// No description provided for @photosFrameTagsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Photos you tag will appear here'**
  String get photosFrameTagsEmptyHint;

  /// No description provided for @photosFrameTrashEmpty.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get photosFrameTrashEmpty;

  /// No description provided for @photosFrameTrashEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Deleted photos stay here for 30 days'**
  String get photosFrameTrashEmptyHint;

  /// No description provided for @photosFrameStatsPhotos.
  ///
  /// In en, this message translates to:
  /// **'{count} photos'**
  String photosFrameStatsPhotos(Object count);

  /// No description provided for @photosFrameStatsMeta.
  ///
  /// In en, this message translates to:
  /// **'{albums} albums · {trash} in trash'**
  String photosFrameStatsMeta(Object albums, Object trash);

  /// No description provided for @photosInsightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Relationship insights'**
  String get photosInsightsTitle;

  /// No description provided for @photosAlbumsManage.
  ///
  /// In en, this message translates to:
  /// **'Manage albums'**
  String get photosAlbumsManage;

  /// No description provided for @photosExpandAlbums.
  ///
  /// In en, this message translates to:
  /// **'Show albums'**
  String get photosExpandAlbums;

  /// No description provided for @photosScrollToTop.
  ///
  /// In en, this message translates to:
  /// **'Back to top'**
  String get photosScrollToTop;

  /// No description provided for @photosRelCooccur.
  ///
  /// In en, this message translates to:
  /// **'{count} co-occurring photos'**
  String photosRelCooccur(Object count);

  /// No description provided for @photosRelOthers.
  ///
  /// In en, this message translates to:
  /// **'{count} more'**
  String photosRelOthers(Object count);

  /// No description provided for @photosRelRelated.
  ///
  /// In en, this message translates to:
  /// **'Related to \"{name}\"'**
  String photosRelRelated(Object name);

  /// No description provided for @photosRelCooccurTitle.
  ///
  /// In en, this message translates to:
  /// **'Related entities'**
  String get photosRelCooccurTitle;

  /// No description provided for @photosRelHint.
  ///
  /// In en, this message translates to:
  /// **'Tap an entity to inspect relations; View all filters the library by that entity.'**
  String get photosRelHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
