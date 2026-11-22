import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../models/app_version.dart';
import '../screens/navigation.dart';
import '../theme.dart';

const currentAppVersion = '1.2.0';
const currentAppBuildNumber = 3;

Future<void> checkAndShowUpdate(BuildContext context, {bool manual = false}) async {
  // Di platform Web (Chrome), tidak perlu mendownload installer APK Android.
  // Kode terbaru di Web selalu langsung aktif cukup dengan F5 / reload browser.
  if (kIsWeb) {
    if (manual && context.mounted) {
      _showCustomSnackBar(
        context,
        icon: Icons.info_outline_rounded,
        iconColor: AppColors.accent,
        text:
            'Versi Web selalu terhubung langsung dengan server terbaru (cukup tekan F5).',
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
      _showCustomSnackBar(
        context,
        icon: Icons.check_circle_rounded,
        iconColor: AppColors.accent,
        text: 'Aplikasi sudah versi terbaru (v$currentAppVersion)',
      );
    }
  } catch (_) {
    if (manual && context.mounted) {
      _showCustomSnackBar(
        context,
        icon: Icons.error_outline_rounded,
        iconColor: Colors.orangeAccent,
        text: 'Tidak dapat memeriksa pembaruan saat ini.',
      );
    }
  }
}

void _showCustomSnackBar(
  BuildContext context, {
  required IconData icon,
  required Color iconColor,
  required String text,
}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      elevation: 6,
      backgroundColor: const Color(0xFF222228),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.white12, width: 0.8),
      ),
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(seconds: 3),
    ),
  );
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in info.changelog)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  size: 14,
                                  color: AppColors.accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.onAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: const Text(
                      'Update Sekarang',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    onPressed: () {
                      openLink(context, info.downloadUrl);
                      if (!info.forceUpdate) Navigator.pop(context);
                      _showCustomSnackBar(
                        context,
                        icon: Icons.downloading_rounded,
                        iconColor: AppColors.accent,
                        text:
                            'Mengunduh file APK baru... Periksa notifikasi download di HP Anda.',
                      );
                    },
                  ),
                ),
                if (!info.forceUpdate) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white60,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Nanti Saja',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
