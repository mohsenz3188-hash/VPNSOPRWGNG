import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/vpn_config.dart';
import '../services/vpn_engine_service.dart';
import '../theme/dragon_theme.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  double _customGb = 20;
  int _customDays = 30;
  bool _processing = false;

  Future<void> _buyPlan(VpnEngineService engine, VpnPlan plan) async {
    setState(() => _processing = true);
    try {
      final msg = await engine.processPaymentAndActivate(plan);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<VpnEngineService>();
    final gw = engine.gatewayConfig;
    final plans = engine.plans;
    final customPrice = (_customGb * gw.pricePerGbTomans).round();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('فروشگاه و خرید حجم',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Gateway Info Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      color: DragonColors.electricBlue, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('درگاه فعال: ${gw.label}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          gw.merchantOrCard.isEmpty
                              ? 'توسط ادمین قابل تنظیم در پنل Admin'
                              : gw.merchantOrCard,
                          style: const TextStyle(
                              fontSize: 12, color: DragonColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (gw.merchantOrCard.isNotEmpty)
                    IconButton(
                      tooltip: 'کپی',
                      icon: const Icon(Icons.copy_rounded,
                          color: DragonColors.electricBlue, size: 20),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: gw.merchantOrCard));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('شماره کارت / لینک کپی شد')),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Custom Volume Picker Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('انتخاب حجم دلخواه (سفارشی)',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${_customGb.round()} گیگابایت',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: DragonColors.electricBlue)),
                      Text('$customPrice تومان',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: DragonColors.crimsonRed)),
                    ],
                  ),
                  Slider(
                    value: _customGb,
                    min: 5,
                    max: 200,
                    divisions: 39,
                    activeColor: DragonColors.electricBlue,
                    onChanged: (v) => setState(() => _customGb = v),
                  ),
                  Row(
                    children: [
                      const Text('مدت اعتبار:',
                          style: TextStyle(
                              fontSize: 12, color: DragonColors.textSecondary)),
                      const SizedBox(width: 10),
                      ChoiceChip(
                        label: const Text('۳۰ روزه'),
                        selected: _customDays == 30,
                        onSelected: (_) => setState(() => _customDays = 30),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('۶۰ روزه'),
                        selected: _customDays == 60,
                        onSelected: (_) => setState(() => _customDays = 60),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DragonColors.crimsonRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: _processing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.flash_on_rounded),
                      label: Text(_processing
                          ? 'در حال فعال‌سازی...'
                          : 'خرید و فعال‌سازی فوری (${_customGb.round()} GB)'),
                      onPressed: _processing
                          ? null
                          : () => _buyPlan(
                                engine,
                                VpnPlan(
                                  id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                                  title: 'سفارشی ${_customGb.round()} گیگ',
                                  volumeGb: _customGb.roundToDouble(),
                                  durationDays: _customDays,
                                  priceTomans: customPrice,
                                ),
                              ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),
          const Text('پکیج‌های آماده',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          ...plans.map((pl) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.black26,
                    child: Icon(Icons.diamond_outlined,
                        color: DragonColors.electricBlue),
                  ),
                  title: Text('${pl.title} (${pl.volumeGb.toStringAsFixed(0)} GB)',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${pl.durationDays} روز اعتبار',
                      style: const TextStyle(
                          fontSize: 12, color: DragonColors.textSecondary)),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DragonColors.electricBlue,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _processing ? null : () => _buyPlan(engine, pl),
                    child: Text('${pl.priceTomans} T'),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
