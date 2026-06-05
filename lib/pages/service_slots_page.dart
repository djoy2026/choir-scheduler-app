import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/time_format.dart';

final supabase = Supabase.instance.client;

class ServiceSlotsPage extends StatefulWidget {
  final String serviceInstanceId;
  final String serviceTitle;
  final String serviceDate;

  const ServiceSlotsPage({
    super.key,
    required this.serviceInstanceId,
    required this.serviceTitle,
    required this.serviceDate,
  });

  @override
  State<ServiceSlotsPage> createState() => _ServiceSlotsPageState();
}

class _ServiceSlotsPageState extends State<ServiceSlotsPage> {
  bool _isAdmin = false;

  List<dynamic> _slots = [];

  bool _isLoading = true;

  String? _message;

  @override
  void initState() {
    super.initState();

    _loadSlots();
  }

  Future<void> _loadSlots() async {
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
          .from('service_slots')
          .select('''
            *,
            profiles!service_slots_assigned_user_id_fkey (
              first_name,
              last_name
            )
          ''')
          .eq('service_instance_id', widget.serviceInstanceId)
          .order('slot_name');

      setState(() {
        _slots = response;
      });
    } catch (e) {
      setState(() {
        _message = 'Failed to load slots: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isMine(Map<String, dynamic> slot) {
    final user = supabase.auth.currentUser;

    return slot['assigned_user_id'] == user?.id;
  }

  String _claimedByName(Map<String, dynamic> slot) {
    final profile = slot['profiles'];

    if (profile == null) {
      return 'Unknown user';
    }

    final firstName = profile['first_name'] ?? '';

    final lastName = profile['last_name'] ?? '';

    final fullName = '$firstName $lastName'.trim();

    return fullName.isEmpty ? 'Unknown user' : fullName;
  }

  String _roleName(Map<String, dynamic> slot) {
    return slot['role_name']?.toString() ??
        slot['slot_name']?.toString() ??
        'Assignment';
  }

  Future<void> _createNotification({
    required String userId,
    required String title,
    required String message,
    required String notificationType,
  }) async {
    await supabase.from('notifications').insert({
      'user_id': userId,
      'title': title,
      'message': message,
      'notification_type': notificationType,
      'related_service_instance_id': widget.serviceInstanceId,
    });
  }

  Future<void> _claimSlot(Map<String, dynamic> slot) async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      await supabase
          .from('service_slots')
          .update({
            'slot_status': 'taken',
            'assigned_user_id': user.id,
            'color_code': 'green',
          })
          .eq('id', slot['id']);

      await _loadSlots();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Slot claimed successfully')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;

      final errorText = e.message.toLowerCase();

      String friendlyMessage = 'Database error occurred';

      if (errorText.contains('ux_service_slots_one_user_per_service') ||
          errorText.contains('constraint') ||
          errorText.contains('duplicate')) {
        friendlyMessage =
            'You already have a position assigned or pending for this service.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyMessage)));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _unclaimSlot(Map<String, dynamic> slot) async {
    try {
      final assignedUserId = slot['assigned_user_id']?.toString();

      await supabase
          .from('service_slots')
          .update({
            'slot_status': 'open',
            'assigned_user_id': null,
            'color_code': 'amber',
          })
          .eq('id', slot['id']);

      if (assignedUserId != null && assignedUserId.isNotEmpty) {
        await _createNotification(
          userId: assignedUserId,
          title: 'Assignment Removed',
          message: 'Your assignment was removed.',
          notificationType: 'assignment_removed',
        );
      }

      await _loadSlots();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Slot unclaimed')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to remove assignment. Please try again.'),
        ),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _loadAssignableUsers() async {
    final response = await supabase
        .from('profiles')
        .select('id, first_name, last_name, email')
        .order('first_name');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<bool> _isUserUnavailableForService(String userId) async {
    final response = await supabase
        .from('service_availability')
        .select('id')
        .eq('service_instance_id', widget.serviceInstanceId)
        .eq('user_id', userId)
        .eq('availability_status', 'unavailable')
        .limit(1);

    return response.isNotEmpty;
  }

  Future<void> _adminAssignSlot(Map<String, dynamic> slot) async {
    try {
      final users = await _loadAssignableUsers();

      if (!mounted) return;

      final selectedUser = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) {
          return SimpleDialog(
            title: const Text('Assign User'),
            children: users.map((user) {
              final name =
                  '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
                      .trim();

              final label = name.isEmpty ? user['email'] : name;

              return SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, user);
                },
                child: Text(label),
              );
            }).toList(),
          );
        },
      );

