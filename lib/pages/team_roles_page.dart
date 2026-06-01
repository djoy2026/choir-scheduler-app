import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _message = 'Failed to load team roles: $e';
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

    if (roleName.isEmpty) {
      return const [];
    }

    if (quantity <= 1) {
      return [roleName];
    }

    return List.generate(quantity, (index) => '$roleName ${index + 1}');
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
        trailing: Chip(
          label: Text(isActive ? 'Active' : 'Inactive'),
          backgroundColor: isActive ? Colors.green.shade100 : Colors.grey[300],
        ),
      ),
    );
  }

  Widget _buildMobileRoleList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _roles.length,
      itemBuilder: (context, index) {
        return _buildRoleCard(_roles[index]);
      },
    );
  }

  Widget _buildDesktopRoleList() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Order')),
          DataColumn(label: Text('Role')),
          DataColumn(label: Text('Qty')),
          DataColumn(label: Text('Generates')),
          DataColumn(label: Text('Status')),
        ],
        rows: _roles.map((role) {
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
            ],
          );
        }).toList(),
      ),
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
      appBar: AppBar(title: const Text('Team Roles')),
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
