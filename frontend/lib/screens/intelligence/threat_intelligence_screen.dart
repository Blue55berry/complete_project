import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as l2;
import 'package:provider/provider.dart';

import '../../core/models/analysis_models.dart';
import '../../core/services/api_config.dart';
import '../../core/services/threat_intelligence_provider.dart';
import 'package:video_player/video_player.dart';

class ThreatIntelligenceScreen extends StatefulWidget {
  const ThreatIntelligenceScreen({super.key});

  @override
  State<ThreatIntelligenceScreen> createState() =>
      _ThreatIntelligenceScreenState();
}

class _ThreatIntelligenceScreenState extends State<ThreatIntelligenceScreen> {
  late final ThreatIntelligenceProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<ThreatIntelligenceProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _provider.attachScreen();
    });
  }

  @override
  void dispose() {
    // Schedule detach after the current frame so we don't call
    // notifyListeners() while the widget tree is locked during unmounting.
    _provider.detachScreenSilent();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B12),
      body: SafeArea(
        child: Consumer<ThreatIntelligenceProvider>(
          builder: (context, provider, child) {
            return Column(
              children: [
                _Header(provider: provider),
                _StatusRow(provider: provider),
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    child: _WorldMapPanel(provider: provider),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: _TerminalPanel(provider: provider),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.provider});
  final ThreatIntelligenceProvider provider;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: Colors.white70,
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF26D9FF).withValues(alpha: 0.35),
              ),
              gradient: const LinearGradient(
                colors: [Color(0x2214B8A6), Color(0x1117C6FF)],
              ),
            ),
            child: const Icon(
              Icons.public_rounded,
              color: Color(0xFF26D9FF),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Intelligence Center',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Privacy-safe deepfake telemetry only',
                  style: TextStyle(
                    color: Color(0xFF7AA6C1),
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: provider.isLoading ? null : provider.refreshAll,
            icon: const Icon(Icons.refresh_rounded),
            color: const Color(0xFF26D9FF),
          ),
          IconButton(
            onPressed: () => _showInfo(context),
            icon: const Icon(Icons.info_outline_rounded),
            color: Colors.white54,
          ),
        ],
      ),
    );
  }

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0B1421),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: const Text(
          'Intelligence Scope',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This view shows aggregated deepfake telemetry only. It does not expose usernames, phone numbers, raw URLs, file names, exact coordinates, or device identifiers.',
          style: TextStyle(color: Color(0xFFB8C7D1), fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.provider});
  final ThreatIntelligenceProvider provider;

  @override
  Widget build(BuildContext context) {
    final hasData =
        provider.terminalThreats.isNotEmpty || provider.hotspots.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: _StatusChip(
              label: 'Feed',
              value: provider.isLoading
                  ? 'SYNCING'
                  : hasData
                  ? 'LIVE'
                  : 'STANDBY',
              color: provider.isLoading
                  ? Colors.orangeAccent
                  : hasData
                  ? const Color(0xFF26D9FF)
                  : Colors.greenAccent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatusChip(
              label: 'Hotspots',
              value: provider.hotspots.length.toString(),
              color: const Color(0xFF26D9FF),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: _StatusChip(
              label: 'Mode',
              value: 'DEEPFAKE',
              color: Color(0xFF14B8A6),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color.withValues(alpha: 0.75),
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorldMapPanel extends StatefulWidget {
  const _WorldMapPanel({required this.provider});
  final ThreatIntelligenceProvider provider;
  @override
  State<_WorldMapPanel> createState() => _WorldMapPanelState();
}

/// Label definition for English-only overlay markers
class _MapLabel {
  const _MapLabel(this.name, this.lat, this.lng);
  final String name;
  final double lat;
  final double lng;
}

  // ---------------------------------------------------
const List<_MapLabel> _continentLabels = [
  _MapLabel('NORTH AMERICA', 38.0,  -99.0),
  _MapLabel('SOUTH AMERICA', -14.2, -53.8),
  _MapLabel('EUROPE',         48.0,  15.3),
  _MapLabel('AFRICA',          5.5,  20.0),
  _MapLabel('ASIA',           43.0,  88.0),
  _MapLabel('AUSTRALIA',     -25.0, 134.0), // Renamed from OCEANIA per request
  _MapLabel('ANTARCTICA',    -80.0,   0.0),
];

  // ---------------------------------------------------
const List<_MapLabel> _priorityCountryLabels = [
  _MapLabel('USA',            39.50,  -98.35),
  _MapLabel('CANADA',         60.00,  -96.80),
  _MapLabel('MEXICO',         23.64, -102.55),
  _MapLabel('BRAZIL',        -14.24,  -51.93),
  _MapLabel('UK',             55.38,   -3.44),
  _MapLabel('GERMANY',        51.17,   10.45),
  _MapLabel('FRANCE',         46.23,    2.21),
  _MapLabel('RUSSIA',         61.52,  105.31),
  _MapLabel('CHINA',          35.86,  104.19),
  _MapLabel('INDIA',          21.00,   78.96),
  _MapLabel('JAPAN',          36.20,  138.25),
  _MapLabel('INDONESIA',      -0.78,  113.92),
  _MapLabel('SAUDI ARABIA',   23.88,   45.07),
  _MapLabel('SOUTH AFRICA',  -30.55,   22.93),
];

  // ---------------------------------------------------
const List<_MapLabel> _countryLabels = [
  // -- NORTH AMERICA
  _MapLabel('CUBA',           21.52,  -79.50),
  _MapLabel('JAMAICA',        18.11,  -77.30),
  _MapLabel('HAITI',          18.97,  -72.29),
  _MapLabel('DOM. REP.',      18.74,  -70.16),
  _MapLabel('BELIZE',         17.19,  -88.49),
  _MapLabel('GUATEMALA',      15.78,  -90.23),
  _MapLabel('EL SALVADOR',    13.79,  -88.90),
  _MapLabel('HONDURAS',       14.82,  -86.83),
  _MapLabel('NICARAGUA',      12.87,  -85.21),
  _MapLabel('COSTA RICA',      9.75,  -84.17),
  _MapLabel('PANAMA',          8.42,  -80.13),
  _MapLabel('TRINIDAD',       10.45,  -61.33),
  // -- SOUTH AMERICA
  _MapLabel('ARGENTINA',     -38.42,  -63.62),
  _MapLabel('COLOMBIA',        4.57,  -74.30),
  _MapLabel('VENEZUELA',       8.00,  -66.60),
  _MapLabel('PERU',           -9.19,  -75.02),
  _MapLabel('CHILE',         -35.68,  -71.54),
  _MapLabel('BOLIVIA',       -16.29,  -63.59),
  _MapLabel('ECUADOR',        -1.83,  -78.18),
  _MapLabel('PARAGUAY',      -23.44,  -58.44),
  _MapLabel('URUGUAY',       -32.52,  -55.77),
  _MapLabel('SURINAME',        3.92,  -56.02),
  _MapLabel('GUYANA',          4.86,  -58.93),
  // -- EUROPE
  _MapLabel('IRELAND',        53.41,   -8.24),
  _MapLabel('ICELAND',        64.96,  -19.02),
  _MapLabel('NORWAY',         64.56,   17.89),
  _MapLabel('SWEDEN',         60.13,   18.64),
  _MapLabel('FINLAND',        61.92,   25.75),
  _MapLabel('DENMARK',        56.26,    9.50),
  _MapLabel('NETHERLANDS',    52.13,    5.29),
  _MapLabel('BELGIUM',        50.50,    4.47),
  _MapLabel('LUXEMBOURG',     49.81,    6.13),
  _MapLabel('PORTUGAL',       39.40,   -8.22),
  _MapLabel('SPAIN',          40.46,   -3.75),
  _MapLabel('SWITZERLAND',    46.82,    8.23),
  _MapLabel('AUSTRIA',        47.52,   14.55),
  _MapLabel('ITALY',          41.87,   12.57),
  _MapLabel('MALTA',          35.94,   14.38),
  _MapLabel('POLAND',         51.92,   19.15),
  _MapLabel('CZECHIA',        49.82,   15.47),
  _MapLabel('SLOVAKIA',       48.67,   19.70),
  _MapLabel('HUNGARY',        47.16,   19.50),
  _MapLabel('UKRAINE',        48.38,   31.17),
  _MapLabel('BELARUS',        53.71,   27.95),
  _MapLabel('MOLDOVA',        47.41,   28.37),
  _MapLabel('ROMANIA',        45.94,   24.97),
  _MapLabel('BULGARIA',       42.73,   25.49),
  _MapLabel('SERBIA',         44.02,   20.91),
  _MapLabel('CROATIA',        45.10,   15.20),
  _MapLabel('BOSNIA',         44.17,   17.91),
  _MapLabel('SLOVENIA',       46.15,   14.99),
  _MapLabel('MONTENEGRO',     42.71,   19.37),
  _MapLabel('N. MACEDONIA',   41.61,   21.75),
  _MapLabel('ALBANIA',        41.15,   20.17),
  _MapLabel('KOSOVO',         42.60,   20.90),
  _MapLabel('GREECE',         39.07,   21.82),
  _MapLabel('ESTONIA',        58.60,   25.01),
  _MapLabel('LATVIA',         56.88,   24.60),
  _MapLabel('LITHUANIA',      55.17,   23.88),
  // -- AFRICA
  _MapLabel('MOROCCO',        31.79,   -5.00),
  _MapLabel('ALGERIA',        28.03,    1.66),
  _MapLabel('TUNISIA',        33.89,    9.54),
  _MapLabel('LIBYA',          26.34,   17.23),
  _MapLabel('EGYPT',          26.82,   30.80),
  _MapLabel('MAURITANIA',     20.25,  -10.94),
  _MapLabel('MALI',           17.57,   -3.99),
  _MapLabel('NIGER',          17.61,    8.08),
  _MapLabel('CHAD',           15.45,   18.73),
  _MapLabel('SUDAN',          12.86,   30.22),
  _MapLabel('SOUTH SUDAN',     6.88,   31.31),
  _MapLabel('ETHIOPIA',        9.15,   40.49),
  _MapLabel('ERITREA',        15.18,   39.78),
  _MapLabel('DJIBOUTI',       11.83,   42.59),
  _MapLabel('SOMALIA',         5.15,   46.20),
  _MapLabel('KENYA',          -0.02,   37.91),
  _MapLabel('UGANDA',          1.37,   32.29),
  _MapLabel('RWANDA',         -1.94,   29.87),
  _MapLabel('BURUNDI',        -3.37,   29.92),
  _MapLabel('SENEGAL',        14.50,  -14.45),
  _MapLabel('GAMBIA',         13.44,  -15.31),
  _MapLabel('GUINEA-BISSAU',  11.80,  -15.18),
  _MapLabel('GUINEA',         10.95,  -10.94),
  _MapLabel('SIERRA LEONE',    8.46,  -11.78),
  _MapLabel('LIBERIA',         6.43,   -9.43),
  _MapLabel('IVOIRE',          7.54,   -5.55),
  _MapLabel('GHANA',           7.95,   -1.02),
  _MapLabel('TOGO',            8.62,    0.82),
  _MapLabel('BENIN',           9.31,    2.32),
  _MapLabel('NIGERIA',         9.08,    8.68),
  _MapLabel('CAMEROON',        3.85,   11.52),
  _MapLabel('CENT. AFR. REP',  6.61,   20.94),
  _MapLabel('BURKINA FASO',   12.36,   -1.56),
  _MapLabel('GABON',          -0.80,   11.61),
  _MapLabel('EQUAT. GUINEA',   1.65,   10.27),
  _MapLabel('D.R. CONGO',     -4.04,   21.76),
  _MapLabel('CONGO',          -0.23,   15.83),
  _MapLabel('ANGOLA',        -11.20,   17.87),
  _MapLabel('ZAMBIA',        -13.13,   27.85),
  _MapLabel('MALAWI',        -13.25,   34.30),
  _MapLabel('TANZANIA',       -6.37,   34.89),
  _MapLabel('MOZAMBIQUE',    -18.67,   35.53),
  _MapLabel('ZIMBABWE',      -19.02,   29.15),
  _MapLabel('NAMIBIA',       -22.96,   18.49),
  _MapLabel('BOTSWANA',      -22.33,   24.68),
  _MapLabel('LESOTHO',       -29.61,   28.23),
  _MapLabel('ESWATINI',      -26.52,   31.47),
  _MapLabel('MADAGASCAR',    -18.77,   46.87),
  // -- MIDDLE EAST
  _MapLabel('TURKEY',        38.96,   35.24),
  _MapLabel('SYRIA',         34.80,   38.50),
  _MapLabel('LEBANON',       33.89,   35.50),
  _MapLabel('ISRAEL',        31.05,   34.85),
  _MapLabel('PALESTINE',     31.95,   35.30),
  _MapLabel('JORDAN',        31.24,   36.51),
  _MapLabel('IRAQ',          33.22,   43.68),
  _MapLabel('KUWAIT',        29.31,   47.48),
  _MapLabel('BAHRAIN',       26.07,   50.56),
  _MapLabel('QATAR',         25.35,   51.18),
  _MapLabel('UAE',           24.00,   53.85),
  _MapLabel('OMAN',          21.51,   55.92),
  _MapLabel('YEMEN',         15.55,   48.52),
  _MapLabel('IRAN',          32.43,   53.69),
  // -- CENTRAL ASIA
  _MapLabel('KAZAKHSTAN',    48.02,   66.92),
  _MapLabel('UZBEKISTAN',    41.38,   63.97),
  _MapLabel('TURKMENISTAN',  38.97,   59.56),
  _MapLabel('KYRGYZSTAN',    41.20,   74.77),
  _MapLabel('TAJIKISTAN',    38.86,   71.28),
  _MapLabel('AFGHANISTAN',   33.94,   67.71),
  _MapLabel('PAKISTAN',      30.38,   69.35),
  // -- CAUCASUS
  _MapLabel('GEORGIA',       42.32,   43.36),
  _MapLabel('ARMENIA',       40.07,   44.95),
  _MapLabel('AZERBAIJAN',    40.14,   47.58),
  // -- ASIA
  _MapLabel('MONGOLIA',      46.86,  103.85),
  _MapLabel('TAIWAN',        23.70,  121.00),
  _MapLabel('NORTH KOREA',   40.34,  127.51),
  _MapLabel('SOUTH KOREA',   36.64,  127.98),
  _MapLabel('NEPAL',         28.39,   84.12),
  _MapLabel('BHUTAN',        27.51,   90.43),
  _MapLabel('BANGLADESH',    23.68,   90.36),
  _MapLabel('SRI LANKA',      7.87,   80.77),
  _MapLabel('MALDIVES',       3.20,   73.22),
  _MapLabel('MYANMAR',       19.16,   96.66),
  _MapLabel('THAILAND',      15.87,  100.99),
  _MapLabel('LAOS',          17.97,  102.50),
  _MapLabel('VIETNAM',       14.06,  108.28),
  _MapLabel('CAMBODIA',      12.57,  104.91),
  _MapLabel('MALAYSIA',       3.14,  110.00),
  _MapLabel('SINGAPORE',      1.35,  103.82),
  _MapLabel('BRUNEI',         4.54,  114.73),
  _MapLabel('PHILIPPINES',   12.88,  121.77),
  _MapLabel('PHILIPPINES',   12.88,  121.77),
  _MapLabel('TIMOR-LESTE',   -8.87,  125.73),
  // -- OCEANIA
  _MapLabel('AUSTRALIA',    -25.27,  133.78),
  _MapLabel('NEW ZEALAND',  -40.90,  174.88),
  _MapLabel('PAPUA N.G.',    -6.31,  143.96),
  _MapLabel('FIJI',         -17.71,  178.06),
  _MapLabel('SOLOMON IS.',   -9.65,  160.16),
  _MapLabel('VANUATU',      -15.38,  166.96),
  _MapLabel('SAMOA',        -13.76, -172.10),
  _MapLabel('TONGA',        -21.18, -175.20),
];

class _WorldMapPanelState extends State<_WorldMapPanel>
    with SingleTickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _pulseCtrl;

  // Plain doubles â€” updated via setState, no VLB nesting complexity.
  double _worldFitZoom = 1.5;
  double _labelScale = 1.0;
  double _lastPanelWidth = 0.0;
  double _lastPanelHeight = 0.0;

  // Reactive zoom â€” used only inside FlutterMap children via VLB.
  final ValueNotifier<double> _zoomNotifier = ValueNotifier<double>(1.5);

  // Loading overlay: shown on first mount and every resize as a visual decoy.
  // Hides when onMapReady fires OR after _loaderTimeout (safety net).
  bool _showLoader = true;
  Timer? _loaderTimer;
  static const Duration _loaderTimeout = Duration(milliseconds: 600);
  // World zoom/pan is clamped by onPositionChanged; no static bounds needed.
  static const double _maxZoom = 8.0;

  static Color _threatColor(double intensity) {
    if (intensity >= 0.85) return const Color(0xFFFF2D55);
    if (intensity >= 0.65) return const Color(0xFFFF7A00);
    if (intensity >= 0.45) return const Color(0xFFFFD60A);
    return const Color(0xFF00E5FF);
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final panelW = (size.width - 28.0).clamp(1.0, 99999.0);

    if ((panelW - _lastPanelWidth).abs() < 1.0) return;
    _lastPanelWidth = panelW;

    // Seed height from MediaQuery so the first frame never uses 0.
    // LayoutBuilder in _buildMapContent will overwrite this with the real value
    // on the next render, but MediaQuery gives us a good-enough estimate here.
    if (_lastPanelHeight < 10.0) {
      _lastPanelHeight = (size.height - 200.0).clamp(100.0, 99999.0);
    }

    // worldFitZoom must cover max(width, height) so the map fills the larger
    // dimension — portrait mobiles are taller than wide, so without this the
    // world tiles are shorter than the panel and black bars appear at top/bottom.
    final maxDim = math.max(panelW, _lastPanelHeight);
    final newWfz = (math.log(maxDim / 256.0) / math.ln2).clamp(0.0, 4.0);
    final newLsc = (panelW / 360.0).clamp(0.75, 1.40);

    // Show the loading overlay as a visual decoy every time width changes,
    // so the user never sees raw map glitches during resize or orientation flip.
    _loaderTimer?.cancel();
    setState(() {
      _worldFitZoom = newWfz;
      _labelScale = newLsc;
      _showLoader = true;
    });

    // Safety-net: hide loader after timeout even if onMapReady doesn't fire.
    _loaderTimer = Timer(_loaderTimeout, () {
      if (mounted && _showLoader) setState(() => _showLoader = false);
    });

    // Snap camera after current frame so MapController is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.move(const l2.LatLng(0, 0), newWfz);
      } catch (_) {
        // Map not yet initialised â€” onMapReady handles first positioning.
      }
    });
  }

  @override
  void dispose() {
    _loaderTimer?.cancel();
    _pulseCtrl.dispose();
    _zoomNotifier.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hotspots = widget.provider.hotspots;
    final hasData = hotspots.isNotEmpty;
    return _buildMapContent(hotspots, hasData);
  }

  Widget _buildMapContent(List<RiskHotspot> hotspots, bool hasData) {
    final worldFitZoom = _worldFitZoom;
    final labelScale = _labelScale;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Capture the actual rendered height of the map panel on this device.
        // This replaces the rough `screenH - 220` estimate used in
        // didChangeDependencies and gives a pixel-perfect clamp on every form factor.
        final actualH = constraints.maxHeight;
        if (actualH.isFinite && actualH > 0 && (actualH - _lastPanelHeight).abs() > 1.0) {
          _lastPanelHeight = actualH;
        }
        return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF26D9FF).withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF26D9FF).withValues(alpha: 0.06),
            blurRadius: 20,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Flutter Map â€” stable key: NEVER destroyed on rebuild.
            // Camera updates exclusively via MapController.
            FlutterMap(
              key: const ValueKey('world_map_stable'),
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const l2.LatLng(0, 0),
                initialZoom: worldFitZoom,
                minZoom: worldFitZoom,
                maxZoom: _maxZoom,
                backgroundColor: const Color(0xFF060D18),
                // NOTE: CameraConstraint.contain REMOVED — it causes an
                // internal flutter_map assertion crash whenever MapOptions
                // are rebuilt (resize / reload / tab switch).  The soft
                // clamp in onPositionChanged below gives identical UX.
                onMapReady: () {
                  // Snap to correct world-fit zoom on first init.
                  _mapController.move(
                      const l2.LatLng(0, 0), _worldFitZoom);
                  _zoomNotifier.value = _mapController.camera.zoom;
                  // Hide the decoy loading overlay immediately.
                  _loaderTimer?.cancel();
                  if (mounted && _showLoader) {
                    setState(() => _showLoader = false);
                  }
                },
                onMapEvent: (event) {
                  _zoomNotifier.value = event.camera.zoom;
                },
                onPositionChanged: (position, hasGesture) {
                  if (!mounted) return;
                  final center = position.center;
                  final zoom = position.zoom;
                  if (center == null || zoom == null) return;

                  // World size in pixels at this zoom level (Mercator tiles are square).
                  final worldPx = 256.0 * math.pow(2.0, zoom);

                  // ── HORIZONTAL clamp (eliminates left/right mirror worlds) ──
                  final visibleLng = (_lastPanelWidth / worldPx) * 360.0;
                  final maxLng = visibleLng >= 360.0 ? 0.0 : 180.0 - (visibleLng / 2.0);

                  // ── VERTICAL clamp (eliminates top/bottom broken map) ──────
                  // Mercator maps ±85.05° latitude onto the same square height
                  // as the full 360° of longitude.  So the *pixel* height of
                  // the visible region maps directly to the fractional lat range.
                  final visibleLatFraction = _lastPanelHeight / worldPx;
                  // Total Mercator lat span = 170.1° (−85.05 … +85.05)
                  final visibleLatDeg = visibleLatFraction * 170.1;
                  final maxLat = visibleLatDeg >= 170.1
                      ? 0.0
                      : 85.05 - (visibleLatDeg / 2.0);

                  final clampedLng = center.longitude.clamp(-maxLng, maxLng);
                  final clampedLat = center.latitude.clamp(-maxLat, maxLat);

                  if ((clampedLat - center.latitude).abs() > 0.001 ||
                      (clampedLng - center.longitude).abs() > 0.001) {
                    if (hasGesture) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _mapController.move(
                              l2.LatLng(clampedLat, clampedLng), zoom);
                        }
                      });
                    }
                  }
                },
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                // Base tiles â€” CartoDB dark, no labels
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.riskguard.app',
                  tileBuilder: (ctx, child, tile) => ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      0.85, 0, 0, 0, 0,
                      0, 0.92, 0, 0, 0,
                      0, 0, 1.05, 0, 10,
                      0, 0, 0, 1, 0,
                    ]),
                    child: child,
                  ),
                ),

                // Tier 1: Continent labels (visible at world-fit zoom)
                ValueListenableBuilder<double>(
                  valueListenable: _zoomNotifier,
                  builder: (ctx, zoom, _) {
                    if (zoom > worldFitZoom + 2.5) {
                      return const SizedBox.shrink();
                    }
                    final opacity =
                        (1.0 - ((zoom - (worldFitZoom + 1.0)) / 1.5))
                            .clamp(0.5, 0.92);
                    return MarkerLayer(
                      markers: _continentLabels
                          .map(
                            (c) => Marker(
                              point: l2.LatLng(c.lat, c.lng),
                              width: 160 * labelScale,
                              height: 30 * labelScale,
                              child: Opacity(
                                opacity: opacity,
                                child: Text(
                                  c.name,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11 * labelScale,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.5 * labelScale,
                                    shadows: [
                                      Shadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.95),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),

                // Tier 1.5: Priority nations (slight zoom-in)
                ValueListenableBuilder<double>(
                  valueListenable: _zoomNotifier,
                  builder: (ctx, zoom, _) {
                    final activeMin = worldFitZoom + 0.8;
                    if (zoom < activeMin || zoom > 6.5) {
                      return const SizedBox.shrink();
                    }
                    final opacity =
                        ((zoom - activeMin) / 0.8).clamp(0.0, 0.70);
                    return MarkerLayer(
                      markers: _priorityCountryLabels
                          .map(
                            (c) => Marker(
                              point: l2.LatLng(c.lat, c.lng),
                              width: 110 * labelScale,
                              height: 22 * labelScale,
                              child: Opacity(
                                opacity: opacity,
                                child: Text(
                                  c.name,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: const Color(0xFF26D9FF)
                                        .withValues(alpha: 0.85),
                                    fontSize: 8.5 * labelScale,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2 * labelScale,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),

                // Tier 2: All countries (deep zoom)
                ValueListenableBuilder<double>(
                  valueListenable: _zoomNotifier,
                  builder: (ctx, zoom, _) {
                    final activeMin = worldFitZoom + 2.0;
                    if (zoom < activeMin || zoom > 7.5) {
                      return const SizedBox.shrink();
                    }
                    final opacity =
                        ((zoom - activeMin) / 0.8).clamp(0.0, 0.65);
                    return MarkerLayer(
                      markers: _countryLabels
                          .map(
                            (c) => Marker(
                              point: l2.LatLng(c.lat, c.lng),
                              width: 100 * labelScale,
                              height: 18 * labelScale,
                              child: Opacity(
                                opacity: opacity,
                                child: Text(
                                  c.name,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: const Color(0xFF26D9FF)
                                        .withValues(alpha: 0.7),
                                    fontSize: 8.5 * labelScale,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0 * labelScale,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.95),
                                        blurRadius: 5,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),

                // Threat hotspot pulses + city labels
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (ctx, _) {
                    return ValueListenableBuilder<double>(
                      valueListenable: _zoomNotifier,
                      builder: (ctx, zoom, _) {
                        return MarkerLayer(
                          markers: hotspots.expand((h) {
                            final color = _threatColor(h.intensity);
                            final ms = (36 + h.intensity * 20)
                                    .clamp(36.0, 56.0)
                                    .toDouble() *
                                labelScale;
                            final markers = <Marker>[
                              Marker(
                                point: l2.LatLng(h.lat, h.lng),
                                width: ms,
                                height: ms,
                                child: _PulseMarker(
                                  color: color,
                                  intensity: h.intensity,
                                  t: _pulseCtrl.value,
                                ),
                              ),
                            ];
                            if (zoom >= 3.0 && h.label.isNotEmpty) {
                              markers.add(Marker(
                                point: l2.LatLng(
                                  h.lat - (0.8 / math.pow(2, zoom - 2)),
                                  h.lng,
                                ),
                                width: 120 * labelScale,
                                height: 28 * labelScale,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      h.label.toUpperCase(),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: color.withValues(alpha: 0.9),
                                        fontSize: 8 * labelScale,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8 * labelScale,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.95),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${h.eventCount} events',
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.4),
                                        fontSize: 7 * labelScale,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ));
                            }
                            return markers;
                          }).toList(),
                        );
                      },
                    );
                  },
                ),

                // Terminal pulse (highest-intensity hotspot)
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (ctx, _) {
                    if (hotspots.isEmpty) return const SizedBox.shrink();
                    final RiskHotspot anchor = hotspots.reduce(
                        (RiskHotspot a, RiskHotspot b) =>
                            a.intensity >= b.intensity ? a : b);
                    return MarkerLayer(
                      markers: [
                        Marker(
                          point: l2.LatLng(anchor.lat, anchor.lng),
                          width: 70 * labelScale,
                          height: 70 * labelScale,
                          child: _PulseMarker(
                            color: const Color(0xFF00E5FF),
                            intensity: anchor.intensity,
                            t: _pulseCtrl.value,
                            isTerminal: true,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),

            // HUD corner brackets
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _HUDCornerPainter()),
              ),
            ),

            // Threat legend (bottom-left)
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE5060B12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: hasData
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          _LegendDot(
                              color: Color(0xFFFF2D55), label: 'CRITICAL'),
                          SizedBox(width: 10),
                          _LegendDot(color: Color(0xFFFF7A00), label: 'HIGH'),
                          SizedBox(width: 10),
                          _LegendDot(
                              color: Color(0xFFFFD60A), label: 'MEDIUM'),
                          SizedBox(width: 10),
                          _LegendDot(color: Color(0xFF00E5FF), label: 'LOW'),
                        ],
                      )
                    : Text(
                        'Standing by for validated deepfake telemetry',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 10,
                          letterSpacing: 0.2,
                        ),
                      ),
              ),
            ),

            // Reset to world view (bottom-right)
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () =>
                      _mapController.move(const l2.LatLng(0, 0), _worldFitZoom),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xE5060B12),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: const Color(0xFF26D9FF).withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      Icons.zoom_out_map_rounded,
                      color: Color(0xFF26D9FF),
                      size: 14,
                    ),
                  ),
                ),
              ),
            ),

            // Full-area decoy overlay â€” covers the map while it repositions.
            // Shows on first mount AND every resize. Hides via onMapReady or
            // after _loaderTimeout ms, whichever comes first.
            if (_showLoader)
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xF0060D18),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: const Color(0xFF26D9FF),
                          backgroundColor:
                              const Color(0xFF26D9FF).withValues(alpha: 0.12),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'SCANNING',
                        style: TextStyle(
                          color:
                              const Color(0xFF26D9FF).withValues(alpha: 0.7),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],       // Stack children
        ),         // ClipRRect
      ),           // Container
      );           // LayoutBuilder return
      },           // LayoutBuilder builder
    );             // LayoutBuilder
  }
}
class _TerminalPanel extends StatelessWidget {
  const _TerminalPanel({required this.provider});
  final ThreatIntelligenceProvider provider;

