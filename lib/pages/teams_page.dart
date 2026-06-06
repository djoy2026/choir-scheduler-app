import 'service_instances_page.dart';
import 'team_management_page.dart';
import 'team_roles_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_branding.dart';
import '../utils/error_messages.dart';

final supabase = Supabase.instance.client;

class TeamsPage extends StatefulWidget {
  final String ministryId;

  final String ministryName;

  const TeamsPage({
    super.key,
    required this.ministryId,
    required this.ministryName,
  });

  @override
  State<TeamsPage> createState() => _TeamsPageState();
}

class _TeamsPageState extends State<TeamsPage> {
  List<dynamic> _teams = [];

  bool _isLoading = true;

  bool _isAdmin = false;

  int _volunteerCount = 0;

  int _openPositionsCount = 0;

  int _upcomingServicesCount = 0;

  String? _message;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    try {
      final user = supabase.auth.currentUser;

      if (user != null) {
        final profile = await supabase
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .single();

        final role = profile['role']?.toString().trim().toLowerCase();

        _isAdmin = role == 'admin';
      }

      final response = await supabase
          .from('teams')
          .select()
          .eq('ministry_id', widget.ministryId)
          .eq('is_active', true)
          .order('display_order')
          .order('name');
      final teams = List<Map<String, dynamic>>.from(response);
      teams.sort(_compareTeamsForMinistry);
      final teamIds = teams
          .map((team) => team['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final today = _dateKey(DateTime.now());

      final teamMembersResponse = teamIds.isEmpty
          ? <dynamic>[]
          : await supabase
                .from('team_members')
                .select('user_id')
                .inFilter('team_id', teamIds);

      final upcomingServicesResponse = teamIds.isEmpty
          ? <dynamic>[]
          : await supabase
                .from('service_instances')
                .select('id')
                .eq('ministry_id', widget.ministryId)
                .inFilter('team_id', teamIds)
                .gte('service_date', today);

      final openPositionsResponse = teamIds.isEmpty
          ? <dynamic>[]
          : await supabase
                .from('service_slots')
                .select('''
            id,
            service_instances!inner (
              team_id,
              ministry_id,
              service_date
            )
          ''')
                .eq('slot_status', 'open')
                .eq('service_instances.ministry_id', widget.ministryId)
                .inFilter('service_instances.team_id', teamIds)
                .gte('service_instances.service_date', today);
      final volunteerIds = <String>{};

      for (final member in teamMembersResponse) {
        if (member is! Map<String, dynamic>) {
          continue;
        }

        final userId = member['user_id']?.toString();

        if (userId != null && userId.isNotEmpty) {
          volunteerIds.add(userId);
        }
      }

      setState(() {
        _teams = teams;
        _volunteerCount = volunteerIds.length;
        _openPositionsCount = openPositionsResponse.length;
        _upcomingServicesCount = upcomingServicesResponse.length;
      });
    } catch (e, stackTrace) {
      logTechnicalError('TeamsPage._loadTeams failed', e, stackTrace);
      setState(() {
        _message = friendlyErrorMessage(
          e,
          fallback: 'Unable to load teams. Please try again.',
        );
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _dateKey(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  int _compareTeamsForMinistry(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aName = a['name']?.toString() ?? '';
    final bName = b['name']?.toString() ?? '';
    final aPriority = _displayOrder(a);
    final bPriority = _displayOrder(b);

    if (aPriority != bPriority) {
      return aPriority.compareTo(bPriority);
    }

    return aName.toLowerCase().compareTo(bName.toLowerCase());
  }

  int _displayOrder(Map<String, dynamic> team) {
    final value = team['display_order'];

    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 999;
  }

  String _displayMinistryName() {
    final name = widget.ministryName;

    if (name.contains('Children\'s Ministry')) {
      return 'Kids Class Schedule';
    }

    return name;
  }

  String _displayTeamName(Map<String, dynamic> team) {
    final name = team['name']?.toString() ?? '';
    final normalizedName = name.trim().toLowerCase();

    if (normalizedName == 'all kids choir volunteers' ||
        normalizedName == 'all main choir volunteers') {
      return 'Choir Volunteers';
    }

    return name;
  }

  IconData _teamIcon(String name) {
    final normalizedName = name.toLowerCase();

    if (normalizedName.contains('nursery') ||
        normalizedName.contains('kindies') ||
        normalizedName.contains('year old') ||
        normalizedName.contains('grade')) {
      return Icons.child_care;
    }

    if (normalizedName.contains('choir')) {
      return Icons.music_note;
    }

    return Icons.groups;
  }

  Widget _buildSummaryCard() {
    final isKidsClass = _displayMinistryName() == 'Kids Class Schedule';
    final stats = isKidsClass
        ? [
            _buildSummaryStat('Classroom Teams', _teams.length),
            _buildSummaryStat('Volunteers', _volunteerCount),
            _buildSummaryStat('Open Positions', _openPositionsCount),
          ]
        : [
            _buildSummaryStat('Teams', _teams.length),
            _buildSummaryStat('Volunteers', _volunteerCount),
            _buildSummaryStat('Upcoming Services', _upcomingServicesCount),
          ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppBranding.primaryDark, AppBranding.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withValues(alpha: .22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _displayMinistryName(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isKidsClass
                ? 'Classroom volunteer scheduling'
                : 'Team scheduling overview',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .78),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: stats),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .14),
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
              fontSize: 20,
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

  Widget _buildTeamCard(Map<String, dynamic> team) {
    final displayName = _displayTeamName(team);
    final databaseName = team['name']?.toString() ?? '';
    final description = team['description']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceInstancesPage(
                  ministryId: widget.ministryId,
                  teamId: team['id'],
                  teamName: databaseName,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppBranding.primaryLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _teamIcon(databaseName),
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
                      if (description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            description,
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
                if (_isAdmin)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'manage_roles') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TeamRolesPage(
                              ministryId: widget.ministryId,
                              ministryName: _displayMinistryName(),
                              teamId: team['id'],
                              teamName: databaseName,
                            ),
                          ),
                        );
                      }
                    },
                    itemBuilder: (context) {
                      return const [
                        PopupMenuItem(
                          value: 'manage_roles',
                          child: Text('Manage Roles'),
                        ),
                      ];
                    },
                  )
                else
                  Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_displayMinistryName()),
        actions: [
          if (_isAdmin)
            IconButton(
              tooltip: 'Manage Teams',
              icon: const Icon(Icons.tune),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TeamManagementPage(
                      ministryId: widget.ministryId,
                      ministryName: _displayMinistryName(),
                    ),
                  ),
                );

                if (mounted) {
                  _loadTeams();
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _message != null
          ? Center(child: Text(_message!))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSummaryCard(),
                const SizedBox(height: 20),
                ..._teams.map((team) {
                  return _buildTeamCard(Map<String, dynamic>.from(team));
                }),
              ],
            ),
    );
  }
}
