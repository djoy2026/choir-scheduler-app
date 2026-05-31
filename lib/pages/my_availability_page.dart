import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class MyAvailabilityPage extends StatefulWidget {
  const MyAvailabilityPage({super.key});

  @override
  State<MyAvailabilityPage> createState() => _MyAvailabilityPageState();
}

class _MyAvailabilityPageState extends State<MyAvailabilityPage> {
  bool _isLoading = true;

  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _services = [];

  @override
  void initState() {
    super.initState();

    _loadServices();
  }

  Future<void> _loadServices() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) return;

      final now = DateTime.now();

      final response = await supabase
          .from('service_instances')
          .select('''
            *,
            teams (
              name
            ),
            service_availability (
              user_id,
              availability_status
            )
          ''')
          .gte('service_date', now.toIso8601String().split('T')[0])
          .order('service_date')
          .order('start_time');

      setState(() {
        _services = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Load services error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isUnavailable(Map<String, dynamic> service) {
    final user = supabase.auth.currentUser;

    if (user == null) return false;

    final availability = service['service_availability'] ?? [];

    return availability.any(
      (item) =>
          item['user_id'] == user.id &&
          item['availability_status'] == 'unavailable',
    );
  }

  Future<void> _toggleAvailability(Map<String, dynamic> service) async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) return;

      final serviceId = service['id'];

      final existing = await supabase
          .from('service_availability')
          .select()
          .eq('service_instance_id', serviceId)
          .eq('user_id', user.id);

      if (existing.isNotEmpty) {
        await supabase
            .from('service_availability')
            .delete()
            .eq('service_instance_id', serviceId)
            .eq('user_id', user.id);
      } else {
        await supabase.from('service_availability').insert({
          'service_instance_id': serviceId,
          'user_id': user.id,
          'availability_status': 'unavailable',
        });
      }

      setState(() {
        final serviceIndex = _services.indexWhere(
          (service) => service['id'] == serviceId,
        );

        if (serviceIndex != -1) {
          final availability = _services[serviceIndex]['service_availability'];

          if (existing.isNotEmpty) {
            availability.removeWhere((item) => item['user_id'] == user.id);
          } else {
            availability.add({
              'user_id': user.id,
              'availability_status': 'unavailable',
            });
          }
        }
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing.isNotEmpty ? 'Marked available' : 'Marked unavailable',
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Availability')),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _services.isEmpty
          ? const Center(child: Text('No upcoming services'))
          : RefreshIndicator(
              onRefresh: _loadServices,

              child: ListView.builder(
                controller: _scrollController,

                padding: const EdgeInsets.all(16),

                itemCount: _services.length,

                itemBuilder: (context, index) {
                  final service = _services[index];

                  final unavailable = _isUnavailable(service);

                  final team = service['teams']?['name'] ?? '';

                  return Card(
                    elevation: 3,

                    color: unavailable
                        ? Colors.red.shade50
                        : Colors.green.shade50,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),

                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),

                      leading: Icon(
                        unavailable ? Icons.block : Icons.check_circle,
                        color: unavailable ? Colors.red : Colors.green,
                      ),

                      title: Text(
                        service['service_name'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),

                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              '${_formatDate(service['service_date'])}'
                              ' • ${service['start_time']}'
                              ' - ${service['end_time']}',
                            ),

                            const SizedBox(height: 4),

                            Text(team),

                            Text(service['location'] ?? ''),

                            const SizedBox(height: 10),

                            Text(
                              unavailable ? 'Unavailable' : 'Available',
                              style: TextStyle(
                                color: unavailable ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      trailing: Switch(
                        value: unavailable,

                        activeColor: Colors.red,
                        activeTrackColor: Colors.red.shade200,

                        inactiveThumbColor: Colors.green,
                        inactiveTrackColor: Colors.green.shade200,

                        onChanged: (_) {
                          _toggleAvailability(service);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
