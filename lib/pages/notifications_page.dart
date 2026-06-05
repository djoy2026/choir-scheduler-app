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
  bool _isMarkingAllRead = false;
  List<Map<String, dynamic>> _notifications = [];
  String? _pressedNotificationId;
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
        _pressedNotificationId = null;
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
    setState(() {
      _pressedNotificationId = notification['id']?.toString();
    });
    await Future.delayed(const Duration(milliseconds: 120));

    if (notification['is_read'] == true) {
      if (!mounted) return;

      setState(() {
        _pressedNotificationId = null;
      });
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

      setState(() {
        _pressedNotificationId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update notification. Please try again.'),
        ),
      );
    }
  }

  Future<void> _markAllRead() async {
    try {
      setState(() {
        _isMarkingAllRead = true;
      });
      await Future.delayed(const Duration(milliseconds: 120));

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
    } finally {
      if (mounted) {
        setState(() {
          _isMarkingAllRead = false;
        });
      }
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

    final now = DateTime.now();
    final difference = now.difference(parsed);

    if (difference.inSeconds < 60) {
      return 'Just now';
    }

    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    }

    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }

    final today = DateUtils.dateOnly(now);
    final notificationDate = DateUtils.dateOnly(parsed);

    if (notificationDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }

    final hour = parsed.hour > 12
        ? parsed.hour - 12
        : parsed.hour == 0
        ? 12
        : parsed.hour;
    final period = parsed.hour >= 12 ? 'PM' : 'AM';
    final minute = parsed.minute.toString().padLeft(2, '0');

    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${weekdays[parsed.weekday - 1]}, ${months[parsed.month]} ${parsed.day} • $hour:$minute $period';
  }

  Color _notificationColor(Map<String, dynamic> notification) {
    final type = notification['notification_type']?.toString();
    final title = notification['title']?.toString();

    if (type == 'assignment_accepted' || title == 'Assignment Accepted') {
      return Colors.green;
    }

    if (type == 'assignment_declined' || title == 'Assignment Declined') {
      return Colors.red;
    }

    if (type == 'new_assignment' || title == 'New Assignment') {
      return Colors.blue;
    }

    return Colors.grey;
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
            AnimatedScale(
              scale: _isMarkingAllRead ? .94 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeInOut,
              child: TextButton(
                onPressed: _markAllRead,
                child: const Text('Mark All Read'),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _message != null
          ? Center(child: Text(_message!))
          : _notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 48,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(height: 12),
                  const Text('No notifications yet'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _notifications.length,
                itemBuilder: (context, index) {
                  final notification = _notifications[index];
                  final isRead = notification['is_read'] == true;
                  final notificationColor = _notificationColor(notification);
                  final isPressed =
                      _pressedNotificationId == notification['id']?.toString();

                  return AnimatedScale(
                    scale: isPressed ? .98 : 1,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeInOut,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: Card(
                        color: isRead
                            ? Colors.grey.shade100
                            : Colors.blue.shade50,
                        child: ListTile(
                          leading: Icon(
                            isRead
                                ? Icons.notifications_none
                                : Icons.notifications_active,
                            color: isRead
                                ? notificationColor.withValues(alpha: .45)
                                : notificationColor,
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
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
