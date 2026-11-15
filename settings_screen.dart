import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vpn_config.dart';
import '../services/vpn_engine_service.dart';
import '../theme/dragon_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _dnsCtrl;
  late TextEditingController _secDnsCtrl;
  late bool _bypassLan;

  @override
  void initState() {
    super.initState();
    final engine = context.read<VpnEngineService>();
    _dnsCtrl = TextEditingController(text: engine.customDns);
    _secDnsCtrl = TextEditingController(text: engine.secondaryDns);
    _bypassLan = engine.bypassLan;
  }

  @override
  void dispose() {
    _dnsCtrl.dispose();
    _secDnsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<VpnEngineService>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('DNS & Settings',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Free & Gaming DNS Presets (Tap to Apply)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: DnsPreset.freePresets.map((preset) {
                      final active = engine.customDns == preset.primary;
                      return ActionChip(
                        backgroundColor: active
                            ? DragonColors.electricBlue.withOpacity(0.22)
                            : DragonColors.charcoal,
                        side: BorderSide(
                          color: active
                              ? DragonColors.electricBlue
                              : Colors.white12,
                        ),
                        label: Text(
                          '${preset.name} (${preset.tag})',
                          style: TextStyle(
                            fontSize: 12,
                            color: active
                                ? DragonColors.electricBlue
                                : DragonColors.textPrimary,
                          ),
                        ),
                        onPressed: () {
                          _dnsCtrl.text = preset.primary;
                          _secDnsCtrl.text = preset.secondary;
                          engine.updateSettings(
                            dns: preset.primary,
                            secondaryDns: preset.secondary,
                            bypassLan: _bypassLan,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'DNS set to ${preset.name} (${preset.primary})')),
                          );
                        },
                      );
                    }).toList(),
                  ),
                  const Divider(height: 24, color: Colors.white12),
                  const Text('Custom DNS',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dnsCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Primary DNS',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _secDnsCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Secondary DNS',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bypass LAN Subnets'),
                    subtitle: const Text(
                        'Keep local router & LAN traffic outside the tunnel'),
                    value: _bypassLan,
                    onChanged: (v) => setState(() => _bypassLan = v),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () {
                        engine.updateSettings(
                          dns: _dnsCtrl.text,
                          secondaryDns: _secDnsCtrl.text,
                          bypassLan: _bypassLan,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Custom DNS & settings saved')),
                        );
                      },
                      child: const Text('Save & Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: ListTile(
              leading: Icon(Icons.shield_moon_rounded,
                  color: DragonColors.electricBlue),
              title: Text('VPNSOPR Turbo v3.0.0'),
              subtitle: Text(
                'Dragon Edition • 1s Live Ping & Jitter Chart • Multi-Panel • Admin & Gateways',
                style: TextStyle(color: DragonColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