  @override
  Widget build(BuildContext context) {
    final threats = provider.terminalThreats;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF08111A),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFF26D9FF),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'THREAT TERMINAL',
                  style: TextStyle(
                    color: Color(0xFF26D9FF),
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${threats.length} EVENTS',
                  style: const TextStyle(
                    color: Color(0xFF6A8293),
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: threats.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No verified deepfake hotspots in the current window.\nTerminal standing by for validated telemetry.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF7AA6C1),
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: threats.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 18,
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                    itemBuilder: (context, index) =>
                        _TerminalRow(threat: threats[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TerminalRow extends StatelessWidget {
  const _TerminalRow({required this.threat});
  final GlobalThreat threat;

  @override
  Widget build(BuildContext context) {
    final severityColor = switch (threat.severity) {
      'CRITICAL' => Colors.redAccent,
      'HIGH' => Colors.orangeAccent,
      _ => const Color(0xFF26D9FF),
    };
    final timestamp = threat.timestamp.length >= 19
        ? threat.timestamp.substring(11, 19)
        : threat.timestamp;
    return GestureDetector(
      onTap: () => _showMediaPreview(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Terminal entry text (existing style)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$timestamp | ${threat.region} | ${threat.threatClass.toUpperCase()} | ${threat.severity} | ${threat.confidenceBand} | ${threat.analysisSource.toUpperCase()}',
                  style: TextStyle(
                    color: severityColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${threat.cityOrZoneLabel} :: ${threat.artifactSummary}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB8C7D1),
                    fontSize: 12,
                    height: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
                if (threat.mediaName.isNotEmpty &&
                    threat.mediaName != 'unknown' &&
                    !threat.mediaName.startsWith('/9j') &&
                    !threat.mediaName.startsWith('data:'))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '📎 ${threat.mediaName.length > 50 ? threat.mediaName.substring(0, 50) : threat.mediaName}  •  ${threat.score}%',
                      style: TextStyle(
                        color: severityColor.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Right: Small media preview thumbnail
          _SmallMediaPreview(threat: threat),
        ],
      ),
    );
  }

  void _showMediaPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xCC060B12),
      builder: (context) => _MediaExpandedOverlay(threat: threat),
    );
  }
}

