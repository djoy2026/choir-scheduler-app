import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/time_format.dart';
import '../utils/ui_helpers.dart';

final supabase = Supabase.instance.client;

class PendingAssignmentsPage extends StatefulWidget {
  const PendingAssignmentsPage({super.key});

  @override
  State<PendingAssignmentsPage> createState() => _PendingAssignmentsPageState();
}

class _PendingAssignmentsPageState extends State<PendingAssignmentsPage> {
  bool _isLoading = true;

  List<dynamic> _assignments = [];

  String? _message;

  @override
  void initState() {
    super.initState();

    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      final response = await supabase
          .from('service_slots')
          .select('''
            id,
            slot_name,
            role_name,
            service_instances!inner (
              id,
              service_name,
              service_date,
              start_time,
              end_time,
              location,
              teams (
                name
              )
            )
          ''')
          .eq('assigned_user_id', user.id)
          .eq('slot_status', 'pending')
          .order('service_instances(service_date)');

      setState(() {
        _assignments = response;
      });
    } catch (e) {
      setState(() {
        _message = 'Failed to load assignments: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool> _isCurrentUserUnavailableForService(
    String serviceInstanceId,
  ) async {
    final currentUser = supabase.auth.currentUser;

    if (currentUser == null) {
      throw Exception('User not logged in');
    }

    final response = await supabase
        .from('service_availability')
        .select('id')
        .eq('service_instance_id', serviceInstanceId)
        .eq('user_id', currentUser.id)
        .eq('availability_status', 'unavailable')
        .limit(1);

    return response.isNotEmpty;
  }

  Future<List<String>> _loadAdminUserIds() async {
    final response = await supabase
        .from('profiles')
        .select('id')
        .eq('role', 'admin');

    return List<Map<String, dynamic>>.from(
      response,
    ).map((profile) => profile['id'].toString()).toList();
  }

  Future<String> _currentVolunteerName() async {
    final currentUser = supabase.auth.currentUser;

    if (currentUser == null) {
      return 'Unknown User';
    }

    final profile = await supabase
        .from('profiles')
        .select('first_name, last_name, email')
        .eq('id', currentUser.id)
        .single();

    final name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
        .trim();

    if (name.isNotEmpty) {
      return name;
    }

    return profile['email']?.toString() ?? 'Unknown User';
  }

  Future<void> _notifyAdmins({
    required String title,
    required String message,
    required String notificationType,
    required String serviceInstanceId,
  }) async {
    final adminUserIds = await _loadAdminUserIds();

    if (adminUserIds.isEmpty) {
      return;
    }

    await supabase
        .from('notifications')
        .insert(
          adminUserIds.map((userId) {
            return {
              'user_id': userId,
              'title': title,
              'message': message,
              'notification_type': notificationType,
              'related_service_instance_id': serviceInstanceId,
            };
          }).toList(),
        );
  }

  Future<void> _respond(Map<String, dynamic> slot, bool accept) async {
    try {
      final currentUser = supabase.auth.currentUser;

      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      final service = slot['service_instances'];

      if (accept && await _isCurrentUserUnavailableForService(service['id'])) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You marked yourself unavailable for this service. Change your availability before accepting.',
            ),
          ),
        );
        return;
      }

      await supabase
          .from('service_slots')
          .update({
            'slot_status': accept ? 'taken' : 'open',

            'assigned_user_id': accept ? currentUser.id : null,

            'color_code': accept ? 'green' : 'amber',
          })
          .eq('id', slot['id']);

      final volunteerName = await _currentVolunteerName();

      await _notifyAdmins(
        title: accept ? 'Assignment Accepted' : 'Assignment Declined',
        message: accept
            ? '$volunteerName accepted assignment.'
            : '$volunteerName declined assignment.',
        notificationType: accept
            ? 'assignment_accepted'
            : 'assignment_declined',
        serviceInstanceId: service['id'],
      );

      await _loadAssignments();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Assignment accepted' : 'Assignment declined'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update assignment. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assignments')),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _message != null
            ? Center(child: Text(_message!))
            : _assignments.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.assignment_turned_in,
                      size: 48,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No upcoming assignments',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'You are all caught up.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _assignments.length,

                itemBuilder: (context, index) {
                  final slot = _assignments[index];

                  final service = slot['service_instances'];

                  final team = service['teams']?['name'] ?? '';

                  return AccentCard(
                    accentColor: Colors.blue.shade500,
                    color: Colors.blue.shade100,
                    child: ListTile(
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
                        '$team\n'
                        '${service['location'] ?? ''}\n'
                        '${slot['role_name'] ?? slot['slot_name']}',
                        style: mutedTextStyle(context),
                      ),

                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,

                        children: [
                          IconButton(
                            icon: const Icon(Icons.check_circle),

                            color: Colors.green,

                            onPressed: () => _respond(slot, true),
                          ),

                          IconButton(
                            icon: const Icon(Icons.cancel),

                            color: Colors.red,

                            onPressed: () => _respond(slot, false),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
