import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/error_messages.dart';

final supabase = Supabase.instance.client;

class TeamRolesPage extends StatefulWidget {
  final String ministryId;
  final String ministryName;
  final String teamId;
  final String teamName;

  const TeamRolesPage({
    super.key,
    required this.ministryId,
    required this.ministryName,
    required this.teamId,
    required this.teamName,
  });

  @override
  State<TeamRolesPage> createState() => _TeamRolesPageState();
}

class _TeamRolesPageState extends State<TeamRolesPage> {
  static const int _minQuantity = 1;
  static const int _maxQuantity = 20;

  bool _isLoading = true;
  bool _isAdmin = false;

  List<Map<String, dynamic>> _roles = [];

  String? _message;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();

      final role = profile['role']?.toString().trim().toLowerCase();
      final isAdmin = role == 'admin';

      List<Map<String, dynamic>> roles = [];

      if (isAdmin) {
        final response = await supabase
            .from('team_roles')
            .select(
              'id, team_id, role_name, quantity, display_order, is_active',
            )
            .eq('team_id', widget.teamId)
            .order('display_order')
            .order('role_name');

        roles = List<Map<String, dynamic>>.from(response);
      }

      if (!mounted) return;

      setState(() {
        _isAdmin = isAdmin;
        _roles = roles;
      });
    } catch (e, stackTrace) {
      logTechnicalError('TeamRolesPage._loadData failed', e, stackTrace);
      if (!mounted) return;

      setState(() {
        _message = friendlyErrorMessage(
          e,
          fallback: 'Unable to load team roles. Please try again.',
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

  int get _activeRoleCount {
    return _roles.where(_isActiveRole).length;
  }

  int get _totalGeneratedSlots {
    return _roles.where(_isActiveRole).fold<int>(0, (total, role) {
      return total + _quantityFor(role);
    });
  }

  List<Map<String, dynamic>> _sortedRoles({required bool isActive}) {
    final roles = _roles.where((role) => _isActiveRole(role) == isActive);

    return List<Map<String, dynamic>>.from(roles)..sort((a, b) {
      final orderCompare = _displayOrderFor(a).compareTo(_displayOrderFor(b));

      if (orderCompare != 0) {
        return orderCompare;
      }

      final aName = a['role_name']?.toString().toLowerCase() ?? '';
      final bName = b['role_name']?.toString().toLowerCase() ?? '';

      return aName.compareTo(bName);
    });
  }

  bool _isActiveRole(Map<String, dynamic> role) {
    return role['is_active'] == true;
  }

  int _quantityFor(Map<String, dynamic> role) {
    final rawQuantity = role['quantity'];

    if (rawQuantity is int) {
      return rawQuantity;
    }

    return int.tryParse(rawQuantity?.toString() ?? '') ?? 1;
  }

  int _displayOrderFor(Map<String, dynamic> role) {
    final rawOrder = role['display_order'];

    if (rawOrder is int) {
      return rawOrder;
    }

    return int.tryParse(rawOrder?.toString() ?? '') ?? 0;
  }

  List<String> _generatedLabelsFor(Map<String, dynamic> role) {
    final roleName = role['role_name']?.toString().trim() ?? '';
    final quantity = _quantityFor(role);

    return _generatedLabels(roleName, quantity);
  }

  List<String> _generatedLabels(String roleName, int quantity) {
    final trimmedRoleName = roleName.trim();

    if (trimmedRoleName.isEmpty) {
      return const [];
    }

    final safeQuantity = quantity.clamp(_minQuantity, _maxQuantity);

    if (safeQuantity <= 1) {
      return [trimmedRoleName];
    }

    return List.generate(
      safeQuantity,
      (index) => '$trimmedRoleName ${index + 1}',
    );
  }

  int _nextDisplayOrder() {
    final activeRoles = _sortedRoles(isActive: true);

    if (activeRoles.isEmpty) {
      return 1;
    }

    final maxDisplayOrder = activeRoles.map(_displayOrderFor).fold<int>(0, (
      currentMax,
      order,
    ) {
      return order > currentMax ? order : currentMax;
    });

    return maxDisplayOrder + 1;
  }

  Future<void> _showAddRoleDialog() async {
    final formKey = GlobalKey<FormState>();
    var roleName = '';
    var quantity = 1;
    var isSaving = false;

    final wasSaved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final previewLabels = _generatedLabels(roleName, quantity);
            final previewText = previewLabels.isEmpty
                ? 'Enter a role name to preview slots.'
                : previewLabels.join(', ');

            Future<void> saveRole() async {
              if (isSaving) {
                return;
              }

              if (!(formKey.currentState?.validate() ?? false)) {
                return;
              }

              setDialogState(() {
                isSaving = true;
              });

              try {
                await supabase.from('team_roles').insert({
                  'team_id': widget.teamId,
                  'role_name': roleName.trim(),
                  'quantity': quantity,
                  'display_order': _nextDisplayOrder(),
                  'is_active': true,
                });

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (e, stackTrace) {
                logTechnicalError(
                  'TeamRolesPage._showAddRoleDialog save failed',
                  e,
                  stackTrace,
                );
                if (!dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  isSaving = false;
                });

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      friendlyErrorMessage(
                        e,
                        fallback: 'Unable to save role. Please try again.',
                      ),
                    ),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Add Role'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Role Name',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Enter a role name';
                          }

                          return null;
                        },
                        onChanged: (value) {
                          setDialogState(() {
                            roleName = value;
                          });
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Quantity',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Decrease quantity',
                            onPressed: quantity <= _minQuantity || isSaving
                                ? null
                                : () {
                                    setDialogState(() {
                                      quantity--;
                                    });
                                  },
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          SizedBox(
                            width: 32,
                            child: Text(
                              '$quantity',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Increase quantity',
                            onPressed: quantity >= _maxQuantity || isSaving
                                ? null
                                : () {
                                    setDialogState(() {
                                      quantity++;
                                    });
                                  },
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Generated slot preview',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(previewText),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          Navigator.pop(dialogContext, false);
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : saveRole,
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (wasSaved == true) {
      await _loadData();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Role added')));
    }
  }

  Future<void> _showEditRoleDialog(Map<String, dynamic> role) async {
    final formKey = GlobalKey<FormState>();
    var roleName = role['role_name']?.toString() ?? '';
    var quantity = _quantityFor(role).clamp(_minQuantity, _maxQuantity);
    var displayOrder = _displayOrderFor(role).toString();
    var isSaving = false;

    final wasSaved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final previewLabels = _generatedLabels(roleName, quantity);
            final previewText = previewLabels.isEmpty
                ? 'Enter a role name to preview slots.'
                : previewLabels.join(', ');

            Future<void> saveRole() async {
              if (isSaving) {
                return;
              }

              if (!(formKey.currentState?.validate() ?? false)) {
                return;
              }

              setDialogState(() {
                isSaving = true;
              });

              try {
                final requestedPosition = int.parse(displayOrder.trim());
                final sectionRoles = _sortedRoles(
                  isActive: _isActiveRole(role),
                );
                final reorderedRoles = List<Map<String, dynamic>>.from(
                  sectionRoles,
                )..removeWhere((item) => item['id'] == role['id']);
                final targetIndex = (requestedPosition - 1).clamp(
                  0,
                  reorderedRoles.length,
                );
                reorderedRoles.insert(targetIndex, {
                  ...role,
                  'role_name': roleName.trim(),
                  'quantity': quantity,
                });
                final updatedAt = DateTime.now().toUtc().toIso8601String();

                for (var index = 0; index < reorderedRoles.length; index++) {
                  final updatedRole = reorderedRoles[index];
                  final updates = <String, dynamic>{
                    'display_order': index + 1,
                    'updated_at': updatedAt,
                  };

                  if (updatedRole['id'] == role['id']) {
                    updates.addAll({
                      'role_name': roleName.trim(),
                      'quantity': quantity,
                    });
                  }

                  await supabase
                      .from('team_roles')
                      .update(updates)
                      .eq('id', updatedRole['id']);
                }

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (e, stackTrace) {
                logTechnicalError(
                  'TeamRolesPage._showEditRoleDialog save failed',
                  e,
                  stackTrace,
                );
                if (!dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  isSaving = false;
                });

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      friendlyErrorMessage(
                        e,
                        fallback: 'Unable to update role. Please try again.',
                      ),
                    ),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Edit Role'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        initialValue: roleName,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Role Name',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Enter a role name';
                          }

                          return null;
                        },
                        onChanged: (value) {
                          setDialogState(() {
                            roleName = value;
                          });
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Quantity',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Decrease quantity',
                            onPressed: quantity <= _minQuantity || isSaving
                                ? null
                                : () {
                                    setDialogState(() {
                                      quantity--;
                                    });
                                  },
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          SizedBox(
                            width: 32,
                            child: Text(
                              '$quantity',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Increase quantity',
                            onPressed: quantity >= _maxQuantity || isSaving
                                ? null
                                : () {
                                    setDialogState(() {
                                      quantity++;
                                    });
                                  },
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: displayOrder,
                        decoration: const InputDecoration(
                          labelText: 'Display Order',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (int.tryParse((value ?? '').trim()) == null) {
                            return 'Enter a whole number';
                          }

                          return null;
                        },
                        onChanged: (value) {
                          displayOrder = value;
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Generated slot preview',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(previewText),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          Navigator.pop(dialogContext, false);
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : saveRole,
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (wasSaved == true) {
      await _loadData();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Role updated')));
    }
  }

  Future<void> _setRoleActive(
    Map<String, dynamic> role, {
    required bool isActive,
  }) async {
    try {
      if (isActive && _hasActiveRoleWithSameName(role)) {
        final roleName = role['role_name']?.toString().trim();

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'An active ${roleName?.isEmpty ?? true ? 'role' : roleName} role already exists for this team.',
            ),
          ),
        );
        return;
      }

      final targetSectionRoles = _sortedRoles(
        isActive: isActive,
      ).where((item) => item['id'] != role['id']);
      final nextDisplayOrder =
          targetSectionRoles
              .map(_displayOrderFor)
              .fold<int>(
                0,
                (currentMax, order) => order > currentMax ? order : currentMax,
              ) +
          1;

      await supabase
          .from('team_roles')
          .update({
            'is_active': isActive,
            'display_order': nextDisplayOrder,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', role['id']);

      await _loadData();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isActive ? 'Role reactivated' : 'Role deactivated'),
        ),
      );
    } catch (e, stackTrace) {
      logTechnicalError('TeamRolesPage._setRoleActive failed', e, stackTrace);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Unable to update role. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  bool _hasActiveRoleWithSameName(Map<String, dynamic> role) {
    final roleName = role['role_name']?.toString().trim().toLowerCase() ?? '';

    if (roleName.isEmpty) {
      return false;
    }

    return _roles.any((item) {
      if (item['id'] == role['id']) {
        return false;
      }

      if (!_isActiveRole(item)) {
        return false;
      }

      final itemRoleName =
          item['role_name']?.toString().trim().toLowerCase() ?? '';

      return itemRoleName == roleName && item['team_id'] == role['team_id'];
    });
  }

  Future<void> _moveRole(
    Map<String, dynamic> role, {
    required bool moveUp,
  }) async {
    final isActive = _isActiveRole(role);
    final sectionRoles = _sortedRoles(isActive: isActive);
    final currentIndex = sectionRoles.indexWhere(
      (item) => item['id'] == role['id'],
    );

    if (currentIndex == -1) {
      return;
    }

    final targetIndex = moveUp ? currentIndex - 1 : currentIndex + 1;

    if (targetIndex < 0 || targetIndex >= sectionRoles.length) {
      return;
    }

    final reorderedRoles = List<Map<String, dynamic>>.from(sectionRoles);
    final movedRole = reorderedRoles.removeAt(currentIndex);
    reorderedRoles.insert(targetIndex, movedRole);

    try {
      final updatedAt = DateTime.now().toUtc().toIso8601String();

      for (var index = 0; index < reorderedRoles.length; index++) {
        await supabase
            .from('team_roles')
            .update({'display_order': index + 1, 'updated_at': updatedAt})
            .eq('id', reorderedRoles[index]['id']);
      }

      await _loadData();
    } catch (e, stackTrace) {
      logTechnicalError('TeamRolesPage._moveRole failed', e, stackTrace);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Unable to reorder role. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeleteRole(Map<String, dynamic> role) async {
    final roleName = role['role_name']?.toString() ?? 'this role';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Role'),
          content: Text('Permanently delete $roleName?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
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

    try {
      await supabase.from('team_roles').delete().eq('id', role['id']);

      await _loadData();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Role deleted')));
    } catch (e, stackTrace) {
      logTechnicalError(
        'TeamRolesPage._confirmDeleteRole failed',
        e,
        stackTrace,
      );
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Unable to delete role. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _handleRoleAction(
    String action,
    Map<String, dynamic> role,
  ) async {
    switch (action) {
      case 'edit':
        await _showEditRoleDialog(role);
        return;
      case 'deactivate':
        await _setRoleActive(role, isActive: false);
        return;
      case 'reactivate':
        await _setRoleActive(role, isActive: true);
        return;
      case 'move_up':
        await _moveRole(role, moveUp: true);
        return;
      case 'move_down':
        await _moveRole(role, moveUp: false);
        return;
      case 'delete':
        await _confirmDeleteRole(role);
        return;
    }
  }

  Widget _buildRoleActions(Map<String, dynamic> role) {
    final isActive = _isActiveRole(role);
    final sectionRoles = _sortedRoles(isActive: isActive);
    final index = sectionRoles.indexWhere((item) => item['id'] == role['id']);

    return PopupMenuButton<String>(
      tooltip: 'Role actions',
      onSelected: (action) {
        _handleRoleAction(action, role);
      },
      itemBuilder: (context) {
        return [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(
            value: index > 0 ? 'move_up' : null,
            enabled: index > 0,
            child: const Text('Move Up'),
          ),
          PopupMenuItem(
            value: index >= 0 && index < sectionRoles.length - 1
                ? 'move_down'
                : null,
            enabled: index >= 0 && index < sectionRoles.length - 1,
            child: const Text('Move Down'),
          ),
          PopupMenuItem(
            value: isActive ? 'deactivate' : 'reactivate',
            child: Text(isActive ? 'Deactivate' : 'Reactivate'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ];
      },
    );
  }

  Widget _buildSummary(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.ministryName, style: textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          widget.teamName,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            Chip(
              avatar: const Icon(Icons.badge, size: 18),
              label: Text('Active roles: $_activeRoleCount'),
            ),
            Chip(
              avatar: const Icon(Icons.event_seat, size: 18),
              label: Text('Slots/service: $_totalGeneratedSlots'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRoleCard(Map<String, dynamic> role) {
    final isActive = _isActiveRole(role);
    final labels = _generatedLabelsFor(role);
    final preview = labels.isEmpty ? 'No generated labels' : labels.join(', ');

    return Card(
      child: ListTile(
        title: Text(role['role_name']?.toString() ?? ''),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quantity: ${_quantityFor(role)}'
                ' | Display order: ${_displayOrderFor(role)}',
              ),
              const SizedBox(height: 4),
              Text('Generates: $preview'),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              label: Text(isActive ? 'Active' : 'Inactive'),
              backgroundColor: isActive
                  ? Colors.green.shade100
                  : Colors.grey[300],
            ),
            _buildRoleActions(role),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileRoleList() {
    final activeRoles = _sortedRoles(isActive: true);
    final inactiveRoles = _sortedRoles(isActive: false);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _buildRoleSectionTitle('Active Roles', activeRoles.length),
        if (activeRoles.isEmpty)
          _buildSectionEmptyState('No active roles.')
        else
          ...activeRoles.map(_buildRoleCard),
        const SizedBox(height: 16),
        _buildRoleSectionTitle('Inactive Roles', inactiveRoles.length),
        if (inactiveRoles.isEmpty)
          _buildSectionEmptyState('No inactive roles.')
        else
          ...inactiveRoles.map(_buildRoleCard),
      ],
    );
  }

  Widget _buildRoleSectionTitle(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        '$title ($count)',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSectionEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(message),
    );
  }

  Widget _buildDesktopRoleTable(List<Map<String, dynamic>> roles) {
    if (roles.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Order')),
          DataColumn(label: Text('Role')),
          DataColumn(label: Text('Qty')),
          DataColumn(label: Text('Generates')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: roles.map((role) {
          final isActive = _isActiveRole(role);
          final labels = _generatedLabelsFor(role);

          return DataRow(
            cells: [
              DataCell(Text('${_displayOrderFor(role)}')),
              DataCell(Text(role['role_name']?.toString() ?? '')),
              DataCell(Text('${_quantityFor(role)}')),
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    labels.isEmpty ? 'No generated labels' : labels.join(', '),
                  ),
                ),
              ),
              DataCell(Text(isActive ? 'Active' : 'Inactive')),
              DataCell(_buildRoleActions(role)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDesktopRoleList() {
    final activeRoles = _sortedRoles(isActive: true);
    final inactiveRoles = _sortedRoles(isActive: false);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _buildRoleSectionTitle('Active Roles', activeRoles.length),
        if (activeRoles.isEmpty)
          _buildSectionEmptyState('No active roles.')
        else
          _buildDesktopRoleTable(activeRoles),
        const SizedBox(height: 20),
        _buildRoleSectionTitle('Inactive Roles', inactiveRoles.length),
        if (inactiveRoles.isEmpty)
          _buildSectionEmptyState('No inactive roles.')
        else
          _buildDesktopRoleTable(inactiveRoles),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No team roles configured. New services for this team will not '
          'generate slots until roles are added.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (!_isAdmin) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'You do not have permission to manage team roles.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_roles.isEmpty) {
      return _buildEmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          return _buildDesktopRoleList();
        }

        return _buildMobileRoleList();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Roles'),
        actions: [
          if (_isAdmin && !_isLoading && _message == null)
            TextButton.icon(
              onPressed: _showAddRoleDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Role'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _message != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_message!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadData,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummary(context),
                  const SizedBox(height: 16),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadData,
                      child: _buildContent(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
