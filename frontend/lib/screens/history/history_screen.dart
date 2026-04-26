import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:risk_guard/core/models/analysis_models.dart';
import 'package:risk_guard/core/services/permission_service.dart';
import 'package:risk_guard/core/services/scan_history_provider.dart';
import 'package:risk_guard/core/services/user_settings_provider.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/screens/history/widgets/animated_phone_signal.dart';

/// Call Monitoring Screen (formerly History).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with WidgetsBindingObserver {
  CallMonitoringPermissionState? _permissionState;
  bool _isRefreshingPermissions = false;

  bool get _hasPermissions => _permissionState?.isReady ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissionState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionState();
    }
  }

  Future<void> _refreshPermissionState() async {
    if (_isRefreshingPermissions) return;
    _isRefreshingPermissions = true;
    try {
      final state = await PermissionService.getCallMonitoringPermissionState();
      if (!mounted) return;
      setState(() => _permissionState = state);
    } finally {
      _isRefreshingPermissions = false;
    }
  }

  Future<void> _requestPermissions() async {
    final state = await PermissionService.ensureCallMonitoringPermissions();
    if (!mounted) return;
    setState(() => _permissionState = state);
  }

  // ─── Edit / Delete / Export helpers ─────────────────────────────

  Future<void> _editContactName(CallHistoryGroup group) async {
    final controller = TextEditingController(text: group.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _EditNameDialog(controller: controller),
    );
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    final provider = context.read<ScanHistoryProvider>();
    for (final call in group.calls) {
      await provider
          .updateCallEntry(call.copyWith(displayName: newName.trim()));
    }
  }

  Future<void> _deleteCallGroup(CallHistoryGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Call Group',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove all ${group.calls.length} call records for ${group.displayName}?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: AppColors.dangerRed,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    context.read<ScanHistoryProvider>().deleteCallGroup(group.personKey);
  }

  Future<void> _deleteCallEntry(CallHistoryEntry call) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Call Record',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove this call record from ${call.displayName}?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: AppColors.dangerRed,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    context.read<ScanHistoryProvider>().deleteCallEntry(call.id);
  }

  void _exportCallGroup(CallHistoryGroup group) {
    final buffer = StringBuffer();
    buffer.writeln('══════════════════════════════════════');
    buffer.writeln('RiskGuard — Call History Export');
    buffer.writeln('══════════════════════════════════════');
    buffer.writeln('Contact: ${group.displayName}');
    buffer.writeln('Phone:   ${group.phoneNumber}');
    buffer.writeln('Total:   ${group.calls.length} call(s)');
    buffer.writeln('──────────────────────────────────────');
    for (final call in group.calls) {
      buffer.writeln(
          '${_formatCallOutcome(call)} | ${_formatDateTimeInline(call.endedAt)} | ${_formatDuration(call.duration)}');
      buffer.writeln('  Risk: ${call.riskLevel} (${call.riskScore}%)');
      if (call.summary.isNotEmpty) {
        buffer.writeln('  Note: ${call.summary}');
      }
      buffer.writeln('');
    }
    buffer.writeln('── Generated by RiskGuard ──');
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: AppColors.successGreen, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Call history copied to clipboard')),
            ],
          ),
          backgroundColor: AppColors.darkCard,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _editCallSummary(CallHistoryEntry call) async {
    final controller = TextEditingController(text: call.summary);
    final newNote = await showDialog<String>(
      context: context,
      builder: (ctx) => _EditNoteDialog(controller: controller),
    );
    if (newNote == null || !mounted) return;
    context.read<ScanHistoryProvider>().updateCallEntry(
          call.copyWith(summary: newNote.trim()),
        );
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final historyProvider = context.watch<ScanHistoryProvider>();
    final settings = context.watch<UserSettingsProvider>();
    final callGroups = historyProvider.groupedCallHistory;
    final isFeatureEnabled = settings.callMonitoringEnabled;
    final isMonitoring = isFeatureEnabled && _hasPermissions;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Call Monitoring',
                style:
                    AppTextStyles.h2.copyWith(fontWeight: FontWeight.bold),
              ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1),

              const SizedBox(height: 24),

              _buildStatusCard(isMonitoring, isFeatureEnabled),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      '${historyProvider.callThreatsFound}',
                      'Threats Found',
                      Icons.block_rounded,
                      AppColors.dangerRed,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      '${historyProvider.verifiedCallsSafe}',
                      'Verified Safe',
                      Icons.verified_rounded,
                      AppColors.successGreen,
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),

              const SizedBox(height: 32),

              // Call History section header with Clear All button
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Call History',
                      style: AppTextStyles.h4
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (callGroups.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _clearAllHistory(historyProvider),
                      icon: Icon(Icons.delete_sweep_rounded,
                          size: 18, color: AppColors.textTertiary),
                      label: Text('Clear All',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.textTertiary)),
                    ),
                ],
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 16),

              if (callGroups.isEmpty)
                _buildEmptyState(settings)
              else
                Column(
                  children: callGroups
                      .take(10)
                      .toList()
                      .asMap()
                      .entries
                      .map((entry) {
                    final index = entry.key;
                    final group = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildCallGroupCard(group)
                          .animate()
                          .fadeIn(
                              delay: Duration(
                                  milliseconds: 500 + index * 60))
                          .slideY(begin: 0.08),
                    );
                  }).toList(),
                ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Status Card ───────────────────────────────────────────────

  Widget _buildStatusCard(bool isMonitoring, bool isFeatureEnabled) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: isMonitoring
            ? AppColors.purpleGradient
            : const LinearGradient(
                colors: [AppColors.darkCard, AppColors.darkCard],
              ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: isMonitoring
                ? AppColors.primaryGold.withValues(alpha: 0.3)
                : Colors.transparent,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isMonitoring
                  ? AppColors.primaryPurple.withValues(alpha: 0.15)
                  : Colors.black12,
              shape: BoxShape.circle,
            ),
            child: AnimatedPhoneSignal(
              color: isMonitoring
                  ? AppColors.primaryGold
                  : AppColors.textSecondary,
              size: 72,
              isActive: isMonitoring,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isMonitoring
                ? 'Monitoring Active'
                : (isFeatureEnabled
                    ? 'Permission Required'
                    : 'Monitoring Disabled'),
            style: AppTextStyles.h4.copyWith(
              color: isMonitoring
                  ? AppColors.primaryGold
                  : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isMonitoring
                ? 'Scanning incoming calls in real-time'
                : (!isFeatureEnabled
                    ? 'Enable Call Monitoring from Profile to start live monitoring.'
                    : _permissionState == null
                        ? 'Checking phone, overlay, and accessibility access.'
                        : 'Grant ${_permissionState!.missingSummary} access before call monitoring can run here.'),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          if (!isMonitoring && isFeatureEnabled) ...[
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _requestPermissions,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Allow Permissions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGold,
                foregroundColor: AppColors.textOnGold,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
  }

  // ─── Stat Card ─────────────────────────────────────────────────

  Widget _buildStatCard(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Empty State ───────────────────────────────────────────────

  Widget _buildEmptyState(UserSettingsProvider settings) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primaryPurple.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.call_rounded,
                color: AppColors.textTertiary, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            settings.callMonitoringEnabled
                ? 'No call history yet'
                : 'Call monitoring disabled',
            style: AppTextStyles.bodyMedium
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            settings.callMonitoringEnabled
                ? 'Call records will appear here once monitoring detects incoming or outgoing calls.'
                : 'Enable call monitoring from Profile to start collecting call history.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 500.ms);
  }

  // ─── Call Group Card ───────────────────────────────────────────

  Widget _buildCallGroupCard(CallHistoryGroup group) {
    final latest = group.latestCall;
    final color = _getColorForRiskLevel(latest.riskLevel);
    final todayCount =
        group.calls.where((call) => _isSameDay(call.endedAt)).length;

    return Dismissible(
      key: Key('call_group_${group.personKey}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDeleteGroup(group),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.dangerRed.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_rounded,
            color: AppColors.dangerRed, size: 26),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showCallHistoryDetails(group),
        onLongPress: () => _showGroupContextMenu(group),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              // Risk-colored avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.25),
                      color.withValues(alpha: 0.08),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: color.withValues(alpha: 0.3),
                      width: 1.5),
                ),
                child: Icon(_getOutcomeIcon(latest.outcome),
                    color: color, size: 22),
              ),
              const SizedBox(width: 14),
              // Contact info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.displayName,
                            style: AppTextStyles.bodyMedium
                                .copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (latest.riskLevel == 'HIGH')
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.dangerRed
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('⚠ RISK',
                                style: TextStyle(
                                    color: AppColors.dangerRed,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      group.phoneNumber,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(_getOutcomeIcon(latest.outcome),
                            size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${_formatCallOutcome(latest)} • ${_formatDateTimeInline(latest.endedAt)}',
                            style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Count badge + time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: color.withValues(alpha: 0.15)),
                    ),
                    child: Text(
                      todayCount > 0
                          ? '$todayCount today'
                          : '${group.calls.length} calls',
                      style: AppTextStyles.labelSmall.copyWith(
                          color: color, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatTime(latest.endedAt),
                    style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Context Menu ──────────────────────────────────────────────

  void _showGroupContextMenu(CallHistoryGroup group) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: AppColors.darkCard,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 20),
            Text(group.displayName,
                style: AppTextStyles.h4
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(group.phoneNumber,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            _contextMenuItem(
              Icons.edit_rounded,
              'Edit Contact Name',
              AppColors.primaryGold,
              () {
                Navigator.pop(ctx);
                _editContactName(group);
              },
            ),
            _contextMenuItem(
              Icons.copy_rounded,
              'Export to Clipboard',
              AppColors.info,
              () {
                Navigator.pop(ctx);
                _exportCallGroup(group);
              },
            ),
            _contextMenuItem(
              Icons.delete_rounded,
              'Delete All Records',
              AppColors.dangerRed,
              () {
                Navigator.pop(ctx);
                _deleteCallGroup(group);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _contextMenuItem(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
                child: Text(label,
                    style: AppTextStyles.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600))),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  // ─── Detail Bottom Sheet ───────────────────────────────────────

  Future<void> _showCallHistoryDetails(CallHistoryGroup group) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final color =
            _getColorForRiskLevel(group.latestCall.riskLevel);
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Handle bar
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  // Header
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Row(
                      children: [
                        // Initials avatar
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                color.withValues(alpha: 0.3),
                                color.withValues(alpha: 0.1),
                              ],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: color.withValues(alpha: 0.3),
                                width: 2),
                          ),
                          child: Center(
                            child: Text(
                              group.displayName.isNotEmpty
                                  ? group.displayName[0]
                                      .toUpperCase()
                                  : '?',
                              style: TextStyle(
                                  color: color,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Contact details
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(group.displayName,
                                  style: AppTextStyles.h4.copyWith(
                                      fontWeight:
                                          FontWeight.bold)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.phone_rounded,
                                      size: 13,
                                      color:
                                          AppColors.textSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    group.phoneNumber,
                                    style: AppTextStyles.bodySmall
                                        .copyWith(
                                            color: AppColors
                                                .textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Risk badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    color.withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            group.latestCall.riskLevel,
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Action buttons row
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _actionButton(
                            Icons.edit_rounded,
                            'Edit',
                            AppColors.primaryGold,
                            () {
                              Navigator.pop(context);
                              _editContactName(group);
                            }),
                        const SizedBox(width: 10),
                        _actionButton(
                            Icons.copy_rounded,
                            'Export',
                            AppColors.info,
                            () {
                              _exportCallGroup(group);
                              Navigator.pop(context);
                            }),
                        const SizedBox(width: 10),
                        _actionButton(
                            Icons.delete_rounded,
                            'Delete',
                            AppColors.dangerRed,
                            () {
                              Navigator.pop(context);
                              _deleteCallGroup(group);
                            }),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Records count
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Text(
                          '${group.calls.length} call records',
                          style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Text(
                          'Tap record to edit note',
                          style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Call list
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(
                          20, 0, 20, 24),
                      itemBuilder: (context, index) {
                        final call = group.calls[index];
                        return _buildCallDetailRow(call);
                      },
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 10),
                      itemCount: group.calls.length,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCallDetailRow(CallHistoryEntry call) {
    final callColor = _getColorForRiskLevel(call.riskLevel);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _editCallSummary(call),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.darkBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            // Outcome icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: callColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_getOutcomeIcon(call.outcome),
                  color: callColor, size: 18),
            ),
            const SizedBox(width: 12),
            // Call info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatCallOutcome(call),
                          style: AppTextStyles.bodyMedium
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: callColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _formatDuration(call.duration),
                          style: TextStyle(
                              color: callColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTimeInline(call.endedAt),
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  if (call.summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.border
                                .withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Icon(
                              Icons.sticky_note_2_rounded,
                              size: 14,
                              color: AppColors.textTertiary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              call.summary,
                              style: AppTextStyles.labelSmall
                                  .copyWith(
                                      color:
                                          AppColors.textSecondary,
                                      height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Delete button
            IconButton(
              onPressed: () => _deleteCallEntry(call),
              icon: const Icon(Icons.close_rounded,
                  color: AppColors.textTertiary, size: 18),
              visualDensity: VisualDensity.compact,
              tooltip: 'Delete record',
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Clear All ─────────────────────────────────────────────────

  Future<void> _clearAllHistory(ScanHistoryProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All History',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'This will permanently remove all call records. This action cannot be undone.',
          style:
              TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: TextStyle(
                      color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear All',
                  style: TextStyle(
                      color: AppColors.dangerRed,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    provider.clearHistory();
  }

  Future<bool> _confirmDeleteGroup(CallHistoryGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Call Group',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove all ${group.calls.length} records for ${group.displayName}?',
          style:
              TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: TextStyle(
                      color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(
                      color: AppColors.dangerRed,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context
          .read<ScanHistoryProvider>()
          .deleteCallGroup(group.personKey);
    }
    // Return false so Dismissible doesn't auto-remove the widget —
    // the provider handles list updates via notifyListeners.
    return false;
  }

  // ─── Helpers ───────────────────────────────────────────────────

  Color _getColorForRiskLevel(String level) {
    switch (level) {
      case 'HIGH':
        return AppColors.dangerRed;
      case 'MEDIUM':
        return Colors.orange;
      default:
        return AppColors.successGreen;
    }
  }

  IconData _getOutcomeIcon(CallHistoryOutcome outcome) {
    switch (outcome) {
      case CallHistoryOutcome.missed:
        return Icons.phone_missed_rounded;
      case CallHistoryOutcome.answered:
        return Icons.phone_in_talk_rounded;
      case CallHistoryOutcome.outgoing:
        return Icons.phone_forwarded_rounded;
      case CallHistoryOutcome.blocked:
        return Icons.phone_disabled_rounded;
      case CallHistoryOutcome.unknown:
        return Icons.phone_rounded;
    }
  }

  String _formatCallOutcome(CallHistoryEntry call) {
    switch (call.outcome) {
      case CallHistoryOutcome.missed:
        return 'Missed call';
      case CallHistoryOutcome.answered:
        return 'Answered call';
      case CallHistoryOutcome.outgoing:
        return 'Outgoing call';
      case CallHistoryOutcome.blocked:
        return 'Blocked call';
      case CallHistoryOutcome.unknown:
        return 'Call completed';
    }
  }

  String _formatDate(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(value.year, value.month, value.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('dd MMM yyyy').format(value);
  }

  String _formatTime(DateTime value) {
    return DateFormat('hh:mm a').format(value);
  }

  String _formatDateTimeInline(DateTime value) {
    return '${_formatDate(value)} | ${_formatTime(value)}';
  }

  bool _isSameDay(DateTime value) {
    final now = DateTime.now();
    return now.year == value.year &&
        now.month == value.month &&
        now.day == value.day;
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds <= 0) return '0s';
    if (duration.inMinutes < 1) return '${duration.inSeconds}s';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes < 60) return '${minutes}m ${seconds}s';
    final hours = duration.inHours;
    final remainingMinutes = duration.inMinutes % 60;
    return '${hours}h ${remainingMinutes}m';
  }
}

// ═════════════════════════════════════════════════════════════════════
// Edit Name Dialog
// ═════════════════════════════════════════════════════════════════════

class _EditNameDialog extends StatelessWidget {
  const _EditNameDialog({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.darkCard,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.edit_rounded,
              color: AppColors.primaryGold, size: 22),
          SizedBox(width: 10),
          Text('Edit Contact Name',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
        ],
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Enter contact name',
          hintStyle: TextStyle(color: AppColors.textTertiary),
          filled: true,
          fillColor: AppColors.darkBackground,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
                color: AppColors.primaryGold, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, controller.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGold,
            foregroundColor: AppColors.textOnGold,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 10),
          ),
          child: const Text('Save',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Edit Note Dialog
// ═════════════════════════════════════════════════════════════════════

class _EditNoteDialog extends StatelessWidget {
  const _EditNoteDialog({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.darkCard,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.note_add_rounded,
              color: AppColors.primaryGold, size: 22),
          SizedBox(width: 10),
          Text('Edit Note',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
        ],
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 4,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Add a note about this call...',
          hintStyle: TextStyle(color: AppColors.textTertiary),
          filled: true,
          fillColor: AppColors.darkBackground,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
                color: AppColors.primaryGold, width: 1.5),
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, controller.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGold,
            foregroundColor: AppColors.textOnGold,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 10),
          ),
          child: const Text('Save',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