/// 44x44 small media preview thumbnail
class _SmallMediaPreview extends StatelessWidget {
  const _SmallMediaPreview({required this.threat});
  final GlobalThreat threat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1726),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF26D9FF).withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildPreviewContent(),
    );
  }

  Widget _buildPreviewContent() {
    final mediaType = threat.mediaType.toLowerCase();
    final cls = threat.threatClass.toLowerCase();
    final isVideo = cls.contains('video') || mediaType.contains('video');
    final isVoice = cls.contains('voice') || cls.contains('clone') || mediaType.contains('voice') || mediaType.contains('audio');
    
    // Voice thumbnail logic
    if (isVoice) {
      return Container(
        color: const Color(0xFF14B8A6).withValues(alpha: 0.1),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mic_rounded, color: Color(0xFF14B8A6), size: 14),
              const SizedBox(height: 2),
              _MiniWaveform(),
            ]
          )
        ),
      );
    }

    Widget? thumbnail;
    if (threat.previewData.isNotEmpty) {
      try {
        String raw = threat.previewData;
        final commaIdx = raw.indexOf(',');
        if (commaIdx > 0 && commaIdx < 80) raw = raw.substring(commaIdx + 1);
        final bytes = base64Decode(raw);
        thumbnail = Image.memory(bytes, fit: BoxFit.cover, width: 44, height: 44);
      } catch (_) {}
    }

    if (isVideo) {
      return Stack(
        fit: StackFit.expand,
        children: [
          thumbnail ?? const SizedBox.shrink(),
          Container(color: Colors.black.withValues(alpha: 0.4)),
          Center(
            child: Icon(
              Icons.play_arrow_rounded,
              color: const Color(0xFFFF7043),
              size: 26,
            ),
          ),
        ],
      );
    } else if (thumbnail != null) {
      return thumbnail;
    }

    if (cls.contains('image') || mediaType.contains('image')) {
      return const Center(
        child: Icon(Icons.image_rounded, color: Color(0xFF26D9FF), size: 22),
      );
    } else {
      return Container(
        color: const Color(0xFF26D9FF).withValues(alpha: 0.05),
        child: Center(
          child: Icon(
            Icons.article_rounded,
            color: const Color(0xFF7AA6C1).withValues(alpha: 0.8),
            size: 22,
          ),
        ),
      );
    }
  }
}

