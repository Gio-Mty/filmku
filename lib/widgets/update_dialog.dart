import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../models/app_version.dart';
import '../screens/navigation.dart';
import '../theme.dart';

const currentAppVersion = '1.1.0';
const currentAppBuildNumber = 2;

Future<void> checkAndShowUpdate(BuildContext context, {bool manual = false}) async {
  // Di platform Web (Chrome), tidak perlu mendownload installer APK Android.
  // Kode terbaru di Web selalu langsung aktif cukup dengan F5 / reload browser.
  if (kIsWeb) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Versi Web selalu terhubung langsung dengan server terbaru (cukup tekan F5).'),
          backgroundColor: AppColors.surface,
          duration: Duration(seconds: 2),
        ),
      );
    }
    return;
  }

  try {
    final info = await Backend.checkAppVersion();
    if (info.versionCode > currentAppBuildNumber ||
        info.latestVersion != currentAppVersion) {
      if (context.mounted) {
        showDialog<void>(
          context: context,
          barrierDismissible: !info.forceUpdate,
          builder: (ctx) => AppUpdateDialog(info: info),
        );
      }
    } else if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aplikasi sudah versi terbaru (v$currentAppVersion)'),
          backgroundColor: AppColors.surface,
          duration: Duration(seconds: 2),
        ),
      );
    }
  } catch (_) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak dapat memeriksa pembaruan saat ini.'),
          backgroundColor: AppColors.surface,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog({super.key, required this.info});
  final AppVersion info;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: AppColors.accent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pembaruan Tersedia!',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v$currentAppVersion  ➔  v${info.latestVersion}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Apa yang baru:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in info.changelog)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 15,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (!info.forceUpdate)
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        minimumSize: const Size.fromHeight(44),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Nanti Saja'),
                    ),
                  ),
                if (!info.forceUpdate) const SizedBox(width: 10),
                Expanded(
                  flex: info.forceUpdate ? 1 : 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.onAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: const Text(
                      'Update Sekarang',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      openLink(context, info.downloadUrl);
                      if (!info.forceUpdate) Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Mengunduh file APK baru... Periksa notifikasi download di HP Anda.',
                          ),
                          backgroundColor: AppColors.accent,
                          duration: Duration(seconds: 4),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
