import 'service_slots_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ServiceInstancesPage extends StatefulWidget {
  final String ministryId;

  final String teamId;

  final String teamName;

  const ServiceInstancesPage({
    super.key,
    required this.ministryId,
    required this.teamId,
    required this.teamName,
  });

  @override
  State<ServiceInstancesPage> createState() => _ServiceInstancesPageState();
}

class _ServiceInstancesPageState extends State<ServiceInstancesPage> {
  List<dynamic> _instances = [];

  bool _isLoading = true;

  bool _isAdmin = false;

  String? _message;

  @override
  void initState() {
    super.initState();
    _loadInstances();
  }

  Future<void> _loadInstances() async {
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
          .from('service_instances')
          .select()
          .eq('ministry_id', widget.ministryId)
          .eq('team_id', widget.teamId)
          .order('service_date')
          .order('start_time');

      setState(() {
        _instances = response;
      });
    } catch (e) {
      setState(() {
        _message = 'Failed to load service instances: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatDate(String rawDate) {
    final parts = rawDate.split('-');

    if (parts.length != 3) {
      return rawDate;
    }

    return '${parts[1]}/${parts[2]}/${parts[0]}';
  }

  Future<void> _regenerateSlots(Map<String, dynamic> instance) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Regenerate Slots'),
          content: const Text('Regenerate slots from current team roles?'),
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
              child: const Text('Regenerate'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await supabase.rpc(
        'generate_slots_from_team_roles',
        params: {'p_service_instance_id': instance['id']},
      );

      await _loadInstances();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Slots regenerated')));
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to regenerate slots: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.teamName)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _message != null
            ? Center(child: Text(_message!))
            : _instances.isEmpty
            ? const Center(child: Text('No service instances found.'))
            : ListView.builder(
                itemCount: _instances.length,
                itemBuilder: (context, index) {
                  final instance = _instances[index];

                  return Card(
                    child: ListTile(
                      title: Text(instance['service_name'] ?? ''),
                      subtitle: Text(
                        '${_formatDate(instance['service_date'])}'
                        ' • ${instance['start_time']}'
                        ' - ${instance['end_time']}\n'
                        '${instance['location'] ?? ''}',
                      ),
                      trailing: _isAdmin
                          ? PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'regenerate_slots') {
                                  _regenerateSlots(instance);
                                }
                              },
                              itemBuilder: (context) {
                                return const [
                                  PopupMenuItem(
                                    value: 'regenerate_slots',
                                    child: Text('Regenerate Slots'),
                                  ),
                                ];
                              },
                            )
                          : null,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ServiceSlotsPage(
                              serviceInstanceId: instance['id'],
                              serviceTitle:
                                  instance['service_name'] ?? 'Service',
                              serviceDate: _formatDate(
                                instance['service_date'],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
