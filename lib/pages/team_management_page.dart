import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_branding.dart';
import '../utils/error_messages.dart';

final supabase = Supabase.instance.client;

const _classroomTeamOrders = {
  'Nursery': 10,
  'Kindies': 20,
  '2 Year Olds': 30,
  '3 Year Olds': 40,
  '4 Year Olds': 50,
  '1st Grade': 60,
  '2nd Grade': 70,
  '3rd Grade': 80,
  '4th Grade': 90,
  '5th Grade': 100,
};

class TeamManagementPage extends StatefulWidget {
  final String ministryId;
  final String ministryName;

  const TeamManagementPage({
    super.key,
    required this.ministryId,
    required this.ministryName,
  });

  @override
  State<TeamManagementPage> createState() => _TeamManagementPageState();
}

class _TeamManagementPageState extends State<TeamManagementPage> {
  List<Map<String, dynamic>> _teams = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('No authenticated user found.');
      }

      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();

      final role = profile['role']?.toString().trim().toLowerCase();
      final isAdmin = role == 'admin';

      if (!isAdmin) {
        setState(() {
          _isAdmin = false;
          _teams = [];
          _message = 'Only admins can manage teams.';
        });
        return;
      }

      final response = await supabase
          .from('teams')
          .select(
            'id, ministry_id, name, description, display_order, is_active',
          )
          .eq('ministry_id', widget.ministryId)
          .order('display_order')
          .order('name');

      setState(() {
        _isAdmin = true;
        _teams = List<Map<String, dynamic>>.from(response);
      });
    } catch (e, stackTrace) {
      logTechnicalError('TeamManagementPage._loadTeams failed', e, stackTrace);
      setState(() {
        _message = friendlyErrorMessage(
          e,
          fallback: 'Unable to load teams. Please try again.',
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

  Future<void> _showCreateTeamDialog() async {
    final teamName = await showDialog<String>(
      context: context,
      builder: (_) =>
          const _TeamNameDialog(title: 'Create Team', actionLabel: 'Create'),
    );

    if (teamName == null || teamName.isEmpty) {
      return;
    }

    try {
      final displayOrder = await _nextTeamDisplayOrder();
      _logTeamSql('Create Team INSERT public.teams', {
        'ministry_id': widget.ministryId,
        'name': teamName,
        'display_order': displayOrder,
        'is_active': true,
      });

      await supabase.from('teams').insert({
        'ministry_id': widget.ministryId,
        'name': teamName,
        'display_order': displayOrder,
        'is_active': true,
      });

      await _loadTeams();
      _showSnackBar('Team created');
    } catch (e, stackTrace) {
      _showDiagnosticError('Create Team failed', e, stackTrace);
    }
  }

  Future<void> _showEditTeamDialog(Map<String, dynamic> team) async {
    final teamName = await showDialog<String>(
      context: context,
      builder: (_) => _TeamNameDialog(
        title: 'Edit Team',
        actionLabel: 'Save',
        initialValue: team['name']?.toString() ?? '',
      ),
    );

    if (teamName == null || teamName.isEmpty) {
      return;
    }

    try {
      _logTeamSql('Rename Team UPDATE public.teams', {
        'id': team['id'],
        'name': teamName,
      });

      await supabase
          .from('teams')
          .update({'name': teamName})
          .eq('id', team['id']);

      await _loadTeams();
      _showSnackBar('Team updated');
    } catch (e, stackTrace) {
      _showDiagnosticError('Rename Team failed', e, stackTrace);
    }
  }

  Future<void> _setTeamActive(
    Map<String, dynamic> team, {
    required bool isActive,
  }) async {
    try {
      final sectionTeams = isActive ? _activeTeams : _inactiveTeams;
      _logTeamSql(
        isActive
            ? 'Activate Team UPDATE public.teams'
            : 'Deactivate Team UPDATE public.teams',
        {
          'id': team['id'],
          'is_active': isActive,
          'display_order': _nextDisplayOrder(sectionTeams),
        },
      );

      await supabase
          .from('teams')
          .update({
            'is_active': isActive,
            'display_order': _nextDisplayOrder(sectionTeams),
          })
          .eq('id', team['id']);

      await _loadTeams();
      _showSnackBar(isActive ? 'Team activated' : 'Team deactivated');
    } catch (e, stackTrace) {
      _showDiagnosticError(
        isActive ? 'Activate Team failed' : 'Deactivate Team failed',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _moveTeam(Map<String, dynamic> team, int direction) async {
    final isActive = _isActive(team);
    final sectionTeams = isActive ? _activeTeams : _inactiveTeams;
    final currentIndex = sectionTeams.indexWhere(
      (sectionTeam) => sectionTeam['id'] == team['id'],
    );
    final targetIndex = currentIndex + direction;

    if (currentIndex == -1 ||
        targetIndex < 0 ||
        targetIndex >= sectionTeams.length) {
      return;
    }

    final targetTeam = sectionTeams[targetIndex];
    final currentDisplayOrder = _displayOrder(team);
    final targetDisplayOrder = _displayOrder(targetTeam);

    try {
      _logTeamSql(
        direction < 0
            ? 'Move Up selected team UPDATE public.teams'
            : 'Move Down selected team UPDATE public.teams',
        {
          'id': team['id'],
          'display_order': targetDisplayOrder,
          'swap_with_team_id': targetTeam['id'],
        },
      );

      await supabase
          .from('teams')
          .update({'display_order': targetDisplayOrder})
          .eq('id', team['id']);

      _logTeamSql(
        direction < 0
            ? 'Move Up target team UPDATE public.teams'
            : 'Move Down target team UPDATE public.teams',
        {
          'id': targetTeam['id'],
          'display_order': currentDisplayOrder,
          'swap_with_team_id': team['id'],
        },
      );

      await supabase
          .from('teams')
          .update({'display_order': currentDisplayOrder})
          .eq('id', targetTeam['id']);

      await _loadTeams();
    } catch (e, stackTrace) {
      _showDiagnosticError(
        direction < 0 ? 'Move Up failed' : 'Move Down failed',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _moveTeamToEdge(
    Map<String, dynamic> team, {
    required bool moveToTop,
  }) async {
    final isActive = _isActive(team);
    final sectionTeams = isActive ? _activeTeams : _inactiveTeams;
    final currentIndex = sectionTeams.indexWhere(
      (sectionTeam) => sectionTeam['id'] == team['id'],
    );

    if (currentIndex == -1 ||
        (moveToTop && currentIndex == 0) ||
        (!moveToTop && currentIndex == sectionTeams.length - 1)) {
      return;
    }

    final reorderedTeams = [...sectionTeams];
    final movedTeam = reorderedTeams.removeAt(currentIndex);

    if (moveToTop) {
      reorderedTeams.insert(0, movedTeam);
    } else {
      reorderedTeams.add(movedTeam);
    }

    try {
      await _applyPositionOrder(reorderedTeams);
      await _loadTeams();
    } catch (e, stackTrace) {
      logTechnicalError(
        'TeamManagementPage._moveTeamToEdge failed',
        e,
        stackTrace,
      );
      _showSnackBar(
        friendlyErrorMessage(
          e,
          fallback: 'Unable to reorder teams. Please try again.',
        ),
      );
    }
  }

  Future<void> _normalizeOrder() async {
    try {
      await _applyPositionOrder(_activeTeams);
      await _applyPositionOrder(_inactiveTeams);
      await _loadTeams();
      _showSnackBar('Team order normalized');
    } catch (e, stackTrace) {
      logTechnicalError(
        'TeamManagementPage._normalizeOrder failed',
        e,
        stackTrace,
      );
      _showSnackBar(
        friendlyErrorMessage(
          e,
          fallback: 'Unable to normalize team order. Please try again.',
        ),
      );
    }
  }

  Future<void> _resetClassroomOrder() async {
    try {
      for (final team in _teams) {
        final teamName = team['name']?.toString() ?? '';
        final predefinedOrder = _classroomTeamOrders[teamName];

        if (predefinedOrder == null) {
          continue;
        }

        await supabase
            .from('teams')
            .update({'display_order': predefinedOrder})
            .eq('id', team['id']);
      }

      final customTeams = _teams.where((team) {
        final teamName = team['name']?.toString() ?? '';

        return !_classroomTeamOrders.containsKey(teamName);
      }).toList();

      for (var index = 0; index < customTeams.length; index += 1) {
        await supabase
            .from('teams')
            .update({'display_order': 110 + (index * 10)})
            .eq('id', customTeams[index]['id']);
      }

      await _loadTeams();
      _showSnackBar('Classroom order reset');
    } catch (e, stackTrace) {
      logTechnicalError(
        'TeamManagementPage._resetClassroomOrder failed',
        e,
        stackTrace,
      );
      _showSnackBar(
        friendlyErrorMessage(
          e,
          fallback: 'Unable to reset classroom order. Please try again.',
        ),
      );
    }
  }

  Future<void> _confirmDeleteTeam(Map<String, dynamic> team) async {
    try {
      final hasHistoricalData = await _teamHasHistoricalData(team['id']);

      if (hasHistoricalData) {
        _showSnackBar(
          'This team contains historical scheduling data. '
          'Deactivate the team instead.',
        );
        return;
      }

      if (!mounted) {
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Delete Team?'),
            content: const Text('This action cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      _logTeamSql('Delete Team DELETE public.teams', {'id': team['id']});
      await supabase.from('teams').delete().eq('id', team['id']);
      await _loadTeams();
      _showSnackBar('Team deleted');
    } catch (e, stackTrace) {
      _showDiagnosticError('Delete Team failed', e, stackTrace);
    }
  }

  Future<bool> _teamHasHistoricalData(dynamic teamId) async {
    final teamMembersResponse = await supabase
        .from('team_members')
        .select('id')
        .eq('team_id', teamId)
        .limit(1);

    if (teamMembersResponse.isNotEmpty) {
      return true;
    }

    final serviceInstancesResponse = await supabase
        .from('service_instances')
        .select('id')
        .eq('team_id', teamId)
        .limit(1);

    if (serviceInstancesResponse.isNotEmpty) {
      return true;
    }

    final serviceSlotsResponse = await supabase
        .from('service_slots')
        .select('''
          id,
          service_instances!inner (
            team_id
          )
        ''')
        .eq('service_instances.team_id', teamId)
        .limit(1);

    return serviceSlotsResponse.isNotEmpty;
  }

  Future<void> _applyPositionOrder(List<Map<String, dynamic>> teams) async {
    for (var index = 0; index < teams.length; index += 1) {
      await supabase
          .from('teams')
          .update({'display_order': (index + 1) * 10})
          .eq('id', teams[index]['id']);
    }
  }

  Future<int> _nextTeamDisplayOrder() async {
    final response = await supabase
        .from('teams')
        .select('display_order')
        .eq('ministry_id', widget.ministryId)
        .order('display_order', ascending: false)
        .limit(1);
    final teams = List<Map<String, dynamic>>.from(response);

    if (teams.isEmpty) {
      return 10;
    }

    return _displayOrder(teams.first) + 10;
  }

  List<Map<String, dynamic>> get _activeTeams {
    return _teams.where(_isActive).toList();
  }

  List<Map<String, dynamic>> get _inactiveTeams {
    return _teams.where((team) => !_isActive(team)).toList();
  }

  bool _isActive(Map<String, dynamic> team) {
    return team['is_active'] != false;
  }

  int _displayOrder(Map<String, dynamic> team) {
    final value = team['display_order'];

    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 999;
  }

  int _nextDisplayOrder(List<Map<String, dynamic>> teams) {
    if (teams.isEmpty) {
      return 10;
    }

    final maxOrder = teams.map(_displayOrder).reduce((a, b) => a > b ? a : b);

    return maxOrder + 10;
  }

  bool get _isKidsClassSchedule {
    final normalizedName = widget.ministryName.trim().toLowerCase();

    return normalizedName == 'kids class schedule' ||
        normalizedName == 'children\'s ministry' ||
        normalizedName == 'children\'s ministry live schedule';
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _logTeamSql(String action, Map<String, dynamic> values) {
    debugPrint('TeamManagement SQL: $action');
    debugPrint('TeamManagement SQL values: $values');
  }

  void _showDiagnosticError(
    String actionContext,
    Object error,
    StackTrace stackTrace,
  ) {
    logTechnicalError(
      'TeamManagementPage diagnostic: $actionContext',
      error,
      stackTrace,
    );

    if (error is PostgrestException) {
      debugPrint('PostgrestException message: ${error.message}');
      debugPrint('PostgrestException details: ${error.details}');
      debugPrint('PostgrestException hint: ${error.hint}');
      debugPrint('PostgrestException code: ${error.code}');
    }

    if (!mounted) {
      return;
    }

    final diagnosticMessage = error is PostgrestException
        ? 'Permission error:\n'
              'message: ${error.message}\n'
              'details: ${error.details}\n'
              'hint: ${error.hint}\n'
              'code: ${error.code}'
        : '$actionContext:\n$error';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(diagnosticMessage),
        duration: const Duration(seconds: 12),
      ),
    );
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> teams) {
    if (teams.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Text(
          title == 'Active Teams' ? 'No active teams' : 'No inactive teams',
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        ...teams.map((team) {
          final index = teams.indexOf(team);

          return _buildTeamCard(
            team,
            canMoveUp: index > 0,
            canMoveDown: index < teams.length - 1,
          );
        }),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildTeamCard(
    Map<String, dynamic> team, {
    required bool canMoveUp,
    required bool canMoveDown,
  }) {
    final isActive = _isActive(team);
    final name = team['name']?.toString() ?? 'Unnamed Team';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive
              ? AppBranding.primaryLight
              : Colors.grey.shade200,
          child: Icon(
            isActive ? Icons.groups : Icons.visibility_off,
            color: isActive ? AppBranding.primary : Colors.grey.shade600,
          ),
        ),
        title: Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Display order ${_displayOrder(team)} • ${isActive ? 'Active' : 'Inactive'}',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: canMoveUp ? () => _moveTeam(team, -1) : null,
                  icon: const Icon(Icons.arrow_upward, size: 16),
                  label: const Text('Move Up'),
                ),
                OutlinedButton.icon(
                  onPressed: canMoveDown ? () => _moveTeam(team, 1) : null,
                  icon: const Icon(Icons.arrow_downward, size: 16),
                  label: const Text('Move Down'),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _showEditTeamDialog(team);
                return;
              case 'move_to_top':
                _moveTeamToEdge(team, moveToTop: true);
                return;
              case 'move_to_bottom':
                _moveTeamToEdge(team, moveToTop: false);
                return;
              case 'activate':
                _setTeamActive(team, isActive: true);
                return;
              case 'deactivate':
                _setTeamActive(team, isActive: false);
                return;
              case 'delete':
                _confirmDeleteTeam(team);
                return;
            }
          },
          itemBuilder: (context) {
            return [
              const PopupMenuItem(value: 'edit', child: Text('Edit Name')),
              PopupMenuItem(
                value: 'move_to_top',
                enabled: canMoveUp,
                child: const Text('Move To Top'),
              ),
              PopupMenuItem(
                value: 'move_to_bottom',
                enabled: canMoveDown,
                child: const Text('Move To Bottom'),
              ),
              PopupMenuItem(
                value: isActive ? 'deactivate' : 'activate',
                child: Text(isActive ? 'Deactivate' : 'Activate'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete Team')),
            ];
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTeams = _activeTeams;
    final inactiveTeams = _inactiveTeams;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Teams'),
        actions: [
          if (_isAdmin)
            IconButton(
              tooltip: 'Create Team',
              onPressed: _showCreateTeamDialog,
              icon: const Icon(Icons.add),
            ),
          if (_isAdmin)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'normalize_order':
                    _normalizeOrder();
                    return;
                  case 'reset_classroom_order':
                    _resetClassroomOrder();
                    return;
                }
              },
              itemBuilder: (context) {
                return [
                  const PopupMenuItem(
                    value: 'normalize_order',
                    child: Text('Normalize Order'),
                  ),
                  if (_isKidsClassSchedule)
                    const PopupMenuItem(
                      value: 'reset_classroom_order',
                      child: Text('Reset Classroom Order'),
                    ),
                ];
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _message != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_message!, textAlign: TextAlign.center),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadTeams,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppBranding.primaryDark, AppBranding.primary],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.ministryName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Create, reorder, activate and deactivate teams.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .82),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildSection('Active Teams', activeTeams),
                  _buildSection('Inactive Teams', inactiveTeams),
                ],
              ),
            ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showCreateTeamDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create Team'),
            )
          : null,
    );
  }
}

class _TeamNameDialog extends StatefulWidget {
  final String title;
  final String actionLabel;
  final String initialValue;

  const _TeamNameDialog({
    required this.title,
    required this.actionLabel,
    this.initialValue = '',
  });

  @override
  State<_TeamNameDialog> createState() => _TeamNameDialogState();
}

class _TeamNameDialogState extends State<_TeamNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Team name',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, _controller.text.trim());
          },
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
