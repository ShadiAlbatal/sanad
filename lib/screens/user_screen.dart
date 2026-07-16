import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

class UserScreen extends StatelessWidget {
  const UserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: context.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                    color: context.accent.withValues(alpha: 0.30), width: 2),
              ),
              child: Icon(Icons.person_rounded,
                  color: context.accent, size: 56),
            ),
          ),
          const SizedBox(height: 18),
          const Center(
            child: Text('Assalamu ʿalaykum',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('Guest · sign-in coming soon',
                style: TextStyle(fontSize: 13.5, color: soft)),
          ),
          const SizedBox(height: 28),
          _StatRow(
            icon: Icons.menu_book_rounded,
            label: 'Last page read',
            value: 'Page ${app.lastPage}',
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: dark ? AppColors.nightCard : AppColors.paperEdge,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: context.accent, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14.5)),
          ),
          Text(value, style: TextStyle(color: soft, fontSize: 13.5)),
        ],
      ),
    );
  }
}
