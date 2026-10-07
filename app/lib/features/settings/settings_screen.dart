import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/server_url.dart';
import 'settings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _url = TextEditingController(text: ref.read(settingsProvider).serverUrl);
  String? _message;
  bool _messageIsError = false;
  bool _testing = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final normalized = normalizeServerUrl(_url.text);
    if (normalized == null) {
      setState(() {
        _message = "That doesn't look like a server address. Try something like https://your-server.onrender.com";
        _messageIsError = true;
      });
      return;
    }
    _url.text = normalized;
    await ref.read(settingsProvider.notifier).setServerUrl(normalized);
    setState(() {
      _testing = true;
      _message = null;
    });
    try {
      final meta = await ref.read(apiClientProvider).getJson('/api/meta');
      final warning = isInsecureRemote(normalized)
          ? ' Note: this address is not secure (http), so your schedule and location would travel unprotected.'
          : '';
      setState(() {
        _message = 'Connected. The server knows ${meta['nodes']} campus path points.$warning';
        _messageIsError = isInsecureRemote(normalized);
      });
    } on ApiException catch (e) {
      setState(() {
        _message = 'Saved, but ${e.message}';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Server', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Server address',
              hintText: 'https://your-server.onrender.com',
            ),
            onSubmitted: (_) => _saveAndTest(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _testing ? null : _saveAndTest,
              child: Text(_testing ? 'Connecting…' : 'Save and test'),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _message!,
                style: TextStyle(color: _messageIsError ? Theme.of(context).colorScheme.error : null),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'The server works out walking times. It keeps nothing: it is sent your classes (and location, if '
            'you allow it) each time and forgets them straight away.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use my location'),
            subtitle: const Text('Starts the walk to your next class from where you are.'),
            value: settings.useLocation,
            onChanged: controller.setUseLocation,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Heads-up before leaving'),
            subtitle: const Text('How early the "leave soon" banner appears.'),
            trailing: DropdownButton<int>(
              value: settings.remindLeadMinutes,
              items: const [
                DropdownMenuItem(value: 0, child: Text('None')),
                DropdownMenuItem(value: 5, child: Text('5 min')),
                DropdownMenuItem(value: 10, child: Text('10 min')),
              ],
              onChanged: (value) => controller.setRemindLead(value ?? 5),
            ),
          ),
        ],
      ),
    );
  }
}
