import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../config/theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.location_on, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('CampusFind',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.notifications_none, color: AppTheme.textSecondary),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: const Color(0xFFF5F5F5),
              child: const Icon(Icons.person, size: 40, color: AppTheme.textTertiary),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text('Student', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          const Center(
            child: Text('student@example.edu', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          ),
          const SizedBox(height: 32),
          _SettingsTile(icon: Icons.person_outline, title: 'Edit Profile'),
          _SettingsTile(icon: Icons.location_on_outlined, title: 'Default Campus'),
          _SettingsTile(
            icon: Icons.dns_outlined,
            title: 'Server URL',
            subtitle: ApiConfig.serverUrl,
          ),
          _SettingsTile(icon: Icons.notifications_outlined, title: 'Notifications'),
          _SettingsTile(icon: Icons.dark_mode_outlined, title: 'Appearance'),
          _SettingsTile(icon: Icons.info_outline, title: 'About'),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.cardBorder.withValues(alpha: 0.5)),
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.textSecondary),
        title: Text(title, style: const TextStyle(fontSize: 15)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: const TextStyle(fontSize: 12)),
        trailing: subtitle == null
            ? const Icon(Icons.chevron_right, color: AppTheme.textTertiary, size: 20)
            : null,
        onTap: () {},
      ),
    );
  }
}
