import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_branding.dart';
import '../utils/error_messages.dart';
import 'auth_page.dart';

final supabase = Supabase.instance.client;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _profile;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      final response = await supabase
          .from('profiles')
          .select('first_name, last_name, email, role')
          .eq('id', user.id)
          .single();

      setState(() {
        _profile = response;
        _message = null;
      });
    } catch (e, stackTrace) {
      logTechnicalError('SettingsPage._loadProfile failed', e, stackTrace);
      setState(() {
        _message = 'Unable to load settings. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    try {
      await supabase.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthPage()),
        (route) => false,
      );
    } catch (e, stackTrace) {
      logTechnicalError('SettingsPage._logout failed', e, stackTrace);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logout failed. Please try again.')),
      );
    }
  }

  String _profileName() {
    final firstName = _profile?['first_name']?.toString() ?? '';
    final lastName = _profile?['last_name']?.toString() ?? '';
    final fullName = '$firstName $lastName'.trim();

    return fullName.isEmpty ? 'Unknown User' : fullName;
  }

  String _profileEmail() {
    return _profile?['email']?.toString() ?? 'No email on file';
  }

  String _profileRole() {
    final role = _profile?['role']?.toString() ?? 'volunteer';

    if (role.isEmpty) {
      return 'Volunteer';
    }

    return '${role[0].toUpperCase()}${role.substring(1)}';
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .05),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: (iconColor ?? AppBranding.primary).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor ?? AppBranding.primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _message != null
          ? Center(child: Text(_message!))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection(
                  title: 'Account',
                  children: [
                    _buildSettingTile(
                      icon: Icons.person_outline,
                      title: 'Name',
                      subtitle: _profileName(),
                    ),
                    _buildSettingTile(
                      icon: Icons.email_outlined,
                      title: 'Email',
                      subtitle: _profileEmail(),
                    ),
                    _buildSettingTile(
                      icon: Icons.badge_outlined,
                      title: 'Role',
                      subtitle: _profileRole(),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _buildSection(
                  title: 'Preferences',
                  children: [
                    _buildSettingTile(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      subtitle: 'Notification preferences coming soon',
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _buildSection(
                  title: 'About',
                  children: [
                    _buildSettingTile(
                      icon: Icons.info_outline,
                      title: AppBranding.appName,
                      subtitle: 'Version 1.0.0+1',
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _buildSection(
                  title: 'Actions',
                  children: [
                    _buildSettingTile(
                      icon: Icons.logout,
                      title: 'Logout',
                      subtitle: 'Sign out of this device',
                      iconColor: Colors.red,
                      onTap: _logout,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
