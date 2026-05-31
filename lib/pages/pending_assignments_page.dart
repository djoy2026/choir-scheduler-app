import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  String _formatDate(String rawDate) {
    final parts = rawDate.split('-');

    if (parts.length != 3) {
      return rawDate;
    }

    return '${parts[1]}/${parts[2]}/${parts[0]}';
  }

  Future<void> _respond(Map<String, dynamic> slot, bool accept) async {
    try {
      final currentUser = supabase.auth.currentUser;

      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      await supabase
          .from('service_slots')
          .update({
            'slot_status': accept ? 'taken' : 'open',

            'assigned_user_id': accept ? currentUser.id : null,

            'color_code': accept ? 'green' : 'amber',
          })
          .eq('id', slot['id']);

      await _loadAssignments();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Assignment accepted' : 'Assignment declined'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
            ? const Center(child: Text('No pending assignments.'))
            : ListView.builder(
                itemCount: _assignments.length,

                itemBuilder: (context, index) {
                  final slot = _assignments[index];

                  final service = slot['service_instances'];

                  final team = service['teams']?['name'] ?? '';

                  return Card(
                    color: Colors.blue.shade100,

                    child: ListTile(
                      title: Text(service['service_name'] ?? ''),

                      subtitle: Text(
                        '${_formatDate(service['service_date'])}'
                        ' • ${service['start_time']}'
                        ' - ${service['end_time']}\n'
                        '${slot['role_name'] ?? slot['slot_name']}\n'
                        '$team\n'
                        '${service['location'] ?? ''}',
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
