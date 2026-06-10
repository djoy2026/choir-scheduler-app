import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/error_messages.dart';

final supabase = Supabase.instance.client;

enum _RecipientGroup {
  allUsers,
  kidsClassSchedule,
  kidsChoir,
  mainChoir,
  adminsOnly,
  specificRole,
}

class BroadcastMessagePage extends StatefulWidget {
  const BroadcastMessagePage({super.key});

  @override
  State<BroadcastMessagePage> createState() => _BroadcastMessagePageState();
}

class _BroadcastMessagePageState extends State<BroadcastMessagePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  _RecipientGroup _recipientGroup = _RecipientGroup.allUsers;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isAdmin = false;
  String? _message;
  int _recipientCount = 0;
  List<Map<String, dynamic>> _teamRoles = [];
  String? _selectedTeamRoleId;

  @override
  void initState() {
    super.initState();
    _loadRecipientCount();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipientCount() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await _verifyAdmin();
      await _loadTeamRoles();
      final recipientIds = await _loadRecipientIds();

      if (!mounted) return;

      setState(() {
        _isAdmin = true;
        _recipientCount = recipientIds.length;
      });
    } catch (e, stackTrace) {
      logTechnicalError(
        'BroadcastMessagePage._loadRecipientCount failed',
        e,
        stackTrace,
      );
      if (!mounted) return;

      setState(() {
        _message = friendlyErrorMessage(
          e,
          fallback: 'Unable to load broadcast recipients. Please try again.',
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

  Future<void> _verifyAdmin() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('User not logged in');
    }

    final profile = await supabase
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    final role = profile?['role']?.toString().trim().toLowerCase();

    if (role != 'admin') {
      throw Exception('Only admins can send broadcast messages.');
    }
  }

  Future<Set<String>> _loadRecipientIds() async {
    switch (_recipientGroup) {
      case _RecipientGroup.allUsers:
        return _loadProfileIds(role: null);
      case _RecipientGroup.adminsOnly:
        return _loadProfileIds(role: 'admin');
      case _RecipientGroup.specificRole:
        return _loadSpecificRoleRecipientIds();
      case _RecipientGroup.kidsClassSchedule:
        return _loadTeamMemberIds(const {
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
        });
      case _RecipientGroup.kidsChoir:
        return _loadTeamMemberIds(const {'All Kids Choir Volunteers'});
      case _RecipientGroup.mainChoir:
        return _loadTeamMemberIds(const {'All Main Choir Volunteers'});
    }
  }

  Future<Set<String>> _loadProfileIds({String? role}) async {
    var query = supabase
        .from('profiles')
        .select('id')
        .neq('status', 'inactive');

    if (role != null) {
      query = query.eq('role', role);
    }

    final response = await query;

    return List<Map<String, dynamic>>.from(response)
        .map((profile) => profile['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<Set<String>> _loadTeamMemberIds(Set<String> teamNames) async {
    final teamsResponse = await supabase
        .from('teams')
        .select('id')
        .inFilter('name', teamNames.toList())
        .eq('is_active', true);
    final teamIds = List<Map<String, dynamic>>.from(teamsResponse)
        .map((team) => team['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    if (teamIds.isEmpty) {
      return {};
    }

    final membersResponse = await supabase
        .from('team_members')
        .select('user_id')
        .inFilter('team_id', teamIds);
    final memberIds = List<Map<String, dynamic>>.from(membersResponse)
        .map((member) => member['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    if (memberIds.isEmpty) {
      return {};
    }

    final activeProfilesResponse = await supabase
        .from('profiles')
        .select('id')
        .inFilter('id', memberIds.toList())
        .neq('status', 'inactive');

    return List<Map<String, dynamic>>.from(activeProfilesResponse)
        .map((profile) => profile['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<void> _loadTeamRoles() async {
    final response = await supabase
        .from('team_roles')
        .select('''
          id,
          role_name,
          quantity,
          display_order,
          teams (
            id,
            name,
            display_order,
            is_active
          )
        ''')
        .eq('is_active', true)
        .order('display_order')
        .order('role_name');
    final roles = List<Map<String, dynamic>>.from(response).where((role) {
      final team = role['teams'];

      if (team is! Map<String, dynamic>) {
        return false;
      }

      return team['is_active'] != false;
    }).toList()..sort(_compareTeamRoles);

    _teamRoles = roles;

    if (_selectedTeamRoleId == null && _teamRoles.isNotEmpty) {
      _selectedTeamRoleId = _teamRoles.first['id']?.toString();
    }

    if (_selectedTeamRoleId != null &&
        !_teamRoles.any(
          (role) => role['id']?.toString() == _selectedTeamRoleId,
        )) {
      _selectedTeamRoleId = _teamRoles.isEmpty
          ? null
          : _teamRoles.first['id']?.toString();
    }
  }

  Future<Set<String>> _loadSpecificRoleRecipientIds() async {
    final teamRoleId = _selectedTeamRoleId;

    if (teamRoleId == null || teamRoleId.isEmpty) {
      return {};
    }

    final assignmentsResponse = await supabase
        .from('user_role_assignments')
        .select('user_id')
        .eq('team_role_id', teamRoleId);
    final assignedUserIds = List<Map<String, dynamic>>.from(assignmentsResponse)
        .map((assignment) => assignment['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    if (assignedUserIds.isEmpty) {
      return {};
    }

    final profilesResponse = await supabase
        .from('profiles')
        .select('id')
        .inFilter('id', assignedUserIds.toList())
        .neq('status', 'inactive');

    return List<Map<String, dynamic>>.from(profilesResponse)
        .map((profile) => profile['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  String _recipientGroupLabel(_RecipientGroup group) {
    switch (group) {
      case _RecipientGroup.allUsers:
        return 'All Users';
      case _RecipientGroup.kidsClassSchedule:
        return 'Kids Class Schedule';
      case _RecipientGroup.kidsChoir:
        return 'All Kids Choir Volunteers';
      case _RecipientGroup.mainChoir:
        return 'All Main Choir Volunteers';
      case _RecipientGroup.adminsOnly:
        return 'Admins Only';
      case _RecipientGroup.specificRole:
        return 'Specific Role';
    }
  }

  int _compareTeamRoles(Map<String, dynamic> a, Map<String, dynamic> b) {
    final teamOrderCompare = _teamDisplayOrder(
      a,
    ).compareTo(_teamDisplayOrder(b));

    if (teamOrderCompare != 0) {
      return teamOrderCompare;
    }

    final teamNameCompare = _teamName(a).compareTo(_teamName(b));

    if (teamNameCompare != 0) {
      return teamNameCompare;
    }

    final roleOrderCompare = _roleDisplayOrder(
      a,
    ).compareTo(_roleDisplayOrder(b));

    if (roleOrderCompare != 0) {
      return roleOrderCompare;
    }

    return _roleName(a).compareTo(_roleName(b));
  }

  int _teamDisplayOrder(Map<String, dynamic> role) {
    final team = role['teams'];
    final displayOrder = team is Map<String, dynamic>
        ? team['display_order']
        : null;

    if (displayOrder is int) {
      return displayOrder;
    }

    return int.tryParse(displayOrder?.toString() ?? '') ?? 999999;
  }

  int _roleDisplayOrder(Map<String, dynamic> role) {
    final displayOrder = role['display_order'];

    if (displayOrder is int) {
      return displayOrder;
    }

    return int.tryParse(displayOrder?.toString() ?? '') ?? 999999;
  }

  String _teamName(Map<String, dynamic> role) {
    final team = role['teams'];

    return team is Map<String, dynamic>
        ? team['name']?.toString() ?? 'Team'
        : 'Team';
  }

  String _roleName(Map<String, dynamic> role) {
    final roleName = role['role_name']?.toString().trim() ?? '';

    return roleName.isEmpty ? 'Role' : roleName;
  }

  List<DropdownMenuItem<String>> _roleDropdownItems() {
    final items = <DropdownMenuItem<String>>[];
    String? currentTeamName;

    for (final role in _teamRoles) {
      final teamName = _teamName(role);

      if (teamName != currentTeamName) {
        currentTeamName = teamName;
        items.add(
          DropdownMenuItem<String>(
            value: 'team-header-$teamName',
            enabled: false,
            child: Text(
              teamName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
        );
      }

      final roleId = role['id']?.toString();

      if (roleId == null || roleId.isEmpty) {
        continue;
      }

      items.add(
        DropdownMenuItem<String>(
          value: roleId,
          child: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(_roleName(role)),
          ),
        ),
      );
    }

    return items;
  }

  String _selectedRoleLabel() {
    final selectedRole = _teamRoles.where((role) {
      return role['id']?.toString() == _selectedTeamRoleId;
    }).firstOrNull;

    if (selectedRole == null) {
      return 'Select role';
    }

    return '${_teamName(selectedRole)} - ${_roleName(selectedRole)}';
  }

  Future<void> _sendBroadcast() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final recipientIds = await _loadRecipientIds();

    if (!mounted) return;

    if (recipientIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No recipients found for this broadcast.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Send Broadcast?'),
          content: Text(
            'Send this message to ${recipientIds.length} '
            '${recipientIds.length == 1 ? 'recipient' : 'recipients'}?',
          ),
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
              child: const Text('Send'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final title = _titleController.text.trim();
      final body = _messageController.text.trim();
      final rows = recipientIds.map((userId) {
        return {
          'user_id': userId,
          'title': title,
          'message': body,
          'notification_type': 'admin_broadcast',
        };
      }).toList();

      await supabase.from('notifications').insert(rows);

      if (!mounted) return;

      _titleController.clear();
      _messageController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Broadcast sent to ${recipientIds.length} users'),
        ),
      );
    } catch (e, stackTrace) {
      logTechnicalError(
        'BroadcastMessagePage._sendBroadcast failed',
        e,
        stackTrace,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Unable to send broadcast. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        await _loadRecipientCount();
      }
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Broadcast Message')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _message != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_message!, textAlign: TextAlign.center),
              ),
            )
          : !_isAdmin
          ? const Center(child: Text('Only admins can send broadcasts.'))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _titleController,
                            decoration: _inputDecoration('Title'),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Title is required';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _messageController,
                            decoration: _inputDecoration('Message'),
                            minLines: 4,
                            maxLines: 8,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Message is required';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<_RecipientGroup>(
                            initialValue: _recipientGroup,
                            decoration: _inputDecoration('Recipients'),
                            items: _RecipientGroup.values.map((group) {
                              return DropdownMenuItem(
                                value: group,
                                child: Text(_recipientGroupLabel(group)),
                              );
                            }).toList(),
                            onChanged: _isSending
                                ? null
                                : (value) async {
                                    if (value == null) {
                                      return;
                                    }

                                    setState(() {
                                      _recipientGroup = value;
                                    });
                                    await _loadRecipientCount();
                                  },
                          ),
                          if (_recipientGroup ==
                              _RecipientGroup.specificRole) ...[
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedTeamRoleId,
                              decoration: _inputDecoration('Specific Role'),
                              selectedItemBuilder: (context) {
                                return _roleDropdownItems().map((item) {
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _selectedRoleLabel(),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList();
                              },
                              items: _roleDropdownItems(),
                              validator: (value) {
                                if (_recipientGroup !=
                                    _RecipientGroup.specificRole) {
                                  return null;
                                }

                                if (value == null || value.isEmpty) {
                                  return 'Select a role';
                                }

                                return null;
                              },
                              onChanged: _isSending
                                  ? null
                                  : (value) async {
                                      if (value == null || value.isEmpty) {
                                        return;
                                      }

                                      setState(() {
                                        _selectedTeamRoleId = value;
                                      });
                                      await _loadRecipientCount();
                                    },
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            'Recipients: $_recipientCount',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSending ? null : _sendBroadcast,
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.campaign),
                      label: Text(_isSending ? 'Sending...' : 'Send Broadcast'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
