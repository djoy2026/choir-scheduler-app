import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      final response = await supabase
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        _notifications = List<Map<String, dynamic>>.from(response);
        _message = null;
      });
    } catch (e) {
      setState(() {
        _message = 'Unable to load notifications. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsRead(Map<String, dynamic> notification) async {
    if (notification['is_read'] == true) {
      return;
    }

    try {
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notification['id']);

      await _loadNotifications();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update notification. Please try again.'),
        ),
      );
    }
  }

  Future<void> _markAllRead() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', user.id)
          .eq('is_read', false);

      await _loadNotifications();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update notifications. Please try again.'),
        ),
      );
    }
  }

  String _formatCreatedAt(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) {
      return '';
    }

    final parsed = DateTime.tryParse(rawValue)?.toLocal();

    if (parsed == null) {
      return '';
    }

    final hour = parsed.hour > 12
        ? parsed.hour - 12
        : parsed.hour == 0
        ? 12
        : parsed.hour;
    final period = parsed.hour >= 12 ? 'PM' : 'AM';
    final minute = parsed.minute.toString().padLeft(2, '0');

    return '${parsed.month}/${parsed.day}/${parsed.year} • $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any(
      (notification) => notification['is_read'] != true,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark All Read'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _message != null
          ? Center(child: Text(_message!))
          : _notifications.isEmpty
          ? const Center(child: Text('No notifications'))
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _notifications.length,
                itemBuilder: (context, index) {
                  final notification = _notifications[index];
                  final isRead = notification['is_read'] == true;

                  return Card(
                    color: isRead ? Colors.grey.shade100 : Colors.blue.shade50,
                    child: ListTile(
                      leading: Icon(
                        isRead
                            ? Icons.notifications_none
                            : Icons.notifications_active,
                        color: isRead ? Colors.grey : Colors.blue,
                      ),
                      title: Text(
                        notification['title']?.toString() ?? '',
                        style: TextStyle(
                          fontWeight: isRead
                              ? FontWeight.w500
                              : FontWeight.w700,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(notification['message']?.toString() ?? ''),
                            const SizedBox(height: 4),
                            Text(
                              _formatCreatedAt(
                                notification['created_at']?.toString(),
                              ),
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                      onTap: () {
                        _markAsRead(notification);
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
