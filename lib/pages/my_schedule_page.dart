import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/time_format.dart';
import '../utils/ui_helpers.dart';

final supabase = Supabase.instance.client;

class MySchedulePage extends StatefulWidget {
  const MySchedulePage({super.key});

  @override
  State<MySchedulePage> createState() => _MySchedulePageState();
}

class _MySchedulePageState extends State<MySchedulePage> {
  List<dynamic> _schedule = [];

  bool _isLoading = true;

  String? _message;

  @override
  void initState() {
    super.initState();

    _loadMySchedule();
  }

  Future<void> _loadMySchedule() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      debugPrint('CURRENT USER ID: ${user.id}');

      final response = await supabase
          .from('service_slots')
          .select('''
          id,
          role_name,
          slot_name,
          slot_status,
          assigned_user_id,
          service_instances (
            id,
            service_name,
            service_date,
            start_time,
            end_time,
            location
          )
        ''')
          .eq('assigned_user_id', user.id)
          .eq('slot_status', 'taken');

      debugPrint('MY SCHEDULE RESPONSE: $response');

      setState(() {
        _schedule = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('MY SCHEDULE ERROR: $e');

      setState(() {
        _message = 'Failed to load schedule: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _hasConflict(Map<String, dynamic> currentSlot) {
    final currentService = currentSlot['service_instances'];

    if (currentService == null) {
      return false;
    }

    final currentDate = currentService['service_date'];

    final currentStart = currentService['start_time'];

    final currentEnd = currentService['end_time'];

    final currentServiceId = currentService['id'];

    for (final otherSlot in _schedule) {
      final otherService = otherSlot['service_instances'];

      if (otherService == null) {
        continue;
      }

      if (otherService['id'] == currentServiceId) {
        continue;
      }

      if (otherService['service_date'] != currentDate) {
        continue;
      }

      final otherStart = otherService['start_time'];

      final otherEnd = otherService['end_time'];

      final overlaps =
          currentStart.compareTo(otherEnd) < 0 &&
          currentEnd.compareTo(otherStart) > 0;

      if (overlaps) {
        return true;
      }
    }

    return false;
  }

  Future<void> _unclaimSlot(Map<String, dynamic> slot) async {
    try {
      await supabase
          .from('service_slots')
          .update({
            'slot_status': 'open',
            'assigned_user_id': null,
            'color_code': 'amber',
          })
          .eq('id', slot['id']);

      await _loadMySchedule();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Removed from schedule')));
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
      appBar: AppBar(title: const Text('My Schedule')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _message != null
            ? Center(child: Text(_message!))
            : _schedule.isEmpty
            ? const Center(child: Text('No upcoming services.'))
            : ListView.builder(
                itemCount: _schedule.length,
                itemBuilder: (context, index) {
                  final slot = _schedule[index];

                  final service = slot['service_instances'];

                  if (service == null) {
                    return const SizedBox.shrink();
                  }

                  final team = service['teams']?['name'] ?? '';

                  final ministry = service['ministries']?['name'] ?? '';

                  final hasConflict = _hasConflict(slot);

                  return AccentCard(
                    accentColor: hasConflict
                        ? Colors.red.shade500
                        : Colors.green.shade500,
                    color: hasConflict ? Colors.red.shade100 : Colors.white,
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
                        '$ministry'
                        '${ministry.isNotEmpty && team.isNotEmpty ? ' • ' : ''}'
                        '$team\n'
                        '${service['location'] ?? ''}\n'
                        '${slot['role_name'] ?? slot['slot_name']}'
                        '${hasConflict ? '\n⚠️ Conflict detected' : ''}',
                        style: mutedTextStyle(context),
                      ),
                      leading: Icon(
                        hasConflict ? Icons.warning : Icons.event_available,
                        color: hasConflict ? Colors.red : Colors.green,
                      ),
                      trailing: const Icon(Icons.undo),
                      onTap: () {
                        _unclaimSlot(slot);
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
