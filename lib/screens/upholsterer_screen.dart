import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../components/app_logo.dart';
import '../components/refreshable_empty_view.dart';
import '../components/searchable_picker.dart';
import '../core/app_events.dart';
import '../core/app_notification.dart';
import '../core/app_theme.dart';
import '../core/category_stock_helper.dart';
import '../core/db_helper.dart';
import '../core/order_delivery_helper.dart';
import '../core/stock_movement_helper.dart';
import '../core/upholsterer_statement_helper.dart';
import 'upholsterer_statement_screen.dart';

class UpholstererScreen extends StatefulWidget {
  const UpholstererScreen({super.key});
  @override
  State<UpholstererScreen> createState() => _UpholstererScreenState();
}

/// عنصر يمثل قطعة قيد التعديل داخل نافذة التنفيذ (تسليم أو استلام)
class _PieceInputItem {
  final String name;
  final int baseQty;
  final int maxAllowed; // -1 يعني بدون حد (في حالة التسليم للمنجد)
  final TextEditingController qtyCtrl;

  _PieceInputItem({
    required this.name,
    required this.baseQty,
    required int initialQty,
    this.maxAllowed = -1,
  }) : qtyCtrl = TextEditingController(text: '${initialQty >= 0 ? initialQty : 0}');

  void dispose() {
    qtyCtrl.dispose();
  }
}

