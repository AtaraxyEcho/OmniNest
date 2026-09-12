// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'OmniNest';

  @override
  String get mobileNavHome => 'Home';

  @override
  String get mobileNavFiles => 'Files';

  @override
  String get mobileNavMusic => 'Music';

  @override
  String get mobileNavVisual => 'Visual';

  @override
  String get mobileNavReader => 'Reading';

  @override
  String get mobileActivityCenter => 'Activity';

  @override
  String get mobileOfflineBanner =>
      'You are offline. Some actions are unavailable.';

  @override
  String get fullscreenEnterShortcut => 'Full screen (F11)';

  @override
  String get fullscreenExitShortcut => 'Exit full screen (F11)';

  @override
  String get searchTitle => 'Search';

  @override
  String get searchHint => 'Search files, books, videos…';

  @override
  String get searchEmptyQuery => 'Enter keywords to start searching';

  @override
  String get searchEmptyResult => 'No matching results found';

  @override
  String get searchFailed => 'Search failed';

  @override
  String get searchScopeAll => 'All';

  @override
  String get searchGroupFile => 'Files';

  @override
  String get searchGroupBook => 'Books';

  @override
  String get searchGroupVideo => 'Videos';

  @override
  String get searchGroupMusic => 'Music';

  @override
  String get searchGroupPhoto => 'Photos';

  @override
  String get tasksTitle => 'Tasks';

  @override
  String get tasksEmpty => 'No tasks';

  @override
  String get tasksEmptyHint => 'System tasks will appear here';

  @override
  String get tasksFilterAll => 'All';

  @override
  String get tasksFilterPending => 'Pending';

  @override
  String get tasksFilterRunning => 'Running';

  @override
  String get tasksFilterCompleted => 'Completed';

  @override
  String get tasksFilterFailed => 'Failed';

  @override
  String get tasksRetry => 'Retry';

  @override
  String get tasksStatusPending => 'Pending';

  @override
  String get tasksStatusRunning => 'Running';

  @override
  String get tasksStatusCompleted => 'Done';

  @override
  String get tasksStatusFailed => 'Failed';

  @override
  String get tasksRetryCount => 'Retry';

  @override
  String tasksRetryProgress(Object current, Object maximum) {
    return 'Retries: $current/$maximum';
  }

  @override
  String get tasksStatusRetryWait => 'Waiting to retry';

  @override
  String get tasksStatusNeedsAttention => 'Needs attention';

  @override
  String get tasksStatusCancelled => 'Cancelled';

  @override
  String get tasksPhasePlanning => 'Planning resource deletion';

  @override
  String get tasksPhaseDeletingObjects => 'Deleting object data';

  @override
  String get tasksPhaseVerifyingReferences => 'Checking resource references';

  @override
  String get tasksPhaseFinalizingDatabase => 'Cleaning up business data';

  @override
  String get tasksPhaseWaiting => 'Waiting for progress';

  @override
  String get tasksTimeJustNow => 'Just now';

  @override
  String tasksTimeMinutesAgo(Object count) {
    return '$count min ago';
  }

  @override
  String tasksTimeHoursAgo(Object count) {
    return '$count hr ago';
  }

  @override
  String tasksTimeDaysAgo(Object count) {
    return '$count days ago';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String settingsLoadFailed(Object error) {
    return 'Failed to load: $error';
  }

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageChinese => 'Chinese';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsNotification => 'Notifications';

  @override
  String get settingsNotificationEnable => 'Enable notifications';

  @override
  String get settingsNotificationEnableHint => 'Receive push notifications';

  @override
  String get settingsEmailNotification => 'Email notifications';

  @override
  String get settingsEmailNotificationHint =>
      'Receive important notifications via email';

  @override
  String get settingsSyncOffline => 'Sync and offline';

  @override
  String get settingsSyncOfflineHint =>
      'Manage online sync status and offline content';

  @override
  String get settingsSecurity => 'Security and devices';

  @override
  String get settingsSecurityHint => 'Manage your password and active sessions';

  @override
  String get settingsAbout => 'About OmniNest';

  @override
  String get settingsAboutHint => 'Version 0.1.0';

  @override
  String get setupTitle => 'Initial Setup';

  @override
  String get setupSubtitle =>
      'Create the super administrator account for this OmniNest instance.';

  @override
  String get setupUnavailableTitle => 'Setup is not ready';

  @override
  String get setupUnavailableMessage =>
      'Configure OMNINEST_SETUP_TOKEN with at least 32 characters on the server, then restart the backend.';

  @override
  String get setupToken => 'Setup token';

  @override
  String get setupTokenHint => 'Enter the setup token configured on the server';

  @override
  String get setupInstanceName => 'Instance name';

  @override
  String get setupInstanceNameRequired => 'Enter an instance name';

  @override
  String get setupDefaultLocale => 'Default locale';

  @override
  String get setupDefaultTimezone => 'Default time zone';

  @override
  String get setupDisplayName => 'Display name';

  @override
  String get setupEmail => 'Email (optional)';

  @override
  String get setupConfirmPassword => 'Confirm password';

  @override
  String get setupPasswordLength =>
      'The super administrator password must be between 8 and 24 characters';

  @override
  String get setupTwoFactorSection => 'Two-Factor Verification';

  @override
  String get setupTwoFactorHint =>
      'This deployment requires two-factor verification for the super administrator: scan the QR code with an authenticator app and enter the 6-digit code to finish setup.';

  @override
  String get setupTwoFactorGenerate => 'Generate QR code';

  @override
  String get setupTwoFactorRegenerate => 'Regenerate secret';

  @override
  String get setupTwoFactorGenerateFirst =>
      'Generate the two-factor QR code and enter the verification code first';

  @override
  String get setupTwoFactorGoLogin => 'Backup codes saved, continue to sign in';

  @override
  String get setupPasswordMismatch => 'Passwords do not match';

  @override
  String get setupCreateAdmin => 'Create super administrator';

  @override
  String get setupRetryStatus => 'Check again';

  @override
  String get setupStatusFailed => 'Unable to read setup status';

  @override
  String get setupCreateFailed => 'Failed to create super administrator';

  @override
  String get setupSecureNotice =>
      'The setup token is only used for initialization and is not stored on this device.';

  @override
  String get setupLanguageSelector => 'Language';

  @override
  String get setupSectionInstance => 'Instance';

  @override
  String get setupSectionAdmin => 'Administrator account';

  @override
  String get setupFeatureFiles => 'Files · multi-provider storage';

  @override
  String get setupFeatureMedia => 'Video · music · photos';

  @override
  String get setupFeatureReader => 'Reader · offline sync';

  @override
  String get adminSearchHint => 'Search…';

  @override
  String get adminNoMatch => 'No matching data found.';

  @override
  String get notificationTitle => 'Notifications';

  @override
  String notificationTitleWithCount(Object count) {
    return 'Notifications ($count)';
  }

  @override
  String get notificationNoTitle => 'No title';

  @override
  String get notificationEmpty => 'No notifications';

  @override
  String get notificationEmptyHint => 'New notifications will appear here';

  @override
  String get notificationMarkAllRead => 'Mark all read';

  @override
  String get notificationDelete => 'Delete notification';

  @override
  String get notificationClearAll => 'Clear notifications';

  @override
  String get notificationClearConfirmTitle => 'Clear all notifications?';

  @override
  String get notificationClearConfirmMessage =>
      'This permanently deletes every notification for the current account.';

  @override
  String get notificationDeleteFailed =>
      'Failed to delete notification. Try again.';

  @override
  String get notificationClearFailed =>
      'Failed to clear notifications. Try again.';

  @override
  String get notificationTypeCompleted => 'Done';

  @override
  String get notificationTypeFailed => 'Failed';

  @override
  String get notificationTypeShare => 'Share';

  @override
  String get notificationTypeTaskCompleted => 'Task Completed';

  @override
  String get notificationTypeTaskCompletedDesc =>
      'Async task completed successfully';

  @override
  String get notificationTypeTaskFailed => 'Task Failed';

  @override
  String get notificationTypeTaskFailedDesc => 'Async task execution failed';

  @override
  String get notificationTypeShareAccess => 'Share Access';

  @override
  String get notificationTypeShareAccessDesc =>
      'Someone accessed your share link';

  @override
  String get notificationTypeSystemMessage => 'System Message';

  @override
  String get notificationTypeSystemMessageDesc => 'System-level notification';

  @override
  String get notificationTypeMetadataScrape => 'Metadata Scrape';

  @override
  String get notificationTypeMetadataScrapeDesc =>
      'Media metadata scraping completed';

  @override
  String get notificationTypeShareVisited => 'Share Visited';

  @override
  String get notificationTypeShareVisitedDesc => 'Your share link was visited';

  @override
  String get notificationTypeStorageWarning => 'Storage Warning';

  @override
  String get notificationTypeStorageWarningDesc =>
      'Storage usage is running high';

  @override
  String get notificationTypeNewDeviceLogin => 'New Device Login';

  @override
  String get notificationTypeNewDeviceLoginDesc => 'New device login detected';

  @override
  String get notificationTypePasswordChanged => 'Password Changed';

  @override
  String get notificationTypePasswordChangedDesc =>
      'Account password was changed';

  @override
  String get notificationTypesHeader => 'Notification Types';

  @override
  String get notificationTimeNow => 'Just now';

  @override
  String notificationTimeMinutes(Object n) {
    return '$n min ago';
  }

  @override
  String notificationTimeHours(Object n) {
    return '$n hr ago';
  }

  @override
  String notificationTimeDays(Object n) {
    return '$n days ago';
  }

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileBackTooltip => 'Back to Portal';

  @override
  String get profileAvatarFormatError =>
      'Only JPG, PNG, WebP formats are supported';

  @override
  String get profileAvatarSizeError => 'Avatar size cannot exceed 5MB';

  @override
  String get profileAvatarSuccess => 'Avatar updated successfully';

  @override
  String get profileAvatarFailed => 'Avatar upload failed, please retry';

  @override
  String get profileEditAvatar => 'Change avatar';

  @override
  String get profileUnknownUser => 'Unknown';

  @override
  String get profileEmailNotSet => 'Email not set';

  @override
  String get profileRole => 'Role';

  @override
  String get profileRoleSuperAdmin => 'Super Admin';

  @override
  String get profileRoleAdmin => 'Admin';

  @override
  String get profileRoleMember => 'Member';

  @override
  String get profileUnreadNotifications => 'Unread notifications';

  @override
  String get profileLastLogin => 'Last login';

  @override
  String get profileToday => 'Today';

  @override
  String get profileAccountStatus => 'Account status';

  @override
  String get profileStatusNormal => 'Active';

  @override
  String get profileAccountInfo => 'Account Info';

  @override
  String get profileSectionAccount => 'Account';

  @override
  String get profileSectionAppearance => 'Appearance & language';

  @override
  String get profileSectionNotifications => 'Notifications';

  @override
  String get profileSectionSecurity => 'Security & devices';

  @override
  String get profileSectionAbout => 'About';

  @override
  String get profileManageBackdrop => 'Manage background';

  @override
  String get profileUsername => 'Username';

  @override
  String get profileEmail => 'Email';

  @override
  String get profileUserId => 'User ID';

  @override
  String get profileChangePassword => 'Change Password';

  @override
  String get profileChangePasswordSubtitle => 'Update your account password';

  @override
  String get profileWeatherCity => 'Weather City';

  @override
  String get profileWeatherCityHint =>
      'Set the weather display city, leave empty to use GPS or system default';

  @override
  String get profileWeatherCityPlaceholder =>
      'Enter city name, e.g. Beijing, Shanghai';

  @override
  String get profileWeatherCitySave => 'Save';

  @override
  String get profileWeatherCityNotSet => 'Not set (GPS / System default)';

  @override
  String profileWeatherCitySaveFailed(Object error) {
    return 'Failed to save city preference: $error';
  }

  @override
  String get profileNotificationSettings => 'Notification Settings';

  @override
  String get profileNotificationMasterSwitch => 'Master Switch';

  @override
  String get profileNotificationMasterSwitchHint =>
      'Disable to stop all notifications';

  @override
  String get profileNotificationTypesLoadFailed =>
      'Failed to load notification types';

  @override
  String get profileNotificationSaveFailed =>
      'Failed to save notification preferences. Try again.';

  @override
  String get profileNotificationSound => 'Sound';

  @override
  String get profileNotificationSoundHint => 'Play sound on notification';

  @override
  String get profileNotificationPreview => 'Notification Preview';

  @override
  String get profileNotificationPreviewHint =>
      'Show message content in notifications';

  @override
  String profileNotificationTypes(Object count) {
    return 'Notification Types ($count)';
  }

  @override
  String profileLoadFailed(Object error) {
    return 'Failed to load: $error';
  }

  @override
  String get profileSessionManagement => 'Session Management';

  @override
  String get profileSessionManagementSubtitle =>
      'View and manage current login sessions';

  @override
  String get profileActiveSessions => 'Active Sessions';

  @override
  String get profileNoSessions => 'No active sessions';

  @override
  String get profileSessionDevice => 'Device';

  @override
  String get profileSessionIp => 'IP Address';

  @override
  String get profileSessionLastActive => 'Last Active';

  @override
  String get profileSessionExpires => 'Expires';

  @override
  String get profileRevokeSession => 'Revoke Session';

  @override
  String get profileRevokeSessionConfirm => 'Revoke Session?';

  @override
  String get profileRevokeSessionMessage =>
      'The device will be forcibly signed out and will need to sign in again.';

  @override
  String get profileSessionRevoked => 'Session revoked';

  @override
  String get profileSessionRevokeFailed => 'Revocation failed, please retry';

  @override
  String get profileSessionsLoadFailed => 'Failed to load sessions';

  @override
  String get profileSessionCurrentDevice => 'Current Device';

  @override
  String get changePasswordOldPassword => 'Current Password';

  @override
  String get changePasswordNewPassword => 'New Password';

  @override
  String get changePasswordEnterNew => 'Please enter new password';

  @override
  String get changePasswordMinLength =>
      'Password must be at least 8 characters';

  @override
  String get changePasswordMaxLength =>
      'Password must be at most 24 characters';

  @override
  String get changePasswordConfirmNew => 'Confirm New Password';

  @override
  String get loginTwoFactorTitle => 'Two-Factor Verification';

  @override
  String get loginTwoFactorSubtitle =>
      'Enter the 6-digit code from your authenticator app to sign in';

  @override
  String get loginTwoFactorCodeLabel => 'Verification code';

  @override
  String get loginTwoFactorCodeHint => 'Enter the 6-digit code';

  @override
  String get loginTwoFactorUseBackupHint =>
      'You can also enter a one-time backup code (XXXX-XXXX)';

  @override
  String get loginTwoFactorVerifyAndSignIn => 'Verify and sign in';

  @override
  String get loginTwoFactorBackToLogin => 'Back to sign in';

  @override
  String get twoFactorEnrollTitle => 'Set Up Two-Factor Verification';

  @override
  String get twoFactorEnrollSubtitle =>
      'Your role requires two-factor verification. Complete setup to continue';

  @override
  String get twoFactorEnrollPasswordLabel => 'Login password';

  @override
  String get twoFactorEnrollPasswordHint => 'Enter your login password';

  @override
  String get twoFactorEnrollContinue => 'Next: scan QR code';

  @override
  String get twoFactorEnrollScanHint =>
      'Scan the QR code with your authenticator app, or copy the secret to add it manually';

  @override
  String get twoFactorEnrollSecretLabel => 'Copy secret';

  @override
  String get twoFactorEnrollConfirmCode => 'Confirm and enable';

  @override
  String get twoFactorEnrollBackupTitle => 'Backup codes';

  @override
  String get twoFactorEnrollBackupHint =>
      'These one-time backup codes are shown only once. Save them to recover access if you lose your authenticator.';

  @override
  String get twoFactorEnrollBackupSavedCheck => 'I have saved the backup codes';

  @override
  String get twoFactorEnrollSavedAndFinish => 'Finish and sign in';

  @override
  String get twoFactorCopied => 'Copied to clipboard';

  @override
  String get twoFactorCopyCodes => 'Copy all backup codes';

  @override
  String get twoFactorDisableHint =>
      'After disabling, sign-in will no longer require a verification code.';

  @override
  String get profileTwoFactorTitle => 'Two-Factor Verification';

  @override
  String get profileTwoFactorSubtitle =>
      'Protect sign-in with one-time verification codes';

  @override
  String get profileTwoFactorEnabled => 'Enabled';

  @override
  String get profileTwoFactorDisabled => 'Not enabled';

  @override
  String get profileTwoFactorRequiredBadge =>
      'Required for your role but not enabled yet';

  @override
  String get profileTwoFactorEnableAction => 'Enable';

  @override
  String get profileTwoFactorDisableAction => 'Disable';

  @override
  String get profileTwoFactorDisableConfirm => 'Disable it';

  @override
  String get profileTwoFactorLoadFailed => 'Failed to load status';

  @override
  String get changePasswordMismatch => 'Passwords do not match';

  @override
  String get changePasswordCancel => 'Cancel';

  @override
  String get changePasswordConfirm => 'Confirm';

  @override
  String get changePasswordSuccess => 'Password changed successfully';

  @override
  String get changePasswordWrongOld => 'Incorrect current password';

  @override
  String get changePasswordFailed => 'Password change failed, please retry';

  @override
  String changePasswordEnterField(Object field) {
    return 'Please enter $field';
  }

  @override
  String get loginWelcome => 'Welcome Back';

  @override
  String get loginDescription => 'Sign in with your OmniNest account.';

  @override
  String get loginSubtitle =>
      'Consolidate family media, reading, files, and automation tasks into one stable personal space.';

  @override
  String get loginFeatureMedia => 'Media Center';

  @override
  String get loginFeatureReader => 'Book Library';

  @override
  String get loginFeatureFiles => 'File Manager';

  @override
  String get loginFeatureAdmin => 'Admin Console';

  @override
  String get loginUsername => 'Username';

  @override
  String get loginUsernameHint => 'Please enter username';

  @override
  String get loginPassword => 'Password';

  @override
  String get loginShowPassword => 'Show password';

  @override
  String get loginHidePassword => 'Hide password';

  @override
  String get loginPasswordHint => 'Please enter password';

  @override
  String get loginSigningIn => 'Signing in...';

  @override
  String get loginSignIn => 'Sign In';

  @override
  String get loginFailed => 'Login failed, please try again later';

  @override
  String get loginConnectionError =>
      'Cannot connect to backend, please confirm the service is running';

  @override
  String get loginRequestFailed =>
      'Login request failed, please check your account or network';

  @override
  String get coreRetry => 'Retry';

  @override
  String get coreStartupFailed => 'Startup failed';

  @override
  String get coreStartupFailedHint =>
      'A runtime dependency could not be initialized. Retry, then check the local media components and application logs if the problem continues.';

  @override
  String get coreCancel => 'Cancel';

  @override
  String get coreConfirm => 'Confirm';

  @override
  String get coreSave => 'Save';

  @override
  String get coreClose => 'Close';

  @override
  String get coreBack => 'Back';

  @override
  String get coreDelete => 'Delete';

  @override
  String get coreClear => 'Clear';

  @override
  String get coreChooseDate => 'Choose date';

  @override
  String get corePlay => 'Play';

  @override
  String get corePause => 'Pause';

  @override
  String get corePrevious => 'Previous';

  @override
  String get coreNext => 'Next';

  @override
  String get coreShowPassword => 'Show password';

  @override
  String get coreHidePassword => 'Hide password';

  @override
  String get coreSearchHint => 'Search…';

  @override
  String get coreProfile => 'Profile';

  @override
  String get coreStorage => 'Storage';

  @override
  String get coreAdmin => 'Admin';

  @override
  String get coreSignOut => 'Sign Out';

  @override
  String get coreMenu => 'Menu';

  @override
  String get coreMore => 'More actions';

  @override
  String get coreTheme => 'Theme';

  @override
  String get coreThemeLight => 'Light';

  @override
  String get coreThemeDark => 'Dark';

  @override
  String get coreLanguage => 'Language';

  @override
  String get coreRoleSuperAdmin => 'Admin';

  @override
  String get coreRoleAdmin => 'Mod';

  @override
  String get coreRoleMember => 'Member';

  @override
  String get filesAllFiles => 'All Files';

  @override
  String get filesRecent => 'Recent';

  @override
  String get filesFavorites => 'Favorites';

  @override
  String get filesRecycleBin => 'Recycle Bin';

  @override
  String get filesSharedWithMe => 'Shared With Me';

  @override
  String get filesMyShares => 'My Shares';

  @override
  String get filesShareManagement => 'Share Link Management';

  @override
  String get filesStorageStats => 'Storage Statistics';

  @override
  String get filesUploadQueue => 'Upload Queue';

  @override
  String get filesOfflineDownloads => 'Offline Downloads';

  @override
  String get filesExternalStorage => 'External Storage';

  @override
  String get filesImportTasks => 'Import Tasks';

  @override
  String get filesAllFilesDesc =>
      'Browse root or specified directory to manage folders, files and paths.';

  @override
  String get filesRecentDesc =>
      'View recently opened or downloaded files sorted by access time.';

  @override
  String get filesFavoritesDesc =>
      'View starred files in one place, ideal for frequently used materials.';

  @override
  String get filesRecycleBinDesc =>
      'View soft-deleted files, supports restore or permanent delete.';

  @override
  String get filesSharedWithMeDesc =>
      'View files shared to your account by other users.';

  @override
  String get filesMySharesDesc => 'View share links created by you.';

  @override
  String get filesShareManagementDesc =>
      'Manage active, expired or revoked share links.';

  @override
  String get filesStorageStatsDesc =>
      'View capacity, quota, file type distribution and space usage.';

  @override
  String get filesUploadQueueDesc =>
      'View multipart upload sessions, resume progress and upload status.';

  @override
  String get filesOfflineDownloadsDesc =>
      'Manage HTTP, BT and magnet offline download tasks.';

  @override
  String get filesExternalStorageDesc =>
      'Manage OneDrive, WebDAV and other third-party storage mounts.';

  @override
  String get filesImportTasksDesc =>
      'View external storage file import progress, supports cancelling queued tasks.';

  @override
  String get filesSharedSpace => 'Shared Space';

  @override
  String get filesSharedSpaceDesc => 'All users shared file space';

  @override
  String get filesSharedSpaceUsage => 'Shared Space Usage';

  @override
  String get filesSharedSpaceEmpty => 'No files in shared space';

  @override
  String get filesMoveToShared => 'Move to Shared Space';

  @override
  String get filesMoveToSharedConfirm => 'Move to Shared Space';

  @override
  String filesMoveToSharedMessage(Object name) {
    return 'Move \"$name\" to shared space? All users will see it.';
  }

  @override
  String get filesMoveToPersonal => 'Move to Personal Space';

  @override
  String get filesMoveToPersonalConfirm => 'Move to Personal Space';

  @override
  String filesMoveToPersonalMessage(Object name) {
    return 'Move \"$name\" to personal space?';
  }

  @override
  String get filesMoveToPersonalLabel => 'Move back';

  @override
  String get filesCount => 'files';

  @override
  String get filesCategoryAll => 'All';

  @override
  String get filesCategoryImage => 'Images';

  @override
  String get filesCategoryVideo => 'Videos';

  @override
  String get filesCategoryAudio => 'Audio';

  @override
  String get filesCategoryDocument => 'Documents';

  @override
  String get filesCategoryNovel => 'Novels';

  @override
  String get filesCategoryComic => 'Comics';

  @override
  String get filesCategoryArchive => 'Archives';

  @override
  String get filesCategoryOther => 'Other';

  @override
  String get filesGroupFiles => 'Files';

  @override
  String get filesGroupSharing => 'Sharing';

  @override
  String get filesGroupTransfer => 'Transfers';

  @override
  String get filesGroupStorage => 'Storage';

  @override
  String get filesNavFiles => 'Files';

  @override
  String get filesNavRecent => 'Recent';

  @override
  String get filesNavShared => 'Shared';

  @override
  String get filesNavRecycleBin => 'Recycle Bin';

  @override
  String get filesOpenFileMenu => 'Open file menu';

  @override
  String get filesSearch => 'Search';

  @override
  String get filesRefresh => 'Refresh';

  @override
  String get filesSearchFiles => 'Search Files';

  @override
  String get filesSearchHint => 'Enter filename, path or type';

  @override
  String get filesStorageUsage => 'Storage Usage';

  @override
  String get filesWaitingStats => 'Waiting for statistics';

  @override
  String get filesUnlimited => 'Unlimited';

  @override
  String get filesUnlimitedQuota => 'Unlimited quota';

  @override
  String filesUsedPercent(Object percent, Object remaining) {
    return '$percent% used · $remaining remaining';
  }

  @override
  String filesUsedOf(Object total, Object used) {
    return '$used / $total';
  }

  @override
  String get filesStorageSpace => 'Storage Space';

  @override
  String get filesFolders => 'Folders';

  @override
  String get filesFiles => 'Files';

  @override
  String get filesCapacity => 'Capacity';

  @override
  String get filesCurrentView => 'Current View';

  @override
  String get filesCurrentViewTotal => 'Current View Total';

  @override
  String get filesSoftDeleted => 'Soft Deleted Files';

  @override
  String get filesEmpty => 'No files';

  @override
  String get filesRecycleBinEmpty => 'Recycle bin is empty';

  @override
  String get filesCameraTakePhoto => 'Take Photo & Upload';

  @override
  String get filesCameraRecordVideo => 'Record Video & Upload';

  @override
  String get filesUploadFile => 'Upload File';

  @override
  String filesLoadMore(Object loaded, Object total) {
    return 'Load more ($loaded / $total loaded)';
  }

  @override
  String get filesDropToUpload => 'Drop files here to upload';

  @override
  String filesUploadProcessing(Object count, Object progress) {
    return 'Processing $count files · Progress $progress';
  }

  @override
  String get filesViewAll => 'View All';

  @override
  String get filesCollapseQueue => 'Collapse upload queue';

  @override
  String get filesExpandQueue => 'Expand upload queue';

  @override
  String filesMoreInQueue(Object count) {
    return '$count more tasks in upload queue';
  }

  @override
  String get filesSortBy => 'Sort By';

  @override
  String get filesSortName => 'Name';

  @override
  String get filesSortTime => 'Time';

  @override
  String get filesSortSize => 'Size';

  @override
  String get filesNewFolder => 'New Folder';

  @override
  String get filesCreate => 'Create';

  @override
  String get filesFolderName => 'Folder Name';

  @override
  String get filesRename => 'Rename';

  @override
  String get filesSave => 'Save';

  @override
  String get filesFileName => 'Filename';

  @override
  String get filesFolder => 'Folder';

  @override
  String get filesMoveToRecycleBin => 'Move to Recycle Bin';

  @override
  String get filesPurge => 'Permanently Delete';

  @override
  String get filesCopyToEllipsis => 'Copy to…';

  @override
  String filesCopiedFile(Object name) {
    return 'Copied \"$name\"';
  }

  @override
  String get filesCopyFailed => 'Copy failed';

  @override
  String get filesMoveToEllipsis => 'Move to…';

  @override
  String get filesDownload => 'Download';

  @override
  String get filesShare => 'Share';

  @override
  String get filesOpen => 'Open';

  @override
  String get filesPreview => 'Preview';

  @override
  String get filesRestore => 'Restore';

  @override
  String get filesMoreActions => 'More Actions';

  @override
  String get filesMoreSections => 'More Sections';

  @override
  String get filesFilterSort => 'Sort & Filter';

  @override
  String get filesSwitchView => 'Switch View';

  @override
  String get filesFileActions => 'File Actions';

  @override
  String filesDeleteConfirmTitle(Object name) {
    return 'Move to Recycle Bin?';
  }

  @override
  String filesDeleteConfirmMessage(Object name) {
    return '\"$name\" will be removed from the file list and associated records in video, music and other modules will be cleaned up.';
  }

  @override
  String filesPurgeConfirmTitle(Object name) {
    return 'Permanently Delete?';
  }

  @override
  String filesPurgeConfirmMessage(Object name) {
    return '\"$name\" will be permanently deleted from the recycle bin. This action cannot be undone.';
  }

  @override
  String filesSelectedCount(Object count) {
    return '$count selected';
  }

  @override
  String get filesSelectAll => 'Select All';

  @override
  String get filesDeselect => 'Deselect';

  @override
  String get filesBatchRestore => 'Batch Restore';

  @override
  String get filesBatchPurge => 'Batch Purge';

  @override
  String get filesBatchMove => 'Batch Move';

  @override
  String get filesBatchDelete => 'Batch Delete';

  @override
  String get filesBatchAddFavorite => 'Batch Favorite';

  @override
  String get filesBatchRemoveFavorite => 'Batch Unfavorite';

  @override
  String get filesAddFavorite => 'Favorite';

  @override
  String get filesRemoveFavorite => 'Unfavorite';

  @override
  String get filesBatchRestoreTitle => 'Batch Restore?';

  @override
  String filesBatchRestoreMessage(Object count) {
    return 'Will restore $count selected files.';
  }

  @override
  String get filesBatchPurgeTitle => 'Batch Permanently Delete?';

  @override
  String filesBatchPurgeMessage(Object count) {
    return '$count selected files will be permanently deleted. This action cannot be undone.';
  }

  @override
  String get filesBatchDeleteTitle => 'Batch Move to Recycle Bin?';

  @override
  String filesBatchDeleteMessage(Object count) {
    return '$count selected files will be moved to the recycle bin.';
  }

  @override
  String get filesDownloadLinkCopied => 'Download link copied to clipboard';

  @override
  String get filesDownloadFailed => 'Failed to get download link';

  @override
  String filesMovedFile(Object name) {
    return 'Moved \"$name\"';
  }

  @override
  String filesMovedCount(Object count) {
    return 'Moved $count files';
  }

  @override
  String filesUploadComplete(Object count) {
    return '$count files uploaded';
  }

  @override
  String filesUploadBatchSummary(
    Object completed,
    Object conflicts,
    Object failed,
    Object paused,
  ) {
    return '$completed uploaded, $conflicts conflicted, $failed failed, $paused paused';
  }

  @override
  String get filesSelectTargetFolder => 'Select Target Folder';

  @override
  String get filesRootDirectory => 'Root Directory';

  @override
  String get filesGoToParent => 'Go to parent folder';

  @override
  String get filesFolderEmpty => 'This folder is empty';

  @override
  String filesMoveToFolder(Object name) {
    return 'Move to \"$name\"';
  }

  @override
  String get filesStatusQueued => 'Queued';

  @override
  String get filesStatusUploading => 'Uploading';

  @override
  String get filesStatusPaused => 'Paused';

  @override
  String get filesStatusFailed => 'Failed';

  @override
  String get filesStatusCompleted => 'Completed';

  @override
  String get filesStatusCancelled => 'Cancelled';

  @override
  String get filesStatusCancelling => 'Cancelling';

  @override
  String get filesOfflineEmpty => 'No offline download tasks';

  @override
  String get filesNewOfflineDownload => 'New Offline Download';

  @override
  String get filesDownloadLink => 'Download Link';

  @override
  String get filesOfflineDownloadHint =>
      'Supports HTTP, BT torrent and magnet links';

  @override
  String get filesNewTask => 'New Task';

  @override
  String get filesCancelTask => 'Cancel Task';

  @override
  String get filesTaskEnded => 'Task Ended';

  @override
  String get filesCancelOfflineConfirm => 'Cancel Offline Download?';

  @override
  String filesCancelOfflineMessage(Object name) {
    return '\"$name\" download will stop. Unfinished data won\'t be imported.';
  }

  @override
  String get filesNoExternalStorage => 'No external storage';

  @override
  String get filesAddMount => 'Add Mount';

  @override
  String get filesEdit => 'Edit';

  @override
  String get filesBrowseRemote => 'Browse Remote Files';

  @override
  String get filesDisableMount => 'Disable Mount';

  @override
  String get filesDisableMountConfirm => 'Disable External Mount?';

  @override
  String filesDisableMountMessage(Object name) {
    return '\"$name\" will no longer participate in file mount and sync.';
  }

  @override
  String get filesDeleteMount => 'Delete Mount';

  @override
  String get filesDeleteMountConfirm => 'Delete External Mount?';

  @override
  String filesDeleteMountMessage(Object name) {
    return 'Will permanently delete \"$name\" and its rclone configuration. This action cannot be undone.';
  }

  @override
  String get filesCloseBrowse => 'Close Browse';

  @override
  String get filesDirectoryEmpty => 'This directory is empty';

  @override
  String get filesEnterFolder => 'Enter Folder';

  @override
  String get filesImportFile => 'Import This File';

  @override
  String get filesImportFolder => 'Import Entire Folder';

  @override
  String get filesImportConfirm => 'Import External Content?';

  @override
  String filesImportMessage(Object name) {
    return 'Import \"$name\" to current file directory.';
  }

  @override
  String get filesImport => 'Import';

  @override
  String get filesNoImportTasks => 'No import tasks';

  @override
  String get filesCancelImportConfirm => 'Cancel Import Task?';

  @override
  String filesCancelImportMessage(Object name) {
    return '\"$name\" import will be cancelled.';
  }

  @override
  String get filesDeleteRecord => 'Delete Record';

  @override
  String get filesDeleteImportConfirm => 'Delete Import Record?';

  @override
  String filesDeleteImportMessage(Object name) {
    return '\"$name\" import record will be deleted.';
  }

  @override
  String get filesNoSharedFiles => 'No shared files';

  @override
  String filesFromUser(Object userId) {
    return 'From $userId';
  }

  @override
  String get filesLongTerm => 'Long term';

  @override
  String get filesHasExpiry => 'Has expiry';

  @override
  String get filesShareMgmt => 'Share Management';

  @override
  String get filesShareMgmtDesc =>
      'Manage share links created by you. Revocable.';

  @override
  String get filesNoShareLinks => 'No share links';

  @override
  String filesLoadFailed(Object error) {
    return 'Failed to load: $error';
  }

  @override
  String get filesAccessUnlimited => 'Unlimited';

  @override
  String get filesShareActive => 'Active';

  @override
  String get filesShareRevoked => 'Revoked';

  @override
  String get filesShareExpired => 'Expired';

  @override
  String get filesShareExhausted => 'Exhausted';

  @override
  String get filesRevokeShare => 'Revoke Share';

  @override
  String get filesRevokeShareConfirm => 'Revoke Share?';

  @override
  String filesRevokeShareMessage(Object name) {
    return '\"$name\" share link will be invalidated. People with the link can no longer access.';
  }

  @override
  String get filesClose => 'Close';

  @override
  String get filesWaitingUpload => 'Waiting to upload';

  @override
  String get filesDirectUploading => 'Direct uploading';

  @override
  String get filesMultipartUploading => 'Multipart uploading';

  @override
  String get filesUploadPausedMsg => 'Paused, can resume';

  @override
  String get filesUploadPausePending => 'Stopping the current transfer';

  @override
  String get filesResumingUpload => 'Resuming upload';

  @override
  String get filesUploadRetrying => 'Cleanup complete. Retrying upload';

  @override
  String get filesUploadDone => 'Upload complete';

  @override
  String filesUploadedParts(Object current, Object total) {
    return 'Uploaded $current/$total parts';
  }

  @override
  String get filesCleanupConflict => 'Clean up same-name file in recycle bin?';

  @override
  String get filesCleanupMessage =>
      'Same-name file exists in recycle bin. Will auto re-upload after cleanup.';

  @override
  String get filesCleanupAndRetry => 'Clean up and retry';

  @override
  String get filesDeleteUploadTask => 'Delete Upload Task?';

  @override
  String get filesDeleteUploadTaskMessage =>
      'The upload task will be removed from the queue. Unfinished server sessions will be cancelled.';

  @override
  String get filesDeleteTask => 'Delete Task';

  @override
  String get filesEditExternalStorage => 'Edit External Storage';

  @override
  String get filesAddExternalStorage => 'Add External Storage';

  @override
  String get externalStorageSpace => 'Space Usage';

  @override
  String get externalMkdir => 'Create Directory';

  @override
  String get externalMkdirHint => 'Enter directory path, e.g. /photos/2024';

  @override
  String get externalDeleteFile => 'Delete';

  @override
  String get externalRenameFile => 'Rename';

  @override
  String get externalDeleteConfirm =>
      'Delete this remote file? This cannot be undone.';

  @override
  String externalSpaceUsedOf(Object used, Object total) {
    return '$used / $total';
  }

  @override
  String get filesStorageType => 'Storage Type';

  @override
  String get filesDisplayName => 'Display Name';

  @override
  String get filesDisplayNameHint => 'e.g. My Cloud Storage';

  @override
  String get filesConnectionCredentials => 'Connection Credentials';

  @override
  String get filesExistingSecretPreserved =>
      'Passwords, secrets, and tokens are never returned. Leave them blank to keep the saved values.';

  @override
  String get filesKeepExistingSecretHint =>
      'Leave blank to keep the saved value';

  @override
  String get filesS3Provider => 'S3 Provider';

  @override
  String get filesEndpointRequired => 'Endpoint (required)';

  @override
  String get filesEndpointHint => 'e.g. http://omninest-minio:9000';

  @override
  String get filesRegion => 'Region';

  @override
  String get filesRegionHint => 'e.g. us-east-1 (optional)';

  @override
  String get filesServiceType => 'Service Type';

  @override
  String get filesWebdavUrl => 'WebDAV URL';

  @override
  String get filesUsername => 'Username';

  @override
  String get filesPasswordOrApp => 'Password / App Password';

  @override
  String get filesDirectoryPath => 'Directory Path';

  @override
  String get filesClientIdOptional => 'Client ID (optional)';

  @override
  String get filesClientSecretOptional => 'Client Secret (optional)';

  @override
  String get filesUnknownStorageType => 'Unknown Storage Type';

  @override
  String get filesAdvancedOptions => 'Advanced Options';

  @override
  String get filesMaxAccessCount => 'Max Access Count';

  @override
  String get filesNoLimit => 'No limit';

  @override
  String get filesExpiryTime => 'Expiry Time';

  @override
  String get filesNeverExpire => 'Never expire';

  @override
  String get filesCreateShareLink => 'Create Share Link';

  @override
  String get filesCreateFailed => 'Creation failed';

  @override
  String get filesSetPassword => 'Set Password';

  @override
  String get filesPasswordRequired => 'Password required to access';

  @override
  String get filesNoPasswordAnyone => 'No password, anyone can access';

  @override
  String get filesRandomGenerate => 'Random';

  @override
  String get filesCustomPassword => 'Custom Password';

  @override
  String get filesEnterPassword => 'Enter password';

  @override
  String get filesEnterCustomPassword => 'Please enter custom password';

  @override
  String get filesCopiedClipboard => 'Copied to clipboard';

  @override
  String get filesPasswordLabel => 'Password';

  @override
  String filesSharePasswordLabel(Object password) {
    return 'Password: $password';
  }

  @override
  String get filesCopyLinkWithPassword => 'Copy link (with password)';

  @override
  String get filesCopyLinkOnly => 'Copy link only';

  @override
  String get filesCopyLink => 'Copy Link';

  @override
  String get filesCannotLoadImage => 'Cannot load image';

  @override
  String get filesImageLoadFailed => 'Image load failed';

  @override
  String get filesCannotGetImageUrl => 'Cannot get image URL';

  @override
  String get filesCannotLoadVideo => 'Cannot load video';

  @override
  String get filesCannotGetVideoUrl => 'Cannot get video URL';

  @override
  String get filesCannotLoadAudio => 'Cannot load audio';

  @override
  String get filesCannotGetAudioUrl => 'Cannot get audio URL';

  @override
  String get filesCannotLoadFile => 'Cannot load file';

  @override
  String get filesCannotGetFileUrl => 'Cannot get file URL';

  @override
  String get filesPdfUnsupported =>
      'PDF preview is not supported on this platform. Please download to view.';

  @override
  String get filesType => 'Type';

  @override
  String get filesUnknown => 'Unknown';

  @override
  String get filesSizeLabel => 'Size';

  @override
  String get filesPath => 'Path';

  @override
  String get filesShareAccessError => 'Cannot access share link';

  @override
  String get filesRetry => 'Retry';

  @override
  String get filesSavedToMyFiles => 'File saved to my files';

  @override
  String get filesFileExists => 'File already exists';

  @override
  String get filesGotIt => 'Got it';

  @override
  String filesSaveFailed(Object message) {
    return 'Save failed: $message';
  }

  @override
  String get filesPasswordAccess => 'This share requires password access';

  @override
  String get filesEnterSharePassword => 'Enter share password to view the file';

  @override
  String get filesAccess => 'Access';

  @override
  String get filesSaveToMyFiles => 'Save to my files';

  @override
  String get filesDelete => 'Delete';

  @override
  String get filesCancel => 'Cancel';

  @override
  String get filesConfirm => 'Confirm';

  @override
  String get filesOpenTooltip => 'Open';

  @override
  String filesConflictMsg(Object name) {
    return 'A file with the same name \"$name\" exists in the recycle bin. Clean up and retry.';
  }

  @override
  String get filesStatusConflict => 'Conflict';

  @override
  String get filesStatusCreated => 'Created';

  @override
  String get filesLocalUpload => 'Local Upload';

  @override
  String filesUploadTaskCount(Object count) {
    return '$count tasks';
  }

  @override
  String get filesNoLocalUpload => 'No local uploads';

  @override
  String get filesFailedTasks => 'Failed Tasks';

  @override
  String get filesNoFailedTasks => 'No failed tasks';

  @override
  String get filesNoUploadTasks => 'No upload tasks';

  @override
  String get filesPauseUpload => 'Pause Upload';

  @override
  String get filesResumeUpload => 'Resume Upload';

  @override
  String get filesCleanAndRetry => 'Clean up and retry';

  @override
  String get filesOfflineQueued => 'Queued';

  @override
  String get filesOfflineRunning => 'Downloading';

  @override
  String get filesOfflineCancelling => 'Cancelling';

  @override
  String get filesOfflineCancelled => 'Cancelled';

  @override
  String get filesImportQueued => 'Queued';

  @override
  String get filesImportScanning => 'Scanning source content';

  @override
  String get filesImportTransferring => 'Transferring from external storage';

  @override
  String get filesImportWriting => 'Writing to the file library';

  @override
  String get filesImportWaitingWorker => 'Waiting for the background worker';

  @override
  String filesImportFileProgress(int completed, int total) {
    return '$completed/$total files completed';
  }

  @override
  String filesImportCurrentFile(Object name) {
    return 'Current: $name';
  }

  @override
  String get filesImportRunning => 'Importing';

  @override
  String get filesImportCancelling => 'Cancelling';

  @override
  String get filesImportCancelled => 'Cancelled';

  @override
  String get filesS3Compatible => 'S3 Compatible Storage';

  @override
  String get filesAliyunDrive => 'Aliyun Drive';

  @override
  String get filesLocalStorage => 'Local Directory';

  @override
  String get portalSearch => 'Search';

  @override
  String get portalOpenReadingItem => 'Open Reading';

  @override
  String get portalOpenPhoto => 'View Photo';

  @override
  String get portalEnterSystem => 'Enter System';

  @override
  String get portalVisualCompactTitle =>
      'Desktop Portal switched to one column';

  @override
  String get portalVisualCompactBody =>
      'The current window is narrow, so content covers and status information are stacked.';

  @override
  String get portalVisualEyebrowRecentContent => 'Recent Content';

  @override
  String get portalVisualEyebrowCompact => 'OmniNest Portal';

  @override
  String get portalVisualStatusTitle => 'Needs Attention';

  @override
  String get portalVisualLastReadingLocation => 'Last reading position';

  @override
  String get portalVisualSync => 'Sync';

  @override
  String get portalFileManager => 'File Manager';

  @override
  String get portalFileManagerSubtitle =>
      'Network storage, folders, recycle bin and object preview.';

  @override
  String get portalMovieCenter => 'Media Library';

  @override
  String get portalMovieCenterSubtitle =>
      'Manage movies, TV series, and anime with metadata sync and direct playback.';

  @override
  String get portalReaderCenter => 'Reader Center';

  @override
  String get portalReaderCenterSubtitle =>
      'Books, comics, and reading progress continuation.';

  @override
  String get portalMusic => 'Music';

  @override
  String get portalMusicSubtitle =>
      'Lossless music, play queue and playlist management.';

  @override
  String get portalPhotos => 'Photos';

  @override
  String get portalPhotosSubtitle => 'Albums, auto backup and memory timeline.';

  @override
  String get portalAdmin => 'Manage';

  @override
  String get portalAdminSubtitle =>
      'User permissions, system config, tasks and status.';

  @override
  String get portalDescriptionAdmin =>
      'Switch between media, reading, files and system admin from one entry; each subsystem has its own workspace.';

  @override
  String get portalDescriptionMember =>
      'Switch between media, reading and file management from one entry; each subsystem has its own workspace.';

  @override
  String get portalNoFiles => 'No files';

  @override
  String get portalNoPlayHistory => 'No play history';

  @override
  String get portalNoReadingHistory => 'No reading history';

  @override
  String get portalNoPhotos => 'No photos';

  @override
  String portalPhotoCount(Object count) {
    return '$count photos';
  }

  @override
  String portalAlbumCount(Object count) {
    return '$count albums';
  }

  @override
  String portalMovieBadge(Object count) {
    return '$count movies';
  }

  @override
  String portalReaderBadge(Object count) {
    return '$count reading';
  }

  @override
  String portalMusicBadge(Object count) {
    return '$count tracks';
  }

  @override
  String portalPhotoBadge(Object count) {
    return '$count photos';
  }

  @override
  String get portalRelativeNow => 'Just now';

  @override
  String portalRelativeMinutes(Object n) {
    return '$n min ago';
  }

  @override
  String portalRelativeHours(Object n) {
    return '$n hr ago';
  }

  @override
  String get portalRelativeYesterday => 'Yesterday';

  @override
  String portalRelativeDays(Object n) {
    return '$n days ago';
  }

  @override
  String portalRelativeMonths(Object n) {
    return '$n months ago';
  }

  @override
  String portalRelativeYears(Object n) {
    return '$n years ago';
  }

  @override
  String get portalStorageTitle => 'Storage';

  @override
  String portalStorageUnlimited(Object used) {
    return '$used GiB / Unlimited';
  }

  @override
  String get portalTaskTitle => 'Tasks';

  @override
  String get portalTaskRunning => 'Running';

  @override
  String get portalTaskQueued => 'Queued';

  @override
  String get portalTaskFailed => 'Failed';

  @override
  String get portalNowPlaying => 'Now Playing';

  @override
  String get portalNoPlayRecord => 'No play record';

  @override
  String get portalImmersivePlayback => 'Immersive playback';

  @override
  String get portalExitImmersivePlayback => 'Exit immersive playback';

  @override
  String get portalMusicVisualizerOpenSystem => 'Open Music';

  @override
  String get portalMusicVisualizerSeek => 'Playback progress';

  @override
  String get portalMusicVisualizerVolume => 'Volume';

  @override
  String get portalMusicVisualizerEdit => 'Edit visuals';

  @override
  String get portalMusicVisualizerSave => 'Save visuals';

  @override
  String get portalMusicVisualizerResetDefault => 'Restore defaults';

  @override
  String get portalMusicVisualizerLyrics => 'Lyrics';

  @override
  String get portalMusicVisualizerPlayer => 'Player';

  @override
  String get portalMusicVisualizerLow => 'Low';

  @override
  String get portalMusicVisualizerMid => 'Mid';

  @override
  String get portalMusicVisualizerHigh => 'High';

  @override
  String get portalMusicVisualizerCurrentFont => 'Current line size';

  @override
  String get portalMusicVisualizerInactiveOpacity => 'Inactive opacity';

  @override
  String get portalMusicVisualizerVisibleLines => 'Visible lines';

  @override
  String get musicVisualizerLyricActiveColor => 'Current line color';

  @override
  String get musicVisualizerLyricReadColor => 'Played line color';

  @override
  String get musicVisualizerLyricUnreadColor => 'Upcoming line color';

  @override
  String get musicVisualizerLyricBreathing => 'Lyric breathing';

  @override
  String get musicVisualizerLyricLineSpacing => 'Line spacing';

  @override
  String get musicVisualizerLyricGlowIntensity => 'Glow intensity';

  @override
  String get musicVisualizerLyricGlowColor => 'Glow color';

  @override
  String get musicVisualizerLyricPosition => 'Lyric position';

  @override
  String get musicVisualizerLyricPositionLeft => 'Left';

  @override
  String get musicVisualizerLyricPositionCenter => 'Center';

  @override
  String get musicVisualizerLyricPositionRight => 'Right';

  @override
  String get musicVisualizerAudioBarStyle => 'Audio bar style';

  @override
  String get musicVisualizerAudioBarSpectrum => 'Spectrum bars';

  @override
  String get musicVisualizerAudioBarLine => 'Light trace';

  @override
  String get musicVisualizerAudioBarDots => 'Pulse dots';

  @override
  String get musicVisualizerColorHue => 'Hue';

  @override
  String get musicVisualizerColorSaturation => 'Saturation';

  @override
  String get musicVisualizerColorBrightness => 'Brightness';

  @override
  String get portalMusicVisualizerLyricGlow => 'Lyric glow';

  @override
  String get portalMusicVisualizerOriginalCover => 'Original cover';

  @override
  String get portalMusicVisualizerCoverBorder => 'Cover border';

  @override
  String get portalMusicVisualizerProgressControl => 'Progress bar';

  @override
  String get musicVisualizerPlayerVisible => 'Show bottom player';

  @override
  String get musicVisualizerAudioBar => 'Show audio bars';

  @override
  String get musicVisualizerFrequencyResponse => 'Audio bar frequency response';

  @override
  String get musicVisualizerCoverSize => 'Cover size';

  @override
  String get musicVisualizerCoverRadius => 'Cover radius';

  @override
  String get musicVisualizerCoverTilt => 'Cover tilt';

  @override
  String get musicVisualizerHeroCoverOpacity => 'Hero cover opacity';

  @override
  String get portalReading => 'Reading';

  @override
  String get portalNoReadingBook => 'No books being read';

  @override
  String get portalRecentPhotos => 'Recent Photos';

  @override
  String portalNewPhotoCount(Object count) {
    return '$count new photos';
  }

  @override
  String get portalQuickUpload => 'Upload';

  @override
  String get portalQuickDownload => 'Download';

  @override
  String get portalQuickNew => 'New';

  @override
  String get portalQuickActions => 'Quick actions';

  @override
  String get portalQuickSearch => 'Search';

  @override
  String get portalQuickScan => 'Scan';

  @override
  String get portalQuickPlay => 'Play';

  @override
  String get portalMobileGreetingMorning => 'Good morning';

  @override
  String get portalMobileGreetingAfternoon => 'Good afternoon';

  @override
  String get portalMobileGreetingEvening => 'Good evening';

  @override
  String get portalMobileContinueUsing => 'Continue';

  @override
  String get portalMobileNoContinue => 'Nothing waiting to resume';

  @override
  String get portalMobileSystemSummary => 'System summary';

  @override
  String get portalMobileSyncOnline => 'Sync service online';

  @override
  String get portalMobileSyncOffline => 'Offline, waiting to sync';

  @override
  String portalMobileTaskSummary(Object active, Object failed) {
    return '$active active, $failed failed';
  }

  @override
  String portalMobileStorageUsed(Object used) {
    return '$used used';
  }

  @override
  String get portalMobileViewAll => 'View all';

  @override
  String get portalContinueWatching => 'Continue Watching';

  @override
  String get portalNoWatchingContent => 'No content being watched';

  @override
  String get portalPressBackAgain => 'Press back again to exit';

  @override
  String get portalLoadMovieFailed => 'Failed to load media library info';

  @override
  String get portalLoadMusicFailed => 'Failed to load music info';

  @override
  String get portalLoadStorageFailed => 'Failed to load storage info';

  @override
  String get portalLoadReadingFailed => 'Failed to load reading info';

  @override
  String get portalLoadPhotoFailed => 'Failed to load photo info';

  @override
  String get portalDockFiles => 'Files';

  @override
  String get portalDockMovies => 'Media';

  @override
  String get portalDockMusic => 'Music';

  @override
  String get portalDockPhotos => 'Photos';

  @override
  String get portalDockReading => 'Reading';

  @override
  String get portalWeatherTitle => 'Weather';

  @override
  String get portalWeatherUpdated => 'Updated';

  @override
  String get portalWeatherDisconnected => 'Disconnected';

  @override
  String portalWeatherFeelsLike(Object text, Object feelsLike) {
    return '$text · Feels like $feelsLike°';
  }

  @override
  String portalWeatherSunrise(Object time) {
    return 'Sunrise $time';
  }

  @override
  String portalWeatherSunset(Object time) {
    return 'Sunset $time';
  }

  @override
  String get portalWeatherConfigApiKey => 'Please configure API Key';

  @override
  String get portalWeatherWeeklyStats => 'Weekly Stats';

  @override
  String get portalWeatherStatReading => 'Reading';

  @override
  String get portalWeatherStatPlaying => 'Playing';

  @override
  String get portalWeatherStatPhotos => 'Photos';

  @override
  String get portalWeatherUnknown => 'Unknown';

  @override
  String get portalWeatherLoading => 'Loading';

  @override
  String get portalWeatherDefaultLocation => 'Beijing';

  @override
  String get portalWeatherTipMask => 'Poor air quality, wear a mask';

  @override
  String get portalWeatherTipRain => 'Rain expected, bring an umbrella';

  @override
  String get portalWeatherTipIce => 'Roads may be slippery, watch your step';

  @override
  String get portalWeatherTipUV => 'Strong UV, protect from sun';

  @override
  String get portalWeatherTipCold => 'Feels cold, dress warmly';

  @override
  String get portalWeatherTipHot => 'Hot weather, stay hydrated';

  @override
  String get portalWeatherTipFog => 'Foggy, drive safely';

  @override
  String get portalWeatherTipNice =>
      'Nice weather, great for outdoor activities';

  @override
  String get portalWeatherHumidity => 'Humidity';

  @override
  String get portalWeatherWind => 'Wind';

  @override
  String get portalWeatherVisibility => 'Visibility';

  @override
  String get portalWeatherPressure => 'Pressure';

  @override
  String get portalWeatherUV => 'UV Index';

  @override
  String get portalWeatherPrecip => 'Precip';

  @override
  String get portalWeatherAdvice => 'Advice';

  @override
  String get portalWeatherSunriseLabel => 'Sunrise';

  @override
  String get portalWeatherSunsetLabel => 'Sunset';

  @override
  String get portalWeatherForecastHourly => 'Hourly';

  @override
  String get portalWeatherForecastWeekly => '7-Day';

  @override
  String get portalWeatherForecastToday => 'Today';

  @override
  String get portalWeatherForecastNow => 'Now';

  @override
  String get portalWeatherForecastEmpty => 'No forecast data';

  @override
  String get portalWeatherDebugTooltip => 'Debug weather visuals';

  @override
  String get portalWeatherDebugLive => 'Live weather';

  @override
  String get portalWeatherDebugDawn => 'Dawn';

  @override
  String get portalWeatherDebugSunny => 'Sunny';

  @override
  String get portalWeatherDebugSunnyNight => 'Clear night';

  @override
  String get portalWeatherDebugDusk => 'Dusk';

  @override
  String get portalWeatherDebugPartlyCloudy => 'Partly cloudy';

  @override
  String get portalWeatherDebugPartlyCloudyNight => 'Partly cloudy night';

  @override
  String get portalWeatherDebugCloudy => 'Cloudy';

  @override
  String get portalWeatherDebugCloudyNight => 'Cloudy night';

  @override
  String get portalWeatherDebugLightRain => 'Light rain';

  @override
  String get portalWeatherDebugLightRainLeft => 'Light rain left';

  @override
  String get portalWeatherDebugHeavyRain => 'Heavy rain';

  @override
  String get portalWeatherDebugHeavyRainRight => 'Heavy rain right';

  @override
  String get portalWeatherDebugRainNight => 'Night rain';

  @override
  String get portalWeatherDebugStorm => 'Storm';

  @override
  String get portalWeatherDebugLightSnow => 'Light snow';

  @override
  String get portalWeatherDebugHeavySnow => 'Heavy snow';

  @override
  String get portalWeatherDebugSnowNight => 'Night snow';

  @override
  String get portalWeatherDebugFog => 'Fog';

  @override
  String get portalWeatherDebugHaze => 'Haze';

  @override
  String get portalWeatherDebugDust => 'Dust';

  @override
  String get portalWeatherDebugHeat => 'Heat';

  @override
  String get portalWeatherDebugCold => 'Cold';

  @override
  String get portalWeatherDebugTimeDawn => 'Dawn';

  @override
  String get portalWeatherDebugTimeDay => 'Day';

  @override
  String get portalWeatherDebugTimeDusk => 'Dusk';

  @override
  String get portalWeatherDebugTimeNight => 'Night';

  @override
  String get portalLocalBackdropShort => 'Backdrops';

  @override
  String get portalLocalBackdropTitle => 'Backdrops';

  @override
  String get portalLocalBackdropSubtitle =>
      'Your backdrop library is synced to your account and shared across Web, desktop, and mobile. The bundled wallpaper also works offline.';

  @override
  String get portalLocalBackdropLoadFailed => 'Failed to load backdrops';

  @override
  String get portalLocalBackdropAddFiles => 'Add backdrops';

  @override
  String get portalLocalBackdropScanDirectory => 'Scan folder';

  @override
  String get portalLocalBackdropUploading => 'Uploading…';

  @override
  String portalLocalBackdropUploadFailedNames(Object titles) {
    return 'Failed to upload: $titles';
  }

  @override
  String get portalLocalBackdropDeleteFailed =>
      'Delete failed. Please try again later.';

  @override
  String get portalLocalBackdropQuotaExceeded =>
      'Backdrop count or storage quota exceeded';

  @override
  String get portalLocalBackdropUnsupportedFormat =>
      'Only JPG, PNG, WebP, GIF images or MP4, WebM, MOV videos are supported';

  @override
  String get portalLocalBackdropFileTooLarge => 'Backdrop file is too large';

  @override
  String get portalLocalBackdropScanUnavailable =>
      'Security scanning is unavailable, upload blocked';

  @override
  String get portalLocalBackdropMalwareDetected =>
      'Malware detected, upload rejected';

  @override
  String get portalLocalBackdropRateLimited =>
      'Uploading too frequently, please try again later';

  @override
  String get portalLocalBackdropClearAll => 'Clear all';

  @override
  String get portalLocalBackdropClearAllTitle => 'Remove all backdrops?';

  @override
  String get portalLocalBackdropClearAllMessage =>
      'Your backdrop assets will be removed from the server library on all devices. The bundled wallpaper stays available offline.';

  @override
  String get portalLocalBackdropClearAllConfirm => 'Remove';

  @override
  String portalLocalBackdropCount(Object count) {
    return '$count backdrops';
  }

  @override
  String get portalLocalBackdropEmpty =>
      'No backdrops yet. Add videos, GIFs, or images and they will sync to all your devices.';

  @override
  String get portalLocalBackdropFilterEmpty => 'No backdrops in this category';

  @override
  String get portalLocalBackdropEmptyScan =>
      'No usable backdrop files found. MP4, WEBM, MOV, M4V, GIF, JPG, PNG, and WEBP are supported.';

  @override
  String get portalLocalBackdropScanFailed =>
      'Scan failed. Check folder permissions.';

  @override
  String get portalLocalBackdropMissing => 'File missing';

  @override
  String get portalLocalBackdropProcessing => 'Processing';

  @override
  String get portalLocalBackdropFailed => 'Unavailable';

  @override
  String get portalLocalBackdropRemoveConfirmTitle => 'Remove this backdrop?';

  @override
  String get portalLocalBackdropRemoveConfirmMessage =>
      'It will be deleted from the server library and disappear on all devices.';

  @override
  String portalLocalBackdropClearPartial(int removed, int failed) {
    return 'Cleared $removed item(s); $failed failed.';
  }

  @override
  String get portalLocalBackdropRemove => 'Remove backdrop';

  @override
  String get portalLocalBackdropEnable => 'Enable backdrop';

  @override
  String get portalLocalBackdropEnableHint =>
      'Used by Portal and Music. The bundled wallpaper also works offline.';

  @override
  String get portalLocalBackdropSeparateDevices =>
      'Separate desktop and mobile';

  @override
  String get portalLocalBackdropSeparateDevicesHint =>
      'Off uses one shared selection. On keeps a separate backdrop for each device class.';

  @override
  String get portalLocalBackdropCurrentDesktop =>
      'Currently configuring the desktop backdrop';

  @override
  String get portalLocalBackdropCurrentMobile =>
      'Currently configuring the mobile backdrop';

  @override
  String get portalLocalBackdropFit => 'Display mode';

  @override
  String get portalLocalBackdropFitCover => 'Fill';

  @override
  String get portalLocalBackdropFitContain => 'Fit';

  @override
  String get portalLocalBackdropFitFill => 'Stretch';

  @override
  String get portalLocalBackdropAlignment => 'Crop anchor';

  @override
  String get portalLocalBackdropAlignTop => 'Top';

  @override
  String get portalLocalBackdropAlignCenter => 'Center';

  @override
  String get portalLocalBackdropAlignBottom => 'Bottom';

  @override
  String get portalLocalBackdropClearVideoCache => 'Clear video cache';

  @override
  String get portalLocalBackdropFilterAll => 'All';

  @override
  String get portalLocalBackdropFilterJpeg => 'JPG';

  @override
  String get portalLocalBackdropFilterPng => 'PNG';

  @override
  String get portalLocalBackdropFilterWebp => 'WEBP';

  @override
  String get portalLocalBackdropFilterGif => 'GIF';

  @override
  String get portalLocalBackdropFilterMp4 => 'MP4';

  @override
  String get portalLocalBackdropFilterWebm => 'WEBM';

  @override
  String get portalLocalBackdropFilterMov => 'MOV';

  @override
  String get portalLocalBackdropFilterM4v => 'M4V';

  @override
  String get portalLocalBackdropDim => 'Dim';

  @override
  String get portalLocalBackdropBlur => 'Blur';

  @override
  String get portalLocalBackdropVideoMuted => 'Mute video';

  @override
  String get portalLocalBackdropRetryPlayback => 'Retry playback';

  @override
  String get portalLocalBackdropLocalOnly =>
      'Backdrop paths are stored only in SQLite on this device. Use short loops with common codecs; playback pauses when the page is hidden or the app enters the background. Web uses the default theme backdrop.';

  @override
  String get adminOpenMenu => 'Open admin menu';

  @override
  String get adminStorageOverview => 'Storage Overview';

  @override
  String adminPercentUsed(Object percent) {
    return '$percent% used';
  }

  @override
  String get adminTopBarPortal => 'Portal';

  @override
  String get adminShellTitle => 'OmniNest Admin';

  @override
  String get adminShellSubtitle => 'Central Console';

  @override
  String get adminRolePillLabel => 'Admin';

  @override
  String get adminRoleSuperAdmin => 'Super Admin';

  @override
  String get adminRoleAdmin => 'Admin';

  @override
  String get adminRoleMember => 'Member';

  @override
  String get adminRoleGuest => 'Guest';

  @override
  String get adminUserStatusActive => 'Active';

  @override
  String get adminUserStatusDisabled => 'Disabled';

  @override
  String adminStorageUsed(Object size) {
    return 'Used $size';
  }

  @override
  String adminStorageFileCount(Object count) {
    return '$count files';
  }

  @override
  String adminOverviewTasksTotal(Object count) {
    return '$count tasks';
  }

  @override
  String adminAnalyticsDays(Object days) {
    return '${days}d';
  }

  @override
  String get adminAnalyticsLive => 'LIVE';

  @override
  String adminTaskThroughputTooltip(Object completed, Object failed) {
    return '$completed done · $failed err';
  }

  @override
  String get adminLoadCpu => 'CPU';

  @override
  String get adminLoadMemory => 'MEM';

  @override
  String get adminLoadDisk => 'DISK';

  @override
  String get adminLoadJvm => 'JVM';

  @override
  String adminMonitoringStepMinutes(Object minutes) {
    return '${minutes}min step';
  }

  @override
  String get adminSystemMonitoring => 'System Monitoring';

  @override
  String get adminMonitoringSubtitle =>
      'View service status, resource usage, component health, alerts and admin operation records.';

  @override
  String get adminRunning => 'Running';

  @override
  String adminAttentionItems(Object count) {
    return '$count items to watch';
  }

  @override
  String get adminServiceStatus => 'Service Status';

  @override
  String adminUptime(Object uptime) {
    return 'Uptime $uptime';
  }

  @override
  String get adminComponents => 'Components';

  @override
  String get adminAlerts => 'Alerts';

  @override
  String get adminSystemCpu => 'System CPU';

  @override
  String get adminMemory => 'Memory';

  @override
  String get adminDiskUsage => 'Disk Usage';

  @override
  String get adminDataDirectoryDisk => 'Data directory disk';

  @override
  String get adminRequests => 'Requests';

  @override
  String get adminComponentHealth => 'Component Health';

  @override
  String get adminComponentHealthSubtitle =>
      'Current snapshot of database, Redis, RabbitMQ, MinIO and index components.';

  @override
  String get adminNoComponentHealth => 'No component health data.';

  @override
  String get adminRecentAlerts => 'Recent System Alerts';

  @override
  String get adminRecentAlertsSubtitle =>
      'Generated by snapshot rules, can be connected to real alert table later.';

  @override
  String get adminNoAlerts => 'No system alerts.';

  @override
  String get adminRecentOperations => 'Recent Operations';

  @override
  String get adminRecentOperationsSubtitle =>
      'From audit logs, useful for troubleshooting config and admin actions.';

  @override
  String get adminNoOperations => 'No admin operation records.';

  @override
  String get adminTrendCharts => 'Real-time Trend Charts';

  @override
  String get adminTrendChartsSubtitle =>
      'Currently showing 55-minute sampling trends, can be replaced with real time-series storage later.';

  @override
  String get adminNoTrendData => 'No trend data.';

  @override
  String get adminAnalyticsDataHint =>
      'Data will be collected automatically once the system is running.';

  @override
  String get adminRealtime => 'Realtime';

  @override
  String get adminLogCenter => 'Log Center';

  @override
  String get adminLogCenterSubtitle =>
      'Unified view of operation audit and login logs.';

  @override
  String adminAuditCount(Object count) {
    return '$count audit records';
  }

  @override
  String get adminTabAudit => 'Operation Audit';

  @override
  String get adminTabLoginLog => 'Login Log';

  @override
  String get adminRecentAudit => 'Recent Audit';

  @override
  String get adminRecentAuditSubtitle =>
      'From audit_logs, sorted by creation time descending.';

  @override
  String get adminNoAuditLogs => 'No audit logs.';

  @override
  String get adminNoLoginLogs => 'No login logs.';

  @override
  String adminLoadFailed(Object error) {
    return 'Load failed: $error';
  }

  @override
  String get adminLoginLog => 'Login Log';

  @override
  String get adminLoginLogSubtitle =>
      'From auth_login_audit, records all login attempts.';

  @override
  String get adminLoginSuccess => 'Success';

  @override
  String get adminLoginFailed => 'Failed';

  @override
  String get adminFilterAction => 'Action';

  @override
  String get adminFilterStatus => 'Status';

  @override
  String get adminFilterPlatform => 'Platform';

  @override
  String get adminCleanup => 'Clean up';

  @override
  String adminRetentionDays(Object days) {
    return 'Keep $days days';
  }

  @override
  String get adminCleanupConfirmTitle => 'Confirm cleanup';

  @override
  String get adminCleanupConfirmMessage =>
      'Records outside the retention period will be deleted permanently.';

  @override
  String adminCleanupCompleted(Object count) {
    return 'Cleaned up $count records';
  }

  @override
  String get adminBackgroundTasks => 'Background Tasks';

  @override
  String get adminBackgroundTasksSubtitle =>
      'Track indexing, transcoding, sync, backup and cleanup tasks.';

  @override
  String get adminTotalTasks => 'Total Tasks';

  @override
  String get adminRecentTasks => 'Recent tasks';

  @override
  String get adminRunningTasks => 'Running';

  @override
  String get adminExecuting => 'Executing';

  @override
  String get adminFailedTasks => 'Failed';

  @override
  String get adminRetryable => 'Retryable';

  @override
  String get adminTaskList => 'Task List';

  @override
  String get adminTaskStatusRunning => 'Running';

  @override
  String get adminTaskStatusCompleted => 'Completed';

  @override
  String get adminTaskStatusDlq => 'Dead letter';

  @override
  String get adminTaskErrorSummary => 'Error summary';

  @override
  String get adminTaskUpdatedAt => 'Updated at';

  @override
  String get adminTaskName => 'Task name';

  @override
  String get adminTaskExecutionStatus => 'Status';

  @override
  String get adminTaskListSubtitle =>
      'Failed, cancelled and DLQ status support re-queue.';

  @override
  String get adminNoBackgroundTasks => 'No background tasks.';

  @override
  String get adminNotSet => 'Not set';

  @override
  String get adminProgress => 'Progress';

  @override
  String get adminRetry => 'Retry';

  @override
  String get adminRoleManagement => 'Role Management';

  @override
  String get adminRoleManagementSubtitle =>
      'Maintain roles, permission sets and resource access boundaries.';

  @override
  String adminPermissionCount(Object count) {
    return '$count permissions';
  }

  @override
  String get adminRoles => 'Roles';

  @override
  String get adminSystemRoles => 'System roles';

  @override
  String get adminPermissionBindings => 'Permission Bindings';

  @override
  String get adminRolePermissions => 'Role permissions';

  @override
  String get adminPermissionModules => 'Permission Modules';

  @override
  String get adminBusinessDomains => 'Business domains';

  @override
  String get adminRolePermissionsTitle => 'Role Permissions';

  @override
  String get adminRolePermissionsSubtitle =>
      'Built-in roles cannot be deleted, SUPER_ADMIN permissions maintained by system.';

  @override
  String get adminNoRoles => 'No role data.';

  @override
  String adminPermissionCountInline(Object count) {
    return '$count permissions';
  }

  @override
  String get adminConfigurePermissions => 'Configure Permissions';

  @override
  String adminConfigureRolePermissions(Object name) {
    return 'Configure $name Permissions';
  }

  @override
  String get adminSecurityWarning => 'Security Warning';

  @override
  String get adminSecurityWarningMessage =>
      'Only grant permissions that are actually needed. Over-privileged roles may lead to unauthorized data access or system misuse.';

  @override
  String get adminConfigCenter => 'Config Center';

  @override
  String get adminConfigCenterSubtitle =>
      'Manage business policies and external service integrations.';

  @override
  String get adminConfigRefresh => 'Refresh settings';

  @override
  String adminConfigGroupItemCount(int count) {
    return '$count settings';
  }

  @override
  String get adminConfigGroupMedia => 'Media Import';

  @override
  String get adminConfigGroupReader => 'Reader';

  @override
  String get adminConfigGroupMusic => 'Music';

  @override
  String get adminConfigGroupPhotos => 'Photos and Backup';

  @override
  String get adminConfigGroupStorage => 'Storage and Shared Space';

  @override
  String get adminConfigGroupUpload => 'Upload';

  @override
  String get adminConfigGroupSecurity => 'Security';

  @override
  String get adminConfigGroupWeather => 'Weather';

  @override
  String get adminConfigGroupOther => 'Other Settings';

  @override
  String get adminConfigProviderPhotoAi => 'Image analysis';

  @override
  String get adminConfigProviderMusicBrainz => 'MusicBrainz';

  @override
  String get adminConfigProviderTmdb => 'TMDB';

  @override
  String get adminConfigProviderGoogleBooks => 'Google Books';

  @override
  String get adminConfigProviderOpenLibrary => 'Open Library';

  @override
  String get adminConfigProviderNetease => 'NetEase Cloud Music';

  @override
  String get adminConfigProviderQqMusic => 'QQ Music';

  @override
  String get adminConfigProviderQWeather => 'QWeather';

  @override
  String get adminConfigManage => 'Manage';

  @override
  String get adminConfigSecretConfigured =>
      'Sensitive credential configured; its value is never shown';

  @override
  String get adminConfigNeedsSetup => 'Not configured';

  @override
  String adminConfigCurrentValue(Object value) {
    return 'Current value: $value';
  }

  @override
  String get adminConfigClearCredential => 'Clear credential';

  @override
  String get adminConfigClearCredentialConfirm =>
      'The related integration will stop working after this credential is cleared. Continue?';

  @override
  String get adminConfigCredentialClearedReason =>
      'Integration credential cleared by administrator';

  @override
  String get adminConfigMediaAutoImport =>
      'Automatically import discovered media';

  @override
  String get adminConfigPhotoBackup => 'Automatic photo backup';

  @override
  String get adminConfigDefaultQuota => 'Default quota for new users';

  @override
  String get adminConfigQuotaWarning => 'Quota warning threshold';

  @override
  String get adminConfigSharedSpace => 'Shared space';

  @override
  String get adminConfigSharedSpaceLimit => 'Shared space capacity limit';

  @override
  String get adminConfigLocalMedia => 'Local read-only media';

  @override
  String get adminConfigWeather => 'Weather feature';

  @override
  String get adminConfigMusicBrainzEnabled => 'Enable MusicBrainz';

  @override
  String get adminConfigTmdbEnabled => 'Enable TMDB';

  @override
  String get adminConfigTmdbApiKey => 'TMDB API Key';

  @override
  String get adminConfigTmdbAccessToken => 'TMDB Access Token';

  @override
  String get adminConfigTmdbLanguage => 'Metadata language';

  @override
  String get adminConfigTmdbAdult => 'Include adult content';

  @override
  String get adminConfigPhotoAiEnabled => 'Enable image analysis';

  @override
  String get adminConfigNeteaseEnabled => 'Enable NetEase Cloud Music';

  @override
  String get adminConfigQqEnabled => 'Enable QQ Music';

  @override
  String get adminConfigQWeatherProjectId => 'Project ID';

  @override
  String get adminConfigQWeatherCredentialId => 'Credential ID';

  @override
  String get adminConfigQWeatherPrivateKey => 'Ed25519 private key';

  @override
  String get adminConfigTmdbTimeout => 'TMDB request timeout';

  @override
  String get adminConfigTmdbStrategy => 'TMDB search strategy';

  @override
  String get adminConfigTmdbLimit => 'TMDB result limit';

  @override
  String get adminConfigMediaTranscode => 'Enable media transcoding';

  @override
  String get adminConfigReaderGoogleBooksEnabled => 'Enable Google Books';

  @override
  String get adminConfigReaderGoogleBooksUrl => 'Google Books service URL';

  @override
  String get adminConfigReaderGoogleBooksLanguage => 'Google Books language';

  @override
  String get adminConfigReaderGoogleBooksLimit => 'Google Books result limit';

  @override
  String get adminConfigReaderGoogleBooksTimeout =>
      'Google Books request timeout';

  @override
  String get adminConfigReaderGoogleBooksApiKey => 'Google Books API Key';

  @override
  String get adminConfigReaderOpenLibraryEnabled => 'Enable Open Library';

  @override
  String get adminConfigReaderOpenLibraryUrl => 'Open Library service URL';

  @override
  String get adminConfigReaderOpenLibraryLanguage => 'Open Library language';

  @override
  String get adminConfigReaderAutoImport => 'Enable reader auto-import';

  @override
  String get adminConfigMusicBrainzBaseUrl => 'MusicBrainz service URL';

  @override
  String get adminConfigMusicAutoImport => 'Enable music auto-import';

  @override
  String get adminConfigMusicBrainzUserAgent => 'MusicBrainz User-Agent';

  @override
  String get adminConfigMusicBrainzCoverUrl => 'MusicBrainz cover service URL';

  @override
  String get adminConfigMusicOnlineEnabled => 'Enable online music';

  @override
  String get adminConfigTmdbBaseUrl => 'TMDB service URL';

  @override
  String get adminConfigPhotoAiEndpoint => 'Image analysis service URL';

  @override
  String get adminConfigNeteaseBaseUrl => 'NetEase Music service URL';

  @override
  String get adminConfigNeteaseHosts => 'NetEase playback hosts';

  @override
  String get adminConfigQqUUrl => 'QQ Music U endpoint';

  @override
  String get adminConfigQqCUrl => 'QQ Music C endpoint';

  @override
  String get adminConfigQqHosts => 'QQ Music playback hosts';

  @override
  String get adminConfigQWeatherBaseUrl => 'QWeather service URL';

  @override
  String get adminConfigWeatherLocation => 'Weather location';

  @override
  String get adminConfigPhotoAiTimeout => 'Image analysis request timeout';

  @override
  String get adminConfigPhotoGeoRate => 'Photo geocoding rate';

  @override
  String get adminConfigUploadRateEnabled => 'Enable upload rate limiting';

  @override
  String get adminConfigSecurityRateLimit => 'Default security rate limit';

  @override
  String get adminConfigClamavEnabled => 'Enable ClamAV';

  @override
  String get adminConfigClamavHost => 'ClamAV host';

  @override
  String get adminConfigClamavPort => 'ClamAV port';

  @override
  String get adminConfigUnlimited => 'Unlimited';

  @override
  String get adminConfigUnlimitedDescription =>
      'No capacity check is applied when unlimited is selected.';

  @override
  String get adminConfigQuotaUnlimitedDescription =>
      'Enter a value directly, or move the slider to the far right or enable unlimited to remove the cap.';

  @override
  String get adminConfigQuotaSliderUnlimited => 'Far right: unlimited';

  @override
  String get adminConfigQuotaSliderMinimum => '1 GB';

  @override
  String get adminConfigQuotaInvalid =>
      'Enter a quota greater than 0 GB, or enable unlimited.';

  @override
  String get adminConfigQuotaWholeGb =>
      'The default user quota must be a whole number of GB.';

  @override
  String get adminConfigEndpointDescription =>
      'Base address used by server requests; adjust it for your deployment.';

  @override
  String get adminConfigWeatherLocationDescription =>
      'City, coordinates, or a provider-specific location identifier used for weather queries.';

  @override
  String get adminConfigUnknownItem => 'Unknown setting';

  @override
  String get adminConfigMediaAutoImportDescription =>
      'Allows discovered titles to enter the media import flow according to Media rules.';

  @override
  String get adminConfigPhotoBackupDescription =>
      'Controls whether new photos enter the automatic backup flow.';

  @override
  String get adminConfigDefaultQuotaDescription =>
      'Storage assigned to newly created users, in GB.';

  @override
  String get adminConfigQuotaWarningDescription =>
      'Shows a capacity warning when usage reaches this percentage.';

  @override
  String get adminConfigSharedSpaceDescription =>
      'Controls whether users can access the shared space.';

  @override
  String get adminConfigSharedSpaceLimitDescription =>
      'Limits the total capacity available to the shared space.';

  @override
  String get adminConfigLocalMediaDescription =>
      'Can only disable local media authorized at deployment; it cannot expand mount access.';

  @override
  String get adminConfigWeatherDescription =>
      'Controls whether clients can request weather data.';

  @override
  String get adminConfigProviderToggleDescription =>
      'Controls whether this integration may be used.';

  @override
  String get adminConfigCredentialDescription =>
      'Used for server-side authentication and never shown again after saving.';

  @override
  String get adminConfigProviderIdentifierDescription =>
      'Project or credential identifier supplied by the external service console.';

  @override
  String get adminConfigTmdbLanguageDescription =>
      'Preferred language for titles, descriptions, and image metadata returned by TMDB.';

  @override
  String get adminConfigTmdbAdultDescription =>
      'Search results may include adult content when enabled.';

  @override
  String get adminConfigInternalNumericDescription =>
      'Internal request or result bound used by this provider.';

  @override
  String get adminConfigTmdbStrategyDescription =>
      'Controls the normalized and fallback queries used for TMDB matching.';

  @override
  String get adminConfigMediaTranscodeDescription =>
      'Allows the media pipeline to generate playback derivatives.';

  @override
  String get adminConfigReaderAutoImportDescription =>
      'Allows recognized reader files to enter the import flow automatically.';

  @override
  String get adminConfigMusicAutoImportDescription =>
      'Allows recognized music files to enter the import flow automatically.';

  @override
  String get adminConfigPhotoGeoRateDescription =>
      'Maximum geocoding requests permitted per second.';

  @override
  String get adminConfigUploadRateDescription =>
      'Controls whether upload traffic is subject to the server rate policy.';

  @override
  String get adminConfigSecurityRateLimitDescription =>
      'Default request limit applied by security controls.';

  @override
  String get adminConfigMusicBrainzUserAgentDescription =>
      'Identification string sent with MusicBrainz requests.';

  @override
  String get adminConfigHostSuffixesDescription =>
      'Comma-separated host suffixes accepted for provider media requests.';

  @override
  String get adminConfigItems => 'Config Items';

  @override
  String get adminAllConfigs => 'All configs';

  @override
  String get adminHotUpdate => 'Hot Update';

  @override
  String get adminEffectiveImmediately => 'Effective immediately';

  @override
  String get adminRestartRequired => 'Restart Required';

  @override
  String get adminEffectiveAfterRestart => 'Effective after restart';

  @override
  String get adminConfigItemList => 'Config Items';

  @override
  String get adminConfigItemListSubtitle =>
      'Settings take effect by hot update, on the next task, or after restart.';

  @override
  String get adminNoConfigItems => 'No config items.';

  @override
  String get adminAllCategories => 'All Categories';

  @override
  String get adminAllScopes => 'All Scopes';

  @override
  String get adminHotReload => 'Hot Reload';

  @override
  String get adminNextTask => 'Next Task';

  @override
  String get adminNeedsRestart => 'Needs Restart';

  @override
  String get adminEdit => 'Edit';

  @override
  String get adminConfigValue => 'Config Value';

  @override
  String get adminSensitiveValuePlaceholder =>
      'Enter a new sensitive value; the current value is never displayed';

  @override
  String get adminChangeReason => 'Change Reason';

  @override
  String get adminTrue => 'True';

  @override
  String get adminFalse => 'False';

  @override
  String get adminConfigHistory => 'Change History';

  @override
  String get adminNoConfigHistory => 'No change history';

  @override
  String get adminRollback => 'Rollback';

  @override
  String get adminNoReason => 'No reason';

  @override
  String get adminDlq => 'Dead Letter Queue';

  @override
  String get adminDlqSubtitle =>
      'Failed tasks exhausted retries — re-queue manually';

  @override
  String get adminNoDlqTasks => 'No DLQ tasks';

  @override
  String get adminNoErrorSummary => 'No error summary';

  @override
  String get adminStorageManagement => 'Storage Management';

  @override
  String get adminListEmpty => 'No data. Try adjusting the filters.';

  @override
  String get adminListRowsPerPage => 'Rows per page';

  @override
  String adminListPageOf(Object current, Object total) {
    return 'Page $current of $total';
  }

  @override
  String get adminListPrevPage => 'Previous page';

  @override
  String get adminListNextPage => 'Next page';

  @override
  String get adminListActions => 'Actions';

  @override
  String get adminListIndex => '#';

  @override
  String adminListSelectedCount(Object count) {
    return '$count selected';
  }

  @override
  String get adminListSelectAll => 'Select all';

  @override
  String get adminListExpandFilters => 'Expand filters';

  @override
  String get adminListCollapseFilters => 'Collapse filters';

  @override
  String get adminListSortAsc => 'Ascending';

  @override
  String get adminListSortDesc => 'Descending';

  @override
  String get adminListExportCsv => 'Export CSV';

  @override
  String get adminLibrarySourcesSection => 'Video library sources';

  @override
  String get statusHealthHealthy => 'Healthy';

  @override
  String get statusHealthAvailable => 'Available';

  @override
  String get statusHealthUnavailable => 'Unavailable';

  @override
  String get statusScopePersonal => 'Personal space';

  @override
  String get statusScopeShared => 'Shared space';

  @override
  String get statusProviderLocalFilesystem => 'Local filesystem';

  @override
  String get statusProviderMinio => 'Object storage';

  @override
  String get statusManagementManaged => 'Managed';

  @override
  String get statusScanReady => 'Ready';

  @override
  String get statusScanDiscovering => 'Discovering';

  @override
  String get statusScanApplying => 'Applying';

  @override
  String get statusScanFailed => 'Failed';

  @override
  String get statusScanCancelled => 'Cancelled';

  @override
  String get statusScanPaused => 'Paused';

  @override
  String get statusScanPartial => 'Partially applied';

  @override
  String get statusScanQueued => 'Queued';

  @override
  String get statusPhaseDiscovery => 'Discovery phase';

  @override
  String get statusPhaseReview => 'Review phase';

  @override
  String get statusPhaseApply => 'Apply phase';

  @override
  String get adminLibrarySourceAdd => 'Add library source';

  @override
  String get adminLibrarySourcesEmpty =>
      'No library sources yet. Create one on an enabled storage location.';

  @override
  String get adminLibrarySourcesSubtitle =>
      'Create movie, series and anime sources on enabled storage locations.';

  @override
  String get adminLibraryReviewSubtitle =>
      'Pick a source to review the scan results and apply them.';

  @override
  String get adminStorageStatusHealthy => 'Healthy';

  @override
  String get adminStorageFilterAll => 'All';

  @override
  String get adminStorageFilterEnabled => 'Enabled';

  @override
  String get adminStorageFilterDisabled => 'Disabled';

  @override
  String get adminStorageFilterUnhealthy => 'Unhealthy';

  @override
  String get adminStorageEmptyList => 'No storage locations match the filter';

  @override
  String get adminStorageDetailHint =>
      'Select a storage location to view details';

  @override
  String get adminStorageStatusDisabled => 'Disabled';

  @override
  String get adminStorageDisableConfirmTitle => 'Disable storage location';

  @override
  String adminStorageDisableConfirmBody(Object name) {
    return 'Scanning and media access stop for \"$name\" until you enable it again.';
  }

  @override
  String get adminStorageDisableAction => 'Disable';

  @override
  String get adminStorageEnableAction => 'Enable';

  @override
  String get adminStorageDeleteConfirmTitle => 'Delete storage location';

  @override
  String adminStorageDeleteConfirmBody(Object name) {
    return 'This permanently removes the \"$name\" registration. Imported content is not affected.';
  }

  @override
  String get adminStorageDeleteAction => 'Delete';

  @override
  String get adminStorageFieldPath => 'Path';

  @override
  String get adminStorageFieldScope => 'Scope';

  @override
  String get adminStorageFieldProvider => 'Provider';

  @override
  String get adminStorageFieldManagement => 'Management';

  @override
  String get adminStorageFieldNode => 'Node';

  @override
  String get adminStorageParentDir => 'Up one level';

  @override
  String get adminStorageManagementSubtitle =>
      'Manage MinIO buckets, capacity, and index maintenance.';

  @override
  String get adminBucketConfig => 'Bucket Config';

  @override
  String get adminMinioBuckets => 'MinIO Buckets';

  @override
  String get adminRecentRecords => 'Recent records';

  @override
  String get adminWaitingToExecute => 'Waiting to execute';

  @override
  String get adminObjectBuckets => 'Object Buckets';

  @override
  String get adminObjectBucketsSubtitle => 'From backend MinIO config.';

  @override
  String get adminNoBucketConfig => 'No bucket config.';

  @override
  String get adminExternalStorageIntegration => 'External Storage Integration';

  @override
  String get adminExternalStorageSubtitle =>
      'Connect WebDAV, S3, SMB and mount cloud drives.';

  @override
  String get adminNewConnection => 'New Connection';

  @override
  String get adminNewExternalStorage => 'New External Storage';

  @override
  String get adminType => 'Type';

  @override
  String get adminLocalMount => 'Local (rclone) account';

  @override
  String get adminDisplayNameLabel => 'Display Name';

  @override
  String get adminCredentialsJson => 'Credentials JSON';

  @override
  String get adminEnterDisplayName => 'Please enter display name';

  @override
  String get adminCreatingLabel => 'Creating';

  @override
  String get adminConnections => 'Connections';

  @override
  String get adminExternalSources => 'External sources';

  @override
  String get adminEnabled => 'Enabled';

  @override
  String get adminSyncable => 'Syncable';

  @override
  String get adminDisabled => 'Disabled';

  @override
  String get adminPausedSync => 'Paused sync';

  @override
  String get adminConnectionList => 'Connection List';

  @override
  String get adminConnectionListSubtitle =>
      'Credentials managed by backend, frontend only shows connection metadata.';

  @override
  String get adminNoExternalStorage => 'No external storage connections.';

  @override
  String get adminDeactivate => 'Deactivate';

  @override
  String get adminActivate => 'Activate';

  @override
  String get adminSessionManagement => 'Session Management';

  @override
  String get adminSessionStatusActive => 'Active';

  @override
  String get adminSessionStatusRevoked => 'Force-signed out';

  @override
  String get adminSessionStatusExpired => 'Expired';

  @override
  String get adminSessionDetailTitle => 'Session details';

  @override
  String get adminSessionFieldDeviceId => 'Device ID';

  @override
  String get adminSessionDeviceName => 'Device name';

  @override
  String get adminSessionLoginTime => 'Signed in at';

  @override
  String get adminSessionExpiresAt => 'Expires at';

  @override
  String get adminSessionLastActive => 'Last active at';

  @override
  String get adminSessionIp => 'IP address';

  @override
  String get adminResourceType => 'Resource type';

  @override
  String get adminLogContent => 'Description';

  @override
  String get adminLogTime => 'Time';

  @override
  String get adminConfigDescription => 'Description';

  @override
  String get adminStorageOpenDetail => 'Details';

  @override
  String get adminStorageColumnType => 'Type';

  @override
  String get adminStorageMountsSection => 'Local mount locations';

  @override
  String get adminTrustedMountsTitle => 'Trusted mounts';

  @override
  String get adminTrustedMountsSubtitle =>
      'Mount keys registered in deployment config and their availability on this node. They back mount locations and mount-direct creation.';

  @override
  String get adminTrustedMountsEmpty =>
      'No mounts registered in deployment config';

  @override
  String adminLibraryOrphanLocation(Object count) {
    return '$count mount location(s) no longer referenced by any library source. Clean them up in the list above.';
  }

  @override
  String get adminLibraryCleanupOrphan => 'Clean up mount location';

  @override
  String get adminLibraryColumnName => 'Name';

  @override
  String get adminLibraryColumnLocation => 'Location · Root';

  @override
  String get adminLibraryColumnScanStatus => 'Scan status';

  @override
  String get adminLibraryColumnLastScan => 'Last scan';

  @override
  String get adminLibraryManageInfoSection => 'Library info';

  @override
  String get adminLibraryManageReviewSection => 'Discovery & review';

  @override
  String adminLibraryLastScanSummary(
    Object found,
    Object created,
    Object missing,
  ) {
    return 'Found $found · Created $created · Missing $missing';
  }

  @override
  String get adminLibraryScanNever => 'Never scanned';

  @override
  String get adminLibraryDeleteSourceTitle => 'Delete library source';

  @override
  String adminLibraryDeleteSourceBody(Object name) {
    return 'Delete library source \"$name\"? This cannot be undone.';
  }

  @override
  String get adminLibraryAccessTitle => 'Access management';

  @override
  String get adminStorageColumnName => 'Name';

  @override
  String get adminStorageColumnMountKey => 'Mount key';

  @override
  String get adminStorageColumnRoot => 'Root';

  @override
  String get adminStorageColumnHealth => 'Health';

  @override
  String get adminLibraryDiscoverUpdates => 'Discover updates';

  @override
  String adminListTotalCount(Object count) {
    return '$count items';
  }

  @override
  String adminListRange(Object start, Object end) {
    return 'Items $start-$end';
  }

  @override
  String get adminListFirstPage => 'First page';

  @override
  String get adminListLastPage => 'Last page';

  @override
  String get adminListJumpTo => 'Go to';

  @override
  String get adminListPageUnit => '';

  @override
  String get adminConfigGroupColumn => 'Group';

  @override
  String get adminBatchRevokeSessions => 'Force sign out selected';

  @override
  String get adminBatchRetryTasks => 'Retry selected';

  @override
  String get adminBatchClearSelection => 'Clear selection';

  @override
  String adminBatchCompleted(Object success, Object failed) {
    return 'Batch finished: $success succeeded, $failed failed';
  }

  @override
  String get adminBatchConfirmTitle => 'Confirm batch operation';

  @override
  String adminBatchConfirmMessage(Object count) {
    return 'This applies to $count selected items one by one; failed items are skipped.';
  }

  @override
  String get adminCsvExported => 'Current page exported';

  @override
  String get adminLoginFailureReason => 'Failure reason';

  @override
  String get adminSessionRevokeReason => 'Revoke reason';

  @override
  String get adminSessionManagementSubtitle =>
      'View all user active sessions, supports forced logout.';

  @override
  String get adminActiveSessions => 'active';

  @override
  String get adminRevokedSessions => 'revoked';

  @override
  String get adminActiveSessionCount => 'Active Sessions';

  @override
  String get adminCurrentOnlineDevices => 'Currently online devices';

  @override
  String get adminRevokedCount => 'Revoked';

  @override
  String get adminBeenKicked => 'Been kicked out';

  @override
  String get adminSessionList => 'Session List';

  @override
  String get adminSessionListSubtitle => 'Sorted by creation time descending.';

  @override
  String get adminNoSessions => 'No session records.';

  @override
  String get adminConfirmKick => 'Confirm Kick';

  @override
  String adminConfirmKickMessage(Object device) {
    return 'Are you sure to revoke this session? Device: $device';
  }

  @override
  String get adminRevokeSession => 'Kick Session';

  @override
  String get adminRevokedLabel => 'revoked';

  @override
  String get adminSessionAllStatuses => 'All statuses';

  @override
  String get adminSessionActiveOnly => 'Active only';

  @override
  String get adminSessionRevokedOnly => 'Revoked only';

  @override
  String get adminSessionExpiredOnly => 'Expired only';

  @override
  String get adminExpiredLabel => 'Expired';

  @override
  String get adminCurrentPage => 'Current page';

  @override
  String get adminFilterTaskType => 'Task type';

  @override
  String adminPageIndicator(Object page, Object totalPages) {
    return 'Page $page / $totalPages';
  }

  @override
  String adminTotalCount(Object count) {
    return 'Total $count';
  }

  @override
  String get adminPreviousPage => 'Previous page';

  @override
  String get adminNextPage => 'Next page';

  @override
  String get adminUserManagement => 'User Management';

  @override
  String get adminUserManagementSubtitle =>
      'Manage accounts, status, quota and role assignment.';

  @override
  String get adminAccountList => 'Account List';

  @override
  String get adminAccountListSubtitle =>
      'Filter accounts by username, nickname, email and role.';

  @override
  String get adminCreateUser => 'Create User';

  @override
  String get adminSearchUsers => 'Search username, nickname or email';

  @override
  String get adminAll => 'All';

  @override
  String get adminNoMatchingUsers => 'No matching users.';

  @override
  String adminLoadMore(Object loaded, Object total) {
    return 'Load more (loaded $loaded / $total)';
  }

  @override
  String get adminTotalUsers => 'Total Users';

  @override
  String get adminDatabaseAccounts => 'Database accounts';

  @override
  String get adminSuperAdmin => 'Super Admin';

  @override
  String get adminHighestPrivilege => 'Highest privilege';

  @override
  String get adminSystemMaintenance => 'System maintenance';

  @override
  String get adminMemberGuest => 'Member / Guest';

  @override
  String get adminBusinessAccess => 'Business access';

  @override
  String get adminNotSetEmail => 'Email not set';

  @override
  String get adminDisable => 'Disable';

  @override
  String get adminRole => 'Role';

  @override
  String get adminQuota => 'Quota';

  @override
  String get adminUnlimited => 'Unlimited';

  @override
  String get adminBatchQuota => 'Batch Set Quota';

  @override
  String get adminDeselect => 'Deselect';

  @override
  String adminSelectedUsers(Object count) {
    return '$count users selected';
  }

  @override
  String adminBatchSetStorageQuota(Object count) {
    return 'Batch Set Storage Quota ($count users)';
  }

  @override
  String get adminBatchQuotaHint =>
      'Will set the same storage quota for all selected users. Super admins and users with insufficient space will be skipped.';

  @override
  String get adminQuotaGib => 'Quota (GiB)';

  @override
  String get adminQuotaHint => 'e.g. 50';

  @override
  String get adminSaving => 'Saving';

  @override
  String get adminSave => 'Save';

  @override
  String get adminValidQuotaRequired => 'Please enter a valid quota value';

  @override
  String get adminNoUsersSelected => 'No users selected';

  @override
  String adminUsersQuotaUpdated(Object count) {
    return 'Updated storage quota for $count users';
  }

  @override
  String adminEditQuota(Object name) {
    return 'Adjust Storage Quota for $name';
  }

  @override
  String adminCurrentUsage(Object used, Object quota) {
    return 'Current usage: $used / $quota';
  }

  @override
  String get adminNewQuotaGib => 'New Quota (GiB)';

  @override
  String adminQuotaMinError(Object used) {
    return 'New quota cannot be less than current used space ($used GiB)';
  }

  @override
  String adminEditRoles(Object name) {
    return 'Adjust Roles for $name';
  }

  @override
  String get adminSelectAtLeastOneRole => 'Please select at least one role';

  @override
  String get adminCreating => 'Creating';

  @override
  String get adminCreate => 'Create';

  @override
  String get adminUsername => 'Username';

  @override
  String get adminEnterUsername => 'Please enter username';

  @override
  String get adminDisplayName => 'Display Name';

  @override
  String get adminEmail => 'Email';

  @override
  String get adminInitialPassword => 'Initial Password';

  @override
  String get adminEnterInitialPassword => 'Please enter initial password';

  @override
  String get adminPasswordMinChars => 'Password must be at least 8 characters';

  @override
  String get adminPasswordMaxChars => 'Password must be at most 24 characters';

  @override
  String get adminRoleLabel => 'Role';

  @override
  String get adminConsole => 'Admin Console';

  @override
  String get adminConsoleSubtitle =>
      'Key metrics of users, permissions, runtime status and storage capacity.';

  @override
  String get adminAccountOverview => 'Account Overview';

  @override
  String get adminActive => 'Active';

  @override
  String get adminPermissionModel => 'Permission Model';

  @override
  String adminPermissionBindingsCount(Object count) {
    return '$count permission bindings';
  }

  @override
  String get adminTasks => 'Tasks';

  @override
  String get adminRunningLabel => 'Running';

  @override
  String get adminQueued => 'Queued';

  @override
  String get adminCompleted => 'Completed';

  @override
  String get adminNeedAttention => 'Need attention';

  @override
  String get adminStorageAssets => 'Storage Assets';

  @override
  String adminFilesFolders(Object files, Object folders) {
    return '$files files · $folders folders';
  }

  @override
  String get adminObjects => 'Objects';

  @override
  String get adminHealthy => 'Healthy';

  @override
  String get adminFiles => 'Files';

  @override
  String get adminFolders => 'Folders';

  @override
  String get adminExternalStorageLabel => 'External Storage';

  @override
  String get adminWarning => 'Warning';

  @override
  String get adminActivityChart => 'Activity Chart';

  @override
  String get adminActivityChartSubtitle =>
      'Admin-side trend view generated from current system statistics.';

  @override
  String get adminHealthStatus => 'Health Status';

  @override
  String get adminHealthStatusSubtitle =>
      'Health status from admin aggregation endpoint.';

  @override
  String get adminUserLabel => 'Users';

  @override
  String get adminTaskLabel => 'Tasks';

  @override
  String get adminStorageLabel => 'Storage';

  @override
  String get adminAnalyticsPage => 'Analytics';

  @override
  String get adminAnalyticsPageSubtitle =>
      'Centralized view of account growth, capacity trends, task throughput and system load.';

  @override
  String get adminAccountGrowth => 'Account Growth';

  @override
  String get adminTaskThroughput => 'Task Throughput';

  @override
  String get adminCompletedLabel => 'completed';

  @override
  String get adminExceptions => 'exceptions';

  @override
  String get adminStorageOccupancy => 'Storage Occupancy';

  @override
  String get adminObjectsLabel => 'objects';

  @override
  String get adminSystemLoad => 'System Load';

  @override
  String get adminHotConfig => 'Hot Config';

  @override
  String get adminRestartItems => 'Restart Items';

  @override
  String get adminStatusEnabled => 'Enabled';

  @override
  String get adminStatusDisabled => 'Disabled';

  @override
  String get adminGroupOverview => 'Overview';

  @override
  String get adminGroupOperations => 'Operations';

  @override
  String get adminGroupIdentity => 'Identity & Permissions';

  @override
  String get adminGroupConfiguration => 'System Config';

  @override
  String get adminGroupStorage => 'Storage';

  @override
  String get adminNavOverview => 'Console Home';

  @override
  String get adminNavAnalytics => 'Analytics';

  @override
  String get adminNavMonitoring => 'System Monitor';

  @override
  String get adminNavLogs => 'Log Center';

  @override
  String get adminNavTasks => 'Background Tasks';

  @override
  String get adminNavSessions => 'Session Management';

  @override
  String get adminNavUsers => 'User Management';

  @override
  String get adminNavRoles => 'Role Management';

  @override
  String get adminNavConfig => 'Config Center';

  @override
  String get adminNavStorage => 'Storage Management';

  @override
  String get adminNavExternalStorage => 'External Storage';

  @override
  String get adminOverviewTitle => 'Admin Console';

  @override
  String get adminOverviewSubtitle =>
      'Key metrics of users, permissions, runtime status and storage capacity.';

  @override
  String get adminAnalyticsTitle => 'Analytics';

  @override
  String get adminAnalyticsSubtitle =>
      'Centralized view of account growth, capacity trends, task throughput and system load.';

  @override
  String get adminMonitoringTitle => 'System Monitor';

  @override
  String get adminMonitoringSubtitle2 =>
      'View health checks, service metrics, node status and alerts.';

  @override
  String get adminLogsTitle => 'Log Center';

  @override
  String get adminLogsSubtitle =>
      'Unified view of application logs, error logs and login audit.';

  @override
  String get adminTasksTitle => 'Background Tasks';

  @override
  String get adminTasksSubtitle =>
      'Track indexing, transcoding, sync, backup and cleanup tasks.';

  @override
  String get adminSectionForbidden =>
      'You do not have permission to open this admin section.';

  @override
  String get adminSessionsTitle => 'Session Management';

  @override
  String get adminSessionsSubtitle =>
      'View and manage user active sessions, supports forced logout.';

  @override
  String get adminUsersTitle => 'User Management';

  @override
  String get adminUsersSubtitle =>
      'Manage accounts, status, quota and role assignment.';

  @override
  String get adminRolesTitle => 'Role Management';

  @override
  String get adminRolesSubtitle =>
      'Maintain roles, permission sets and resource access boundaries.';

  @override
  String get adminConfigTitle => 'Config Center';

  @override
  String get adminConfigSubtitle =>
      'Manage system config items, feature flags and hot update release status.';

  @override
  String get adminStorageTitle => 'Storage Management';

  @override
  String get adminStorageSubtitle =>
      'Manage MinIO buckets, capacity, and index maintenance.';

  @override
  String get adminExternalStorageTitle => 'External Storage Integration';

  @override
  String get adminRefresh => 'Refresh';

  @override
  String get adminRecalculate => 'Recalculate';

  @override
  String adminRecalculateDone(Object count) {
    return 'Updated storage for $count users';
  }

  @override
  String get adminRebuildIndex => 'Rebuild Index';

  @override
  String adminRebuildIndexDone(Object count) {
    return 'Cleared $count index documents, re-indexing in progress';
  }

  @override
  String get adminApiResponseFormat => 'Admin response format is incorrect';

  @override
  String get adminNoResponse => 'Server did not return admin result';

  @override
  String get adminOperationFailed => 'Admin operation failed';

  @override
  String get adminUserListFormat => 'User list format is incorrect';

  @override
  String get adminUserResponseFormat => 'User response format is incorrect';

  @override
  String get adminNoUserResult => 'Server did not return user result';

  @override
  String get adminUserOperationFailed => 'User operation failed';

  @override
  String get adminConsoleResponseFormat =>
      'Admin console response format is incorrect';

  @override
  String get adminNoConsoleResult =>
      'Server did not return admin console result';

  @override
  String get adminConsoleLoadFailed => 'Admin console load failed';

  @override
  String get adminNoDetailDiagnostics => 'No detailed diagnostics available';

  @override
  String get readerNavBookshelf => 'Bookshelf';

  @override
  String get readerNavLibrary => 'Library';

  @override
  String get readerNavStats => 'Stats';

  @override
  String get readerNavManage => 'Manage';

  @override
  String get readerShelfEmpty =>
      'Your shelf is empty. Add books from the library.';

  @override
  String get readerShelfEmptyHint =>
      'Browse the library and add books to your shelf.';

  @override
  String get readerStatsActivity => 'Reading Activity';

  @override
  String get readerStatsTitle => 'Statistics';

  @override
  String get adminHistoryEmpty => 'No reading sessions yet.';

  @override
  String get readerStatsLast14 => 'Last 14 days';

  @override
  String get readerStatsCompleted => 'Completed';

  @override
  String get readerStatsInProgress => 'In Progress';

  @override
  String get readerStatsInLibrary => 'In Library';

  @override
  String get readerStatsBooksRead => 'Books Read';

  @override
  String get readerStatsDayUnit => 'days';

  @override
  String get readerDetailInfo => 'About';

  @override
  String get readerDetailChapters => 'Chapters';

  @override
  String get readerDetailAnnotations => 'Annotations';

  @override
  String get readerDetailBookmarks => 'Bookmarks';

  @override
  String get readerDetailProgress => 'Progress';

  @override
  String get readerDetailComplete => 'Complete';

  @override
  String get readerDetailType => 'Type';

  @override
  String get readerDetailLanguage => 'Language';

  @override
  String get readerDetailAdded => 'Added';

  @override
  String get readerDetailLastRead => 'Last read';

  @override
  String get readerDetailWords => 'Words';

  @override
  String get readerDetailMinRead => 'min read';

  @override
  String get readerDetailEditMeta => 'Edit metadata';

  @override
  String get readerDetailReparse => 'Reparse';

  @override
  String get readerDetailNoAnn => 'No annotations yet.';

  @override
  String get readerDetailNoBm => 'No bookmarks yet.';

  @override
  String get readerNavComics => 'Comics';

  @override
  String get readerSegmentAll => 'All';

  @override
  String get readerSegmentBooks => 'Books';

  @override
  String get readerSegmentComics => 'Comics';

  @override
  String get readerNavBookmarks => 'Bookmarks';

  @override
  String get readerNavFavorites => 'Favorites';

  @override
  String get readerManageHint =>
      'Management tools visible to super admins only';

  @override
  String get readerSearchHint => 'Search book titles, authors…';

  @override
  String get readerSearch => 'Search';

  @override
  String get readerThemeLight => 'Light';

  @override
  String get readerThemeEyeCare => 'Eye Care';

  @override
  String get readerThemeDark => 'Dark';

  @override
  String get readerThemeGreen => 'Green';

  @override
  String get readerSettingsTitle => 'Reading Settings';

  @override
  String get readerReadingMode => 'Reading Mode';

  @override
  String get readerModeScroll => 'Scroll';

  @override
  String get readerModePage => 'Page';

  @override
  String get readerFontSize => 'Font Size';

  @override
  String get readerLineHeight => 'Line Height';

  @override
  String get readerFontFamily => 'Font';

  @override
  String get readerFontSerif => 'Serif';

  @override
  String get readerFontSans => 'Sans';

  @override
  String get readerFontSystem => 'System';

  @override
  String get readerTheme => 'Theme';

  @override
  String get readerImmersiveMode => 'Immersive mode';

  @override
  String get readerPreviousPage => 'Previous page';

  @override
  String get readerNextPage => 'Next page';

  @override
  String get readerPreviousChapter => 'Previous chapter';

  @override
  String get readerReadAloud => 'Read aloud';

  @override
  String get readerShortcutsTitle => 'Keyboard shortcuts';

  @override
  String get readerShortcutNavigation => 'Reading navigation';

  @override
  String get readerShortcutTurnPage => 'Turn a page or move one viewport';

  @override
  String get readerShortcutContents => 'Open or close contents';

  @override
  String get readerShortcutBookmark => 'Add or remove bookmark';

  @override
  String get readerShortcutSearch => 'Search the current chapter';

  @override
  String get readerShortcutAnnotations => 'Open annotations and notes';

  @override
  String get readerShortcutImmersive => 'Toggle immersive mode';

  @override
  String get readerShortcutFullscreen => 'Toggle fullscreen';

  @override
  String get readerShortcutTypography => 'Adjust or reset typography';

  @override
  String get readerShortcutClose => 'Close the current panel or go back';

  @override
  String get readerShortcutMode => 'Switch comic reading mode';

  @override
  String get readerSearchCurrentChapter => 'Search current chapter';

  @override
  String get readerNoSearchResults => 'No matching content found';

  @override
  String readerSearchResultCount(int count) {
    return '$count matches';
  }

  @override
  String readerReadingProgress(int percent) {
    return 'Reading progress $percent%';
  }

  @override
  String get readerResetTypography => 'Reset typography';

  @override
  String get readerComicModePage => 'Page mode';

  @override
  String get readerComicModeScroll => 'Scroll mode';

  @override
  String get readerComicFullWidth =>
      'Use all available width in continuous mode';

  @override
  String get readerComicFullWidthHint =>
      'Turn off to limit page width on desktop and avoid excessive upscaling';

  @override
  String readerComicContentWidth(int width) {
    return 'Content width: $width px';
  }

  @override
  String readerComicPageGap(int gap) {
    return 'Page spacing: $gap px';
  }

  @override
  String get readerComicImageLoadFailed => 'Comic page failed to load';

  @override
  String get readerComicImageDecodeFailed => 'Comic page failed to decode';

  @override
  String get readerStatsToday => 'Today';

  @override
  String get readerStatsWeek => 'This week';

  @override
  String get readerStatsStreak => 'Streak';

  @override
  String get readerStatsBooks => 'Books';

  @override
  String readerStatsMinutes(Object count) {
    return '$count min';
  }

  @override
  String readerStatsHoursMinutes(Object hours, Object minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String readerStatsHours(Object hours) {
    return '${hours}h';
  }

  @override
  String readerStatsDays(Object count) {
    return '${count}d';
  }

  @override
  String get readerNoContent => 'No content';

  @override
  String get readerTtsPlay => 'Play';

  @override
  String get readerTtsPause => 'Pause';

  @override
  String get readerTtsStop => 'Stop';

  @override
  String get readerAlreadyFirstChapter => 'Already at the first chapter';

  @override
  String get readerAlreadyLastChapter => 'Already at the last chapter';

  @override
  String get readerRestoringProgress => 'Restoring reading position…';

  @override
  String get readerReturnToProgress => 'Return to last position';

  @override
  String get readerReturn => 'Return';

  @override
  String get readerBookmarkRemoved => 'Bookmark removed';

  @override
  String get readerBookmarkAdded => 'Bookmark added';

  @override
  String get readerBookmarkFailed => 'Bookmark operation failed';

  @override
  String get readerHighlightAdded => 'Highlight added';

  @override
  String get readerAddAnnotation => 'Add Annotation';

  @override
  String get readerAnnotationHint => 'Enter your notes...';

  @override
  String get readerAddBookmark => 'Add bookmark';

  @override
  String get readerRemoveBookmark => 'Remove bookmark';

  @override
  String get readerChapterList => 'Chapter List';

  @override
  String get readerOperationFailed =>
      'Operation failed, please try again later';

  @override
  String get readerOperationSubmitted => 'Operation submitted';

  @override
  String get readerChapterLoadFailed =>
      'The chapter could not be loaded. Please try again.';

  @override
  String get readerRemoveFavorite => 'Remove from favorites';

  @override
  String get readerAddFavorite => 'Add to favorites';

  @override
  String get readerReadComic => 'Read Comic';

  @override
  String get readerNoPages => 'No pages available';

  @override
  String get readerContinueReading => 'Continue Reading';

  @override
  String get readerNavNotes => 'Notes';

  @override
  String get readerStartReading => 'Start Reading';

  @override
  String get readerAddedToBookshelf => 'Added to Bookshelf';

  @override
  String get readerAddToBookshelf => 'Add to Bookshelf';

  @override
  String get readerNoDescription => 'No description';

  @override
  String get readerDescription => 'Description';

  @override
  String get readerCollapse => 'Collapse';

  @override
  String get readerExpandFull => 'Show full text';

  @override
  String readerChapterListCount(Object count) {
    return 'Chapter List ($count chapters)';
  }

  @override
  String readerTotalPages(Object count) {
    return '$count pages total';
  }

  @override
  String readerPageCount(Object count) {
    return '$count pages';
  }

  @override
  String readerViewAllChapters(Object count) {
    return 'View all $count chapters';
  }

  @override
  String get readerPageInfo => 'Page Info';

  @override
  String get readerTableOfContents => 'Table of Contents';

  @override
  String readerTotalChapters(Object count) {
    return '$count chapters total';
  }

  @override
  String get readerDeleteCollection => 'Delete Collection';

  @override
  String readerCollectionCount(Object count) {
    return '$count items';
  }

  @override
  String get readerCollectionEmpty => 'No books in this collection';

  @override
  String get readerCollectionEmptyHint =>
      'Long press a book on the bookshelf to add it to a collection.';

  @override
  String get readerConfirmDeleteCollection => 'Delete collection';

  @override
  String readerConfirmDeleteCollectionMsg(Object name) {
    return 'Are you sure you want to delete \"$name\"? Books in the collection will not be deleted.';
  }

  @override
  String readerDeletedCollection(Object name) {
    return 'Deleted \"$name\"';
  }

  @override
  String readerDeleteFailed(Object error) {
    return 'Delete failed: $error';
  }

  @override
  String get readerNoChanges => 'No changes made';

  @override
  String get readerMetadataSaved => 'Metadata saved';

  @override
  String readerSaveFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get readerEditMetadata => 'Edit Metadata';

  @override
  String get readerSave => 'Save';

  @override
  String get readerLabelTitle => 'Title';

  @override
  String get readerLabelAuthor => 'Author';

  @override
  String get readerLabelDescription => 'Description';

  @override
  String get readerLabelPublisher => 'Publisher';

  @override
  String get readerLabelReleaseDate => 'Release Date';

  @override
  String get readerLabelRating => 'Rating (0-10)';

  @override
  String get readerLabelGenres => 'Genre Tags (comma separated)';

  @override
  String get readerLabelSerialStatus => 'Serial Status';

  @override
  String get readerStatusOngoing => 'Ongoing';

  @override
  String get readerStatusCompleted => 'Completed';

  @override
  String get readerStatusUnknown => 'Unknown';

  @override
  String get readerSelectFromFile => 'Select from Files';

  @override
  String get readerUploadCover => 'Upload New Cover';

  @override
  String get readerNoImageFiles =>
      'No image files available in the file system';

  @override
  String get readerSelectCoverImage => 'Select Cover Image';

  @override
  String get readerUnknownFile => 'Unknown file';

  @override
  String get readerCoverUpdated => 'Cover updated';

  @override
  String readerOperationFailedError(Object error) {
    return 'Operation failed: $error';
  }

  @override
  String get readerCoverUploaded => 'Cover uploaded';

  @override
  String readerUploadFailed(Object error) {
    return 'Upload failed: $error';
  }

  @override
  String readerPageInfoFormat(Object current, Object total) {
    return 'Page $current / $total pages';
  }

  @override
  String readerPageNumber(Object page) {
    return 'Page $page';
  }

  @override
  String readerWordCount(Object count) {
    return '$count characters';
  }

  @override
  String readerWordCountWan(Object count) {
    return '$count 万';
  }

  @override
  String get readerRetry => 'Retry';

  @override
  String get readerRtl => 'Right to Left (RTL)';

  @override
  String get readerLtr => 'Left to Right (LTR)';

  @override
  String get readerChapterListBtn => 'Chapter List';

  @override
  String get readerPrevChapter => 'Previous Chapter';

  @override
  String get readerNextChapter => 'Next Chapter';

  @override
  String get readerClose => 'Close';

  @override
  String readerDeletedItem(Object name) {
    return 'Deleted \"$name\"';
  }

  @override
  String get readerDeleteItemFailed => 'Delete failed, please try again later';

  @override
  String get readerRemovedFromBookshelf => 'Removed from bookshelf';

  @override
  String get readerSearchBooksHint => 'Search book titles, authors…';

  @override
  String readerCollectionCreated(Object name) {
    return 'Collection \"$name\" created';
  }

  @override
  String get readerCreateFailed => 'Create failed, please try again later';

  @override
  String readerImportSuccess(Object name) {
    return '\"$name\" imported successfully';
  }

  @override
  String get readerImportFailed => 'Import failed, please try again later';

  @override
  String readerImportFailedWithReason(Object name, Object reason) {
    return 'Failed to import $name: $reason';
  }

  @override
  String get readerImportFromFile => 'Import from device';

  @override
  String get readerImporting => 'Importing...';

  @override
  String get readerImportTypeTitle => 'Choose EPUB import type';

  @override
  String get readerImportTypeDesc =>
      'Fixed-layout or image-based EPUB files can be imported as comics. Text EPUB files should usually be imported as books.';

  @override
  String get readerImportNovel => 'Book';

  @override
  String get readerImportLiterature => 'Literature';

  @override
  String get readerImportAcademic => 'Academic';

  @override
  String get readerImportTechnical => 'Technical';

  @override
  String get readerImportPoetry => 'Poetry';

  @override
  String get readerImportEssay => 'Essay';

  @override
  String get readerImportComic => 'Comic';

  @override
  String get readerPendingImport => 'Pending Import';

  @override
  String readerPendingImportCount(Object count) {
    return '$count files';
  }

  @override
  String get readerPendingImportDesc =>
      'These files have been uploaded but not yet imported to the Reader Center. EPUB files can be imported as books or comics.';

  @override
  String get readerNoPendingImport => 'No files pending import';

  @override
  String get readerNoPendingImportHint =>
      'After uploading EPUB, CBZ and other reading files, they will appear here. Already imported files won\'t be shown again.';

  @override
  String get readerReparse => 'Re-parse';

  @override
  String get readerReparseDesc =>
      'Re-parse cover, metadata and chapters for imported content. Useful when parsing was incomplete or new parsing capabilities have been added.';

  @override
  String get readerNoImportedContent => 'No imported content';

  @override
  String get readerNoImportedContentHint =>
      'After importing books, you can re-parse them here.';

  @override
  String get readerNoFileNode => 'This entry has no file node, cannot re-parse';

  @override
  String readerReparseSuccess(Object name) {
    return '\"$name\" re-parsed successfully';
  }

  @override
  String readerComicReparseStarted(Object name) {
    return '\"$name\" re-parse has started. Refresh later to view the status.';
  }

  @override
  String get readerReparseFailed => 'Re-parse failed, please try again later';

  @override
  String get readerComicImportStatusTitle => 'Comic Parse Status';

  @override
  String readerComicImportStatusValue(Object status) {
    return 'Current status: $status';
  }

  @override
  String readerComicSourceCount(Object count) {
    return '$count sources';
  }

  @override
  String readerComicCatalogCount(Object count) {
    return '$count catalog entries';
  }

  @override
  String get readerComicCatalogPreview => 'Catalog Structure';

  @override
  String get readerComicPagePreview => 'Page Preview';

  @override
  String get readerComicCatalogPending =>
      'Catalog parsing is still in progress. Refresh later to view the result.';

  @override
  String get readerComicPagesPending =>
      'Pages are still being parsed. Refresh later to view previews.';

  @override
  String get readerComicImportPending => 'Waiting to parse';

  @override
  String get readerComicImportParsing => 'Parsing';

  @override
  String get readerComicImportReady => 'Ready';

  @override
  String get readerComicImportPartialFailed => 'Partially Failed';

  @override
  String get readerComicImportFailed => 'Parse Failed';

  @override
  String get readerComicEmptyTitle => 'No comics yet';

  @override
  String get readerComicEmptyHint =>
      'Import a CBZ, ZIP, or image-based EPUB to start reading.';

  @override
  String get readerComicParsingMessage => 'The comic is being parsed…';

  @override
  String get readerComicPartialFailedMessage =>
      'Some sources failed to parse. Retry or remove the failed sources.';

  @override
  String get readerComicFailedMessage =>
      'Parsing failed. Retry the failed source.';

  @override
  String get readerComicSources => 'Sources';

  @override
  String readerComicRetryCount(Object count) {
    return 'Retried $count times';
  }

  @override
  String get readerRefreshFailed => 'Refresh failed, please try again later';

  @override
  String get readerDone => 'Done';

  @override
  String get readerUnsupportedLink => 'This link is not supported yet';

  @override
  String get readerUnknownAuthor => 'Unknown author';

  @override
  String get readerUnknownBook => 'Unknown book';

  @override
  String get readerReadingReport => 'Reading Report';

  @override
  String readerWeeklyHours(Object hours) {
    return 'Read $hours hours this week';
  }

  @override
  String get readerContinueBtn => 'Continue Reading';

  @override
  String get readerBookshelfSection => 'Bookshelf';

  @override
  String readerShowAllBooks(Object count) {
    return 'Show all $count more';
  }

  @override
  String get readerViewAll => 'View all';

  @override
  String readerBookCount(Object count) {
    return '$count items';
  }

  @override
  String readerContinueCount(Object count) {
    return '$count continue';
  }

  @override
  String get readerRefresh => 'Refresh';

  @override
  String get readerAddBook => 'Add Book';

  @override
  String get readerImportQueued =>
      'File uploaded. Import is running in the background...';

  @override
  String get readerImportQueuedShort => 'Waiting to upload';

  @override
  String get readerImportRegistering => 'Adding to library';

  @override
  String get readerCancelImport => 'Stop import';

  @override
  String get readerImportCancelled => 'Import cancelled';

  @override
  String get readerMetadataManagement => 'Metadata Management';

  @override
  String get readerMetadataDesc =>
      'Manually edit metadata for books/comics, including title, author, description, cover, etc. Visible to super admins only.';

  @override
  String get readerNoBookEntries => 'No book entries';

  @override
  String get readerNoBookEntriesHint =>
      'Import books to manage their metadata here.';

  @override
  String get readerStatusPending => 'Pending';

  @override
  String get readerStatusFailed => 'Failed';

  @override
  String get readerStatusManual => 'Manual';

  @override
  String get readerStatusMatched => 'Matched';

  @override
  String get readerEdit => 'Edit';

  @override
  String get readerScrapeQueue => 'Scrape Queue';

  @override
  String get readerScrapeQueueDesc =>
      'Entries missing metadata (description, rating, genre, etc.) can be manually scraped. Visible to super admins only.';

  @override
  String get readerAllMetadataComplete => 'All entries have complete metadata';

  @override
  String get readerScrapeHint =>
      'Newly imported books will be automatically scraped. You can also manually retry from the detail page.';

  @override
  String readerScrapeSubmitted(Object id) {
    return 'Scrape task submitted: $id…';
  }

  @override
  String get readerScrapeSubmitFailed =>
      'Scrape task submission failed, please try again later';

  @override
  String get readerSubmitting => 'Submitting…';

  @override
  String get readerBatchScrape => 'Batch Scrape';

  @override
  String readerBatchScrapeResult(Object success, Object total) {
    return 'Submitted $success / $total scrape tasks';
  }

  @override
  String get readerSubmittingLabel => 'Submitting';

  @override
  String get readerScrapeLabel => 'Scrape';

  @override
  String get readerRemoveFromBookshelf => 'Remove from Bookshelf';

  @override
  String get readerDeleteBook => 'Delete Book';

  @override
  String get readerDeleteBookHint =>
      'Permanently delete the book and its source file';

  @override
  String get readerDeleteSource => 'Delete source';

  @override
  String readerConfirmDeleteSource(Object name) {
    return 'Delete source \"$name\"? Its parsed pages will be removed from this comic, while the original file remains in Files.';
  }

  @override
  String get readerConfirmDelete => 'Confirm Permanent Deletion';

  @override
  String readerConfirmDeleteMsg(Object name) {
    return 'Remove \"$name\" from the library? The source file will be kept.';
  }

  @override
  String readerFieldRequired(Object field) {
    return '$field cannot be empty';
  }

  @override
  String get readerHistory => 'History';

  @override
  String get readerImports => 'Imports';

  @override
  String get readerGroupPersonal => 'Personal';

  @override
  String get readerGroupTools => 'Tools';

  @override
  String get readerGroupManagement => 'Management';

  @override
  String readerPercentRead(Object percent) {
    return '$percent% read';
  }

  @override
  String readerSectionNotAvailable(Object section) {
    return '$section not yet available';
  }

  @override
  String get readerSectionNotAvailableHint =>
      'This entry has been reserved and will be connected to an independent content page later.';

  @override
  String get readerNoBookmarks => 'No bookmarks yet';

  @override
  String get readerNoBookmarksHint =>
      'Add bookmarks while reading to quickly jump back here later.';

  @override
  String get readerEmptyHint => 'No content here yet';

  @override
  String get readerEmptyHintDesc =>
      'After importing books from the file manager, they will automatically appear on the bookshelf.';

  @override
  String get readerHighlight => 'Highlight';

  @override
  String get readerAnnotate => 'Annotate';

  @override
  String get readerRemoveHighlight => 'Remove highlight';

  @override
  String get readerRemoveAnnotation => 'Remove annotation';

  @override
  String get readerCopy => 'Copy';

  @override
  String get readerAnnotations => 'Annotations';

  @override
  String get readerNoAnnotations => 'No annotations yet';

  @override
  String get readerEditAnnotation => 'Edit annotation';

  @override
  String get readerDeleteAnnotation => 'Delete annotation';

  @override
  String get readerSearchAnnotations => 'Search annotations';

  @override
  String get readerSearchAnnotationsHint => 'Search annotations...';

  @override
  String get readerThisChapter => 'This chapter';

  @override
  String get readerAllChapters => 'All chapters';

  @override
  String get readerPageTransition => 'Page Transition';

  @override
  String get readerTransitionSlide => 'Slide';

  @override
  String get readerTransitionCover => 'Cover';

  @override
  String get readerTransitionFade => 'Fade';

  @override
  String get readerTransitionScroll => 'Vertical';

  @override
  String get videoSectionMovies => 'Movies';

  @override
  String get videoSectionTvShows => 'TV Shows';

  @override
  String get videoSectionAnime => 'Anime';

  @override
  String get videoSectionCollections => 'Collections';

  @override
  String get videoSectionRecent => 'Recently Added';

  @override
  String get videoSectionContinueWatching => 'Continue Watching';

  @override
  String get videoSectionFavorites => 'Favorites';

  @override
  String get videoSectionHistory => 'Watch History';

  @override
  String get videoSeriesFeatured => 'Featured';

  @override
  String get videoSectionMetadataManagement => 'Metadata';

  @override
  String get videoSectionLibraryScan => 'Media Library Management';

  @override
  String get videoSidebarGroupLibrary => 'Media Library';

  @override
  String get videoSidebarGroupMine => 'My Media';

  @override
  String get videoSidebarGroupManagement => 'Management Tools';

  @override
  String get videoRefreshTooltip => 'Refresh';

  @override
  String get videoBackToPortal => 'Portal home';

  @override
  String get videoBackToLibrary => 'Back to library';

  @override
  String get videoSearchMovies => 'Search Movies';

  @override
  String get videoSearchMovieHint => 'Enter movie name...';

  @override
  String get videoCancel => 'Cancel';

  @override
  String get videoSearch => 'Search';

  @override
  String get videoManageAdminOnly => 'Management tools visible to admins only';

  @override
  String get videoBrowse => 'Browse';

  @override
  String get videoMore => 'More';

  @override
  String get videoClose => 'Close';

  @override
  String get videoSearchLibraryHint => 'Search movie library...';

  @override
  String get videoMovieLibrary => 'Media Library';

  @override
  String get videoMovieLibrarySubtitle =>
      'Browse movies, TV series, and anime with filters and categories.';

  @override
  String get videoAnimeLibrary => 'Anime Library';

  @override
  String get videoAnimeLibrarySubtitle =>
      'Japanese anime organized by series, click to view details, season/episode list and direct playback.';

  @override
  String get videoRecentSubtitle =>
      'Content added in the last 30 days is shown here.';

  @override
  String get videoFavoritesSubtitle =>
      'Movies and TV shows starred by the current user are shown here.';

  @override
  String videoSeasonProgress(Object season, Object current, Object total) {
    return 'Season $season - $current/$total episodes';
  }

  @override
  String get videoDefaultVersion => 'Default Version';

  @override
  String get videoSelectVersion => 'Select Version';

  @override
  String get videoPlay => 'Play';

  @override
  String get videoFavorited => 'Favorited';

  @override
  String get videoFavorite => 'Favorite';

  @override
  String get videoSubtitle => 'Subtitles';

  @override
  String get videoAudio => 'Audio';

  @override
  String get videoMovedToRecycleBin =>
      'Media item and source file permanently deleted';

  @override
  String get videoDelete => 'Delete';

  @override
  String get videoDeleteItemTitle => 'Delete media item?';

  @override
  String videoDeleteItemMessage(Object title) {
    return '\"$title\" and its source file will be permanently deleted. This cannot be undone.';
  }

  @override
  String get videoSubtitleManagement => 'Subtitle Management';

  @override
  String get videoNoSubtitles => 'No subtitles available';

  @override
  String get videoSubtitleLoadFailed => 'Failed to load subtitle info';

  @override
  String get videoUploading => 'Uploading...';

  @override
  String get videoUploadSubtitle => 'Upload Subtitle File';

  @override
  String get videoSubtitleUploaded => 'Subtitle uploaded successfully';

  @override
  String get videoDeleteSubtitleTitle => 'Delete Subtitle?';

  @override
  String videoDeleteSubtitleMessage(Object label) {
    return 'Are you sure you want to delete subtitle \"$label\"?';
  }

  @override
  String get videoSubtitleDeleted => 'Subtitle deleted';

  @override
  String get videoSubtitleLanguage => 'Subtitle Language';

  @override
  String get videoSubtitleLanguageHint => 'e.g. chi, eng, jpn';

  @override
  String get videoConfirm => 'Confirm';

  @override
  String get videoEmbedded => 'Embedded';

  @override
  String get videoExternal => 'External';

  @override
  String get videoDeleteSubtitleTooltip => 'Delete subtitle';

  @override
  String get videoAudioManagement => 'Audio Management';

  @override
  String get videoOriginalAudio => 'Original Audio';

  @override
  String get videoUnknown => 'Unknown';

  @override
  String get videoCompatibleAudioCache => 'Compatible Audio Cache';

  @override
  String get videoNotExtracted => 'Not extracted';

  @override
  String get videoLoadFailed => 'Load failed';

  @override
  String videoAudioIncompatibleNotice(Object codec) {
    return 'Current audio codec $codec is incompatible with web browsers. After extracting compatible audio, the web player will use cached audio.';
  }

  @override
  String get videoCompatibleAudioReady => 'Compatible audio ready';

  @override
  String get videoExtracting => 'Extracting...';

  @override
  String get videoExtractCompatibleAudio => 'Extract Compatible Audio';

  @override
  String get videoAudioExtractCreated => 'Audio extraction task created';

  @override
  String get videoCached => 'Cached';

  @override
  String get videoIncompatible => 'Incompatible';

  @override
  String get videoCompatible => 'Compatible';

  @override
  String get videoCast => 'Cast';

  @override
  String get videoMediaGallery => 'Media Gallery';

  @override
  String get videoTrailer => 'Trailer';

  @override
  String get videoTechnicalInfo => 'Technical Info';

  @override
  String get videoScrapeStatus => 'Scrape Status';

  @override
  String get videoNfoExport => 'NFO Export';

  @override
  String get videoExported => 'Exported';

  @override
  String get videoNotExported => 'Not exported';

  @override
  String get videoDetecting => 'Detecting...';

  @override
  String get videoContainerFormat => 'Container Format';

  @override
  String get videoDuration => 'Duration';

  @override
  String get videoType => 'Type';

  @override
  String get videoMatched => 'Matched';

  @override
  String get videoPendingScrape => 'Pending';

  @override
  String get videoSectionMovieAdmin => 'Movie management';

  @override
  String get videoMovieAdminSubtitle =>
      'Manage metadata, scraping and transcoding for your library.';

  @override
  String get videoMovieAdminEmpty => 'No movies match the current filters.';

  @override
  String get videoLibraryFilterAll => 'All';

  @override
  String get videoPreviousPage => 'Previous page';

  @override
  String get videoNextPage => 'Next page';

  @override
  String get videoTaskProgressDialog => 'Task progress';

  @override
  String get videoSnackViewProgress => 'View progress';

  @override
  String get videoAdminLibrarySources => 'Library sources';

  @override
  String videoSeriesEpisodeCount(Object count) {
    return '$count episodes';
  }

  @override
  String get videoMatchFailed => 'Match Failed';

  @override
  String get videoManualEdit => 'Manual Edit';

  @override
  String get videoOverview => 'Overview';

  @override
  String get videoCollapse => 'Collapse';

  @override
  String get videoExpandAll => 'Expand All';

  @override
  String get videoRecommendations => 'Recommendations';

  @override
  String get videoWatchRecord => 'Watch Record';

  @override
  String get videoWatched => 'Watched';

  @override
  String get videoWatching => 'Watching';

  @override
  String get videoNoWatchRecord => 'No watch record';

  @override
  String videoLastPlayed(Object time) {
    return 'Last played: $time';
  }

  @override
  String get videoJustNow => 'Just now';

  @override
  String videoMinutesAgo(Object n) {
    return '$n min ago';
  }

  @override
  String videoHoursAgo(Object n) {
    return '$n hr ago';
  }

  @override
  String videoDaysAgo(Object n) {
    return '$n days ago';
  }

  @override
  String get videoHighRated => 'Top Rated';

  @override
  String get videoNewest => 'Newest Releases';

  @override
  String get videoViewMore => 'View More';

  @override
  String get videoContinueSubtitle =>
      'Shows unfinished movies and TV shows, click card to resume playback.';

  @override
  String get videoNoContinueRecord => 'No continue watching records.';

  @override
  String get videoCollectionsSubtitle =>
      'Supports user-defined or auto-generated collections, such as movie universes, director filmographies and family collections.';

  @override
  String get videoNewCollection => 'New Collection';

  @override
  String get videoAllMedia => 'All Media';

  @override
  String get videoCustomCollection => 'Custom Collection';

  @override
  String get videoCollectionName => 'Collection Name';

  @override
  String get videoDescription => 'Description';

  @override
  String get videoCreate => 'Create';

  @override
  String get videoCollectionNameEmpty => 'Collection name cannot be empty';

  @override
  String get videoCollectionCreated => 'Collection created';

  @override
  String get videoCollectionEmpty => 'Collection is empty';

  @override
  String get videoCollectionAddMovies => 'Add Movies';

  @override
  String get videoCollectionPickerTitle => 'Select Movies';

  @override
  String get videoCollectionPickerSearchHint => 'Search titles';

  @override
  String get videoCollectionAlreadyAdded => 'Already in collection';

  @override
  String get videoCollectionPickerEmpty => 'No matching movies';

  @override
  String videoLoadFailedWith(Object error) {
    return 'Load failed: $error';
  }

  @override
  String get videoRequestTimeout => 'Request timed out, please try again later';

  @override
  String get videoConnectionError =>
      'Cannot connect to backend, please confirm the service is running';

  @override
  String get videoOperationCancelled => 'Operation cancelled';

  @override
  String get videoServerError =>
      'Server response error, please try again later';

  @override
  String get videoCertificateError =>
      'Certificate verification failed, please check service configuration';

  @override
  String get videoRequestFailed => 'Request failed, please try again later';

  @override
  String get videoOperationFailed => 'Operation failed, please try again later';

  @override
  String get videoProcessing => 'Processing';

  @override
  String get videoHistorySubtitle =>
      'Complete playback records with filtering by watched, unwatched and time range.';

  @override
  String get videoClearHistory => 'Clear History';

  @override
  String get videoNoWatchHistory => 'No watch history.';

  @override
  String get videoMoreFilters => 'More Filters';

  @override
  String get videoGenre => 'Genre';

  @override
  String get videoYear => 'Year';

  @override
  String get videoRating => 'Rating';

  @override
  String get videoSort => 'Sort';

  @override
  String get videoClear => 'Clear';

  @override
  String get videoSortDateAdded => 'Date Added';

  @override
  String get videoSortReleaseDate => 'Release Date';

  @override
  String get videoSortTitle => 'Title';

  @override
  String get videoNoMediaItems => 'No media items here yet.';

  @override
  String get videoTaskSubmitted => 'Task Submitted';

  @override
  String get videoRetry => 'Retry';

  @override
  String get videoSubmitting => 'Submitting';

  @override
  String get videoEdit => 'Edit';

  @override
  String get videoNfo => 'NFO';

  @override
  String videoEpisodeStatus(Object count, Object status) {
    return 'Series - $count episodes - $status';
  }

  @override
  String get videoParse => 'Parse';

  @override
  String get videoTranscode => 'Video Transcode';

  @override
  String get videoAudioExtract => 'Audio Extract';

  @override
  String get videoNoTasks => 'No tasks.';

  @override
  String get videoMetadataScrape => 'Metadata Scrape';

  @override
  String get videoMediaScan => 'Media Scan';

  @override
  String get videoQueued => 'Queued';

  @override
  String get videoRunning => 'Running';

  @override
  String get videoCompleted => 'Completed';

  @override
  String get videoFailed => 'Failed';

  @override
  String get videoCancelled => 'Cancelled';

  @override
  String get videoDeadLetterQueue => 'Dead Letter Queue';

  @override
  String get videoIncrementalScan => 'Incremental Scan';

  @override
  String get videoScanning => 'Scanning';

  @override
  String get videoIncrementalScanComplete => 'Incremental scan complete';

  @override
  String get videoFullScan => 'Full Scan';

  @override
  String get videoFullScanComplete => 'Full scan complete';

  @override
  String videoNfoPreviewTitle(Object title) {
    return 'NFO - $title';
  }

  @override
  String get videoSeriesLibrary => 'Series Library';

  @override
  String get videoSeriesLibrarySubtitle =>
      'TV series organized by series, click to view details, season/episode list and direct playback.';

  @override
  String get videoNoSeries => 'No series yet.';

  @override
  String get videoNoSeasonInfo => 'No season info';

  @override
  String get videoEpisodeList => 'Episode List';

  @override
  String videoSeasonTab(Object number) {
    return 'Season $number';
  }

  @override
  String get videoNoEpisodesInSeason => 'No episodes in this season';

  @override
  String get videoMediaCenter => 'Media Library';

  @override
  String videoSeasonLabel(Object number) {
    return 'Season $number';
  }

  @override
  String videoEpisodeLabel(Object number) {
    return 'Episode $number';
  }

  @override
  String get videoPreviousEpisode => 'Previous Episode';

  @override
  String get videoNextEpisode => 'Next Episode';

  @override
  String get videoTitleRequired => 'Title cannot be empty';

  @override
  String get videoMetadataSaved => 'Metadata saved';

  @override
  String get videoEditMetadataDesc =>
      'Edit title, overview, poster and backdrop for display. Saving will lock to manual metadata.';

  @override
  String get videoCoverAssets => 'Cover Assets';

  @override
  String get videoPosterFileId => 'Poster File ID';

  @override
  String get videoBackdropFileId => 'Backdrop File ID';

  @override
  String get videoCoverIdHint =>
      'Use file node ID to bind poster and backdrop; saving will immediately update Media Library display resources.';

  @override
  String get videoBrandVersion => 'Media Library v1.0';

  @override
  String get videoMetadataStatus => 'Metadata Status';

  @override
  String get videoManualLock => 'Manual Lock';

  @override
  String get videoPendingRecognition => 'Pending';

  @override
  String get videoRecognitionFailed => 'Recognition Failed';

  @override
  String get videoOriginalTitle => 'Original Title';

  @override
  String get videoReleaseDate => 'Release Date';

  @override
  String get videoRuntimeMinutes => 'Runtime (minutes)';

  @override
  String get videoOverviewLabel => 'Overview';

  @override
  String get videoSaveChanges => 'Save Changes';

  @override
  String get videoBackdrop => 'Backdrop';

  @override
  String get videoFillScreen => 'Fill Screen';

  @override
  String get videoOriginalAspectRatio => 'Original Aspect Ratio';

  @override
  String get videoCompatibleAudioNotice =>
      'Using compatible audio stream. Tap the audio button at the bottom to switch audio source.';

  @override
  String get videoGotIt => 'Got it';

  @override
  String get videoSubtitleTrack => 'Subtitle Track';

  @override
  String get videoNoSubtitlesAvailable =>
      'No subtitles available for this video';

  @override
  String get videoDisableSubtitles => 'Disable Subtitles';

  @override
  String get videoAudioTrack => 'Audio Track';

  @override
  String get videoCompatibleAudioAac => 'Compatible Audio (AAC Cache)';

  @override
  String get videoCompatibleAudioDesc =>
      'Pre-processed AAC audio stream, compatible with all web browsers';

  @override
  String videoOriginalAudioLabel(Object codec) {
    return 'Original Audio ($codec)';
  }

  @override
  String get videoOriginalAudioDesc =>
      'Real-time transcoded original audio, may require more processing time';

  @override
  String get videoPlaybackSpeed => 'Playback Speed';

  @override
  String get videoAspectRatio => 'Aspect Ratio';

  @override
  String get videoPlaybackSettings => 'Playback Settings';

  @override
  String get videoSubtitlesEnabled => 'Subtitles Enabled';

  @override
  String get videoSubtitlesOff => 'Off';

  @override
  String get videoSubtitlesOn => 'On';

  @override
  String get videoPlaybackInfo => 'Playback Info';

  @override
  String get videoInfoMode => 'Mode';

  @override
  String get videoInfoContainer => 'Container';

  @override
  String get videoInfoVideoCodec => 'Video Codec';

  @override
  String get videoInfoAudioCodec => 'Audio Codec';

  @override
  String get videoInfoAudioSource => 'Audio Source';

  @override
  String videoInfoSubtitleCount(Object count) {
    return '$count tracks';
  }

  @override
  String get videoInfoVolume => 'Volume';

  @override
  String get videoBackToDetail => 'Back to Detail';

  @override
  String videoStatusSubtitle(Object container, Object video, Object audio) {
    return 'Current video is $container/$video/$audio, browser does not support direct playback, streaming via server transcoding. Seek precision is limited, use desktop client for precise seeking.';
  }

  @override
  String videoLastPlayedTime(Object time) {
    return 'Last played: $time';
  }

  @override
  String get photosLoading => 'Loading...';

  @override
  String get photoThumbnailLoading => 'Loading thumbnail';

  @override
  String get photosTaskFailed => 'Task failed';

  @override
  String get photosTaskStatusRefreshFailed =>
      'Unable to refresh task status. Retrying automatically';

  @override
  String photosProcessedItems(Object count) {
    return '$count items completed';
  }

  @override
  String get photosDone => 'Done';

  @override
  String get photosRunInBackground => 'Run in background';

  @override
  String get photosSlideshow3s => '3s';

  @override
  String get photosSlideshow5s => '5s';

  @override
  String get photosSlideshow10s => '10s';

  @override
  String get photosTabHome => 'Home';

  @override
  String get photosTabFavorites => 'Favorites';

  @override
  String get photosTabTimeline => 'Timeline';

  @override
  String get photosTabAlbums => 'Albums';

  @override
  String get photosTabGroups => 'Groups';

  @override
  String get photosTabGraph => 'Graph';

  @override
  String get photosSurfaceLibrary => 'Library';

  @override
  String get photosSurfaceExplore => 'Explore';

  @override
  String get photosGraphKindAlbum => 'Albums';

  @override
  String get photosGraphKindTime => 'Time';

  @override
  String get photosGraphKindLocation => 'Places';

  @override
  String get photosGraphEmpty => 'No photo relationships are available yet.';

  @override
  String get photosGraphViewPhoto => 'View photo';

  @override
  String photosGraphPhotoCount(Object count) {
    return '$count photos';
  }

  @override
  String get photosGroupByDate => 'Time';

  @override
  String get photosGroupByLocation => 'Places';

  @override
  String get photosGroupByFormat => 'Formats';

  @override
  String get photosGroupByTag => 'Tags';

  @override
  String get photosEditTypeRotate => 'Rotate';

  @override
  String get photosEditTypeCrop => 'Crop';

  @override
  String get photosEditTypeBrightness => 'Brightness';

  @override
  String get photosEditTypeContrast => 'Contrast';

  @override
  String get photosEditTypeFilter => 'Filter';

  @override
  String get photosImportCompletedNotVisible =>
      'Import finished, but the photos are not visible in this list yet. Refresh later.';

  @override
  String get photosImportStillProcessing =>
      'Photo import is still processing. Refresh the page later.';

  @override
  String get photosImportBackendFailed =>
      'Photo import failed in the background. Check the task center for details.';

  @override
  String get photosSharedPoweredBy => 'Powered by OmniNest';

  @override
  String get photosTabMemories => 'Memories';

  @override
  String get photosClose => 'Close';

  @override
  String get photosDeletePhotoTitle => 'Permanently Delete Photo';

  @override
  String photosDeletePhotoConfirm(Object title) {
    return '\"$title\" and its source file will be permanently deleted. This cannot be undone.';
  }

  @override
  String get photosCancel => 'Cancel';

  @override
  String get photosDelete => 'Delete';

  @override
  String get photosDeletePermanently => 'Delete Permanently';

  @override
  String photosDeletedPhoto(Object title) {
    return 'Permanently deleted \"$title\" and its source file';
  }

  @override
  String get photosDeleteFailed => 'Delete failed, please try again later';

  @override
  String get photosDeleteAlbumTitle => 'Delete Album';

  @override
  String photosDeleteAlbumConfirm(Object name) {
    return 'Are you sure you want to delete album \"$name\"? Photos in the album will not be deleted.';
  }

  @override
  String photosDeletedAlbum(Object name) {
    return 'Deleted album \"$name\"';
  }

  @override
  String get photosNewAlbum => 'New Album';

  @override
  String get photosAlbumName => 'Album Name';

  @override
  String get photosAlbumNameHint => 'e.g. Travel Photos';

  @override
  String get photosAlbumDescription => 'Description (optional)';

  @override
  String get photosAlbumDescriptionHint => 'Briefly describe this album';

  @override
  String photosAlbumCreated(Object name) {
    return 'Album \"$name\" created';
  }

  @override
  String get photosCreateFailed => 'Creation failed, please try again later';

  @override
  String get photosCreate => 'Create';

  @override
  String get photosBackToPortal => 'Back to Portal';

  @override
  String get photosSearchPhotos => 'Search Photos';

  @override
  String get photosSearchHint => 'Search photos...';

  @override
  String get photosClear => 'Clear';

  @override
  String get photosSearch => 'Search';

  @override
  String get photosAll => 'All';

  @override
  String get photosNoFavorites => 'No favorite photos yet';

  @override
  String get photosNoFavoritesHint =>
      'Tap the favorite button in photo details to add favorites.';

  @override
  String get photosRecentPhotos => 'Recent Photos';

  @override
  String get photosNoPhotos => 'No photos yet';

  @override
  String get photosNoPhotosHint =>
      'Photos will appear here automatically after uploading.';

  @override
  String get photosAlbums => 'Albums';

  @override
  String get photosNoAlbums => 'No albums yet';

  @override
  String photosAlbumPhotoCount(Object count) {
    return '$count';
  }

  @override
  String get photosViewAll => 'View All';

  @override
  String photosLoadMore(Object loaded, Object total) {
    return 'Load more ($loaded / $total loaded)';
  }

  @override
  String photosSelectedCount(Object count) {
    return '$count selected';
  }

  @override
  String get photosTag => 'Tag';

  @override
  String get photosMove => 'Move';

  @override
  String get photosExportZip => 'Export ZIP';

  @override
  String get photosUpdateDate => 'Update date taken';

  @override
  String get photosSaveZip => 'Save ZIP';

  @override
  String get photosDownloadStarted => 'Download handed off to the browser';

  @override
  String photosArchiveSaved(Object path) {
    return 'ZIP saved to $path';
  }

  @override
  String get photosArchiveDownloadFailed =>
      'ZIP download failed. Choose the same path to resume.';

  @override
  String get photosDownloadPhoto => 'Download original';

  @override
  String get photosDownloadFailed => 'Download failed, please try again later';

  @override
  String photosDownloadSaved(Object path) {
    return 'Saved to $path';
  }

  @override
  String get photosDownloadSourceUnavailable =>
      'Original file is unavailable for download';

  @override
  String photosSlideshowBadge(int current, int total) {
    return 'Slideshow · $current / $total';
  }

  @override
  String get photosBatchAddTag => 'Batch Add Tags';

  @override
  String get photosTagName => 'Tag Name';

  @override
  String get photosTagNameHint => 'e.g. Travel';

  @override
  String get photosAdd => 'Add';

  @override
  String get photosTaskCreateFailed => 'Task creation failed';

  @override
  String get photosSelectAlbum => 'Select Album';

  @override
  String get photosBatchDelete => 'Batch Delete';

  @override
  String photosBatchDeleteConfirm(Object count) {
    return 'The selected $count photos and their source files will be permanently deleted. This cannot be undone.';
  }

  @override
  String photosBatchDeleted(Object count) {
    return 'Permanently deleted $count photos and their source files';
  }

  @override
  String get photosDeselect => 'Deselect';

  @override
  String get photosNoTimelineData => 'No timeline data';

  @override
  String get photosNoTimelineHint =>
      'Photos need capture time info to display timeline';

  @override
  String photosYear(Object year) {
    return '$year';
  }

  @override
  String get photosOperationFailed =>
      'Operation failed, please try again later';

  @override
  String get photosImageLoadFailed => 'Image load failed';

  @override
  String get photosBack => 'Back';

  @override
  String get photosUnfavorite => 'Unfavorite';

  @override
  String get photosFavorite => 'Favorite';

  @override
  String get photosHideInfo => 'Hide Info';

  @override
  String get photosShowInfo => 'Show Info';

  @override
  String get photosEdit => 'Edit';

  @override
  String get photosSlideshow => 'Slideshow';

  @override
  String get photosSlideshowUnavailable => 'No consecutive photos to play here';

  @override
  String get photosAddToAlbum => 'Add to Album';

  @override
  String get photosPhotoInfo => 'Photo Info';

  @override
  String get photosBasicInfo => 'Basic Info';

  @override
  String get photosFormat => 'Format';

  @override
  String get photosFileSize => 'File Size';

  @override
  String get photosResolution => 'Resolution';

  @override
  String get photosDateTaken => 'Date Taken';

  @override
  String get photosCameraInfo => 'Camera Info';

  @override
  String get photosBrand => 'Brand';

  @override
  String get photosModel => 'Model';

  @override
  String get photosLens => 'Lens';

  @override
  String get photosAperture => 'Aperture';

  @override
  String get photosShutterSpeed => 'Shutter Speed';

  @override
  String get photosFocalLength => 'Focal Length';

  @override
  String get photosShootingParams => 'Shooting Parameters';

  @override
  String get photosFlash => 'Flash';

  @override
  String get photosWhiteBalance => 'White Balance';

  @override
  String get photosMeteringMode => 'Metering Mode';

  @override
  String get photosLocationInfo => 'Location Info';

  @override
  String get photosPlace => 'Place';

  @override
  String get photosCoordinates => 'Coordinates';

  @override
  String get photosAIRecognition => 'Image Analysis';

  @override
  String get photosAnalysisSubject => 'Subjects';

  @override
  String get photosAnalysisScene => 'Scenes';

  @override
  String get photosAnalysisStyle => 'Styles';

  @override
  String get photosAiCategoryPerson => 'People';

  @override
  String get photosAiCategoryCat => 'Cats';

  @override
  String get photosAiCategoryDog => 'Dogs';

  @override
  String get photosAiCategoryAnimal => 'Animals';

  @override
  String get photosAiCategoryNature => 'Nature';

  @override
  String get photosAiCategoryArchitecture => 'Architecture';

  @override
  String get photosAiCategoryIndoor => 'Indoor';

  @override
  String get photosAiCategoryFood => 'Food';

  @override
  String get photosAiCategoryVehicle => 'Vehicles';

  @override
  String get photosAiCategoryPlant => 'Plants';

  @override
  String get photosAiCategorySport => 'Sports';

  @override
  String get photosAiCategoryNight => 'Night';

  @override
  String get photosAiCategoryArt => 'Art';

  @override
  String get photosAiCategoryDocument => 'Documents and screens';

  @override
  String get photosDescription => 'Description';

  @override
  String get photosDeleteTagFailed => 'Failed to delete tag';

  @override
  String get photosAddTag => 'Add Tag';

  @override
  String get photosTagNameInput => 'Enter tag name';

  @override
  String get photosAddTagFailed => 'Failed to add tag';

  @override
  String get photosNoAlbumsCreateFirst =>
      'No albums yet, please create one first';

  @override
  String get photosAddedToAlbum => 'Added to album';

  @override
  String get photosAddFailed => 'Failed to add, please try again later';

  @override
  String get photosNoChanges => 'No changes made';

  @override
  String get photosEditSaved => 'Edit saved';

  @override
  String get photosSaveFailed => 'Save failed, please try again later';

  @override
  String get photosEditorCancel => 'Cancel';

  @override
  String get photosEditorUndo => 'Undo';

  @override
  String get photosEditorRedo => 'Redo';

  @override
  String get photosEditorDone => 'Done';

  @override
  String get photosEditorRemove => 'Remove';

  @override
  String get photosEditorBack => 'Back';

  @override
  String get photosEditorMore => 'More';

  @override
  String get photosEditorDoneLoadingMsg => 'Changes are being applied';

  @override
  String get photosEditorImportStateHistoryMsg => 'Initialize Editor';

  @override
  String get photosEditorLoadingDialogMsg => 'Please wait...';

  @override
  String get photosEditorCloseWarningTitle => 'Close Image Editor?';

  @override
  String get photosEditorCloseWarningMessage =>
      'Are you sure you want to close the Image Editor? Your changes will not be saved.';

  @override
  String get photosEditorCloseWarningConfirm => 'OK';

  @override
  String get photosEditorPaintBottomNav => 'Paint';

  @override
  String get photosEditorPaintMoveAndZoom => 'Zoom';

  @override
  String get photosEditorPaintFreestyle => 'Freestyle';

  @override
  String get photosEditorPaintArrow => 'Arrow';

  @override
  String get photosEditorPaintLine => 'Line';

  @override
  String get photosEditorPaintRectangle => 'Rectangle';

  @override
  String get photosEditorPaintCircle => 'Circle';

  @override
  String get photosEditorPaintDashLine => 'Dash line';

  @override
  String get photosEditorPaintDashDotLine => 'Dash-dot line';

  @override
  String get photosEditorPaintHexagon => 'Hexagon';

  @override
  String get photosEditorPaintPolygon => 'Polygon';

  @override
  String get photosEditorPaintBlur => 'Blur';

  @override
  String get photosEditorPaintPixelate => 'Pixelate';

  @override
  String get photosEditorLineWidth => 'Line width';

  @override
  String get photosEditorEraser => 'Eraser';

  @override
  String get photosEditorToggleFill => 'Toggle fill';

  @override
  String get photosEditorChangeOpacity => 'Change opacity';

  @override
  String get photosEditorOpacity => 'Opacity';

  @override
  String get photosEditorColor => 'Color';

  @override
  String get photosEditorStrokeWidth => 'Stroke Width';

  @override
  String get photosEditorFill => 'Fill';

  @override
  String get photosEditorTextInputHint => 'Enter text';

  @override
  String get photosEditorTextBottomNav => 'Text';

  @override
  String get photosEditorTextAlign => 'Align text';

  @override
  String get photosEditorFontScale => 'Font scale';

  @override
  String get photosEditorTextBackgroundMode => 'Background mode';

  @override
  String get photosEditorCropBottomNav => 'Crop/ Rotate';

  @override
  String get photosEditorCropRotate => 'Rotate';

  @override
  String get photosEditorCropFlip => 'Flip';

  @override
  String get photosEditorCropTilt => 'Tilt';

  @override
  String get photosEditorCropTiltHorizontal => 'Horizontal';

  @override
  String get photosEditorCropTiltVertical => 'Vertical';

  @override
  String get photosEditorCropRatio => 'Ratio';

  @override
  String get photosEditorCropReset => 'Reset';

  @override
  String get photosEditorRatioFree => 'Free';

  @override
  String get photosEditorRatioOriginal => 'Original';

  @override
  String get photosEditorTuneBottomNav => 'Tune';

  @override
  String get photosEditorTuneBrightness => 'Brightness';

  @override
  String get photosEditorTuneContrast => 'Contrast';

  @override
  String get photosEditorTuneSaturation => 'Saturation';

  @override
  String get photosEditorTuneExposure => 'Exposure';

  @override
  String get photosEditorTuneHue => 'Hue';

  @override
  String get photosEditorTuneTemperature => 'Temperature';

  @override
  String get photosEditorTuneFade => 'Fade';

  @override
  String get photosEditorTuneTint => 'Tint';

  @override
  String get photosEditorFilterBottomNav => 'Filter';

  @override
  String get photosEditorFilterNone => 'No Filter';

  @override
  String get photosEditorBlurBottomNav => 'Blur';

  @override
  String get photosEditorEmojiBottomNav => 'Emoji';

  @override
  String get photosEditorEmojiSearch => 'Search';

  @override
  String get photosEditorEmojiRecent => 'Recent';

  @override
  String get photosEditorEmojiSmileys => 'Smileys & People';

  @override
  String get photosEditorEmojiAnimals => 'Animals & Nature';

  @override
  String get photosEditorEmojiFood => 'Food & Drink';

  @override
  String get photosEditorEmojiActivities => 'Activities';

  @override
  String get photosEditorEmojiTravel => 'Travel & Places';

  @override
  String get photosEditorEmojiObjects => 'Objects';

  @override
  String get photosEditorEmojiSymbols => 'Symbols';

  @override
  String get photosEditorEmojiFlags => 'Flags';

  @override
  String get photosEditorStickerBottomNav => 'Stickers';

  @override
  String get photosEditorLayerEdit => 'Edit';

  @override
  String get photosEditorLayerRotateScale => 'Rotate and Scale';

  @override
  String get photosRolledBack => 'Rolled back to specified version';

  @override
  String get photosRollbackFailed => 'Rollback failed';

  @override
  String photosEditTitle(Object title) {
    return 'Edit - $title';
  }

  @override
  String get photosVersionHistory => 'Version History';

  @override
  String get photosSave => 'Save';

  @override
  String get photosCropDragHint => 'Drag to select crop area';

  @override
  String get photosConfirmCrop => 'Confirm Crop';

  @override
  String get photosEditVersionHistory => 'Edit Version History';

  @override
  String get photosNoEditHistory => 'No edit history';

  @override
  String get photosRollback => 'Rollback';

  @override
  String get photosConfirm => 'Confirm';

  @override
  String photosPhotoCount(Object count) {
    return '$count photos';
  }

  @override
  String photosSharedAlbumAccessError(Object error) {
    return 'Cannot access shared album: $error';
  }

  @override
  String get photosSharedAlbumPasswordRequired =>
      'This album requires password access';

  @override
  String get photosSharedAlbumPasswordHint =>
      'Enter share password to view album content';

  @override
  String get photosEnterPassword => 'Enter password';

  @override
  String get photosAccess => 'Access';

  @override
  String get photosAlbumEmpty => 'No photos in this album';

  @override
  String get photosAddPhotos => 'Add photos';

  @override
  String photosPickerAddCount(Object count) {
    return 'Add $count';
  }

  @override
  String photosPickerAddSuccess(Object count) {
    return 'Added $count photos';
  }

  @override
  String get photosPickerNoCandidates => 'No photos available to add';

  @override
  String get photosSharePhoto => 'Share Photo';

  @override
  String get photosSharedItemPasswordRequired =>
      'This share requires password access';

  @override
  String get photosLiveBadge => 'LIVE';

  @override
  String get photosLiveBadgeTooltip =>
      'Tap to play the motion photo, long-press the photo for a quick preview';

  @override
  String get photosMotionPlayFailed => 'Failed to play motion video';

  @override
  String get photosShareEyebrow => 'SHARE';

  @override
  String get photosShareLinkEyebrow => 'LINK';

  @override
  String get photosShareCopy => 'Copy';

  @override
  String get photosShareCopied => '✓ Copied';

  @override
  String get photosShareToEyebrow => 'SHARE TO';

  @override
  String get photosShareToMessages => 'Messages';

  @override
  String get photosShareToMail => 'Mail';

  @override
  String get photosShareToInstagram => 'Instagram';

  @override
  String get photosShareToMore => 'More';

  @override
  String get photosShareToWeChat => 'WeChat';

  @override
  String get photosShareToQr => 'QR code';

  @override
  String get photosShareWeChatCopiedFallback =>
      'Link copied. Paste it into WeChat to send.';

  @override
  String photosShareQrHint(String url) {
    return 'Open this link on your phone in WeChat:\n$url';
  }

  @override
  String get photosShareOptionLocation => 'Include location';

  @override
  String get photosShareOptionOriginal => 'Original quality';

  @override
  String get photosShareManage => 'Manage existing links';

  @override
  String get photosShareDone => 'Done';

  @override
  String get photosShareOptionsEyebrow => 'OPTIONS';

  @override
  String get photosShareExpiryOption => 'Expiry';

  @override
  String get photosSharePasswordOption => 'Password protection';

  @override
  String get photosSharePasswordNone => 'Not set';

  @override
  String get photosSharePasswordOn => 'Enabled';

  @override
  String get photosShareCreatedHint => 'Link created and copied to clipboard';

  @override
  String get photosShareAlbum => 'Share Album';

  @override
  String get photosSharePassword => 'Access Password (optional)';

  @override
  String get photosSharePasswordHint => 'Leave empty for no password';

  @override
  String get photosShareExpiry => 'Expiry';

  @override
  String get photosShareExpiry1d => '1 day';

  @override
  String get photosShareExpiry7d => '7 days';

  @override
  String get photosShareExpiry30d => '30 days';

  @override
  String get photosShareExpiryNever => 'Never';

  @override
  String get photosExistingShareLinks => 'Existing Share Links';

  @override
  String photosShareAccessCount(Object count) {
    return 'Accessed $count times';
  }

  @override
  String get photosCreateLink => 'Create Link';

  @override
  String photosShareLinkCreated(Object token) {
    return 'Share link created: $token';
  }

  @override
  String get photosShareLinkFailed => 'Failed to create share link';

  @override
  String get photosRemoveFromAlbum => 'Remove from Album';

  @override
  String photosRemoveFromAlbumConfirm(Object title) {
    return 'Are you sure you want to remove \"$title\" from the album? The photo itself will not be deleted.';
  }

  @override
  String get photosRemove => 'Remove';

  @override
  String photosRemovedFromAlbum(Object title) {
    return 'Removed \"$title\" from album';
  }

  @override
  String photosAlbumPhotoCountLabel(Object count) {
    return '$count photos';
  }

  @override
  String get photosDeleteAlbumTooltip => 'Delete Album';

  @override
  String get photosAllPhotos => 'All Photos';

  @override
  String get photosNoGroupData => 'No group data';

  @override
  String get photosBrightness => 'Brightness';

  @override
  String get photosContrast => 'Contrast';

  @override
  String get photosCrop => 'Crop';

  @override
  String get photosRotate => 'Rotate';

  @override
  String get photosFilter => 'Filter';

  @override
  String get photosFilterOriginal => 'Original';

  @override
  String get photosFilterGrayscale => 'Grayscale';

  @override
  String get photosFilterSepia => 'Sepia';

  @override
  String get photosFilterBlur => 'Blur';

  @override
  String get photosFilterSharpen => 'Sharpen';

  @override
  String get musicDeckTitle => 'Music Space';

  @override
  String get musicDeckHome => 'Home';

  @override
  String get musicDeckLibrary => 'Library';

  @override
  String get musicDeckPlaylists => 'Playlists';

  @override
  String get musicDeckFavorites => 'Favorites';

  @override
  String get musicDeckRecent => 'Recently played';

  @override
  String get musicDeckOffline => 'Offline';

  @override
  String get musicDeckLocalManagement => 'Local resources';

  @override
  String get musicDeckMore => 'More';

  @override
  String get musicDeckSources => 'Sources';

  @override
  String get musicDeckSourceLocal => 'Local';

  @override
  String get musicDeckSourceNetease => 'NetEase';

  @override
  String get musicDeckSourceQq => 'QQ Music';

  @override
  String get musicDailyRecommendationSection => 'Recommended today';

  @override
  String get musicDailyRecommendationTitle => 'Daily recommended tracks';

  @override
  String musicDailyRecommendationTrackCount(Object count) {
    return '$count tracks · Updated daily';
  }

  @override
  String get musicLibraryAlbumsEmptyTitle => 'No albums yet';

  @override
  String get musicLibraryAlbumsEmptyMessage =>
      'Albums will appear here after importing local music or connecting an online platform.';

  @override
  String get musicLibraryArtistsEmptyTitle => 'No artists yet';

  @override
  String get musicLibraryArtistsEmptyMessage =>
      'Artists will appear here after importing local music or connecting an online platform.';

  @override
  String get musicDailyRecommendationEmpty =>
      'Today\'s recommendations are unavailable. Try again later.';

  @override
  String get musicDailyRecommendationLoadFailed =>
      'Could not load daily recommendations. Try again.';

  @override
  String get musicDeckAccounts => 'Platform accounts';

  @override
  String get musicDeckManageAccounts => 'Manage platform accounts';

  @override
  String get musicDeckManage => 'Manage';

  @override
  String get musicLocalManagementSubtitle =>
      'Manage local metadata, covers, lyrics, and storage scans.';

  @override
  String get musicStartScan => 'Scan storage';

  @override
  String get musicCreatePlaylist => 'New playlist';

  @override
  String get musicPlaylistName => 'Playlist name';

  @override
  String get musicPlaylistDescription => 'Description';

  @override
  String get musicCreate => 'Create';

  @override
  String get musicEditPlaylist => 'Edit playlist';

  @override
  String get musicDeletePlaylist => 'Delete playlist';

  @override
  String get musicDeleteLocalTrack => 'Delete local track';

  @override
  String get musicDeleteLocalTrackTitle => 'Permanently delete local track?';

  @override
  String musicDeleteLocalTrackMessage(Object title) {
    return '\"$title\" and its source file will be permanently deleted. This cannot be undone.';
  }

  @override
  String get musicDeleteLocalTrackSuccess => 'Local track permanently deleted';

  @override
  String get musicDeleteLocalTrackFailed =>
      'Delete failed. Please try again later.';

  @override
  String get musicDeletePlaylistTitle => 'Delete this playlist?';

  @override
  String musicDeletePlaylistMessage(Object name) {
    return 'Delete \"$name\"? Songs in the playlist will not be deleted.';
  }

  @override
  String get musicPlaylistCoverPick => 'Choose cover';

  @override
  String get musicPlaylistCoverChange => 'Change cover';

  @override
  String get musicPlaylistCoverHint =>
      'Uses the first song cover when no image is selected';

  @override
  String musicPlaylistSaveFailed(Object error) {
    return 'Could not save playlist: $error';
  }

  @override
  String musicPlaylistDeleteFailed(Object error) {
    return 'Could not delete playlist: $error';
  }

  @override
  String get musicDeckConnectedSources => 'Connected sources';

  @override
  String get musicDeckSearchPrompt =>
      'Enter at least two characters to filter by song, artist, or album';

  @override
  String get musicDeckNoSearchResults => 'No matching songs';

  @override
  String get musicDeckSelectTrack => 'Select a song to start listening';

  @override
  String get musicDeckPrevious => 'Previous';

  @override
  String get musicDeckNext => 'Next';

  @override
  String get musicDeckNowPlaying => 'Now playing';

  @override
  String get musicDeckLibraryReady => 'Library ready';

  @override
  String musicDeckLibrarySummary(Object trackCount, Object albumCount) {
    return '$trackCount songs · $albumCount albums';
  }

  @override
  String musicDeckTrackCount(Object count) {
    return '$count songs';
  }

  @override
  String get musicDeckContinueListening => 'Continue listening';

  @override
  String get musicDeckYourCollections => 'Your playlists';

  @override
  String get musicDeckRecentEmpty =>
      'Recently played content will appear here after you play a song.';

  @override
  String get musicDeckPartialSourceFailure =>
      'Some online sources are temporarily unavailable. Local music and other sources remain usable.';

  @override
  String get musicDeckLibrarySubtitle =>
      'Browse local music and known songs from your connected accounts.';

  @override
  String get musicDeckPlaylistsSubtitle =>
      'Local and connected-platform playlists share one organized space.';

  @override
  String get musicDeckFavoritesSubtitle =>
      'Local favorites and liked songs from connected platforms.';

  @override
  String get musicDeckRecentSubtitle =>
      'Continue with recently accessed local content.';

  @override
  String get musicDeckLocalPlaylist => 'Local playlist';

  @override
  String get musicDeckOfflineSubtitle =>
      'Manage content downloaded to this device for offline playback.';

  @override
  String get musicDeckOfflineEmpty =>
      'No music is available offline yet. Downloads will appear after download management is connected.';

  @override
  String get musicDeckRetry => 'Retry';

  @override
  String get musicNavSongs => 'Songs';

  @override
  String get musicNavAlbums => 'Albums';

  @override
  String get musicNavArtists => 'Artists';

  @override
  String get musicNavPlaylists => 'Playlists';

  @override
  String get musicNavFavorites => 'Favorites';

  @override
  String get musicSearch => 'Search';

  @override
  String get musicSearchTitle => 'Search Music';

  @override
  String get musicSearchHint => 'Enter song name, artist or album';

  @override
  String get musicClose => 'Close';

  @override
  String get musicGotIt => 'Got it';

  @override
  String get musicPlaybackError =>
      'Audio playback failed, the codec may not be supported';

  @override
  String get musicCancel => 'Cancel';

  @override
  String get musicSave => 'Save';

  @override
  String get musicSaving => 'Saving...';

  @override
  String get musicEdit => 'Edit';

  @override
  String get musicApply => 'Apply';

  @override
  String get musicApplying => 'Applying';

  @override
  String get musicNoLyrics => 'No lyrics';

  @override
  String get musicNowPlayingArtwork => 'Artwork';

  @override
  String get musicNowPlayingLyrics => 'Lyrics';

  @override
  String get musicEditMetadata => 'Edit Metadata';

  @override
  String get musicTitleRequired => 'Title cannot be empty';

  @override
  String get musicMetadataSaved => 'Metadata saved';

  @override
  String musicSaveFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get musicFieldTitle => 'Title';

  @override
  String get musicFieldArtist => 'Artist';

  @override
  String get musicFieldAlbum => 'Album';

  @override
  String get musicFieldGenre => 'Genre';

  @override
  String get musicCoverImage => 'Cover Image';

  @override
  String musicCoverSelected(Object name) {
    return 'Selected: $name';
  }

  @override
  String get musicCoverPick => 'Select Cover Image';

  @override
  String get musicLyricsFile => 'Lyrics File';

  @override
  String get musicLyricsPick => 'Select Lyrics File (LRC / TXT / SRT / VTT)';

  @override
  String musicAddToPlaylistSuccess(Object name) {
    return 'Added to \"$name\"';
  }

  @override
  String get musicAddToPlaylistFailed => 'Failed to add to playlist';

  @override
  String get musicScrapeMatch => 'Match Online';

  @override
  String get musicScrapeCandidatesTitle => 'Match Results';

  @override
  String get musicScrapeNoCandidates => 'No matching candidates found';

  @override
  String get musicScrapeApply => 'Apply';

  @override
  String get musicScrapeApplied => 'Matched metadata applied';

  @override
  String get musicScrapeLibrary => 'Rescrape Library';

  @override
  String get musicScrapeLibraryConfirmTitle => 'Rescrape entire library?';

  @override
  String get musicScrapeLibraryConfirmMessage =>
      'Every local track will be re-matched online, including already scraped ones. Continue?';

  @override
  String get musicQualityHint =>
      'Playback falls back automatically to tiers your connected platforms support';

  @override
  String get musicQualityUnsupported => 'Not supported by connected platforms';

  @override
  String get musicQualityTitle => 'Playback Quality';

  @override
  String get musicQualityJymaster => 'Master';

  @override
  String get musicQualityJyeffect => 'HD Surround';

  @override
  String get musicQualitySky => 'Immersive Surround';

  @override
  String get musicQualityDolby => 'Dolby Atmos';

  @override
  String get musicQualityHires => 'Hi-Res';

  @override
  String get musicQualityLossless => 'Lossless';

  @override
  String get musicQualityExhigh => 'Very High';

  @override
  String get musicQualityHigher => 'High';

  @override
  String get musicQualityStandard => 'Standard';

  @override
  String get musicPlatformLoginTitle => 'Platform Accounts';

  @override
  String get musicPlatformNeteaseName => 'Netease Cloud Music';

  @override
  String get musicPlatformNeteaseQrHint =>
      'Scan the QR code with the Netease Cloud Music app to log in';

  @override
  String get musicPlatformQrGenerating => 'Generating QR code...';

  @override
  String get musicPlatformQrAction => 'Scan QR Login';

  @override
  String get musicPlatformQqName => 'QQ Music';

  @override
  String get musicPlatformQqCookieRequired =>
      'Please paste your QQ Music cookie';

  @override
  String musicPlatformQqVerifyFailed(Object error) {
    return 'Verification failed: $error';
  }

  @override
  String get musicPlatformQqCookieHint =>
      'Log in at y.qq.com in your browser, then copy the full cookie and paste it below.';

  @override
  String get musicPlatformQqCookieKeyHint =>
      'Must include qm_keyst or qqmusic_key for playback.';

  @override
  String get musicPlatformQqCookiePlaceholder => 'Paste cookie here...';

  @override
  String get musicPlatformQqVerifying => 'Verifying...';

  @override
  String get musicPlatformQqVerifyAction => 'Verify & Save';

  @override
  String get musicPlatformAnonymousUser => 'User';

  @override
  String get musicPlatformVipBadge => 'VIP';

  @override
  String musicPlatformUserId(Object userId) {
    return 'ID: $userId';
  }

  @override
  String get musicPlatformLogout => 'Logout';

  @override
  String get musicHistoryTitle => 'Play History';

  @override
  String get musicHistoryEmpty => 'No plays in the last 7 days';

  @override
  String get musicHistoryLoadMore => 'Load More';

  @override
  String get musicHistoryToday => 'Today';

  @override
  String get musicHistoryYesterday => 'Yesterday';

  @override
  String get musicHistoryViewAll => 'View All';

  @override
  String get musicLyricsSearch => 'Search Lyrics';

  @override
  String get musicLyricsApply => 'Apply Lyrics';

  @override
  String get musicLyricsNoResult => 'No matching lyrics found';

  @override
  String get musicLyricsOnlineSource => 'Online lyrics';

  @override
  String musicLyricsApplied(Object title) {
    return 'Lyrics applied to \"$title\"';
  }

  @override
  String get musicScanConfirmMessage =>
      'Audio files in your music directories will be scanned into the library; existing files are skipped or updated.';

  @override
  String get musicScanPollTimeout =>
      'The job is still running in the background; progress display has stopped. Refresh later to check.';

  @override
  String musicSelectionCount(Object count) {
    return '$count selected';
  }

  @override
  String get musicSelectionSelectAll => 'Select All';

  @override
  String get musicSelectionExit => 'Exit selection';

  @override
  String musicBatchAddedToPlaylist(Object count, Object name) {
    return 'Added $count tracks to \"$name\"';
  }

  @override
  String musicBatchPartial(Object success, Object failed) {
    return '$success succeeded, $failed failed';
  }

  @override
  String musicBatchEnqueued(Object count) {
    return 'Added $count tracks to the play queue';
  }

  @override
  String get musicPlaybackSettings => 'Playback Settings';

  @override
  String get musicSleepTimer => 'Sleep Timer';

  @override
  String musicSleepMinutes(Object minutes) {
    return '$minutes min';
  }

  @override
  String get musicSleepAfterCurrentTrack => 'After current track';

  @override
  String get musicSleepOff => 'Turn off timer';

  @override
  String musicSleepRemaining(Object minutes, Object seconds) {
    return 'Pausing in $minutes:$seconds';
  }

  @override
  String get musicPlaybackSpeed => 'Playback Speed';

  @override
  String get musicSpeedApplyHint =>
      'Changes apply to the current track immediately';

  @override
  String get musicNavGenres => 'Genres';

  @override
  String get musicGenresEmpty =>
      'No genre info on local tracks yet; add it in metadata editing';

  @override
  String get musicGenresPickHint => 'Pick a genre to browse its tracks';

  @override
  String get taskNotifyTitleCompleted => 'Task Completed';

  @override
  String get taskNotifyTitleFailed => 'Task Failed';

  @override
  String get profileTaskSystemNotifications => 'System Notifications';

  @override
  String get profileTaskSystemNotificationsHint =>
      'Send a system notification when tasks complete or fail';

  @override
  String get batteryOptimizationTitle => 'Allow background running';

  @override
  String get batteryOptimizationHint =>
      'Exclude the app from battery optimization so background backups are not blocked';

  @override
  String get batteryOptimizationGranted => 'Background running allowed';

  @override
  String get batteryOptimizationAllow => 'Allow';

  @override
  String get settingsCheckUpdate => 'Check for Updates';

  @override
  String settingsCheckUpdateFailed(Object error) {
    return 'Check for updates failed: $error';
  }

  @override
  String get settingsAlreadyLatest => 'You are on the latest version';

  @override
  String settingsNewVersionFound(Object version) {
    return 'New version $version available';
  }

  @override
  String get settingsOpenDownloadPage => 'Open download page';

  @override
  String get musicQueueTitle => 'Play Queue';

  @override
  String get musicQueueEmpty => 'Play queue is empty';

  @override
  String get musicQueueClear => 'Clear Queue';

  @override
  String get musicPlayNext => 'Play Next';

  @override
  String get musicQueueReorderHint => 'Drag to reorder the queue';

  @override
  String get musicPlayNextAdded => 'Added to play queue';

  @override
  String get musicShuffle => 'Shuffle';

  @override
  String get musicRepeatOff => 'Sequential';

  @override
  String get musicRepeatAll => 'Loop All';

  @override
  String get musicRepeatOne => 'Loop Single';

  @override
  String get musicPlaylistsSubtitle => 'Manage your local playlists.';

  @override
  String get musicPlaylistsEmptyHint => 'Create playlists to manage them here.';

  @override
  String get musicOpenPlaylist => 'Open Playlist';

  @override
  String get musicPlaylistEmptyHint =>
      'Add songs from the song list to see them here.';

  @override
  String get musicAlbumNoTracks => 'No tracks in this album.';

  @override
  String get musicArtistNoTracks => 'No tracks for this artist.';

  @override
  String get musicRemoveFromPlaylist => 'Remove from Playlist';

  @override
  String musicViewAll(Object count) {
    return 'View All ($count)';
  }

  @override
  String get musicPause => 'Pause';

  @override
  String get musicPlay => 'Play';

  @override
  String get musicNotPlaying => 'Not playing';

  @override
  String get musicRecommendedArtist => 'Recommended Artist';

  @override
  String get musicExploreMusic => 'Explore Music';

  @override
  String get musicPlayNow => 'Play Now';

  @override
  String get musicTrendingArtists => 'Trending Artists';

  @override
  String get musicViewAllSimple => 'View All';

  @override
  String get musicNoTracks => 'No tracks yet';

  @override
  String get musicTracksHint => 'Tracks will appear here after music scanning.';

  @override
  String get musicAddToPlaylist => 'Add to Playlist';

  @override
  String get musicUnfavorite => 'Unfavorite';

  @override
  String get musicFavorite => 'Favorite';

  @override
  String get musicNoAlbums => 'No albums yet';

  @override
  String get musicAlbumsHint =>
      'Albums are automatically aggregated after music scanning.';

  @override
  String get musicAlbumsSubtitle => 'Browse your local music library by album.';

  @override
  String get musicArtistsSubtitle => 'Aggregate songs and albums by artist.';

  @override
  String get musicNoArtists => 'No artists yet';

  @override
  String get musicArtistsHint => 'Artists will appear after song tag parsing.';

  @override
  String musicSidebarViewAll(Object count) {
    return 'View All ($count)';
  }

  @override
  String get musicScanSubtitle =>
      'Scan audio files in the file library, parse tags, albums, artists and covers.';

  @override
  String get musicNoScanTask => 'No new scan tasks.';

  @override
  String musicScanStatus(
    Object id,
    Object status,
    Object progress,
    Object files,
  ) {
    return 'Task $id · $status · $progress% · $files files scanned';
  }

  @override
  String get musicMetadataSubtitle =>
      'Review song titles, artists, albums and quality tags.';

  @override
  String get musicNoMetadataHint =>
      'After music scanning, you can complete MusicBrainz metadata here.';

  @override
  String get musicCandidate => 'Candidate';

  @override
  String get musicBrainzCandidates => 'MusicBrainz Candidates';

  @override
  String get musicCandidateFetchFailed => 'Failed to fetch candidates';

  @override
  String get musicNoCandidates => 'No candidates found';

  @override
  String get musicNoCandidatesHint =>
      'Try improving the local title, artist or album, then retry.';

  @override
  String get backupSkipNonWifi => 'Not on WiFi, skipping backup';

  @override
  String get backupSkipNoPermission => 'Photo library access not granted';

  @override
  String get backupSkipNoAlbums => 'No albums';

  @override
  String get backupSkipNoPhotos => 'No photos';

  @override
  String get backupNotificationChannel => 'Photo Backup';

  @override
  String get backupNotificationChannelDesc => 'Photo auto-backup progress';

  @override
  String get backupNotificationTitle => 'Photo Backup In Progress';

  @override
  String backupNotificationProgress(
    Object current,
    Object total,
    Object uploaded,
  ) {
    return 'Processed $current/$total, $uploaded uploaded';
  }

  @override
  String get backupNotificationComplete => 'Photo Backup Complete';

  @override
  String backupNotificationSummary(
    Object uploaded,
    Object skipped,
    Object failed,
  ) {
    return '$uploaded uploaded, $skipped skipped, $failed failed';
  }

  @override
  String get photoRegenerateThumbnails => 'Regenerate Thumbnails';

  @override
  String get photoRegenerateQueued =>
      'Thumbnail rebuild queued. Track progress in the task center.';

  @override
  String get photosActionFailed => 'Action failed. Try again later.';

  @override
  String get photoImportCandidates => 'Import Candidates';

  @override
  String get photoNoImportCandidates => 'No pending photos to import';

  @override
  String get importFiles => 'Import Files';

  @override
  String get importToPersonalSpace => 'Personal Space';

  @override
  String get importToSharedSpace => 'Shared Space';

  @override
  String get importSpaceSelectorTitle => 'Choose Import Destination';

  @override
  String get importSpaceSelectorDesc => 'Select where to import files';

  @override
  String get importPersonalSpaceDesc => 'Only you can see these files';

  @override
  String get importSharedSpaceDesc => 'All users can see these files';

  @override
  String get importUploading => 'Importing...';

  @override
  String importComplete(Object count) {
    return '$count files imported successfully';
  }

  @override
  String get importFailed => 'Import failed';

  @override
  String get importRefreshFailed =>
      'Import completed, but the list could not be refreshed.';

  @override
  String importProcessing(Object count) {
    return '$count files uploaded; processing is still in progress.';
  }

  @override
  String importUnsupportedFormat(Object files, Object extensions) {
    return 'Unsupported file format: $files. Supported formats: $extensions.';
  }

  @override
  String get readerPortal => 'Portal';

  @override
  String get readerCenter => 'Reader Center';

  @override
  String get readerSortRecent => 'Recent';

  @override
  String get readerSortTitle => 'Title';

  @override
  String get readerTypeNovel => 'Novel';

  @override
  String get readerTypeLiterature => 'Literature';

  @override
  String get readerTypeAcademic => 'Academic';

  @override
  String get readerTypeTechnical => 'Technical';

  @override
  String get readerTypePoetry => 'Poetry';

  @override
  String get readerTypeEssay => 'Essay';

  @override
  String get readerTypeComic => 'Comic';

  @override
  String get readerNotStarted => 'Not started';

  @override
  String get readerUnknownTime => 'Unknown time';

  @override
  String readerChapterNumber(Object number) {
    return 'Chapter $number';
  }

  @override
  String readerProgressLabel(Object progress) {
    return 'Progress $progress';
  }

  @override
  String get readerRestoreProgress => 'Restore Reading Progress';

  @override
  String get readerRestoreProgressConfirm =>
      'Restore to this version\'s reading progress? Current progress will be overwritten.';

  @override
  String get readerConfirmRestore => 'Restore';

  @override
  String get readerProgressRestored => 'Reading progress restored';

  @override
  String readerRestoreFailed(Object error) {
    return 'Restore failed: $error';
  }

  @override
  String get readerVersionHistory => 'Version History';

  @override
  String get readerNoVersionHistory => 'No version history';

  @override
  String get readerVersionHistoryHint =>
      'Versions are automatically recorded when reading progress changes';

  @override
  String get readerRestoreThisVersion => 'Restore this version';

  @override
  String get readerFeatureComingSoon => 'This feature is coming soon';

  @override
  String get videoImportSubtitle => 'Import subtitle file';

  @override
  String get videoImportedSubtitle => 'Imported subtitle';

  @override
  String get videoLocalSubtitle => 'Local subtitle';

  @override
  String get videoSubtitleImportSuccess => 'Subtitle loaded';

  @override
  String get videoSubtitleImportFailed => 'Unable to read the subtitle file';

  @override
  String get videoSubtitleFileTooLarge =>
      'Subtitle files must be 2 MB or smaller';

  @override
  String get videoSubtitleNoCues =>
      'No supported timed captions were found in this file';

  @override
  String videoAudioTrackNumber(int index) {
    return 'Audio track $index';
  }

  @override
  String videoLanguageTrackNumber(int index) {
    return 'Language $index';
  }

  @override
  String videoSubtitleTrackNumber(int index) {
    return 'Subtitle track $index';
  }

  @override
  String get videoMute => 'Mute';

  @override
  String get videoUnmute => 'Unmute';

  @override
  String get videoPause => 'Pause';

  @override
  String get videoEnterFullscreen => 'Enter fullscreen';

  @override
  String get videoExitFullscreen => 'Exit fullscreen';

  @override
  String videoSeekBackwardSeconds(int seconds) {
    return 'Back ${seconds}s';
  }

  @override
  String videoSeekForwardSeconds(int seconds) {
    return 'Forward ${seconds}s';
  }

  @override
  String get videoNoAudioTracks => 'No audio tracks available';

  @override
  String get videoSelectAudioTrack => 'Select audio track';

  @override
  String get videoNoLanguages => 'No languages available';

  @override
  String get videoSelectLanguage => 'Select language';

  @override
  String videoVolumeValue(int volume) {
    return 'Volume $volume%';
  }

  @override
  String videoVolumeMutedValue(int volume) {
    return 'Volume $volume% (muted)';
  }

  @override
  String videoSeasonEpisodeLabel(int season, int episode) {
    return 'Season $season · Episode $episode';
  }

  @override
  String get videoHeroFeatured => 'Featured';

  @override
  String get videoHeroMovie => 'Movie';

  @override
  String get videoHeroTv => 'TV';

  @override
  String get videoHeroWatchNow => 'Play now';

  @override
  String get videoHeroFallbackOverview => 'This local title is ready to play.';

  @override
  String get videoHeroCenterTitle => 'Media Library';

  @override
  String get videoHeroCenterSubtitle =>
      'Select a title to view its details and start playback.';

  @override
  String get filePurgeDeleteTitle => 'Permanently delete?';

  @override
  String filePurgeDeleteMessage(String name) {
    return 'Delete $name and its stored file? This action cannot be undone.';
  }

  @override
  String get filePurgeImpactTitle => 'This file is still in use';

  @override
  String filePurgeImpactMessage(int fileCount, int referenceCount) {
    return 'This operation affects $fileCount file nodes and $referenceCount references in other modules. Continue with cascade deletion?';
  }

  @override
  String get filePurgeCascadeDelete => 'Delete all references';

  @override
  String get videoLocalLibrarySources => 'Local direct media libraries';

  @override
  String get videoLocalLibrarySourcesSubtitle =>
      'Reference read-only deployment mounts directly; original movies are not copied to MinIO.';

  @override
  String get videoLibrarySourcesTitle => 'Media sources';

  @override
  String videoLibrarySourceCount(int count) {
    return '$count sources';
  }

  @override
  String get videoLibraryLoading => 'Loading media library';

  @override
  String get videoRefreshSources => 'Refresh media library sources';

  @override
  String get videoAddLibrarySource => 'Add source';

  @override
  String get videoEditLibrarySource => 'Edit source';

  @override
  String get videoStorageLocationUnavailable =>
      'Storage locations could not be loaded';

  @override
  String get videoNoStorageLocation => 'No local storage location is available';

  @override
  String get videoNoStorageLocationHint =>
      'Ask a system administrator to configure and enable a read-only local mount in Storage Management.';

  @override
  String get videoLoadSourcesFailed => 'Library sources could not be loaded';

  @override
  String get videoNoLibrarySources =>
      'No local media library source has been configured.';

  @override
  String get videoLibraryType => 'Library type';

  @override
  String get videoLibraryTypeHint =>
      'The type selects the scanner and hierarchy; existing sources cannot change it directly.';

  @override
  String get videoLibraryTypeMovie => 'Movie';

  @override
  String get videoLibraryTypeTvSeries => 'TV Series';

  @override
  String get videoLibraryTypeAnime => 'Anime';

  @override
  String get videoLibraryTypeRoot => 'Mixed root';

  @override
  String get videoStorageAvailable => 'Available';

  @override
  String get videoStorageUnavailable => 'Unavailable';

  @override
  String get videoStorageDisabled => 'Disabled';

  @override
  String get videoDeleteLibrarySource => 'Delete media source';

  @override
  String videoDeleteLibrarySourceConfirm(String name) {
    return 'Delete source “$name”? Imported media is not deleted; deletion is rejected while media references remain.';
  }

  @override
  String get videoDeleteLibrarySourceDone => 'Media source deleted';

  @override
  String get videoUnknownStorageLocation => 'Unknown storage location';

  @override
  String videoSourceScanSummary(int count, int created) {
    return 'Last discovery found $count videos with $created awaiting review';
  }

  @override
  String videoSourceMissingCount(int count) {
    return '$count unavailable';
  }

  @override
  String get videoSourceDisabled => 'Disabled';

  @override
  String get videoScanThisSource => 'Discover updates';

  @override
  String get videoReviewLibrarySource =>
      'Review discoveries and add selected media';

  @override
  String get videoBrowseRelativeDirectory => 'Browse safe directories';

  @override
  String get videoChooseThisDirectory => 'Choose this directory';

  @override
  String get videoDirectoryRoot => 'Root directory';

  @override
  String get videoSourceFromMount => 'Direct from trusted mount';

  @override
  String get videoTrustedMountLabel => 'Trusted mount';

  @override
  String get videoNoTrustedMount => 'No trusted mount available';

  @override
  String get videoNoTrustedMountHint =>
      'Register a mount in deployment config first and make sure it is available. The mount root is registered as a storage location automatically on creation.';

  @override
  String get videoBrowseMountDirectory => 'Browse mount directories';

  @override
  String get videoDiscoveryTitle => 'Discovery and import';

  @override
  String get videoReviewSelectionHint =>
      'Select a series, season, or episode. Only confirmed selections are added to the library.';

  @override
  String get videoLocalDiscoveryTask => 'Local media discovery';

  @override
  String get videoLocalImportTask => 'Selected media import';

  @override
  String get videoAwaitingReview => 'Awaiting review';

  @override
  String get videoDiscoveryEmpty =>
      'No discovery result yet. Discovering creates candidates without immediately adding them.';

  @override
  String get videoDiscoveryRunning =>
      'Discovering media files. Leaving this screen does not stop the background task.';

  @override
  String get videoDiscoveryFailed =>
      'Discovery failed. Check source health and try again.';

  @override
  String get videoDiscoveryCancelled =>
      'The discovery or import task was cancelled.';

  @override
  String videoDiscoveryCandidates(int count) {
    return '$count candidates';
  }

  @override
  String videoDiscoverySelected(int count) {
    return '$count selected';
  }

  @override
  String videoDiscoveryIssues(int count) {
    return '$count issues';
  }

  @override
  String get videoSelectAllCandidates => 'Select all';

  @override
  String get videoClearCandidateSelection => 'Clear selection';

  @override
  String get videoAddSelectedToLibrary => 'Add to media library';

  @override
  String get videoPauseImport => 'Pause import';

  @override
  String get videoCancelDiscovery => 'Cancel task';

  @override
  String get videoBackToParentNode => 'Back to parent';

  @override
  String get videoLoadTreeFailed => 'Candidate tree could not be loaded';

  @override
  String get videoNoCandidates => 'There are no candidates at this level.';

  @override
  String get videoCandidateExisting => 'Already in library';

  @override
  String get videoCandidateChanged => 'File changed';

  @override
  String get videoCandidateUnmatched => 'Unrecognized';

  @override
  String get videoCandidateNew => 'New candidate';

  @override
  String get videoUnavailableTitle => 'Unavailable items';

  @override
  String get videoLibraryRecordsExpand => 'Show more records';

  @override
  String get videoLibraryRecordsCollapse => 'Show fewer records';

  @override
  String get photosPrevPhoto => 'Previous photo';

  @override
  String get photosNextPhoto => 'Next photo';

  @override
  String get videoUnavailableEmpty =>
      'No local media is currently missing or unreadable.';

  @override
  String videoUnavailableCount(int count) {
    return '$count items need attention';
  }

  @override
  String get videoUnavailableLoadFailed =>
      'Unavailable items could not be loaded';

  @override
  String get videoMissingPending => 'Awaiting missing confirmation';

  @override
  String get videoMissingConfirmed => 'File missing';

  @override
  String get videoFileUnavailable => 'File unavailable';

  @override
  String get videoSourceOffline => 'Source offline';

  @override
  String get videoSourceDegraded => 'Partially unavailable';

  @override
  String get videoSourceName => 'Source name';

  @override
  String get videoStorageLocation => 'Storage location';

  @override
  String get videoSelectLibrarySource => 'Select library source';

  @override
  String get videoNoAvailableStorageLocation => 'No storage location available';

  @override
  String get videoNoAvailableStorageLocationHint =>
      'Add a local storage location and ensure it is enabled before creating a library source.';

  @override
  String get videoRelativeDirectory => 'Relative directory';

  @override
  String get videoRelativeDirectoryHint =>
      'Enter a path within the storage location, for example Movies/4K';

  @override
  String get videoSourceEnabled => 'Enable this source';

  @override
  String get videoSourceRequiredFields =>
      'Enter a source name and relative directory';

  @override
  String get videoNeverScanned => 'Never scanned';

  @override
  String get adminAddLocalStorageLocation => 'Add mount location';

  @override
  String get adminLocalStorageLocations => 'Local storage locations';

  @override
  String get adminReadOnlyMediaMounts => 'Read-only media mounts';

  @override
  String get adminLocalStorageLocationsSubtitle =>
      'Only deployment allowlisted mount keys and relative directories are stored; host absolute paths are not persisted.';

  @override
  String get adminNoLocalStorageLocations =>
      'No read-only local storage location has been configured.';

  @override
  String get adminDeleteLocalStorageLocation => 'Delete storage location';

  @override
  String get adminMountKey => 'Mount key';

  @override
  String get adminMountKeyHint =>
      'Must match a key under file.local-media.mounts in application.yml';

  @override
  String get adminRelativeRoot => 'Relative root';

  @override
  String get adminRelativeRootHint =>
      'Enter a directory inside the mount; use . for the mount root';

  @override
  String get adminLocalStorageSecurityHint =>
      'Absolute paths are supplied by deployment configuration; this screen can only select a relative directory in an approved mount.';

  @override
  String get adminLocalStorageRequiredFields =>
      'Enter a name, mount key, and relative root';

  @override
  String get adminCancel => 'Cancel';

  @override
  String get photosTaskNotFound => 'This task is no longer available.';

  @override
  String get photosTaskMonitorTimedOut =>
      'Status monitoring timed out. The background task may still be running.';

  @override
  String get photosRetryStatus => 'Retry status';

  @override
  String get musicQrLoginTitle => 'Netease Cloud Music login';

  @override
  String get musicQrLoginInstruction =>
      'Open the Netease Cloud Music app and scan this QR code.';

  @override
  String get musicQrWaiting => 'Waiting for scan…';

  @override
  String get musicQrScanned => 'Scanned — confirm on your phone';

  @override
  String get musicQrExpired =>
      'The QR code expired. Start login again to get a new code.';

  @override
  String get musicQrStatusFailed =>
      'Unable to refresh login status. Check the connection and retry.';

  @override
  String get musicQrRetry => 'Retry';

  @override
  String musicQrUnknownStatus(String status) {
    return 'Status: $status';
  }

  @override
  String get videoLibraryOverviewTab => 'Overview';

  @override
  String get videoLibraryScanReviewTab => 'Scan and review';

  @override
  String get videoLibraryAccessTab => 'Access';

  @override
  String get videoLibraryVisibilityPrivate => 'Private';

  @override
  String get videoLibraryVisibilityPrivateHint =>
      'Only the creator sees this library in media views. Administrators can still manage it here.';

  @override
  String get videoLibraryVisibilitySelected => 'Selected users';

  @override
  String get videoLibraryVisibilitySelectedHint =>
      'Only the users selected below can browse and play this library.';

  @override
  String get videoLibraryVisibilityMembers => 'All members';

  @override
  String get videoLibraryVisibilityMembersHint =>
      'Members and administrators with media read access are included. Guests are not included automatically.';

  @override
  String get videoLibraryAccessSearch => 'Search username or display name';

  @override
  String get videoLibraryAccessNoUsers => 'No matching users';

  @override
  String videoLibraryAccessSelectedCount(int count) {
    return '$count users selected';
  }

  @override
  String get videoLibraryAccessSave => 'Save access';

  @override
  String get videoLibraryAccessSaved => 'Access settings saved';

  @override
  String get videoLibraryAccessLoadFailed => 'Unable to load access settings';

  @override
  String get videoLibraryAccessUsersFailed => 'Unable to load users';

  @override
  String get videoLibrarySourceVisibilityLabel => 'Visibility';

  @override
  String get videoLibrarySourceLocationLabel => 'Storage location';

  @override
  String get videoLibrarySourcePathLabel => 'Relative folder';

  @override
  String get videoLibrarySourceTypeLabel => 'Media type';

  @override
  String get adminTrustedMountUnavailable =>
      'No configured mount is available. Check application.yml or the environment variables, then restart the backend.';

  @override
  String get adminChooseRelativeFolder => 'Choose relative folder';

  @override
  String get adminUseCurrentFolder => 'Use current folder';

  @override
  String get adminOpenFolder => 'Open folder';

  @override
  String get adminNoSubfolders => 'This folder has no browsable subfolders';

  @override
  String readerComicCatalogItems(int count) {
    return '$count items';
  }

  @override
  String get readerComicExpandAll => 'Expand all';

  @override
  String get readerComicCollapseAll => 'Collapse all';

  @override
  String get photosViewSwitch => 'Switch view';

  @override
  String get photosViewGridDay => 'Grid · By day';

  @override
  String get photosViewGridMonth => 'Grid · By month';

  @override
  String get photosViewTimeline => 'Timeline';

  @override
  String get photosViewGroups => 'Groups';

  @override
  String get photosToggleSelection => 'Toggle selection';

  @override
  String photosTrashSubtitle(Object count) {
    return '$count items · automatically deleted after 30 days';
  }

  @override
  String get photosEmptyTrash => 'Empty Trash';

  @override
  String get photosRestore => 'Restore';

  @override
  String get photosDeleteForever => 'Delete Forever';

  @override
  String get photosEmptyTrashConfirmTitle => 'Empty Trash?';

  @override
  String photosEmptyTrashConfirmBody(Object count) {
    return 'All $count photos in the trash will be permanently deleted. This cannot be undone.';
  }

  @override
  String get photosDeleteForeverConfirmTitle => 'Delete Forever?';

  @override
  String get photosDeleteForeverConfirmBody =>
      'This photo will be permanently deleted. This cannot be undone.';

  @override
  String get photosMoveToTrashTitle => 'Move to Trash?';

  @override
  String photosMoveToTrashBody(Object count) {
    return '$count photos will be moved to the Trash. You can restore them within 30 days.';
  }

  @override
  String get photosMoveToTrashBodyOne =>
      'This photo will be moved to the Trash. You can restore it within 30 days.';

  @override
  String get photosMoveToTrashAction => 'Move to Trash';

  @override
  String get photosTrashRestored => 'Photo restored';

  @override
  String get photosTrashPurged => 'Deleted permanently';

  @override
  String get photosTrashMoved => 'Moved to Trash';

  @override
  String get photosBackToPhotos => 'Back to Photos';

  @override
  String get photosPlay => 'Play';

  @override
  String get photosPause => 'Pause';

  @override
  String get photosFullscreen => 'Fullscreen';

  @override
  String get photosStripHide => 'HIDE';

  @override
  String get photosStripShow => 'STRIP';

  @override
  String get photosIso => 'ISO';

  @override
  String get photosTagsSelectHint => 'Select a tag to browse its photos';

  @override
  String photosTagsPhotoCount(int count) {
    return '$count photos';
  }

  @override
  String get photosLocationsBack => 'Back to Locations';

  @override
  String get photosDeleteShort => 'Delete';

  @override
  String get photosSaturation => 'Saturation';

  @override
  String get photosModuleDisplayName => 'Lightbox';

  @override
  String get photosSelectAll => 'Select all';

  @override
  String get photosDeselectAll => 'Deselect all';

  @override
  String get photosFrameNavPhotos => 'Photos';

  @override
  String get photosFrameNavLocations => 'Locations';

  @override
  String get photosFrameNavTags => 'Tags';

  @override
  String get photosFrameNavTrash => 'Trash';

  @override
  String get photosFrameLocationsEmpty => 'No locations yet';

  @override
  String get photosFrameLocationsEmptyHint =>
      'Photos with location details will appear here';

  @override
  String get photosFrameTagsEmpty => 'No tags yet';

  @override
  String get photosFrameTagsEmptyHint => 'Photos you tag will appear here';

  @override
  String get photosFrameTrashEmpty => 'Trash is empty';

  @override
  String get photosFrameTrashEmptyHint =>
      'Deleted photos stay here for 30 days';

  @override
  String photosFrameStatsPhotos(Object count) {
    return '$count photos';
  }

  @override
  String photosFrameStatsMeta(Object albums, Object trash) {
    return '$albums albums · $trash in trash';
  }

  @override
  String get photosInsightsTitle => 'Relationship insights';

  @override
  String get photosAlbumsManage => 'Manage albums';

  @override
  String get photosExpandAlbums => 'Show albums';

  @override
  String get photosScrollToTop => 'Back to top';

  @override
  String photosRelCooccur(Object count) {
    return '$count co-occurring photos';
  }

  @override
  String photosRelOthers(Object count) {
    return '$count more';
  }

  @override
  String photosRelRelated(Object name) {
    return 'Related to \"$name\"';
  }

  @override
  String get photosRelCooccurTitle => 'Related entities';

  @override
  String get photosRelHint =>
      'Tap an entity to inspect relations; View all filters the library by that entity.';

  @override
  String videoRedesignItemsCount(int count) {
    return '$count items';
  }

  @override
  String get videoRedesignStatusMatched => 'Matched';

  @override
  String get videoRedesignStatusPending => 'Pending';

  @override
  String get videoRedesignStatusFailed => 'Failed';

  @override
  String get videoRedesignFilterAll => 'All';

  @override
  String get videoRedesignFilterMatched => 'Matched';

  @override
  String get videoRedesignFilterPending => 'Pending';

  @override
  String get videoRedesignFilterFailed => 'Failed';

  @override
  String get videoRedesignDetail => 'Detail';

  @override
  String get videoRedesignPlayNow => 'Play now';

  @override
  String get videoRedesignNoMatches => 'No matching items';

  @override
  String get videoRedesignAdjustFilters => 'Try adjusting the filters';

  @override
  String get videoRedesignSubMovies => 'Movies';

  @override
  String get videoRedesignSubTvShows => 'TV Series';

  @override
  String get videoRedesignSubAnime => 'Anime';

  @override
  String get videoRedesignSubCollections => 'Collections';

  @override
  String get videoRedesignSubRecent => 'Recently Added';

  @override
  String get videoRedesignSubContinue => 'Continue Watching';

  @override
  String get videoRedesignSubFavorites => 'Favorites';

  @override
  String get videoRedesignSubHistory => 'Watch History';

  @override
  String get videoRedesignSubAdmin => 'Library Management';

  @override
  String videoRedesignSearchHint(Object section) {
    return 'Search $section…';
  }

  @override
  String get videoRedesignNoFavorites => 'No favorites yet';

  @override
  String get videoRedesignNoFavoritesHint =>
      'Tap the favorite button while playing';

  @override
  String get videoRedesignNoHistoryHint =>
      'Your watch records will appear here';

  @override
  String get videoRedesignSubtitlesEn => 'Subtitles';

  @override
  String get videoRedesignUploadSubtitle => 'Upload subtitle';

  @override
  String get videoRedesignNoSubtitles => 'No subtitles';

  @override
  String get videoRedesignSubtitleEmbedded => 'Embedded';

  @override
  String get videoRedesignSubtitleExternal => 'External';

  @override
  String get videoRedesignVersions => 'Versions';

  @override
  String get videoRedesignVersionsEn => 'Versions';

  @override
  String get videoRedesignOriginalVersion => 'Original';

  @override
  String get videoRedesignLanguage => 'Language';

  @override
  String get videoRedesignConfirmUpload => 'Confirm upload';

  @override
  String get videoRedesignStatTotal => 'Total items';

  @override
  String get videoRedesignStatTotalEn => 'Total';

  @override
  String get fontScaleTitle => 'Font size';

  @override
  String get fontScaleFollowSystem => 'Follow system';

  @override
  String get fontScaleCompact => 'Compact';

  @override
  String get fontScaleStandard => 'Standard';

  @override
  String get fontScaleComfortable => 'Comfortable';

  @override
  String get fontScaleLarge => 'Large';

  @override
  String get fontScaleResetDefault => 'Reset to default';

  @override
  String get fontScalePreviewSample => 'Hello, OmniNest';

  @override
  String get videoDetailBack => 'BACK';

  @override
  String get videoDetailEdit => 'EDIT';

  @override
  String get videoDetailSave => 'SAVE';

  @override
  String get videoDetailPlay => 'PLAY';

  @override
  String get videoDetailTabOverview => 'overview';

  @override
  String get videoDetailTabVersions => 'versions';

  @override
  String get videoDetailTabSubtitles => 'subtitles';

  @override
  String get videoDetailCast => 'Cast';

  @override
  String get videoDetailDirector => 'DIR.';

  @override
  String get videoDetailNoVersions => 'No versions available.';

  @override
  String get videoDetailUploadSubtitle => 'UPLOAD SUBTITLE';

  @override
  String videoDetailSeasonCount(int count) {
    return '$count seasons';
  }

  @override
  String get videoDetailEpisodesHeader => 'EPISODES';

  @override
  String get videoMetaFieldOriginalTitle => 'Original title';

  @override
  String get videoMetaFieldYear => 'Year';

  @override
  String get videoMetaFieldRuntimeMinutes => 'Runtime (minutes)';

  @override
  String get videoMetaFieldOverview => 'Overview';

  @override
  String get readerComicManifestLoadFailed =>
      'Failed to load the comic manifest, please retry later';

  @override
  String readerComicParseFailedWithReason(Object reason) {
    return 'Comic parsing failed: $reason';
  }

  @override
  String get readerComicParseFailed =>
      'Comic parsing failed, retry sources on the detail page';

  @override
  String readerComicPartialFailedWithReason(Object reason) {
    return 'Some comic sources failed to parse: $reason';
  }

  @override
  String get readerComicPartialFailed =>
      'Some comic sources failed to parse, handle failed sources on the detail page';

  @override
  String get readerComicEmptyManifest =>
      'Comic content is empty or the manifest has not been generated';

  @override
  String get readerComicEmpty => 'Comic content is empty';

  @override
  String get filesHomeLocations => 'Locations';

  @override
  String get filesHomeSections => 'Sections';

  @override
  String get filesHomePersonalSpaceHint => 'Your private files';

  @override
  String get filesHomeAllFilesHint => 'Browse all files and folders';

  @override
  String get filesHomeRecentHint => 'Recently added or changed';

  @override
  String get filesHomeFavoritesHint => 'Starred files';

  @override
  String get filesHomeTrashHint => 'Deleted items';

  @override
  String get filesHomeMoreHint => 'Upload queue, offline downloads and shares';
}
