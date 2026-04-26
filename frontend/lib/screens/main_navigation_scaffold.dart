import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/services/realtime_protection_provider.dart';
import 'package:risk_guard/screens/home/home_screen.dart';
import 'package:risk_guard/screens/history/history_screen.dart';
import 'package:risk_guard/screens/analysis/analysis_lab_screen.dart';
import 'package:risk_guard/screens/image_recognition/image_recognition_screen.dart';
import 'package:risk_guard/screens/profile/profile_screen.dart';
import 'package:risk_guard/widgets/custom_bottom_nav.dart';

/// Main navigation scaffold with persistent bottom navbar
class MainNavigationScaffold extends StatefulWidget {
  const MainNavigationScaffold({super.key});

  @override
  State<MainNavigationScaffold> createState() => _MainNavigationScaffoldState();
}

class _MainNavigationScaffoldState extends State<MainNavigationScaffold> {
  // Kept as a mutable list so IndexedStack holds all screens alive forever.
  // NEVER use const here — each screen must be a unique stable instance.
  late final List<Widget> _screens;
  int _currentIndex = 2;
  // Non-late so it's always initialized before build(), even after hot restart.
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  @override
  void initState() {
    super.initState();
    _screens = [
      const HistoryScreen(),       // index 0
      const AnalysisLabScreen(),   // index 1
      HomeScreen(
        key: _homeKey,
        onSwitchTab: (index) => setState(() => _currentIndex = index),
      ),                           // index 2
      const ImageRecognitionScreen(), // index 3
      const ProfileScreen(),       // index 4
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAccessibilityGuidance();
    });
  }

  void _checkAccessibilityGuidance() {
    final provider = context.read<RealtimeProtectionProvider>();
    if (provider.showAccessibilityGuidance) {
      _showGuidanceDialog();
    }
    // Also listen for changes
    provider.addListener(() {
      if (mounted && provider.showAccessibilityGuidance) {
        _showGuidanceDialog();
      }
    });
  }

  void _showGuidanceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.cyanAccent, width: 0.5)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text('Android 13+ Notice', style: TextStyle(color: Colors.white, fontFamily: 'Orbitron', fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'If you can\'t enable RiskGuard in Accessibility settings (it says "Restricted setting"):',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _buildStep(1, 'Go to the device "App Info" for RiskGuard (long-press the app icon).'),
            _buildStep(2, 'Tap the ⋮ (three dots) in the top-right corner.'),
            _buildStep(3, 'Select "Allow restricted settings".'),
            _buildStep(4, 'Now return to Accessibility and you can enable RiskGuard Proactive Shield.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              context.read<RealtimeProtectionProvider>().dismissAccessibilityGuidance();
              Navigator.pop(ctx);
            },
            child: const Text('GOT IT', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(int num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 8, backgroundColor: Colors.cyanAccent.withValues(alpha: 0.2), child: Text(num.toString(), style: const TextStyle(fontSize: 10, color: Colors.cyanAccent))),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Stack(
        children: [
          // IndexedStack keeps ALL screens alive simultaneously.
          // This is the key fix: screens are NEVER destroyed when switching
          // tabs, so no InheritedWidget dependents are orphaned mid-frame.
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),

          // Persistent bottom navigation
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomBottomNav(
              currentIndex: _currentIndex,
              onTap: (index) {
                if (_currentIndex == 2 && index != 2) {
                  _homeKey.currentState?.hideNotificationPanel();
                }
                setState(() {
                  _currentIndex = index;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
