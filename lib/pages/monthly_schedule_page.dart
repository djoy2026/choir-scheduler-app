import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'service_slots_page.dart';
import 'package:intl/intl.dart';

final supabase = Supabase.instance.client;

class MonthlySchedulePage extends StatefulWidget {
  const MonthlySchedulePage({super.key});

  @override
  State<MonthlySchedulePage> createState() => _MonthlySchedulePageState();
}

class _MonthlySchedulePageState extends State<MonthlySchedulePage> {
  bool _isLoading = true;

  bool _isAdmin = false;

  List<Map<String, dynamic>> _services = [];

  String? _message;

  @override
  void initState() {
    super.initState();

    _loadServices();
  }

  Future<void> _loadServices() async {
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

      final now = DateTime.now();

      final firstDay = DateTime(now.year, now.month, 1);

      final lastDay = DateTime(now.year, now.month + 1, 0);

      final response = await supabase
          .from('service_instances')
          .select('''
            *,
            teams (
              name
            ),
            service_slots (
              slot_status
            ),
            service_availability (
              user_id,
              availability_status
            )
          ''')
          .gte('service_date', firstDay.toIso8601String().split('T')[0])
          .lte('service_date', lastDay.toIso8601String().split('T')[0])
          .order('service_date')
          .order('start_time');

      final services = List<Map<String, dynamic>>.from(response);

      services.sort((a, b) {
        final aSlots = a['service_slots'] ?? [];
        final bSlots = b['service_slots'] ?? [];

        final aOpen = aSlots
            .where((slot) => slot['slot_status'] == 'open')
            .length;

        final bOpen = bSlots
            .where((slot) => slot['slot_status'] == 'open')
            .length;

        return bOpen.compareTo(aOpen);
      });

      setState(() {
        _services = services;
      });
    } catch (e) {
      setState(() {
        _message = 'Failed to load services: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createService() async {
    try {
      final teams = await supabase
          .from('teams')
          .select('id, name, ministry_id')
          .inFilter('name', [
            'All Main Choir Volunteers',
            'All Kids Choir Volunteers',
            "Children's Ministry Live Schedule",
          ]);

      if (!mounted) return;

      Map<String, dynamic>? selectedTeam;

      final locationController = TextEditingController();

      final dateController = TextEditingController();

      final startTimeController = TextEditingController();

      final endTimeController = TextEditingController();

      String selectedServiceType = 'Service';

      final confirmed = await showDialog<bool>(
        context: context,

        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Create Service'),

                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,

                    children: [
                      DropdownButtonFormField<Map<String, dynamic>>(
                        isExpanded: true,

                        initialValue: selectedTeam,

                        items: teams
                            .map<DropdownMenuItem<Map<String, dynamic>>>((
                              team,
                            ) {
                              return DropdownMenuItem(
                                value: team,

                                child: Text(
                                  team['name'],
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            })
                            .toList(),

                        onChanged: (value) {
                          setDialogState(() {
                            selectedTeam = value;
                          });
                        },

                        decoration: const InputDecoration(labelText: 'Team'),
                      ),

                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        initialValue: selectedServiceType,

                        items: const [
                          DropdownMenuItem(
                            value: 'Service',

                            child: Text('Service'),
                          ),

                          DropdownMenuItem(
                            value: 'Rehearsal',

                            child: Text('Rehearsal'),
                          ),

                          DropdownMenuItem(
                            value: 'Special Event',

                            child: Text('Special Event'),
                          ),
                        ],

                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setDialogState(() {
                            selectedServiceType = value;
                          });
                        },

                        decoration: const InputDecoration(
                          labelText: 'Service Type',
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: dateController,

                        readOnly: true,

                        decoration: const InputDecoration(
                          labelText: 'Date',

                          suffixIcon: Icon(Icons.calendar_today),
                        ),

                        onTap: () async {
                          final pickedDate = await showDatePicker(
                            context: context,

                            initialDate: DateTime.now(),

                            firstDate: DateTime.now(),

                            lastDate: DateTime(2030),
                          );

                          if (pickedDate != null) {
                            dateController.text = pickedDate
                                .toIso8601String()
                                .split('T')[0];
                          }
                        },
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: startTimeController,

                        readOnly: true,

                        decoration: const InputDecoration(
                          labelText: 'Start Time',

                          suffixIcon: Icon(Icons.access_time),

                          border: OutlineInputBorder(),
                        ),

                        onTap: () async {
                          final pickedTime = await showTimePicker(
                            context: context,

                            initialTime: const TimeOfDay(hour: 9, minute: 0),
                          );

                          if (pickedTime != null) {
                            final hour = pickedTime.hour.toString().padLeft(
                              2,
                              '0',
                            );

                            final minute = pickedTime.minute.toString().padLeft(
                              2,
                              '0',
                            );

                            startTimeController.text = '$hour:$minute:00';
                          }
                        },
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: endTimeController,

                        readOnly: true,

                        decoration: const InputDecoration(
                          labelText: 'End Time',

                          suffixIcon: Icon(Icons.access_time),

                          border: OutlineInputBorder(),
                        ),

                        onTap: () async {
                          final pickedTime = await showTimePicker(
                            context: context,

                            initialTime: const TimeOfDay(hour: 11, minute: 0),
                          );

                          if (pickedTime != null) {
                            final hour = pickedTime.hour.toString().padLeft(
                              2,
                              '0',
                            );

                            final minute = pickedTime.minute.toString().padLeft(
                              2,
                              '0',
                            );

                            endTimeController.text = '$hour:$minute:00';
                          }
                        },
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: locationController,

                        decoration: const InputDecoration(
                          labelText: 'Location',

                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),

                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context, false);
                    },

                    child: const Text('Cancel'),
                  ),

                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context, true);
                    },

                    child: const Text('Create'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (confirmed != true ||
          selectedTeam == null ||
          dateController.text.isEmpty ||
          startTimeController.text.isEmpty ||
          endTimeController.text.isEmpty) {
        return;
      }
      final inserted = await supabase
          .from('service_instances')
          .insert({
            'ministry_id': selectedTeam!['ministry_id'],
            'team_id': selectedTeam!['id'],
            'service_name': '$selectedServiceType ${startTimeController.text}',
            'service_date': dateController.text,
            'start_time': startTimeController.text,
            'end_time': endTimeController.text,
            'location': locationController.text,
            'status': 'active',
          })
          .select()
          .single();

      await supabase.rpc(
        'generate_slots_from_team_roles',
        params: {'p_service_instance_id': inserted['id']},
      );

      await _loadServices();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service created successfully')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _formatDate(String rawDate) {
    final parts = rawDate.split('-');

    if (parts.length != 3) {
      return rawDate;
    }

    return '${parts[1]}/${parts[2]}/${parts[0]}';
  }

  String _formatTime(String rawTime) {
    try {
      final parsedTime = DateFormat('HH:mm:ss').parse(rawTime);

      return DateFormat('h:mm a').format(parsedTime);
    } catch (e) {
      return rawTime;
    }
  }

  String _monthName(int month) {
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month];
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Schedule'),

        actions: [
          if (_isAdmin)
            IconButton(onPressed: _createService, icon: const Icon(Icons.add)),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _message != null
            ? Center(child: Text(_message!))
            : _services.isEmpty
            ? const Center(child: Text('No services this month'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    '${_monthName(now.month)} ${now.year}',

                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadServices,

                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),

                        itemCount: _services.length,

                        itemBuilder: (context, index) {
                          final service = _services[index];

                          final team = service['teams']?['name'] ?? '';

                          final slots = service['service_slots'] ?? [];

                          final availability =
                              service['service_availability'] ?? [];

                          final openCount = slots
                              .where((slot) => slot['slot_status'] == 'open')
                              .length;

                          final pendingCount = slots
                              .where((slot) => slot['slot_status'] == 'pending')
                              .length;

                          final takenCount = slots
                              .where((slot) => slot['slot_status'] == 'taken')
                              .length;

                          final unavailableCount = availability
                              .where(
                                (item) =>
                                    item['availability_status'] ==
                                    'unavailable',
                              )
                              .length;

                          final availableCount =
                              (slots.length - unavailableCount).clamp(
                                0,
                                slots.length,
                              );

                          return Card(
                            color: openCount > 0
                                ? Colors.orange.shade50
                                : Colors.green.shade50,

                            child: ListTile(
                              title: Text(
                                (service['service_name'] ?? '')
                                    .replaceAllMapped(
                                      RegExp(r'(\d{2}):(\d{2}):\d{2}'),
                                      (match) {
                                        final parsed = DateFormat(
                                          'HH:mm:ss',
                                        ).parse(match.group(0)!);

                                        return DateFormat(
                                          'h:mm a',
                                        ).format(parsed);
                                      },
                                    ),
                              ),

                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  Text(
                                    '${_formatDate(service['service_date'])}'
                                    ' • ${_formatTime(service['start_time'])}'
                                    ' - ${_formatTime(service['end_time'])}\n'
                                    '$team\n'
                                    '${service['location'] ?? ''}',
                                  ),

                                  const SizedBox(height: 6),

                                  Text(
                                    'Open: $openCount | Pending: $pendingCount | Taken: $takenCount',

                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),

                                  const SizedBox(height: 4),

                                  RichText(
                                    text: TextSpan(
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),

                                      children: [
                                        TextSpan(
                                          text: 'Available: $availableCount',
                                          style: TextStyle(
                                            color: Colors.green.shade700,
                                          ),
                                        ),

                                        const TextSpan(
                                          text: '   |   ',
                                          style: TextStyle(color: Colors.grey),
                                        ),

                                        TextSpan(
                                          text:
                                              'Unavailable: $unavailableCount',
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  if (openCount > 0)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 4),

                                      child: Text(
                                        'Needs Volunteers',

                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),

                              trailing: const Icon(Icons.arrow_forward_ios),

                              onTap: () {
                                Navigator.push(
                                  context,

                                  MaterialPageRoute(
                                    builder: (_) => ServiceSlotsPage(
                                      serviceInstanceId: service['id'],

                                      serviceTitle:
                                          service['service_name'] ?? 'Service',

                                      serviceDate: _formatDate(
                                        service['service_date'],
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
                  ),
                ],
              ),
      ),
    );
  }
}
