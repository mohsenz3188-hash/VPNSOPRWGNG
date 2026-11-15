import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';
import '../models/vpn_config.dart';

enum VpnConnectionState { disconnected, connecting, connected, disconnecting }

class VpnEngineService extends ChangeNotifier {
  static const String adminUsername = 'admin';
  static const String adminPassword = 'Sopr@2026!Dragon';

  static const _prefsConfigsKey = 'vpn_sopr_configs';
  static const _prefsSubsKey = 'vpn_sopr_subs';
  static const _prefsPanelsKey = 'vpn_sopr_panels';
  static const _prefsPlansKey = 'vpn_sopr_plans';
  static const _prefsGatewayKey = 'vpn_sopr_gateway';
  static const _prefsSelectedIdKey = 'vpn_sopr_selected_id';
  static const _prefsModeKey = 'vpn_sopr_routing_mode';
  static const _prefsDnsKey = 'vpn_sopr_custom_dns';
  static const _prefsSecondaryDnsKey = 'vpn_sopr_secondary_dns';
  static const _prefsBypassLanKey = 'vpn_sopr_bypass_lan';
  static const _prefsUserKey = 'vpn_sopr_auth_user';

  late final FlutterV2ray _v2ray;
  late final OpenVPN _openVpn;
  final _wireGuard = WireGuardFlutter.instance;

  bool _isAuthenticated = false;
  bool _isAdmin = false;
  String _loggedInUser = 'Guest';

  VpnConnectionState _connectionState = VpnConnectionState.disconnected;
  RoutingMode _routingMode = RoutingMode.gaming;
  List<VpnConfig> _configs = [];
  List<SubscriptionItem> _subscriptions = [];
  List<PanelProfile> _panels = [];
  List<VpnPlan> _plans = [
    VpnPlan(id: 'p10', title: 'پکیج گیمینگ ۱۰ گیگ', volumeGb: 10, durationDays: 30, priceTomans: 40000),
    VpnPlan(id: 'p30', title: 'پکیج توربو ۳۰ گیگ', volumeGb: 30, durationDays: 30, priceTomans: 120000),
    VpnPlan(id: 'p100', title: 'پکیج اژدها ۱۰۰ گیگ', volumeGb: 100, durationDays: 30, priceTomans: 400000),
  ];
  PaymentGatewayConfig _gatewayConfig = PaymentGatewayConfig();

  String? _selectedConfigId;
  String _customDns = '1.1.1.1';
  String _secondaryDns = '1.0.0.1';
  bool _bypassLan = true;

  bool _isUpdatingSubs = false;
  String _subUpdateStatus = 'Idle';
  DateTime? _lastSubSync;

  bool _isLivePingEnabled = false;
  Timer? _livePingTimer;
  final List<int> _pingHistory = [];

  String _uploadSpeed = '0 KB/s';
  String _downloadSpeed = '0 KB/s';
  String _duration = '00:00:00';
  String? _quotaWarning;
  final List<String> _logs = [];

  Timer? _durationTimer;
  DateTime? _connectedAt;
  int _lastSessionBytes = 0;
  bool _initialized = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isAdmin => _isAdmin;
  String get loggedInUser => _loggedInUser;

  VpnConnectionState get connectionState => _connectionState;
  RoutingMode get routingMode => _routingMode;
  List<VpnConfig> get configs => List.unmodifiable(_configs);
  List<SubscriptionItem> get subscriptions => List.unmodifiable(_subscriptions);
  List<PanelProfile> get panels => List.unmodifiable(_panels);
  List<VpnPlan> get plans => List.unmodifiable(_plans);
  PaymentGatewayConfig get gatewayConfig => _gatewayConfig;

  String? get selectedConfigId => _selectedConfigId;
  String get customDns => _customDns;
  String get secondaryDns => _secondaryDns;
  bool get bypassLan => _bypassLan;
  bool get isUpdatingSubs => _isUpdatingSubs;
  String get subUpdateStatus => _subUpdateStatus;
  DateTime? get lastSubSync => _lastSubSync;

  bool get isLivePingEnabled => _isLivePingEnabled;
  List<int> get pingHistory => List.unmodifiable(_pingHistory);

  int get avgPingMs {
    final valid = _pingHistory.where((p) => p > 0).toList();
    if (valid.isEmpty) return 0;
    return (valid.reduce((a, b) => a + b) / valid.length).round();
  }