      if (selectedUser == null) {
        return;
      }

      final isUnavailable = await _isUserUnavailableForService(
        selectedUser['id'],
      );

      if (isUnavailable) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This volunteer marked themselves unavailable for this service.',
            ),
          ),
        );
        return;
      }

      await supabase
          .from('service_slots')
          .update({
            'slot_status': 'pending',
            'assigned_user_id': selectedUser['id'],
            'color_code': 'blue',
          })
          .eq('id', slot['id']);

      await _createNotification(
        userId: selectedUser['id'],
        title: 'New Assignment',
        message: 'You have been assigned to:\n${_roleName(slot)}',
        notificationType: 'new_assignment',
      );

      await _loadSlots();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User assigned pending confirmation')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;

      final errorText = e.message.toLowerCase();
      final friendlyMessage =
          errorText.contains('ux_service_slots_one_user_per_service')
          ? 'This volunteer is already assigned to another role in this service.'
          : 'Unable to assign volunteer. Please try again.';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyMessage)));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to assign volunteer. Please try again.'),
        ),
      );
    }
  }

  Color _slotColor(Map<String, dynamic> slot) {
    final status = slot['slot_status'];

    if (status == 'taken') {
      return Colors.green.shade200;
    }

    if (status == 'pending') {
      return Colors.blue.shade100;
    }

    return Colors.orange.shade200;
  }

  String _subtitle(Map<String, dynamic> slot) {
    final status = slot['slot_status'];

    if (status == 'open') {
      return 'Available';
    }

    if (status == 'pending') {
      if (_isMine(slot)) {
        return 'Pending your approval';
      }

      return 'Pending: ${_claimedByName(slot)}';
    }

    if (_isMine(slot)) {
      return 'Claimed by you';
    }

    return 'Taken by ${_claimedByName(slot)}';
  }

  String _formatServiceTitle(String title) {
    final formattedTitle = title.replaceAllMapped(
      RegExp(r'(\d{2}):(\d{2}):\d{2}'),
      (match) {
        return formatTime(match.group(0));
      },
    );

    final withoutSuffix = removeServiceSuffix(formattedTitle).trim();

    if (withoutSuffix.startsWith('Service ')) {
      return withoutSuffix.replaceFirst('Service ', '');
    }

    return withoutSuffix;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _formatServiceTitle(widget.serviceTitle),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _message != null
            ? Center(child: Text(_message!))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.serviceDate,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Expanded(
                    child: ListView.builder(
                      itemCount: _slots.length,
                      itemBuilder: (context, index) {
                        final slot = _slots[index];

                        final isOpen = slot['slot_status'] == 'open';

                        final isMine = _isMine(slot);

                        return Card(
                          color: _slotColor(slot),
                          child: ListTile(
                            title: Text(
                              slot['role_name'] ?? slot['slot_name'] ?? '',
                            ),

                            subtitle: Text(_subtitle(slot)),

                            trailing: Icon(
                              isOpen
                                  ? Icons.touch_app
                                  : isMine
                                  ? Icons.undo
                                  : Icons.check,
                            ),

                            onTap: isOpen
                                ? _isAdmin
                                      ? () => _adminAssignSlot(slot)
                                      : () => _claimSlot(slot)
                                : isMine
                                ? () => _unclaimSlot(slot)
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
