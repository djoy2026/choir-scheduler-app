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
import 'settings_page.dart';
import '../theme/app_branding.dart';
import '../utils/error_messages.dart';
import '../utils/time_format.dart';

final supabase = Supabase.instance.client;

const _kidsClassTeamNames = {
  'Nursery',
  'Kindies',
  '2 Year Olds',
  '3 Year Olds',
  '4 Year Olds',
  '1st Grade',
  '2nd Grade',
  '3rd Grade',
  '4th Grade',
  '5th Grade',
};

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomeAction {
  final String label;
  final IconData icon;
  final MaterialColor color;
  final Widget page;

  const _HomeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.page,
  });
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  List<dynamic> _ministries = [];
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _nextServiceSlot;
  Map<String, int> _ministryUpcomingCounts = {};
  int _upcomingServicesCount = 0;
  int _openSlotsCount = 0;
  int _pendingAssignmentsCount = 0;
  int _unreadNotificationCount = 0;
  late final AnimationController _bellPulseController;
  late final Animation<double> _bellPulseAnimation;

  bool _isLoading = true;

  String? _message;

  @override
  void initState() {
    super.initState();
    _bellPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _bellPulseAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: 30),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.08,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: 30),
    ]).animate(_bellPulseController);
    _loadHomeData();
  }

  @override
  void dispose() {
    _bellPulseController.dispose();
    super.dispose();
  }

  void _syncBellPulseAnimation() {
    if (_unreadNotificationCount > 0) {
      if (!_bellPulseController.isAnimating) {
        _bellPulseController.repeat();
      }
      return;
    }

    _bellPulseController.stop();
    _bellPulseController.value = 0;
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
      final isAdmin =
          profileResponse['role']?.toString().trim().toLowerCase() == 'admin';
      debugPrint(isAdmin ? 'ROUTE_ADMIN' : 'ROUTE_HOME');

      final ministriesResponse = await supabase
          .from('ministries')
          .select()
          .order('display_order');

      final unreadNotificationsResponse = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_read', false);

      final today = _dateKey(DateTime.now());

      final upcomingServicesResponse = await supabase
          .from('service_instances')
          .select('''
            id,
            ministry_id,
            team_id,
            service_slots (
              id,
              slot_status
            )
          ''')
          .gte('service_date', today);

      final pendingAssignmentsResponse = await supabase
          .from('service_slots')
          .select('id')
          .eq('assigned_user_id', user.id)
          .eq('slot_status', 'pending');

      final volunteerUpcomingResponse = await supabase
          .from('service_slots')
          .select('''
            id,
            service_instances!inner (
              service_date
            )
          ''')
          .eq('assigned_user_id', user.id)
          .inFilter('slot_status', ['pending', 'taken'])
          .gte('service_instances.service_date', today);

      final nextServiceResponse = await supabase
          .from('service_slots')
          .select('''
            id,
            role_name,
            slot_name,
            slot_status,
            service_instances!inner (
              id,
              service_name,
              service_date,
              start_time,
              location,
              teams (
                name
              )
            )
          ''')
          .eq('assigned_user_id', user.id)
          .inFilter('slot_status', ['pending', 'taken'])
          .gte('service_instances.service_date', today)
          .order('service_instances(service_date)')
          .order('service_instances(start_time)')
          .limit(1);

      final upcomingServices = List<Map<String, dynamic>>.from(
        upcomingServicesResponse,
      );
      final activeTeamIds = await _activeTeamIds();
      final kidsClassTeamIds = await _kidsClassTeamIds();
      final kidsClassMinistryId = _kidsClassMinistryId(ministriesResponse);
      final ministryCounts = <String, int>{};
      var openSlotsCount = 0;
      var pendingSlotsCount = 0;

      for (final service in upcomingServices) {
        final ministryId = service['ministry_id']?.toString();
        final teamId = service['team_id']?.toString();

        if (teamId == null || !activeTeamIds.contains(teamId)) {
          continue;
        }

        final slots = List<Map<String, dynamic>>.from(
          service['service_slots'] ?? const [],
        );

        openSlotsCount += slots.where((slot) {
          final status = slot['slot_status']?.toString().trim().toLowerCase();
          return status == 'open';
        }).length;
        pendingSlotsCount += slots.where((slot) {
          final status = slot['slot_status']?.toString().trim().toLowerCase();
          return status == 'pending';
        }).length;

        if (ministryId == null || ministryId.isEmpty) {
          continue;
        }

        ministryCounts[ministryId] = (ministryCounts[ministryId] ?? 0) + 1;

        if (!kidsClassTeamIds.contains(teamId)) {
          continue;
        }

        if (kidsClassMinistryId == null || kidsClassMinistryId.isEmpty) {
          continue;
        }

        if (ministryId == kidsClassMinistryId) {
          continue;
        }

        ministryCounts[kidsClassMinistryId] =
            (ministryCounts[kidsClassMinistryId] ?? 0) + 1;
      }

      setState(() {
        _profile = profileResponse;
        _ministries = ministriesResponse;
        _upcomingServicesCount = volunteerUpcomingResponse.length;
        _openSlotsCount = openSlotsCount;
        _pendingAssignmentsCount = isAdmin
            ? pendingSlotsCount
            : pendingAssignmentsResponse.length;
        _unreadNotificationCount = unreadNotificationsResponse.length;
        _ministryUpcomingCounts = ministryCounts;
        _nextServiceSlot = nextServiceResponse.isEmpty
            ? null
            : Map<String, dynamic>.from(nextServiceResponse.first);
      });
      _syncBellPulseAnimation();
    } catch (e, stackTrace) {
      logTechnicalError('HomePage._loadHomeData failed', e, stackTrace);
      setState(() {
        _message = friendlyErrorMessage(
          e,
          fallback: 'Unable to load home. Please try again.',
        );
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<Set<String>> _kidsClassTeamIds() async {
    final response = await supabase
        .from('teams')
        .select('id')
        .eq('is_active', true)
        .inFilter('name', _kidsClassTeamNames.toList())
        .order('display_order')
        .order('name');

    return List<Map<String, dynamic>>.from(response)
        .map((team) => team['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<Set<String>> _activeTeamIds() async {
    final response = await supabase
        .from('teams')
        .select('id')
        .eq('is_active', true)
        .order('display_order')
        .order('name');

    return List<Map<String, dynamic>>.from(response)
        .map((team) => team['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  String? _kidsClassMinistryId(List<dynamic> ministries) {
    for (final ministry in ministries) {
      if (ministry is! Map<String, dynamic>) {
        continue;
      }

      final name = ministry['name']?.toString() ?? '';

      if (_ministryHomePriority(name) != 1) {
        continue;
      }

      return ministry['id']?.toString();
    }

    return null;
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
      logTechnicalError('HomePage._logout failed', e, stackTrace);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Unable to log out. Please try again.',
            ),
          ),
        ),
      );
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
      _syncBellPulseAnimation();
    } catch (e, stackTrace) {
      logTechnicalError(
        'HomePage._refreshUnreadNotificationCount failed',
        e,
        stackTrace,
      );
      if (!mounted) return;

      setState(() {
        _unreadNotificationCount = 0;
      });
      _syncBellPulseAnimation();
    }
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    if (!mounted) return;

    await _refreshUnreadNotificationCount();
  }

  String _dateKey(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  String _greeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'Good Morning';
    }

    if (hour < 17) {
      return 'Good Afternoon';
    }

    return 'Good Evening';
  }

  String _titleCaseName(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      return 'User';
    }

    return trimmed
        .split(RegExp(r'\s+'))
        .map((part) {
          if (part.isEmpty) {
            return part;
          }

          return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  List<Map<String, dynamic>> _sortedMinistries() {
    final sortedMinistries = List<Map<String, dynamic>>.from(
      _ministries.where((ministry) {
        final name = ministry['name']?.toString() ?? '';

        return _ministryHomePriority(name) < 999;
      }),
    );

    sortedMinistries.sort((a, b) {
      final aName = a['name']?.toString() ?? '';
      final bName = b['name']?.toString() ?? '';

      return _ministryHomePriority(
        aName,
      ).compareTo(_ministryHomePriority(bName));
    });

    return sortedMinistries;
  }

  int _ministryHomePriority(String name) {
    final normalizedName = name.trim().toLowerCase();

    if (normalizedName == 'children\'s ministry' ||
        normalizedName == 'children\'s ministry live schedule') {
      return 1;
    }

    if (normalizedName == 'kids choir') {
      return 2;
    }

    if (normalizedName == 'main choir') {
      return 3;
    }

    return 999;
  }

  IconData _ministryIcon(String name) {
    final normalizedName = name.toLowerCase();

    if (normalizedName.contains('children')) {
      return Icons.child_care;
    }

    if (normalizedName.contains('kids')) {
      return Icons.music_note;
    }

    if (normalizedName.contains('main')) {
      return Icons.mic;
    }

    return Icons.groups;
  }

  String _ministryDisplayName(String name) {
    if (name.contains('Children\'s Ministry Live Schedule')) {
      return 'Kids Class Schedule';
    }

    return name;
  }

  String _ministrySubtitle(Map<String, dynamic> ministry) {
    final ministryName = ministry['name']?.toString() ?? '';

    if (ministryName.contains('Children\'s Ministry Live Schedule')) {
      return 'Live Schedule • Classroom volunteer scheduling';
    }

    return ministry['description']?.toString() ?? '';
  }

  String _serviceName(Map<String, dynamic> service) {
    final rawName = service['service_name']?.toString() ?? '';
    final trimmedName = removeServiceSuffix(rawName).trim();

    if (trimmedName.isEmpty || trimmedName.startsWith('Service ')) {
      return 'Next Service';
    }

    return trimmedName;
  }

  String _assignmentStatus(String? status) {
    if (status == 'pending') {
      return 'Pending';
    }

    if (status == 'taken') {
      return 'Confirmed';
    }

    return 'Assigned';
  }

  Widget _buildHeroCard(String firstName, {required bool isAdmin}) {
    final displayName = isAdmin
        ? '${_titleCaseName(firstName)} (Admin)'
        : _titleCaseName(firstName);
    final subtitle = isAdmin
        ? 'Manage schedules, assignments and volunteers'
        : 'Welcome back to Kids Ministry Scheduler';
    final stats = isAdmin
        ? [
            _buildHeroStat('Open Slots', _openSlotsCount),
            _buildHeroStat('Pending', _pendingAssignmentsCount),
            _buildHeroStat('Unread', _unreadNotificationCount),
          ]
        : [
            _buildHeroStat('Upcoming', _upcomingServicesCount),
            _buildHeroStat('Pending', _pendingAssignmentsCount),
            _buildHeroStat('Unread', _unreadNotificationCount),
          ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppBranding.primaryDark, AppBranding.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withValues(alpha: .24),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _greeting(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: .82),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .78),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: stats),
        ],
      ),
    );
  }

  Widget _buildHeroStat(String label, int value) {
    return Container(
      width: 78,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .82),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildActionGrid(bool isAdmin) {
    final actions = [
      _HomeAction(
        label: 'Monthly',
        icon: Icons.calendar_month,
        color: Colors.indigo,
        page: const MonthlySchedulePage(),
      ),
      _HomeAction(
        label: 'My Schedule',
        icon: Icons.schedule,
        color: Colors.teal,
        page: const MySchedulePage(),
      ),
      _HomeAction(
        label: 'Assignments',
        icon: Icons.assignment,
        color: Colors.orange,
        page: const PendingAssignmentsPage(),
      ),
      _HomeAction(
        label: 'Availability',
        icon: Icons.event_available,
        color: Colors.green,
        page: const MyAvailabilityPage(),
      ),
    ];

    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.55,
          ),
          itemBuilder: (context, index) {
            final action = actions[index];

            return _buildActionCard(action);
          },
        ),
        if (isAdmin) ...[
          const SizedBox(height: 12),
          _buildAdminDashboardCard(),
        ],
      ],
    );
  }

  Widget _buildActionCard(_HomeAction action) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          _openPage(action.page);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(action.icon, color: action.color),
              ),
              Text(
                action.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminDashboardCard() {
    return Material(
      color: Colors.deepPurple.shade50,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          _openPage(const AdminDashboardPage());
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Colors.deepPurple),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Admin Dashboard',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextServiceCard() {
    final slot = _nextServiceSlot;

    if (slot == null) {
      return _buildEmptyNextServiceCard();
    }

    final service = slot['service_instances'] as Map<String, dynamic>?;

    if (service == null) {
      return _buildEmptyNextServiceCard();
    }

    final team = service['teams']?['name']?.toString() ?? 'Team not set';
    final roleName =
        slot['role_name']?.toString() ??
        slot['slot_name']?.toString() ??
        'Role not set';
    final status = _assignmentStatus(slot['slot_status']?.toString());

    return _buildDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.event, color: Colors.deepPurple.shade500),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _serviceName(service),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatServiceHeading(
                        service['service_date']?.toString(),
                        service['start_time']?.toString(),
                      ),
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildNextServiceDetail(Icons.groups, team),
          const SizedBox(height: 8),
          _buildNextServiceDetail(Icons.badge, roleName),
          const SizedBox(height: 8),
          _buildStatusChip(status),
        ],
      ),
    );
  }

  Widget _buildEmptyNextServiceCard() {
    return _buildDashboardCard(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy, color: Colors.grey.shade600, size: 34),
              const SizedBox(height: 10),
              const Text(
                'No upcoming assigned services',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextServiceDetail(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    final normalizedStatus = status.toLowerCase();
    final color = normalizedStatus.contains('confirmed')
        ? Colors.green
        : normalizedStatus.contains('pending')
        ? Colors.amber
        : normalizedStatus.contains('declined')
        ? Colors.red
        : Colors.grey;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.shade100,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.shade300),
        ),
        child: Text(
          status,
          style: TextStyle(
            color: color.shade900,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildMinistryCard(Map<String, dynamic> ministry) {
    final ministryName = ministry['name']?.toString() ?? '';
    final displayName = _ministryDisplayName(ministryName);
    final subtitle = _ministrySubtitle(ministry);
    final ministryId = ministry['id']?.toString() ?? '';
    final upcomingCount = _ministryUpcomingCounts[ministryId] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            _openPage(
              TeamsPage(ministryId: ministry['id'], ministryName: displayName),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppBranding.primaryLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _ministryIcon(ministryName),
                    color: AppBranding.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$upcomingCount Upcoming ${upcomingCount == 1 ? 'Service' : 'Services'}',
                        style: TextStyle(
                          color: AppBranding.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationBell() {
    final hasUnread = _unreadNotificationCount > 0;
    final badgeText = _unreadNotificationCount > 99
        ? '99+'
        : _unreadNotificationCount.toString();

    return ScaleTransition(
      scale: _bellPulseAnimation,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(
                Icons.notifications,
                color: hasUnread ? Colors.amber.shade700 : Colors.grey,
              ),
            ),
            if (hasUnread)
              Positioned(
                top: 1,
                right: 0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Container(
                    key: ValueKey(badgeText),
                    constraints: const BoxConstraints(
                      minWidth: 19,
                      minHeight: 19,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .22),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('HOME_PAGE_BUILD');
    final firstName = _profile?['first_name'] ?? 'User';

    final role = _profile?['role'] ?? 'volunteer';

    final isAdmin = role == 'admin';
    final visibleMinistries = _sortedMinistries();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppBranding.appName),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {
              _openPage(const NotificationsPage());
            },
            icon: _buildNotificationBell(),
            tooltip: 'Notifications',
          ),
          IconButton(
            onPressed: () {
              _openPage(const SettingsPage());
            },
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppBranding.primaryLight,
              Colors.purple.shade50,
              Colors.grey.shade50,
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _message != null
              ? Center(child: Text(_message!))
              : RefreshIndicator(
                  onRefresh: _loadHomeData,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      _buildHeroCard(firstName, isAdmin: isAdmin),
                      const SizedBox(height: 24),
                      _buildSectionHeader('Quick Actions'),
                      _buildActionGrid(isAdmin),
                      const SizedBox(height: 24),
                      _buildSectionHeader('Next Service'),
                      _buildNextServiceCard(),
                      const SizedBox(height: 24),
                      _buildSectionHeader('Ministries'),
                      if (visibleMinistries.isEmpty)
                        _buildDashboardCard(
                          child: const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Text('No ministries found.'),
                            ),
                          ),
                        )
                      else
                        ...visibleMinistries.map(_buildMinistryCard),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