/// Mini animated waveform for voice entries
class _MiniWaveform extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final height = 8.0 + (i % 3) * 6.0;
          return Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF26D9FF).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

/// Full-screen expandable overlay for media preview
class _MediaExpandedOverlay extends StatelessWidget {
  const _MediaExpandedOverlay({required this.threat});
  final GlobalThreat threat;

  @override
  Widget build(BuildContext context) {
    final severityColor = switch (threat.severity) {
      'CRITICAL' => Colors.redAccent,
      'HIGH' => Colors.orangeAccent,
      _ => const Color(0xFF26D9FF),
    };

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1220),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF26D9FF).withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF26D9FF).withValues(alpha: 0.08),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: severityColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${(threat.score * 100).toInt()}% ${threat.severity}',
                      style: TextStyle(
                        color: severityColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: Colors.white54,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),
            // Media content
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.35,
                    minHeight: 120,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF08111D),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: _buildExpandedContent(),
                ),
              ),
            ),
            // Metadata
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _mediaTypeIcon(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          threat.mediaName.isNotEmpty &&
                                  threat.mediaName != 'unknown'
                              ? threat.mediaName
                              : threat.threatClass.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    threat.artifactSummary,
                    style: const TextStyle(
                      color: Color(0xFF7AA6C1),
                      fontSize: 11,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Bottom bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${threat.region} • ${threat.cityOrZoneLabel}',
                      style: const TextStyle(
                        color: Color(0xFF5A7A8A),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14B8A6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Text(
                      '✓ BLOCKCHAIN',
                      style: TextStyle(
                        color: Color(0xFF14B8A6),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    final mediaType = threat.mediaType.toLowerCase();
    final cls = threat.threatClass.toLowerCase();
    final isVideo = cls.contains('video') || mediaType.contains('video');
    final isVoice = cls.contains('voice') || cls.contains('clone') || mediaType.contains('voice') || mediaType.contains('audio');
    final isImage = cls.contains('image') || mediaType.contains('image');
    
    Uint8List? imageBytes;
    if (threat.previewData.isNotEmpty) {
      try {
        String raw = threat.previewData;
        final commaIdx = raw.indexOf(',');
        if (commaIdx > 0 && commaIdx < 80) raw = raw.substring(commaIdx + 1);
        imageBytes = base64Decode(raw.trim());
      } catch (_) {}
    }

    if (isVoice) {
      return _ExpandedVoiceVisual(threat: threat);
    } else if (isVideo) {
      return _ExpandedVideoPlaceholder(threat: threat, imageBytes: imageBytes);
    } else if (isImage && imageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(
          imageBytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => _NoPreviewPlaceholder(
            icon: Icons.broken_image_rounded,
            label: 'Image could not be loaded',
            color: const Color(0xFF26D9FF),
          ),
        ),
      );
    } else if (isImage) {
      return _ExpandedImagePlaceholder(threat: threat);
    }
    
    // Generic fallback -> Text report UI
    return _ExpandedTextPlaceholder(threat: threat);
  }

  Widget _mediaTypeIcon() {
    final mediaType = threat.mediaType.toLowerCase();
    if (mediaType.contains('image') || threat.threatClass.contains('image')) {
      return const Icon(
        Icons.image_rounded,
        color: Color(0xFF26D9FF),
        size: 18,
      );
    } else if (mediaType.contains('video') ||
        threat.threatClass.contains('video')) {
      return const Icon(
        Icons.videocam_rounded,
        color: Color(0xFFFF7043),
        size: 18,
      );
    } else if (mediaType.contains('voice') ||
        threat.threatClass.contains('voice') ||
        threat.threatClass.contains('clone')) {
      return const Icon(Icons.mic_rounded, color: Color(0xFF14B8A6), size: 18);
    }
    return const Icon(
      Icons.description_rounded,
      color: Color(0xFF7AA6C1),
      size: 18,
    );
  }
}

/// Expanded voice waveform with play button
class _ExpandedVoiceVisual extends StatefulWidget {
  const _ExpandedVoiceVisual({required this.threat});
  final GlobalThreat threat;

  @override
  State<_ExpandedVoiceVisual> createState() => _ExpandedVoiceVisualState();
}

class _ExpandedVoiceVisualState extends State<_ExpandedVoiceVisual> with TickerProviderStateMixin {
  VideoPlayerController? _ctrl;
  AnimationController? _scanCtrl;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final mediaUrl = widget.threat.mediaUrl;
    if (mediaUrl.isEmpty) return;
    try {
      final fullUrl = '${ApiConfig.baseUrl}$mediaUrl';
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(fullUrl));
      await ctrl.initialize();
      ctrl.addListener(() {
        if (mounted) {
          setState(() {
            _position = ctrl.value.position;
            _duration = ctrl.value.duration;
            _isPlaying = ctrl.value.isPlaying;
          });
        }
      });
      if (mounted) {
        setState(() {
          _ctrl = ctrl;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    _scanCtrl?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_ctrl != null) {
      if (_isPlaying) {
        _ctrl!.pause();
      } else {
        _ctrl!.play();
      }
    }
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF03070C),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background Animation
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _scanCtrl ?? Listenable.merge([]),
              builder: (context, child) {
                if (_scanCtrl == null) return const SizedBox();
                return CustomPaint(
                  painter: _VoiceBackgroundPainter(
                    progress: _scanCtrl!.value,
                    isPlaying: _isPlaying,
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.mic_rounded, color: const Color(0xFF14B8A6).withValues(alpha: 0.6), size: 16),
                      const SizedBox(width: 8),
                      const Text('LIVE VOICE ANALYSIS', style: TextStyle(color: Color(0xFF14B8A6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(24, (i) {
                      final height = 10.0 + math.Random(i + (widget.threat.score * 100).toInt()).nextDouble() * 40.0;
                      return Container(
                        width: 4,
                        height: height,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14B8A6).withValues(alpha: _isPlaying ? 1.0 : 0.4),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: _isPlaying ? [
                            BoxShadow(
                              color: const Color(0xFF14B8A6).withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 1,
                            )
                          ] : [],
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(_formatDuration(_position), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: _duration.inSeconds > 0 ? _position.inSeconds / _duration.inSeconds : 0.0,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF14B8A6)),
                        )
                      ),
                      const SizedBox(width: 8),
                      Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    ]
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 24),
                      GestureDetector(
                        onTap: _togglePlay,
                        child: Icon(_isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: const Color(0xFF14B8A6), size: 42),
                      ),
                      const SizedBox(width: 24),
                      const Icon(Icons.skip_next_rounded, color: Colors.white, size: 24),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('AI Voice: ${widget.threat.severity} RISK • ${(widget.threat.score * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceBackgroundPainter extends CustomPainter {
  final double progress;
  final bool isPlaying;

  _VoiceBackgroundPainter({required this.progress, required this.isPlaying});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final gridStep = 40.0;
    final color = const Color(0xFF14B8A6);

    // Subtle Grid
    for (double x = 0; x <= size.width; x += gridStep) {
      paint.color = color.withValues(alpha: 0.05);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += gridStep) {
      paint.color = color.withValues(alpha: 0.05);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Scanning Line
    final scanY = size.height * progress;
    final scanPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: isPlaying ? 0.3 : 0.1),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTRB(0, scanY - 40, size.width, scanY + 40));

    canvas.drawRect(Rect.fromLTWH(0, scanY - 40, size.width, 80), scanPaint);

    final linePaint = Paint()
      ..color = color.withValues(alpha: isPlaying ? 0.6 : 0.2)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, scanY), Offset(size.width, scanY), linePaint);

    // Extra "reaction" pulses if playing
    if (isPlaying) {
      final pulseR = (progress * 1.5 % 1.0) * size.width;
      final pulsePaint = Paint()
        ..color = color.withValues(alpha: (1.0 - (progress * 1.5 % 1.0)) * 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), pulseR, pulsePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceBackgroundPainter oldDelegate) => true;
}


class _ExpandedVideoPlaceholder extends StatefulWidget {
  const _ExpandedVideoPlaceholder({required this.threat, this.imageBytes});
  final GlobalThreat threat;
  final Uint8List? imageBytes;

  @override
  State<_ExpandedVideoPlaceholder> createState() => _ExpandedVideoPlaceholderState();
}

class _ExpandedVideoPlaceholderState extends State<_ExpandedVideoPlaceholder> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _hasError = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final mediaUrl = widget.threat.mediaUrl;
    if (mediaUrl.isEmpty) return;

    try {
      final fullUrl = '${_baseUrl()}$mediaUrl';
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(fullUrl));
      await ctrl.initialize();
      ctrl.setLooping(true);
      ctrl.play();
      if (mounted) {
        setState(() {
          _ctrl = ctrl;
          _initialized = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  String _baseUrl() => ApiConfig.baseUrl;

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A12),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Poster / video frame
          if (_initialized && _ctrl != null)
            AspectRatio(
              aspectRatio: _ctrl!.value.aspectRatio,
              child: VideoPlayer(_ctrl!),
            )
          else if (widget.imageBytes != null)
            Image.memory(widget.imageBytes!, fit: BoxFit.cover)
          else
            Container(color: const Color(0xFF0A0A12)),

          // Scrim
          Container(
            color: const Color(0xFF0A0A12)
                .withValues(alpha: _initialized ? 0.0 : (widget.imageBytes != null ? 0.55 : 1.0)),
          ),

          // Controls overlay at the bottom
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Scrubber
                  if (_initialized && _ctrl != null)
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _ctrl!,
                      builder: (context2, v, child2) {
                        final total = v.duration.inMilliseconds;
                        final pos = v.position.inMilliseconds;
                        final progress = total > 0 ? pos / total : 0.0;
                        String fmtDur(Duration d) {
                          final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
                          final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
                          return '$m:$s';
                        }
                        return Row(children: [
                          Text(fmtDur(v.position),
                              style: const TextStyle(color: Colors.white70, fontSize: 10)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: progress.clamp(0.0, 1.0),
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF7043)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(fmtDur(v.duration),
                              style: const TextStyle(color: Colors.white70, fontSize: 10)),
                        ]);
                      },
                    )
                  else
                    Row(children: [
                      const Text('0:00', style: TextStyle(color: Colors.white70, fontSize: 10)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF7043)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('0:00', style: TextStyle(color: Colors.white70, fontSize: 10)),
                    ]),

                  const SizedBox(height: 10),

                  // Play / pause button row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 24),
                      GestureDetector(
                        onTap: () {
                          if (_ctrl == null) return;
                          _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play();
                          setState(() {});
                        },
                        child: Icon(
                          (_ctrl?.value.isPlaying ?? false)
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                          color: const Color(0xFFFF7043),
                          size: 34,
                        ),
                      ),
                      const SizedBox(width: 24),
                      const Icon(Icons.skip_next_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 24),
                      GestureDetector(
                        onTap: () {
                          if (_ctrl == null) return;
                          setState(() {
                            _muted = !_muted;
                            _ctrl!.setVolume(_muted ? 0.0 : 1.0);
                          });
                        },
                        child: Icon(
                          _muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: _muted ? const Color(0xFFFF7043) : Colors.white70,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Label badge
          Positioned(
            top: 12, left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.black54, borderRadius: BorderRadius.circular(4)),
              child: Text(
                _hasError
                    ? 'VIDEO PREVIEW'
                    : _initialized
                        ? 'LIVE VIDEO EVIDENCE'
                        : 'LOADING...',
                style: TextStyle(
                  color: _hasError ? Colors.white54 : const Color(0xFFFF7043),
                  fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2,
                ),
              ),
            ),
          ),

          // Big play icon if not initialized and no poster
          if (!_initialized && widget.imageBytes == null && !_hasError)
            const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  color: Color(0xFFFF7043), size: 56),
            ),
        ],
      ),
    );
  }
}

