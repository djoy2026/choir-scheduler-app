import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'service_slots_page.dart';
import 'teams_page.dart';
import '../utils/error_messages.dart';
import '../utils/time_format.dart';
import '../utils/ui_helpers.dart';

final supabase = Supabase.instance.client;

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  bool _isLoading = true;
  bool _isAdmin = false;
  String? _message;
  String _greetingName = 'Admin';
  DateTime? _lastRefreshedAt;
  List<Map<String, dynamic>> _ministries = [];
  List<Map<String, dynamic>> _upcomingServices = [];
  List<Map<String, dynamic>> _pendingAssignments = [];
  int _openSlotCount = 0;
  int _pendingAssignmentCount = 0;
  int _fullyStaffedServiceCount = 0;
  int _servicesNeedingAttentionCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('No authenticated user found.');
      }

      final profile = await supabase
          .from('profiles')
          .select('role, first_name, email')
          .eq('id', user.id)
          .single();
      final role = profile['role']?.toString().trim().toLowerCase();

      if (role != 'admin') {
        setState(() {
          _isAdmin = false;
          _isLoading = false;
        });
        return;
      }

      final today = DateTime.now().toIso8601String().split('T').first;
      final ministriesResponse = await supabase
          .from('ministries')
          .select('id, name')
          .order('display_order');
      final servicesResponse = await supabase
          .from('service_instances')
          .select('''
            id,
            service_name,
            service_date,
            start_time,
            location,
            teams (
              id,
              name
            ),
            ministries (
              id,
              name
            ),
            service_slots (
              id,
              slot_name,
              role_name,
              slot_status,
              assigned_user_id
            )
          ''')
          .gte('service_date', today)
          .order('service_date')
          .order('start_time');
      final pendingResponse = await supabase
          .from('service_slots')
          .select('''
            id,
            slot_name,
            role_name,
            assigned_user_id,
            profiles!service_slots_assigned_user_id_fkey (
              first_name,
              last_name,
              email
            ),
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
          .eq('slot_status', 'pending')
          .gte('service_instances.service_date', today)
          .order('service_instances(service_date)')
          .limit(20);

      final services = List<Map<String, dynamic>>.from(servicesResponse);
      final upcomingServices = <Map<String, dynamic>>[];
      var openSlotCount = 0;
      var pendingAssignmentCount = 0;
      var fullyStaffedServiceCount = 0;
      var servicesNeedingAttentionCount = 0;

      for (final service in services) {
        final slots = List<Map<String, dynamic>>.from(
          service['service_slots'] ?? const [],
        );
        final openSlots = slots.where((slot) {
          final status = slot['slot_status']?.toString().trim().toLowerCase();
          return status == 'open';
        }).length;
        final pendingSlots = slots.where((slot) {
          final status = slot['slot_status']?.toString().trim().toLowerCase();
          return status == 'pending';
        }).length;
        final takenSlots = slots.where((slot) {
          final status = slot['slot_status']?.toString().trim().toLowerCase();
          return status == 'taken';
        }).length;
        final fullyStaffed =
            openSlots == 0 && pendingSlots == 0 && takenSlots > 0;

        openSlotCount += openSlots;
        pendingAssignmentCount += pendingSlots;

        if (fullyStaffed) {
          fullyStaffedServiceCount++;
        }

        if (openSlots > 0 || pendingSlots > 0) {
          servicesNeedingAttentionCount++;
        }

        upcomingServices.add({
          ...service,
          'open_slot_count': openSlots,
          'pending_slot_count': pendingSlots,
          'taken_slot_count': takenSlots,
        });
      }

      setState(() {
        _isAdmin = true;
        _greetingName =
            profile['first_name']?.toString().trim().isNotEmpty == true
            ? profile['first_name'].toString().trim()
            : profile['email']?.toString().trim() ?? 'Admin';
        _lastRefreshedAt = DateTime.now();
        _ministries = List<Map<String, dynamic>>.from(ministriesResponse);
        _upcomingServices = upcomingServices;
        _pendingAssignments = List<Map<String, dynamic>>.from(pendingResponse);
        _openSlotCount = openSlotCount;
        _pendingAssignmentCount = pendingAssignmentCount;
        _fullyStaffedServiceCount = fullyStaffedServiceCount;
        _servicesNeedingAttentionCount = servicesNeedingAttentionCount;
      });
    } catch (e, stackTrace) {
      logTechnicalError(
        'AdminDashboardPage._loadDashboard failed',
        e,
        stackTrace,
      );
      setState(() {
        _message = friendlyErrorMessage(
          e,
          fallback: 'Unable to load admin dashboard. Please try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatRefreshTime(DateTime? value) {
    if (value == null) {
      return 'Not refreshed yet';
    }

    final hour = value.hour > 12
        ? value.hour - 12
        : value.hour == 0
        ? 12
        : value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';

    return 'Last refreshed $hour:$minute $period';
  }

  Future<void> _openMinistryPicker() async {
    if (_ministries.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No ministries found.')));
      return;
    }

    final ministry = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Choose Ministry',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ..._ministries.map((ministry) {
                return ListTile(
                  title: Text(ministry['name']?.toString() ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context, ministry);
                  },
                );
              }),
            ],
          ),
        );
      },
    );

    if (ministry == null || !mounted) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeamsPage(
          ministryId: ministry['id'],
          ministryName: ministry['name']?.toString() ?? 'Ministry',
        ),
      ),
    );

    if (mounted) {
      await _loadDashboard();
    }
  }

  void _showMonthlyPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Monthly Schedule shortcut placeholder')),
    );
  }

  Future<void> _openService(Map<String, dynamic> service) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceSlotsPage(
          serviceInstanceId: service['id'],
          serviceTitle: formatServiceHeading(
            service['service_date']?.toString(),
            service['start_time']?.toString(),
          ),
          serviceDate: formatNumericDate(service['service_date']?.toString()),
        ),
      ),
    );

    if (mounted) {
      await _loadDashboard();
    }
  }

  String _assignedVolunteerName(Map<String, dynamic> slot) {
    final profile = slot['profiles'];

    if (profile is Map<String, dynamic>) {
      final firstName = profile['first_name']?.toString().trim() ?? '';
      final lastName = profile['last_name']?.toString().trim() ?? '';
      final fullName = '$firstName $lastName'.trim();

      if (fullName.isNotEmpty) {
        return fullName;
      }

      final email = profile['email']?.toString().trim();

      if (email != null && email.isNotEmpty) {
        return email;
      }
    }

    return 'Unknown User';
  }

  Widget _buildSummaryGrid() {
    final cards = [
      _SummaryCard(
        label: 'Open Slots',
        value: _openSlotCount,
        icon: Icons.event_busy,
        color: Colors.amber,
      ),
      _SummaryCard(
        label: 'Pending Assignments',
        value: _pendingAssignmentCount,
        icon: Icons.assignment_late,
        color: Colors.blue,
      ),
      _SummaryCard(
        label: 'Fully Staffed Services',
        value: _fullyStaffedServiceCount,
        icon: Icons.verified,
        color: Colors.green,
      ),
      _SummaryCard(
        label: 'Services Needing Attention',
        value: _servicesNeedingAttentionCount,
        icon: Icons.priority_high,
        color: Colors.red,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 700 ? 4 : 2;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: constraints.maxWidth >= 700 ? 1.45 : 1.15,
          children: cards,
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;

        return GridView.count(
          crossAxisCount: wide ? 3 : 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: wide ? 2.6 : 4.2,
          children: [
            _ActionCard(
              icon: Icons.calendar_month,
              label: 'Monthly Schedule',
              onTap: _showMonthlyPlaceholder,
            ),
            _ActionCard(
              icon: Icons.groups,
              label: 'Teams & Roles',
              onTap: () {
                _openMinistryPicker();
              },
            ),
            _ActionCard(
              icon: Icons.event_note,
              label: 'Services',
              onTap: () {
                _openMinistryPicker();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildOpenServicesList() {
    if (_upcomingServices.isEmpty) {
      return const Text('No upcoming services found.');
    }

    return Column(
      children: _upcomingServices.take(10).map((service) {
        final team = service['teams'];
        final openSlots = service['open_slot_count'] as int? ?? 0;
        final pendingSlots = service['pending_slot_count'] as int? ?? 0;
        final takenSlots = service['taken_slot_count'] as int? ?? 0;
        final statusColor = _serviceStatusColor(
          openSlots: openSlots,
          pendingSlots: pendingSlots,
          takenSlots: takenSlots,
        );
        final statusText = _serviceStatusText(
          openSlots: openSlots,
          pendingSlots: pendingSlots,
          takenSlots: takenSlots,
        );

        return AccentCard(
          accentColor: statusColor.shade600,
          color: statusColor.shade50,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: statusColor.shade100,
              foregroundColor: statusColor.shade900,
              child: Icon(_serviceStatusIcon(openSlots, pendingSlots)),
            ),
            title: Text(
              formatServiceHeading(
                service['service_date']?.toString(),
                service['start_time']?.toString(),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: serviceTitleTextStyle,
            ),
            subtitle: Text(
              '${team?['name'] ?? ''}\n'
              '${service['location'] ?? ''}',
              style: mutedTextStyle(context),
            ),
            trailing: Text(statusText),
            onTap: () {
              _openService(service);
            },
          ),
        );
      }).toList(),
    );
  }

  MaterialColor _serviceStatusColor({
    required int openSlots,
    required int pendingSlots,
    required int takenSlots,
  }) {
    if (openSlots > 5) {
      return Colors.red;
    }

    if (openSlots > 0) {
      return Colors.amber;
    }

    if (pendingSlots > 0) {
      return Colors.blue;
    }

    if (takenSlots > 0) {
      return Colors.green;
    }

    return Colors.grey;
  }

  IconData _serviceStatusIcon(int openSlots, int pendingSlots) {
    if (openSlots > 5) {
      return Icons.priority_high;
    }

    if (openSlots > 0) {
      return Icons.event_busy;
    }

    if (pendingSlots > 0) {
      return Icons.assignment_late;
    }

    return Icons.verified;
  }

  String _serviceStatusText({
    required int openSlots,
    required int pendingSlots,
    required int takenSlots,
  }) {
    if (openSlots > 5) {
      return '$openSlots open';
    }

    if (openSlots > 0) {
      return '$openSlots open';
    }

    if (pendingSlots > 0) {
      return '$pendingSlots pending';
    }

    if (takenSlots > 0) {
      return 'Staffed';
    }

    return 'No slots';
  }

  Widget _buildPendingAssignmentsList() {
    if (_pendingAssignments.isEmpty) {
      return const Text('No pending assignments.');
    }

    return Column(
      children: _pendingAssignments.take(10).map((slot) {
        final service = slot['service_instances'];
        final assignedName = _assignedVolunteerName(slot);

        return AccentCard(
          accentColor: Colors.blue.shade500,
          child: ListTile(
            title: Text(slot['role_name'] ?? slot['slot_name'] ?? ''),
            subtitle: Text(
              'Assigned to: $assignedName\n'
              '${formatServiceHeading(service?['service_date']?.toString(), service?['start_time']?.toString())}',
              style: mutedTextStyle(context),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: RefreshIndicator(
        onRefresh: _loadDashboard,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(child: Text(_message!)),
              )
            else if (!_isAdmin)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(
                  child: Text('You do not have permission to view this page.'),
                ),
              )
            else ...[
              Text(
                'Welcome back, $_greetingName',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatRefreshTime(_lastRefreshedAt),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              _buildSummaryGrid(),
              const SizedBox(height: 24),
              Text('Quick Actions', style: sectionHeaderTextStyle(context)),
              const SizedBox(height: 12),
              _buildQuickActions(),
              const SizedBox(height: 24),
              Text('Upcoming Services', style: sectionHeaderTextStyle(context)),
              const SizedBox(height: 12),
              _buildOpenServicesList(),
              const SizedBox(height: 24),
              Text(
                'Pending Assignments',
                style: sectionHeaderTextStyle(context),
              ),
              const SizedBox(height: 12),
              _buildPendingAssignmentsList(),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final MaterialColor color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 28, color: color.shade800),
            Text(
              '$value',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color.shade900,
              ),
            ),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: color.shade900),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