class _UpholstererScreenState extends State<UpholstererScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _transactions = [];

  final Set<int> _expandedCategoryIds = {};
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
    AppEvents.instance.refreshNotifier.addListener(_load);
  }

  @override
  void dispose() {
    AppEvents.instance.refreshNotifier.removeListener(_load);
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// دمج تلقائي لأي دفعات مكررة تحمل نفس الصنف (أو نفس الاسم بعد التطبيع) في سجل واحد موحّد
  Future<void> _autoMergeDuplicateBatches(Database db) async {
    try {
      final allBatches = await db.query('upholsterer_batches', orderBy: 'id ASC');
      if (allBatches.length <= 1) return;

      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final b in allBatches) {
        final int catId = CategoryStockHelper.parseInt(b['category_id']);
        final String normName = SearchableSelectFormField.normalizeArabic(
          (b['category_name'] ?? '').toString(),
        );
        final String key = normName.isNotEmpty ? 'name:$normName' : 'id:$catId';
        grouped.putIfAbsent(key, () => []).add(b);
      }

      for (final entry in grouped.entries) {
        final list = entry.value;
        if (list.length <= 1) continue;

        final primary = list.first;
        final int primaryId = primary['id'] as int;

        final Map<String, Map<String, dynamic>> mergedPieces = {};
        String latestUphName = (primary['upholsterer_name'] ?? '').toString().trim();
        String latestSentDate = (primary['sent_date'] ?? '').toString();
        String? latestRecDate = primary['received_date']?.toString();

        for (final b in list) {
          final u = (b['upholsterer_name'] ?? '').toString().trim();
          if (u.isNotEmpty) latestUphName = u;
          final sd = (b['sent_date'] ?? '').toString();
          if (sd.compareTo(latestSentDate) > 0) latestSentDate = sd;
          final rd = b['received_date']?.toString();
          if (rd != null && rd.isNotEmpty && (latestRecDate == null || rd.compareTo(latestRecDate) > 0)) {
            latestRecDate = rd;
          }

          final pieces = UpholstererStatementHelper.parseBatchPieces(b);
          for (final p in pieces) {
            final pName = (p['name'] ?? '').toString().trim();
            if (pName.isEmpty) continue;
            final sQty = CategoryStockHelper.parseInt(p['sent_qty']);
            final rQty = CategoryStockHelper.parseInt(p['received_qty']);
            final bQty = math.max(1, CategoryStockHelper.parseInt(p['base_qty'], fallback: 1));

            if (mergedPieces.containsKey(pName)) {
              mergedPieces[pName]!['sent_qty'] =
                  CategoryStockHelper.parseInt(mergedPieces[pName]!['sent_qty']) + sQty;
              mergedPieces[pName]!['received_qty'] =
                  CategoryStockHelper.parseInt(mergedPieces[pName]!['received_qty']) + rQty;
              mergedPieces[pName]!['base_qty'] = bQty;
              if (p['sent_date'] != null) mergedPieces[pName]!['sent_date'] = p['sent_date'];
              if (p['received_date'] != null) mergedPieces[pName]!['received_date'] = p['received_date'];
            } else {
              mergedPieces[pName] = {
                'name': pName,
                'base_qty': bQty,
                'sent_qty': sQty,
                'received_qty': rQty,
                'sent_date': p['sent_date'] ?? b['sent_date'],
                'received_date': p['received_date'] ?? b['received_date'],
              };
            }
          }
        }

        final pieceList = mergedPieces.values.toList();
        int totalSent = 0;
        int totalRec = 0;
        for (final p in pieceList) {
          totalSent += CategoryStockHelper.parseInt(p['sent_qty']);
          totalRec += CategoryStockHelper.parseInt(p['received_qty']);
        }
        final sentSets = CategoryStockHelper.computeBreakdownFromPieces(
          pieceList,
          qtyKey: 'sent_qty',
        ).completeSets;
        final recSets = CategoryStockHelper.computeBreakdownFromPieces(
          pieceList,
          qtyKey: 'received_qty',
        ).completeSets;

        await db.transaction((txn) async {
          await txn.update(
            'upholsterer_batches',
            {
              'upholsterer_name': latestUphName,
              'total_sent': totalSent,
              'received_qty': totalRec,
              'sets_sent': sentSets,
              'sets_received': recSets,
              'sent_date': latestSentDate,
              'received_date': latestRecDate,
              'pieces_json': jsonEncode(pieceList),
            },
            where: 'id = ?',
            whereArgs: [primaryId],
          );

          for (int i = 1; i < list.length; i++) {
            final dupId = list[i]['id'] as int;
            await txn.update(
              'upholsterer_transactions',
              {'batch_id': primaryId},
              where: 'batch_id = ?',
              whereArgs: [dupId],
            );
            await txn.delete('upholsterer_batches', where: 'id = ?', whereArgs: [dupId]);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    final db = await DBHelper.instance.database;
    await CategoryStockHelper.syncDatabaseStock(db);
    await _autoMergeDuplicateBatches(db);

    final cats = await db.query('categories', orderBy: 'id DESC');
    final batches = await db.query('upholsterer_batches', orderBy: 'id DESC');
    List<Map<String, dynamic>> txs = [];
    try {
      txs = await db.query('upholsterer_transactions', orderBy: 'id DESC');
    } catch (_) {}

    if (mounted) {
      setState(() {
        _categories = cats;
        _batches = batches;
        _transactions = txs;
      });
    }
  }

  /// جلب الدفعة المدمجة الخاصة بصنف معين (إن وجدت) مع تجميع القطع على أساس مكونات الصنف الرسمية
  Map<String, dynamic>? _findMergedBatchForCategory(Map<String, dynamic> cat) {
    final int catId = CategoryStockHelper.parseInt(cat['id']);
    final String normCatName = SearchableSelectFormField.normalizeArabic(
      (cat['name'] ?? '').toString(),
    );
    for (final b in _batches) {
      if (CategoryStockHelper.parseInt(b['category_id']) == catId) return b;
      final bNorm = SearchableSelectFormField.normalizeArabic(
        (b['category_name'] ?? '').toString(),
      );
      if (normCatName.isNotEmpty && bNorm == normCatName) return b;
    }
    return null;
  }

  /// بناء قائمة القطع الكاملة لصنف لدى المنجد بدمج مكونات الصنف التأسيسية مع ما تم تسليمه واستلامه
  List<Map<String, dynamic>> _buildCategoryWorkshopPieces(
    Map<String, dynamic> cat,
    Map<String, dynamic>? batch,
  ) {
    final catComps = CategoryStockHelper.getMainComponents(cat['components_json']);
    final batchPieces = batch != null
        ? UpholstererStatementHelper.parseBatchPieces(batch)
        : const <Map<String, dynamic>>[];

    final Map<String, Map<String, dynamic>> byName = {};
    for (final c in catComps) {
      final name = (c['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final base = math.max(1, CategoryStockHelper.parseInt(c['base_qty'], fallback: 1));
      byName[name] = {
        'name': name,
        'base_qty': base,
        'sent_qty': 0,
        'received_qty': 0,
      };
    }

    for (final bp in batchPieces) {
      final name = (bp['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final sQty = CategoryStockHelper.parseInt(bp['sent_qty']);
      final rQty = CategoryStockHelper.parseInt(bp['received_qty']);
      final base = math.max(1, CategoryStockHelper.parseInt(bp['base_qty'], fallback: 1));
      if (byName.containsKey(name)) {
        byName[name]!['sent_qty'] = CategoryStockHelper.parseInt(byName[name]!['sent_qty']) + sQty;
        byName[name]!['received_qty'] = CategoryStockHelper.parseInt(byName[name]!['received_qty']) + rQty;
      } else {
        byName[name] = {
          'name': name,
          'base_qty': base,
          'sent_qty': sQty,
          'received_qty': rQty,
        };
      }
    }

    return byName.values.toList();
  }

  Set<String> _collectPreviousUpholsterers({int? categoryId}) {
    final names = <String>{};
    for (final b in _batches) {
      if (categoryId != null && CategoryStockHelper.parseInt(b['category_id']) != categoryId) {
        continue;
      }
      final n = (b['upholsterer_name'] ?? '').toString().trim();
      if (n.isNotEmpty && n != 'ورشة التنجيد' && n != 'ورشه التنجيد') names.add(n);
    }
    for (final t in _transactions) {
      if (categoryId != null && CategoryStockHelper.parseInt(t['category_id']) != categoryId) {
        continue;
      }
      final n = (t['upholsterer_name'] ?? '').toString().trim();
      if (n.isNotEmpty && n != 'ورشة التنجيد' && n != 'ورشه التنجيد') names.add(n);
    }
    return names;
  }

  /// نافذة عرض القطع الفردية المتبقية عند الضغط على أفاتار "فردي"
  void _showIndividualPiecesDialog({
    required String categoryName,
    required int completeSets,
    required int totalExcess,
    required List<Map<String, dynamic>> excessPieces,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.warningBg(ctx),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.chair_rounded, color: AppTheme.warningFg(ctx), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'القطع الفردية لدى المنجد',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(ctx),
                    ),
                  ),
                  Text(
                    '$categoryName (أطقم كاملة: $completeSets)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted(ctx)),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: totalExcess == 0
            ? const Text('لا توجد قطع فردية متبقية لهذا الصنف لدى المنجد حالياً.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: excessPieces.map((p) {
                    final qty = CategoryStockHelper.parseInt(p['rem_qty'], fallback: CategoryStockHelper.parseInt(p['excess_qty']));
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.subtleBg(ctx),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.borderColor(ctx)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            (p['name'] ?? '').toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppTheme.textPrimary(ctx),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD97706),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$qty قطعة فردية',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: AppTheme.royalGold,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  /// نافذة زر "تفاصيل" الخارجي على الكارت (تعرض سجل حركات الاستلام فقط في تاب استلام، أو التسليم فقط في تاب تسليم، مع التاريخ والأطقم والفردي)
  void _openCategoryMovementsModal({
    required Map<String, dynamic> category,
    required bool isReceiveTab,
  }) {
    final int catId = CategoryStockHelper.parseInt(category['id']);
    final String catName = (category['name'] ?? '').toString().trim();
    final String normName = SearchableSelectFormField.normalizeArabic(catName);
    final String targetType = isReceiveTab ? 'receive' : 'send';
    final catComps = CategoryStockHelper.getMainComponents(category['components_json']);

    final matchingTxs = _transactions.where((tx) {
      if ((tx['action_type'] ?? '').toString() != targetType) return false;
      if (CategoryStockHelper.parseInt(tx['category_id']) == catId) return true;
      return SearchableSelectFormField.normalizeArabic((tx['category_name'] ?? '').toString()) == normName;
    }).toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: AppTheme.modalSheetPadding(ctx),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isReceiveTab ? Icons.move_to_inbox_rounded : Icons.outbox_rounded,
                  color: isReceiveTab ? Colors.green.shade600 : AppTheme.accentOnSurface(ctx),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      isReceiveTab ? 'سجل الاستلام — $catName' : 'سجل التسليم — $catName',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(ctx),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (matchingTxs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  isReceiveTab
                      ? 'لا توجد حركات استلام مسجلة لصنف "$catName" حتى الآن.'
                      : 'لا توجد حركات تسليم مسجلة لصنف "$catName" حتى الآن.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted(ctx), fontSize: 14),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.58),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: matchingTxs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final tx = matchingTxs[idx];
                    final txPieces = CategoryStockHelper.parseComponents(tx['pieces_json']);
                    final summary = OrderDeliveryHelper.summarizeOrder(
                      orderComps: txPieces,
                      rawCategoryComps: catComps,
                    );
                    final label = CategoryStockHelper.formatSetsAndIndividual(
                      summary.sets,
                      summary.individualPieces,
                    );
                    final dateStr = StockMovementHelper.formatDateString12(
                      (tx['created_at'] ?? tx['action_date'] ?? '').toString(),
                    );
                    final uphName = (tx['upholsterer_name'] ?? '').toString().trim();

                    return Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: AppTheme.subtleBg(ctx),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isReceiveTab
                              ? AppTheme.successBorder(ctx)
                              : AppTheme.infoBorder(ctx),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    '📅 $dateStr',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary(ctx),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isReceiveTab ? Colors.green.shade700 : AppTheme.primaryNavy,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (uphName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'المنجد: $uphName • إجمالي القطع: ${summary.totalPieces} قطعة',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted(ctx)),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: txPieces.map((p) {
                              final pName = (p['name'] ?? '').toString();
                              final pQty = CategoryStockHelper.parseInt(p['qty']);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.cardBg(ctx),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.borderColor(ctx)),
                                ),
                                child: Text(
                                  '$pName: $pQty',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textBody(ctx),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// نافذة التنفيذ المباشرة عند الضغط على أي طقم (في تاب استلام أو تاب تسليم)
  /// بدون خانة اختيار اسم الطقم (لأنه مختار مباشرة من الكارت) + زر "تنفيذ"
  void _openActionModal({
    required Map<String, dynamic> category,
    required bool isReceive,
  }) {
    final String catName = (category['name'] ?? '').toString().trim();
    final batch = _findMergedBatchForCategory(category);
    final workshopPieces = _buildCategoryWorkshopPieces(category, batch);
    final catComps = CategoryStockHelper.getMainComponents(category['components_json']);

    final sentBreakdown = CategoryStockHelper.computeBreakdownFromPieces(
      workshopPieces,
      qtyKey: 'sent_qty',
      expectedComponentCount: catComps.length,
    );

    if (isReceive && sentBreakdown.totalPieces <= 0) {
      AppNotification.showInfo(
        context,
        'لا يوجد رصيد تم تسليمه من طقم "$catName" لدى المنجد لتعديل استلامه حالياً.',
      );
      return;
    }

    final int catId = CategoryStockHelper.parseInt(category['id']);
    final previousUpholsterersForCategory = _collectPreviousUpholsterers(categoryId: catId);
    final allPreviousUpholsterers = _collectPreviousUpholsterers();
    // في الاستلام: نفضل أسماء المنجدين الذين تم تسليم هذا الطقم لهم، وإن لم توجد فمن جميع المعاملات
    final relevantUpholsterers = isReceive && previousUpholsterersForCategory.isNotEmpty
        ? previousUpholsterersForCategory
        : (isReceive ? allPreviousUpholsterers : allPreviousUpholsterers);

    // ملء اسم المنجد المسجل سابقاً إن وجد
    final existingUph = batch != null ? (batch['upholsterer_name'] ?? '').toString().trim() : '';
    final uphNameCtrl = TextEditingController(
      text: existingUph.isNotEmpty && existingUph != 'ورشة التنجيد' && existingUph != 'ورشه التنجيد'
          ? existingUph
          : '',
    );
    String? uphError;

    final remBreak = CategoryStockHelper.computeBreakdownFromPieces(
      workshopPieces,
      qtyKey: 'sent_qty',
      subtractKey: 'received_qty',
      expectedComponentCount: catComps.length,
    );

    // عدد الأطقم والقطع الافتراضية عند فتح النافذة هو صفر بناءً على طلب المستخدم
    int setsCount = 0;
    final setsCtrl = TextEditingController(text: '0');

    final List<_PieceInputItem> pieceItems = workshopPieces.map((wp) {
      final pName = (wp['name'] ?? '').toString();
      final baseQ = math.max(1, CategoryStockHelper.parseInt(wp['base_qty'], fallback: 1));
      final sentQ = CategoryStockHelper.parseInt(wp['sent_qty']);
      final recQ = CategoryStockHelper.parseInt(wp['received_qty']);
      final remQ = math.max(0, sentQ - recQ);

      return _PieceInputItem(
        name: pName,
        baseQty: baseQ,
        initialQty: 0,
        maxAllowed: isReceive ? remQ : -1,
      );
    }).toList();

    bool isSaving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void syncSets(int n) {
            int clamped = n < 0 ? 0 : n;
            if (isReceive && clamped > remBreak.completeSets) {
              clamped = remBreak.completeSets;
            }
            setsCount = clamped;
            setsCtrl.text = '$setsCount';
            for (final p in pieceItems) {
              int target = setsCount * p.baseQty;
              if (isReceive && p.maxAllowed >= 0 && target > p.maxAllowed) {
                target = p.maxAllowed;
              }
              p.qtyCtrl.text = '$target';
            }
          }

          // حساب المعاينة الحية للأطقم والقطع الفردية
          final previewPieces = pieceItems.map((p) {
            final q = math.max(0, int.tryParse(p.qtyCtrl.text.trim()) ?? 0);
            return {'name': p.name, 'base_qty': p.baseQty, 'qty': q};
          }).toList();
          final liveBreak = CategoryStockHelper.computeBreakdownFromPieces(
            previewPieces,
            qtyKey: 'qty',
            expectedComponentCount: catComps.length,
          );
          final liveText = CategoryStockHelper.formatSetsAndIndividual(
            liveBreak.completeSets,
            liveBreak.individualPieces,
          );

          return Padding(
            padding: AppTheme.modalSheetPadding(ctx),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: isReceive ? Colors.green.withValues(alpha: 0.14) : AppTheme.primaryNavy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isReceive ? Icons.move_to_inbox_rounded : Icons.outbox_rounded,
                          color: isReceive ? Colors.green.shade700 : AppTheme.primaryNavy,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isReceive ? 'استلام من المنجد' : 'تسليم للمنجد',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: isReceive ? Colors.green.shade800 : AppTheme.primaryNavy,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'طقم: $catName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textMuted(ctx),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: isSaving ? null : () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  if (isReceive) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppTheme.warningBg(ctx),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.warningBorder(ctx)),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          'المسلّم لدى المنجد: ${CategoryStockHelper.formatSetsAndIndividual(sentBreakdown.completeSets, sentBreakdown.individualPieces)} (${sentBreakdown.totalPieces} قطعة)',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.warningFg(ctx),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // اسم المنجد (إجباري)
                  TextField(
                    controller: uphNameCtrl,
                    onChanged: (_) {
                      if (uphError != null) {
                        setModalState(() => uphError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: isReceive ? 'اسم المنجد المستلم منه *' : 'اسم المنجد / الورشة *',
                      hintText: isReceive
                          ? (relevantUpholsterers.isNotEmpty
                              ? 'اختر اسم المنجد من القائمة أدناه أو اكتب اسمه'
                              : 'اكتب اسم المنجد المستلم منه')
                          : 'اكتب اسم المنجد أو اختر من المسجلين سابقاً',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      errorText: uphError,
                      helperText: isReceive
                          ? 'يجب تحديد اسم المنجد المستلم منه'
                          : 'يجب كتابة أو اختيار اسم المنجد لإتمام التسليم',
                    ),
                  ),
                  if (relevantUpholsterers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.history_rounded, size: 14, color: AppTheme.textMuted(ctx)),
                        const SizedBox(width: 4),
                        Text(
                          isReceive ? 'منجدون تم التسليم لهم سابقاً (اضغط للاختيار):' : 'منجدون مسجلون سابقاً (اضغط للاختيار):',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.textMuted(ctx)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: relevantUpholsterers.map((name) {
                        final isSelected = uphNameCtrl.text.trim() == name;
                        return ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.white : AppTheme.textPrimary(ctx),
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: isReceive ? Colors.green.shade700 : AppTheme.primaryNavy,
                          onSelected: (selected) {
                            setModalState(() {
                              uphNameCtrl.text = selected ? name : '';
                              uphError = null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // عداد عدد الأطقم الكاملة
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.subtleBg(ctx),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor(ctx)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isReceive ? 'عدد الأطقم المستلمة:' : 'عدد الأطقم المسلّمة:',
                                maxLines: 1,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppTheme.textPrimary(ctx),
                                ),
                              ),
                              if (isReceive)
                                Text(
                                  'أقصى عدد أطقم مكتملة متاحة للاستلام: ${remBreak.completeSets}',
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted(ctx)),
                                ),
                            ],
                          ),
                        ),
                        Material(
                          color: Colors.red.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: setsCount > 0 ? () => setModalState(() => syncSets(setsCount - 1)) : null,
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.remove, color: Colors.red, size: 22),
                            ),
                          ),
                        ),
                        Container(
                          width: 54,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          child: TextField(
                            controller: setsCtrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(ctx),
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            ),
                            onChanged: (val) {
                              final n = int.tryParse(val.trim());
                              if (n != null && n >= 0) {
                                setModalState(() => syncSets(n));
                              }
                            },
                          ),
                        ),
                        Material(
                          color: Colors.green.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: (!isReceive || setsCount < sentBreakdown.completeSets)
                                ? () => setModalState(() => syncSets(setsCount + 1))
                                : null,
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.add, color: Colors.green, size: 22),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // قائمة القطع الفردية
                  Text(
                    'القطع (يمكنك تعديل أي قطعة فردياً):',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: AppTheme.textPrimary(ctx),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...pieceItems.map((piece) {
                    final curQ = int.tryParse(piece.qtyCtrl.text.trim()) ?? 0;
                    final bool canInc = !isReceive || piece.maxAllowed < 0 || curQ < piece.maxAllowed;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg(ctx),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.borderColor(ctx)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.chair_rounded, color: AppTheme.accentOnSurface(ctx), size: 19),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    piece.name,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                      color: AppTheme.textPrimary(ctx),
                                    ),
                                  ),
                                ),
                                Text(
                                  isReceive
                                      ? 'متبقي لديه: ${piece.maxAllowed} • (${piece.baseQty} بالطقم)'
                                      : 'النسبة: ${piece.baseQty} في الطقم الواحد',
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted(ctx)),
                                ),
                              ],
                            ),
                          ),
                          Material(
                            color: Colors.red.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: curQ > 0
                                  ? () => setModalState(() => piece.qtyCtrl.text = '${curQ - 1}')
                                  : null,
                              child: const Padding(
                                padding: EdgeInsets.all(7.0),
                                child: Icon(Icons.remove, color: Colors.red, size: 20),
                              ),
                            ),
                          ),
                          Container(
                            width: 48,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            child: TextField(
                              controller: piece.qtyCtrl,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15.5,
                                color: AppTheme.textPrimary(ctx),
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              ),
                              onChanged: (val) {
                                final parsed = int.tryParse(val.trim()) ?? 0;
                                if (isReceive && piece.maxAllowed >= 0 && parsed > piece.maxAllowed) {
                                  piece.qtyCtrl.text = '${piece.maxAllowed}';
                                }
                                setModalState(() {});
                              },
                            ),
                          ),
                          Material(
                            color: Colors.green.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: canInc
                                  ? () => setModalState(() => piece.qtyCtrl.text = '${curQ + 1}')
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(7.0),
                                child: Icon(
                                  Icons.add,
                                  color: canInc ? Colors.green : Colors.grey,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: isReceive ? AppTheme.successBg(ctx) : AppTheme.infoBg(ctx),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isReceive ? AppTheme.successBorder(ctx) : AppTheme.infoBorder(ctx),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isReceive
                            ? 'المحدد للاستلام: $liveText (${liveBreak.totalPieces} قطعة)'
                            : 'المحدد للتسليم: $liveText (${liveBreak.totalPieces} قطعة)',
                        maxLines: 1,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isReceive ? AppTheme.successFg(ctx) : AppTheme.infoFg(ctx),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // زر التنفيذ الرئيسي
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isReceive ? Colors.green.shade700 : AppTheme.primaryNavy,
                      foregroundColor: isReceive ? Colors.white : AppTheme.brightGold,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isSaving
                        ? null
                        : () async {
                            final rawUphName = uphNameCtrl.text.trim();
                            if (rawUphName.isEmpty) {
                              setModalState(() {
                                uphError = isReceive
                                    ? 'برجاء اختيار أو كتابة اسم المنجد المستلم منه'
                                    : 'برجاء كتابة أو اختيار اسم المنجد أولاً';
                              });
                              AppNotification.showError(
                                context,
                                isReceive
                                    ? 'يجب تحديد اسم المنجد المستلم منه للمتابعة'
                                    : 'لا يمكن إتمام التسليم بدون إدخال اسم المنجد / الورشة',
                              );
                              return;
                            }

                            setModalState(() {
                              isSaving = true;
                              uphError = null;
                            });
                            final uphName = rawUphName;

                            final selectedPieces = <Map<String, dynamic>>[];
                            for (final p in pieceItems) {
                              int q = math.max(0, int.tryParse(p.qtyCtrl.text.trim()) ?? 0);
                              if (isReceive && p.maxAllowed >= 0 && q > p.maxAllowed) {
                                q = p.maxAllowed;
                              }
                              selectedPieces.add({
                                'name': p.name,
                                'qty': q,
                                'base_qty': p.baseQty,
                              });
                            }

                            final ok = isReceive
                                ? await _executeReceive(
                                    category: category,
                                    existingBatch: batch,
                                    upholstererName: uphName,
                                    receivedPieces: selectedPieces,
                                  )
                                : await _executeSend(
                                    category: category,
                                    existingBatch: batch,
                                    upholstererName: uphName,
                                    sentPieces: selectedPieces,
                                  );

                            if (ok && ctx.mounted) {
                              Navigator.pop(ctx);
                            } else if (ctx.mounted) {
                              setModalState(() => isSaving = false);
                            }
                          },
                    icon: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_rounded),
                    label: Text(
                      isReceive ? 'تنفيذ الاستلام وإضافة للمخزن' : 'تنفيذ التسليم للمنجد',
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      uphNameCtrl.dispose();
      setsCtrl.dispose();
      for (final p in pieceItems) {
        p.dispose();
      }
    });
  }

  /// تنفيذ عملية التسليم للمنجد مع الدمج التلقائي في سجل الصنف وتسجيلها في كشف الحساب والتفاصيل
  Future<bool> _executeSend({
    required Map<String, dynamic> category,
    required Map<String, dynamic>? existingBatch,
    required String upholstererName,
    required List<Map<String, dynamic>> sentPieces,
  }) async {
    try {
      final db = await DBHelper.instance.database;
      final int catId = CategoryStockHelper.parseInt(category['id']);
      final String catName = (category['name'] ?? '').toString().trim();
      final today = UpholstererStatementHelper.formatIsoDate(DateTime.now());
      final now12 = StockMovementHelper.formatDateTime12(DateTime.now());
      final catComps = CategoryStockHelper.getMainComponents(category['components_json']);

      final sendBreak = CategoryStockHelper.computeBreakdownFromPieces(
        sentPieces,
        qtyKey: 'qty',
        expectedComponentCount: catComps.length,
      );

      final List<Map<String, dynamic>> mergedPieces =
          _buildCategoryWorkshopPieces(category, existingBatch);

      final nonZeroSentPieces = sentPieces
          .where((sp) => CategoryStockHelper.parseInt(sp['qty']) > 0)
          .toList();

      for (final sp in nonZeroSentPieces) {
        final pName = (sp['name'] ?? '').toString().trim();
        final addQty = CategoryStockHelper.parseInt(sp['qty']);
        final bQty = math.max(1, CategoryStockHelper.parseInt(sp['base_qty'], fallback: 1));
        final idx = mergedPieces.indexWhere((m) => (m['name'] ?? '').toString().trim() == pName);
        if (idx != -1) {
          final curSent = CategoryStockHelper.parseInt(mergedPieces[idx]['sent_qty']);
          mergedPieces[idx]['sent_qty'] = curSent + addQty;
          mergedPieces[idx]['sent_date'] = today;
        } else {
          mergedPieces.add({
            'name': pName,
            'base_qty': bQty,
            'sent_qty': addQty,
            'received_qty': 0,
            'sent_date': today,
            'received_date': null,
          });
        }
      }

      int totalSent = 0;
      int totalRec = 0;
      for (final mp in mergedPieces) {
        totalSent += CategoryStockHelper.parseInt(mp['sent_qty']);
        totalRec += CategoryStockHelper.parseInt(mp['received_qty']);
      }
      final mainMergedForSend = CategoryStockHelper.getMainComponents(mergedPieces);
      final totalSentSets = CategoryStockHelper.computeBreakdownFromPieces(
        mainMergedForSend,
        qtyKey: 'sent_qty',
        expectedComponentCount: catComps.length,
      ).completeSets;
      final totalRecSets = CategoryStockHelper.computeBreakdownFromPieces(
        mainMergedForSend,
        qtyKey: 'received_qty',
        expectedComponentCount: catComps.length,
      ).completeSets;

      int batchId = 0;
      await db.transaction((txn) async {
        if (existingBatch != null) {
          batchId = existingBatch['id'] as int;
          await txn.update(
            'upholsterer_batches',
            {
              'upholsterer_name': upholstererName,
              'total_sent': totalSent,
              'received_qty': totalRec,
              'sets_sent': totalSentSets,
              'sets_received': totalRecSets,
              'sent_date': today,
              'pieces_json': jsonEncode(mergedPieces),
            },
            where: 'id = ?',
            whereArgs: [batchId],
          );
        } else {
          batchId = await txn.insert('upholsterer_batches', {
            'upholsterer_name': upholstererName,
            'category_id': catId,
            'category_name': catName,
            'piece_name': sentPieces.first['name'],
            'total_sent': totalSent,
            'received_qty': totalRec,
            'sent_date': today,
            'received_date': null,
            'sets_sent': totalSentSets,
            'sets_received': totalRecSets,
            'pieces_json': jsonEncode(mergedPieces),
          });
        }

        await txn.insert('upholsterer_transactions', {
          'batch_id': batchId,
          'upholsterer_name': upholstererName,
          'category_id': catId,
          'category_name': catName,
          'action_type': 'send',
          'sets_count': sendBreak.completeSets,
          'pieces_json': jsonEncode(nonZeroSentPieces.isNotEmpty ? nonZeroSentPieces : sentPieces),
          'total_pieces': sendBreak.totalPieces,
          'action_date': today,
          'created_at': now12,
        });
      });

      await StockMovementHelper.logMovement(
        categoryId: catId,
        categoryName: catName,
        movementType: 'upholsterer_out',
        qtyChange: 0,
        stockAfter: CategoryStockHelper.parseInt(category['stock_qty']),
        notes: 'تسليم للمنجد: $uphNamePlaceholder (${CategoryStockHelper.formatSetsAndIndividual(sendBreak.completeSets, sendBreak.individualPieces)})'
            .replaceFirst(uphNamePlaceholder, upholstererName),
      );

      AppEvents.instance.notifyAll();
      if (mounted) {
        AppNotification.showSuccess(
          context,
          'تم تنفيذ تسليم ${CategoryStockHelper.formatSetsAndIndividual(sendBreak.completeSets, sendBreak.individualPieces)} من "$catName" بنجاح',
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        AppNotification.showError(context, 'تعذر تنفيذ التسليم: $e');
      }
      return false;
    }
  }

  static const String uphNamePlaceholder = '__UPH__';

  /// تنفيذ عملية الاستلام من المنجد مع إضافة القطع فوراً لمخزن المعرض وتسجيلها في كشف الحساب والتفاصيل
  Future<bool> _executeReceive({
    required Map<String, dynamic> category,
    required Map<String, dynamic>? existingBatch,
    required String upholstererName,
    required List<Map<String, dynamic>> receivedPieces,
  }) async {
    if (existingBatch == null) return false;
    try {
      final db = await DBHelper.instance.database;
      final int catId = CategoryStockHelper.parseInt(category['id']);
      final String catName = (category['name'] ?? '').toString().trim();
      final int batchId = existingBatch['id'] as int;
      final today = UpholstererStatementHelper.formatIsoDate(DateTime.now());
      final now12 = StockMovementHelper.formatDateTime12(DateTime.now());
      final catComps = CategoryStockHelper.getMainComponents(category['components_json']);

      final recBreak = CategoryStockHelper.computeBreakdownFromPieces(
        receivedPieces,
        qtyKey: 'qty',
        expectedComponentCount: catComps.length,
      );

      final mergedPieces = _buildCategoryWorkshopPieces(category, existingBatch);
      final List<Map<String, dynamic>> receiveDeltas = [];

      final nonZeroReceivedPieces = receivedPieces
          .where((rp) => CategoryStockHelper.parseInt(rp['qty']) > 0)
          .toList();

      for (final rp in nonZeroReceivedPieces) {
        final pName = (rp['name'] ?? '').toString().trim();
        final addRec = CategoryStockHelper.parseInt(rp['qty']);
        final bQty = math.max(1, CategoryStockHelper.parseInt(rp['base_qty'], fallback: 1));
        final idx = mergedPieces.indexWhere((m) => (m['name'] ?? '').toString().trim() == pName);
        if (idx != -1) {
          final maxSent = CategoryStockHelper.parseInt(mergedPieces[idx]['sent_qty']);
          final curRec = CategoryStockHelper.parseInt(mergedPieces[idx]['received_qty']);
          final clampedNewRec = maxSent > 0 ? math.min(maxSent, curRec + addRec) : (curRec + addRec);
          final int delta = math.max(0, clampedNewRec - curRec);
          if (delta > 0) {
            mergedPieces[idx]['received_qty'] = clampedNewRec;
            mergedPieces[idx]['received_date'] = today;
            receiveDeltas.add({
              'name': pName,
              'base_qty': bQty,
              'delta': delta,
              'qty': delta,
            });
          }
        }
      }



      int totalSent = 0;
      int totalRec = 0;
      for (final mp in mergedPieces) {
        totalSent += CategoryStockHelper.parseInt(mp['sent_qty']);
        totalRec += CategoryStockHelper.parseInt(mp['received_qty']);
      }
      final totalRecSets = CategoryStockHelper.computeBreakdownFromPieces(
        CategoryStockHelper.getMainComponents(mergedPieces),
        qtyKey: 'received_qty',
        expectedComponentCount: catComps.length,
      ).completeSets;

      int newStockSets = CategoryStockHelper.parseInt(category['stock_qty']);
      int oldStockSets = newStockSets;

      await db.transaction((txn) async {
        await txn.update(
          'upholsterer_batches',
          {
            'upholsterer_name': upholstererName,
            'total_sent': totalSent,
            'received_qty': totalRec,
            'sets_received': totalRecSets,
            'received_date': today,
            'pieces_json': jsonEncode(mergedPieces),
          },
          where: 'id = ?',
          whereArgs: [batchId],
        );

        await txn.insert('upholsterer_transactions', {
          'batch_id': batchId,
          'upholsterer_name': upholstererName,
          'category_id': catId,
          'category_name': catName,
          'action_type': 'receive',
          'sets_count': recBreak.completeSets,
          'pieces_json': jsonEncode(nonZeroReceivedPieces.isNotEmpty ? nonZeroReceivedPieces : receivedPieces),
          'total_pieces': recBreak.totalPieces,
          'action_date': today,
          'created_at': now12,
        });

        final catRows = await txn.query('categories', where: 'id = ?', whereArgs: [catId]);
        if (catRows.isNotEmpty) {
          oldStockSets = CategoryStockHelper.parseInt(catRows.first['stock_qty']);
          final updatedCatComps = CategoryStockHelper.parseComponents(catRows.first['components_json']);
          for (final rd in receiveDeltas) {
            final pName = (rd['name'] ?? '').toString().trim();
            final delta = rd['delta'] as int;
            final bQ = math.max(1, CategoryStockHelper.parseInt(rd['base_qty'], fallback: 1));
            final cIdx = updatedCatComps.indexWhere((c) => (c['name'] ?? '').toString().trim() == pName);
            if (cIdx != -1) {
              updatedCatComps[cIdx]['qty'] = math.max(0, CategoryStockHelper.parseInt(updatedCatComps[cIdx]['qty']) + delta);
            } else if (delta > 0) {
              updatedCatComps.add({'name': pName, 'base_qty': bQ, 'qty': delta});
            }
          }
          newStockSets = CategoryStockHelper.computeBreakdownFromPieces(
            CategoryStockHelper.getMainComponents(updatedCatComps),
          ).completeSets;
          await txn.update(
            'categories',
            {
              'stock_qty': newStockSets,
              'components_json': jsonEncode(updatedCatComps),
            },
            where: 'id = ?',
            whereArgs: [catId],
          );
        }
      });

      final nonZeroDeltas = receiveDeltas.where((rd) => (rd['delta'] as int) != 0).toList();
      if (nonZeroDeltas.isNotEmpty) {
        await StockMovementHelper.logMovement(
          categoryId: catId,
          categoryName: catName,
          movementType: 'upholsterer_in',
          qtyChange: newStockSets - oldStockSets,
          stockAfter: newStockSets,
          piecesDelta: nonZeroDeltas.map((rd) => {
            'name': rd['name'],
            'delta': rd['delta'],
          }).toList(),
          notes:
              'استلام / تعديل مدخلات من المنجد ($upholstererName): ${CategoryStockHelper.formatSetsAndIndividual(recBreak.completeSets, recBreak.individualPieces)}',
        );
      }

      AppEvents.instance.notifyAll();
      if (mounted) {
        AppNotification.showSuccess(
          context,
          'تم استلام ${CategoryStockHelper.formatSetsAndIndividual(recBreak.completeSets, recBreak.individualPieces)} من "$catName" وإضافتها للمخزن',
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        AppNotification.showError(context, 'تعذر تنفيذ الاستلام: $e');
      }
      return false;
    }
  }

  Widget _buildCategoryList({required bool isReceiveTab}) {
    final normQuery = SearchableSelectFormField.normalizeArabic(_searchQuery);
    final filteredCats = _categories.where((cat) {
      if (normQuery.isEmpty) return true;
      final name = SearchableSelectFormField.normalizeArabic((cat['name'] ?? '').toString());
      return name.contains(normQuery);
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: filteredCats.isEmpty
          ? const RefreshableEmptyView(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'لا توجد أصناف مسجلة بعد.\nأضف الأصناف من تبويب (المخزن ➔ الأصناف ومكوناتها) لتظهر هنا تلقائياً.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15),
                ),
              ),
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              itemCount: filteredCats.length,
              itemBuilder: (ctx, idx) {
                final cat = filteredCats[idx];
                final int catId = CategoryStockHelper.parseInt(cat['id']);
                final String catName = (cat['name'] ?? '').toString().trim();
                final bool isExpanded = _expandedCategoryIds.contains(catId);
                final batch = _findMergedBatchForCategory(cat);
                final workshopPieces = _buildCategoryWorkshopPieces(cat, batch);
                final catComps = CategoryStockHelper.getMainComponents(cat['components_json']);

                final sentBreak = CategoryStockHelper.computeBreakdownFromPieces(
                  workshopPieces,
                  qtyKey: 'sent_qty',
                  expectedComponentCount: catComps.length,
                );
                final recBreak = CategoryStockHelper.computeBreakdownFromPieces(
                  workshopPieces,
                  qtyKey: 'received_qty',
                  expectedComponentCount: catComps.length,
                );
                final remBreak = CategoryStockHelper.computeBreakdownFromPieces(
                  workshopPieces,
                  qtyKey: 'sent_qty',
                  subtractKey: 'received_qty',
                  expectedComponentCount: catComps.length,
                );

                final bool hasRemaining = remBreak.totalPieces > 0;
                final String remText = hasRemaining
                    ? 'متبقي: ${CategoryStockHelper.formatSetsAndIndividual(remBreak.completeSets, remBreak.individualPieces)}'
                    : 'لا يوجد رصيد لديه';

                return Card(
                  elevation: isExpanded ? 3 : 1.5,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isExpanded
                          ? AppTheme.brightGold
                          : (hasRemaining ? AppTheme.royalGold.withValues(alpha: 0.45) : AppTheme.borderColor(context)),
                      width: isExpanded ? 1.5 : 1.0,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openActionModal(category: cat, isReceive: isReceiveTab),
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              // 1. أفاتار الأطقم الكاملة المتبقية لدى المنجد
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: AppTheme.setsAvatarGradient(
                                      context,
                                      hasValue: remBreak.completeSets > 0,
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border: AppTheme.isDark(context)
                                      ? Border.all(color: AppTheme.brightGold.withValues(alpha: 0.35))
                                      : null,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'الأطقم',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: AppTheme.brightGold,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${remBreak.completeSets}',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),

                              // 2. أفاتار الفردي المتبقي لدى المنجد (قابل للضغط لعرض تفاصيل القطع)
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => _showIndividualPiecesDialog(
                                    categoryName: catName,
                                    completeSets: remBreak.completeSets,
                                    totalExcess: remBreak.individualPieces,
                                    excessPieces: remBreak.excessPieces,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: AppTheme.individualAvatarGradient(
                                          context,
                                          hasValue: remBreak.individualPieces > 0,
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'فردي',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '${remBreak.individualPieces}',
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // 3. اسم الطقم كاملاً بدون قص + الحالة في سطر واحد محكم
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: AlignmentDirectional.centerStart,
                                      child: Text(
                                        catName,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textPrimary(context),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: AlignmentDirectional.centerStart,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: hasRemaining
                                              ? AppTheme.warningBg(context)
                                              : AppTheme.successBg(context),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: hasRemaining
                                                ? AppTheme.warningBorder(context)
                                                : AppTheme.successBorder(context),
                                          ),
                                        ),
                                        child: Text(
                                          remText,
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: hasRemaining
                                                ? AppTheme.warningFg(context)
                                                : AppTheme.successFg(context),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),

                              // 4. زر "تفاصيل" خارجي يعرض سجل حركات هذا التاب بالتاريخ
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.accentOnSurface(context),
                                  side: BorderSide(
                                    color: AppTheme.accentOnSurface(context).withValues(alpha: 0.6),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                                ),
                                onPressed: () => _openCategoryMovementsModal(
                                  category: cat,
                                  isReceiveTab: isReceiveTab,
                                ),
                                child: const Text(
                                  'تفاصيل',
                                  maxLines: 1,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 2),



                              // 5. سهم التوسيع لعرض ملخص التسليم لهذا الطقم
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                tooltip: isExpanded ? 'طي الملخص' : 'عرض ملخص التسليم',
                                icon: Icon(
                                  isExpanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: AppTheme.textMuted(context),
                                  size: 24,
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (isExpanded) {
                                      _expandedCategoryIds.remove(catId);
                                    } else {
                                      _expandedCategoryIds.add(catId);
                                    }
                                  });
                                },
                              ),
                            ],
                          ),

                          // ملخص التسليم والاستلام عند توسع الكارت
                          if (isExpanded) ...[
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.subtleBg(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.borderColor(context)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _SummaryMiniCol(
                                      title: 'المسلّم للمنجد',
                                      value: CategoryStockHelper.formatSetsAndIndividual(
                                        sentBreak.completeSets,
                                        sentBreak.individualPieces,
                                      ),
                                      piecesText: '${sentBreak.totalPieces} قطعة',
                                      color: AppTheme.infoFg(context),
                                    ),
                                  ),
                                  Container(width: 1, height: 38, color: AppTheme.borderColor(context)),
                                  Expanded(
                                    child: _SummaryMiniCol(
                                      title: 'المستلَم منه',
                                      value: CategoryStockHelper.formatSetsAndIndividual(
                                        recBreak.completeSets,
                                        recBreak.individualPieces,
                                      ),
                                      piecesText: '${recBreak.totalPieces} قطعة',
                                      color: AppTheme.successFg(context),
                                    ),
                                  ),
                                  Container(width: 1, height: 38, color: AppTheme.borderColor(context)),
                                  Expanded(
                                    child: _SummaryMiniCol(
                                      title: 'المتبقي لديه',
                                      value: CategoryStockHelper.formatSetsAndIndividual(
                                        remBreak.completeSets,
                                        remBreak.individualPieces,
                                      ),
                                      piecesText: '${remBreak.totalPieces} قطعة',
                                      color: AppTheme.warningFg(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: workshopPieces.map((wp) {
                                final pName = (wp['name'] ?? '').toString();
                                final pSent = CategoryStockHelper.parseInt(wp['sent_qty']);
                                final pRec = CategoryStockHelper.parseInt(wp['received_qty']);
                                final pRem = math.max(0, pSent - pRec);
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: pRem > 0 ? AppTheme.warningBg(context) : AppTheme.cardBg(context),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: pRem > 0 ? AppTheme.warningBorder(context) : AppTheme.borderColor(context),
                                    ),
                                  ),
                                  child: Text(
                                    '$pName: سُلّم $pSent | استُلم $pRec | باقي $pRem',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: pRem > 0 ? AppTheme.warningFg(context) : AppTheme.textMuted(context),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isReceiveTab ? Colors.green.shade700 : AppTheme.primaryNavy,
                                  foregroundColor: isReceiveTab ? Colors.white : AppTheme.royalGold,
                                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.edit_rounded, size: 17),
                                label: Text(
                                  isReceiveTab ? 'تعديل مدخلات الاستلام لهذا الطقم' : 'تعديل مدخلات التسليم لهذا الطقم',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                ),
                                onPressed: () => _openActionModal(
                                  category: cat,
                                  isReceive: isReceiveTab,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitleWithLogo(title: 'الأصناف لدى المنجد'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: AppTheme.royalGold,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const UpholstererStatementScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.receipt_long_rounded, size: 17),
              label: const Text(
                'كشف حساب',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.move_to_inbox_rounded), text: 'استلام'),
            Tab(icon: Icon(Icons.outbox_rounded), text: 'تسليم'),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            color: AppTheme.filterBarBg(context),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'بحث باسم الطقم / الصنف...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchCtrl.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCategoryList(isReceiveTab: true),
                _buildCategoryList(isReceiveTab: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMiniCol extends StatelessWidget {
  final String title;
  final String value;
  final String piecesText;
  final Color color;

  const _SummaryMiniCol({
    required this.title,
    required this.value,
    required this.piecesText,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            maxLines: 1,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary(context),
            ),
          ),
        ),
        Text(
          piecesText,
          maxLines: 1,
          style: TextStyle(fontSize: 10, color: AppTheme.textMuted(context)),
        ),
      ],
    );
  }
}