class _ExpandedImagePlaceholder extends StatelessWidget {
  const _ExpandedImagePlaceholder({required this.threat});
  final GlobalThreat threat;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_rounded,
            color: const Color(0xFF26D9FF).withValues(alpha: 0.4),
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            'Image analysis • ${threat.score}%',
            style: const TextStyle(color: Color(0xFF7AA6C1), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ExpandedTextPlaceholder extends StatelessWidget {
  const _ExpandedTextPlaceholder({required this.threat});
  final GlobalThreat threat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_rounded, color: Color(0xFF26D9FF), size: 16),
              const SizedBox(width: 8),
              const Text('LIVE TEXT ANALYSIS', style: TextStyle(color: Color(0xFF26D9FF), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                threat.artifactSummary.isNotEmpty ? threat.artifactSummary : 'No readable payload provided.',
                style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _NoPreviewPlaceholder extends StatelessWidget {
  const _NoPreviewPlaceholder({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 48),
          const SizedBox(height: 14),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.85),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

  // ---------------------------------------------------
/// [t] is the normalised animation clock (0.0 – 1.0), driven by parent
/// AnimatedBuilder so all markers sync to the same beat.
class _PulseMarker extends StatelessWidget {
  const _PulseMarker({
    required this.color,
    required this.intensity,
    required this.t,
    this.isTerminal = false,
  });

  final Color color;
  final double intensity;
  final double t; // 0..1 animation progress
  final bool isTerminal;

  @override
  Widget build(BuildContext context) {
    // Three rings staggered 1/3 cycle apart
    final t1 = t;
    final t2 = (t + 0.33) % 1.0;
    final t3 = (t + 0.66) % 1.0;

    final baseRadius = isTerminal ? 24.0 : 14.0;
    final maxR = baseRadius + intensity * 10.0; // max ring radius px
    final dotR = isTerminal ? 7.0 : 5.0;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Ring 3 (outermost)
        _Ring(color: color, t: t3, maxR: maxR),
        // Ring 2
        _Ring(color: color, t: t2, maxR: maxR * 0.75),
        // Ring 1 (innermost)
        _Ring(color: color, t: t1, maxR: maxR * 0.50),

        // Solid core dot
        Container(
          width: dotR * 2,
          height: dotR * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.85),
                blurRadius: isTerminal ? 14 : 8,
                spreadRadius: isTerminal ? 2 : 1,
              ),
              if (isTerminal)
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.color, required this.t, required this.maxR});
  final Color color;
  final double t; // 0..1 – how far expanded this ring is
  final double maxR; // maximum radius in px

  @override
  Widget build(BuildContext context) {
    // Ease-out: ring expands quickly then slows
    final eased = Curves.easeOut.transform(t);
    final size = maxR * 2 * eased;

    // Opacity: full at start, fades to 0 at end
    final alpha = (1.0 - eased).clamp(0.0, 1.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: alpha * 0.85),
          width: 1.5,
        ),
      ),
    );
  }
}

  // ---------------------------------------------------

