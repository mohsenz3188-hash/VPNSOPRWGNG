import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vpn_config.dart';
import '../services/vpn_engine_service.dart';
import '../theme/dragon_theme.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  late IranianGateway _selectedGateway;
  late bool _gwEnabled;
  late TextEditingController _merchantCtrl;

  @override
  void initState() {
    super.initState();
    final gw = context.read<VpnEngineService>().gatewayConfig;
    _selectedGateway = gw.gateway;
    _gwEnabled = gw.enabled;
    _merchantCtrl = TextEditingController(text: gw.merchantOrCard);
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<VpnEngineService>();
    final panels = engine.panels;
    final plans = engine.plans;
    final wgConfigs =
        engine.configs.where((c) => c.protocol == VpnProtocol.wireguard).toList();
    final ovpnConfigs =
        engine.configs.where((c) => c.protocol == VpnProtocol.openvpn).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Admin Command Center',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Add Panel (3x-UI / Marzban / Pasargad)',
            icon: const Icon(Icons.add_circle_outline_rounded,
                color: DragonColors.electricBlue),
            onPressed: () => _showAddPanelDialog(context, engine),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Volume & Price Plans for Gateway Checkout
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('پکیج‌های حجم و قیمت (فروش درگاه)',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_box_rounded,
                            color: DragonColors.electricBlue),
                        onPressed: () => _showAddPlanDialog(context, engine),
                      ),
                    ],
                  ),
                  if (plans.isEmpty)
                    const Text('هیچ پکیجی ثبت نشده است.',
                        style: TextStyle(
                            fontSize: 12, color: DragonColors.textSecondary))
                  else
                    ...plans.map((pl) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${pl.title} (${pl.volumeGb} GB)'),
                          subtitle: Text(
                              '${pl.durationDays} روز • ${pl.priceTomans} تومان',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: DragonColors.electricBlue)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: DragonColors.crimsonRed),
                            onPressed: () => engine.deletePlan(pl.id),
                          ),
                        )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 2. Connected Panels
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Connected Panels (3x-UI / Marzban / Pasargad)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (panels.isEmpty)
                    const Text('No panels added yet. Tap + above to connect.',
                        style: TextStyle(
                            fontSize: 12, color: DragonColors.textSecondary))
                  else
                    ...panels.map((p) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${p.name} (${p.typeLabel})'),
                          subtitle: Text(p.baseUrl,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: DragonColors.textSecondary)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.sync,
                                    color: DragonColors.electricBlue),
                                onPressed: () async {
                                  final msg = await engine.syncPanel(p);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(msg)));
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: DragonColors.crimsonRed),
                                onPressed: () => engine.deletePanel(p.id),
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 3. Instant WireGuard & OpenVPN Tester
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Instant WireGuard & OpenVPN Tester',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'WireGuard configs: ${wgConfigs.length}  •  OpenVPN configs: ${ovpnConfigs.length}',
                    style: const TextStyle(
                        fontSize: 12, color: DragonColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.security_rounded, size: 16),
                        label: const Text('Test WireGuard'),
                        onPressed: wgConfigs.isEmpty
                            ? null
                            : () async {
                                final res = await engine
                                    .testProtocolConfig(wgConfigs.first);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(res)));
                                }
                              },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.vpn_key_rounded, size: 16),
                        label: const Text('Test OpenVPN'),
                        onPressed: ovpnConfigs.isEmpty
                            ? null
                            : () async {
                                final res = await engine
                                    .testProtocolConfig(ovpnConfigs.first);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(res)));
                                }
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 4. Iranian Payment Gateways
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Iranian Payment Gateways (درگاه پرداخت ایرانی)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<IranianGateway>(
                    value: _selectedGateway,
                    decoration: const InputDecoration(
                      labelText: 'Select Gateway',
                      border: OutlineInputBorder(),
                    ),
                    items: IranianGateway.values
                        .map((g) => DropdownMenuItem(
                              value: g,
                              child: Text(
                                  PaymentGatewayConfig(gateway: g).label),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedGateway = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _merchantCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Merchant ID / API Key / شماره کارت بلوبانک',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Payment Gateway'),
                    value: _gwEnabled,
                    onChanged: (v) => setState(() => _gwEnabled = v),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () {
                        engine.saveGatewayConfig(PaymentGatewayConfig(
                          gateway: _selectedGateway,
                          enabled: _gwEnabled,
                          merchantOrCard: _merchantCtrl.text.trim(),
                        ));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Payment gateway settings saved!')),
                        );
                      },
                      child: const Text('Save Gateway'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddPlanDialog(BuildContext context, VpnEngineService engine) {
    final titleCtrl = TextEditingController();
    final gbCtrl = TextEditingController(text: '20');
    final daysCtrl = TextEditingController(text: '30');
    final priceCtrl = TextEditingController(text: '80000');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DragonColors.charcoal,
        title: const Text('افزودن پکیج حجم و قیمت'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'نام پکیج')),
              const SizedBox(height: 8),
              TextField(
                  controller: gbCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'حجم (GB)')),
              const SizedBox(height: 8),
              TextField(
                  controller: daysCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'مدت (روز)')),
              const SizedBox(height: 8),
              TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'قیمت (تومان)')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
          ElevatedButton(
            onPressed: () async {
              await engine.addPlan(VpnPlan(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                title: titleCtrl.text.trim().isEmpty
                    ? 'پکیج ویژه'
                    : titleCtrl.text.trim(),
                volumeGb: double.tryParse(gbCtrl.text) ?? 20,
                durationDays: int.tryParse(daysCtrl.text) ?? 30,
                priceTomans: int.tryParse(priceCtrl.text) ?? 80000,
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('ذخیره پکیج'),
          ),
        ],
      ),
    );
  }

  void _showAddPanelDialog(BuildContext context, VpnEngineService engine) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    PanelType type = PanelType.threeXUi;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: DragonColors.charcoal,
          title: const Text('Connect New Panel'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<PanelType>(
                  value: type,
                  items: PanelType.values
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(PanelProfile(
                                    id: '',
                                    name: '',
                                    type: t,
                                    baseUrl: '',
                                    username: '',
                                    password: '')
                                .typeLabel),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setSt(() => type = v);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Panel Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                      labelText: 'URL (e.g. https://panel.domain.com:2053)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await engine.addPanel(PanelProfile(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  name: nameCtrl.text.trim().isEmpty
                      ? 'Main Panel'
                      : nameCtrl.text.trim(),
                  type: type,
                  baseUrl: urlCtrl.text.trim(),
                  username: userCtrl.text.trim(),
                  password: passCtrl.text.trim(),
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Add Panel'),
            ),
          ],
        ),
      ),
    );
  }
}
