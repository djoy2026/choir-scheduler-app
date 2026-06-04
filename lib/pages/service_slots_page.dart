import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

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
      await supabase
          .from('service_slots')
          .update({
            'slot_status': 'open',
            'assigned_user_id': null,
            'color_code': 'amber',
          })
          .eq('id', slot['id']);

      await _loadSlots();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Slot unclaimed')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<List<Map<String, dynamic>>> _loadAssignableUsers() async {
    final response = await supabase
        .from('profiles')
        .select('id, first_name, last_name, email')
        .order('first_name');

    return List<Map<String, dynamic>>.from(response);
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

      await supabase
          .from('service_slots')
          .update({
            'slot_status': 'pending',
            'assigned_user_id': selectedUser['id'],
            'color_code': 'blue',
          })
          .eq('id', slot['id']);

      await _loadSlots();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User assigned pending confirmation')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.serviceTitle.replaceAllMapped(
            RegExp(r'(\d{2}):(\d{2}):\d{2}'),
            (match) {
              final parsed = DateFormat('HH:mm:ss').parse(match.group(0)!);

              return DateFormat('h:mm a').format(parsed);
            },
          ),
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
