import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../components/app_logo.dart';
import '../components/stat_card.dart';
import '../core/app_events.dart';
import '../core/app_settings_service.dart';
import '../core/app_theme.dart';
import '../core/app_update_service.dart';
import '../core/app_version.dart';
import '../core/category_stock_helper.dart';
import '../core/db_helper.dart';
import 'settings_hub_screen.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int tabIndex, {int? managementSubTab})? onNavigateTab;

  const DashboardScreen({super.key, this.onNavigateTab});

  /// حساب إجمالي الأطقم الكاملة والقطع الفردية الزائدة وإجمالي القطع المتبقية عند المنجد
  /// يستخدم المحرك الموحد CategoryStockHelper لمنع التكرار
  static Map<String, int> calculateUpholstererWorkshopStats(
    List<Map<String, dynamic>> batches,
    Map<int, int> categoryComponentsCount,
  ) {
    int totalSets = 0;
    int totalIndividual = 0;
    int totalPieces = 0;

    for (final b in batches) {
      final int sent = CategoryStockHelper.parseInt(b['total_sent']);
      final int rec = CategoryStockHelper.parseInt(b['received_qty']);
      final int remBatch = sent - rec;
      if (remBatch <= 0) continue;

      final pieces = CategoryStockHelper.parseComponents(b['pieces_json']);
      if (pieces.isEmpty) {
        totalPieces += remBatch;
        totalIndividual += remBatch;
        continue;
      }

      final int? catId = b['category_id'] as int?;
      final int expectedComps = catId != null ? (categoryComponentsCount[catId] ?? 0) : 0;

      final breakdown = CategoryStockHelper.computeBreakdownFromPieces(
        pieces,
        qtyKey: 'sent_qty',
        subtractKey: 'received_qty',
        expectedComponentCount: expectedComps,
      );

      totalSets += breakdown.completeSets;
      totalIndividual += breakdown.individualPieces;
      totalPieces += breakdown.totalPieces;
    }

    return {
      'sets': totalSets,
      'individual': totalIndividual,
      'totalPieces': totalPieces,
    };
  }

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int customersCount = 0;
  int categoriesCount = 0;
  int totalStock = 0;

  int waitingStandard = 0;
  int waitingCustom = 0;

  int deliveredStandard = 0;
  int deliveredCustom = 0;

  int upholstererRemainingSets = 0;
  int upholstererRemainingIndividualPieces = 0;
  int upholstererRemainingPieces = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
    AppEvents.instance.refreshNotifier.addListener(_loadStats);
  }

  @override
  void dispose() {
    AppEvents.instance.refreshNotifier.removeListener(_loadStats);
    super.dispose();
  }

  Future<void> _loadStats() async {
    final db = await DBHelper.instance.database;
    final cust = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM customers')) ?? 0;
    final cats = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM categories')) ?? 0;
    final stock = Sqflite.firstIntValue(await db.rawQuery('SELECT SUM(stock_qty) FROM categories')) ?? 0;

    final waitStd = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM orders WHERE status = 'waiting' AND (order_type = 'نمطي' OR order_type = 'نمطى')"
    )) ?? 0;
    final waitCust = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM orders WHERE status = 'waiting' AND (order_type != 'نمطي' AND order_type != 'نمطى')"
    )) ?? 0;

    final delivStd = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM orders WHERE status = 'delivered' AND (order_type = 'نمطي' OR order_type = 'نمطى')"
    )) ?? 0;
    final delivCust = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM orders WHERE status = 'delivered' AND (order_type != 'نمطي' AND order_type != 'نمطى')"
    )) ?? 0;

    final catRows = await db.query('categories', columns: ['id', 'components_json']);
    final Map<int, int> catCompCounts = {};
    for (final c in catRows) {
      final int? id = c['id'] as int?;
      if (id == null) continue;
      try {
        catCompCounts[id] = CategoryStockHelper.getMainComponents(c['components_json']).length;
      } catch (_) {}
    }

    final batchRows = await db.query(
      'upholsterer_batches',
      columns: ['category_id', 'total_sent', 'received_qty', 'pieces_json'],
    );
    final uphStats = DashboardScreen.calculateUpholstererWorkshopStats(batchRows, catCompCounts);

    if (mounted) {
      setState(() {
        customersCount = cust;
        categoriesCount = cats;
        totalStock = stock;
        waitingStandard = waitStd;
        waitingCustom = waitCust;
        deliveredStandard = delivStd;
        deliveredCustom = delivCust;
        upholstererRemainingSets = uphStats['sets']!;
        upholstererRemainingIndividualPieces = uphStats['individual']!;
        upholstererRemainingPieces = uphStats['totalPieces']!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitleWithLogo(
          title: 'لوحة التحكم والتقارير',
          logoSize: 36,
        ),
        actions: [
          ValueListenableBuilder<AppUpdateInfo?>(
            valueListenable: AppUpdateService.availableUpdateNotifier,
            builder: (context, update, child) {
              return IconButton(
                tooltip: update != null
                    ? 'تحديث جديد متاح (إصدار ${update.latestVersion})'
                    : 'الإعدادات',
                icon: Badge(
                  isLabelVisible: update != null,
                  label: const Text(
                    '1',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  backgroundColor: const Color(0xFFE53935),
                  alignment: AlignmentDirectional.topEnd,
                  child: Icon(
                    Icons.settings_rounded,
                    color: AppTheme.accentOnSurface(context),
                    size: 26,
                  ),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsHubScreen()),
                ).then((_) => _loadStats()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double maxWidth = constraints.maxWidth;
            final int crossAxisCount = maxWidth >= 1020
                ? 4
                : (maxWidth >= 660 ? 3 : 2);
            final double aspectRatio = maxWidth >= 1020
                ? 1.32
                : (maxWidth >= 660
                    ? 1.25
                    : (maxWidth < 380 ? 1.05 : 1.15));

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1220),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    // بنر الترحيب المدمج بهوية المعرض الديناميكية ورقم الإصدار
                    ValueListenableBuilder<ShowroomProfile>(
                      valueListenable: AppSettingsService.showroomProfileNotifier,
                      builder: (context, profile, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppTheme.primaryNavy, Color(0xFF2B5282)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.14),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const AppLogo(size: 46, showBorder: true),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: AlignmentDirectional.centerStart,
                                            child: Text(
                                              profile.displayName,
                                              style: const TextStyle(
                                                color: AppTheme.royalGold,
                                                fontSize: 16.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.royalGold.withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: AppTheme.royalGold.withValues(alpha: 0.45),
                                            ),
                                          ),
                                          child: Text(
                                            AppVersion.displayVersion,
                                            style: const TextStyle(
                                              color: AppTheme.royalGold,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      profile.displaySubtitle,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.85),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // شبكة الكروت الإحصائية المتجاوبة لجميع المقاسات (موبايل / تابلت / كمبيوتر)
                    GridView.count(
                      crossAxisCount: crossAxisCount,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: aspectRatio,
                      children: [
                        SplitStatCard(
                          title: 'قائمة الانتظار',
                          icon: Icons.pending_actions_rounded,
                          color: Colors.orange.shade700,
                          standardCount: waitingStandard,
                          customCount: waitingCustom,
                          onTap: () => widget.onNavigateTab?.call(1),
                        ),
                        SplitStatCard(
                          title: 'تم التسليم',
                          icon: Icons.task_alt_rounded,
                          color: Colors.green.shade600,
                          standardCount: deliveredStandard,
                          customCount: deliveredCustom,
                          onTap: () => widget.onNavigateTab?.call(2),
                        ),
                        StatCard(
                          title: 'مخزن المعرض',
                          value: '$totalStock طقم جاهز',
                          icon: Icons.storefront_rounded,
                          color: AppTheme.primaryNavy,
                          onTap: () => widget.onNavigateTab?.call(4, managementSubTab: 0),
                        ),
                        SplitStatCard(
                          title: 'ورشة المنجد',
                          icon: Icons.chair_alt_rounded,
                          color: Colors.purple.shade400,
                          standardCount: upholstererRemainingSets,
                          customCount: upholstererRemainingIndividualPieces,
                          firstLabel: 'أطقم',
                          secondLabel: 'فردي',
                          footerText: 'إجمالي القطع: $upholstererRemainingPieces',
                          onTap: () => widget.onNavigateTab?.call(3),
                        ),
                        StatCard(
                          title: 'سجل العملاء',
                          value: '$customersCount عميل',
                          icon: Icons.people_alt_rounded,
                          color: Colors.teal.shade500,
                          onTap: () => widget.onNavigateTab?.call(4, managementSubTab: 2),
                        ),
                        StatCard(
                          title: 'قائمة الأصناف',
                          value: '$categoriesCount صنف',
                          icon: Icons.category_rounded,
                          color: Colors.brown.shade400,
                          onTap: () => widget.onNavigateTab?.call(4, managementSubTab: 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 76),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
