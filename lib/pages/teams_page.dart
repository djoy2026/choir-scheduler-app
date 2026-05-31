import 'service_instances_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class TeamsPage extends StatefulWidget {
  final String ministryId;

  final String ministryName;

  const TeamsPage({
    super.key,
    required this.ministryId,
    required this.ministryName,
  });

  @override
  State<TeamsPage> createState() => _TeamsPageState();
}

class _TeamsPageState extends State<TeamsPage> {
  List<dynamic> _teams = [];

  bool _isLoading = true;

  String? _message;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    try {
      final response = await supabase
          .from('teams')
          .select()
          .eq('ministry_id', widget.ministryId)
          .order('name');

      setState(() {
        _teams = response;
      });
    } catch (e) {
      setState(() {
        _message = 'Failed to load teams: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.ministryName)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _message != null
            ? Center(child: Text(_message!))
            : ListView.builder(
                itemCount: _teams.length,
                itemBuilder: (context, index) {
                  final team = _teams[index];

                  return Card(
                    child: ListTile(
                      title: Text(team['name'] ?? ''),
                      subtitle: Text(team['description'] ?? ''),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ServiceInstancesPage(
                              ministryId: widget.ministryId,
                              teamId: team['id'],
                              teamName: team['name'],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