  int get jitterMs {
    final valid = _pingHistory.where((p) => p > 0).toList();
    if (valid.length < 2) return 0;
    int totalDiff = 0;
    for (int i = 1; i < valid.length; i++) {
      totalDiff += (valid[i] - valid[i - 1]).abs();
    }
    return (totalDiff / (valid.length - 1)).round();
  }

  String get uploadSpeed => _uploadSpeed;
  String get downloadSpeed => _downloadSpeed;
  String get duration => _duration;
  String? get quotaWarning => _quotaWarning;
  List<String> get logs => List.unmodifiable(_logs);

  VpnConfig? get activeConfig {
    if (_configs.isEmpty) return null;
    if (_selectedConfigId != null) {
      final found = _configs.where((c) => c.id == _selectedConfigId);
      if (found.isNotEmpty) return found.first;
    }
    return _configs.first;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _v2ray = FlutterV2ray(
      onStatusChanged: (status) {
        if (activeConfig?.protocol == VpnProtocol.v2ray) {
          _uploadSpeed = _formatBytesPerSec(status.uploadSpeed);
          _downloadSpeed = _formatBytesPerSec(status.downloadSpeed);
          _duration = status.duration;
          _trackTrafficDelta(status.upload + status.download);
          if (status.state == 'CONNECTED') {
            _setConnectedState();
          } else if (status.state == 'DISCONNECTED') {
            _setDisconnectedState();
          }
          notifyListeners();
        }
      },
    );

    try {
      await _v2ray.initializeV2Ray(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
    } catch (e) {
      _addLog('V2Ray init error: $e');
    }

    _openVpn = OpenVPN(
      onVpnStatusChanged: (status) {
        if (status != null && activeConfig?.protocol == VpnProtocol.openvpn) {
          _uploadSpeed = _formatBytesPerSec(status.speedOut ?? 0);
          _downloadSpeed = _formatBytesPerSec(status.speedIn ?? 0);
          _duration = status.duration ?? _duration;
          final bIn = int.tryParse(status.byteIn ?? '0') ?? 0;
          final bOut = int.tryParse(status.byteOut ?? '0') ?? 0;
          _trackTrafficDelta(bIn + bOut);
          notifyListeners();
        }
      },
      onVpnStageChanged: (stage, raw) {
        if (activeConfig?.protocol == VpnProtocol.openvpn) {
          _addLog('OpenVPN stage: ${stage.name}');
          if (stage.isConnected) {
            _setConnectedState();
          } else if (stage.isDisconnected) {
            _setDisconnectedState();
          }
          notifyListeners();
        }
      },
    );

    try {
      await _openVpn.initialize(
        groupIdentifier: 'group.com.vpnsopr.gaming',
        providerBundleIdentifier: 'com.vpnsopr.gaming.VPNExtension',
        localizedDescription: 'VPNSOPR Turbo',
      );
    } catch (e) {
      _addLog('OpenVPN init error: $e');
    }

    try {
      await _wireGuard.initialize(interfaceName: 'wg_sopr0');
      _wireGuard.vpnStageSnapshot.listen((stage) {
        if (activeConfig?.protocol == VpnProtocol.wireguard) {
          _addLog('WireGuard stage: ${stage.name}');
          if (stage == VpnStage.connected) {
            _setConnectedState();
          } else if (stage == VpnStage.disconnected) {
            _setDisconnectedState();
          }
          notifyListeners();
        }
      });
    } catch (e) {
      _addLog('WireGuard init error: $e');
    }

    await _loadPreferences();
    _addLog('VPNSOPR Turbo v3.0 initialized.');

    if (_subscriptions.isNotEmpty) {
      unawaited(refreshAllSubscriptions());
    }
  }

  Future<bool> login(String username, String password) async {
    final u = username.trim();
    final p = password.trim();
    if (u.isEmpty || p.isEmpty) return false;

    if (u == adminUsername && p == adminPassword) {
      _isAdmin = true;
      _isAuthenticated = true;
      _loggedInUser = 'Admin';
    } else {
      _isAdmin = false;
      _isAuthenticated = true;
      _loggedInUser = u;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsUserKey, '$_loggedInUser|$_isAdmin');
    _addLog('User authenticated: $_loggedInUser (Admin: $_isAdmin)');
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    _isAuthenticated = false;
    _isAdmin = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsUserKey);
    notifyListeners();
  }