class _HUDCornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF26D9FF).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const arm = 20.0;
    const pad = 6.0;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(pad, pad + arm)
        ..lineTo(pad, pad)
        ..lineTo(pad + arm, pad),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - pad - arm, pad)
        ..lineTo(size.width - pad, pad)
        ..lineTo(size.width - pad, pad + arm),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(pad, size.height - pad - arm)
        ..lineTo(pad, size.height - pad)
        ..lineTo(pad + arm, size.height - pad),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - pad - arm, size.height - pad)
        ..lineTo(size.width - pad, size.height - pad)
        ..lineTo(size.width - pad, size.height - pad - arm),
      paint,
    );

    // Small coordinate labels
    final labelPaint = TextPainter(
      text: TextSpan(
        text: 'N90°',
        style: TextStyle(
          color: const Color(0xFF26D9FF).withValues(alpha: 0.3),
          fontSize: 7,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPaint.paint(canvas, const Offset(pad + 4, pad + arm + 2));

    final labelPaint2 = TextPainter(
      text: TextSpan(
        text: 'E180°',
        style: TextStyle(
          color: const Color(0xFF26D9FF).withValues(alpha: 0.3),
          fontSize: 7,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPaint2.paint(
      canvas,
      Offset(size.width - pad - arm - 4, size.height - pad - arm - 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}






