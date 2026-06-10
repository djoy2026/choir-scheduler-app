import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/time_format.dart';
import '../utils/ui_helpers.dart';
import '../utils/error_messages.dart';

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
            ministry_id,
            team_id,
            service_name,
            service_date,
            start_time,
            end_time,
            location,
            teams (
              name
            ),
            ministries (
              name
            )
          )
        ''')
          .eq('assigned_user_id', user.id)
          .eq('slot_status', 'taken');

      setState(() {
        _schedule = List<Map<String, dynamic>>.from(response);
      });
    } catch (e, stackTrace) {
      logTechnicalError('MySchedulePage._loadMySchedule failed', e, stackTrace);
      setState(() {
        _message = friendlyErrorMessage(
          e,
          fallback: 'Unable to load your schedule. Please try again.',
        );
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
      final slotId = slot['id'];
      final updateResponse = await supabase
          .from('service_slots')
          .update({
            'slot_status': 'open',
            'assigned_user_id': null,
            'color_code': 'amber',
          })
          .eq('id', slotId)
          .select('id, slot_status, assigned_user_id, color_code');
      final updatedRows = List<Map<String, dynamic>>.from(updateResponse);

      debugPrint(
        'MySchedulePage._unclaimSlot update response: $updateResponse',
      );
      debugPrint('MySchedulePage._unclaimSlot returned rows: $updatedRows');

      if (updatedRows.isEmpty) {
        throw const PostgrestException(
          message: 'Schedule removal affected 0 rows.',
          code: 'PGRST_ZERO_ROWS',
          details: 'The service_slots update completed but returned no rows.',
          hint: 'Verify RLS permits updating the selected service_slots row.',
        );
      }

      final updatedSlot = updatedRows.first;

      if (updatedSlot['slot_status'] != 'open' ||
          updatedSlot['assigned_user_id'] != null ||
          updatedSlot['color_code'] != 'amber') {
        throw PostgrestException(
          message: 'Schedule removal verification failed.',
          code: 'PGRST_VERIFY_FAILED',
          details:
              'Expected slot_status=open, assigned_user_id=null, color_code=amber. Got $updatedSlot.',
          hint:
              'The update returned a row, but the slot was not persisted as available.',
        );
      }

      final verificationResponse = await supabase
          .from('service_slots')
          .select('id, slot_status, assigned_user_id, color_code')
          .eq('id', slotId)
          .maybeSingle();

      debugPrint(
        'MySchedulePage._unclaimSlot verification query: '
        '$verificationResponse',
      );

      if (verificationResponse == null ||
          verificationResponse['slot_status'] != 'open' ||
          verificationResponse['assigned_user_id'] != null ||
          verificationResponse['color_code'] != 'amber') {
        throw PostgrestException(
          message: 'Schedule removal verification query failed.',
          code: 'PGRST_VERIFY_QUERY_FAILED',
          details: 'Verification query returned $verificationResponse.',
          hint: 'The database did not report the slot as open after removal.',
        );
      }

      await _loadMySchedule();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Removed from schedule')));
    } catch (e, stackTrace) {
      logTechnicalError('MySchedulePage._unclaimSlot failed', e, stackTrace);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Unable to remove this assignment. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _requestCoverage(Map<String, dynamic> slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Request Coverage?'),
          content: const Text(
            'Your assignment will be released and team members will be notified.',
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
              child: const Text('Request Coverage'),
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
        'request_coverage',
        params: {'p_service_slot_id': slot['id'], 'p_message': null},
      );

      await _loadMySchedule();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Coverage request sent')));
    } catch (e, stackTrace) {
      logTechnicalError(
        'MySchedulePage._requestCoverage failed',
        e,
        stackTrace,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Unable to request coverage. Please try again.',
            ),
          ),
        ),
      );
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
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.event_available,
                      size: 48,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No scheduled services',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Confirmed assignments will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              )
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

                  final accentColor = hasConflict
                      ? Colors.red.shade500
                      : Colors.green.shade500;

                  return Card(
                    color: hasConflict ? Colors.red.shade100 : Colors.white,
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: accentColor.withValues(alpha: .8),
                            width: 4,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    hasConflict
                                        ? Icons.warning
                                        : Icons.event_available,
                                    color: hasConflict
                                        ? Colors.red
                                        : Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        formatServiceHeading(
                                          service['service_date']?.toString(),
                                          service['start_time']?.toString(),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: true,
                                        style: serviceTitleTextStyle,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '$ministry'
                                        '${ministry.isNotEmpty && team.isNotEmpty ? ' • ' : ''}'
                                        '$team\n'
                                        '${service['location'] ?? ''}\n'
                                        '${slot['role_name'] ?? slot['slot_name']}'
                                        '${hasConflict ? '\nConflict detected' : ''}',
                                        softWrap: true,
                                        style: mutedTextStyle(context),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _unclaimSlot(slot),
                                  icon: const Icon(Icons.undo),
                                  label: const Text('Remove'),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _requestCoverage(slot),
                                  icon: const Icon(Icons.volunteer_activism),
                                  label: const Text(
                                    'Request Coverage',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                  ),
                                ),
                              ],
                            ),
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
