import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../theme.dart';
import 'vidfast_controller.dart';

/// Overlay minimalis untuk pemutar embed video.
/// Menggunakan PointerInterceptor agar klik tombol Kembali tidak bocor ke iframe.
class VidFastControlsOverlay extends StatefulWidget {
  const VidFastControlsOverlay({
    super.key,
    required this.controller,
    required this.title,
    required this.onBack,
    this.activeRoomId,
    this.onWatchPartyTap,
    this.serverName,
    this.onSelectServerTap,
  });

  final VidFastController controller;
  final String title;
  final VoidCallback onBack;
  final String? activeRoomId;
  final VoidCallback? onWatchPartyTap;
  final String? serverName;
  final VoidCallback? onSelectServerTap;

  @override
  State<VidFastControlsOverlay> createState() => _VidFastControlsOverlayState();
}

class _VidFastControlsOverlayState extends State<VidFastControlsOverlay> {
  bool _visible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _showOverlay() {
    if (!_visible) {
      setState(() => _visible = true);
    }
    _startHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => _showOverlay(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Header Bar di bagian atas
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            top: _visible ? 0 : -90,
            left: 0,
            right: 0,
            child: PointerInterceptor(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Kembali',
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white),
                          onPressed: widget.onBack,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    widget.serverName ?? 'VidFast Player',
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (widget.activeRoomId != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.accent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'NOBAR: ${widget.activeRoomId}',
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (widget.onSelectServerTap != null) ...[
                          IconButton(
                            tooltip: 'Ganti Server Pemutar',
                            icon: const Icon(Icons.dns_rounded,
                                size: 20, color: Colors.white),
                            onPressed: () {
                              _startHideTimer();
                              widget.onSelectServerTap?.call();
                            },
                          ),
                          const SizedBox(width: 4),
                        ],
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: widget.activeRoomId != null
                                ? AppColors.accent
                                : Colors.white,
                            backgroundColor: Colors.white10,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          icon: const Icon(Icons.groups_rounded, size: 18),
                          label: Text(
                            widget.activeRoomId != null ? 'Room Nobar' : 'Nobar',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () {
                            _startHideTimer();
                            widget.onWatchPartyTap?.call();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Tombol Kembali melayang minimalis saat header bar tersembunyi
          if (!_visible)
            Positioned(
              top: 10,
              left: 10,
              child: SafeArea(
                child: PointerInterceptor(
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Tampilkan Menu / Kembali',
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 20),
                      onPressed: _showOverlay,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
