import 'package:flutter/material.dart';

import '../theme.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
      child: Text(title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
    );
  }
}

class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ),
        ?action,
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.5)),
        ]),
      ),
    );
  }
}
