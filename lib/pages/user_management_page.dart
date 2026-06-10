import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_branding.dart';
import '../utils/error_messages.dart';

final supabase = Supabase.instance.client;

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _teamRoles = [];
  Map<String, Set<String>> _roleAssignmentsByUserId = {};
  bool _isLoading = true;
  String? _message;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;

      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      _currentUserId = currentUser.id;

      final currentProfile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', currentUser.id)
          .maybeSingle();
      final currentRole = currentProfile?['role']?.toString().toLowerCase();

      if (currentRole != 'admin') {
        setState(() {
          _message = 'Only admins can manage users.';
        });
        return;
      }

      final response = await supabase
          .from('profiles')
          .select('id, first_name, last_name, email, role, status')
          .order('first_name')
          .order('last_name')
          .order('email');

      final teamRolesResponse = await supabase
          .from('team_roles')
          .select('''
            id,
            team_id,
            role_name,
            quantity,
            display_order,
            teams (
              id,
              name,
              display_order
            )
          ''')
          .eq('is_active', true)
          .order('display_order')
          .order('role_name');

      final assignmentsResponse = await supabase
          .from('user_role_assignments')
          .select('user_id, team_role_id');
      final assignmentsByUserId = <String, Set<String>>{};

      for (final assignment in List<Map<String, dynamic>>.from(
        assignmentsResponse,
      )) {
        final userId = assignment['user_id']?.toString();
        final teamRoleId = assignment['team_role_id']?.toString();

        if (userId == null || teamRoleId == null) {
          continue;
        }

        assignmentsByUserId.putIfAbsent(userId, () => {}).add(teamRoleId);
      }

      setState(() {
        _users = List<Map<String, dynamic>>.from(response);
        _teamRoles = List<Map<String, dynamic>>.from(teamRolesResponse);
        _roleAssignmentsByUserId = assignmentsByUserId;
      });
    } catch (e, stackTrace) {
      logTechnicalError('UserManagementPage._loadUsers failed', e, stackTrace);
      setState(() {
        _message = friendlyErrorMessage(
          e,
          fallback: 'Unable to load users. Please try again.',
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

  Future<void> _confirmRoleChange(
    Map<String, dynamic> user,
    String newRole,
  ) async {
    final userId = user['id']?.toString();
    final currentRole = _role(user);

    if (userId == _currentUserId &&
        currentRole == 'admin' &&
        newRole != 'admin') {
      _showSnackBar('You cannot remove your own admin role.');
      return;
    }

    final confirmed = await _showConfirmationDialog(
      title: 'Change Role?',
      message: 'Change ${_displayName(user)} to ${_displayRole(newRole)}?',
      actionLabel: 'Change Role',
    );

    if (confirmed != true) {
      return;
    }

    await _updateUser(user, {'role': newRole}, 'Role updated');
  }

  Future<void> _confirmStatusChange(
    Map<String, dynamic> user,
    String newStatus,
  ) async {
    final confirmed = await _showConfirmationDialog(
      title: 'Change Status?',
      message: 'Set ${_displayName(user)} to ${_displayStatus(newStatus)}?',
      actionLabel: 'Change Status',
    );

    if (confirmed != true) {
      return;
    }

    await _updateUser(user, {'status': newStatus}, 'Status updated');
  }

  Future<void> _updateUser(
    Map<String, dynamic> user,
    Map<String, dynamic> values,
    String successMessage,
  ) async {
    final userId = user['id']?.toString();

    if (userId == null || userId.isEmpty) {
      _showSnackBar('Unable to update user: missing profile id.');
      return;
    }

    try {
      debugPrint(
        'UserManagementPage._updateUser executing: update profiles '
        'set $values where id = $userId',
      );

      final response = await supabase
          .from('profiles')
          .update(values)
          .eq('id', userId)
          .select('id, first_name, last_name, email, role, status');
      final updatedRows = List<Map<String, dynamic>>.from(response);

      if (updatedRows.isEmpty) {
        throw const PostgrestException(
          message: 'Profile update affected 0 rows.',
          code: 'PGRST_ZERO_ROWS',
          details:
              'The update statement completed but no profile row was returned. Check profiles RLS policies and table grants.',
          hint:
              'Expected update profiles set ... where id = ... to return one row.',
        );
      }

      final updatedUser = updatedRows.first;
      for (final entry in values.entries) {
        if (updatedUser[entry.key]?.toString() != entry.value?.toString()) {
          throw PostgrestException(
            message: 'Profile update verification failed.',
            code: 'PGRST_VERIFY_FAILED',
            details:
                'Column ${entry.key} expected ${entry.value}, got ${updatedUser[entry.key]}.',
            hint:
                'The update returned a row, but the requested value was not persisted.',
          );
        }
      }

      await _loadUsers();
      _showSnackBar(successMessage);
    } on PostgrestException catch (e, stackTrace) {
      logTechnicalError(
        'UserManagementPage._updateUser PostgREST failed '
        'message=${e.message} code=${e.code} details=${e.details} hint=${e.hint}',
        e,
        stackTrace,
      );
      _showSnackBar(
        'PostgREST error: ${e.message}'
        '${e.code == null ? '' : '\nCode: ${e.code}'}'
        '${e.details == null ? '' : '\nDetails: ${e.details}'}'
        '${e.hint == null ? '' : '\nHint: ${e.hint}'}',
      );
    } catch (e, stackTrace) {
      logTechnicalError('UserManagementPage._updateUser failed', e, stackTrace);
      _showSnackBar('Update error: $e');
    }
  }

  Future<void> _showRoleAssignmentsDialog(Map<String, dynamic> user) async {
    final userId = user['id']?.toString();

    if (userId == null || userId.isEmpty) {
      return;
    }

    final selectedRoleIds = Set<String>.from(
      _roleAssignmentsByUserId[userId] ?? const {},
    );
    final updatedRoleIds = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Roles for ${_displayName(user)}'),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                  maxWidth: 520,
                ),
                child: SizedBox(
                  width: double.maxFinite,
                  child: _teamRoles.isEmpty
                      ? const Text('No roles are available yet.')
                      : Scrollbar(
                          child: ListView(
                            shrinkWrap: true,
                            children: _buildTeamRoleSections(
                              selectedRoleIds,
                              setDialogState,
                            ),
                          ),
                        ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, selectedRoleIds);
                  },
                  child: const Text('Save Roles'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updatedRoleIds == null) {
      return;
    }

    await _saveRoleAssignments(userId, updatedRoleIds);
  }

  Future<void> _saveRoleAssignments(
    String userId,
    Set<String> updatedRoleIds,
  ) async {
    try {
      final currentRoleIds = _roleAssignmentsByUserId[userId] ?? const {};
      final roleIdsToAdd = updatedRoleIds.difference(currentRoleIds);
      final roleIdsToRemove = currentRoleIds.difference(updatedRoleIds);
      final currentUserId = supabase.auth.currentUser?.id;

      for (final roleId in roleIdsToAdd) {
        await supabase.from('user_role_assignments').insert({
          'user_id': userId,
          'team_role_id': roleId,
          'assigned_by': currentUserId,
        });
      }

      for (final roleId in roleIdsToRemove) {
        await supabase
            .from('user_role_assignments')
            .delete()
            .eq('user_id', userId)
            .eq('team_role_id', roleId);
      }

      await _loadUsers();
      _showSnackBar('Role assignments updated');
    } catch (e, stackTrace) {
      logTechnicalError(
        'UserManagementPage._saveRoleAssignments failed',
        e,
        stackTrace,
      );
      _showSnackBar(
        friendlyErrorMessage(
          e,
          fallback: 'Unable to update role assignments. Please try again.',
        ),
      );
    }
  }

  Future<bool?> _showConfirmationDialog({
    required String title,
    required String message,
    required String actionLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      return _users;
    }

    return _users.where((user) {
      final haystack = [
        user['first_name'],
        user['last_name'],
        user['email'],
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');

      return haystack.contains(query);
    }).toList();
  }

  int get _adminCount {
    return _users.where((user) => _role(user) == 'admin').length;
  }

  int get _activeCount {
    return _users.where((user) => _status(user) == 'active').length;
  }

  String _displayName(Map<String, dynamic> user) {
    final firstName = user['first_name']?.toString() ?? '';
    final lastName = user['last_name']?.toString() ?? '';
    final fullName = '$firstName $lastName'.trim();

    return fullName.isEmpty ? 'Unknown User' : fullName;
  }

  String _email(Map<String, dynamic> user) {
    return user['email']?.toString() ?? 'No email';
  }

  String _role(Map<String, dynamic> user) {
    final role = user['role']?.toString().trim().toLowerCase() ?? 'volunteer';

    return role.isEmpty ? 'volunteer' : role;
  }

  String _status(Map<String, dynamic> user) {
    final status = user['status']?.toString().trim().toLowerCase() ?? 'active';

    return status.isEmpty ? 'active' : status;
  }

  String _displayRole(String role) {
    return role == 'admin' ? 'Admin' : 'Volunteer';
  }

  String _displayStatus(String status) {
    return status == 'inactive' ? 'Inactive' : 'Active';
  }

  List<Widget> _buildTeamRoleSections(
    Set<String> selectedRoleIds,
    StateSetter setDialogState,
  ) {
    final rolesByTeam = <String, List<Map<String, dynamic>>>{};

    for (final role in _sortedTeamRoles) {
      rolesByTeam.putIfAbsent(_teamNameForRole(role), () => []).add(role);
    }

    final sections = <Widget>[];

    for (final entry in rolesByTeam.entries) {
      if (sections.isNotEmpty) {
        sections.add(const Divider(height: 24));
      }

      sections.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            entry.key,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );

      for (final role in entry.value) {
        final roleId = role['id']?.toString() ?? '';
        final isSelected = selectedRoleIds.contains(roleId);

        sections.add(
          CheckboxListTile(
            value: isSelected,
            title: Text(_baseRoleLabel(role)),
            subtitle: Text(_coveragePreview(role)),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) {
              setDialogState(() {
                if (value == true) {
                  selectedRoleIds.add(roleId);
                } else {
                  selectedRoleIds.remove(roleId);
                }
              });
            },
          ),
        );
      }
    }

    return sections;
  }

  List<Map<String, dynamic>> get _sortedTeamRoles {
    return List<Map<String, dynamic>>.from(_teamRoles)..sort((a, b) {
      final teamOrderCompare = _teamDisplayOrderForRole(
        a,
      ).compareTo(_teamDisplayOrderForRole(b));

      if (teamOrderCompare != 0) {
        return teamOrderCompare;
      }

      final teamCompare = _teamNameForRole(a).compareTo(_teamNameForRole(b));

      if (teamCompare != 0) {
        return teamCompare;
      }

      final orderCompare = _displayOrderForRole(
        a,
      ).compareTo(_displayOrderForRole(b));

      if (orderCompare != 0) {
        return orderCompare;
      }

      return _baseRoleLabel(a).compareTo(_baseRoleLabel(b));
    });
  }

  String _teamNameForRole(Map<String, dynamic> role) {
    final team = role['teams'];

    return team is Map<String, dynamic>
        ? team['name']?.toString() ?? 'Team'
        : 'Team';
  }

  int _teamDisplayOrderForRole(Map<String, dynamic> role) {
    final team = role['teams'];
    final displayOrder = team is Map<String, dynamic>
        ? team['display_order']
        : null;

    if (displayOrder is int) {
      return displayOrder;
    }

    return int.tryParse(displayOrder?.toString() ?? '') ?? 999999;
  }

  String _baseRoleLabel(Map<String, dynamic> role) {
    final roleName = role['role_name']?.toString().trim() ?? '';

    return roleName.isEmpty ? 'Role' : roleName;
  }

  String _coveragePreview(Map<String, dynamic> role) {
    final roleName = _baseRoleLabel(role);
    final quantity = _quantityForRole(role);

    if (quantity <= 1) {
      return 'Covers: $roleName';
    }

    final labels = List.generate(quantity, (index) => '$roleName ${index + 1}');

    return 'Covers: ${labels.join(', ')}';
  }

  int _quantityForRole(Map<String, dynamic> role) {
    final quantity = role['quantity'];

    if (quantity is int) {
      return quantity;
    }

    return int.tryParse(quantity?.toString() ?? '') ?? 1;
  }

  int _displayOrderForRole(Map<String, dynamic> role) {
    final displayOrder = role['display_order'];

    if (displayOrder is int) {
      return displayOrder;
    }

    return int.tryParse(displayOrder?.toString() ?? '') ?? 0;
  }

  String _assignedRoleSummary(Map<String, dynamic> user) {
    final userId = user['id']?.toString();
    final assignedRoleIds = _roleAssignmentsByUserId[userId] ?? const {};

    if (assignedRoleIds.isEmpty) {
      return 'No roles assigned';
    }

    return '${assignedRoleIds.length} role${assignedRoleIds.length == 1 ? '' : 's'} assigned';
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildSummaryCards() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildSummaryCard('Users', _users.length, Colors.deepPurple),
        _buildSummaryCard('Admins', _adminCount, Colors.blue),
        _buildSummaryCard('Active', _activeCount, Colors.green),
        _buildSummaryCard('Inactive', _users.length - _activeCount, Colors.red),
      ],
    );
  }

  Widget _buildSummaryCard(String label, int count, MaterialColor color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              color: color.shade700,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final role = _role(user);
    final status = _status(user);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppBranding.primaryLight,
                  child: Text(
                    _displayName(user).substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: AppBranding.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName(user),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _email(user),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildChip(_displayRole(role), Colors.blue),
                _buildChip(_displayStatus(status), Colors.green),
                DropdownButton<String>(
                  value: role == 'admin' ? 'admin' : 'volunteer',
                  items: const [
                    DropdownMenuItem(
                      value: 'volunteer',
                      child: Text('Volunteer'),
                    ),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (value) {
                    if (value == null || value == role) {
                      return;
                    }

                    _confirmRoleChange(user, value);
                  },
                ),
                DropdownButton<String>(
                  value: status == 'inactive' ? 'inactive' : 'active',
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                      value: 'inactive',
                      child: Text('Inactive'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null || value == status) {
                      return;
                    }

                    _confirmStatusChange(user, value);
                  },
                ),
                OutlinedButton.icon(
                  onPressed: () => _showRoleAssignmentsDialog(user),
                  icon: const Icon(Icons.assignment_ind_outlined),
                  label: const Text('Roles'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _assignedRoleSummary(user),
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.shade100),
      ),
      child: Text(
        label,
        style: TextStyle(color: color.shade700, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _filteredUsers;

    return Scaffold(
      appBar: AppBar(title: const Text('User Management')),
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
              onRefresh: _loadUsers,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummaryCards(),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search users',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (filteredUsers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No users found')),
                    )
                  else
                    ...filteredUsers.map(_buildUserCard),
                ],
              ),
            ),
    );
  }
}
