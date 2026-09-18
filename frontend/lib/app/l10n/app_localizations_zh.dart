// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'OmniNest';

  @override
  String get mobileNavHome => '首页';

  @override
  String get mobileNavFiles => '文件';

  @override
  String get mobileNavMusic => '音乐';

  @override
  String get mobileNavVisual => '影像';

  @override
  String get mobileNavReader => '阅读';

  @override
  String get mobileActivityCenter => '活动中心';

  @override
  String get mobileOfflineBanner => '当前处于离线状态，部分操作暂不可用';

  @override
  String get fullscreenEnterShortcut => '全屏（F11）';

  @override
  String get fullscreenExitShortcut => '退出全屏（F11）';

  @override
  String get portalImmersiveModeEnter => '沉浸模式';

  @override
  String get portalImmersiveModeExit => '退出沉浸模式';

  @override
  String get searchTitle => '搜索';

  @override
  String get searchHint => '搜索文件、书籍、视频…';

  @override
  String get searchEmptyQuery => '输入关键词开始搜索';

  @override
  String get searchEmptyResult => '未找到匹配结果';

  @override
  String get searchFailed => '搜索失败';

  @override
  String get searchScopeAll => '全部';

  @override
  String get searchGroupFile => '文件';

  @override
  String get searchGroupBook => '书籍';

  @override
  String get searchGroupVideo => '视频';

  @override
  String get searchGroupMusic => '音乐';

  @override
  String get searchGroupPhoto => '照片';

  @override
  String get tasksTitle => '任务';

  @override
  String get tasksEmpty => '暂无任务';

  @override
  String get tasksEmptyHint => '系统任务会显示在这里';

  @override
  String get tasksFilterAll => '全部';

  @override
  String get tasksFilterPending => '等待中';

  @override
  String get tasksFilterRunning => '执行中';

  @override
  String get tasksFilterCompleted => '已完成';

  @override
  String get tasksFilterFailed => '失败';

  @override
  String get tasksRetry => '重试';

  @override
  String get tasksStatusPending => '等待';

  @override
  String get tasksStatusRunning => '执行中';

  @override
  String get tasksStatusCompleted => '完成';

  @override
  String get tasksStatusFailed => '失败';

  @override
  String get tasksRetryCount => '重试';

  @override
  String tasksRetryProgress(Object current, Object maximum) {
    return '重试 $current/$maximum';
  }

  @override
  String get tasksStatusRetryWait => '等待重试';

  @override
  String get tasksStatusNeedsAttention => '需处理';

  @override
  String get tasksStatusCancelled => '已取消';

  @override
  String get tasksPhasePlanning => '规划删除资源';

  @override
  String get tasksPhaseDeletingObjects => '删除对象数据';

  @override
  String get tasksPhaseVerifyingReferences => '校验资源引用';

  @override
  String get tasksPhaseFinalizingDatabase => '清理业务数据';

  @override
  String get tasksPhaseWaiting => '等待任务进度';

  @override
  String get tasksTimeJustNow => '刚刚';

  @override
  String tasksTimeMinutesAgo(Object count) {
    return '$count 分钟前';
  }

  @override
  String tasksTimeHoursAgo(Object count) {
    return '$count 小时前';
  }

  @override
  String tasksTimeDaysAgo(Object count) {
    return '$count 天前';
  }

  @override
  String get settingsTitle => '设置';

  @override
  String settingsLoadFailed(Object error) {
    return '加载失败：$error';
  }

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '浅色模式';

  @override
  String get settingsThemeDark => '深色模式';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageChinese => '中文';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsNotification => '通知';

  @override
  String get settingsNotificationEnable => '启用通知';

  @override
  String get settingsNotificationEnableHint => '接收系统推送通知';

  @override
  String get settingsEmailNotification => '邮件通知';

  @override
  String get settingsEmailNotificationHint => '通过邮件接收重要通知';

  @override
  String get settingsSyncOffline => '同步与离线';

  @override
  String get settingsSyncOfflineHint => '管理在线同步状态和离线内容';

  @override
  String get settingsSecurity => '安全与设备';

  @override
  String get settingsSecurityHint => '管理密码和当前登录会话';

  @override
  String get settingsAbout => '关于 OmniNest';

  @override
  String get settingsAboutHint => '版本 0.1.0';

  @override
  String get setupTitle => '首次安装';

  @override
  String get setupSubtitle => '创建此 OmniNest 实例的超级管理员账户。';

  @override
  String get setupUnavailableTitle => '安装向导尚未就绪';

  @override
  String get setupUnavailableMessage =>
      '请在服务端配置至少 32 个字符的 OMNINEST_SETUP_TOKEN，然后重启后端。';

  @override
  String get setupToken => '安装令牌';

  @override
  String get setupTokenHint => '输入服务端配置的安装令牌';

  @override
  String get setupInstanceName => '实例名称';

  @override
  String get setupInstanceNameRequired => '请输入实例名称';

  @override
  String get setupDefaultLocale => '默认语言';

  @override
  String get setupDefaultTimezone => '默认时区';

  @override
  String get setupDisplayName => '显示名称';

  @override
  String get setupEmail => '邮箱（可选）';

  @override
  String get setupConfirmPassword => '确认密码';

  @override
  String get setupPasswordLength => '超级管理员密码长度必须在 8 到 24 个字符之间';

  @override
  String get setupTwoFactorSection => '两步验证';

  @override
  String get setupTwoFactorHint =>
      '当前部署要求为超级管理员开启两步验证：使用验证器 App 扫码后输入 6 位验证码完成安装。';

  @override
  String get setupTwoFactorGenerate => '生成二维码';

  @override
  String get setupTwoFactorRegenerate => '重新生成秘钥';

  @override
  String get setupTwoFactorGenerateFirst => '请先生成两步验证二维码并输入验证码';

  @override
  String get setupTwoFactorGoLogin => '备份码已保存，前往登录';

  @override
  String get setupPasswordMismatch => '两次输入的密码不一致';

  @override
  String get setupCreateAdmin => '创建超级管理员';

  @override
  String get setupRetryStatus => '重新检查';

  @override
  String get setupStatusFailed => '无法读取安装状态';

  @override
  String get setupCreateFailed => '创建超级管理员失败';

  @override
  String get setupSecureNotice => '安装令牌仅用于本次初始化，不会保存在客户端。';

  @override
  String get setupLanguageSelector => '界面语言';

  @override
  String get setupSectionInstance => '实例信息';

  @override
  String get setupSectionAdmin => '管理员账户';

  @override
  String get setupFeatureFiles => '文件管理 · 多存储位';

  @override
  String get setupFeatureMedia => '影视 · 音乐 · 相册';

  @override
  String get setupFeatureReader => '阅读 · 离线同步';

  @override
  String get adminSearchHint => '搜索…';

  @override
  String get adminNoMatch => '未找到匹配数据。';

  @override
  String get notificationTitle => '通知';

  @override
  String notificationTitleWithCount(Object count) {
    return '通知 ($count)';
  }

  @override
  String get notificationNoTitle => '无标题';

  @override
  String get notificationEmpty => '暂无通知';

  @override
  String get notificationEmptyHint => '新通知会实时推送到这里';

  @override
  String get notificationMarkAllRead => '全部已读';

  @override
  String get notificationDelete => '删除通知';

  @override
  String get notificationClearAll => '清空通知';

  @override
  String get notificationClearConfirmTitle => '清空全部通知？';

  @override
  String get notificationClearConfirmMessage => '此操作会永久删除当前账户的全部通知。';

  @override
  String get notificationDeleteFailed => '删除通知失败，请重试';

  @override
  String get notificationClearFailed => '清空通知失败，请重试';

  @override
  String get notificationTypeCompleted => '完成';

  @override
  String get notificationTypeFailed => '失败';

  @override
  String get notificationTypeShare => '分享';

  @override
  String get notificationTypeTaskCompleted => '任务完成';

  @override
  String get notificationTypeTaskCompletedDesc => '异步任务执行成功';

  @override
  String get notificationTypeTaskFailed => '任务失败';

  @override
  String get notificationTypeTaskFailedDesc => '异步任务执行失败';

  @override
  String get notificationTypeShareAccess => '分享访问';

  @override
  String get notificationTypeShareAccessDesc => '有人访问了你的分享链接';

  @override
  String get notificationTypeSystemMessage => '系统消息';

  @override
  String get notificationTypeSystemMessageDesc => '系统级通知';

  @override
  String get notificationTypeMetadataScrape => '元数据刮削';

  @override
  String get notificationTypeMetadataScrapeDesc => '媒体元数据抓取完成';

  @override
  String get notificationTypeShareVisited => '分享被访问';

  @override
  String get notificationTypeShareVisitedDesc => '你的分享链接被他人访问';

  @override
  String get notificationTypeStorageWarning => '存储预警';

  @override
  String get notificationTypeStorageWarningDesc => '存储空间使用率过高';

  @override
  String get notificationTypeNewDeviceLogin => '新设备登录';

  @override
  String get notificationTypeNewDeviceLoginDesc => '检测到新设备登录';

  @override
  String get notificationTypePasswordChanged => '密码已修改';

  @override
  String get notificationTypePasswordChangedDesc => '账户密码已成功修改';

  @override
  String get notificationTypesHeader => '通知类型';

  @override
  String get notificationTimeNow => '刚刚';

  @override
  String notificationTimeMinutes(Object n) {
    return '$n分钟前';
  }

  @override
  String notificationTimeHours(Object n) {
    return '$n小时前';
  }

  @override
  String notificationTimeDays(Object n) {
    return '$n天前';
  }

  @override
  String get profileTitle => '个人中心';

  @override
  String get profileBackTooltip => '返回 Portal';

  @override
  String get profileAvatarFormatError => '仅支持 JPG、PNG、WebP 格式';

  @override
  String get profileAvatarSizeError => '头像大小不能超过 5MB';

  @override
  String get profileAvatarSuccess => '头像更新成功';

  @override
  String get profileAvatarFailed => '头像上传失败，请重试';

  @override
  String get profileEditAvatar => '更换头像';

  @override
  String get profileUnknownUser => '未知用户';

  @override
  String get profileEmailNotSet => '未设置邮箱';

  @override
  String get profileRole => '角色';

  @override
  String get profileRoleSuperAdmin => '超级管理员';

  @override
  String get profileRoleAdmin => '管理员';

  @override
  String get profileRoleMember => '成员';

  @override
  String get profileUnreadNotifications => '未读通知';

  @override
  String get profileLastLogin => '上次登录';

  @override
  String get profileToday => '今天';

  @override
  String get profileAccountStatus => '账户状态';

  @override
  String get profileStatusNormal => '正常';

  @override
  String get profileAccountInfo => '账户信息';

  @override
  String get profileSectionAccount => '账户';

  @override
  String get profileSectionAppearance => '外观与语言';

  @override
  String get profileSectionNotifications => '通知';

  @override
  String get profileSectionSecurity => '安全与设备';

  @override
  String get profileSectionBackup => '备份';

  @override
  String get profileSectionAbout => '关于';

  @override
  String get photoBackupBackgroundTitle => '自动备份本机相册';

  @override
  String get photoBackupBackgroundSubtitle =>
      '开启后将本机相册的全部照片自动上传到你的 OmniNest 服务器（仅 Android）';

  @override
  String get photoBackupConfirmTitle => '开启自动备份？';

  @override
  String get photoBackupConfirmBody =>
      '将按所选范围自动上传照片到你的 OmniNest 服务器（仅 Android）。';

  @override
  String get photoBackupConfirmBodyScoped =>
      '仅上传下方勾选相册中的照片到你的 OmniNest 服务器（仅 Android）。';

  @override
  String get photoBackupBackgroundSubtitleScoped =>
      '开启后将自动上传所选范围的照片到你的 OmniNest 服务器（仅 Android）';

  @override
  String get photoBackupAllowMobileData => '无 Wi-Fi 时也使用移动数据备份';

  @override
  String get photoBackupAllowMobileDataHint => '勾选后在移动网络下也会消耗流量上传';

  @override
  String photoBackupScopeSelectedCount(int count) {
    return '已选 $count 个相册';
  }

  @override
  String get photoBackupScopeOptionAll => '全部相册';

  @override
  String get photoBackupScopeOptionSelected => '自选相册';

  @override
  String get photoBackupConfirmEnable => '开启';

  @override
  String get photoBackupAlbumPickerTitle => '选择要备份的相册';

  @override
  String get photoBackupAlbumPickerEmpty => '未获取到相册，请检查相册访问权限';

  @override
  String get photoBackupNeedSelectAlbum => '请至少选择一个相册';

  @override
  String get photoBackupScopeSummaryAll => '当前范围：全部相册';

  @override
  String photoBackupScopeSummarySelected(int count) {
    return '当前范围：已选 $count 个相册';
  }

  @override
  String get profileManageBackdrop => '管理背景';

  @override
  String get profileUsername => '用户名';

  @override
  String get profileEmail => '邮箱';

  @override
  String get profileUserId => '用户 ID';

  @override
  String get profileChangePassword => '修改密码';

  @override
  String get profileChangePasswordSubtitle => '更新账户登录密码';

  @override
  String get profileWeatherCity => '天气城市';

  @override
  String get profileWeatherCityHint => '设置天气显示的城市，留空则使用 GPS 定位或系统默认值';

  @override
  String get profileWeatherCityPlaceholder => '输入城市名，如 北京、上海';

  @override
  String get profileWeatherCitySave => '保存';

  @override
  String get profileWeatherCityNotSet => '未设置（使用 GPS / 系统默认）';

  @override
  String profileWeatherCitySaveFailed(Object error) {
    return '保存城市偏好失败：$error';
  }

  @override
  String get profileNotificationSettings => '通知设置';

  @override
  String get profileNotificationMasterSwitch => '通知总开关';

  @override
  String get profileNotificationMasterSwitchHint => '关闭后不再接收任何通知';

  @override
  String get profileNotificationTypesLoadFailed => '加载通知类型失败';

  @override
  String get profileNotificationSaveFailed => '保存通知偏好失败，请重试';

  @override
  String get profileNotificationSound => '提示音';

  @override
  String get profileNotificationSoundHint => '收到通知时播放声音';

  @override
  String get profileNotificationPreview => '通知预览';

  @override
  String get profileNotificationPreviewHint => '在通知中显示消息内容';

  @override
  String profileNotificationTypes(Object count) {
    return '通知类型 ($count)';
  }

  @override
  String profileLoadFailed(Object error) {
    return '加载失败：$error';
  }

  @override
  String get profileSessionManagement => '会话管理';

  @override
  String get profileSessionManagementSubtitle => '查看和管理当前登录的设备会话';

  @override
  String get profileActiveSessions => '活跃会话';

  @override
  String get profileNoSessions => '暂无活跃会话';

  @override
  String get profileSessionDevice => '设备';

  @override
  String get profileSessionIp => 'IP 地址';

  @override
  String get profileSessionLastActive => '最后活跃';

  @override
  String get profileSessionExpires => '过期时间';

  @override
  String get profileRevokeSession => '撤销会话';

  @override
  String get profileRevokeSessionConfirm => '撤销会话？';

  @override
  String get profileRevokeSessionMessage => '撤销后该设备将被强制登出，需要重新登录。';

  @override
  String get profileSessionRevoked => '会话已撤销';

  @override
  String get profileSessionRevokeFailed => '撤销失败，请重试';

  @override
  String get profileSessionsLoadFailed => '加载会话失败';

  @override
  String get profileSessionCurrentDevice => '当前设备';

  @override
  String get changePasswordOldPassword => '原密码';

  @override
  String get changePasswordNewPassword => '新密码';

  @override
  String get changePasswordEnterNew => '请输入新密码';

  @override
  String get changePasswordMinLength => '密码至少 8 位';

  @override
  String get changePasswordMaxLength => '密码最多 24 位';

  @override
  String get changePasswordConfirmNew => '确认新密码';

  @override
  String get loginTwoFactorTitle => '两步验证';

  @override
  String get loginTwoFactorSubtitle => '输入验证器 App 中的 6 位验证码完成登录';

  @override
  String get loginTwoFactorCodeLabel => '验证码';

  @override
  String get loginTwoFactorCodeHint => '请输入 6 位验证码';

  @override
  String get loginTwoFactorUseBackupHint => '丢失认证器时可输入一次性备份码（XXXX-XXXX）';

  @override
  String get loginTwoFactorVerifyAndSignIn => '验证并登录';

  @override
  String get loginTwoFactorBackToLogin => '返回重新登录';

  @override
  String get twoFactorEnrollTitle => '开启两步验证';

  @override
  String get twoFactorEnrollSubtitle => '当前角色要求开启两步验证，请先完成注册引导';

  @override
  String get twoFactorEnrollPasswordLabel => '登录密码';

  @override
  String get twoFactorEnrollPasswordHint => '请输入登录密码';

  @override
  String get twoFactorEnrollContinue => '下一步：扫码';

  @override
  String get twoFactorEnrollScanHint => '使用验证器 App 扫描二维码，或复制秘钥手动添加';

  @override
  String get twoFactorEnrollSecretLabel => '复制秘钥';

  @override
  String get twoFactorEnrollConfirmCode => '确认开启';

  @override
  String get twoFactorEnrollBackupTitle => '备份码';

  @override
  String get twoFactorEnrollBackupHint => '以下一次性备份码仅显示这一次，丢失认证器时用于恢复登录，请妥善保存。';

  @override
  String get twoFactorEnrollBackupSavedCheck => '我已保存备份码';

  @override
  String get twoFactorEnrollSavedAndFinish => '完成并登录';

  @override
  String get twoFactorCopied => '已复制到剪贴板';

  @override
  String get twoFactorCopyCodes => '复制全部备份码';

  @override
  String get twoFactorDisableHint => '关闭后登录将不再需要验证码，请确认。';

  @override
  String get profileTwoFactorTitle => '两步验证';

  @override
  String get profileTwoFactorSubtitle => '为登录增加一次性验证码保护';

  @override
  String get profileTwoFactorEnabled => '已开启';

  @override
  String get profileTwoFactorDisabled => '未开启';

  @override
  String get profileTwoFactorRequiredBadge => '当前角色要求开启，尚未开启';

  @override
  String get profileTwoFactorEnableAction => '开启';

  @override
  String get profileTwoFactorDisableAction => '关闭';

  @override
  String get profileTwoFactorDisableConfirm => '确认关闭';

  @override
  String get profileTwoFactorLoadFailed => '状态加载失败';

  @override
  String get changePasswordMismatch => '两次密码不一致';

  @override
  String get changePasswordCancel => '取消';

  @override
  String get changePasswordConfirm => '确认修改';

  @override
  String get changePasswordSuccess => '密码修改成功';

  @override
  String get changePasswordWrongOld => '原密码错误';

  @override
  String get changePasswordFailed => '密码修改失败，请重试';

  @override
  String changePasswordEnterField(Object field) {
    return '请输入$field';
  }

  @override
  String get loginWelcome => '欢迎回来';

  @override
  String get loginDescription => '使用 OmniNest 内置账号登录。';

  @override
  String get loginSubtitle => '把家庭媒体、阅读、文件与自动化任务收拢到一个稳定的个人空间。';

  @override
  String get loginFeatureMedia => '媒体中心';

  @override
  String get loginFeatureReader => '阅读书库';

  @override
  String get loginFeatureFiles => '文件管理';

  @override
  String get loginFeatureAdmin => '系统控制台';

  @override
  String get loginUsername => '用户名';

  @override
  String get loginUsernameHint => '请输入用户名';

  @override
  String get loginPassword => '密码';

  @override
  String get loginShowPassword => '显示密码';

  @override
  String get loginHidePassword => '隐藏密码';

  @override
  String get loginPasswordHint => '请输入密码';

  @override
  String get loginSigningIn => '正在登录';

  @override
  String get loginSignIn => '登录';

  @override
  String get loginFailed => '登录失败，请稍后重试';

  @override
  String get loginConnectionError => '无法连接后端服务，请确认服务已启动';

  @override
  String get loginRequestFailed => '登录请求失败，请检查账号或网络';

  @override
  String get coreRetry => '重试';

  @override
  String get coreStartupFailed => '启动失败';

  @override
  String get coreStartupFailedHint => '运行依赖初始化失败，请重试。若问题持续，请检查本机媒体组件和应用日志。';

  @override
  String get coreCancel => '取消';

  @override
  String get coreConfirm => '确认';

  @override
  String get coreSave => '保存';

  @override
  String get coreClose => '关闭';

  @override
  String get coreBack => '返回';

  @override
  String get coreDelete => '删除';

  @override
  String get coreClear => '清除';

  @override
  String get coreChooseDate => '选择日期';

  @override
  String get corePlay => '播放';

  @override
  String get corePause => '暂停';

  @override
  String get corePrevious => '上一个';

  @override
  String get coreNext => '下一个';

  @override
  String get coreShowPassword => '显示密码';

  @override
  String get coreHidePassword => '隐藏密码';

  @override
  String get coreSearchHint => '搜索…';

  @override
  String get coreProfile => '个人中心';

  @override
  String get coreStorage => '存储空间';

  @override
  String get coreAdmin => '管理后台';

  @override
  String get coreSignOut => '退出登录';

  @override
  String get coreMenu => '菜单';

  @override
  String get coreMore => '更多操作';

  @override
  String get coreTheme => '主题';

  @override
  String get coreThemeLight => '浅色';

  @override
  String get coreThemeDark => '深色';

  @override
  String get coreLanguage => '语言';

  @override
  String get coreRoleSuperAdmin => '管理员';

  @override
  String get coreRoleAdmin => '管理';

  @override
  String get coreRoleMember => '成员';

  @override
  String get filesAllFiles => '全部文件';

  @override
  String get filesRecent => '最近使用';

  @override
  String get filesFavorites => '我的收藏';

  @override
  String get filesRecycleBin => '回收站';

  @override
  String get filesSharedWithMe => '共享给我';

  @override
  String get filesMyShares => '我的分享';

  @override
  String get filesShareManagement => '分享链接管理';

  @override
  String get filesStorageStats => '存储统计';

  @override
  String get filesUploadQueue => '上传队列';

  @override
  String get filesOfflineDownloads => '离线下载';

  @override
  String get filesExternalStorage => '外部存储';

  @override
  String get filesImportTasks => '导入任务';

  @override
  String get filesAllFilesDesc => '浏览根目录或指定目录，完成文件夹、文件和路径管理。';

  @override
  String get filesRecentDesc => '按访问时间倒序查看最近打开或下载过的文件。';

  @override
  String get filesFavoritesDesc => '集中查看星标文件，适合固定常用资料。';

  @override
  String get filesRecycleBinDesc => '查看软删除文件，支持恢复或彻底删除。';

  @override
  String get filesSharedWithMeDesc => '查看其他用户定向分享给当前账号的文件。';

  @override
  String get filesMySharesDesc => '查看当前用户创建的分享链接。';

  @override
  String get filesShareManagementDesc => '管理有效、过期或已撤销分享链接。';

  @override
  String get filesStorageStatsDesc => '查看容量、配额、文件类型分布和空间使用情况。';

  @override
  String get filesUploadQueueDesc => '查看分片上传会话、断点续传进度和上传状态。';

  @override
  String get filesOfflineDownloadsDesc => '管理 HTTP、BT 和磁力链离线下载任务。';

  @override
  String get filesExternalStorageDesc => '管理 OneDrive、WebDAV 等第三方存储挂载。';

  @override
  String get filesImportTasksDesc => '查看外部存储文件导入进度，支持取消排队中的任务。';

  @override
  String get filesSharedSpace => '共享空间';

  @override
  String get filesSharedSpaceDesc => '所有用户共享的文件空间';

  @override
  String get filesSharedSpaceUsage => '共享空间用量';

  @override
  String get filesSharedSpaceEmpty => '共享空间暂无文件';

  @override
  String get filesMoveToShared => '移到共享空间';

  @override
  String get filesMoveToSharedConfirm => '移到共享空间';

  @override
  String filesMoveToSharedMessage(Object name) {
    return '将 \"$name\" 移到共享空间？所有用户将可见。';
  }

  @override
  String get filesMoveToPersonal => '移回个人空间';

  @override
  String get filesMoveToPersonalConfirm => '移回个人空间';

  @override
  String filesMoveToPersonalMessage(Object name) {
    return '将 \"$name\" 移回个人空间？';
  }

  @override
  String get filesMoveToPersonalLabel => '移回';

  @override
  String get filesCount => '个文件';

  @override
  String get filesCategoryAll => '全部';

  @override
  String get filesCategoryImage => '图片';

  @override
  String get filesCategoryVideo => '视频';

  @override
  String get filesCategoryAudio => '音频';

  @override
  String get filesCategoryDocument => '文档';

  @override
  String get filesCategoryNovel => '小说';

  @override
  String get filesCategoryComic => '漫画';

  @override
  String get filesCategoryArchive => '压缩包';

  @override
  String get filesCategoryOther => '其他';

  @override
  String get filesGroupFiles => '文件';

  @override
  String get filesGroupSharing => '协作分享';

  @override
  String get filesGroupTransfer => '传输任务';

  @override
  String get filesGroupStorage => '存储';

  @override
  String get filesNavFiles => '文件';

  @override
  String get filesNavRecent => '最近';

  @override
  String get filesNavShared => '共享';

  @override
  String get filesNavRecycleBin => '回收站';

  @override
  String get filesOpenFileMenu => '打开文件菜单';

  @override
  String get filesSearch => '搜索';

  @override
  String get filesRefresh => '刷新';

  @override
  String get filesSearchFiles => '搜索文件';

  @override
  String get filesSearchHint => '输入文件名、路径或类型';

  @override
  String get filesStorageUsage => '存储用量';

  @override
  String get filesWaitingStats => '等待统计数据';

  @override
  String get filesUnlimited => '无限制';

  @override
  String get filesUnlimitedQuota => '无限制配额';

  @override
  String filesUsedPercent(Object percent, Object remaining) {
    return '$percent% 已使用 · $remaining 剩余';
  }

  @override
  String filesUsedOf(Object total, Object used) {
    return '$used / $total';
  }

  @override
  String get filesStorageSpace => '存储空间';

  @override
  String get filesFolders => '文件夹';

  @override
  String get filesFiles => '文件';

  @override
  String get filesCapacity => '容量';

  @override
  String get filesCurrentView => '当前视图';

  @override
  String get filesCurrentViewTotal => '当前视图合计';

  @override
  String get filesSoftDeleted => '软删除文件';

  @override
  String get filesEmpty => '暂无文件';

  @override
  String get filesRecycleBinEmpty => '回收站为空';

  @override
  String get filesCameraTakePhoto => '拍照上传';

  @override
  String get filesCameraRecordVideo => '录像上传';

  @override
  String get filesUploadFile => '上传文件';

  @override
  String filesLoadMore(Object loaded, Object total) {
    return '加载更多（已加载 $loaded / $total）';
  }

  @override
  String get filesDropToUpload => '拖放文件到此处上传';

  @override
  String filesUploadProcessing(Object count, Object progress) {
    return '正在处理 $count 个文件 · 总进度 $progress';
  }

  @override
  String get filesViewAll => '查看全部';

  @override
  String get filesCollapseQueue => '收起上传队列';

  @override
  String get filesExpandQueue => '展开上传队列';

  @override
  String filesMoreInQueue(Object count) {
    return '还有 $count 个任务在上传队列中';
  }

  @override
  String get filesSortBy => '排序方式';

  @override
  String get filesSortName => '名称';

  @override
  String get filesSortTime => '时间';

  @override
  String get filesSortSize => '大小';

  @override
  String get filesNewFolder => '新建文件夹';

  @override
  String get filesCreate => '创建';

  @override
  String get filesFolderName => '文件夹名称';

  @override
  String get filesRename => '重命名';

  @override
  String get filesSave => '保存';

  @override
  String get filesFileName => '文件名';

  @override
  String get filesFolder => '文件夹';

  @override
  String get filesMoveToRecycleBin => '移入回收站';

  @override
  String get filesPurge => '彻底删除';

  @override
  String get filesCopyToEllipsis => '复制到…';

  @override
  String filesCopiedFile(Object name) {
    return '已复制 \"$name\"';
  }

  @override
  String get filesCopyFailed => '复制失败';

  @override
  String get filesMoveToEllipsis => '移动到…';

  @override
  String get filesDownload => '下载';

  @override
  String get filesShare => '分享';

  @override
  String get filesOpen => '打开';

  @override
  String get filesPreview => '预览';

  @override
  String get filesRestore => '恢复';

  @override
  String get filesMoreActions => '更多操作';

  @override
  String get filesMoreSections => '更多分区';

  @override
  String get filesFilterSort => '排序与筛选';

  @override
  String get filesSwitchView => '切换视图';

  @override
  String get filesFileActions => '文件操作';

  @override
  String filesDeleteConfirmTitle(Object name) {
    return '移入回收站？';
  }

  @override
  String filesDeleteConfirmMessage(Object name) {
    return '\"$name\" 会从文件列表中移除，并同步清理影视、音乐等模块中的关联记录。';
  }

  @override
  String filesPurgeConfirmTitle(Object name) {
    return '彻底删除？';
  }

  @override
  String filesPurgeConfirmMessage(Object name) {
    return '\"$name\" 将从回收站永久删除，此操作不可撤销。';
  }

  @override
  String filesSelectedCount(Object count) {
    return '已选择 $count 项';
  }

  @override
  String get filesSelectAll => '全选';

  @override
  String get filesDeselect => '取消选择';

  @override
  String get filesBatchRestore => '批量恢复';

  @override
  String get filesBatchPurge => '批量彻底删除';

  @override
  String get filesBatchMove => '批量移动';

  @override
  String get filesBatchDelete => '批量删除';

  @override
  String get filesBatchAddFavorite => '批量收藏';

  @override
  String get filesBatchRemoveFavorite => '批量取消收藏';

  @override
  String get filesAddFavorite => '收藏';

  @override
  String get filesRemoveFavorite => '取消收藏';

  @override
  String get filesBatchRestoreTitle => '批量恢复？';

  @override
  String filesBatchRestoreMessage(Object count) {
    return '将恢复选中的 $count 个文件。';
  }

  @override
  String get filesBatchPurgeTitle => '批量彻底删除？';

  @override
  String filesBatchPurgeMessage(Object count) {
    return '选中的 $count 个文件将永久删除，此操作不可撤销。';
  }

  @override
  String get filesBatchDeleteTitle => '批量移入回收站？';

  @override
  String filesBatchDeleteMessage(Object count) {
    return '选中的 $count 个文件将移入回收站。';
  }

  @override
  String get filesDownloadLinkCopied => '下载链接已复制到剪贴板';

  @override
  String get filesDownloadFailed => '获取下载链接失败';

  @override
  String filesMovedFile(Object name) {
    return '已移动 \"$name\"';
  }

  @override
  String filesMovedCount(Object count) {
    return '已移动 $count 个文件';
  }

  @override
  String filesUploadComplete(Object count) {
    return '已完成 $count 个文件上传';
  }

  @override
  String filesUploadBatchSummary(
    Object completed,
    Object conflicts,
    Object failed,
    Object paused,
  ) {
    return '上传完成 $completed 个，冲突 $conflicts 个，失败 $failed 个，暂停 $paused 个';
  }

  @override
  String get filesSelectTargetFolder => '选择目标文件夹';

  @override
  String get filesRootDirectory => '根目录';

  @override
  String get filesGoToParent => '返回上级目录';

  @override
  String get filesFolderEmpty => '此文件夹为空';

  @override
  String filesMoveToFolder(Object name) {
    return '移动到「$name」';
  }

  @override
  String get filesStatusQueued => '等待中';

  @override
  String get filesStatusUploading => '上传中';

  @override
  String get filesStatusPaused => '已暂停';

  @override
  String get filesStatusFailed => '失败';

  @override
  String get filesStatusCompleted => '已完成';

  @override
  String get filesStatusCancelled => '已取消';

  @override
  String get filesStatusCancelling => '取消中';

  @override
  String get filesOfflineEmpty => '暂无离线下载任务';

  @override
  String get filesNewOfflineDownload => '新建离线下载';

  @override
  String get filesDownloadLink => '下载链接';

  @override
  String get filesOfflineDownloadHint => '支持 HTTP、BT 种子链接和 magnet 磁力链接';

  @override
  String get filesNewTask => '新建任务';

  @override
  String get filesCancelTask => '取消任务';

  @override
  String get filesTaskEnded => '任务已结束';

  @override
  String get filesCancelOfflineConfirm => '取消离线下载？';

  @override
  String filesCancelOfflineMessage(Object name) {
    return '\"$name\" 的下载任务会停止，未完成的数据不会导入文件库。';
  }

  @override
  String get filesNoExternalStorage => '暂无外部存储';

  @override
  String get filesAddMount => '添加挂载';

  @override
  String get filesEdit => '编辑';

  @override
  String get filesBrowseRemote => '浏览远程文件';

  @override
  String get filesDisableMount => '禁用挂载';

  @override
  String get filesDisableMountConfirm => '禁用外部挂载？';

  @override
  String filesDisableMountMessage(Object name) {
    return '\"$name\" 将不再参与文件挂载和同步。';
  }

  @override
  String get filesDeleteMount => '删除挂载';

  @override
  String get filesDeleteMountConfirm => '删除外部挂载？';

  @override
  String filesDeleteMountMessage(Object name) {
    return '将永久删除 \"$name\" 及其 rclone 配置，此操作不可撤销。';
  }

  @override
  String get filesCloseBrowse => '关闭浏览';

  @override
  String get filesDirectoryEmpty => '此目录为空';

  @override
  String get filesEnterFolder => '进入文件夹';

  @override
  String get filesImportFile => '导入此文件';

  @override
  String get filesImportFolder => '导入整个文件夹';

  @override
  String get filesImportConfirm => '导入外部内容？';

  @override
  String filesImportMessage(Object name) {
    return '将 \"$name\" 导入到当前文件目录。';
  }

  @override
  String get filesImportSizeGuardHint => '超大文件可能被拒绝导入；4K 等重片源请放入本地媒体目录。';

  @override
  String get filesTestConnection => '测试连接';

  @override
  String get filesAuthorizeAccount => '去授权';

  @override
  String get filesAuthorizeHint => '在浏览器中打开以下链接完成授权，完成后回到本页刷新连接：';

  @override
  String get filesImport => '导入';

  @override
  String get filesNoImportTasks => '暂无导入任务';

  @override
  String get filesCancelImportConfirm => '取消导入任务？';

  @override
  String filesCancelImportMessage(Object name) {
    return '\"$name\" 的导入将被取消。';
  }

  @override
  String get filesDeleteRecord => '删除记录';

  @override
  String get filesDeleteImportConfirm => '删除导入记录？';

  @override
  String filesDeleteImportMessage(Object name) {
    return '\"$name\" 的导入记录将被删除。';
  }

  @override
  String get filesNoSharedFiles => '暂无共享文件';

  @override
  String filesFromUser(Object userId) {
    return '来自 $userId';
  }

  @override
  String get filesLongTerm => '长期有效';

  @override
  String get filesHasExpiry => '有到期时间';

  @override
  String get filesShareMgmt => '分享管理';

  @override
  String get filesShareMgmtDesc => '管理我创建的分享链接，可撤销已分享的链接。';

  @override
  String get filesNoShareLinks => '暂无分享链接';

  @override
  String filesLoadFailed(Object error) {
    return '加载失败：$error';
  }

  @override
  String get filesAccessUnlimited => '不限';

  @override
  String get filesShareActive => '有效';

  @override
  String get filesShareRevoked => '已撤销';

  @override
  String get filesShareExpired => '已过期';

  @override
  String get filesShareExhausted => '已达上限';

  @override
  String get filesRevokeShare => '撤销分享';

  @override
  String get filesRevokeShareConfirm => '撤销分享？';

  @override
  String filesRevokeShareMessage(Object name) {
    return '\"$name\" 的分享链接将失效，已获得链接的人无法继续访问。';
  }

  @override
  String get filesClose => '关闭';

  @override
  String get filesWaitingUpload => '等待上传';

  @override
  String get filesDirectUploading => '直传上传中';

  @override
  String get filesMultipartUploading => '分片上传中';

  @override
  String get filesUploadPausedMsg => '已暂停，可继续上传';

  @override
  String get filesUploadPausePending => '正在暂停当前传输';

  @override
  String get filesResumingUpload => '继续上传中';

  @override
  String get filesUploadRetrying => '清理完成，正在重新上传';

  @override
  String get filesUploadDone => '上传完成';

  @override
  String get filesUploadScanPending => '上传完成，安全扫描中，文件通过后自动显示';

  @override
  String filesUploadedParts(Object current, Object total) {
    return '已上传 $current/$total 分片';
  }

  @override
  String get filesCleanupConflict => '清理回收站中的同名文件？';

  @override
  String get filesCleanupMessage => '回收站中存在同名文件，清理后将自动重新上传。';

  @override
  String get filesCleanupAndRetry => '清理并重试';

  @override
  String get filesDeleteUploadTask => '删除上传任务？';

  @override
  String get filesDeleteUploadTaskMessage => '该上传任务会从队列中移除，未完成的服务器会话也会被取消。';

  @override
  String get filesDeleteTask => '删除任务';

  @override
  String get filesEditExternalStorage => '编辑外部存储';

  @override
  String get filesAddExternalStorage => '添加外部存储';

  @override
  String get externalStorageSpace => '空间用量';

  @override
  String get externalMkdir => '创建目录';

  @override
  String get externalMkdirHint => '输入目录路径，如 /photos/2024';

  @override
  String get externalDeleteFile => '删除';

  @override
  String get externalRenameFile => '重命名';

  @override
  String get externalDeleteConfirm => '确定要删除远程文件吗？此操作不可撤销。';

  @override
  String externalSpaceUsedOf(Object used, Object total) {
    return '$used / $total';
  }

  @override
  String get filesStorageType => '存储类型';

  @override
  String get filesDisplayName => '显示名称';

  @override
  String get filesDisplayNameHint => '如：我的坚果云';

  @override
  String get filesConnectionCredentials => '连接凭据';

  @override
  String get filesExistingSecretPreserved => '密码、密钥和令牌不会回传；保持为空将继续使用已保存的值。';

  @override
  String get filesKeepExistingSecretHint => '留空以保留已保存的值';

  @override
  String get filesS3Provider => 'S3 提供商';

  @override
  String get filesEndpointRequired => '端点地址（必填）';

  @override
  String get filesEndpointHint => '如 http://omninest-minio:9000';

  @override
  String get filesRegion => '区域';

  @override
  String get filesRegionHint => '如 us-east-1（可选）';

  @override
  String get filesServiceType => '服务类型';

  @override
  String get filesWebdavUrl => 'WebDAV 地址';

  @override
  String get filesUsername => '用户名';

  @override
  String get filesPasswordOrApp => '密码 / 应用密码';

  @override
  String get filesDirectoryPath => '目录路径';

  @override
  String get filesClientIdOptional => 'Client ID（可选）';

  @override
  String get filesClientSecretOptional => 'Client Secret（可选）';

  @override
  String get filesUnknownStorageType => '未知存储类型';

  @override
  String get filesAdvancedOptions => '高级选项';

  @override
  String get filesMaxAccessCount => '最大访问次数';

  @override
  String get filesNoLimit => '不限制';

  @override
  String get filesExpiryTime => '过期时间';

  @override
  String get filesNeverExpire => '永不过期';

  @override
  String get filesCreateShareLink => '创建分享链接';

  @override
  String get filesCreateFailed => '创建失败';

  @override
  String get filesSetPassword => '设置密码';

  @override
  String get filesPasswordRequired => '访问时需要输入密码';

  @override
  String get filesNoPasswordAnyone => '无密码，任何人可访问';

  @override
  String get filesRandomGenerate => '随机生成';

  @override
  String get filesCustomPassword => '自定义密码';

  @override
  String get filesEnterPassword => '输入密码';

  @override
  String get filesEnterCustomPassword => '请输入自定义密码';

  @override
  String get filesCopiedClipboard => '已复制到剪贴板';

  @override
  String get filesPasswordLabel => '密码';

  @override
  String filesSharePasswordLabel(Object password) {
    return '密码: $password';
  }

  @override
  String get filesCopyLinkWithPassword => '复制链接（含密码）';

  @override
  String get filesCopyLinkOnly => '仅复制链接';

  @override
  String get filesCopyLink => '复制链接';

  @override
  String get filesCannotLoadImage => '无法加载图片';

  @override
  String get filesImageLoadFailed => '图片加载失败';

  @override
  String get filesCannotGetImageUrl => '无法获取图片地址';

  @override
  String get filesCannotLoadVideo => '无法加载视频';

  @override
  String get filesCannotGetVideoUrl => '无法获取视频地址';

  @override
  String get filesCannotLoadAudio => '无法加载音频';

  @override
  String get filesCannotGetAudioUrl => '无法获取音频地址';

  @override
  String get filesCannotLoadFile => '无法加载文件';

  @override
  String get filesCannotGetFileUrl => '无法获取文件地址';

  @override
  String get filesPdfDownloadHint => '暂不支持 PDF 在线预览，请下载后查看';

  @override
  String get filesAccessKeyId => '访问密钥 ID';

  @override
  String get filesSecretAccessKey => '访问密钥';

  @override
  String get filesOauthTokenJson => 'OAuth 令牌 JSON';

  @override
  String get filesType => '类型';

  @override
  String get filesUnknown => '未知';

  @override
  String get filesSizeLabel => '大小';

  @override
  String get filesPath => '路径';

  @override
  String get filesShareAccessError => '无法访问分享链接';

  @override
  String get filesRetry => '重试';

  @override
  String get filesSavedToMyFiles => '文件已保存到我的文件';

  @override
  String get filesFileExists => '文件已存在';

  @override
  String get filesGotIt => '知道了';

  @override
  String filesSaveFailed(Object message) {
    return '保存失败：$message';
  }

  @override
  String get filesPasswordAccess => '此分享需要密码访问';

  @override
  String get filesEnterSharePassword => '请输入分享密码以查看文件';

  @override
  String get filesAccess => '访问';

  @override
  String get filesSaveToMyFiles => '保存到我的文件';

  @override
  String get filesDelete => '删除';

  @override
  String get filesCancel => '取消';

  @override
  String get filesConfirm => '确认';

  @override
  String get filesOpenTooltip => '打开';

  @override
  String filesConflictMsg(Object name) {
    return '回收站存在同名文件\"$name\"，需清理后重试';
  }

  @override
  String get filesStatusConflict => '冲突';

  @override
  String get filesStatusCreated => '已创建';

  @override
  String get filesLocalUpload => '本地上传';

  @override
  String filesUploadTaskCount(Object count) {
    return '$count 个任务';
  }

  @override
  String get filesNoLocalUpload => '暂无本地上传';

  @override
  String get filesFailedTasks => '失败任务';

  @override
  String get filesNoFailedTasks => '暂无失败任务';

  @override
  String get filesNoUploadTasks => '暂无上传任务';

  @override
  String get filesPauseUpload => '暂停上传';

  @override
  String get filesResumeUpload => '继续上传';

  @override
  String get filesCleanAndRetry => '清理并重试';

  @override
  String get filesOfflineQueued => '排队中';

  @override
  String get filesOfflineRunning => '下载中';

  @override
  String get filesOfflineCancelling => '取消中';

  @override
  String get filesOfflineCancelled => '已取消';

  @override
  String get filesImportQueued => '排队中';

  @override
  String get filesImportScanning => '正在扫描源内容';

  @override
  String get filesImportTransferring => '正在从外部存储传输';

  @override
  String get filesImportWriting => '正在写入文件库';

  @override
  String get filesImportWaitingWorker => '等待后台 Worker 处理';

  @override
  String filesImportFileProgress(int completed, int total) {
    return '已完成 $completed/$total 个文件';
  }

  @override
  String filesImportCurrentFile(Object name) {
    return '当前：$name';
  }

  @override
  String get filesImportRunning => '导入中';

  @override
  String get filesImportCancelling => '取消中';

  @override
  String get filesImportCancelled => '已取消';

  @override
  String get filesS3Compatible => 'S3 兼容存储';

  @override
  String get filesAliyunDrive => '阿里云盘';

  @override
  String get filesLocalStorage => '本地目录';

  @override
  String get portalSearch => '搜索';

  @override
  String get portalOpenReadingItem => '打开阅读';

  @override
  String get portalOpenPhoto => '查看照片';

  @override
  String get portalEnterSystem => '进入系统';

  @override
  String get portalVisualCompactTitle => '桌面首页已切换为单列';

  @override
  String get portalVisualCompactBody => '当前窗口较窄，内容封面与状态信息以单列排列。';

  @override
  String get portalVisualEyebrowRecentContent => '最近内容';

  @override
  String get portalVisualEyebrowCompact => 'OmniNest 首页';

  @override
  String get portalVisualStatusTitle => '需要关注';

  @override
  String get portalVisualLastReadingLocation => '上次阅读位置';

  @override
  String get portalVisualSync => '同步';

  @override
  String get portalFileManager => 'File Manager';

  @override
  String get portalFileManagerSubtitle => '网络存储、文件夹、回收站与对象预览。';

  @override
  String get portalMovieCenter => '媒体库';

  @override
  String get portalMovieCenterSubtitle => '集中管理电影、剧集与动漫，支持元数据同步和直接播放。';

  @override
  String get portalReaderCenter => 'Reader Center';

  @override
  String get portalReaderCenterSubtitle => '图书、漫画与阅读进度续接。';

  @override
  String get portalMusic => 'Music';

  @override
  String get portalMusicSubtitle => '无损音乐、播放队列和歌单管理。';

  @override
  String get portalPhotos => 'Photos';

  @override
  String get portalPhotosSubtitle => '相册、自动备份和回忆时间线。';

  @override
  String get portalAdmin => '管理';

  @override
  String get portalAdminSubtitle => '用户权限、系统配置、任务与运行状态。';

  @override
  String get portalDescriptionAdmin => '从一个入口切换媒体、阅读、文件和系统管理；每个子系统进入后拥有独立工作台。';

  @override
  String get portalDescriptionMember => '从一个入口切换媒体、阅读和文件管理；每个子系统进入后拥有独立工作台。';

  @override
  String get portalNoFiles => '暂无文件';

  @override
  String get portalNoPlayHistory => '暂无播放记录';

  @override
  String get portalNoReadingHistory => '暂无阅读记录';

  @override
  String get portalNoPhotos => '暂无照片';

  @override
  String portalPhotoCount(Object count) {
    return '$count 张照片';
  }

  @override
  String portalAlbumCount(Object count) {
    return '$count 个相册';
  }

  @override
  String portalMovieBadge(Object count) {
    return '$count 部';
  }

  @override
  String portalReaderBadge(Object count) {
    return '$count 续读';
  }

  @override
  String portalMusicBadge(Object count) {
    return '$count 首';
  }

  @override
  String portalPhotoBadge(Object count) {
    return '$count 张';
  }

  @override
  String get portalRelativeNow => '刚刚';

  @override
  String portalRelativeMinutes(Object n) {
    return '$n 分钟前';
  }

  @override
  String portalRelativeHours(Object n) {
    return '$n 小时前';
  }

  @override
  String get portalRelativeYesterday => '昨天';

  @override
  String portalRelativeDays(Object n) {
    return '$n 天前';
  }

  @override
  String portalRelativeMonths(Object n) {
    return '$n 个月前';
  }

  @override
  String portalRelativeYears(Object n) {
    return '$n 年前';
  }

  @override
  String get portalStorageTitle => '存储空间';

  @override
  String portalStorageUnlimited(Object used) {
    return '$used GiB / 无限制';
  }

  @override
  String get portalTaskTitle => '任务';

  @override
  String get portalTaskRunning => '运行中';

  @override
  String get portalTaskQueued => '队列中';

  @override
  String get portalTaskFailed => '失败';

  @override
  String get portalNowPlaying => '正在播放';

  @override
  String get portalNoPlayRecord => '暂无播放记录';

  @override
  String get portalImmersivePlayback => '沉浸播放';

  @override
  String get portalExitImmersivePlayback => '退出沉浸播放';

  @override
  String get portalMusicVisualizerSeek => '播放进度';

  @override
  String get portalMusicVisualizerVolume => '音量';

  @override
  String get portalMusicVisualizerEdit => '编辑视觉';

  @override
  String get portalMusicVisualizerSave => '保存视觉';

  @override
  String get portalMusicVisualizerResetDefault => '恢复默认';

  @override
  String get portalMusicVisualizerLyrics => '歌词';

  @override
  String get portalMusicVisualizerPlayer => '播放器';

  @override
  String get portalMusicVisualizerLow => '低频';

  @override
  String get portalMusicVisualizerMid => '中频';

  @override
  String get portalMusicVisualizerHigh => '高频';

  @override
  String get portalMusicVisualizerCurrentFont => '当前句字号';

  @override
  String get portalMusicVisualizerInactiveOpacity => '非当前句透明度';

  @override
  String get portalMusicVisualizerVisibleLines => '可见行数';

  @override
  String get musicVisualizerLyricActiveColor => '当前歌词颜色';

  @override
  String get musicVisualizerLyricReadColor => '已读歌词颜色';

  @override
  String get musicVisualizerLyricUnreadColor => '未读歌词颜色';

  @override
  String get musicVisualizerLyricBreathing => '歌词呼吸效果';

  @override
  String get musicVisualizerLyricLineSpacing => '歌词行距';

  @override
  String get musicVisualizerLyricGlowIntensity => '溢光强度';

  @override
  String get musicVisualizerLyricGlowColor => '溢光颜色';

  @override
  String get musicVisualizerLyricPosition => '歌词位置';

  @override
  String get musicVisualizerLyricPositionLeft => '左侧';

  @override
  String get musicVisualizerLyricPositionCenter => '居中';

  @override
  String get musicVisualizerLyricPositionRight => '右侧';

  @override
  String get musicVisualizerAudioBarStyle => '音频条样式';

  @override
  String get musicVisualizerAudioBarSpectrum => '频谱柱';

  @override
  String get musicVisualizerAudioBarLine => '流光曲线';

  @override
  String get musicVisualizerAudioBarDots => '脉冲点阵';

  @override
  String get musicVisualizerColorHue => '色相';

  @override
  String get musicVisualizerColorPreset => '预设颜色';

  @override
  String get musicVisualizerColorTheme => '主题配色';

  @override
  String get musicVisualizerColorCustom => '自定义颜色';

  @override
  String get musicVisualizerColorHex => 'HEX 色值';

  @override
  String get musicVisualizerColorResetDefault => '恢复默认色';

  @override
  String get portalMusicVisualizerLyricGlow => '歌词溢光';

  @override
  String get portalMusicVisualizerOriginalCover => '原始封面';

  @override
  String get portalMusicVisualizerCoverBorder => '封面边框';

  @override
  String get portalMusicVisualizerProgressControl => '进度条';

  @override
  String get musicVisualizerPlayerVisible => '显示底部播放器';

  @override
  String get musicVisualizerAudioBar => '显示音频条';

  @override
  String get musicVisualizerFrequencyResponse => '音频条频率响应';

  @override
  String get musicVisualizerCoverSize => '封面尺寸';

  @override
  String get musicVisualizerCoverRadius => '封面圆角';

  @override
  String get musicVisualizerCoverTilt => '封面倾斜角度';

  @override
  String get musicVisualizerHeroCoverOpacity => 'Hero 封面不透明度';

  @override
  String get portalReading => '在读';

  @override
  String get portalNoReadingBook => '暂无在读书籍';

  @override
  String get portalRecentPhotos => '最近照片';

  @override
  String portalNewPhotoCount(Object count) {
    return '$count 张新照片';
  }

  @override
  String get portalQuickUpload => '上传';

  @override
  String get portalQuickDownload => '下载';

  @override
  String get portalQuickNew => '新建';

  @override
  String get portalQuickActions => '快捷操作';

  @override
  String get portalQuickSearch => '搜索';

  @override
  String get portalQuickScan => '扫描';

  @override
  String get portalQuickPlay => '播放';

  @override
  String get portalMobileGreetingMorning => '早上好';

  @override
  String get portalMobileGreetingAfternoon => '下午好';

  @override
  String get portalMobileGreetingEvening => '晚上好';

  @override
  String get portalMobileContinueUsing => '继续使用';

  @override
  String get portalMobileNoContinue => '暂无未完成内容';

  @override
  String get portalMobileSystemSummary => '系统摘要';

  @override
  String get portalMobileSyncOnline => '同步服务在线';

  @override
  String get portalMobileSyncOffline => '离线，等待恢复同步';

  @override
  String portalMobileTaskSummary(Object active, Object failed) {
    return '$active 项运行中，$failed 项失败';
  }

  @override
  String portalMobileStorageUsed(Object used) {
    return '已使用 $used';
  }

  @override
  String get portalMobileViewAll => '查看全部';

  @override
  String get portalContinueWatching => '最近观看';

  @override
  String get portalNoWatchingContent => '暂无在看内容';

  @override
  String get portalPressBackAgain => '再按一次退出';

  @override
  String get portalLoadMovieFailed => '加载媒体库信息失败';

  @override
  String get portalLoadMusicFailed => '加载音乐信息失败';

  @override
  String get portalLoadStorageFailed => '加载存储信息失败';

  @override
  String get portalLoadReadingFailed => '加载阅读信息失败';

  @override
  String get portalLoadPhotoFailed => '加载照片信息失败';

  @override
  String get portalDockFiles => '文件';

  @override
  String get portalDockMovies => '媒体';

  @override
  String get portalDockMusic => '音乐';

  @override
  String get portalDockPhotos => '照片';

  @override
  String get portalDockReading => '阅读';

  @override
  String get portalWeatherTitle => '天气';

  @override
  String get portalWeatherUpdated => '已更新';

  @override
  String get portalWeatherDisconnected => '未连接';

  @override
  String portalWeatherFeelsLike(Object text, Object feelsLike) {
    return '$text · 体感$feelsLike°';
  }

  @override
  String portalWeatherSunrise(Object time) {
    return '日出 $time';
  }

  @override
  String portalWeatherSunset(Object time) {
    return '日落 $time';
  }

  @override
  String get portalWeatherConfigApiKey => '请配置 API Key';

  @override
  String get portalWeatherWeeklyStats => '本周统计';

  @override
  String get portalWeatherStatReading => '在读';

  @override
  String get portalWeatherStatPlaying => '播放';

  @override
  String get portalWeatherStatPhotos => '照片';

  @override
  String get portalWeatherUnknown => '未知';

  @override
  String get portalWeatherLoading => '加载中';

  @override
  String get portalWeatherDefaultLocation => '北京';

  @override
  String get portalWeatherTipMask => '空气质量较差，建议佩戴口罩';

  @override
  String get portalWeatherTipRain => '有雨，出门记得带伞';

  @override
  String get portalWeatherTipIce => '路面可能湿滑，注意防滑';

  @override
  String get portalWeatherTipUV => '紫外线较强，注意防晒';

  @override
  String get portalWeatherTipCold => '体感较冷，注意添衣保暖';

  @override
  String get portalWeatherTipHot => '天气炎热，注意防暑补水';

  @override
  String get portalWeatherTipFog => '有雾，出行注意安全';

  @override
  String get portalWeatherTipNice => '天气不错，适合户外活动';

  @override
  String get portalWeatherHumidity => '湿度';

  @override
  String get portalWeatherWind => '风向';

  @override
  String get portalWeatherVisibility => '能见度';

  @override
  String get portalWeatherPressure => '气压';

  @override
  String get portalWeatherUV => '紫外线';

  @override
  String get portalWeatherPrecip => '降水';

  @override
  String get portalWeatherAdvice => '建议';

  @override
  String get portalWeatherSunriseLabel => '日出';

  @override
  String get portalWeatherSunsetLabel => '日落';

  @override
  String get portalWeatherForecastHourly => '逐小时';

  @override
  String get portalWeatherForecastWeekly => '一周预报';

  @override
  String get portalWeatherForecastToday => '今天';

  @override
  String get portalWeatherForecastNow => '现在';

  @override
  String get portalWeatherForecastEmpty => '暂无预报数据';

  @override
  String get portalWeatherDebugTooltip => '调试天气视觉';

  @override
  String get portalWeatherDebugLive => '实时天气';

  @override
  String get portalWeatherDebugDawn => '清晨';

  @override
  String get portalWeatherDebugSunny => '晴天';

  @override
  String get portalWeatherDebugSunnyNight => '夜间晴天';

  @override
  String get portalWeatherDebugDusk => '日暮';

  @override
  String get portalWeatherDebugPartlyCloudy => '多云';

  @override
  String get portalWeatherDebugPartlyCloudyNight => '夜间多云';

  @override
  String get portalWeatherDebugCloudy => '阴天';

  @override
  String get portalWeatherDebugCloudyNight => '夜间阴天';

  @override
  String get portalWeatherDebugLightRain => '小雨';

  @override
  String get portalWeatherDebugLightRainLeft => '小雨左斜';

  @override
  String get portalWeatherDebugHeavyRain => '大雨';

  @override
  String get portalWeatherDebugHeavyRainRight => '大雨右斜';

  @override
  String get portalWeatherDebugRainNight => '夜间小雨';

  @override
  String get portalWeatherDebugStorm => '雷雨';

  @override
  String get portalWeatherDebugLightSnow => '小雪';

  @override
  String get portalWeatherDebugHeavySnow => '大雪';

  @override
  String get portalWeatherDebugSnowNight => '夜间小雪';

  @override
  String get portalWeatherDebugFog => '雾';

  @override
  String get portalWeatherDebugHaze => '霾';

  @override
  String get portalWeatherDebugDust => '沙尘';

  @override
  String get portalWeatherDebugHeat => '高温';

  @override
  String get portalWeatherDebugCold => '低温';

  @override
  String get portalWeatherDebugTimeDawn => '清晨';

  @override
  String get portalWeatherDebugTimeDay => '白天';

  @override
  String get portalWeatherDebugTimeDusk => '日暮';

  @override
  String get portalWeatherDebugTimeNight => '夜晚';

  @override
  String get portalLocalBackdropShort => '背景库';

  @override
  String get portalLocalBackdropTitle => '背景库';

  @override
  String get portalLocalBackdropSubtitle =>
      '背景素材库随账号同步，Web、桌面与移动端共用；内置壁纸离线同样可用。';

  @override
  String get portalLocalBackdropLoadFailed => '背景库加载失败';

  @override
  String get portalLocalBackdropAddFiles => '添加背景';

  @override
  String get portalLocalBackdropScanDirectory => '扫描目录';

  @override
  String get portalLocalBackdropUploading => '正在上传…';

  @override
  String portalLocalBackdropUploadFailedNames(Object titles) {
    return '上传失败：$titles';
  }

  @override
  String get portalLocalBackdropDeleteFailed => '删除失败，请稍后重试';

  @override
  String get portalLocalBackdropQuotaExceeded => '背景素材数量或存储空间配额不足';

  @override
  String get portalLocalBackdropUnsupportedFormat =>
      '仅支持 JPG、PNG、WebP、GIF 图片或 MP4、WebM、MOV 视频';

  @override
  String get portalLocalBackdropFileTooLarge => '背景素材文件过大';

  @override
  String get portalLocalBackdropScanUnavailable => '安全扫描服务不可用，暂无法上传';

  @override
  String get portalLocalBackdropMalwareDetected => '文件检测到安全威胁，已拒绝';

  @override
  String get portalLocalBackdropRateLimited => '上传过于频繁，请稍后再试';

  @override
  String get portalLocalBackdropClearAll => '全部清理';

  @override
  String get portalLocalBackdropClearAllTitle => '移除全部背景？';

  @override
  String get portalLocalBackdropClearAllMessage =>
      '背景素材将从服务端素材库移除并在所有设备上消失；内置壁纸离线仍可用。';

  @override
  String get portalLocalBackdropClearAllConfirm => '移除';

  @override
  String portalLocalBackdropCount(Object count) {
    return '$count 个背景';
  }

  @override
  String get portalLocalBackdropEmpty =>
      '还没有背景素材。添加视频壁纸、GIF 或图片后，会自动同步到你的所有设备。';

  @override
  String get portalLocalBackdropFilterEmpty => '当前分类没有可用背景';

  @override
  String get portalLocalBackdropEmptyScan =>
      '未发现可用背景文件。当前支持 MP4、WEBM、MOV、M4V、GIF、JPG、PNG、WEBP。';

  @override
  String get portalLocalBackdropScanFailed => '扫描失败，请检查目录权限';

  @override
  String get portalLocalBackdropMissing => '文件已缺失';

  @override
  String get portalLocalBackdropProcessing => '处理中';

  @override
  String get portalLocalBackdropProcessingVideo => '处理中（视频约需 1-2 分钟）';

  @override
  String get portalLocalBackdropFailed => '已失效';

  @override
  String get portalLocalBackdropRemoveConfirmTitle => '移除该背景？';

  @override
  String get portalLocalBackdropRemoveConfirmMessage =>
      '素材将从服务端背景库删除，并在所有设备上消失。';

  @override
  String portalLocalBackdropClearPartial(int removed, int failed) {
    return '已清理 $removed 项，失败 $failed 项。';
  }

  @override
  String get portalLocalBackdropRemove => '移除背景';

  @override
  String get portalLocalBackdropEnable => '启用背景';

  @override
  String get portalLocalBackdropEnableHint => '用于 Portal 和音乐空间；内置壁纸离线仍可用。';

  @override
  String get portalLocalBackdropSeparateDevices => '分别设置桌面与移动端';

  @override
  String get portalLocalBackdropSeparateDevicesHint =>
      '关闭时共用同一选择，开启后分别保留两端的壁纸。';

  @override
  String get portalLocalBackdropCurrentDesktop => '当前正在设置桌面端壁纸';

  @override
  String get portalLocalBackdropCurrentMobile => '当前正在设置移动端壁纸';

  @override
  String get portalLocalBackdropFit => '显示方式';

  @override
  String get portalLocalBackdropFitCover => '填充';

  @override
  String get portalLocalBackdropFitContain => '完整显示';

  @override
  String get portalLocalBackdropFitFill => '拉伸铺满';

  @override
  String get portalLocalBackdropAlignment => '裁切对齐';

  @override
  String get portalLocalBackdropAlignTop => '顶部';

  @override
  String get portalLocalBackdropAlignCenter => '居中';

  @override
  String get portalLocalBackdropAlignBottom => '底部';

  @override
  String get portalLocalBackdropClearVideoCache => '清除视频缓存';

  @override
  String get portalLocalBackdropFilterAll => '全部';

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
  String get portalLocalBackdropDim => '暗化';

  @override
  String get portalLocalBackdropBlur => '模糊';

  @override
  String get portalLocalBackdropVideoMuted => '视频静音';

  @override
  String get portalLocalBackdropRetryPlayback => '重试播放';

  @override
  String get portalLocalBackdropLocalOnly =>
      '背景路径只保存在当前设备的 SQLite 中。动态背景建议使用短循环和常见编码；系统会在页面隐藏或进入后台时暂停播放。Web 使用默认主题背景。';

  @override
  String get adminOpenMenu => '打开管理菜单';

  @override
  String get adminStorageOverview => '存储概览';

  @override
  String adminPercentUsed(Object percent) {
    return '$percent% 已使用';
  }

  @override
  String get adminTopBarPortal => 'Portal';

  @override
  String get adminShellTitle => 'OmniNest 管理台';

  @override
  String get adminShellSubtitle => '集中管控中枢';

  @override
  String get adminRolePillLabel => '管理';

  @override
  String get adminRoleSuperAdmin => '超级管理员';

  @override
  String get adminRoleAdmin => '管理员';

  @override
  String get adminRoleMember => '成员';

  @override
  String get adminRoleGuest => '访客';

  @override
  String get adminUserStatusActive => '启用';

  @override
  String get adminUserStatusDisabled => '禁用';

  @override
  String adminStorageUsed(Object size) {
    return '已用 $size';
  }

  @override
  String adminStorageFileCount(Object count) {
    return '$count 个文件';
  }

  @override
  String adminOverviewTasksTotal(Object count) {
    return '$count 个任务';
  }

  @override
  String adminAnalyticsDays(Object days) {
    return '$days 天';
  }

  @override
  String get adminAnalyticsLive => '实时';

  @override
  String adminTaskThroughputTooltip(Object completed, Object failed) {
    return '$completed 完成 · $failed 失败';
  }

  @override
  String get adminLoadCpu => 'CPU';

  @override
  String get adminLoadMemory => '内存';

  @override
  String get adminLoadDisk => '磁盘';

  @override
  String get adminLoadJvm => 'JVM';

  @override
  String adminMonitoringStepMinutes(Object minutes) {
    return '$minutes 分钟粒度';
  }

  @override
  String get adminSystemMonitoring => '系统监控';

  @override
  String get adminMonitoringSubtitle => '查看服务状态、资源使用率、组件健康、告警和管理员操作记录。';

  @override
  String get adminRunning => '运行正常';

  @override
  String adminAttentionItems(Object count) {
    return '$count 个关注项';
  }

  @override
  String get adminServiceStatus => '服务状态';

  @override
  String adminUptime(Object uptime) {
    return '运行时长 $uptime';
  }

  @override
  String get adminComponents => '组件';

  @override
  String get adminAlerts => '告警';

  @override
  String get adminSystemCpu => '系统 CPU';

  @override
  String get adminMemory => '内存';

  @override
  String get adminDiskUsage => '磁盘使用率';

  @override
  String get adminDataDirectoryDisk => '数据目录所在磁盘';

  @override
  String get adminRequests => '请求';

  @override
  String get adminComponentHealth => '组件健康状态';

  @override
  String get adminComponentHealthSubtitle =>
      '数据库、Redis、RabbitMQ、MinIO 和索引组件的当前快照。';

  @override
  String get adminNoComponentHealth => '当前没有组件健康数据。';

  @override
  String get adminRecentAlerts => '最近系统告警';

  @override
  String get adminRecentAlertsSubtitle => '按快照规则生成，后续可接入真实告警表。';

  @override
  String get adminNoAlerts => '当前没有系统告警。';

  @override
  String get adminRecentOperations => '最近操作记录';

  @override
  String get adminRecentOperationsSubtitle => '来自审计日志，便于排查配置和管理动作。';

  @override
  String get adminNoOperations => '当前没有管理员操作记录。';

  @override
  String get adminTrendCharts => '实时趋势图';

  @override
  String get adminTrendChartsSubtitle => '当前阶段展示过去 55 分钟的采样趋势，后续可替换为真实时序存储。';

  @override
  String get adminNoTrendData => '当前没有趋势数据。';

  @override
  String get adminAnalyticsDataHint => '系统运行后将自动采集数据。';

  @override
  String get adminRealtime => '实时';

  @override
  String get adminLogCenter => '日志中心';

  @override
  String get adminLogCenterSubtitle => '统一查看操作审计和登录日志。';

  @override
  String adminAuditCount(Object count) {
    return '$count 条审计';
  }

  @override
  String get adminTabAudit => '操作审计';

  @override
  String get adminTabLoginLog => '登录日志';

  @override
  String get adminRecentAudit => '最近审计';

  @override
  String get adminRecentAuditSubtitle => '来自 audit_logs，按创建时间倒序展示。';

  @override
  String get adminNoAuditLogs => '当前没有审计日志。';

  @override
  String get adminNoLoginLogs => '当前没有登录日志。';

  @override
  String adminLoadFailed(Object error) {
    return '加载失败: $error';
  }

  @override
  String get adminLoginLog => '登录日志';

  @override
  String get adminLoginLogSubtitle => '来自 auth_login_audit，记录所有登录尝试。';

  @override
  String get adminLoginSuccess => '成功';

  @override
  String get adminLoginFailed => '失败';

  @override
  String get adminFilterAction => '操作类型';

  @override
  String get adminFilterStatus => '状态';

  @override
  String get adminFilterPlatform => '平台';

  @override
  String get adminCleanup => '清理';

  @override
  String adminRetentionDays(Object days) {
    return '保留 $days 天';
  }

  @override
  String get adminCleanupConfirmTitle => '确认清理记录';

  @override
  String get adminCleanupConfirmMessage => '将删除保留期之外的记录。此操作不可撤销。';

  @override
  String adminCleanupCompleted(Object count) {
    return '已清理 $count 条记录';
  }

  @override
  String get adminBackgroundTasks => '后台任务';

  @override
  String get adminBackgroundTasksSubtitle => '跟踪索引、转码、同步、备份和清理任务。';

  @override
  String get adminTotalTasks => '任务总数';

  @override
  String get adminRecentTasks => '最近任务';

  @override
  String get adminRunningTasks => '运行中';

  @override
  String get adminExecuting => '正在执行';

  @override
  String get adminFailedTasks => '失败';

  @override
  String get adminRetryable => '可重试';

  @override
  String get adminTaskList => '任务列表';

  @override
  String get adminTaskStatusRunning => '运行中';

  @override
  String get adminTaskStatusCompleted => '成功';

  @override
  String get adminTaskStatusDlq => '死信';

  @override
  String get adminTaskErrorSummary => '错误摘要';

  @override
  String get adminTaskUpdatedAt => '更新时间';

  @override
  String get adminTaskName => '任务名称';

  @override
  String get adminTaskExecutionStatus => '执行状态';

  @override
  String get adminTaskListSubtitle => '失败、取消、死信状态支持重新入队。';

  @override
  String get adminNoBackgroundTasks => '当前没有后台任务。';

  @override
  String get adminNotSet => '未设置';

  @override
  String get adminProgress => '进度';

  @override
  String get adminRetry => '重试';

  @override
  String get adminRoleManagement => '角色管理';

  @override
  String get adminRoleManagementSubtitle => '维护角色、权限集合和资源访问边界。';

  @override
  String adminPermissionCount(Object count) {
    return '$count 个权限';
  }

  @override
  String get adminRoles => '角色';

  @override
  String get adminSystemRoles => '系统角色';

  @override
  String get adminPermissionBindings => '权限绑定';

  @override
  String get adminRolePermissions => '角色权限项';

  @override
  String get adminPermissionModules => '权限模块';

  @override
  String get adminBusinessDomains => '业务域';

  @override
  String get adminRolePermissionsTitle => '角色权限';

  @override
  String get adminRolePermissionsSubtitle => '内置角色不允许删除，SUPER_ADMIN 权限由系统维护。';

  @override
  String get adminNoRoles => '当前没有角色数据。';

  @override
  String adminPermissionCountInline(Object count) {
    return '$count 个权限';
  }

  @override
  String get adminConfigurePermissions => '配置权限';

  @override
  String adminConfigureRolePermissions(Object name) {
    return '配置 $name 权限';
  }

  @override
  String get adminSecurityWarning => '安全提示';

  @override
  String get adminSecurityWarningMessage =>
      '请仅授予实际需要的权限，过度授权可能导致越权访问数据或滥用系统功能。';

  @override
  String get adminConfigCenter => '配置中心';

  @override
  String get adminConfigCenterSubtitle => '管理业务策略与外部服务集成。';

  @override
  String get adminConfigRefresh => '刷新配置';

  @override
  String adminConfigGroupItemCount(int count) {
    return '$count 项设置';
  }

  @override
  String get adminConfigGroupMedia => '媒体导入';

  @override
  String get adminConfigGroupReader => '阅读';

  @override
  String get adminConfigGroupMusic => '音乐';

  @override
  String get adminConfigGroupPhotos => '照片与备份';

  @override
  String get adminConfigGroupStorage => '存储与共享空间';

  @override
  String get adminConfigGroupUpload => '上传';

  @override
  String get adminConfigGroupSecurity => '安全';

  @override
  String get adminConfigGroupWeather => '天气服务';

  @override
  String get adminConfigGroupOther => '其他设置';

  @override
  String get adminConfigProviderPhotoAi => '图像分析';

  @override
  String get adminConfigProviderMusicBrainz => 'MusicBrainz';

  @override
  String get adminConfigProviderTmdb => 'TMDB';

  @override
  String get adminConfigProviderGoogleBooks => 'Google Books';

  @override
  String get adminConfigProviderOpenLibrary => 'Open Library';

  @override
  String get adminConfigProviderNetease => '网易云音乐';

  @override
  String get adminConfigProviderQqMusic => 'QQ 音乐';

  @override
  String get adminConfigProviderQWeather => '和风天气';

  @override
  String get adminConfigManage => '管理设置';

  @override
  String get adminConfigSecretConfigured => '敏感凭据已配置，原值不会回显';

  @override
  String get adminConfigNeedsSetup => '尚未配置';

  @override
  String adminConfigCurrentValue(Object value) {
    return '当前值：$value';
  }

  @override
  String get adminConfigClearCredential => '清除凭据';

  @override
  String get adminConfigClearCredentialConfirm => '清除后相关集成功能将无法使用，确定继续吗？';

  @override
  String get adminConfigCredentialClearedReason => '管理员清除集成凭据';

  @override
  String get adminConfigMediaAutoImport => '自动导入已发现的媒体';

  @override
  String get adminConfigPhotoBackup => '照片自动备份';

  @override
  String get adminConfigDefaultQuota => '新用户默认配额';

  @override
  String get adminConfigQuotaWarning => '配额预警阈值';

  @override
  String get adminConfigSharedSpace => '共享空间';

  @override
  String get adminConfigSharedSpaceLimit => '共享空间容量上限';

  @override
  String get adminConfigLocalMedia => '本地只读媒体';

  @override
  String get adminConfigWeather => '天气功能';

  @override
  String get adminConfigMusicBrainzEnabled => '启用 MusicBrainz';

  @override
  String get adminConfigTmdbEnabled => '启用 TMDB';

  @override
  String get adminConfigTmdbApiKey => 'TMDB API Key';

  @override
  String get adminConfigTmdbAccessToken => 'TMDB Access Token';

  @override
  String get adminConfigTmdbLanguage => '元数据语言';

  @override
  String get adminConfigTmdbAdult => '包含成人内容';

  @override
  String get adminConfigPhotoAiEnabled => '启用图像分析';

  @override
  String get adminConfigNeteaseEnabled => '启用网易云音乐';

  @override
  String get adminConfigQqEnabled => '启用 QQ 音乐';

  @override
  String get adminConfigQWeatherProjectId => '项目 ID';

  @override
  String get adminConfigQWeatherCredentialId => '凭据 ID';

  @override
  String get adminConfigQWeatherPrivateKey => 'Ed25519 私钥';

  @override
  String get adminConfigTmdbTimeout => 'TMDB 请求超时';

  @override
  String get adminConfigTmdbStrategy => 'TMDB 搜索策略';

  @override
  String get adminConfigTmdbLimit => 'TMDB 结果上限';

  @override
  String get adminConfigMediaTranscode => '启用媒体转码';

  @override
  String get adminConfigReaderGoogleBooksEnabled => '启用 Google Books';

  @override
  String get adminConfigReaderGoogleBooksUrl => 'Google Books 服务地址';

  @override
  String get adminConfigReaderGoogleBooksLanguage => 'Google Books 语言';

  @override
  String get adminConfigReaderGoogleBooksLimit => 'Google Books 结果上限';

  @override
  String get adminConfigReaderGoogleBooksTimeout => 'Google Books 请求超时';

  @override
  String get adminConfigReaderGoogleBooksApiKey => 'Google Books API Key';

  @override
  String get adminConfigReaderOpenLibraryEnabled => '启用 Open Library';

  @override
  String get adminConfigReaderOpenLibraryUrl => 'Open Library 服务地址';

  @override
  String get adminConfigReaderOpenLibraryLanguage => 'Open Library 语言';

  @override
  String get adminConfigReaderAutoImport => '启用阅读自动导入';

  @override
  String get adminConfigMusicBrainzBaseUrl => 'MusicBrainz 服务地址';

  @override
  String get adminConfigMusicAutoImport => '启用音乐自动导入';

  @override
  String get adminConfigMusicBrainzUserAgent => 'MusicBrainz User-Agent';

  @override
  String get adminConfigMusicBrainzCoverUrl => 'MusicBrainz 封面服务地址';

  @override
  String get adminConfigMusicOnlineEnabled => '启用在线音乐';

  @override
  String get adminConfigTmdbBaseUrl => 'TMDB 服务地址';

  @override
  String get adminConfigPhotoAiEndpoint => '图像分析服务地址';

  @override
  String get adminConfigNeteaseBaseUrl => '网易云音乐服务地址';

  @override
  String get adminConfigNeteaseHosts => '网易云播放域名';

  @override
  String get adminConfigQqUUrl => 'QQ 音乐 U 接口地址';

  @override
  String get adminConfigQqCUrl => 'QQ 音乐 C 接口地址';

  @override
  String get adminConfigQqHosts => 'QQ 音乐播放域名';

  @override
  String get adminConfigQWeatherBaseUrl => '和风天气服务地址';

  @override
  String get adminConfigWeatherLocation => '天气位置';

  @override
  String get adminConfigPhotoAiTimeout => '图像分析请求超时';

  @override
  String get adminConfigPhotoGeoRate => '照片地理编码速率';

  @override
  String get adminConfigUploadRateEnabled => '启用上传限速';

  @override
  String get adminConfigSecurityRateLimit => '默认安全限流';

  @override
  String get adminConfigClamavEnabled => '启用 ClamAV';

  @override
  String get adminConfigClamavHost => 'ClamAV 主机';

  @override
  String get adminConfigClamavPort => 'ClamAV 端口';

  @override
  String get adminConfigUnlimited => '无限制';

  @override
  String get adminConfigUnlimitedDescription => '设为无限制后不执行该项容量上限校验。';

  @override
  String get adminConfigQuotaUnlimitedDescription =>
      '支持直接输入容量；将滑块拖到最右侧或开启无限制即可取消上限。';

  @override
  String get adminConfigQuotaSliderUnlimited => '最右侧：无限制';

  @override
  String get adminConfigQuotaSliderMinimum => '1 GB';

  @override
  String get adminConfigQuotaInvalid => '请输入大于 0 GB 的配额，或明确开启无限制。';

  @override
  String get adminConfigQuotaWholeGb => '新用户默认配额必须填写整数 GB。';

  @override
  String get adminConfigEndpointDescription => '服务端请求使用的基础地址，可按部署环境调整。';

  @override
  String get adminConfigWeatherLocationDescription => '用于天气查询的城市、坐标或服务支持的位置编码。';

  @override
  String get adminConfigUnknownItem => '未知配置项';

  @override
  String get adminConfigLogRetentionEnabled => '日志保留清理';

  @override
  String get adminConfigLogRetentionDays => '日志保留天数';

  @override
  String get adminConfigLogRetentionPaths => '日志清理扫描目录';

  @override
  String get adminConfigMediaAutoImportDescription => '启用后可按媒体模块规则自动接收已发现的影片。';

  @override
  String get adminConfigPhotoBackupDescription => '控制新照片是否进入自动备份流程。';

  @override
  String get adminConfigDefaultQuotaDescription => '创建新用户时采用的默认存储容量，单位为 GB。';

  @override
  String get adminConfigQuotaWarningDescription => '达到该使用比例时向用户显示容量预警。';

  @override
  String get adminConfigSharedSpaceDescription => '控制所有用户是否可以使用共享空间。';

  @override
  String get adminConfigSharedSpaceLimitDescription => '限制共享空间可使用的总容量。';

  @override
  String get adminConfigLocalMediaDescription => '只能关闭部署层已授权的本地媒体能力，不能扩大挂载范围。';

  @override
  String get adminConfigWeatherDescription => '控制客户端是否可以请求天气数据。';

  @override
  String get adminConfigProviderToggleDescription => '控制是否允许使用此集成服务。';

  @override
  String get adminConfigCredentialDescription => '用于服务端认证；保存后不会再次回显。';

  @override
  String get adminConfigProviderIdentifierDescription => '由外部服务控制台提供的项目或凭据标识。';

  @override
  String get adminConfigTmdbLanguageDescription => 'TMDB 返回标题、简介和图片信息时优先使用的语言。';

  @override
  String get adminConfigTmdbAdultDescription => '启用后搜索结果可能包含成人内容。';

  @override
  String get adminConfigInternalNumericDescription => '该服务使用的内部请求或结果边界。';

  @override
  String get adminConfigTmdbStrategyDescription => '控制 TMDB 匹配时使用的标准化及回退查询。';

  @override
  String get adminConfigMediaTranscodeDescription => '允许媒体流程生成播放派生文件。';

  @override
  String get adminConfigReaderAutoImportDescription => '允许识别出的阅读文件自动进入导入流程。';

  @override
  String get adminConfigMusicAutoImportDescription => '允许识别出的音乐文件自动进入导入流程。';

  @override
  String get adminConfigPhotoGeoRateDescription => '每秒允许发起的地理编码请求上限。';

  @override
  String get adminConfigUploadRateDescription => '控制上传流量是否受服务器限速策略约束。';

  @override
  String get adminConfigSecurityRateLimitDescription => '安全控制默认应用的请求限流上限。';

  @override
  String get adminConfigMusicBrainzUserAgentDescription =>
      '随 MusicBrainz 请求发送的客户端标识。';

  @override
  String get adminConfigHostSuffixesDescription => '以逗号分隔的服务媒体请求允许域名后缀。';

  @override
  String get adminConfigItems => '配置项';

  @override
  String get adminAllConfigs => '全部配置';

  @override
  String get adminHotUpdate => '热更新';

  @override
  String get adminEffectiveImmediately => '立即生效';

  @override
  String get adminRestartRequired => '需重启';

  @override
  String get adminEffectiveAfterRestart => '重启后生效';

  @override
  String get adminConfigItemList => '配置项';

  @override
  String get adminConfigItemListSubtitle => '配置按热更新、下次任务或重启范围生效。';

  @override
  String get adminNoConfigItems => '当前没有配置项。';

  @override
  String get adminAllCategories => '全部分类';

  @override
  String get adminAllScopes => '全部范围';

  @override
  String get adminHotReload => '热更新';

  @override
  String get adminNextTask => '下次任务';

  @override
  String get adminNeedsRestart => '需重启';

  @override
  String get adminEdit => '编辑';

  @override
  String get adminConfigValue => '配置值';

  @override
  String get adminSensitiveValuePlaceholder => '请输入新的敏感配置值，原值不会回显';

  @override
  String get adminChangeReason => '变更原因';

  @override
  String get adminTrue => '是';

  @override
  String get adminFalse => '否';

  @override
  String get adminConfigHistory => '变更历史';

  @override
  String get adminNoConfigHistory => '暂无变更记录';

  @override
  String get adminRollback => '回滚';

  @override
  String get adminNoReason => '无备注';

  @override
  String get adminDlq => '死信队列';

  @override
  String get adminDlqSubtitle => '重试耗尽的失败任务，可手动重新入队';

  @override
  String get adminNoDlqTasks => '暂无死信任务';

  @override
  String get adminNoErrorSummary => '无错误摘要';

  @override
  String get adminStorageManagement => '存储管理';

  @override
  String get adminListEmpty => '暂无数据，可调整筛选条件';

  @override
  String get adminListRowsPerPage => '每页条数';

  @override
  String adminListPageOf(Object current, Object total) {
    return '第 $current/$total 页';
  }

  @override
  String get adminListPrevPage => '上一页';

  @override
  String get adminListNextPage => '下一页';

  @override
  String get adminListActions => '操作';

  @override
  String get adminListIndex => '序号';

  @override
  String adminListSelectedCount(Object count) {
    return '已选 $count 项';
  }

  @override
  String get adminListSelectAll => '全选';

  @override
  String get adminListExpandFilters => '展开筛选';

  @override
  String get adminListCollapseFilters => '收起筛选';

  @override
  String get adminListSortAsc => '升序';

  @override
  String get adminListSortDesc => '降序';

  @override
  String get adminListExportCsv => '导出 CSV';

  @override
  String get adminLibrarySourcesSection => '视频库源';

  @override
  String get statusHealthHealthy => '健康';

  @override
  String get statusHealthAvailable => '可用';

  @override
  String get statusHealthUnavailable => '不可达';

  @override
  String get statusScopePersonal => '个人空间';

  @override
  String get statusScopeShared => '共享空间';

  @override
  String get statusProviderLocalFilesystem => '本机文件系统';

  @override
  String get statusProviderMinio => '对象存储';

  @override
  String get statusManagementManaged => '托管';

  @override
  String get statusScanReady => '就绪';

  @override
  String get statusScanDiscovering => '发现中';

  @override
  String get statusScanApplying => '应用中';

  @override
  String get statusScanFailed => '失败';

  @override
  String get statusScanCancelled => '已取消';

  @override
  String get statusScanPaused => '已暂停';

  @override
  String get statusScanPartial => '部分完成';

  @override
  String get statusScanQueued => '排队中';

  @override
  String get statusPhaseDiscovery => '发现阶段';

  @override
  String get statusPhaseReview => '审阅阶段';

  @override
  String get statusPhaseApply => '应用阶段';

  @override
  String get adminLibrarySourceAdd => '新建库源';

  @override
  String get adminLibrarySourcesEmpty => '尚无库源，点击\"新建库源\"在已启用的存储位置上建立';

  @override
  String get adminLibrarySourcesSubtitle => '在已启用的存储位置上建立电影、剧集与动漫库源。';

  @override
  String get adminLibraryReviewSubtitle => '选择库源后审阅扫描结果并应用入库。';

  @override
  String get adminStorageStatusHealthy => '健康';

  @override
  String get adminStorageFilterAll => '全部';

  @override
  String get adminStorageFilterEnabled => '已启用';

  @override
  String get adminStorageFilterDisabled => '已停用';

  @override
  String get adminStorageFilterUnhealthy => '异常';

  @override
  String get adminStorageEmptyList => '没有符合条件的存储位置';

  @override
  String get adminStorageDetailHint => '选择左侧存储位置查看详情';

  @override
  String get adminStorageStatusDisabled => '已停用';

  @override
  String get adminStorageDisableConfirmTitle => '停用存储位置';

  @override
  String adminStorageDisableConfirmBody(Object name) {
    return '停用后\"$name\"将不再参与扫描与媒体读取，可随时重新启用。';
  }

  @override
  String get adminStorageDisableAction => '停用';

  @override
  String get adminStorageEnableAction => '启用';

  @override
  String get adminStorageDeleteConfirmTitle => '删除存储位置';

  @override
  String adminStorageDeleteConfirmBody(Object name) {
    return '将永久移除\"$name\"的登记信息，已入库内容不受影响。';
  }

  @override
  String get adminStorageDeleteAction => '删除';

  @override
  String get adminStorageFieldPath => '路径';

  @override
  String get adminStorageFieldScope => '空间';

  @override
  String get adminStorageFieldProvider => '提供方';

  @override
  String get adminStorageFieldManagement => '管理模式';

  @override
  String get adminStorageFieldNode => '节点';

  @override
  String get adminStorageParentDir => '上一级';

  @override
  String get adminStorageManagementSubtitle =>
      '管理 MinIO 桶与本地媒体位置；4K 等重片源使用本地位置直连播放。';

  @override
  String get adminBucketConfig => '桶配置';

  @override
  String get adminMinioBuckets => 'MinIO Buckets';

  @override
  String get adminRecentRecords => '最近记录';

  @override
  String get adminWaitingToExecute => '等待执行';

  @override
  String get adminObjectBuckets => '对象桶';

  @override
  String get adminObjectBucketsSubtitle => '来自后端 MinIO 配置。';

  @override
  String get adminNoBucketConfig => '当前没有桶配置。';

  @override
  String get adminExternalStorageIntegration => '外部存储集成';

  @override
  String get adminExternalStorageSubtitle =>
      '治理远程来源连接状态；连接创建与导入请在文件模块的远程导入中操作。';

  @override
  String get adminOAuthAppsTitle => 'OAuth 应用';

  @override
  String get adminOAuthAppsSubtitle =>
      '为 OneDrive / Google 等连接器配置实例级 OAuth 应用（BYOA）。';

  @override
  String get adminNoOAuthApps => '尚未配置 OAuth 应用。';

  @override
  String get adminNewConnection => '新增连接';

  @override
  String get adminNewExternalStorage => '新增外部存储';

  @override
  String get adminType => '类型';

  @override
  String get adminExternalStorageClientId => '客户端 ID';

  @override
  String get adminExternalStorageClientSecret => '客户端密钥';

  @override
  String get adminExternalStorageRedirectUri => '重定向 URI';

  @override
  String get adminLocalMount => '本地(rclone) 账号';

  @override
  String get adminDisplayNameLabel => '展示名称';

  @override
  String get adminCredentialsJson => '凭据 JSON';

  @override
  String get adminEnterDisplayName => '请输入展示名称';

  @override
  String get adminCreatingLabel => '创建中';

  @override
  String get adminConnections => '连接';

  @override
  String get adminExternalSources => '外部源';

  @override
  String get adminEnabled => '启用';

  @override
  String get adminSyncable => '可同步';

  @override
  String get adminDisabled => '停用';

  @override
  String get adminPausedSync => '暂停同步';

  @override
  String get adminConnectionList => '连接列表';

  @override
  String get adminConnectionListSubtitle => '凭据由后端托管，前端只展示连接元数据。';

  @override
  String get adminNoExternalStorage => '当前没有外部存储连接。';

  @override
  String get adminDeactivate => '停用';

  @override
  String get adminActivate => '启用';

  @override
  String get adminSessionManagement => '会话管理';

  @override
  String get adminSessionStatusActive => '有效';

  @override
  String get adminSessionStatusRevoked => '已强制下线';

  @override
  String get adminSessionStatusExpired => '已过期';

  @override
  String get adminSessionDetailTitle => '会话详情';

  @override
  String get adminSessionFieldDeviceId => '设备 ID';

  @override
  String get adminSessionDeviceName => '设备名称';

  @override
  String get adminSessionLoginTime => '登录时间';

  @override
  String get adminSessionExpiresAt => '过期时间';

  @override
  String get adminSessionLastActive => '最后活跃时间';

  @override
  String get adminSessionIp => 'IP 地址';

  @override
  String get adminResourceType => '资源类型';

  @override
  String get adminLogContent => '操作内容';

  @override
  String get adminLogTime => '时间';

  @override
  String get adminConfigDescription => '说明';

  @override
  String get adminStorageOpenDetail => '详情';

  @override
  String get adminStorageColumnType => '类型';

  @override
  String get adminStorageMountsSection => '本地挂载位置';

  @override
  String get adminTrustedMountsTitle => '可信挂载点';

  @override
  String get adminTrustedMountsSubtitle =>
      '部署配置登记的挂载键及其在当前节点的可用状态，是挂载位置与挂载直达创建的来源。';

  @override
  String get adminTrustedMountsEmpty => '未在部署配置中登记挂载';

  @override
  String adminLibraryOrphanLocation(Object count) {
    return '有 $count 个挂载位置已无库源引用，可在上方列表中清理';
  }

  @override
  String get adminLibraryCleanupOrphan => '清理挂载位置';

  @override
  String get adminLibraryColumnName => '库名称';

  @override
  String get adminLibraryColumnLocation => '存储位置 · 根目录';

  @override
  String get adminLibraryColumnScanStatus => '扫描状态';

  @override
  String get adminLibraryColumnLastScan => '上次扫描';

  @override
  String get adminLibraryManageInfoSection => '库源信息';

  @override
  String get adminLibraryManageReviewSection => '发现与审阅';

  @override
  String adminLibraryLastScanSummary(
    Object found,
    Object created,
    Object missing,
  ) {
    return '发现 $found · 入库 $created · 缺失 $missing';
  }

  @override
  String get adminLibraryScanNever => '未扫描';

  @override
  String get adminLibraryDeleteSourceTitle => '删除库源';

  @override
  String adminLibraryDeleteSourceBody(Object name) {
    return '确定删除库源「$name」吗？该操作不可撤销。';
  }

  @override
  String get adminLibraryAccessTitle => '访问管理';

  @override
  String get adminStorageColumnName => '名称';

  @override
  String get adminStorageColumnMountKey => '挂载键';

  @override
  String get adminStorageColumnRoot => '根目录';

  @override
  String get adminStorageColumnHealth => '健康状态';

  @override
  String get adminLibraryDiscoverUpdates => '发现更新';

  @override
  String adminListTotalCount(Object count) {
    return '共 $count 条';
  }

  @override
  String adminListRange(Object start, Object end) {
    return '第 $start-$end 条';
  }

  @override
  String get adminListFirstPage => '首页';

  @override
  String get adminListLastPage => '末页';

  @override
  String get adminListJumpTo => '跳至';

  @override
  String get adminListPageUnit => '页';

  @override
  String get adminConfigGroupColumn => '分组';

  @override
  String get adminBatchRevokeSessions => '批量强制下线';

  @override
  String get adminBatchRetryTasks => '批量重试';

  @override
  String get adminBatchClearSelection => '取消选择';

  @override
  String adminBatchCompleted(Object success, Object failed) {
    return '批量操作完成：成功 $success 项，失败 $failed 项';
  }

  @override
  String get adminBatchConfirmTitle => '确认批量操作';

  @override
  String adminBatchConfirmMessage(Object count) {
    return '将对选中的 $count 项逐条执行该操作，失败项会跳过。';
  }

  @override
  String get adminCsvExported => '已导出当前页';

  @override
  String get adminLoginFailureReason => '失败原因';

  @override
  String get adminSessionRevokeReason => '强制下线原因';

  @override
  String get adminSessionManagementSubtitle => '查看所有用户活跃会话，支持强制踢出。';

  @override
  String get adminActiveSessions => '活跃';

  @override
  String get adminRevokedSessions => '已撤销';

  @override
  String get adminActiveSessionCount => '活跃会话';

  @override
  String get adminCurrentOnlineDevices => '当前在线设备';

  @override
  String get adminRevokedCount => '已撤销';

  @override
  String get adminBeenKicked => '已被踢出';

  @override
  String get adminSessionList => '会话列表';

  @override
  String get adminSessionListSubtitle => '按创建时间倒序展示。';

  @override
  String get adminNoSessions => '暂无会话记录。';

  @override
  String get adminConfirmKick => '确认踢出';

  @override
  String adminConfirmKickMessage(Object device) {
    return '确定要撤销该会话吗？设备: $device';
  }

  @override
  String get adminRevokeSession => '踢出会话';

  @override
  String get adminRevokedLabel => '已撤销';

  @override
  String get adminSessionAllStatuses => '全部状态';

  @override
  String get adminSessionActiveOnly => '仅活跃';

  @override
  String get adminSessionRevokedOnly => '仅已撤销';

  @override
  String get adminSessionExpiredOnly => '仅过期';

  @override
  String get adminExpiredLabel => '已过期';

  @override
  String get adminCurrentPage => '当前页';

  @override
  String get adminFilterTaskType => '任务类型';

  @override
  String adminPageIndicator(Object page, Object totalPages) {
    return '第 $page / $totalPages 页';
  }

  @override
  String adminTotalCount(Object count) {
    return '共 $count 条';
  }

  @override
  String get adminPreviousPage => '上一页';

  @override
  String get adminNextPage => '下一页';

  @override
  String get adminUserManagement => '用户管理';

  @override
  String get adminUserManagementSubtitle => '管理账号、状态、配额和角色分配。';

  @override
  String get adminAccountList => '账号列表';

  @override
  String get adminAccountListSubtitle => '按用户名、昵称、邮箱和角色筛选账号。';

  @override
  String get adminCreateUser => '创建用户';

  @override
  String get adminSearchUsers => '搜索用户名、昵称或邮箱';

  @override
  String get adminAll => '全部';

  @override
  String get adminNoMatchingUsers => '当前没有匹配用户。';

  @override
  String adminLoadMore(Object loaded, Object total) {
    return '加载更多（已加载 $loaded / $total）';
  }

  @override
  String get adminTotalUsers => '用户总数';

  @override
  String get adminDatabaseAccounts => '数据库账号';

  @override
  String get adminSuperAdmin => '超级管理员';

  @override
  String get adminHighestPrivilege => '最高权限';

  @override
  String get adminSystemMaintenance => '系统维护';

  @override
  String get adminMemberGuest => '成员 / 访客';

  @override
  String get adminBusinessAccess => '业务访问';

  @override
  String get adminNotSetEmail => '未设置邮箱';

  @override
  String get adminDisable => '禁用';

  @override
  String get adminRole => '角色';

  @override
  String get adminQuota => '配额';

  @override
  String get adminUnlimited => '无限制';

  @override
  String get adminBatchQuota => '批量设置配额';

  @override
  String get adminDeselect => '取消选择';

  @override
  String adminSelectedUsers(Object count) {
    return '已选择 $count 个用户';
  }

  @override
  String adminBatchSetStorageQuota(Object count) {
    return '批量设置存储配额（$count 个用户）';
  }

  @override
  String get adminBatchQuotaHint => '将为所有选中的用户设置相同的存储配额。超级管理员和空间不足的用户将被跳过。';

  @override
  String get adminQuotaGib => '配额 (GiB)';

  @override
  String get adminQuotaHint => '例如：50';

  @override
  String get adminSaving => '保存中';

  @override
  String get adminSave => '保存';

  @override
  String get adminValidQuotaRequired => '请输入有效的配额值';

  @override
  String get adminNoUsersSelected => '未选择任何用户';

  @override
  String adminUsersQuotaUpdated(Object count) {
    return '已更新 $count 个用户的存储配额';
  }

  @override
  String adminEditQuota(Object name) {
    return '调整 $name 的存储配额';
  }

  @override
  String adminCurrentUsage(Object used, Object quota) {
    return '当前使用：$used / $quota';
  }

  @override
  String get adminNewQuotaGib => '新配额 (GiB)';

  @override
  String adminQuotaMinError(Object used) {
    return '新配额不能小于当前已使用空间（$used GiB）';
  }

  @override
  String adminEditRoles(Object name) {
    return '调整 $name 的角色';
  }

  @override
  String get adminSelectAtLeastOneRole => '请至少选择一个角色';

  @override
  String get adminCreating => '创建中';

  @override
  String get adminCreate => '创建';

  @override
  String get adminUsername => '用户名';

  @override
  String get adminEnterUsername => '请输入用户名';

  @override
  String get adminDisplayName => '展示名称';

  @override
  String get adminEmail => '邮箱';

  @override
  String get adminInitialPassword => '初始密码';

  @override
  String get adminEnterInitialPassword => '请输入初始密码';

  @override
  String get adminPasswordMinChars => '密码至少 8 个字符';

  @override
  String get adminPasswordMaxChars => '密码不能超过 24 个字符';

  @override
  String get adminRoleLabel => '角色';

  @override
  String get adminConsole => '管理控制台';

  @override
  String get adminConsoleSubtitle => '汇总用户、权限、运行状态和存储能力的关键指标。';

  @override
  String get adminAccountOverview => '账号概况';

  @override
  String get adminActive => '活跃';

  @override
  String get adminPermissionModel => '权限模型';

  @override
  String adminPermissionBindingsCount(Object count) {
    return '$count 个权限绑定';
  }

  @override
  String get adminTasks => '后台任务';

  @override
  String get adminRunningLabel => '运行';

  @override
  String get adminQueued => '排队';

  @override
  String get adminCompleted => '已完成';

  @override
  String get adminNeedAttention => '需处理';

  @override
  String get adminStorageAssets => '存储资产';

  @override
  String adminFilesFolders(Object files, Object folders) {
    return '$files 文件 · $folders 文件夹';
  }

  @override
  String get adminObjects => '对象';

  @override
  String get adminHealthy => '健康';

  @override
  String get adminFiles => '文件';

  @override
  String get adminFolders => '文件夹';

  @override
  String get adminExternalStorageLabel => '外部存储';

  @override
  String get adminWarning => '告警';

  @override
  String get adminActivityChart => '系统活动';

  @override
  String get adminActivityChartSubtitle => '根据当前系统统计生成的管理端趋势视图。';

  @override
  String get adminHealthStatus => '服务状态';

  @override
  String get adminHealthStatusSubtitle => '来自管理端聚合接口的健康状态。';

  @override
  String get adminUserLabel => '用户';

  @override
  String get adminTaskLabel => '任务';

  @override
  String get adminStorageLabel => '存储';

  @override
  String get adminAnalyticsPage => '可视化图表';

  @override
  String get adminAnalyticsPageSubtitle => '集中查看账号增长、容量趋势、任务吞吐和系统负载。';

  @override
  String get adminAccountGrowth => '账号增长';

  @override
  String get adminTaskThroughput => '任务吞吐';

  @override
  String get adminCompletedLabel => '完成';

  @override
  String get adminExceptions => '异常';

  @override
  String get adminStorageOccupancy => '存储占用';

  @override
  String get adminObjectsLabel => '对象';

  @override
  String get adminSystemLoad => '系统负载';

  @override
  String get adminHotConfig => '热配置';

  @override
  String get adminRestartItems => '重启项';

  @override
  String get adminStatusEnabled => '启用';

  @override
  String get adminStatusDisabled => '禁用';

  @override
  String get adminGroupOverview => '总览';

  @override
  String get adminGroupOperations => '运维';

  @override
  String get adminGroupIdentity => '身份与权限';

  @override
  String get adminGroupConfiguration => '系统配置';

  @override
  String get adminGroupStorage => '存储';

  @override
  String get adminNavOverview => '控制台首页';

  @override
  String get adminNavAnalytics => '可视化图表';

  @override
  String get adminNavMonitoring => '系统监控';

  @override
  String get adminNavLogs => '日志中心';

  @override
  String get adminNavTasks => '后台任务';

  @override
  String get adminNavSessions => '会话管理';

  @override
  String get adminNavUsers => '用户管理';

  @override
  String get adminNavRoles => '角色管理';

  @override
  String get adminNavConfig => '配置中心';

  @override
  String get adminNavStorage => '存储管理';

  @override
  String get adminNavExternalStorage => '外部存储';

  @override
  String get adminOverviewTitle => '管理控制台';

  @override
  String get adminOverviewSubtitle => '汇总用户、权限、运行状态和存储能力的关键指标。';

  @override
  String get adminAnalyticsTitle => '可视化图表';

  @override
  String get adminAnalyticsSubtitle => '集中查看账号增长、容量趋势、任务吞吐和系统负载。';

  @override
  String get adminMonitoringTitle => '系统监控';

  @override
  String get adminMonitoringSubtitle2 => '查看健康检查、服务指标、节点状态和告警。';

  @override
  String get adminLogsTitle => '日志中心';

  @override
  String get adminLogsSubtitle => '统一查看应用日志、异常日志和登录审计。';

  @override
  String get adminTasksTitle => '后台任务';

  @override
  String get adminTasksSubtitle => '跟踪索引、转码、同步、备份和清理任务。';

  @override
  String get adminSectionForbidden => '当前账号无权打开该管理分区。';

  @override
  String get adminSessionsTitle => '会话管理';

  @override
  String get adminSessionsSubtitle => '查看和管理用户活跃会话，支持强制踢出。';

  @override
  String get adminUsersTitle => '用户管理';

  @override
  String get adminUsersSubtitle => '管理账号、状态、配额和角色分配。';

  @override
  String get adminRolesTitle => '角色管理';

  @override
  String get adminRolesSubtitle => '维护角色、权限集合和资源访问边界。';

  @override
  String get adminConfigTitle => '配置中心';

  @override
  String get adminConfigSubtitle => '管理系统配置项、功能开关和热更新发布状态。';

  @override
  String get adminStorageTitle => '存储管理';

  @override
  String get adminStorageSubtitle => '管理 MinIO 桶、容量与索引维护。';

  @override
  String get adminExternalStorageTitle => '外部存储集成';

  @override
  String get adminRefresh => '刷新';

  @override
  String get adminRecalculate => '重算用量';

  @override
  String adminRecalculateDone(Object count) {
    return '已更新 $count 位用户的存储用量';
  }

  @override
  String get adminRebuildIndex => '重建索引';

  @override
  String adminRebuildIndexDone(Object count) {
    return '已清除 $count 个索引文档，请等待重新索引';
  }

  @override
  String get adminApiResponseFormat => 'Admin 响应格式不正确';

  @override
  String get adminNoResponse => '服务端没有返回 Admin 结果';

  @override
  String get adminOperationFailed => 'Admin 操作失败';

  @override
  String get adminUserListFormat => '用户列表格式不正确';

  @override
  String get adminUserResponseFormat => '用户响应格式不正确';

  @override
  String get adminNoUserResult => '服务端没有返回用户结果';

  @override
  String get adminUserOperationFailed => '用户操作失败';

  @override
  String get adminConsoleResponseFormat => '管理控制台响应格式不正确';

  @override
  String get adminNoConsoleResult => '服务端没有返回管理控制台结果';

  @override
  String get adminConsoleLoadFailed => '管理控制台加载失败';

  @override
  String get adminNoDetailDiagnostics => '暂无详细诊断信息';

  @override
  String get readerNavBookshelf => '书架';

  @override
  String get readerNavLibrary => '书库';

  @override
  String get readerNavStats => '统计';

  @override
  String get readerNavManage => '管理';

  @override
  String get readerShelfEmpty => '书架为空，请在书库中添加书籍。';

  @override
  String get readerShelfEmptyHint => '去书库挑选喜欢的书加入书架吧。';

  @override
  String get readerStatsActivity => '阅读记录';

  @override
  String get readerStatsTitle => '阅读统计';

  @override
  String get adminHistoryEmpty => '暂无阅读记录。';

  @override
  String get readerStatsLast14 => '最近 14 天';

  @override
  String get readerStatsCompleted => '已完成';

  @override
  String get readerStatsInProgress => '进行中';

  @override
  String get readerStatsInLibrary => '书库';

  @override
  String get readerStatsBooksRead => '已读书籍';

  @override
  String get readerStatsDayUnit => '天';

  @override
  String get readerDetailInfo => '简介';

  @override
  String get readerDetailChapters => '章节';

  @override
  String get readerDetailAnnotations => '批注';

  @override
  String get readerDetailBookmarks => '书签';

  @override
  String get readerDetailProgress => '进度';

  @override
  String get readerDetailComplete => '已读完';

  @override
  String get readerDetailType => '类型';

  @override
  String get readerDetailLanguage => '语言';

  @override
  String get readerDetailAdded => '添加时间';

  @override
  String get readerDetailLastRead => '上次阅读';

  @override
  String get readerDetailWords => '字数';

  @override
  String get readerDetailMinRead => '分钟';

  @override
  String get readerDetailEditMeta => '编辑元数据';

  @override
  String get readerDetailReparse => '重新解析';

  @override
  String get readerDetailNoAnn => '暂无批注。';

  @override
  String get readerDetailNoBm => '暂无书签。';

  @override
  String get readerNavComics => '漫画';

  @override
  String get readerSegmentAll => '全部';

  @override
  String get readerSegmentBooks => '图书';

  @override
  String get readerSegmentComics => '漫画';

  @override
  String get readerNavBookmarks => '书签';

  @override
  String get readerNavFavorites => '收藏';

  @override
  String get readerManageHint => '管理工具仅超级管理员可见';

  @override
  String get readerSearchHint => '搜索书名、作者…';

  @override
  String get readerSearch => '搜索';

  @override
  String get readerThemeLight => '浅色';

  @override
  String get readerThemeEyeCare => '护眼';

  @override
  String get readerThemeDark => '深色';

  @override
  String get readerThemeGreen => '绿色';

  @override
  String get readerSettingsTitle => '阅读设置';

  @override
  String get readerReadingMode => '阅读模式';

  @override
  String get readerModeScroll => '滑动';

  @override
  String get readerModePage => '左右滑动';

  @override
  String get readerFontSize => '字号';

  @override
  String get readerLineHeight => '行高';

  @override
  String get readerFontFamily => '字体';

  @override
  String get readerFontSerif => '宋体';

  @override
  String get readerFontSans => '黑体';

  @override
  String get readerFontSystem => '跟随系统';

  @override
  String get readerTheme => '主题';

  @override
  String get readerImmersiveMode => '沉浸模式';

  @override
  String get readerVolumeKeyPaging => '音量键翻页';

  @override
  String get readerPreviousPage => '上一页';

  @override
  String get readerNextPage => '下一页';

  @override
  String get readerPreviousChapter => '上一章';

  @override
  String get readerReadAloud => '朗读';

  @override
  String get readerShortcutsTitle => '快捷键';

  @override
  String get readerShortcutNavigation => '阅读导航';

  @override
  String get readerShortcutTurnPage => '翻页或移动一个视口';

  @override
  String get readerShortcutContents => '打开或关闭目录';

  @override
  String get readerShortcutBookmark => '添加或取消书签';

  @override
  String get readerShortcutSearch => '搜索当前章节';

  @override
  String get readerShortcutAnnotations => '打开批注与笔记';

  @override
  String get readerShortcutImmersive => '切换沉浸模式';

  @override
  String get readerShortcutFullscreen => '切换全屏';

  @override
  String get readerShortcutTypography => '调整或重置排版';

  @override
  String get readerShortcutClose => '关闭当前面板或返回';

  @override
  String get readerShortcutMode => '切换漫画阅读模式';

  @override
  String get readerSearchCurrentChapter => '搜索当前章节';

  @override
  String get readerNoSearchResults => '没有找到匹配内容';

  @override
  String readerSearchResultCount(int count) {
    return '找到 $count 处';
  }

  @override
  String readerReadingProgress(int percent) {
    return '阅读进度 $percent%';
  }

  @override
  String readerBookChapterPosition(int current, int total, int percent) {
    return '第 $current/$total 章 · $percent%';
  }

  @override
  String get readerResetTypography => '恢复默认排版';

  @override
  String get readerComicModePage => '翻页模式';

  @override
  String get readerComicModeScroll => '卷轴模式';

  @override
  String get readerComicFullWidth => '连续阅读使用全部可用宽度';

  @override
  String get readerComicFullWidthHint => '关闭后限制桌面端页面宽度，避免图片被过度放大';

  @override
  String readerComicContentWidth(int width) {
    return '内容宽度 $width 像素';
  }

  @override
  String readerComicPageGap(int gap) {
    return '页面间距 $gap 像素';
  }

  @override
  String get readerComicImageLoadFailed => '漫画页面加载失败';

  @override
  String get readerComicImageDecodeFailed => '漫画页面解码失败';

  @override
  String get readerStatsToday => '今日';

  @override
  String get readerStatsWeek => '本周';

  @override
  String get readerStatsStreak => '连续';

  @override
  String get readerStatsBooks => '书籍';

  @override
  String readerStatsMinutes(Object count) {
    return '$count分钟';
  }

  @override
  String readerStatsHoursMinutes(Object hours, Object minutes) {
    return '$hours小时$minutes分';
  }

  @override
  String readerStatsHours(Object hours) {
    return '$hours小时';
  }

  @override
  String readerStatsDays(Object count) {
    return '$count天';
  }

  @override
  String get readerNoContent => '暂无内容';

  @override
  String get readerTtsPlay => '播放';

  @override
  String get readerTtsPause => '暂停';

  @override
  String get readerTtsStop => '停止';

  @override
  String get readerAlreadyFirstChapter => '已经是第一章了';

  @override
  String get readerChapterSwitching => '正在切换章节，请稍候';

  @override
  String get readerSyncRemoteProgress => '其他设备已更新进度，点击同步';

  @override
  String get readerAlreadyLastChapter => '已经是最后一章了';

  @override
  String get readerRestoringProgress => '正在恢复阅读位置…';

  @override
  String get readerReturnToProgress => '回到上次阅读位置';

  @override
  String get readerReturn => '返回';

  @override
  String get readerBookmarkRemoved => '书签已取消';

  @override
  String get readerBookmarkAdded => '书签已添加';

  @override
  String get readerBookmarkFailed => '书签操作失败';

  @override
  String get readerHighlightAdded => '高亮已添加';

  @override
  String get readerAddAnnotation => '添加批注';

  @override
  String get readerAnnotationHint => '输入你的笔记...';

  @override
  String get readerAddBookmark => '添加书签';

  @override
  String get readerRemoveBookmark => '取消书签';

  @override
  String get readerChapterList => '章节列表';

  @override
  String get readerOperationFailed => '操作失败，请稍后重试';

  @override
  String get readerOperationSubmitted => '操作已提交';

  @override
  String get readerChapterLoadFailed => '章节内容加载失败，请重试';

  @override
  String get readerRemoveFavorite => '取消收藏';

  @override
  String get readerAddFavorite => '加入收藏';

  @override
  String get readerReadComic => '阅读漫画';

  @override
  String get readerNoPages => '暂无页面';

  @override
  String get readerContinueReading => '继续阅读';

  @override
  String get readerNavNotes => '笔记';

  @override
  String get readerStartReading => '开始阅读';

  @override
  String get readerAddedToBookshelf => '已加入书架';

  @override
  String get readerAddToBookshelf => '加入书架';

  @override
  String get readerNoDescription => '暂无简介';

  @override
  String get readerDescription => '简介';

  @override
  String get readerCollapse => '收起';

  @override
  String get readerExpand => '展开';

  @override
  String get readerExpandFull => '展开全文';

  @override
  String readerChapterListCount(Object count) {
    return '章节列表 ($count 章)';
  }

  @override
  String readerTotalPages(Object count) {
    return '共 $count 页';
  }

  @override
  String readerPageCount(Object count) {
    return '$count 页';
  }

  @override
  String readerViewAllChapters(Object count) {
    return '查看全部 $count 章';
  }

  @override
  String get readerPageInfo => '页面信息';

  @override
  String get readerTableOfContents => '目录';

  @override
  String readerTotalChapters(Object count) {
    return '共 $count 章';
  }

  @override
  String get readerDeleteCollection => '删除合集';

  @override
  String readerCollectionCount(Object count) {
    return '$count 本';
  }

  @override
  String get readerCollectionEmpty => '合集里还没有书籍';

  @override
  String get readerCollectionEmptyHint => '在书架中长按书籍，可以将它添加到合集。';

  @override
  String get readerConfirmDeleteCollection => '删除合集';

  @override
  String readerConfirmDeleteCollectionMsg(Object name) {
    return '确定要删除「$name」吗？合集内的书籍不会被删除。';
  }

  @override
  String readerDeletedCollection(Object name) {
    return '已删除「$name」';
  }

  @override
  String readerDeleteFailed(Object error) {
    return '删除失败: $error';
  }

  @override
  String get readerNoChanges => '未修改任何字段';

  @override
  String get readerMetadataSaved => '元数据已保存';

  @override
  String readerSaveFailed(Object error) {
    return '保存失败: $error';
  }

  @override
  String get readerEditMetadata => '编辑元数据';

  @override
  String get readerSave => '保存';

  @override
  String get readerLabelTitle => '标题';

  @override
  String get readerLabelAuthor => '作者';

  @override
  String get readerLabelDescription => '简介';

  @override
  String get readerLabelPublisher => '出版社';

  @override
  String get readerLabelReleaseDate => '发行日期';

  @override
  String get readerLabelRating => '评分 (0-10)';

  @override
  String get readerLabelGenres => '类型标签（逗号分隔）';

  @override
  String get readerLabelSerialStatus => '连载状态';

  @override
  String get readerStatusOngoing => '连载中';

  @override
  String get readerStatusCompleted => '已完结';

  @override
  String get readerStatusUnknown => '未知';

  @override
  String get readerSelectFromFile => '从文件选择';

  @override
  String get readerUploadCover => '上传新封面';

  @override
  String get readerNoImageFiles => '文件系统中没有可用的图片文件';

  @override
  String get readerSelectCoverImage => '选择封面图片';

  @override
  String get readerUnknownFile => '未知文件';

  @override
  String get readerCoverUpdated => '封面已更新';

  @override
  String readerOperationFailedError(Object error) {
    return '操作失败: $error';
  }

  @override
  String get readerCoverUploaded => '封面已上传';

  @override
  String readerUploadFailed(Object error) {
    return '上传失败: $error';
  }

  @override
  String readerPageInfoFormat(Object current, Object total) {
    return '第 $current 页 / 共 $total 页';
  }

  @override
  String readerPageNumber(Object page) {
    return '第 $page 页';
  }

  @override
  String readerWordCount(Object count) {
    return '$count 字';
  }

  @override
  String readerWordCountWan(Object count) {
    return '$count 万';
  }

  @override
  String get readerRetry => '重试';

  @override
  String get readerRtl => '右到左 (RTL)';

  @override
  String get readerLtr => '左到右 (LTR)';

  @override
  String get readerChapterListBtn => '章节列表';

  @override
  String get readerPrevChapter => '上一章';

  @override
  String get readerNextChapter => '下一章';

  @override
  String get readerClose => '关闭';

  @override
  String readerDeletedItem(Object name) {
    return '已删除「$name」';
  }

  @override
  String get readerDeleteItemFailed => '删除失败，请稍后重试';

  @override
  String get readerRemovedFromBookshelf => '已从书架移除';

  @override
  String get readerSearchBooksHint => '搜索书名、作者…';

  @override
  String readerCollectionCreated(Object name) {
    return '合集「$name」已创建';
  }

  @override
  String get readerCreateFailed => '创建失败，请稍后重试';

  @override
  String readerImportSuccess(Object name) {
    return '「$name」导入成功';
  }

  @override
  String get readerImportFailed => '导入失败，请稍后重试';

  @override
  String readerImportFailedWithReason(Object name, Object reason) {
    return '《$name》导入失败：$reason';
  }

  @override
  String get readerImportFromFile => '从设备导入';

  @override
  String get readerImporting => '导入中...';

  @override
  String get readerImportTypeTitle => '选择 EPUB 导入方式';

  @override
  String get readerImportTypeDesc =>
      '固定版式或图片型 EPUB 可作为漫画导入，普通文本 EPUB 建议作为图书导入。';

  @override
  String get readerImportNovel => '图书';

  @override
  String get readerImportLiterature => '文学';

  @override
  String get readerImportAcademic => '学术';

  @override
  String get readerImportTechnical => '技术';

  @override
  String get readerImportPoetry => '诗歌';

  @override
  String get readerImportEssay => '散文';

  @override
  String get readerImportComic => '漫画';

  @override
  String get readerPendingImport => '待导入文件';

  @override
  String readerPendingImportCount(Object count) {
    return '$count 个';
  }

  @override
  String get readerPendingImportDesc =>
      '以下是已上传但尚未导入到阅读中心的文件。EPUB 文件可选择作为图书或漫画导入。';

  @override
  String get readerNoPendingImport => '没有待导入的文件';

  @override
  String get readerNoPendingImportHint =>
      '上传 EPUB、CBZ 等阅读文件后，它们会出现在这里。已导入的文件不会重复显示。';

  @override
  String get readerReparse => '重新解析';

  @override
  String get readerReparseDesc => '对已导入的内容重新解析封面、元数据和章节。适用于解析结果不完整或新增了解析能力的场景。';

  @override
  String get readerNoImportedContent => '暂无已导入的内容';

  @override
  String get readerNoImportedContentHint => '导入书籍后，可以在这里重新解析。';

  @override
  String get readerNoFileNode => '该条目无文件节点，无法重新解析';

  @override
  String readerReparseSuccess(Object name) {
    return '「$name」重新解析成功';
  }

  @override
  String readerComicReparseStarted(Object name) {
    return '「$name」已开始重新解析，稍后可刷新查看状态';
  }

  @override
  String get readerReparseFailed => '重新解析失败，请稍后重试';

  @override
  String get readerComicImportStatusTitle => '漫画解析状态';

  @override
  String readerComicImportStatusValue(Object status) {
    return '当前状态：$status';
  }

  @override
  String readerComicSourceCount(Object count) {
    return '$count 个来源';
  }

  @override
  String readerComicCatalogCount(Object count) {
    return '$count 个目录';
  }

  @override
  String get readerComicCatalogPreview => '目录结构';

  @override
  String get readerComicPagePreview => '页面预览';

  @override
  String get readerComicCatalogPending => '目录仍在解析中，稍后刷新可查看结果。';

  @override
  String get readerComicPagesPending => '页面仍在解析中，稍后刷新可查看预览。';

  @override
  String get readerComicImportPending => '等待解析';

  @override
  String get readerComicImportParsing => '解析中';

  @override
  String get readerComicImportReady => '可阅读';

  @override
  String get readerComicImportPartialFailed => '部分失败';

  @override
  String get readerComicImportFailed => '解析失败';

  @override
  String get readerComicEmptyTitle => '还没有漫画';

  @override
  String get readerComicEmptyHint => '导入 CBZ、ZIP 或图片型 EPUB 后即可开始阅读。';

  @override
  String get readerComicParsingMessage => '正在解析漫画文件…';

  @override
  String get readerComicPartialFailedMessage => '部分来源解析失败，可重试或删除失败来源。';

  @override
  String get readerComicFailedMessage => '解析失败，请重试失败来源。';

  @override
  String get readerComicSources => '来源';

  @override
  String readerComicRetryCount(Object count) {
    return '已重试 $count 次';
  }

  @override
  String get readerRefreshFailed => '刷新失败，请稍后重试';

  @override
  String get readerCoverBadgeComic => '漫';

  @override
  String get readerCoverBadgeText => '文';

  @override
  String get readerDone => '完成';

  @override
  String get readerUnsupportedLink => '暂不支持打开该链接';

  @override
  String get readerUnknownAuthor => '未知作者';

  @override
  String get readerUnknownBook => '未知书籍';

  @override
  String get readerReadingReport => '阅读报告';

  @override
  String readerWeeklyHours(Object hours) {
    return '本周阅读 $hours 小时';
  }

  @override
  String get readerContinueBtn => '继续阅读';

  @override
  String get readerBookshelfSection => '书架';

  @override
  String readerShowAllBooks(Object count) {
    return '显示全部 $count 本';
  }

  @override
  String get readerViewAll => '查看全部';

  @override
  String readerBookCount(Object count) {
    return '$count 本';
  }

  @override
  String readerContinueCount(Object count) {
    return '$count 继续';
  }

  @override
  String get readerRefresh => '刷新';

  @override
  String get readerAddBook => '添加图书';

  @override
  String get readerImportQueued => '文件已上传，正在后台导入...';

  @override
  String get readerImportQueuedShort => '等待上传';

  @override
  String get readerImportRegistering => '正在加入书库';

  @override
  String get readerCancelImport => '中断导入';

  @override
  String get readerImportCancelled => '导入已取消';

  @override
  String get readerMetadataManagement => '元数据管理';

  @override
  String get readerMetadataDesc => '手动编辑书籍/漫画的元数据信息，包括标题、作者、简介、封面等。仅超级管理员可见。';

  @override
  String get readerNoBookEntries => '暂无书籍条目';

  @override
  String get readerNoBookEntriesHint => '导入书籍后即可在此管理元数据。';

  @override
  String get readerStatusPending => '待刮削';

  @override
  String get readerStatusFailed => '失败';

  @override
  String get readerStatusManual => '手动';

  @override
  String get readerStatusMatched => '已匹配';

  @override
  String get readerEdit => '编辑';

  @override
  String get readerScrapeQueue => '刮削队列';

  @override
  String get readerScrapeQueueDesc =>
      '以下条目缺少元数据（简介、评分、类型等），可手动触发刮削补全。仅超级管理员可见。';

  @override
  String get readerAllMetadataComplete => '所有条目元数据已齐全';

  @override
  String get readerScrapeHint => '新导入的书籍会自动触发刮削，也可在详情页手动重试。';

  @override
  String readerScrapeSubmitted(Object id) {
    return '刮削任务已提交: $id…';
  }

  @override
  String get readerScrapeSubmitFailed => '刮削任务提交失败，请稍后重试';

  @override
  String get readerSubmitting => '提交中…';

  @override
  String get readerBatchScrape => '全量刮削';

  @override
  String readerBatchScrapeResult(Object success, Object total) {
    return '已提交 $success / $total 个刮削任务';
  }

  @override
  String get readerSubmittingLabel => '提交中';

  @override
  String get readerScrapeLabel => '刮削';

  @override
  String get readerRemoveFromBookshelf => '从书架移除';

  @override
  String get readerDeleteBook => '删除书籍';

  @override
  String get readerDeleteBookHint => '永久删除书籍及其源文件';

  @override
  String get readerDeleteSource => '删除来源';

  @override
  String readerConfirmDeleteSource(Object name) {
    return '确定删除来源「$name」吗？该来源解析出的页面会从漫画中移除，文件模块中的原始文件将保留。';
  }

  @override
  String get readerConfirmDelete => '确认永久删除';

  @override
  String readerConfirmDeleteMsg(Object name) {
    return '确定要永久删除「$name」吗？书库记录与源文件都会删除，此操作不可撤销。';
  }

  @override
  String readerFieldRequired(Object field) {
    return '$field不能为空';
  }

  @override
  String get readerHistory => '历史';

  @override
  String get readerImports => '导入';

  @override
  String get readerGroupPersonal => '个人';

  @override
  String get readerGroupTools => '工具';

  @override
  String get readerGroupManagement => '管理';

  @override
  String readerPercentRead(Object percent) {
    return '$percent% 已读';
  }

  @override
  String readerSectionNotAvailable(Object section) {
    return '$section 暂未接入';
  }

  @override
  String get readerSectionNotAvailableHint => '这个入口已经预留好了，后续会接入独立内容页。';

  @override
  String get readerNoBookmarks => '还没有书签';

  @override
  String get readerNoBookmarksHint => '在阅读时添加书签，下次可以从这里快速跳转。';

  @override
  String get readerEmptyHint => '这里还没有内容';

  @override
  String get readerEmptyHintDesc => '支持 EPUB、TXT、CBZ、ZIP、PDF，导入后会自动出现在书架里。';

  @override
  String get readerImportBooks => '导入书籍';

  @override
  String get readerHighlight => '高亮';

  @override
  String get readerAnnotate => '批注';

  @override
  String get readerRemoveHighlight => '取消高亮';

  @override
  String get readerRemoveAnnotation => '取消批注';

  @override
  String get readerCopy => '复制';

  @override
  String get readerAnnotations => '批注';

  @override
  String get readerNoAnnotations => '暂无批注';

  @override
  String get readerEditAnnotation => '编辑批注';

  @override
  String get readerDeleteAnnotation => '删除批注';

  @override
  String get readerSearchAnnotations => '搜索批注';

  @override
  String get readerSearchAnnotationsHint => '搜索批注...';

  @override
  String get readerThisChapter => '本章';

  @override
  String get readerAllChapters => '全书';

  @override
  String get readerPageTransition => '翻页动画';

  @override
  String get readerTransitionSlide => '滑动';

  @override
  String get readerTransitionCover => '覆盖';

  @override
  String get readerTransitionFade => '淡入';

  @override
  String get readerTransitionScroll => '上下';

  @override
  String get videoSectionMovies => '电影';

  @override
  String get videoSectionTvShows => '剧集';

  @override
  String get videoSectionAnime => '动漫';

  @override
  String get videoSectionCollections => '合集';

  @override
  String get videoSectionRecent => '最近添加';

  @override
  String get videoSectionContinueWatching => '继续观看';

  @override
  String get videoSectionFavorites => '我的收藏';

  @override
  String get videoSectionHistory => '观看历史';

  @override
  String get videoSeriesFeatured => '精选';

  @override
  String get videoSectionMetadataManagement => '元数据管理';

  @override
  String get videoSectionLibraryScan => '媒体库管理';

  @override
  String get videoSidebarGroupLibrary => '媒体库';

  @override
  String get videoSidebarGroupMine => '我的媒体';

  @override
  String get videoSidebarGroupManagement => '管理工具';

  @override
  String get videoRefreshTooltip => '刷新';

  @override
  String get videoBackToPortal => 'Portal 首页';

  @override
  String get videoBackToLibrary => '返回影库';

  @override
  String get videoSearchMovies => '搜索影片';

  @override
  String get videoSearchMovieHint => '输入影片名称…';

  @override
  String get videoCancel => '取消';

  @override
  String get videoSearch => '搜索';

  @override
  String get videoManageAdminOnly => '管理工具仅管理员可见';

  @override
  String get videoBrowse => '浏览';

  @override
  String get videoMore => '更多';

  @override
  String get videoClose => '关闭';

  @override
  String get videoSearchLibraryHint => '搜索影视库…';

  @override
  String get videoMovieLibrary => '媒体库';

  @override
  String get videoMovieLibrarySubtitle => '浏览电影、剧集与动漫，支持筛选和分类浏览。';

  @override
  String get videoAnimeLibrary => '动漫库';

  @override
  String get videoAnimeLibrarySubtitle => '日本动画按系列组织，点击可查看详情、季集列表和直接播放。';

  @override
  String get videoRecentSubtitle => '最近 30 天新增的内容集中显示在此。';

  @override
  String get videoFavoritesSubtitle => '当前用户标记星标的影片和剧集会集中显示在这里。';

  @override
  String videoSeasonProgress(Object season, Object current, Object total) {
    return '第 $season 季 · $current/$total 集';
  }

  @override
  String get videoDefaultVersion => '默认版本';

  @override
  String get videoSelectVersion => '选择版本';

  @override
  String get videoPlay => '播放';

  @override
  String get videoFavorited => '已收藏';

  @override
  String get videoFavorite => '收藏';

  @override
  String get videoSubtitle => '字幕';

  @override
  String get videoAudio => '音频';

  @override
  String get videoMovedToRecycleBin => '影片及源文件已永久删除';

  @override
  String get videoDelete => '删除';

  @override
  String get videoDeleteItemTitle => '删除影视条目？';

  @override
  String videoDeleteItemMessage(Object title) {
    return '\"$title\" 及其源文件将被永久删除，此操作无法撤销。';
  }

  @override
  String get videoSubtitleManagement => '字幕管理';

  @override
  String get videoNoSubtitles => '暂无可用字幕';

  @override
  String get videoSubtitleLoadFailed => '加载字幕信息失败';

  @override
  String get videoUploading => '上传中...';

  @override
  String get videoUploadSubtitle => '上传字幕文件';

  @override
  String get videoSubtitleUploaded => '字幕上传成功';

  @override
  String get videoDeleteSubtitleTitle => '删除字幕？';

  @override
  String videoDeleteSubtitleMessage(Object label) {
    return '确定删除字幕 \"$label\" 吗？';
  }

  @override
  String get videoSubtitleDeleted => '字幕已删除';

  @override
  String get videoSubtitleLanguage => '字幕语言';

  @override
  String get videoSubtitleLanguageHint => '例如: chi, eng, jpn';

  @override
  String get videoConfirm => '确定';

  @override
  String get videoEmbedded => '内嵌';

  @override
  String get videoExternal => '外挂';

  @override
  String get videoDeleteSubtitleTooltip => '删除字幕';

  @override
  String get videoAudioManagement => '音频管理';

  @override
  String get videoOriginalAudio => '原始音频';

  @override
  String get videoUnknown => '未知';

  @override
  String get videoCompatibleAudioCache => '兼容音频缓存';

  @override
  String get videoNotExtracted => '未提取';

  @override
  String get videoLoadFailed => '加载失败';

  @override
  String videoAudioIncompatibleNotice(Object codec) {
    return '当前音频编码 $codec 不兼容 Web 浏览器。提取兼容音频后，Web 端将使用缓存音频播放。';
  }

  @override
  String get videoCompatibleAudioReady => '兼容音频已就绪';

  @override
  String get videoExtracting => '提取中...';

  @override
  String get videoExtractCompatibleAudio => '提取兼容音频';

  @override
  String get videoAudioExtractCreated => '音频提取任务已创建';

  @override
  String get videoCached => '已缓存';

  @override
  String get videoIncompatible => '不兼容';

  @override
  String get videoCompatible => '兼容';

  @override
  String get videoCast => '演员';

  @override
  String get videoMediaGallery => '媒体库';

  @override
  String get videoTrailer => '预告片';

  @override
  String get videoTechnicalInfo => '技术信息';

  @override
  String get videoScrapeStatus => '刮削状态';

  @override
  String get videoNfoExport => 'NFO 导出';

  @override
  String get videoExported => '已导出';

  @override
  String get videoNotExported => '未导出';

  @override
  String get videoDetecting => '检测中...';

  @override
  String get videoContainerFormat => '容器格式';

  @override
  String get videoDuration => '时长';

  @override
  String get videoType => '类型';

  @override
  String get videoMatched => '已匹配';

  @override
  String get videoPendingScrape => '待刮削';

  @override
  String get videoSectionMovieAdmin => '影片管理';

  @override
  String get videoMovieAdminSubtitle => '统一管理影片的元数据、刮削与转码操作。';

  @override
  String get videoMovieAdminEmpty => '没有符合条件的影片。';

  @override
  String get videoLibraryFilterAll => '全部';

  @override
  String get videoPreviousPage => '上一页';

  @override
  String get videoNextPage => '下一页';

  @override
  String get videoTaskProgressDialog => '任务进度';

  @override
  String get videoSnackViewProgress => '查看进度';

  @override
  String get videoAdminLibrarySources => '库源配置';

  @override
  String videoSeriesEpisodeCount(Object count) {
    return '$count 集';
  }

  @override
  String get videoMatchFailed => '匹配失败';

  @override
  String get videoManualEdit => '手动编辑';

  @override
  String get videoOverview => '剧情简介';

  @override
  String get videoCollapse => '收起';

  @override
  String get videoExpandAll => '展开全部';

  @override
  String get videoRecommendations => '推荐';

  @override
  String get videoWatchRecord => '观看记录';

  @override
  String get videoWatched => '已看完';

  @override
  String get videoWatching => '观看中';

  @override
  String get videoNoWatchRecord => '暂无观看记录';

  @override
  String videoLastPlayed(Object time) {
    return '上次播放: $time';
  }

  @override
  String get videoJustNow => '刚刚';

  @override
  String videoMinutesAgo(Object n) {
    return '$n 分钟前';
  }

  @override
  String videoHoursAgo(Object n) {
    return '$n 小时前';
  }

  @override
  String videoDaysAgo(Object n) {
    return '$n 天前';
  }

  @override
  String get videoHighRated => '高分推荐';

  @override
  String get videoNewest => '最新上映';

  @override
  String get videoViewMore => '查看更多';

  @override
  String get videoContinueSubtitle => '展示未看完的电影和剧集，点击卡片可直接续播。';

  @override
  String get videoNoContinueRecord => '暂无继续观看记录。';

  @override
  String get videoCollectionsSubtitle => '支持用户自定义或自动生成合集，例如电影宇宙、导演作品集和家庭收藏。';

  @override
  String get videoNewCollection => '新建合集';

  @override
  String get videoAllMedia => '全部媒体';

  @override
  String get videoCustomCollection => '自定义合集';

  @override
  String get videoCollectionName => '合集名称';

  @override
  String get videoDescription => '描述';

  @override
  String get videoCreate => '创建';

  @override
  String get videoCollectionNameEmpty => '合集名称不能为空';

  @override
  String get videoCollectionCreated => '合集已创建';

  @override
  String get videoCollectionEmpty => '合集为空';

  @override
  String get videoCollectionAddMovies => '添加影片';

  @override
  String get videoCollectionPickerTitle => '选择影片';

  @override
  String get videoCollectionPickerSearchHint => '搜索标题';

  @override
  String get videoCollectionAlreadyAdded => '已在合集中';

  @override
  String get videoCollectionPickerEmpty => '没有匹配的影片';

  @override
  String videoLoadFailedWith(Object error) {
    return '加载失败: $error';
  }

  @override
  String get videoRequestTimeout => '请求超时，请稍后重试';

  @override
  String get videoConnectionError => '无法连接后端服务，请确认服务已启动';

  @override
  String get videoOperationCancelled => '操作已取消';

  @override
  String get videoServerError => '服务端响应异常，请稍后重试';

  @override
  String get videoCertificateError => '证书校验失败，请检查服务配置';

  @override
  String get videoRequestFailed => '请求失败，请稍后重试';

  @override
  String get videoOperationFailed => '操作失败，请稍后重试';

  @override
  String get videoProcessing => '处理中';

  @override
  String get videoHistorySubtitle => '完整播放记录支持按已看完、未看完和时间范围筛选。';

  @override
  String get videoClearHistory => '清空历史';

  @override
  String get videoNoWatchHistory => '暂无观看历史。';

  @override
  String get videoMoreFilters => '更多筛选';

  @override
  String get videoGenre => '类型';

  @override
  String get videoYear => '年份';

  @override
  String get videoRating => '评分';

  @override
  String get videoSort => '排序';

  @override
  String get videoClear => '清除';

  @override
  String get videoSortDateAdded => '添加时间';

  @override
  String get videoSortReleaseDate => '上映日期';

  @override
  String get videoSortTitle => '标题';

  @override
  String get videoNoMediaItems => '这里还没有媒体条目。';

  @override
  String get videoTaskSubmitted => '任务已提交';

  @override
  String get videoRetry => '重试';

  @override
  String get videoSubmitting => '提交中';

  @override
  String get videoEdit => '编辑';

  @override
  String get videoNfo => 'NFO';

  @override
  String videoEpisodeStatus(Object count, Object status) {
    return '剧集 · $count 集 · $status';
  }

  @override
  String get videoParse => '解析';

  @override
  String get videoTranscode => '视频转码';

  @override
  String get videoAudioExtract => '音频提取';

  @override
  String get videoNoTasks => '当前没有任务。';

  @override
  String get videoMetadataScrape => '元数据抓取';

  @override
  String get videoMediaScan => '媒体扫描';

  @override
  String get videoQueued => '排队中';

  @override
  String get videoRunning => '执行中';

  @override
  String get videoCompleted => '已完成';

  @override
  String get videoFailed => '失败';

  @override
  String get videoCancelled => '已取消';

  @override
  String get videoDeadLetterQueue => '死信队列';

  @override
  String get videoIncrementalScan => '增量扫描';

  @override
  String get videoScanning => '扫描中';

  @override
  String get videoIncrementalScanComplete => '增量扫描已完成';

  @override
  String get videoFullScan => '全量扫描';

  @override
  String get videoFullScanComplete => '全量扫描已完成';

  @override
  String videoNfoPreviewTitle(Object title) {
    return 'NFO - $title';
  }

  @override
  String get videoSeriesLibrary => '剧集库';

  @override
  String get videoSeriesLibrarySubtitle => '剧集按系列组织，点击可查看详情、季集列表和直接播放。';

  @override
  String get videoNoSeries => '还没有剧集系列。';

  @override
  String get videoNoSeasonInfo => '暂无季信息';

  @override
  String get videoEpisodeList => '剧集列表';

  @override
  String videoSeasonTab(Object number) {
    return '第$number季';
  }

  @override
  String get videoNoEpisodesInSeason => '该季暂无单集信息';

  @override
  String get videoMediaCenter => '媒体库';

  @override
  String videoSeasonLabel(Object number) {
    return '第 $number 季';
  }

  @override
  String videoEpisodeLabel(Object number) {
    return '第 $number 集';
  }

  @override
  String get videoPreviousEpisode => '上一集';

  @override
  String get videoNextEpisode => '下一集';

  @override
  String get videoTitleRequired => '标题不能为空';

  @override
  String get videoMetadataSaved => '元数据已保存';

  @override
  String get videoEditMetadataDesc => '在这里编辑用于展示的标题、简介、封面和背景图，保存后会锁定为手动元数据。';

  @override
  String get videoCoverAssets => '封面资产';

  @override
  String get videoPosterFileId => '封面文件 ID';

  @override
  String get videoBackdropFileId => '背景图文件 ID';

  @override
  String get videoCoverIdHint => '使用文件节点 ID 绑定封面和背景图；保存后会立即更新媒体库展示资源。';

  @override
  String get videoBrandVersion => '媒体库 v1.0';

  @override
  String get videoMetadataStatus => '元数据状态';

  @override
  String get videoManualLock => '手动锁定';

  @override
  String get videoPendingRecognition => '待识别';

  @override
  String get videoRecognitionFailed => '识别失败';

  @override
  String get videoOriginalTitle => '原始标题';

  @override
  String get videoReleaseDate => '上映日期';

  @override
  String get videoRuntimeMinutes => '时长（分钟）';

  @override
  String get videoOverviewLabel => '简介';

  @override
  String get videoSaveChanges => '保存修改';

  @override
  String get videoBackdrop => '背景图';

  @override
  String get videoFillScreen => '铺满';

  @override
  String get videoOriginalAspectRatio => '原始比例';

  @override
  String get videoCompatibleAudioNotice => '已使用兼容音频流播放。点击底部音频按钮可切换音频源。';

  @override
  String get videoGotIt => '知道了';

  @override
  String get videoSubtitleTrack => '字幕轨道';

  @override
  String get videoNoSubtitlesAvailable => '当前视频无可用字幕';

  @override
  String get videoDisableSubtitles => '关闭字幕';

  @override
  String get videoAudioTrack => '音频轨道';

  @override
  String get videoCompatibleAudioAac => '兼容音频（AAC 缓存）';

  @override
  String get videoCompatibleAudioDesc => '预处理的 AAC 音频流，兼容所有 Web 浏览器';

  @override
  String videoOriginalAudioLabel(Object codec) {
    return '原始音频（$codec）';
  }

  @override
  String get videoOriginalAudioDesc => '实时转码原始音频，可能需要更多处理时间';

  @override
  String get videoPlaybackSpeed => '播放速度';

  @override
  String get videoAspectRatio => '画面比例';

  @override
  String get videoPlaybackSettings => '播放设置';

  @override
  String get videoSubtitlesEnabled => '字幕已开启';

  @override
  String get videoSubtitlesOff => '关闭';

  @override
  String get videoSubtitlesOn => '已开启';

  @override
  String get videoPlaybackInfo => '播放信息';

  @override
  String get videoInfoMode => '模式';

  @override
  String get videoInfoContainer => '容器';

  @override
  String get videoInfoVideoCodec => '视频编码';

  @override
  String get videoInfoAudioCodec => '音频编码';

  @override
  String get videoInfoAudioSource => '音频源';

  @override
  String videoInfoSubtitleCount(Object count) {
    return '$count 条';
  }

  @override
  String get videoInfoVolume => '音量';

  @override
  String get videoBackToDetail => '返回详情';

  @override
  String videoStatusSubtitle(Object container, Object video, Object audio) {
    return '当前视频为 $container/$video/$audio，浏览器不支持直接播放，正在通过服务端转码流式播放。跳转精度有限，如需精准 Seek 请使用桌面客户端。';
  }

  @override
  String videoLastPlayedTime(Object time) {
    return '上次播放: $time';
  }

  @override
  String get photosLoading => '加载中...';

  @override
  String get photoThumbnailLoading => '正在加载缩略图';

  @override
  String get photosTaskFailed => '任务执行失败';

  @override
  String get photosTaskStatusRefreshFailed => '任务状态更新失败，正在自动重试';

  @override
  String photosProcessedItems(Object count) {
    return '已完成 $count 项';
  }

  @override
  String get photosDone => '完成';

  @override
  String get photosRunInBackground => '后台运行';

  @override
  String get photosSlideshow3s => '3秒';

  @override
  String get photosSlideshow5s => '5秒';

  @override
  String get photosSlideshow10s => '10秒';

  @override
  String get photosTabHome => '首页';

  @override
  String get photosTabFavorites => '收藏';

  @override
  String get photosTabTimeline => '时间线';

  @override
  String get photosTabAlbums => '相册';

  @override
  String get photosTabGroups => '分组';

  @override
  String get photosTabGraph => '关系图谱';

  @override
  String get photosSurfaceLibrary => '照片库';

  @override
  String get photosSurfaceExplore => '探索';

  @override
  String get photosGraphKindAlbum => '相册';

  @override
  String get photosGraphKindTime => '时间';

  @override
  String get photosGraphKindLocation => '地点';

  @override
  String get photosGraphEmpty => '暂时没有可展示的照片关系。';

  @override
  String get photosGraphViewPhoto => '查看照片';

  @override
  String photosGraphPhotoCount(Object count) {
    return '$count 张照片';
  }

  @override
  String get photosGroupByDate => '时间';

  @override
  String get photosGroupByLocation => '位置';

  @override
  String get photosGroupByFormat => '格式';

  @override
  String get photosGroupByTag => '标签';

  @override
  String get photosEditTypeRotate => '旋转';

  @override
  String get photosEditTypeCrop => '裁剪';

  @override
  String get photosEditTypeBrightness => '亮度';

  @override
  String get photosEditTypeContrast => '对比度';

  @override
  String get photosEditTypeFilter => '滤镜';

  @override
  String get photosImportCompletedNotVisible => '照片导入任务已完成，但照片尚未出现在当前列表中';

  @override
  String get photosImportStillProcessing => '照片仍在后台导入，请稍后刷新查看';

  @override
  String get photosImportBackendFailed => '照片后台导入任务失败，请在任务中心查看详情';

  @override
  String get photosSharedPoweredBy => '由 OmniNest 提供';

  @override
  String get photosTabMemories => '回忆';

  @override
  String get photosClose => '关闭';

  @override
  String get photosDeletePhotoTitle => '永久删除照片';

  @override
  String photosDeletePhotoConfirm(Object title) {
    return '「$title」及其源文件将被永久删除，此操作无法撤销。';
  }

  @override
  String get photosCancel => '取消';

  @override
  String get photosDelete => '删除';

  @override
  String get photosDeletePermanently => '永久删除';

  @override
  String photosDeletedPhoto(Object title) {
    return '已永久删除「$title」及其源文件';
  }

  @override
  String get photosDeleteFailed => '删除失败，请稍后重试';

  @override
  String get photosDeleteAlbumTitle => '删除相册';

  @override
  String photosDeleteAlbumConfirm(Object name) {
    return '确定要删除相册「$name」吗？相册内的照片不会被删除。';
  }

  @override
  String photosDeletedAlbum(Object name) {
    return '已删除相册「$name」';
  }

  @override
  String get photosNewAlbum => '新建相册';

  @override
  String get photosAlbumName => '相册名称';

  @override
  String get photosAlbumNameHint => '例如：旅行照片';

  @override
  String get photosAlbumDescription => '描述（可选）';

  @override
  String get photosAlbumDescriptionHint => '简要描述这个相册';

  @override
  String photosAlbumCreated(Object name) {
    return '相册「$name」已创建';
  }

  @override
  String get photosCreateFailed => '创建失败，请稍后重试';

  @override
  String get photosCreate => '创建';

  @override
  String get photosBackToPortal => '返回 Portal';

  @override
  String get photosSearchPhotos => '搜索照片';

  @override
  String get photosSearchHint => '搜索照片…';

  @override
  String get photosClear => '清除';

  @override
  String get photosSearch => '搜索';

  @override
  String get photosAll => '全部';

  @override
  String get photosNoFavorites => '还没有收藏的照片';

  @override
  String get photosNoFavoritesHint => '点击照片详情中的收藏按钮来收藏照片。';

  @override
  String get photosRecentPhotos => '最近照片';

  @override
  String get photosNoPhotos => '还没有照片';

  @override
  String get photosNoPhotosHint => '上传照片后，它们会自动出现在这里。';

  @override
  String get photosAlbums => '影集';

  @override
  String get photosNoAlbums => '还没有影集';

  @override
  String photosAlbumPhotoCount(Object count) {
    return '$count';
  }

  @override
  String get photosViewAll => '查看全部';

  @override
  String photosLoadMore(Object loaded, Object total) {
    return '加载更多（已加载 $loaded / $total）';
  }

  @override
  String photosSelectedCount(Object count) {
    return '已选 $count 张';
  }

  @override
  String get photosTag => '标签';

  @override
  String get photosMove => '移动';

  @override
  String get photosExportZip => '导出 ZIP';

  @override
  String get photosUpdateDate => '更新拍摄时间';

  @override
  String get photosSaveZip => '保存 ZIP';

  @override
  String get photosDownloadStarted => '已交由浏览器下载';

  @override
  String photosArchiveSaved(Object path) {
    return 'ZIP 已保存至 $path';
  }

  @override
  String get photosArchiveDownloadFailed => 'ZIP 下载失败，可重新选择同一路径继续下载';

  @override
  String get photosDownloadPhoto => '下载原片';

  @override
  String get photosDownloadFailed => '下载失败，请稍后重试';

  @override
  String photosDownloadSaved(Object path) {
    return '已保存至 $path';
  }

  @override
  String get photosDownloadSourceUnavailable => '原图暂不可用，无法下载';

  @override
  String photosSlideshowBadge(int current, int total) {
    return '幻灯片 · $current / $total';
  }

  @override
  String get photosBatchAddTag => '批量添加标签';

  @override
  String get photosTagName => '标签名称';

  @override
  String get photosTagNameHint => '例如：旅行';

  @override
  String get photosAdd => '添加';

  @override
  String get photosTaskCreateFailed => '任务创建失败';

  @override
  String get photosSelectAlbum => '选择相册';

  @override
  String get photosBatchDelete => '批量删除';

  @override
  String photosBatchDeleteConfirm(Object count) {
    return '选中的 $count 张照片及其源文件将被永久删除，此操作无法撤销。';
  }

  @override
  String photosBatchDeleted(Object count) {
    return '已永久删除 $count 张照片及其源文件';
  }

  @override
  String get photosDeselect => '取消选择';

  @override
  String get photosNoTimelineData => '暂无时间线数据';

  @override
  String get photosNoTimelineHint => '照片需要包含拍摄时间信息才能显示时间线';

  @override
  String photosYear(Object year) {
    return '$year年';
  }

  @override
  String get photosOperationFailed => '操作失败，请稍后重试';

  @override
  String get photosImageLoadFailed => '图片加载失败';

  @override
  String get photosBack => '返回';

  @override
  String get photosUnfavorite => '取消收藏';

  @override
  String get photosFavorite => '收藏';

  @override
  String get photosHideInfo => '隐藏信息';

  @override
  String get photosShowInfo => '显示信息';

  @override
  String get photosEdit => '编辑';

  @override
  String get photosSlideshow => '幻灯片';

  @override
  String get photosSlideshowUnavailable => '当前没有可连续播放的照片';

  @override
  String get photosAddToAlbum => '加入相册';

  @override
  String get photosPhotoInfo => '照片信息';

  @override
  String get photosBasicInfo => '基本信息';

  @override
  String get photosFormat => '格式';

  @override
  String get photosFileSize => '文件大小';

  @override
  String get photosResolution => '分辨率';

  @override
  String get photosDateTaken => '拍摄日期';

  @override
  String get photosCameraInfo => '相机信息';

  @override
  String get photosBrand => '品牌';

  @override
  String get photosModel => '型号';

  @override
  String get photosLens => '镜头';

  @override
  String get photosAperture => '光圈';

  @override
  String get photosShutterSpeed => '快门速度';

  @override
  String get photosFocalLength => '焦距';

  @override
  String get photosShootingParams => '拍摄参数';

  @override
  String get photosFlash => '闪光灯';

  @override
  String get photosWhiteBalance => '白平衡';

  @override
  String get photosMeteringMode => '测光模式';

  @override
  String get photosLocationInfo => '位置信息';

  @override
  String get photosPlace => '地点';

  @override
  String get photosCoordinates => '坐标';

  @override
  String get photosAIRecognition => '图像分析';

  @override
  String get photosAnalysisSubject => '主体';

  @override
  String get photosAnalysisScene => '场景';

  @override
  String get photosAnalysisStyle => '风格';

  @override
  String get photosAiCategoryPerson => '人物';

  @override
  String get photosAiCategoryCat => '猫';

  @override
  String get photosAiCategoryDog => '狗';

  @override
  String get photosAiCategoryAnimal => '动物';

  @override
  String get photosAiCategoryNature => '自然风景';

  @override
  String get photosAiCategoryArchitecture => '城市建筑';

  @override
  String get photosAiCategoryIndoor => '室内';

  @override
  String get photosAiCategoryFood => '食物';

  @override
  String get photosAiCategoryVehicle => '交通工具';

  @override
  String get photosAiCategoryPlant => '植物';

  @override
  String get photosAiCategorySport => '运动';

  @override
  String get photosAiCategoryNight => '夜景';

  @override
  String get photosAiCategoryArt => '艺术';

  @override
  String get photosAiCategoryDocument => '文档与屏幕';

  @override
  String get photosDescription => '描述';

  @override
  String get photosDeleteTagFailed => '删除标签失败';

  @override
  String get photosAddTag => '添加标签';

  @override
  String get photosTagNameInput => '输入标签名称';

  @override
  String get photosAddTagFailed => '添加标签失败';

  @override
  String get photosNoAlbumsCreateFirst => '暂无相册，请先创建相册';

  @override
  String get photosAddedToAlbum => '已添加到相册';

  @override
  String get photosAddFailed => '添加失败，请稍后重试';

  @override
  String get photosNoChanges => '未做任何修改';

  @override
  String get photosEditSaved => '编辑已保存';

  @override
  String get photosSaveFailed => '保存失败，请稍后重试';

  @override
  String get photosEditorCancel => '取消';

  @override
  String get photosEditorUndo => '撤销';

  @override
  String get photosEditorRedo => '重做';

  @override
  String get photosEditorDone => '完成';

  @override
  String get photosEditorRemove => '移除';

  @override
  String get photosEditorBack => '返回';

  @override
  String get photosEditorMore => '更多';

  @override
  String get photosEditorDoneLoadingMsg => '正在应用更改';

  @override
  String get photosEditorImportStateHistoryMsg => '正在载入编辑内容';

  @override
  String get photosEditorLoadingDialogMsg => '请稍候…';

  @override
  String get photosEditorCloseWarningTitle => '关闭图片编辑器？';

  @override
  String get photosEditorCloseWarningMessage => '确定要关闭图片编辑器吗？未保存的更改将丢失。';

  @override
  String get photosEditorCloseWarningConfirm => '确定';

  @override
  String get photosEditorPaintBottomNav => '绘画';

  @override
  String get photosEditorPaintMoveAndZoom => '移动与缩放';

  @override
  String get photosEditorPaintFreestyle => '自由绘制';

  @override
  String get photosEditorPaintArrow => '箭头';

  @override
  String get photosEditorPaintLine => '直线';

  @override
  String get photosEditorPaintRectangle => '矩形';

  @override
  String get photosEditorPaintCircle => '圆形';

  @override
  String get photosEditorPaintDashLine => '虚线';

  @override
  String get photosEditorPaintDashDotLine => '点划线';

  @override
  String get photosEditorPaintHexagon => '六边形';

  @override
  String get photosEditorPaintPolygon => '多边形';

  @override
  String get photosEditorPaintBlur => '模糊';

  @override
  String get photosEditorPaintPixelate => '像素化';

  @override
  String get photosEditorLineWidth => '线条粗细';

  @override
  String get photosEditorEraser => '橡皮擦';

  @override
  String get photosEditorToggleFill => '切换填充';

  @override
  String get photosEditorChangeOpacity => '更改不透明度';

  @override
  String get photosEditorOpacity => '不透明度';

  @override
  String get photosEditorColor => '颜色';

  @override
  String get photosEditorStrokeWidth => '描边宽度';

  @override
  String get photosEditorFill => '填充';

  @override
  String get photosEditorTextInputHint => '输入文字';

  @override
  String get photosEditorTextBottomNav => '文字';

  @override
  String get photosEditorTextAlign => '文字对齐';

  @override
  String get photosEditorFontScale => '字号';

  @override
  String get photosEditorTextBackgroundMode => '背景色';

  @override
  String get photosEditorCropBottomNav => '裁剪旋转';

  @override
  String get photosEditorCropRotate => '旋转';

  @override
  String get photosEditorCropFlip => '翻转';

  @override
  String get photosEditorCropTilt => '矫正';

  @override
  String get photosEditorCropTiltHorizontal => '水平';

  @override
  String get photosEditorCropTiltVertical => '垂直';

  @override
  String get photosEditorCropRatio => '比例';

  @override
  String get photosEditorCropReset => '重置';

  @override
  String get photosEditorRatioFree => '自由';

  @override
  String get photosEditorRatioOriginal => '原始';

  @override
  String get photosEditorTuneBottomNav => '调节';

  @override
  String get photosEditorTuneBrightness => '亮度';

  @override
  String get photosEditorTuneContrast => '对比度';

  @override
  String get photosEditorTuneSaturation => '饱和度';

  @override
  String get photosEditorTuneExposure => '曝光';

  @override
  String get photosEditorTuneHue => '色相';

  @override
  String get photosEditorTuneTemperature => '色温';

  @override
  String get photosEditorTuneFade => '褪色';

  @override
  String get photosEditorTuneTint => '色调';

  @override
  String get photosEditorFilterBottomNav => '滤镜';

  @override
  String get photosEditorFilterNone => '无滤镜';

  @override
  String get photosEditorBlurBottomNav => '模糊';

  @override
  String get photosEditorEmojiBottomNav => '表情';

  @override
  String get photosEditorEmojiSearch => '搜索';

  @override
  String get photosEditorEmojiRecent => '最近';

  @override
  String get photosEditorEmojiSmileys => '笑脸与人物';

  @override
  String get photosEditorEmojiAnimals => '动物与自然';

  @override
  String get photosEditorEmojiFood => '食物与饮品';

  @override
  String get photosEditorEmojiActivities => '活动';

  @override
  String get photosEditorEmojiTravel => '旅行与地点';

  @override
  String get photosEditorEmojiObjects => '物品';

  @override
  String get photosEditorEmojiSymbols => '符号';

  @override
  String get photosEditorEmojiFlags => '旗帜';

  @override
  String get photosEditorStickerBottomNav => '贴纸';

  @override
  String get photosEditorLayerEdit => '编辑';

  @override
  String get photosEditorLayerRotateScale => '旋转与缩放';

  @override
  String get photosRolledBack => '已回滚到指定版本';

  @override
  String get photosRollbackFailed => '回滚失败';

  @override
  String photosEditTitle(Object title) {
    return '编辑 - $title';
  }

  @override
  String get photosVersionHistory => '版本历史';

  @override
  String get photosSave => '保存';

  @override
  String get photosCropDragHint => '拖拽选择裁剪区域';

  @override
  String get photosConfirmCrop => '确认裁剪';

  @override
  String get photosEditVersionHistory => '编辑版本历史';

  @override
  String get photosNoEditHistory => '暂无编辑历史';

  @override
  String get photosRollback => '回滚';

  @override
  String get photosConfirm => '确定';

  @override
  String photosPhotoCount(Object count) {
    return '$count 张照片';
  }

  @override
  String photosSharedAlbumAccessError(Object error) {
    return '无法访问共享相册：$error';
  }

  @override
  String get photosSharedAlbumPasswordRequired => '此相册需要密码访问';

  @override
  String get photosSharedAlbumPasswordHint => '请输入分享密码以查看相册内容';

  @override
  String get photosEnterPassword => '输入密码';

  @override
  String get photosAccess => '访问';

  @override
  String get photosAlbumEmpty => '相册中还没有照片';

  @override
  String get photosAddPhotos => '添加照片';

  @override
  String photosPickerAddCount(Object count) {
    return '添加 $count 张';
  }

  @override
  String photosPickerAddSuccess(Object count) {
    return '已添加 $count 张照片';
  }

  @override
  String get photosPickerNoCandidates => '没有可添加的照片';

  @override
  String get photosSharePhoto => '分享照片';

  @override
  String get photosSharedItemPasswordRequired => '此分享需要访问密码';

  @override
  String get photosLiveBadge => '实况';

  @override
  String get photosLiveBadgeTooltip => '点击播放动态效果，长按照片可快速预览';

  @override
  String get photosMotionPlayFailed => '动态视频播放失败';

  @override
  String get photosShareEyebrow => '分享';

  @override
  String get photosShareLinkEyebrow => '链接';

  @override
  String get photosShareCopy => '复制';

  @override
  String get photosShareCopied => '✓ 已复制';

  @override
  String get photosShareToEyebrow => '分享至';

  @override
  String get photosShareToMessages => '信息';

  @override
  String get photosShareToMail => '邮件';

  @override
  String get photosShareToInstagram => 'Instagram';

  @override
  String get photosShareToWeChat => '微信';

  @override
  String get photosShareToQr => '二维码';

  @override
  String get photosShareWeChatCopiedFallback => '已复制链接，请粘贴到微信发送';

  @override
  String get photosShareOptionLocation => '包含位置信息';

  @override
  String get photosShareOptionOriginal => '原图画质';

  @override
  String get photosShareOptionOriginalFull => '原始分辨率';

  @override
  String get photosShareManage => '管理已有链接';

  @override
  String get photosShareDone => '完成';

  @override
  String get photosShareOptionsEyebrow => '选项';

  @override
  String get photosShareExpiryOption => '有效期';

  @override
  String get photosSharePasswordOption => '密码保护';

  @override
  String get photosSharePasswordNone => '未设置';

  @override
  String get photosSharePasswordOn => '已启用';

  @override
  String get photosShareCreatedHint => '链接已创建并复制到剪贴板';

  @override
  String get photosShareAlbum => '分享相册';

  @override
  String get photosSharePassword => '访问密码（可选）';

  @override
  String get photosSharePasswordHint => '留空则无需密码';

  @override
  String get photosShareExpiry => '有效期';

  @override
  String get photosShareExpiry1d => '1天';

  @override
  String get photosShareExpiry7d => '7天';

  @override
  String get photosShareExpiry30d => '30天';

  @override
  String get photosShareExpiryNever => '永不过期';

  @override
  String get photosExistingShareLinks => '现有分享链接';

  @override
  String photosShareAccessCount(Object count) {
    return '访问 $count 次';
  }

  @override
  String get photosCreateLink => '创建链接';

  @override
  String photosShareLinkCreated(Object token) {
    return '分享链接已创建: $token';
  }

  @override
  String get photosShareLinkFailed => '创建分享链接失败';

  @override
  String get photosRemoveFromAlbum => '从相册移除';

  @override
  String photosRemoveFromAlbumConfirm(Object title) {
    return '确定要将「$title」从相册中移除吗？照片本身不会被删除。';
  }

  @override
  String get photosRemove => '移除';

  @override
  String photosRemovedFromAlbum(Object title) {
    return '已将「$title」从相册移除';
  }

  @override
  String photosAlbumPhotoCountLabel(Object count) {
    return '$count 张照片';
  }

  @override
  String get photosDeleteAlbumTooltip => '删除相册';

  @override
  String get photosAllPhotos => '全部照片';

  @override
  String get photosNoGroupData => '暂无分组数据';

  @override
  String get photosBrightness => '亮度';

  @override
  String get photosContrast => '对比度';

  @override
  String get photosCrop => '裁剪';

  @override
  String get photosRotate => '旋转';

  @override
  String get photosFilter => '滤镜';

  @override
  String get photosFilterOriginal => '原图';

  @override
  String get photosFilterGrayscale => '黑白';

  @override
  String get photosFilterSepia => '复古';

  @override
  String get photosFilterBlur => '模糊';

  @override
  String get photosFilterSharpen => '锐化';

  @override
  String get musicDeckTitle => '音乐空间';

  @override
  String get musicDeckHome => '首页';

  @override
  String get musicDeckLibrary => '曲库';

  @override
  String get musicDeckPlaylists => '歌单';

  @override
  String get musicDeckFavorites => '收藏';

  @override
  String get musicDeckRecent => '最近播放';

  @override
  String get musicDeckOffline => '离线内容';

  @override
  String get musicDeckLocalManagement => '本地资源';

  @override
  String get musicDeckMore => '更多';

  @override
  String get musicDeckSources => '来源';

  @override
  String get musicDeckSourceLocal => '本地';

  @override
  String get musicDeckSourceNetease => '网易云';

  @override
  String get musicDeckSourceQq => 'QQ 音乐';

  @override
  String get musicDailyRecommendationSection => '今日推荐';

  @override
  String get musicDailyRecommendationTitle => '每日推荐歌曲';

  @override
  String musicDailyRecommendationTrackCount(Object count) {
    return '共 $count 首 · 每日更新';
  }

  @override
  String get musicLibraryAlbumsEmptyTitle => '还没有专辑';

  @override
  String get musicLibraryAlbumsEmptyMessage => '导入本地音乐或连接在线平台后，专辑会出现在这里。';

  @override
  String get musicLibraryArtistsEmptyTitle => '还没有艺人';

  @override
  String get musicLibraryArtistsEmptyMessage => '导入本地音乐或连接在线平台后，艺人会出现在这里。';

  @override
  String get musicDailyRecommendationEmpty => '今日推荐暂不可用，请稍后再试';

  @override
  String get musicDailyRecommendationLoadFailed => '加载每日推荐失败，请稍后重试';

  @override
  String get musicDeckAccounts => '平台账号';

  @override
  String get musicDeckManageAccounts => '管理平台账号';

  @override
  String get musicDeckManage => '管理';

  @override
  String get musicLocalManagementSubtitle => '管理本地歌曲信息、封面、歌词和存储扫描。';

  @override
  String get musicStartScan => '扫描存储';

  @override
  String get musicCreatePlaylist => '新建歌单';

  @override
  String get musicPlaylistName => '歌单名称';

  @override
  String get musicPlaylistDescription => '描述';

  @override
  String get musicCreate => '创建';

  @override
  String get musicEditPlaylist => '编辑歌单';

  @override
  String get musicDeletePlaylist => '删除歌单';

  @override
  String get musicDeleteLocalTrack => '删除本地歌曲';

  @override
  String get musicDeleteLocalTrackTitle => '永久删除本地歌曲？';

  @override
  String musicDeleteLocalTrackMessage(Object title) {
    return '「$title」及其源文件将被永久删除，此操作无法撤销。';
  }

  @override
  String get musicDeleteLocalTrackSuccess => '本地歌曲已永久删除';

  @override
  String get musicDeleteLocalTrackFailed => '删除失败，请稍后重试';

  @override
  String get musicDeletePlaylistTitle => '删除这个歌单？';

  @override
  String musicDeletePlaylistMessage(Object name) {
    return '确定要删除「$name」吗？歌单内的歌曲不会被删除。';
  }

  @override
  String get musicPlaylistCoverPick => '选择封面';

  @override
  String get musicPlaylistCoverChange => '更换封面';

  @override
  String get musicPlaylistCoverHint => '未选择时使用第一首歌曲的封面';

  @override
  String musicPlaylistSaveFailed(Object error) {
    return '歌单保存失败：$error';
  }

  @override
  String musicPlaylistDeleteFailed(Object error) {
    return '歌单删除失败：$error';
  }

  @override
  String get musicDeckConnectedSources => '已连接来源';

  @override
  String get musicDeckSearchPrompt => '输入至少两个字符，按歌曲、歌手或专辑筛选';

  @override
  String get musicDeckNoSearchResults => '没有匹配的歌曲';

  @override
  String get musicDeckSelectTrack => '选择一首歌曲开始播放';

  @override
  String get musicDeckPrevious => '上一首';

  @override
  String get musicDeckNext => '下一首';

  @override
  String get musicDeckNowPlaying => '正在播放';

  @override
  String get musicDeckLibraryReady => '曲库已就绪';

  @override
  String musicDeckLibrarySummary(Object trackCount, Object albumCount) {
    return '$trackCount 首歌曲 · $albumCount 张专辑';
  }

  @override
  String musicDeckTrackCount(Object count) {
    return '$count 首歌曲';
  }

  @override
  String get musicDeckContinueListening => '继续聆听';

  @override
  String get musicDeckYourCollections => '你的歌单';

  @override
  String get musicDeckRecentEmpty => '播放歌曲后，最近内容会显示在这里。';

  @override
  String get musicDeckPartialSourceFailure => '部分在线来源暂时不可用，本地曲库和其他来源仍可继续使用。';

  @override
  String get musicDeckLibrarySubtitle => '浏览本地曲库与账号范围内已知的在线歌曲。';

  @override
  String get musicDeckPlaylistsSubtitle => '本地歌单与已连接平台歌单在同一空间中分区呈现。';

  @override
  String get musicDeckFavoritesSubtitle => '汇总本地收藏与已连接平台的喜欢歌曲。';

  @override
  String get musicDeckRecentSubtitle => '继续播放最近访问的本地内容。';

  @override
  String get musicDeckLocalPlaylist => '本地歌单';

  @override
  String get musicDeckOfflineSubtitle => '管理已下载到当前设备、断网后仍可播放的内容。';

  @override
  String get musicDeckOfflineEmpty => '当前还没有可离线播放的音乐。离线下载将在后续下载管理能力接入后显示。';

  @override
  String get musicDeckRetry => '重试';

  @override
  String get musicNavSongs => '歌曲';

  @override
  String get musicNavAlbums => '专辑';

  @override
  String get musicNavArtists => '艺人';

  @override
  String get musicNavPlaylists => '歌单';

  @override
  String get musicNavFavorites => '收藏';

  @override
  String get musicSearch => '搜索';

  @override
  String get musicSearchTitle => '搜索音乐';

  @override
  String get musicSearchHint => '输入歌曲名、歌手或专辑';

  @override
  String get musicClose => '关闭';

  @override
  String get musicGotIt => '知道了';

  @override
  String get musicPlaybackError => '音频播放失败，可能不支持该音频编码格式';

  @override
  String get musicCancel => '取消';

  @override
  String get musicSave => '保存';

  @override
  String get musicSaving => '保存中...';

  @override
  String get musicEdit => '编辑';

  @override
  String get musicApply => '应用';

  @override
  String get musicApplying => '应用中';

  @override
  String get musicNoLyrics => '暂无歌词';

  @override
  String get musicNowPlayingArtwork => '封面';

  @override
  String get musicNowPlayingLyrics => '歌词';

  @override
  String get musicEditMetadata => '编辑元数据';

  @override
  String get musicTitleRequired => '标题不能为空';

  @override
  String get musicMetadataSaved => '元数据已保存';

  @override
  String musicSaveFailed(Object error) {
    return '保存失败: $error';
  }

  @override
  String get musicFieldTitle => '标题';

  @override
  String get musicFieldArtist => '艺术家';

  @override
  String get musicFieldAlbum => '专辑';

  @override
  String get musicFieldGenre => '风格';

  @override
  String get musicCoverImage => '封面图片';

  @override
  String musicCoverSelected(Object name) {
    return '已选择: $name';
  }

  @override
  String get musicCoverPick => '选择封面图片';

  @override
  String get musicLyricsFile => '歌词文件';

  @override
  String get musicLyricsPick => '选择歌词文件（LRC / TXT / SRT / VTT）';

  @override
  String musicAddToPlaylistSuccess(Object name) {
    return '已加入「$name」';
  }

  @override
  String get musicAddToPlaylistFailed => '加入歌单失败';

  @override
  String get musicScrapeMatch => '在线匹配';

  @override
  String get musicScrapeCandidatesTitle => '匹配候选';

  @override
  String get musicScrapeNoCandidates => '未找到匹配候选';

  @override
  String get musicScrapeApply => '应用';

  @override
  String get musicScrapeApplied => '已应用匹配元数据';

  @override
  String get musicScrapeLibrary => '全库重刮';

  @override
  String get musicScrapeLibraryConfirmTitle => '确认全库重刮';

  @override
  String get musicScrapeLibraryConfirmMessage =>
      '将对所有本地曲目重新匹配在线元数据，包括已刮削的曲目。是否继续？';

  @override
  String get musicQualityHint => '按已连接平台支持的档位自动降级播放';

  @override
  String get musicQualityUnsupported => '当前平台不支持';

  @override
  String get musicQualityTitle => '播放音质';

  @override
  String get musicQualityJymaster => '超清母带';

  @override
  String get musicQualityJyeffect => '高清环绕声';

  @override
  String get musicQualitySky => '沉浸环绕声';

  @override
  String get musicQualityDolby => '杜比全景声';

  @override
  String get musicQualityHires => 'Hi-Res';

  @override
  String get musicQualityLossless => '无损';

  @override
  String get musicQualityExhigh => '极高';

  @override
  String get musicQualityHigher => '较高';

  @override
  String get musicQualityStandard => '标准';

  @override
  String get musicPlatformLoginTitle => '平台账号';

  @override
  String get musicPlatformNeteaseName => '网易云音乐';

  @override
  String get musicPlatformNeteaseQrHint => '使用网易云音乐 App 扫码登录';

  @override
  String get musicPlatformQrGenerating => '正在生成二维码…';

  @override
  String get musicPlatformQrAction => '扫码登录';

  @override
  String get musicPlatformQqName => 'QQ 音乐';

  @override
  String get musicPlatformQqCookieRequired => '请粘贴 QQ 音乐 Cookie';

  @override
  String musicPlatformQqVerifyFailed(Object error) {
    return '验证失败：$error';
  }

  @override
  String get musicPlatformQqCookieHint =>
      '请先在浏览器登录 y.qq.com，再复制完整 Cookie 粘贴到下方。';

  @override
  String get musicPlatformQqCookieKeyHint =>
      '必须包含 qm_keyst 或 qqmusic_key 才能播放。';

  @override
  String get musicPlatformQqCookiePlaceholder => '在此粘贴 Cookie…';

  @override
  String get musicPlatformQqVerifying => '正在验证…';

  @override
  String get musicPlatformQqVerifyAction => '验证并保存';

  @override
  String get musicPlatformAnonymousUser => '用户';

  @override
  String get musicPlatformVipBadge => 'VIP';

  @override
  String musicPlatformUserId(Object userId) {
    return 'ID: $userId';
  }

  @override
  String get musicPlatformLogout => '退出登录';

  @override
  String get musicHistoryTitle => '播放历史';

  @override
  String get musicHistoryEmpty => '最近 7 天没有播放记录';

  @override
  String get musicHistoryLoadMore => '加载更多';

  @override
  String get musicHistoryToday => '今天';

  @override
  String get musicHistoryYesterday => '昨天';

  @override
  String get musicHistoryViewAll => '查看全部';

  @override
  String get musicLyricsSearch => '搜索歌词';

  @override
  String get musicLyricsApply => '应用歌词';

  @override
  String get musicLyricsNoResult => '未找到匹配歌词';

  @override
  String get musicLyricsOnlineSource => '在线歌词';

  @override
  String musicLyricsApplied(Object title) {
    return '歌词已应用到「$title」';
  }

  @override
  String get musicScanConfirmMessage => '将扫描音乐目录中的音频文件并入库，已有文件会被跳过或更新。';

  @override
  String get musicScanPollTimeout => '任务仍在后台执行，进度展示已停止，可稍后刷新查看。';

  @override
  String musicSelectionCount(Object count) {
    return '已选 $count 项';
  }

  @override
  String get musicSelectionSelectAll => '全选';

  @override
  String get musicSelectionExit => '退出多选';

  @override
  String musicBatchAddedToPlaylist(Object count, Object name) {
    return '已将 $count 首曲目加入「$name」';
  }

  @override
  String musicBatchPartial(Object success, Object failed) {
    return '$success 首成功，$failed 首失败';
  }

  @override
  String musicBatchEnqueued(Object count) {
    return '已将 $count 首曲目加入播放队列';
  }

  @override
  String get musicPlaybackSettings => '播放设置';

  @override
  String get musicSleepTimer => '定时关闭';

  @override
  String musicSleepMinutes(Object minutes) {
    return '$minutes 分钟';
  }

  @override
  String get musicSleepAfterCurrentTrack => '播完当前曲';

  @override
  String get musicSleepOff => '关闭定时';

  @override
  String musicSleepRemaining(Object minutes, Object seconds) {
    return '剩余 $minutes:$seconds 后暂停播放';
  }

  @override
  String get musicPlaybackSpeed => '播放倍速';

  @override
  String get musicSpeedApplyHint => '切换档位对当前曲目立即生效';

  @override
  String get musicNavGenres => '流派';

  @override
  String get musicGenresEmpty => '本地曲目暂无流派信息，可在元数据编辑中补充';

  @override
  String get musicGenresPickHint => '选择一个流派查看曲目';

  @override
  String get taskNotifyTitleCompleted => '任务完成';

  @override
  String get taskNotifyTitleFailed => '任务失败';

  @override
  String get profileTaskSystemNotifications => '系统通知';

  @override
  String get profileTaskSystemNotificationsHint => '任务完成或失败时发送系统通知';

  @override
  String get batteryOptimizationTitle => '允许后台运行';

  @override
  String get batteryOptimizationHint => '将本应用加入电池优化白名单，避免后台备份被系统拦截';

  @override
  String get batteryOptimizationGranted => '已允许后台运行';

  @override
  String get batteryOptimizationAllow => '去允许';

  @override
  String get settingsCheckUpdate => '检查更新';

  @override
  String settingsCheckUpdateFailed(Object error) {
    return '检查更新失败：$error';
  }

  @override
  String get settingsAlreadyLatest => '已是最新版本';

  @override
  String settingsNewVersionFound(Object version) {
    return '发现新版本 $version';
  }

  @override
  String get settingsOpenDownloadPage => '打开下载页';

  @override
  String get filesOpRefresh => '刷新文件列表';

  @override
  String get filesOpSwitchSpace => '切换空间';

  @override
  String get filesOpLoadRecent => '加载最近文件';

  @override
  String get filesOpLoadFavorites => '加载收藏文件';

  @override
  String get filesOpLoadRecycleBin => '加载回收站';

  @override
  String get filesOpLoadShared => '加载共享文件';

  @override
  String get filesOpLoadSharedSpace => '加载共享空间';

  @override
  String get filesOpOpenSharedFolder => '打开共享空间文件夹';

  @override
  String get filesOpNavigateSharedUp => '返回共享空间上级';

  @override
  String get filesOpMoveToSharedSpace => '移到共享空间';

  @override
  String get filesOpMoveToPersonalSpace => '移到个人空间';

  @override
  String get filesOpCreateSharedFolder => '创建共享空间文件夹';

  @override
  String get filesOpDeleteSharedFile => '删除共享空间文件';

  @override
  String get filesOpLoadMyShares => '加载我的分享';

  @override
  String get filesOpLoadShareLinks => '加载分享链接';

  @override
  String get filesOpLoadStorageStats => '加载存储统计';

  @override
  String get filesOpLoadUploadQueue => '加载上传队列';

  @override
  String get filesOpLoadOfflineDownloads => '加载离线下载';

  @override
  String get filesOpLoadExternalStorage => '加载外部存储';

  @override
  String get filesOpOpenFolder => '打开文件夹';

  @override
  String get filesOpNavigateToRoot => '返回根目录';

  @override
  String get filesOpChangeDirectory => '切换目录';

  @override
  String get filesOpFilterFileType => '筛选文件类型';

  @override
  String get filesOpLoadMore => '加载更多文件';

  @override
  String get filesOpCreateFolder => '新建文件夹';

  @override
  String get filesOpRename => '重命名文件';

  @override
  String get filesOpCopy => '复制文件';

  @override
  String get filesOpMove => '移动文件';

  @override
  String get filesOpMoveToRecycleBin => '移入回收站';

  @override
  String get filesOpRestore => '恢复文件';

  @override
  String get filesOpPurge => '彻底删除';

  @override
  String get filesOpAddFavorite => '添加收藏';

  @override
  String get filesOpRemoveFavorite => '取消收藏';

  @override
  String get filesOpBatchMoveToRecycleBin => '批量移入回收站';

  @override
  String get filesOpBatchRestore => '批量恢复';

  @override
  String get filesOpBatchPurge => '批量彻底删除';

  @override
  String get filesOpBatchMove => '批量移动';

  @override
  String get filesOpBatchAddFavorite => '批量添加收藏';

  @override
  String get filesOpBatchRemoveFavorite => '批量取消收藏';

  @override
  String get filesOpCreateShareLink => '创建分享链接';

  @override
  String get filesOpRevokeShare => '撤销分享';

  @override
  String get filesOpUpload => '上传文件';

  @override
  String get filesOpResumeUpload => '继续上传';

  @override
  String get filesOpDeleteUploadTask => '删除上传任务';

  @override
  String get filesOpCreateOfflineDownload => '新建离线下载';

  @override
  String get filesOpCancelOfflineDownload => '取消离线下载';

  @override
  String get filesOpAddExternalStorage => '添加外部存储';

  @override
  String get filesOpDisableExternalStorage => '禁用外部存储';

  @override
  String get filesOpDeleteMount => '删除挂载';

  @override
  String get filesOpUpdateExternalStorage => '更新外部存储';

  @override
  String get filesOpBrowseRemoteDirectory => '浏览远程目录';

  @override
  String get filesOpOpenRemoteSubdirectory => '打开远程子目录';

  @override
  String get filesOpMkdirExternalStorage => '创建远程目录';

  @override
  String get filesOpDeleteExternalFile => '删除远程文件';

  @override
  String get filesOpRenameExternalFile => '重命名远程文件';

  @override
  String get filesOpCreateImportTask => '创建导入任务';

  @override
  String get filesOpLoadImportTasks => '加载导入任务';

  @override
  String get filesOpCancelImportTask => '取消导入任务';

  @override
  String get filesOpDeleteImportTask => '删除导入任务';

  @override
  String get filesOpImportMedia => '导入媒体';

  @override
  String get filesOpDeleteFile => '删除文件';

  @override
  String get musicQueueTitle => '播放队列';

  @override
  String get musicQueueEmpty => '播放队列为空';

  @override
  String get musicQueueClear => '清空队列';

  @override
  String get musicPlayNext => '下一首播放';

  @override
  String get musicQueueReorderHint => '拖动调整播放顺序';

  @override
  String get musicPlayNextAdded => '已加入播放队列';

  @override
  String get musicShuffle => '随机播放';

  @override
  String get musicRepeatOff => '顺序播放';

  @override
  String get musicRepeatAll => '列表循环';

  @override
  String get musicRepeatOne => '单曲循环';

  @override
  String get musicPlaylistsSubtitle => '管理你创建的本地播放列表。';

  @override
  String get musicPlaylistsEmptyHint => '创建歌单后可在这里集中管理。';

  @override
  String get musicOpenPlaylist => '打开歌单';

  @override
  String get musicPlaylistEmptyHint => '从歌曲列表中添加歌曲后会显示在这里。';

  @override
  String get musicAlbumNoTracks => '该专辑下暂无歌曲。';

  @override
  String get musicArtistNoTracks => '该艺术家下暂无歌曲。';

  @override
  String get musicRemoveFromPlaylist => '移出歌单';

  @override
  String musicViewAll(Object count) {
    return '查看全部 ($count)';
  }

  @override
  String get musicPause => '暂停';

  @override
  String get musicPlay => '播放';

  @override
  String get musicNotPlaying => '未播放';

  @override
  String get musicRecommendedArtist => '推荐艺术家';

  @override
  String get musicExploreMusic => '探索音乐';

  @override
  String get musicPlayNow => '立即播放';

  @override
  String get musicTrendingArtists => '热门艺术家';

  @override
  String get musicViewAllSimple => '查看全部';

  @override
  String get musicNoTracks => '暂无曲目';

  @override
  String get musicTracksHint => '音乐扫描完成后，歌曲会出现在这里。';

  @override
  String get musicAddToPlaylist => '加入歌单';

  @override
  String get musicUnfavorite => '取消收藏';

  @override
  String get musicFavorite => '收藏';

  @override
  String get musicNoAlbums => '暂无专辑';

  @override
  String get musicAlbumsHint => '扫描音乐后会自动按专辑聚合。';

  @override
  String get musicAlbumsSubtitle => '按专辑浏览你的本地音乐库。';

  @override
  String get musicArtistsSubtitle => '按艺术家聚合歌曲与专辑。';

  @override
  String get musicNoArtists => '暂无艺术家';

  @override
  String get musicArtistsHint => '歌曲标签解析后会显示艺术家。';

  @override
  String musicSidebarViewAll(Object count) {
    return '查看全部 ($count)';
  }

  @override
  String get musicScanSubtitle => '扫描文件库中的音频文件，解析标签、专辑、艺术家和封面。';

  @override
  String get musicNoScanTask => '当前没有新扫描任务。';

  @override
  String musicScanStatus(
    Object id,
    Object status,
    Object progress,
    Object files,
  ) {
    return '任务 $id · $status · $progress% · 已扫描 $files 个文件';
  }

  @override
  String get musicMetadataSubtitle => '集中检查歌曲标题、艺术家、专辑和音质标签。';

  @override
  String get musicNoMetadataHint => '音乐扫描完成后，可以在这里补全 MusicBrainz 元数据。';

  @override
  String get musicCandidate => '候选';

  @override
  String get musicBrainzCandidates => 'MusicBrainz 候选';

  @override
  String get musicCandidateFetchFailed => '候选获取失败';

  @override
  String get musicNoCandidates => '没有找到候选';

  @override
  String get musicNoCandidatesHint => '可以先完善本地标题、歌手或专辑，再重新尝试。';

  @override
  String get backupSkipNonWifi => '非 WiFi 网络，跳过备份';

  @override
  String get backupSkipNoPermission => '未获得相册访问权限';

  @override
  String get backupSkipNoAlbums => '无相册';

  @override
  String get backupSkipNoPhotos => '无照片';

  @override
  String get backupNotificationChannel => '照片备份';

  @override
  String get backupNotificationChannelDesc => '照片自动备份进度';

  @override
  String get backupNotificationTitle => '照片备份中';

  @override
  String backupNotificationProgress(
    Object current,
    Object total,
    Object uploaded,
  ) {
    return '已处理 $current/$total，已上传 $uploaded 张';
  }

  @override
  String get backupNotificationComplete => '照片备份完成';

  @override
  String backupNotificationSummary(
    Object uploaded,
    Object skipped,
    Object failed,
  ) {
    return '上传 $uploaded 张，跳过 $skipped 张，失败 $failed 张';
  }

  @override
  String get photoRegenerateThumbnails => '重建缩略图';

  @override
  String get photoRegenerateQueued => '缩略图重建任务已创建，可在任务中心查看进度';

  @override
  String get photosActionFailed => '操作失败，请稍后重试';

  @override
  String get photoImportCandidates => '导入候选';

  @override
  String get photoNoImportCandidates => '暂无待导入的图片';

  @override
  String get importFiles => '导入文件';

  @override
  String get importToPersonalSpace => '个人空间';

  @override
  String get importToSharedSpace => '共享空间';

  @override
  String get importSpaceSelectorTitle => '选择导入位置';

  @override
  String get importSpaceSelectorDesc => '选择文件导入到哪个空间';

  @override
  String get importPersonalSpaceDesc => '仅自己可见';

  @override
  String get importSharedSpaceDesc => '所有用户可见';

  @override
  String get importUploading => '导入中...';

  @override
  String importComplete(Object count) {
    return '已导入 $count 个文件';
  }

  @override
  String get importFailed => '导入失败';

  @override
  String get importRefreshFailed => '文件已导入，但列表刷新失败。';

  @override
  String importProcessing(Object count) {
    return '已上传 $count 个文件，仍在处理中，请稍后刷新。';
  }

  @override
  String importUnsupportedFormat(Object files, Object extensions) {
    return '不支持以下文件格式：$files。支持格式：$extensions。';
  }

  @override
  String get readerPortal => 'Portal';

  @override
  String get readerCenter => '阅读中心';

  @override
  String get readerSortRecent => '最近阅读';

  @override
  String get readerSortTitle => '标题';

  @override
  String get readerTypeNovel => '小说';

  @override
  String get readerTypeLiterature => '文学';

  @override
  String get readerTypeAcademic => '学术';

  @override
  String get readerTypeTechnical => '技术';

  @override
  String get readerTypePoetry => '诗歌';

  @override
  String get readerTypeEssay => '散文';

  @override
  String get readerTypeComic => '漫画';

  @override
  String get readerNotStarted => '未开始';

  @override
  String get readerUnknownTime => '未知时间';

  @override
  String readerChapterNumber(Object number) {
    return '第 $number 章';
  }

  @override
  String readerProgressLabel(Object progress) {
    return '进度 $progress';
  }

  @override
  String get readerRestoreProgress => '恢复阅读进度';

  @override
  String get readerRestoreProgressConfirm => '确定要恢复到此版本的阅读进度吗？当前进度将被覆盖。';

  @override
  String get readerConfirmRestore => '确定恢复';

  @override
  String get readerProgressRestored => '阅读进度已恢复';

  @override
  String readerRestoreFailed(Object error) {
    return '恢复失败: $error';
  }

  @override
  String get readerVersionHistory => '版本历史';

  @override
  String get readerNoVersionHistory => '暂无版本记录';

  @override
  String get readerVersionHistoryHint => '阅读进度变更后会自动记录版本';

  @override
  String get readerRestoreThisVersion => '恢复此版本';

  @override
  String get videoImportSubtitle => '导入字幕文件';

  @override
  String get videoImportedSubtitle => '导入的字幕';

  @override
  String get videoLocalSubtitle => '本地字幕';

  @override
  String get videoSubtitleImportSuccess => '字幕已载入';

  @override
  String get videoSubtitleImportFailed => '无法读取字幕文件';

  @override
  String get videoSubtitleFileTooLarge => '字幕文件不能超过 2 MB';

  @override
  String get videoSubtitleNoCues => '字幕文件中没有可识别的时间轴内容';

  @override
  String videoAudioTrackNumber(int index) {
    return '音轨 $index';
  }

  @override
  String videoLanguageTrackNumber(int index) {
    return '语言 $index';
  }

  @override
  String videoSubtitleTrackNumber(int index) {
    return '字幕轨道 $index';
  }

  @override
  String get videoMute => '静音';

  @override
  String get videoUnmute => '取消静音';

  @override
  String get videoPause => '暂停';

  @override
  String get videoEnterFullscreen => '进入全屏';

  @override
  String get videoExitFullscreen => '退出全屏';

  @override
  String videoSeekBackwardSeconds(int seconds) {
    return '快退 $seconds 秒';
  }

  @override
  String videoSeekForwardSeconds(int seconds) {
    return '快进 $seconds 秒';
  }

  @override
  String get videoNoAudioTracks => '没有可用音轨';

  @override
  String get videoSelectAudioTrack => '选择音轨';

  @override
  String get videoNoLanguages => '没有可用语言';

  @override
  String get videoSelectLanguage => '选择语言';

  @override
  String videoVolumeValue(int volume) {
    return '音量 $volume%';
  }

  @override
  String videoVolumeMutedValue(int volume) {
    return '音量 $volume%（已静音）';
  }

  @override
  String videoSeasonEpisodeLabel(int season, int episode) {
    return '第 $season 季 · 第 $episode 集';
  }

  @override
  String get videoHeroFeatured => '精选';

  @override
  String get videoHeroMovie => '电影';

  @override
  String get videoHeroTv => '剧集';

  @override
  String get videoHeroWatchNow => '立即播放';

  @override
  String get videoHeroFallbackOverview => '本地影片已准备好播放。';

  @override
  String get videoHeroCenterTitle => '媒体库';

  @override
  String get videoHeroCenterSubtitle => '选择影片以查看详情并开始播放。';

  @override
  String get filePurgeDeleteTitle => '永久删除？';

  @override
  String filePurgeDeleteMessage(String name) {
    return '是否删除“$name”及其存储文件？此操作无法撤销。';
  }

  @override
  String get filePurgeImpactTitle => '文件仍被其他内容使用';

  @override
  String filePurgeImpactMessage(int fileCount, int referenceCount) {
    return '本次操作将影响 $fileCount 个文件节点和其他模块中的 $referenceCount 个引用。是否继续级联删除？';
  }

  @override
  String get filePurgeCascadeDelete => '删除全部引用';

  @override
  String get videoLocalLibrarySources => '本地直连媒体库';

  @override
  String get videoLocalLibrarySourcesSubtitle =>
      '直接引用部署白名单内的只读目录，原始影片不会复制到 MinIO。';

  @override
  String get videoLibrarySourcesTitle => '媒体来源';

  @override
  String videoLibrarySourceCount(int count) {
    return '$count 个来源';
  }

  @override
  String get videoLibraryLoading => '正在加载媒体库';

  @override
  String get videoRefreshSources => '刷新媒体库来源';

  @override
  String get videoAddLibrarySource => '添加来源';

  @override
  String get videoEditLibrarySource => '编辑来源';

  @override
  String get videoStorageLocationUnavailable => '存储位置加载失败';

  @override
  String get videoNoStorageLocation => '没有可用的本地存储位置';

  @override
  String get videoNoStorageLocationHint => '请先由系统管理员在存储管理中配置并启用本地只读挂载。';

  @override
  String get videoLoadSourcesFailed => '影视库来源加载失败';

  @override
  String get videoNoLibrarySources => '尚未配置本地媒体库来源。';

  @override
  String get videoLibraryType => '媒体库类型';

  @override
  String get videoLibraryTypeHint => '类型决定扫描器和归类层级；已有来源不可直接更改。';

  @override
  String get videoLibraryTypeMovie => '电影';

  @override
  String get videoLibraryTypeTvSeries => '剧集';

  @override
  String get videoLibraryTypeAnime => '动漫';

  @override
  String get videoLibraryTypeRoot => '混合根目录';

  @override
  String get videoStorageAvailable => '可用';

  @override
  String get videoStorageUnavailable => '不可用';

  @override
  String get videoStorageDisabled => '已停用';

  @override
  String get videoDeleteLibrarySource => '删除媒体来源';

  @override
  String videoDeleteLibrarySourceConfirm(String name) {
    return '确定删除来源“$name”吗？已入库媒体不会被删除，存在媒体引用时操作会被拒绝。';
  }

  @override
  String get videoDeleteLibrarySourceDone => '媒体来源已删除';

  @override
  String get videoUnknownStorageLocation => '未知存储位置';

  @override
  String videoSourceScanSummary(int count, int created) {
    return '上次发现 $count 个视频，待审核 $created 项';
  }

  @override
  String videoSourceMissingCount(int count) {
    return '不可用 $count 项';
  }

  @override
  String get videoSourceDisabled => '已停用';

  @override
  String get videoScanThisSource => '发现更新';

  @override
  String get videoReviewLibrarySource => '查看发现结果并按需加入媒体库';

  @override
  String get videoBrowseRelativeDirectory => '浏览安全目录';

  @override
  String get videoChooseThisDirectory => '选择此目录';

  @override
  String get videoDirectoryRoot => '根目录';

  @override
  String get videoSourceFromMount => '从挂载点直达';

  @override
  String get videoTrustedMountLabel => '挂载点';

  @override
  String get videoNoTrustedMount => '暂无可用挂载点';

  @override
  String get videoNoTrustedMountHint => '请先在部署配置登记挂载并确认其可用，创建时会自动登记挂载根为存储位置。';

  @override
  String get videoBrowseMountDirectory => '浏览挂载目录';

  @override
  String get videoDiscoveryTitle => '发现与入库';

  @override
  String get videoReviewSelectionHint => '按系列、季度或单集选择，确认后才会写入正式媒体库。';

  @override
  String get videoLocalDiscoveryTask => '本地媒体发现';

  @override
  String get videoLocalImportTask => '所选媒体入库';

  @override
  String get videoAwaitingReview => '等待审核';

  @override
  String get videoDiscoveryEmpty => '尚无发现结果。先运行“发现更新”，系统只生成候选，不会立即入库。';

  @override
  String get videoDiscoveryRunning => '正在发现媒体文件，离开页面不会中断后台任务。';

  @override
  String get videoDiscoveryFailed => '发现任务失败，请检查来源健康状态后重试。';

  @override
  String get videoDiscoveryCancelled => '发现或入库任务已取消。';

  @override
  String videoDiscoveryCandidates(int count) {
    return '候选 $count 项';
  }

  @override
  String videoDiscoverySelected(int count) {
    return '已选择 $count 项';
  }

  @override
  String videoDiscoveryIssues(int count) {
    return '异常 $count 项';
  }

  @override
  String get videoSelectAllCandidates => '全选候选';

  @override
  String get videoClearCandidateSelection => '清除选择';

  @override
  String get videoAddSelectedToLibrary => '加入媒体库';

  @override
  String get videoPauseImport => '暂停入库';

  @override
  String get videoCancelDiscovery => '取消任务';

  @override
  String get videoBackToParentNode => '返回上一级';

  @override
  String get videoLoadTreeFailed => '候选树加载失败';

  @override
  String get videoNoCandidates => '当前层级没有候选项。';

  @override
  String get videoCandidateExisting => '已入库';

  @override
  String get videoCandidateChanged => '文件已变化';

  @override
  String get videoCandidateUnmatched => '无法识别';

  @override
  String get videoCandidateNew => '新候选';

  @override
  String get videoUnavailableTitle => '不可用项目';

  @override
  String get videoLibraryRecordsExpand => '展开更多记录';

  @override
  String get videoLibraryRecordsCollapse => '收起记录';

  @override
  String get photosPrevPhoto => '上一张';

  @override
  String get photosNextPhoto => '下一张';

  @override
  String get videoUnavailableEmpty => '当前没有缺失或不可读取的本地媒体。';

  @override
  String videoUnavailableCount(int count) {
    return '$count 项需要处理';
  }

  @override
  String get videoUnavailableLoadFailed => '不可用项目加载失败';

  @override
  String get videoMissingPending => '等待缺失确认';

  @override
  String get videoMissingConfirmed => '文件缺失';

  @override
  String get videoFileUnavailable => '文件不可用';

  @override
  String get videoSourceOffline => '来源离线';

  @override
  String get videoSourceDegraded => '部分异常';

  @override
  String get videoSourceName => '来源名称';

  @override
  String get videoStorageLocation => '存储位置';

  @override
  String get videoSelectLibrarySource => '选择库源';

  @override
  String get videoNoAvailableStorageLocation => '暂无可用存储位置';

  @override
  String get videoNoAvailableStorageLocationHint => '请先添加本地存储位置并确保已启用，再创建库源。';

  @override
  String get videoRelativeDirectory => '相对目录';

  @override
  String get videoRelativeDirectoryHint => '仅填写存储位置内的相对路径，例如 Movies/4K';

  @override
  String get videoSourceEnabled => '启用此来源';

  @override
  String get videoSourceRequiredFields => '请填写来源名称和相对目录';

  @override
  String get videoNeverScanned => '未扫描';

  @override
  String get adminAddLocalStorageLocation => '添加挂载位置';

  @override
  String get adminLocalStorageLocations => '本地存储位置';

  @override
  String get adminReadOnlyMediaMounts => '只读媒体挂载';

  @override
  String get adminLocalStorageLocationsSubtitle =>
      '仅登记部署白名单中的挂载键和相对目录，不保存宿主机绝对路径。';

  @override
  String get adminNoLocalStorageLocations => '尚未配置本地只读存储位置。';

  @override
  String get adminDeleteLocalStorageLocation => '删除存储位置';

  @override
  String get adminMountKey => '挂载键';

  @override
  String get adminMountKeyHint =>
      '必须与 application.yml 中 file.local-media.mounts 的键一致';

  @override
  String get adminAutoCreateLibrarySource => '同时创建影视库源';

  @override
  String get adminAutoCreateLibrarySourceHint =>
      '创建挂载位置后自动建立对应的影视库来源，无需再单独配置一次';

  @override
  String get adminRelativeRoot => '相对根目录';

  @override
  String get adminRelativeRootHint => '填写挂载点内部目录，根目录使用 .';

  @override
  String get adminLocalStorageSecurityHint => '绝对路径由部署环境配置，界面只能选择受控挂载内的相对目录。';

  @override
  String get adminLocalStorageRequiredFields => '请填写名称、挂载键和相对根目录';

  @override
  String get adminCancel => '取消';

  @override
  String get photosTaskNotFound => '该任务已不存在或无权访问。';

  @override
  String get photosTaskMonitorTimedOut => '状态监控已超时，后台任务可能仍在运行。';

  @override
  String get photosRetryStatus => '重试状态';

  @override
  String get musicQrLoginTitle => '登录网易云音乐';

  @override
  String get musicQrLoginInstruction => '打开网易云音乐 App，扫描此二维码。';

  @override
  String get musicQrWaiting => '等待扫码…';

  @override
  String get musicQrScanned => '已扫码，请在手机上确认';

  @override
  String get musicQrExpired => '二维码已过期，请重新发起登录获取新二维码。';

  @override
  String get musicQrStatusFailed => '登录状态刷新失败，请检查网络后重试。';

  @override
  String get musicQrRetry => '重试';

  @override
  String musicQrUnknownStatus(String status) {
    return '状态：$status';
  }

  @override
  String get videoLibraryOverviewTab => '概览';

  @override
  String get videoLibraryScanReviewTab => '扫描与审核';

  @override
  String get videoLibraryAccessTab => '访问权限';

  @override
  String get videoLibraryVisibilityPrivate => '私人';

  @override
  String get videoLibraryVisibilityPrivateHint => '仅创建者可在消费页面查看，管理员仍可在此管理。';

  @override
  String get videoLibraryVisibilitySelected => '指定用户';

  @override
  String get videoLibraryVisibilitySelectedHint => '只有下方选中的用户可以查看和播放。';

  @override
  String get videoLibraryVisibilityMembers => '全部成员';

  @override
  String get videoLibraryVisibilityMembersHint =>
      '具有媒体读取权限的成员和管理员可以访问，访客不自动包含。';

  @override
  String get videoLibraryAccessSearch => '搜索用户名或显示名称';

  @override
  String get videoLibraryAccessNoUsers => '没有符合条件的用户';

  @override
  String videoLibraryAccessSelectedCount(int count) {
    return '已选择 $count 位用户';
  }

  @override
  String get videoLibraryAccessSave => '保存访问权限';

  @override
  String get videoLibraryAccessSaved => '访问权限已保存';

  @override
  String get videoLibraryAccessLoadFailed => '无法加载访问权限';

  @override
  String get videoLibraryAccessUsersFailed => '无法加载用户列表';

  @override
  String get videoLibrarySourceVisibilityLabel => '可见性';

  @override
  String get videoLibrarySourceLocationLabel => '存储位置';

  @override
  String get videoLibrarySourcePathLabel => '相对目录';

  @override
  String get videoLibrarySourceTypeLabel => '媒体类型';

  @override
  String get adminTrustedMountUnavailable =>
      '没有可用的部署可信挂载，请先检查 application.yml 或环境变量并重启后端。';

  @override
  String get adminChooseRelativeFolder => '选择相对目录';

  @override
  String get adminUseCurrentFolder => '使用当前目录';

  @override
  String get adminOpenFolder => '打开目录';

  @override
  String get adminNoSubfolders => '当前目录没有可浏览的子目录';

  @override
  String readerComicCatalogItems(int count) {
    return '$count 项';
  }

  @override
  String get readerComicExpandAll => '全部展开';

  @override
  String get readerComicCollapseAll => '全部收起';

  @override
  String get photosViewSwitch => '切换视图';

  @override
  String get photosViewGridDay => '网格 · 按日';

  @override
  String get photosViewGridMonth => '网格 · 按月';

  @override
  String get photosViewTimeline => '时间线';

  @override
  String get photosViewGroups => '分组';

  @override
  String get photosToggleSelection => '多选';

  @override
  String photosTrashSubtitle(Object count) {
    return '$count 个项目 · 保留 30 天后自动永久删除';
  }

  @override
  String get photosEmptyTrash => '清空回收站';

  @override
  String get photosRestore => '恢复';

  @override
  String get photosDeleteForever => '永久删除';

  @override
  String get photosEmptyTrashConfirmTitle => '清空回收站？';

  @override
  String photosEmptyTrashConfirmBody(Object count) {
    return '回收站中的 $count 张照片将被永久删除，且无法撤销。';
  }

  @override
  String get photosDeleteForeverConfirmTitle => '永久删除？';

  @override
  String get photosDeleteForeverConfirmBody => '该照片将被永久删除，且无法撤销。';

  @override
  String get photosMoveToTrashTitle => '移入回收站？';

  @override
  String photosMoveToTrashBody(Object count) {
    return '$count 张照片将移入回收站，30 天内可恢复。';
  }

  @override
  String get photosMoveToTrashBodyOne => '该照片将移入回收站，30 天内可恢复。';

  @override
  String get photosMoveToTrashAction => '移入回收站';

  @override
  String get photosTrashRestored => '照片已恢复';

  @override
  String get photosTrashPurged => '已永久删除';

  @override
  String get photosTrashMoved => '已移入回收站';

  @override
  String get photosBackToPhotos => '返回照片';

  @override
  String get photosPlay => '播放';

  @override
  String get photosPause => '暂停';

  @override
  String get photosFullscreen => '全屏';

  @override
  String get photosStripHide => '隐藏';

  @override
  String get photosStripShow => '缩略图';

  @override
  String get photosIso => 'ISO';

  @override
  String get photosTagsSelectHint => '选择一个标签查看对应照片';

  @override
  String photosTagsPhotoCount(int count) {
    return '$count 张照片';
  }

  @override
  String get photosLocationsBack => '返回地点列表';

  @override
  String get photosDeleteShort => '删除';

  @override
  String get photosSaturation => '饱和度';

  @override
  String get photosModuleDisplayName => '光影集';

  @override
  String get photosSelectAll => '全选';

  @override
  String get photosDeselectAll => '取消全选';

  @override
  String get photosFrameNavPhotos => '照片';

  @override
  String get photosFrameNavLocations => '地点';

  @override
  String get photosFrameNavTags => '标签';

  @override
  String get photosFrameNavTrash => '回收站';

  @override
  String get photosFrameLocationsEmpty => '暂无地点信息';

  @override
  String get photosFrameLocationsEmptyHint => '包含拍摄地点的照片会显示在这里';

  @override
  String get photosFrameTagsEmpty => '暂无标签';

  @override
  String get photosFrameTagsEmptyHint => '已打标签的照片会显示在这里';

  @override
  String get photosFrameTrashEmpty => '回收站为空';

  @override
  String get photosFrameTrashEmptyHint => '删除的照片会在这里保留 30 天';

  @override
  String photosFrameStatsPhotos(Object count) {
    return '$count 张照片';
  }

  @override
  String photosFrameStatsMeta(Object albums, Object trash) {
    return '$albums 个影集 · $trash 张在回收站';
  }

  @override
  String get photosInsightsTitle => '关联视图';

  @override
  String get photosAlbumsManage => '管理相册';

  @override
  String get photosExpandAlbums => '展开相册';

  @override
  String get photosScrollToTop => '回到顶部';

  @override
  String photosRelCooccur(Object count) {
    return '共现 $count 张';
  }

  @override
  String photosRelOthers(Object count) {
    return '其他 $count 项';
  }

  @override
  String photosRelRelated(Object name) {
    return '与「$name」关联';
  }

  @override
  String get photosRelCooccurTitle => '关联实体';

  @override
  String get photosRelHint => '点击实体查看关联；「查看全部」将按该实体筛选图库。';

  @override
  String videoRedesignItemsCount(int count) {
    return '$count 项';
  }

  @override
  String get videoRedesignStatusMatched => '已匹配';

  @override
  String get videoRedesignStatusPending => '待刮削';

  @override
  String get videoRedesignStatusFailed => '失败';

  @override
  String get videoRedesignFilterAll => '全部';

  @override
  String get videoRedesignFilterMatched => '已匹配';

  @override
  String get videoRedesignFilterPending => '待刮削';

  @override
  String get videoRedesignFilterFailed => '失败';

  @override
  String get videoRedesignDetail => '详情';

  @override
  String get videoRedesignPlayNow => '立即播放';

  @override
  String get videoRedesignNoMatches => '无匹配条目';

  @override
  String get videoRedesignAdjustFilters => '尝试调整筛选条件';

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
    return '搜索$section…';
  }

  @override
  String get videoRedesignNoFavorites => '暂无收藏';

  @override
  String get videoRedesignNoFavoritesHint => '播放时点击收藏按钮';

  @override
  String get videoRedesignNoHistoryHint => '开始观看后记录将在此显示';

  @override
  String get videoRedesignSubtitlesEn => 'Subtitles';

  @override
  String get videoRedesignUploadSubtitle => '上传字幕';

  @override
  String get videoRedesignNoSubtitles => '暂无字幕';

  @override
  String get videoRedesignSubtitleEmbedded => '内嵌';

  @override
  String get videoRedesignSubtitleExternal => '外挂';

  @override
  String get videoRedesignVersions => '版本';

  @override
  String get videoRedesignVersionsEn => 'Versions';

  @override
  String get videoRedesignOriginalVersion => '原版';

  @override
  String get videoRedesignLanguage => '语言';

  @override
  String get videoRedesignConfirmUpload => '确认上传';

  @override
  String get videoRedesignStatTotal => '总条目';

  @override
  String get videoRedesignStatTotalEn => 'Total';

  @override
  String get fontScaleTitle => '字体大小';

  @override
  String get fontScaleFollowSystem => '跟随系统';

  @override
  String get fontScaleCompact => '紧凑';

  @override
  String get fontScaleStandard => '标准';

  @override
  String get fontScaleComfortable => '舒适';

  @override
  String get fontScaleLarge => '大';

  @override
  String get fontScaleResetDefault => '恢复默认';

  @override
  String get fontScalePreviewSample => '你好，OmniNest';

  @override
  String get videoDetailBack => '返回';

  @override
  String get videoDetailEdit => '编辑';

  @override
  String get videoDetailSave => '保存';

  @override
  String get videoDetailPlay => '播放';

  @override
  String get videoDetailTabOverview => '简介';

  @override
  String get videoDetailTabVersions => '版本';

  @override
  String get videoDetailTabSubtitles => '字幕';

  @override
  String get videoDetailCast => '演员';

  @override
  String get videoDetailDirector => '导演';

  @override
  String get videoDetailNoVersions => '暂无可用版本';

  @override
  String get videoDetailUploadSubtitle => '上传字幕';

  @override
  String videoDetailSeasonCount(int count) {
    return '$count 季';
  }

  @override
  String get videoDetailEpisodesHeader => '剧集列表';

  @override
  String get videoMetaFieldOriginalTitle => '原名';

  @override
  String get videoMetaFieldYear => '年份';

  @override
  String get videoMetaFieldRuntimeMinutes => '时长（分钟）';

  @override
  String get videoMetaFieldOverview => '简介';

  @override
  String get readerComicManifestLoadFailed => '漫画清单加载失败，请稍后重试';

  @override
  String readerComicParseFailedWithReason(Object reason) {
    return '漫画解析失败：$reason';
  }

  @override
  String get readerComicParseFailed => '漫画解析失败，请在详情页重试来源';

  @override
  String readerComicPartialFailedWithReason(Object reason) {
    return '部分漫画来源解析失败：$reason';
  }

  @override
  String get readerComicPartialFailed => '部分漫画来源解析失败，请在详情页处理失败来源';

  @override
  String get readerComicEmptyManifest => '漫画内容为空或尚未生成清单';

  @override
  String get readerComicEmpty => '漫画内容为空';

  @override
  String get filesHomeLocations => '位置';

  @override
  String get filesHomeSections => '分区';

  @override
  String get filesHomePersonalSpaceHint => '我的私有文件';

  @override
  String get filesHomeAllFilesHint => '浏览全部文件与文件夹';

  @override
  String get filesHomeRecentHint => '最近上传与修改';

  @override
  String get filesHomeFavoritesHint => '收藏标记的文件';

  @override
  String get filesHomeTrashHint => '已删除的项目';

  @override
  String get filesHomeMoreHint => '上传队列、离线下载与分享管理';

  @override
  String get errorInvalidResponse => '服务端返回的数据格式不正确';

  @override
  String get errorEmptyResponse => '服务端没有返回结果';

  @override
  String get errorOperationFailed => '操作失败';

  @override
  String get errorNetworkTimeout => '请求超时，请检查网络后重试';

  @override
  String get errorNetworkError => '网络错误，请稍后重试';

  @override
  String get errorUnknown => '未知错误';

  @override
  String get errorNeedPassword => '请输入分享密码';

  @override
  String get errorShareSessionInvalid => '分享会话无效';

  @override
  String get errorUnnamedFile => '未命名';

  @override
  String get errorUnnamedResource => '未命名资源';

  @override
  String get errorUploadUrlMissing => '上传地址无效';

  @override
  String get errorSecurityScanFailed => '安全扫描未完成，文件已保留；请稍后在书库查看，或重新导入';

  @override
  String get errorOtherCategory => '其他';

  @override
  String musicBatchFailedTitles(Object titles) {
    return '失败：$titles';
  }

  @override
  String get readerPdfTitle => 'PDF 阅读';

  @override
  String get readerPdfLoadFailed => 'PDF 加载失败';

  @override
  String readerPdfPageIndicator(Object page, Object total) {
    return '第 $page / $total 页';
  }

  @override
  String get errorServiceUnavailable => '服务暂时不可用，请稍后重试；文件仍处于安全隔离状态';

  @override
  String get errorCannotConnect => '无法连接后端服务，请确认服务已启动或网络可用';

  @override
  String get errorRequestCancelled => '请求已取消';

  @override
  String get errorBadCertificate => '后端证书校验失败，请检查服务配置';

  @override
  String errorServerCode(Object code) {
    return '服务端返回 $code 错误';
  }

  @override
  String get errorRequestFailedRetry => '请求失败，请稍后重试';

  @override
  String get errorWebPdfTooLarge => 'Web 阅读仅支持 128 MiB 以内的 PDF 文件';

  @override
  String get errorWebBookTooLarge => 'Web 阅读仅支持 32 MiB 以内的 EPUB 或 TXT 文件';

  @override
  String get errorFileNotFound => '文件不存在';

  @override
  String get errorConflict => '数据冲突，请刷新后重试';

  @override
  String get errorUnauthorized => '未登录或登录已过期';

  @override
  String get errorForbidden => '没有权限执行该操作';

  @override
  String get filesOpListVersions => '查看版本';

  @override
  String get filesOpRestoreVersion => '恢复版本';

  @override
  String get filesOpSaveVersion => '保存新版本';

  @override
  String get filesVersionsTitle => '文件版本';

  @override
  String get filesVersionsEmpty => '暂无历史版本';

  @override
  String get filesVersionsRestore => '恢复';

  @override
  String get filesVersionsCurrent => '当前';

  @override
  String get filesVersionsRestored => '已恢复版本';

  @override
  String get desktopCloseDialogTitle => '关闭 OmniNest';

  @override
  String get desktopCloseDialogBody => '最小化到托盘后，程序将在后台继续运行，可随时从托盘恢复窗口。';

  @override
  String get desktopCloseDialogMinimize => '最小化到托盘';

  @override
  String get desktopCloseDialogExit => '退出程序';

  @override
  String get desktopCloseDialogRemember => '记住我的选择，下次不再询问';

  @override
  String get desktopCloseBehaviorTitle => '关闭窗口行为';

  @override
  String get desktopCloseBehaviorAsk => '每次询问';

  @override
  String get desktopCloseBehaviorExit => '直接退出';

  @override
  String get trayShowMainWindow => '显示主窗口';

  @override
  String get trayQuit => '退出';
}