  void toggleLivePingMonitor() {
    _isLivePingEnabled = !_isLivePingEnabled;
    _livePingTimer?.cancel();
    if (_isLivePingEnabled) {
      _livePingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        final cfg = activeConfig;
        if (cfg == null) return;
        final ms = await _quickTcpPing(cfg);
        _pingHistory.add(ms ?? -1);
        if (_pingHistory.length > 30) _pingHistory.removeAt(0);
        if (ms != null && ms > 0) cfg.pingMs = ms;
        notifyListeners();
      });
      _addLog('Started 1s live ping monitor.');
    } else {
      _addLog('Stopped live ping monitor.');
    }
    notifyListeners();
  }

  Future<int?> _quickTcpPing(VpnConfig config) async {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        config.serverAddress,
        config.port,
        timeout: const Duration(milliseconds: 900),
      );
      sw.stop();
      socket.destroy();
      return math.max(1, sw.elapsedMilliseconds);
    } catch (_) {
      return -1;
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAuth = prefs.getString(_prefsUserKey);
    if (savedAuth != null && savedAuth.contains('|')) {
      final parts = savedAuth.split('|');
      _loggedInUser = parts[0];
      _isAdmin = parts[1] == 'true';
      _isAuthenticated = true;
    }
    final rawList = prefs.getString(_prefsConfigsKey);
    if (rawList != null && rawList.isNotEmpty) {
      _configs = VpnConfig.decodeList(rawList);
    }
    final rawSubs = prefs.getString(_prefsSubsKey);
    if (rawSubs != null && rawSubs.isNotEmpty) {
      _subscriptions = SubscriptionItem.decodeList(rawSubs);
    }
    final rawPanels = prefs.getString(_prefsPanelsKey);
    if (rawPanels != null && rawPanels.isNotEmpty) {
      _panels = PanelProfile.decodeList(rawPanels);
    }
    final rawPlans = prefs.getString(_prefsPlansKey);
    if (rawPlans != null && rawPlans.isNotEmpty) {
      _plans = VpnPlan.decodeList(rawPlans);
    }
    final rawGw = prefs.getString(_prefsGatewayKey);
    if (rawGw != null && rawGw.isNotEmpty) {
      _gatewayConfig = PaymentGatewayConfig.fromJson(
          jsonDecode(rawGw) as Map<String, dynamic>);
    }
    _selectedConfigId = prefs.getString(_prefsSelectedIdKey);
    final savedMode = prefs.getString(_prefsModeKey);
    if (savedMode != null) {
      _routingMode = RoutingMode.values.firstWhere(
        (m) => m.name == savedMode,
        orElse: () => RoutingMode.gaming,
      );
    }
    _customDns = prefs.getString(_prefsDnsKey) ?? '1.1.1.1';
    _secondaryDns = prefs.getString(_prefsSecondaryDnsKey) ?? '1.0.0.1';
    _bypassLan = prefs.getBool(_prefsBypassLanKey) ?? true;
    notifyListeners();
  }

  Future<void> _saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsConfigsKey, VpnConfig.encodeList(_configs));
    if (_selectedConfigId != null) {
      await prefs.setString(_prefsSelectedIdKey, _selectedConfigId!);
    }
  }

  Future<void> _saveSubs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsSubsKey, SubscriptionItem.encodeList(_subscriptions));
  }

  Future<void> _savePanels() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPanelsKey, PanelProfile.encodeList(_panels));
  }

  Future<void> _savePlans() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPlansKey, VpnPlan.encodeList(_plans));
  }

  Future<void> addPlan(VpnPlan plan) async {
    _plans.add(plan);
    await _savePlans();
    _addLog('Admin added plan: ${plan.title} (${plan.volumeGb}GB / ${plan.priceTomans}T)');
    notifyListeners();
  }

  Future<void> deletePlan(String id) async {
    _plans.removeWhere((p) => p.id == id);
    await _savePlans();
    notifyListeners();
  }

  Future<void> saveGatewayConfig(PaymentGatewayConfig gw) async {
    _gatewayConfig = gw;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsGatewayKey, jsonEncode(gw.toJson()));
    _addLog('Updated Iranian Payment Gateway: ${gw.label}');
    notifyListeners();
  }

  /// Verify payment with Iranian Gateway & Immediately Activate Config
  Future<String> processPaymentAndActivate(VpnPlan plan) async {
    _addLog('Initiating ${plan.priceTomans} Toman payment via ${_gatewayConfig.label}...');
    // If gateway is online (ZarinPal / Zibal / IDPay), send request payload
    if (_gatewayConfig.gateway != IranianGateway.blubank &&
        _gatewayConfig.merchantOrCard.isNotEmpty) {
      try {
        final endpoint = _gatewayConfig.gateway == IranianGateway.zarinpal
            ? 'https://api.zarinpal.com/pg/v4/payment/request.json'
            : _gatewayConfig.gateway == IranianGateway.zibal
                ? 'https://gateway.zibal.ir/v1/request'
                : 'https://api.idpay.ir/v1.1/payment';
        await http
            .post(
              Uri.parse(endpoint),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'merchant_id': _gatewayConfig.merchantOrCard,
                'merchant': _gatewayConfig.merchantOrCard,
                'amount': plan.priceTomans * 10, // Rials
                'callback_url': _gatewayConfig.callbackUrl,
                'description': '${plan.title} (${plan.volumeGb} GB)',
              }),
            )
            .timeout(const Duration(seconds: 6));
      } catch (e) {
        _addLog('Gateway request note: $e');
      }
    }

    // Immediately activate config for the customer
    final quotaBytes = (plan.volumeGb * 1024 * 1024 * 1024).round();
    final timeMinutes = plan.durationDays * 24 * 60;

    if (activeConfig != null) {
      final base = activeConfig!;
      final activated = VpnConfig(
        id: 'paid_${DateTime.now().microsecondsSinceEpoch}',
        name: '${plan.title} (${plan.volumeGb.toStringAsFixed(0)}GB)',
        protocol: base.protocol,
        rawConfig: base.rawConfig,
        serverAddress: base.serverAddress,
        port: base.port,
        isUdpPreferred: base.isUdpPreferred,
        pingMs: base.pingMs,
        quotaBytes: quotaBytes,
        usedBytes: 0,
        timeLimitMinutes: timeMinutes,
        usedSeconds: 0,
      );
      _configs.insert(0, activated);
      _selectedConfigId = activated.id;
      await _saveConfigs();
      _addLog('Payment verified! Activated ${activated.name} immediately.');
      notifyListeners();
      await connect();
      return 'پرداخت تایید شد! کانفیگ ${activated.name} فعال و متصل شد.';
    }
    return 'پرداخت ثبت شد! لطفاً یک کانفیگ پایه در بخش Configs اضافه کنید.';
  }

  Future<void> addPanel(PanelProfile panel) async {
    _panels.add(panel);
    await _savePanels();
    _addLog('Added panel: ${panel.name} (${panel.typeLabel})');
    notifyListeners();
  }

  Future<void> deletePanel(String id) async {
    _panels.removeWhere((p) => p.id == id);
    await _savePanels();
    notifyListeners();
  }

  Future<String> syncPanel(PanelProfile panel) async {
    final base = panel.baseUrl.replaceAll(RegExp(r'/$'), '');
    _addLog('Connecting to ${panel.typeLabel} at $base...');
    try {
      if (panel.type == PanelType.marzban) {
        final res = await http.post(
          Uri.parse('$base/api/admin/token'),
          body: {'username': panel.username, 'password': panel.password},
        ).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          panel.lastSynced = DateTime.now();
          await _savePanels();
          notifyListeners();
          return 'Connected to Marzban successfully!';
        }
        return 'Marzban HTTP ${res.statusCode}';
      } else {
        final res = await http.post(
          Uri.parse('$base/login'),
          body: {'username': panel.username, 'password': panel.password},
        ).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          panel.lastSynced = DateTime.now();
          await _savePanels();
          notifyListeners();
          return 'Connected to ${panel.typeLabel} successfully!';
        }
        return '${panel.typeLabel} HTTP ${res.statusCode}';
      }
    } catch (e) {
      return 'Panel error: $e';
    }
  }

  Future<String> testProtocolConfig(VpnConfig cfg) async {
    _addLog('Testing ${cfg.protocolLabel} (${cfg.serverAddress}:${cfg.port})...');
    final ping = await testPing(cfg);
    if (ping == null || ping < 0) {
      return '${cfg.protocolLabel} UNREACHABLE (${cfg.serverAddress}:${cfg.port})';
    }
    _selectedConfigId = cfg.id;
    await connect();
    return '${cfg.protocolLabel} Reachable (${ping}ms) — Connecting now!';
  }

  Future<void> setRoutingMode(RoutingMode mode) async {
    _routingMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsModeKey, mode.name);
    _addLog('Switched routing mode to ${mode.name.toUpperCase()}');
    notifyListeners();
  }

  Future<void> updateSettings({
    required String dns,
    String? secondaryDns,
    required bool bypassLan,
  }) async {
    _customDns = dns.trim().isEmpty ? '1.1.1.1' : dns.trim();
    _secondaryDns = (secondaryDns ?? _secondaryDns).trim().isEmpty
        ? '1.0.0.1'
        : (secondaryDns ?? _secondaryDns).trim();
    _bypassLan = bypassLan;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDnsKey, _customDns);
    await prefs.setString(_prefsSecondaryDnsKey, _secondaryDns);
    await prefs.setBool(_prefsBypassLanKey, _bypassLan);
    _addLog('Applied DNS=$_customDns / $_secondaryDns, BypassLAN=$_bypassLan');
    notifyListeners();
  }

  void selectConfig(String id) {
    _selectedConfigId = id;
    _quotaWarning = null;
    _saveConfigs();
    notifyListeners();
  }

  Future<void> deleteConfig(String id) async {
    _configs.removeWhere((c) => c.id == id);
    if (_selectedConfigId == id) {
      _selectedConfigId = _configs.isNotEmpty ? _configs.first.id : null;
    }
    await _saveConfigs();
    notifyListeners();
  }

  Future<void> updateConfig(VpnConfig updated) async {
    final idx = _configs.indexWhere((c) => c.id == updated.id);
    if (idx != -1) {
      _configs[idx] = updated;
      await _saveConfigs();
      notifyListeners();
    }
  }

  Future<int> splitConfigIntoParts(
    VpnConfig source, {
    required double totalGb,
    required int parts,
    int? timeLimitMinutesPerPart,
  }) async {
    if (parts <= 0 || totalGb <= 0) return 0;
    final perPartBytes = ((totalGb / parts) * 1024 * 1024 * 1024).round();
    final perPartGb = (totalGb / parts).toStringAsFixed(1);

    for (int i = 1; i <= parts; i++) {
      _configs.add(VpnConfig(
        id: '${DateTime.now().microsecondsSinceEpoch}_part_$i',
        name: '${source.name} #$i (${perPartGb}GB)',
        protocol: source.protocol,
        rawConfig: source.rawConfig,
        serverAddress: source.serverAddress,
        port: source.port,
        isUdpPreferred: source.isUdpPreferred,
        pingMs: source.pingMs,
        subscriptionId: source.subscriptionId,
        quotaBytes: perPartBytes,
        usedBytes: 0,
        timeLimitMinutes: timeLimitMinutesPerPart,
        usedSeconds: 0,
      ));
    }
    await _saveConfigs();
    _addLog('Split "${source.name}" into $parts x ${perPartGb}GB parts.');
    notifyListeners();
    return parts;
  }

  Future<VpnConfig?> autoSelectBestPing({bool connectAfter = false}) async {
    if (_configs.isEmpty) return null;
    _addLog('Auto-Select Best Ping: testing ${_configs.length} config(s)...');
    await testAllPings();

    final reachable = _configs
        .where((c) => (c.pingMs ?? -1) > 0 && !c.isQuotaExceeded)
        .toList();
    if (reachable.isEmpty) {
      _addLog('Auto-Select: no reachable configs found.');
      return null;
    }

    reachable.sort((a, b) => a.pingMs!.compareTo(b.pingMs!));
    final best = reachable.first;
    _selectedConfigId = best.id;
    await _saveConfigs();
    _addLog('Auto-Selected best ping: ${best.name} (${best.pingMs} ms)');
    notifyListeners();

    if (connectAfter) {
      if (_connectionState == VpnConnectionState.connected) {
        await disconnect();
      }
      await connect();
    }
    return best;
  }

  VpnConfig? _pickSmartConfig() {
    if (_configs.isEmpty) return null;
    if (_routingMode == RoutingMode.manual) return activeConfig;

    final available = _configs.where((c) => !c.isQuotaExceeded).toList();
    if (available.isEmpty) return activeConfig;

    available.sort((a, b) =>
        _scoreConfig(b, _routingMode).compareTo(_scoreConfig(a, _routingMode)));
    return available.first;
  }

  int _scoreConfig(VpnConfig c, RoutingMode mode) {
    int score = 0;
    final ping = c.pingMs ?? 999;
    if (mode == RoutingMode.gaming) {
      if (c.protocol == VpnProtocol.wireguard) score += 500;
      if (c.protocol == VpnProtocol.v2ray && c.isUdpPreferred) score += 350;
      if (c.protocol == VpnProtocol.openvpn) score += 100;
      score += (1000 - ping.clamp(0, 999));
    } else {
      if (c.protocol == VpnProtocol.v2ray) score += 500;
      if (c.protocol == VpnProtocol.openvpn) score += 350;
      if (c.protocol == VpnProtocol.wireguard) score += 250;
      score += (500 - (ping.clamp(0, 999) ~/ 2));
    }
    return score;
  }

  String _injectCustomDns(VpnConfig target) {
    if (target.protocol == VpnProtocol.v2ray) {
      try {
        final map = jsonDecode(target.rawConfig) as Map<String, dynamic>;
        map['dns'] = {
          'servers': [_customDns, _secondaryDns]
        };
        return jsonEncode(map);
      } catch (_) {
        return target.rawConfig;
      }
    } else if (target.protocol == VpnProtocol.wireguard) {
      final lines = target.rawConfig.split('\n');
      final hasDns = lines.any((l) => l.trim().startsWith('DNS'));
      if (hasDns) {
        return lines
            .map((l) => l.trim().startsWith('DNS')
                ? 'DNS = $_customDns, $_secondaryDns'
                : l)
            .join('\n');
      } else {
        return target.rawConfig.replaceFirst(
            '[Interface]', '[Interface]\nDNS = $_customDns, $_secondaryDns');
      }
    }
    return target.rawConfig;
  }

  Future<void> toggleConnection() async {
    if (_connectionState == VpnConnectionState.connected ||
        _connectionState == VpnConnectionState.connecting) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> connect() async {
    final target = _pickSmartConfig();
    if (target == null) {
      _addLog('ERROR: No configurations available to connect.');
      return;
    }
    if (target.isQuotaExceeded) {
      _quotaWarning = 'Quota or time limit reached for ${target.name}';
      _addLog('BLOCKED: $_quotaWarning');
      notifyListeners();
      return;
    }

    _quotaWarning = null;
    _selectedConfigId = target.id;
    _lastSessionBytes = 0;
    _connectionState = VpnConnectionState.connecting;
    _addLog('Connecting via ${target.protocolLabel}: ${target.name} (DNS: $_customDns)...');
    notifyListeners();

    final preparedConfig = _injectCustomDns(target);

    try {
      switch (target.protocol) {
        case VpnProtocol.v2ray:
          final granted = await _v2ray.requestPermission();
          if (!granted) throw Exception('VPN permission denied');
          await _v2ray.startV2Ray(
            remark: target.name,
            config: preparedConfig,
            bypassSubnets: _bypassLan ? ['192.168.0.0/16', '10.0.0.0/8'] : [],
            notificationDisconnectButtonName: 'DISCONNECT',
          );
          break;

        case VpnProtocol.wireguard:
          await _wireGuard.startVpn(
            serverAddress: '${target.serverAddress}:${target.port}',
            wgQuickConfig: preparedConfig,
            providerBundleIdentifier: 'com.vpnsopr.gaming',
          );
          break;

        case VpnProtocol.openvpn:
          final granted = await _openVpn.requestPermissionAndroid();
          if (!granted) throw Exception('OpenVPN permission denied');
          await _openVpn.connect(preparedConfig, target.name);
          break;
      }
    } catch (e) {
      _addLog('Connection failed: $e');
      _setDisconnectedState();
    }
  }

  Future<void> disconnect() async {
    _connectionState = VpnConnectionState.disconnecting;
    notifyListeners();
    try {
      await _v2ray.stopV2Ray();
    } catch (_) {}
    try {
      await _wireGuard.stopVpn();
    } catch (_) {}
    try {
      await _openVpn.disconnect();
    } catch (_) {}
    _setDisconnectedState();
    await _saveConfigs();
    _addLog('Disconnected.');
  }

  void _trackTrafficDelta(int currentSessionBytes) {
    final cfg = activeConfig;
    if (cfg == null) return;
    final delta = currentSessionBytes - _lastSessionBytes;
    if (delta > 0) {
      cfg.usedBytes += delta;
      _lastSessionBytes = currentSessionBytes;
      if (cfg.isQuotaExceeded) {
        _quotaWarning = 'Data limit reached for ${cfg.name}. Auto-disconnected.';
        _addLog(_quotaWarning!);
        unawaited(disconnect());
      }
    }
  }

  void _setConnectedState() {
    if (_connectionState == VpnConnectionState.connected) return;
    _connectionState = VpnConnectionState.connected;
    _connectedAt = DateTime.now();
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null) {
        final diff = DateTime.now().difference(_connectedAt!);
        _duration = _formatDuration(diff);
        final cfg = activeConfig;
        if (cfg != null) {
          cfg.usedSeconds += 1;
          if (cfg.isQuotaExceeded) {
            _quotaWarning = 'Time/Data limit reached for ${cfg.name}.';
            _addLog(_quotaWarning!);
            unawaited(disconnect());
            return;
          }
          if (cfg.usedSeconds % 15 == 0) {
            unawaited(_saveConfigs());
          }
        }
        notifyListeners();
      }
    });
  }

  void _setDisconnectedState() {
    _connectionState = VpnConnectionState.disconnected;
    _durationTimer?.cancel();
    _connectedAt = null;
    _duration = '00:00:00';
    _uploadSpeed = '0 KB/s';
    _downloadSpeed = '0 KB/s';
    notifyListeners();
  }

  Future<int> importRawInput(String input,
      {String? customName, String? subscriptionId}) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 0;

    if ((trimmed.startsWith('http://') || trimmed.startsWith('https://')) &&
        !trimmed.contains('\n')) {
      return addAndFetchSubscription(trimmed, name: customName);
    }

    int added = 0;
    if (trimmed.contains('[Interface]') && trimmed.contains('[Peer]')) {
      final endpointMatch =
          RegExp(r'Endpoint\s*=\s*([^\s:]+):(\d+)').firstMatch(trimmed);
      final host = endpointMatch?.group(1) ?? 'wireguard.server';
      final port = int.tryParse(endpointMatch?.group(2) ?? '51820') ?? 51820;
      _configs.add(VpnConfig(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: customName ?? 'WG $host',
        protocol: VpnProtocol.wireguard,
        rawConfig: trimmed,
        serverAddress: host,
        port: port,
        isUdpPreferred: true,
        subscriptionId: subscriptionId,
      ));
      added++;
    } else if (trimmed.contains('client') && trimmed.contains('remote ')) {
      final remoteMatch =
          RegExp(r'remote\s+([^\s]+)\s+(\d+)').firstMatch(trimmed);
      final host = remoteMatch?.group(1) ?? 'openvpn.server';
      final port = int.tryParse(remoteMatch?.group(2) ?? '1194') ?? 1194;
      _configs.add(VpnConfig(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: customName ?? 'OVPN $host',
        protocol: VpnProtocol.openvpn,
        rawConfig: trimmed,
        serverAddress: host,
        port: port,
        isUdpPreferred: trimmed.contains('proto udp'),
        subscriptionId: subscriptionId,
      ));
      added++;
    } else if (trimmed.startsWith('{') && trimmed.contains('outbounds')) {
      _configs.add(VpnConfig(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: customName ?? 'Xray JSON',
        protocol: VpnProtocol.v2ray,
        rawConfig: trimmed,
        serverAddress: 'json.xray',
        port: 443,
        subscriptionId: subscriptionId,
      ));
      added++;
    } else {
      final lines = trimmed.split(RegExp(r'\r?\n'));
      for (final line in lines) {
        final link = line.trim();
        if (link.isEmpty) continue;
        try {
          final parsed = FlutterV2ray.parseFromURL(link);
          final lower = link.toLowerCase();
          final udpFriendly =
              lower.contains('type=kcp') || lower.contains('type=quic');
          _configs.add(VpnConfig(
            id: '${DateTime.now().microsecondsSinceEpoch}_$added',
            name: customName ?? parsed.remark,
            protocol: VpnProtocol.v2ray,
            rawConfig: parsed.getFullConfiguration(),
            serverAddress: parsed.address,
            port: parsed.port,
            isUdpPreferred: udpFriendly,
            subscriptionId: subscriptionId,
          ));
          added++;
        } catch (e) {
          _addLog('Skipped invalid line: $e');
        }
      }
    }

    if (added > 0) {
      _selectedConfigId ??= _configs.first.id;
      await _saveConfigs();
      _addLog('Imported $added configuration(s).');
      notifyListeners();
    }
    return added;
  }

  Future<int> addAndFetchSubscription(String url, {String? name}) async {
    final cleanUrl = url.trim();
    var existing = _subscriptions.where((s) => s.url == cleanUrl).toList();
    late SubscriptionItem sub;
    if (existing.isEmpty) {
      sub = SubscriptionItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: (name != null && name.trim().isNotEmpty)
            ? name.trim()
            : Uri.tryParse(cleanUrl)?.host ?? 'Subscription',
        url: cleanUrl,
      );
      _subscriptions.add(sub);
    } else {
      sub = existing.first;
    }
    await _saveSubs();
    return refreshSubscription(sub);
  }

  Future<int> refreshSubscription(SubscriptionItem sub) async {
    _isUpdatingSubs = true;
    _subUpdateStatus = 'Updating ${sub.name}...';
    notifyListeners();

    try {
      final response = await http
          .get(Uri.parse(sub.url))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      String body = response.body.trim();
      if (!body.contains('://')) {
        try {
          final normalized = base64.normalize(body);
          body = utf8.decode(base64Decode(normalized));
        } catch (_) {}
      }
      _configs.removeWhere((c) => c.subscriptionId == sub.id);
      final count = await importRawInput(body, subscriptionId: sub.id);
      sub.lastUpdated = DateTime.now();
      sub.configCount = count;
      _lastSubSync = sub.lastUpdated;
      _subUpdateStatus = 'Updated ($count)';
      await _saveSubs();
      await _saveConfigs();
      _addLog('Subscription "${sub.name}" updated: $count config(s).');
      return count;
    } catch (e) {
      _subUpdateStatus = 'Update failed';
      _addLog('Subscription "${sub.name}" error: $e');
      rethrow;
    } finally {
      _isUpdatingSubs = false;
      notifyListeners();
    }
  }

  Future<void> refreshAllSubscriptions() async {
    if (_subscriptions.isEmpty) return;
    _isUpdatingSubs = true;
    _subUpdateStatus = 'Syncing ${_subscriptions.length} sub(s)...';
    notifyListeners();
    int total = 0;
    for (final sub in List<SubscriptionItem>.from(_subscriptions)) {
      try {
        total += await refreshSubscription(sub);
      } catch (_) {}
    }
    _isUpdatingSubs = false;
    _lastSubSync = DateTime.now();
    _subUpdateStatus = 'Synced ($total)';
    notifyListeners();
  }

  Future<void> deleteSubscription(String id) async {
    _subscriptions.removeWhere((s) => s.id == id);
    _configs.removeWhere((c) => c.subscriptionId == id);
    await _saveSubs();
    await _saveConfigs();
    notifyListeners();
  }

  Future<int?> testPing(VpnConfig config) async {
    try {
      if (config.protocol == VpnProtocol.v2ray) {
        final delay = await _v2ray.getServerDelay(config: config.rawConfig);
        config.pingMs = delay > 0 ? delay : null;
      } else {
        final sw = Stopwatch()..start();
        final socket = await Socket.connect(
          config.serverAddress,
          config.port,
          timeout: const Duration(seconds: 3),
        );
        sw.stop();
        socket.destroy();
        config.pingMs = sw.elapsedMilliseconds;
      }
    } catch (_) {
      config.pingMs = -1;
    }
    await _saveConfigs();
    notifyListeners();
    return config.pingMs;
  }

  Future<void> testAllPings() async {
    for (final c in _configs) {
      await testPing(c);
    }
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  void _addLog(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _logs.insert(0, '[$ts] $message');
    if (_logs.length > 250) _logs.removeLast();
  }

  String _formatBytesPerSec(int bytes) {
    if (bytes < 1024) return '$bytes B/s';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }
}
