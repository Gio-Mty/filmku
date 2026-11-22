import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/backend.dart';
import '../../theme.dart';

class WatchPartyDialog extends StatefulWidget {
  const WatchPartyDialog({
    super.key,
    this.activeRoomId,
    required this.onJoinRoom,
    required this.onLeaveRoom,
  });

  final String? activeRoomId;
  final void Function(String roomId, bool isHost) onJoinRoom;
  final VoidCallback onLeaveRoom;

  @override
  State<WatchPartyDialog> createState() => _WatchPartyDialogState();
}

class _WatchPartyDialogState extends State<WatchPartyDialog> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Backend.createWatchParty();
      final roomId = res['room_id'] as String;
      if (mounted) {
        widget.onJoinRoom(roomId, true);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Room Nobar berhasil dibuat: $roomId'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal membuat room: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinRoom() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 4) {
      setState(() => _error = 'Masukkan kode room yang valid');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Backend.getWatchParty(code);
      if (mounted) {
        widget.onJoinRoom(code, false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tersambung ke Room Nobar: $code'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Room tidak ditemukan');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.activeRoomId;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_rounded,
                    color: AppColors.accent, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Nonton Bareng (Watch Party)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (active != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent.withAlpha(80)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'SEDANG TERHUBUNG KE ROOM',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          active,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: 'Salin Kode',
                          icon: const Icon(Icons.copy_rounded,
                              color: Colors.white70),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: active));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Kode room disalin ke clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tindakan play, pause, dan seek tersinkronisasi otomatis antar penonton.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.exit_to_app_rounded),
                  label: const Text('Tinggalkan Room'),
                  onPressed: () {
                    widget.onLeaveRoom();
                    Navigator.pop(context);
                  },
                ),
              ),
            ] else ...[
              const Text(
                'Tonton film bersama teman dari jarak jauh. Putar, jeda, dan lompat waktu akan sinkron secara otomatis.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Buat Room Baru (Sebagai Host)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _loading ? null : _createRoom,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white24)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('ATAU',
                          style:
                              TextStyle(color: AppColors.muted, fontSize: 11)),
                    ),
                    Expanded(child: Divider(color: Colors.white24)),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Kode Room (contoh: 8C09B9)',
                        hintStyle: const TextStyle(
                            color: Colors.white38, fontSize: 13),
                        filled: true,
                        fillColor: Colors.black26,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _loading ? null : _joinRoom,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Gabung'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
