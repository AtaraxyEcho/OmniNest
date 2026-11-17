class InitialSetupStatus {
  const InitialSetupStatus({
    required this.setupRequired,
    required this.setupAvailable,
    this.persistentStateEnabled = true,
    this.twoFactorRequired = false,
  });

  final bool setupRequired;
  final bool setupAvailable;
  final bool persistentStateEnabled;

  /// 安装向导是否要求为超管完成两步验证注册（部署姿态开关）。
  final bool twoFactorRequired;

  factory InitialSetupStatus.fromJson(Map<String, dynamic> json) {
    return InitialSetupStatus(
      setupRequired: json['setupRequired'] == true,
      setupAvailable: json['setupAvailable'] == true,
      persistentStateEnabled: json['persistentStateEnabled'] != false,
      twoFactorRequired: json['twoFactorRequired'] == true,
    );
  }
}
