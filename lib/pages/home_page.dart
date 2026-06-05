import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'teams_page.dart';
import 'monthly_schedule_page.dart';
import 'my_schedule_page.dart';
import 'my_availability_page.dart';
import 'auth_page.dart';
import 'pending_assignments_page.dart';
import 'admin_dashboard_page.dart';
import 'notifications_page.dart';

final supabase = Supabase.instance.client;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<dynamic> _ministries = [];
  Map<String, dynamic>? _profile;
  int _unreadNotificationCount = 0;

  bool _isLoading = true;

  String? _message;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('No authenticated user found.');
      }

      final profileResponse = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      final ministriesResponse = await supabase
          .from('ministries')
          .select()
          .order('display_order');

      final unreadNotificationsResponse = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_read', false);

      setState(() {
        _profile = profileResponse;
        _ministries = ministriesResponse;
        _unreadNotificationCount = unreadNotificationsResponse.length;
      });
    } catch (e) {
      setState(() {
        _message = 'Failed to load home data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
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
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  Future<void> _refreshUnreadNotificationCount() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        return;
      }

      final response = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_read', false);

      if (!mounted) return;

      setState(() {
        _unreadNotificationCount = response.length;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _unreadNotificationCount = 0;
      });
    }
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    if (!mounted) return;

    await _refreshUnreadNotificationCount();
  }

  @override
  Widget build(BuildContext context) {
    final firstName = _profile?['first_name'] ?? 'User';

    final role = _profile?['role'] ?? 'volunteer';

    final isAdmin = role == 'admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choir Scheduler'),
        actions: [
          IconButton(
            onPressed: () {
              _openPage(const NotificationsPage());
            },
            icon: Badge.count(
              count: _unreadNotificationCount,
              isLabelVisible: _unreadNotificationCount > 0,
              child: const Icon(Icons.notifications),
            ),
            tooltip: 'Notifications',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _message != null
            ? Center(child: Text(_message!))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    isAdmin
                        ? 'Welcome, $firstName (Admin)'
                        : 'Welcome, $firstName',

                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 24),

                  Wrap(
                    spacing: 10,
                    runSpacing: 10,

                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.calendar_month),

                        label: const Text('Monthly'),

                        onPressed: () {
                          _openPage(const MonthlySchedulePage());
                        },
                      ),

                      ElevatedButton.icon(
                        icon: const Icon(Icons.schedule),

                        label: const Text('My Schedule'),

                        onPressed: () {
                          _openPage(const MySchedulePage());
                        },
                      ),

                      ElevatedButton.icon(
                        icon: const Icon(Icons.assignment),

                        label: const Text('Assignments'),

                        onPressed: () {
                          _openPage(const PendingAssignmentsPage());
                        },
                      ),

                      ElevatedButton.icon(
                        icon: const Icon(Icons.event_available),

                        label: const Text('Availability'),

                        onPressed: () {
                          _openPage(const MyAvailabilityPage());
                        },
                      ),

                      if (isAdmin)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.admin_panel_settings),

                          label: const Text('Admin Dashboard'),

                          onPressed: () {
                            _openPage(const AdminDashboardPage());
                          },
                        ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Ministries',

                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  Expanded(
                    child: _ministries.isEmpty
                        ? const Center(child: Text('No ministries found.'))
                        : ListView.builder(
                            itemCount: _ministries.length,

                            itemBuilder: (context, index) {
                              final sortedMinistries =
                                  List<Map<String, dynamic>>.from(_ministries);

                              sortedMinistries.sort((a, b) {
                                final aName = a['name'] ?? '';
                                final bName = b['name'] ?? '';

                                int getPriority(String name) {
                                  if (name ==
                                      'Children\'s Ministry Live Schedule') {
                                    return 1;
                                  }

                                  if (name == 'Kids Choir') {
                                    return 2;
                                  }

                                  if (name == 'Main Choir') {
                                    return 3;
                                  }

                                  return 999;
                                }

                                return getPriority(
                                  aName,
                                ).compareTo(getPriority(bName));
                              });

                              final ministry = sortedMinistries[index];

                              return Card(
                                child: ListTile(
                                  title: Text(ministry['name'] ?? ''),

                                  subtitle: Text(ministry['description'] ?? ''),

                                  trailing: const Icon(Icons.arrow_forward_ios),

                                  onTap: () {
                                    _openPage(
                                      TeamsPage(
                                        ministryId: ministry['id'],
                                        ministryName: ministry['name'],
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
