class AppVersion {
  final String latestVersion;
  final int versionCode;
  final List<String> changelog;
  final String downloadUrl;
  final String releasedAt;
  final bool forceUpdate;

  const AppVersion({
    required this.latestVersion,
    required this.versionCode,
    required this.changelog,
    required this.downloadUrl,
    required this.releasedAt,
    this.forceUpdate = false,
  });

  factory AppVersion.fromJson(Map<String, dynamic> j) => AppVersion(
        latestVersion: (j['latest_version'] as String?) ?? '1.0.0',
        versionCode: (j['version_code'] as num?)?.toInt() ?? 1,
        changelog: List<String>.from(j['changelog'] as List? ?? const []),
        downloadUrl: (j['download_url'] as String?) ?? '',
        releasedAt: (j['released_at'] as String?) ?? '',
        forceUpdate: (j['force_update'] as bool?) ?? false,
      );
}
