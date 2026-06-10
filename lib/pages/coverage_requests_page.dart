import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/error_messages.dart';
import '../utils/time_format.dart';

final supabase = Supabase.instance.client;

class CoverageRequestsPage extends StatefulWidget {
  const CoverageRequestsPage({super.key});

  @override
  State<CoverageRequestsPage> createState() => _CoverageRequestsPageState();
}

class _CoverageRequestsPageState extends State<CoverageRequestsPage> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      _isAdmin = profile?['role']?.toString().trim().toLowerCase() == 'admin';

      final query = supabase
          .from('coverage_requests')
          .select('''
            id,
            status,
            message,
            requesting_user_id,
            service_slots (
              role_name,
              slot_name
            ),
            service_instances (
              service_name,
              service_date,
              start_time,
              location
            ),
            teams (
              name
            ),
            profiles!coverage_requests_requesting_user_id_fkey (
              first_name,
              last_name,
              email
            )
          ''')
          .eq('status', 'open');

      final response = await query.order('created_at');

      setState(() {
        _requests = List<Map<String, dynamic>>.from(response);
      });
    } catch (e, stackTrace) {
      logTechnicalError(
        'CoverageRequestsPage._loadRequests failed',
        e,
        stackTrace,
      );
      setState(() {
        _message = friendlyErrorMessage(
          e,
          fallback: 'Unable to load coverage requests. Please try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _claimCoverage(Map<String, dynamic> request) async {
    try {
      await supabase.rpc(
        'claim_coverage_request',
        params: {'p_coverage_request_id': request['id']},
      );

      await _loadRequests();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Coverage claimed')));
    } catch (e, stackTrace) {
      logTechnicalError(
        'CoverageRequestsPage._claimCoverage failed',
        e,
        stackTrace,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Unable to claim coverage. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  String _roleName(Map<String, dynamic> request) {
    final slot = request['service_slots'];

    if (slot is! Map<String, dynamic>) {
      return 'Assignment';
    }

    return slot['role_name']?.toString() ??
        slot['slot_name']?.toString() ??
        'Assignment';
  }

  String _requesterName(Map<String, dynamic> request) {
    final profile = request['profiles'];

    if (profile is! Map<String, dynamic>) {
      return 'Unknown User';
    }

    final firstName = profile['first_name']?.toString() ?? '';
    final lastName = profile['last_name']?.toString() ?? '';
    final fullName = '$firstName $lastName'.trim();

    return fullName.isEmpty
        ? profile['email']?.toString() ?? 'Unknown User'
        : fullName;
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final service = request['service_instances'] as Map<String, dynamic>?;
    final team = request['teams'] as Map<String, dynamic>?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _roleName(request),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              formatServiceHeading(
                service?['service_date']?.toString(),
                service?['start_time']?.toString(),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${team?['name'] ?? 'Team'}'
              '${service?['location'] == null ? '' : ' • ${service?['location']}'}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              'Requested by ${_requesterName(request)}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            if (request['message'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(request['message'].toString()),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _claimCoverage(request),
                icon: const Icon(Icons.volunteer_activism),
                label: const Text('Claim Coverage'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coverage Requests')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _message != null
          ? Center(child: Text(_message!))
          : RefreshIndicator(
              onRefresh: _loadRequests,
              child: _requests.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 120),
                        Icon(
                          Icons.volunteer_activism,
                          size: 52,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(height: 14),
                        const Center(
                          child: Text(
                            'No coverage requests',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: Text(
                            _isAdmin
                                ? 'Open coverage needs will appear here.'
                                : 'Requests matching your assigned roles will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: _requests.map(_buildRequestCard).toList(),
                    ),
            ),
    );
  }
}
