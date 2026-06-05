import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'service_slots_page.dart';

final supabase = Supabase.instance.client;

class MonthlySchedulePage extends StatefulWidget {
  const MonthlySchedulePage({super.key});

  @override
  State<MonthlySchedulePage> createState() => _MonthlySchedulePageState();
}

class _MonthlySchedulePageState extends State<MonthlySchedulePage> {
  bool _isLoading = true;
  bool _isAdmin = false;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> _services = [];
  final Set<String> _expandedServiceIds = {};
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

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

      final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month);
      final lastDay = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + 1,
        0,
      );

      final response = await supabase
          .from('service_instances')
          .select('''
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
            service_slots (
              id,
              slot_name,
              role_name,
              slot_status,
              assigned_user_id,
              profiles!service_slots_assigned_user_id_fkey (
                first_name,
                last_name,
                email
              )
            ),
            service_availability (
              user_id,
              availability_status,
              profiles (
                first_name,
                last_name,
                email
              )
            )
          ''')
          .gte('service_date', _dateKey(firstDay))
          .lte('service_date', _dateKey(lastDay))
          .order('service_date')
          .order('start_time');

      setState(() {
        _services = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      setState(() {
        _message = 'Failed to load monthly schedule: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
                            initialDate: _selectedMonth,
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2030),
                          );

                          if (pickedDate != null) {
                            dateController.text = _dateKey(pickedDate);
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
                            startTimeController.text = _timeKey(pickedTime);
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
                            endTimeController.text = _timeKey(pickedTime);
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

  String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');

    return '${value.year}-$month-$day';
  }

  String _timeKey(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');

    return '$hour:$minute:00';
  }

  String _formatDate(String rawDate) {
    final parts = rawDate.split('-');

    if (parts.length != 3) {
      return rawDate;
    }

    return '${parts[1]}/${parts[2]}/${parts[0]}';
  }

  DateTime? _parseDate(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) {
      return null;
    }

    return DateTime.tryParse(rawDate);
  }

  String _formatTime(String? rawTime) {
    if (rawTime == null || rawTime.isEmpty) {
      return '';
    }

    final parts = rawTime.split(':');

    if (parts.length < 2) {
      return rawTime;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) {
      return rawTime;
    }

    final displayHour = hour > 12
        ? hour - 12
        : hour == 0
        ? 12
        : hour;
    final period = hour >= 12 ? 'PM' : 'AM';

    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  String _weekdayName(DateTime value) {
    const weekdays = [
      '',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return weekdays[value.weekday];
  }

  String _serviceTitle(Map<String, dynamic> service) {
    final rawName = service['service_name']?.toString() ?? 'Service';

    if (!rawName.startsWith('Service ')) {
      return rawName;
    }

    final serviceDate = _parseDate(service['service_date']?.toString());
    final formattedTime = _formatTime(service['start_time']?.toString());

    if (serviceDate == null || formattedTime.isEmpty) {
      return rawName;
    }

    return '${_weekdayName(serviceDate)} $formattedTime Service';
  }

  String _monthLabel(DateTime value) {
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

    return '${months[value.month]} ${value.year}';
  }

  String _volunteerName(Map<String, dynamic> slot) {
    final profile = slot['profiles'];

    if (profile is Map<String, dynamic>) {
      final firstName = profile['first_name']?.toString().trim() ?? '';
      final lastName = profile['last_name']?.toString().trim() ?? '';
      final fullName = '$firstName $lastName'.trim();

      if (fullName.isNotEmpty) {
        return fullName;
      }

      final email = profile['email']?.toString().trim();

      if (email != null && email.isNotEmpty) {
        return email;
      }
    }

    final status = slot['slot_status']?.toString().trim().toLowerCase();

    return status == 'open' ? 'Unassigned' : 'Unknown User';
  }

  String _availabilityVolunteerName(Map<String, dynamic> availability) {
    final profile = availability['profiles'];

    if (profile is Map<String, dynamic>) {
      final firstName = profile['first_name']?.toString().trim() ?? '';
      final lastName = profile['last_name']?.toString().trim() ?? '';
      final fullName = '$firstName $lastName'.trim();

      if (fullName.isNotEmpty) {
        return fullName;
      }

      final email = profile['email']?.toString().trim();

      if (email != null && email.isNotEmpty) {
        return email;
      }
    }

    return 'Unknown User';
  }

  String _roleName(Map<String, dynamic> slot) {
    return slot['role_name']?.toString().trim().isNotEmpty == true
        ? slot['role_name'].toString()
        : slot['slot_name']?.toString() ?? 'Role';
  }

  MaterialColor _statusColor(String? status) {
    switch (status?.trim().toLowerCase()) {
      case 'pending':
        return Colors.blue;
      case 'taken':
        return Colors.green;
      case 'open':
      default:
        return Colors.amber;
    }
  }

  String _statusLabel(String? status) {
    switch (status?.trim().toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'taken':
        return 'Taken';
      case 'open':
      default:
        return 'Open';
    }
  }

  int _slotCount(List<Map<String, dynamic>> slots, String status) {
    return slots.where((slot) {
      return slot['slot_status']?.toString().trim().toLowerCase() == status;
    }).length;
  }

  List<Map<String, dynamic>> _unavailableRows(
    List<Map<String, dynamic>> availabilityRows,
  ) {
    return availabilityRows.where((availability) {
      return availability['availability_status']
              ?.toString()
              .trim()
              .toLowerCase() ==
          'unavailable';
    }).toList();
  }

  MaterialColor _serviceHealthColor({
    required int open,
    required int pending,
    required int taken,
  }) {
    if (open > 5) {
      return Colors.red;
    }

    if (open > 0) {
      return Colors.amber;
    }

    if (pending > 0) {
      return Colors.blue;
    }

    if (taken > 0) {
      return Colors.green;
    }

    return Colors.grey;
  }

  String _serviceHealthLabel({
    required int open,
    required int pending,
    required int taken,
  }) {
    if (open > 0) {
      return 'Needs Volunteers';
    }

    if (pending > 0) {
      return 'Pending Confirmations';
    }

    if (taken > 0) {
      return 'Fully Staffed';
    }

    return 'No Slots';
  }

  Map<String, List<Map<String, dynamic>>> _groupServices() {
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final service in _services) {
      final key =
          '${service['service_date'] ?? ''}|${service['service_name'] ?? ''}';
      grouped.putIfAbsent(key, () => []).add(service);
    }

    return grouped;
  }

  Future<void> _changeMonth(int offset) async {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + offset,
      );
    });

    await _loadServices();
  }

  Future<void> _openSlots(Map<String, dynamic> service) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceSlotsPage(
          serviceInstanceId: service['id'],
          serviceTitle: _serviceTitle(service),
          serviceDate: _formatDate(service['service_date'] ?? ''),
        ),
      ),
    );

    if (mounted) {
      await _loadServices();
    }
  }

  Widget _buildMonthSelector() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: () {
            _changeMonth(-1);
          },
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            _monthLabel(_selectedMonth),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: () {
            _changeMonth(1);
          },
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _buildScheduleList() {
    if (_services.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(child: Text('No services scheduled for this month.')),
        ],
      );
    }

    final grouped = _groupServices();
    final entries = grouped.entries.toList()
      ..sort((a, b) {
        final aService = a.value.first;
        final bService = b.value.first;
        final dateCompare = (aService['service_date']?.toString() ?? '')
            .compareTo(bService['service_date']?.toString() ?? '');

        if (dateCompare != 0) {
          return dateCompare;
        }

        return (aService['start_time']?.toString() ?? '').compareTo(
          bService['start_time']?.toString() ?? '',
        );
      });

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final services = entries[index].value;
        final firstService = services.first;
        final serviceId = firstService['id']?.toString() ?? entries[index].key;
        final slots =
            services
                .expand((service) => service['service_slots'] ?? const [])
                .map((slot) => Map<String, dynamic>.from(slot))
                .toList()
              ..sort((a, b) => _roleName(a).compareTo(_roleName(b)));
        final availabilityRows = services
            .expand((service) => service['service_availability'] ?? const [])
            .map((availability) => Map<String, dynamic>.from(availability))
            .toList();
        final unavailableRows = _unavailableRows(availabilityRows)
          ..sort(
            (a, b) => _availabilityVolunteerName(
              a,
            ).compareTo(_availabilityVolunteerName(b)),
          );
        final teamName = firstService['teams']?['name'] ?? '';
        final location = firstService['location']?.toString() ?? '';
        final openCount = _slotCount(slots, 'open');
        final pendingCount = _slotCount(slots, 'pending');
        final takenCount = _slotCount(slots, 'taken');
        final healthColor = _serviceHealthColor(
          open: openCount,
          pending: pendingCount,
          taken: takenCount,
        );
        final healthLabel = _serviceHealthLabel(
          open: openCount,
          pending: pendingCount,
          taken: takenCount,
        );
        final isExpanded = _expandedServiceIds.contains(serviceId);

        return Card(
          color: healthColor.shade50,
          child: ExpansionTile(
            key: PageStorageKey(serviceId),
            initiallyExpanded: isExpanded,
            onExpansionChanged: (expanded) {
              setState(() {
                if (expanded) {
                  _expandedServiceIds.add(serviceId);
                } else {
                  _expandedServiceIds.remove(serviceId);
                }
              });
            },
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            title: Text(
              _serviceTitle(firstService),
              softWrap: true,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHealthBadge(healthLabel, healthColor),
                  const SizedBox(height: 6),
                  Text(
                    'Open: $openCount | Pending: $pendingCount | Taken: $takenCount',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (_isAdmin) ...[
                    const SizedBox(height: 4),
                    Text('Unavailable: ${unavailableRows.length}'),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '${_formatDate(firstService['service_date'] ?? '')}'
                    ' • ${_formatTime(firstService['start_time'])}'
                    ' - ${_formatTime(firstService['end_time'])}',
                  ),
                  if (teamName.toString().isNotEmpty || location.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '$teamName${location.isEmpty ? '' : ' • $location'}',
                      ),
                    ),
                ],
              ),
            ),
            trailing: Text(
              isExpanded ? '▲ Hide Roles' : '▼ Show Roles',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    _openSlots(firstService);
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Slots'),
                ),
              ),
              if (slots.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('No slots have been generated yet.'),
                  ),
                )
              else
                ...slots.map(_buildSlotRow),
              if (_isAdmin && unavailableRows.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Unavailable Volunteers',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 6),
                ...unavailableRows.map(_buildUnavailableRow),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSlotRow(Map<String, dynamic> slot) {
    final status = slot['slot_status']?.toString().trim().toLowerCase();
    final color = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _roleName(slot),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(_volunteerName(slot)),
              ],
            ),
          ),
          Text(_statusLabel(status), style: TextStyle(color: color.shade900)),
        ],
      ),
    );
  }

  Widget _buildUnavailableRow(Map<String, dynamic> availability) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.block, color: Colors.red.shade700, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(_availabilityVolunteerName(availability))),
          Text('Unavailable', style: TextStyle(color: Colors.red.shade900)),
        ],
      ),
    );
  }

  Widget _buildHealthBadge(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade300),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.shade900,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Schedule'),
        actions: [
          if (_isAdmin)
            IconButton(
              tooltip: 'Create service',
              onPressed: _createService,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildMonthSelector(),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _message != null
                  ? Center(child: Text(_message!))
                  : RefreshIndicator(
                      onRefresh: _loadServices,
                      child: _buildScheduleList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
