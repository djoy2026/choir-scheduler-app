import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/time_format.dart';
import '../utils/ui_helpers.dart';
import '../utils/error_messages.dart';

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
    } catch (e, stackTrace) {
      logTechnicalError(
        'MyAvailabilityPage._loadServices failed',
        e,
        stackTrace,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load availability.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
      final shouldMarkUnavailable = !_isUnavailable(service);

      if (shouldMarkUnavailable) {
        await supabase.from('service_availability').upsert({
          'service_instance_id': serviceId,
          'user_id': user.id,
          'availability_status': 'unavailable',
        }, onConflict: 'user_id,service_instance_id');
      } else {
        await supabase
            .from('service_availability')
            .delete()
            .eq('service_instance_id', serviceId)
            .eq('user_id', user.id);
      }

      await _loadServices();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Availability updated')));
    } on PostgrestException catch (e, stackTrace) {
      logTechnicalError(
        'MyAvailabilityPage._toggleAvailability failed',
        e,
        stackTrace,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update availability. Please try again.'),
        ),
      );
    } catch (e, stackTrace) {
      logTechnicalError(
        'MyAvailabilityPage._toggleAvailability failed',
        e,
        stackTrace,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update availability. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Availability')),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _services.isEmpty
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
                    'No upcoming services',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Availability options will appear when services are scheduled.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            )
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

                  return AccentCard(
                    accentColor: unavailable
                        ? Colors.red.shade500
                        : Colors.green.shade500,
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
                        formatServiceHeading(
                          service['service_date']?.toString(),
                          service['start_time']?.toString(),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: serviceTitleTextStyle,
                      ),

                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(team, style: mutedTextStyle(context)),

                            const SizedBox(height: 4),

                            Text(
                              service['location'] ?? '',
                              style: mutedTextStyle(context),
                            ),

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

                        activeThumbColor: Colors.red,
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
