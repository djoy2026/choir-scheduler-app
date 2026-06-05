import 'service_slots_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/time_format.dart';
import '../utils/ui_helpers.dart';

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

  Future<void> _cleanDuplicateSlots(Map<String, dynamic> instance) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clean Duplicate Slots'),
          content: const Text(
            'Remove duplicate slots while keeping the highest-priority copy?',
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
              child: const Text('Clean'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      final response = await supabase.rpc(
        'cleanup_duplicate_service_slots',
        params: {'p_service_instance_id': instance['id']},
      );
      final deletedCount = response is int
          ? response
          : int.tryParse(response?.toString() ?? '') ?? 0;

      await _loadInstances();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $deletedCount duplicate slots')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clean duplicate slots: $e')),
      );
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

                  return AccentCard(
                    accentColor: Colors.amber.shade500,
                    child: ListTile(
                      title: Text(
                        formatServiceHeading(
                          instance['service_date']?.toString(),
                          instance['start_time']?.toString(),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: serviceTitleTextStyle,
                      ),
                      subtitle: Text(
                        '${widget.teamName}\n'
                        '${instance['location'] ?? ''}',
                        style: mutedTextStyle(context),
                      ),
                      trailing: _isAdmin
                          ? PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'regenerate_slots') {
                                  _regenerateSlots(instance);
                                  return;
                                }

                                if (action == 'clean_duplicate_slots') {
                                  _cleanDuplicateSlots(instance);
                                }
                              },
                              itemBuilder: (context) {
                                return const [
                                  PopupMenuItem(
                                    value: 'regenerate_slots',
                                    child: Text('Regenerate Slots'),
                                  ),
                                  PopupMenuItem(
                                    value: 'clean_duplicate_slots',
                                    child: Text('Clean Duplicate Slots'),
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
                              serviceTitle: formatServiceHeading(
                                instance['service_date']?.toString(),
                                instance['start_time']?.toString(),
                              ),
                              serviceDate: formatNumericDate(
                                instance['service_date']?.toString(),
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
