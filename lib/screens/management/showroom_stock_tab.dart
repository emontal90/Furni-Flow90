import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../../components/refreshable_empty_view.dart';
import '../../core/app_events.dart';
import '../../core/app_notification.dart';
import '../../core/app_theme.dart';
import '../../core/category_stock_helper.dart';
import '../../core/db_helper.dart';
import '../../core/stock_movement_helper.dart';

class ShowroomStockTab extends StatefulWidget {
  const ShowroomStockTab({super.key});
  @override
  State<ShowroomStockTab> createState() => _ShowroomStockTabState();
}

class _PieceEditItem {
  final String name;
  final int baseQty;
  final TextEditingController qtyCtrl;

  _PieceEditItem({required this.name, required this.baseQty, required int qty})
      : qtyCtrl = TextEditingController(text: qty.toString());

  void dispose() {
    qtyCtrl.dispose();
  }
}

class _ShowroomStockTabState extends State<ShowroomStockTab> {
  List<Map<String, dynamic>> _categories = [];
  final Set<int> _expandedCategoryIds = {};

  // فلتر تاريخ استعادة وضع المخزن في نهاية يوم محدد
  DateTime? _selectedHistoryDate;
  bool _isLoadingHistory = false;
  List<Map<String, dynamic>>? _historicalCategories;

  @override
  void initState() {
    super.initState();
    _load();
    AppEvents.instance.refreshNotifier.addListener(_load);
  }

  @override
  void dispose() {
    AppEvents.instance.refreshNotifier.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final db = await DBHelper.instance.database;
    await CategoryStockHelper.syncDatabaseStock(db);
    final data = await db.query('categories', orderBy: 'id DESC');
    if (mounted) {
      setState(() => _categories = data);
      if (_selectedHistoryDate != null) {
        _applyDateFilter(_selectedHistoryDate!);
      }
    }
  }

  Future<void> _applyDateFilter(DateTime dt) async {
    setState(() => _isLoadingHistory = true);
    final hist = await StockMovementHelper.getStockAtEndOfDate(
      currentCategories: _categories,
      targetDate: dt,
    );
    if (mounted) {
      setState(() {
        _selectedHistoryDate = dt;
        _historicalCategories = hist;
        _isLoadingHistory = false;
      });
    }
  }

  void _clearDateFilter() {
    setState(() {
      _selectedHistoryDate = null;
      _historicalCategories = null;
    });
  }

  Future<void> _pickHistoryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedHistoryDate ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'اختر التاريخ لاستعراض وضع المخزن في نهايته',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryNavy,
              onPrimary: AppTheme.royalGold,
              surface: Colors.white,
              onSurface: AppTheme.primaryNavy,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      await _applyDateFilter(picked);
    }
  }

  // نافذة تأكيد حذف صنف بالكامل
  Future<void> _confirmDeleteCategory(
    BuildContext callerCtx,
    Map<String, dynamic> cat, {
    BuildContext? modalContext,
  }) async {
    final bool? confirm = await showDialog<bool>(
      context: callerCtx,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red, size: 30),
            SizedBox(width: 8),
            Text('تأكيد حذف الصنف', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف طقم "${cat['name']}" بالكامل من المخزن وقاعدة البيانات؟\nلن يمكن التراجع عن هذا الإجراء.',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('نعم، حذف الصنف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = await DBHelper.instance.database;
      await db.delete('categories', where: 'id = ?', whereArgs: [cat['id']]);
      AppEvents.instance.notifyAll();
      if (modalContext != null && modalContext.mounted) {
        Navigator.pop(modalContext);
      }
      if (!mounted) return;
      AppNotification.showError(context, 'تم حذف طقم "${cat['name']}" بنجاح');
    }
  }

  // ---------------------------------------------------------------------------
  // نافذة تعديل رصيد المخزن (مضاعفة أعداد القطع حسب نسبة كل قطعة بالطقم)
  // ---------------------------------------------------------------------------
  /// نافذة عرض تفاصيل القطع الفردية الزائدة عند الضغط على أفاتار الرصيد الفردي
  void _showIndividualPiecesDialog({
    required BuildContext context,
    required String setName,
    required int completeSets,
    required int totalExcess,
    required List<Map<String, dynamic>> excessPieces,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.chair_rounded, color: Color(0xFFD97706), size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'تفاصيل الرصيد الفردي',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryNavy),
                  ),
                  Text(
                    'طقم: $setName (الأطقم المكتملة: $completeSets)',
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.normal),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: totalExcess == 0
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 22),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'لا توجد قطع فردية زائدة. كافة القطع متكاملة ضمن الأطقم المكتملة.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'إجمالي القطع الفردية الزائدة:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFB45309)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD97706),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$totalExcess قطعة',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'القطع الفردية الزائدة حالياً بالمخزن:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    ...excessPieces.map((p) {
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.weekend_outlined, size: 20, color: AppTheme.primaryNavy),
                                const SizedBox(width: 8),
                                Text(
                                  p['name'] as String,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryNavy),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD97706),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${p['excess_qty']} قطعة زائدة',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _openEditDialog(Map<String, dynamic> cat) {
    final parsedComps = CategoryStockHelper.parseComponents(cat['components_json']);
    final int initialSets = CategoryStockHelper.calculateCompleteSets(cat);
    final stockCtrl = TextEditingController(text: '$initialSets');

    // تحميل رصيد كل قطعة الفعلي الحالي بالمخزن بدون تصفير
    final List<_PieceEditItem> pieces = parsedComps.map((e) {
      final String name = (e['name'] ?? 'قطعة').toString().trim();
      final int baseQty = CategoryStockHelper.parseInt(e['base_qty'], fallback: 1);
      final int initialQty = CategoryStockHelper.parseInt(e['qty']);
      return _PieceEditItem(
        name: name,
        baseQty: baseQty > 0 ? baseQty : 1,
        qty: initialQty,
      );
    }).toList();

    if (pieces.isEmpty) {
      pieces.add(_PieceEditItem(name: 'كنبة كبيرة', baseQty: 1, qty: initialSets));
      pieces.add(_PieceEditItem(name: 'فوتيه', baseQty: 2, qty: initialSets * 2));
    }

    int calcCurrentSets() {
      if (pieces.isEmpty) return 0;
      return pieces.map((p) {
        final q = int.tryParse(p.qtyCtrl.text.trim()) ?? 0;
        final b = p.baseQty > 0 ? p.baseQty : 1;
        return q ~/ b;
      }).reduce(math.min);
    }

    int calcCurrentExcess() {
      final s = calcCurrentSets();
      int excess = 0;
      for (final p in pieces) {
        final q = int.tryParse(p.qtyCtrl.text.trim()) ?? 0;
        final b = p.baseQty > 0 ? p.baseQty : 1;
        final ex = q - (s * b);
        if (ex > 0) excess += ex;
      }
      return excess;
    }

    void modifySetsBy(int delta, StateSetter setModalState) {
      setModalState(() {
        for (final p in pieces) {
          int q = int.tryParse(p.qtyCtrl.text.trim()) ?? 0;
          final nextQ = math.max(0, q + (delta * p.baseQty));
          p.qtyCtrl.text = '$nextQ';
        }
        stockCtrl.text = '${calcCurrentSets()}';
      });
    }

    void onDirectSetsTyped(int targetSets, StateSetter setModalState) {
      setModalState(() {
        final currentS = calcCurrentSets();
        for (final p in pieces) {
          int q = int.tryParse(p.qtyCtrl.text.trim()) ?? 0;
          int excess = math.max(0, q - (currentS * p.baseQty));
          p.qtyCtrl.text = '${(targetSets * p.baseQty) + excess}';
        }
        stockCtrl.text = '$targetSets';
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final liveSets = calcCurrentSets();
          final liveExcess = calcCurrentExcess();

          return Padding(
            padding: AppTheme.modalSheetPadding(ctx),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // رأس النافذة
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.warehouse_rounded, color: AppTheme.primaryNavy, size: 26),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'تعديل رصيد المخزن: ${cat['name']}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryNavy,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'تعديل مباشر على المخزون الحالي: يمكنك تعديل عدد الأطقم الكاملة أو تعديل قطع الطقم الفردية بدقة.',
                    style: TextStyle(color: AppTheme.textMuted(ctx), fontSize: 13),
                  ),
                  const SizedBox(height: 12),

                  // كارت الملخص اللحظي
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.subtleBg(ctx),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor(ctx)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'أطقم مكتملة: $liveSets طقم',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
                            ),
                          ],
                        ),
                        Container(width: 1, height: 24, color: AppTheme.borderColor(ctx)),
                        Row(
                          children: [
                            Icon(Icons.inventory_2_outlined, color: liveExcess > 0 ? const Color(0xFFD97706) : AppTheme.textMuted(ctx), size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'قطع فردية زائدة: $liveExcess قطعة',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: liveExcess > 0 ? const Color(0xFFD97706) : AppTheme.textMuted(ctx),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 1. حقل إضافة/تعديل الأطقم الكاملة
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تعديل الأطقم الكاملة بالمخزن:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryNavy),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // زر إنقاص عدد الأطقم
                            Material(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  if (liveSets > 0) {
                                    modifySetsBy(-1, setModalState);
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(10.0),
                                  child: Icon(Icons.remove, color: Colors.red, size: 26),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // حقل إجمالي الأطقم
                            Expanded(
                              child: TextField(
                                controller: stockCtrl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryNavy),
                                decoration: const InputDecoration(
                                  labelText: 'عدد الأطقم',
                                  prefixIcon: Icon(Icons.weekend_rounded),
                                ),
                                onChanged: (val) {
                                  final n = int.tryParse(val.trim());
                                  if (n != null && n >= 0) {
                                    onDirectSetsTyped(n, setModalState);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),

                            // زر زيادة عدد الأطقم
                            Material(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  modifySetsBy(1, setModalState);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(10.0),
                                  child: Icon(Icons.add, color: Colors.green, size: 26),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),

                  // 2. سرد قطع هذا الطقم وتعديل رصيد كل قطعة
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'قطع الطقم بالمخزن (تعديل فردي لكل قطعة):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryNavy),
                      ),
                      Text(
                        '${pieces.length} قطع مسجلة',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted(ctx), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  ...pieces.map((piece) {
                    final int q = int.tryParse(piece.qtyCtrl.text.trim()) ?? 0;
                    final int excessOfPiece = math.max(0, q - (liveSets * piece.baseQty));

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: excessOfPiece > 0 ? const Color(0xFFD97706).withValues(alpha: 0.5) : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.chair_rounded, color: AppTheme.primaryNavy, size: 20),
                          const SizedBox(width: 8),

                          // اسم القطعة ونسبتها والرصيد الزائد
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  piece.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      'النسبة: ${piece.baseQty} في الطقم',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                    if (excessOfPiece > 0) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD97706).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '+$excessOfPiece فردي زائد',
                                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // زر إنقاص عدد القطعة
                          Material(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                if (q > 0) {
                                  setModalState(() {
                                    piece.qtyCtrl.text = '${q - 1}';
                                    stockCtrl.text = '${calcCurrentSets()}';
                                  });
                                }
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Icon(Icons.remove, color: Colors.red, size: 22),
                              ),
                            ),
                          ),

                          // حقل عدد القطع
                          Container(
                            width: 58,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            child: TextField(
                              controller: piece.qtyCtrl,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: (_) {
                                setModalState(() {
                                  stockCtrl.text = '${calcCurrentSets()}';
                                });
                              },
                            ),
                          ),

                          // زر زيادة عدد القطعة
                          Material(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setModalState(() {
                                  piece.qtyCtrl.text = '${q + 1}';
                                  stockCtrl.text = '${calcCurrentSets()}';
                                });
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Icon(Icons.add, color: Colors.green, size: 22),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 20),

                  // زر حفظ التعديلات في المخزن
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                      foregroundColor: AppTheme.royalGold,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      final validComps = <Map<String, dynamic>>[];
                      for (final p in pieces) {
                        final pName = p.name.trim();
                        if (pName.isNotEmpty) {
                          final pQty = int.tryParse(p.qtyCtrl.text.trim()) ?? 0;
                          validComps.add({
                            'name': pName,
                            'base_qty': p.baseQty,
                            'qty': pQty >= 0 ? pQty : 0,
                          });
                        }
                      }

                      final int calculatedSets = validComps.isEmpty
                          ? (int.tryParse(stockCtrl.text.trim()) ?? 0)
                          : validComps.map<int>((p) {
                              final q = (p['qty'] as int?) ?? 0;
                              final b = (p['base_qty'] as int?) ?? 1;
                              return q ~/ (b > 0 ? b : 1);
                            }).reduce(math.min);

                      final int oldStock = (cat['stock_qty'] as int?) ?? 0;

                      final db = await DBHelper.instance.database;
                      await db.update(
                        'categories',
                        {
                          'stock_qty': calculatedSets,
                          'components_json': jsonEncode(validComps),
                        },
                        where: 'id = ?',
                        whereArgs: [cat['id']],
                      );

                      // 1. تسجيل حركة منفصلة لتغير رصيد المخزن الإجمالي للطقم
                      if (calculatedSets != oldStock) {
                        final diff = calculatedSets - oldStock;
                        await StockMovementHelper.logMovement(
                          categoryId: cat['id'],
                          categoryName: cat['name'],
                          movementType: diff > 0 ? 'manual_add' : 'manual_deduct',
                          qtyChange: diff,
                          stockAfter: calculatedSets,
                          notes: diff > 0
                              ? 'تعديل رصيد مخزن للطقم (+$diff طقم) - أصبح $calculatedSets بدلاً من $oldStock'
                              : 'تعديل رصيد مخزن للطقم ($diff طقم) - أصبح $calculatedSets بدلاً من $oldStock',
                        );
                      }

                      // 2. تدوين حركات التعديل في قطع الطقم
                      List oldComps = [];
                      try {
                        oldComps = jsonDecode(cat['components_json']);
                      } catch (_) {}

                      for (final p in validComps) {
                        final pName = p['name'] as String;
                        final pQty = p['qty'] as int;

                        final matchingOld = oldComps.firstWhere(
                          (oc) => (oc['name'] ?? '').toString().trim() == pName.trim(),
                          orElse: () => null,
                        );

                        if (matchingOld != null) {
                          final int oldQty = (matchingOld['qty'] as int?) ?? 0;
                          final pieceDiff = pQty - oldQty;
                          if (pieceDiff != 0) {
                            await StockMovementHelper.logMovement(
                              categoryId: cat['id'],
                              categoryName: cat['name'],
                              movementType: pieceDiff > 0 ? 'piece_add' : 'piece_deduct',
                              qtyChange: pieceDiff,
                              stockAfter: calculatedSets,
                              piecesDelta: [
                                {'name': pName, 'delta': pieceDiff},
                              ],
                              notes: pieceDiff > 0
                                  ? 'تعديل رصيد قطعة ($pName) بمقدار (+$pieceDiff قطعة) - أصبحت $pQty بدلاً من $oldQty'
                                  : 'تعديل رصيد قطعة ($pName) بمقدار ($pieceDiff قطعة) - أصبحت $pQty بدلاً من $oldQty',
                            );
                          }
                        }
                      }

                      await _load();
                      AppEvents.instance.notifyAll();
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (mounted) {
                        AppNotification.showSuccess(context, 'تم تحديث رصيد وقطع الطقم بالمخزن بنجاح');
                      }
                    },
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text(
                      'حفظ التعديلات في المخزن',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      stockCtrl.dispose();
      for (final p in pieces) {
        p.dispose();
      }
    });
  }

  /// نافذة عرض كشف حركة الطقم في المخزن
  Future<void> _openMovementsModal(Map<String, dynamic> cat) async {
    final movements = await StockMovementHelper.getMovementsForCategory(cat['id']);

    if (!mounted) return;

    showModalBottomSheet(
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, color: AppTheme.primaryNavy, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'كشف حركات طقم: ${cat['name']}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.primaryNavy),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'الرصيد الحالي بالمخزن: ${cat['stock_qty']} طقم',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryNavy, fontSize: 14),
                  ),
                  Text(
                    'إجمالي الحركات: ${movements.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (movements.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('لا توجد حركات مسجلة لهذا الطقم حتى الآن', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: movements.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (mCtx, idx) {
                    final mov = movements[idx];
                    final type = mov['movement_type'] ?? '';
                    final int change = mov['qty_change'] ?? 0;
                    final int after = mov['stock_after'] ?? 0;
                    final notes = mov['notes'] ?? '';
                    final date = mov['created_at'] ?? '';

                    Color iconColor;
                    Color badgeBg;
                    IconData iconData;
                    String typeTitle;

                    if (type == 'delivered_out') {
                      iconColor = Colors.purple.shade700;
                      badgeBg = Colors.purple.shade50;
                      iconData = Icons.local_shipping_rounded;
                      typeTitle = 'تسليم أوردر للعميل (خصم)';
                    } else if (type == 'upholsterer_in') {
                      iconColor = Colors.green.shade800;
                      badgeBg = Colors.green.shade50;
                      iconData = Icons.assignment_turned_in_rounded;
                      typeTitle = 'استلام من المنجد (إضافة)';
                    } else if (type == 'manual_add') {
                      iconColor = Colors.teal.shade800;
                      badgeBg = Colors.teal.shade50;
                      iconData = Icons.add_circle_outline_rounded;
                      typeTitle = 'إضافة رصيد طقم بالمخزن (+)';
                    } else if (type == 'manual_deduct') {
                      iconColor = Colors.red.shade800;
                      badgeBg = Colors.red.shade50;
                      iconData = Icons.remove_circle_outline_rounded;
                      typeTitle = 'إنقاص رصيد طقم بالمخزن (-)';
                    } else if (type == 'piece_add') {
                      iconColor = Colors.indigo.shade800;
                      badgeBg = Colors.indigo.shade50;
                      iconData = Icons.playlist_add_rounded;
                      typeTitle = 'إضافة رصيد قطع للطقم (+)';
                    } else if (type == 'piece_deduct') {
                      iconColor = Colors.deepOrange.shade800;
                      badgeBg = Colors.deepOrange.shade50;
                      iconData = Icons.playlist_remove_rounded;
                      typeTitle = 'إنقاص عدد قطع الطقم (-)';
                    } else if (type == 'upholsterer_out') {
                      iconColor = Colors.orange.shade800;
                      badgeBg = Colors.orange.shade50;
                      iconData = Icons.handyman_rounded;
                      typeTitle = 'تسليم للمنجد للتشطيب';
                    } else {
                      iconColor = AppTheme.primaryNavy;
                      badgeBg = Colors.blue.shade50;
                      iconData = Icons.tune_rounded;
                      typeTitle = 'تعديل رصيد المخزن';
                    }

                    final formattedDate12 = StockMovementHelper.formatDateString12(date);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(iconData, color: iconColor, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      typeTitle,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: iconColor,
                                      ),
                                    ),
                                    if (change != 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: badgeBg,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          change > 0 ? '+$change' : '$change',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: iconColor,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  notes,
                                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '📅 $formattedDate12',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                    Text(
                                      'رصيد الطقم: $after طقم',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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

  // ---------------------------------------------------------------------------
  // واجهة عرض المخزون مع تحسين عرض عدد الأطقم وعدد القطع بشكل لائق ومميز
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final effectiveCategories = _historicalCategories ?? _categories;
    final bool isHistoricalMode = _selectedHistoryDate != null;
    final dateFormatted = isHistoricalMode
        ? intl.DateFormat('yyyy-MM-dd').format(_selectedHistoryDate!)
        : '';

    return Column(
      children: [
        // شريط فلتر التاريخ لاستعراض وضع المخزن في نهاية يوم محدد
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isHistoricalMode ? (AppTheme.isDark(context) ? const Color(0xFF3A2A0A) : const Color(0xFFFFFBEB)) : AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHistoricalMode ? AppTheme.warningBorder(context) : AppTheme.borderColor(context),
              width: isHistoricalMode ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                isHistoricalMode ? Icons.history_toggle_off_rounded : Icons.calendar_month_rounded,
                color: isHistoricalMode ? AppTheme.warningFg(context) : AppTheme.accentOnSurface(context),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: _pickHistoryDate,
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isHistoricalMode ? 'وضع المخزن كما كان بنهاية تاريخ:' : 'استعادة وضع المخزن بتاريخ سابق:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isHistoricalMode ? AppTheme.warningFg(context) : AppTheme.textMuted(context),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        isHistoricalMode ? dateFormatted : 'اضغط لاختيار تاريخ سابق',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isHistoricalMode ? AppTheme.warningFg(context) : AppTheme.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isLoadingHistory)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD97706)),
                )
              else if (isHistoricalMode)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _clearDateFilter,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('إلغاء الفلتر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                )
              else
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentOnSurface(context),
                    side: BorderSide(color: AppTheme.accentOnSurface(context).withValues(alpha: 0.55)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _pickHistoryDate,
                  icon: const Icon(Icons.date_range_rounded, size: 16),
                  label: const Text('تحديد تاريخ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                ),
            ],
          ),
        ),

        if (isHistoricalMode)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF92400E)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'أرقام المخزون المعروضة حالياً تعكس الوضع في نهاية $dateFormatted بناءً على سجل الحركات.',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF92400E), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

        // قائمة الأصناف
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: effectiveCategories.isEmpty
                ? const RefreshableEmptyView(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'لا توجد أصناف في المخزن حالياً.\nيمكنك إضافة الأصناف من تبويب (الأصناف ومكوناتها).',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 80),
                    itemCount: effectiveCategories.length,
                    itemBuilder: (ctx, i) {
                      final cat = effectiveCategories[i];
              List comps = [];
              try {
                comps = jsonDecode(cat['components_json']);
              } catch (_) {}

              final breakdown = CategoryStockHelper.calculateCategoryBreakdown(cat);
              final int completeSets = breakdown.completeSets;
              final int individualPiecesCount = breakdown.individualPieces;
              final List<Map<String, dynamic>> excessPieces = breakdown.excessPieces;

              final int qty = completeSets;
              final int catId = (cat['id'] as int?) ?? i;
              final bool isExpanded = _expandedCategoryIds.contains(catId);
              final int totalStockPieces = comps.fold<int>(
                0,
                (sum, c) => sum + ((c['qty'] is int) ? c['qty'] as int : (int.tryParse(c['qty']?.toString() ?? '0') ?? 0)),
              );

              return Card(
                elevation: isExpanded ? 3 : 1.5,
                margin: const EdgeInsets.symmetric(vertical: 5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isExpanded
                        ? AppTheme.royalGold
                        : (qty > 0 ? AppTheme.royalGold.withValues(alpha: 0.4) : Colors.grey.shade300),
                    width: isExpanded ? 1.5 : 1.2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedCategoryIds.remove(catId);
                      } else {
                        _expandedCategoryIds.add(catId);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: isExpanded ? 12 : 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // الصف الأول (ملخص مضغوط): بادج الأطقم + بادج الفردي + اسم الصنف + سهم التوسيع
                        Row(
                          children: [
                            // 1. بادج رصيد الأطقم الكاملة
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: AppTheme.setsAvatarGradient(context, hasValue: completeSets > 0),
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
                                    style: TextStyle(fontSize: 9.5, color: AppTheme.brightGold, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '$completeSets',
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),

                            // 2. بادج الرصيد الفردي (اضغط لعرض تفاصيل القطع الفردية)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  _showIndividualPiecesDialog(
                                    context: context,
                                    setName: (cat['name'] ?? '').toString(),
                                    completeSets: completeSets,
                                    totalExcess: individualPiecesCount,
                                    excessPieces: excessPieces,
                                  );
                                },
                                child: Tooltip(
                                  message: 'اضغط لعرض تفاصيل القطع الفردية الزائدة',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: AppTheme.individualAvatarGradient(context, hasValue: individualPiecesCount > 0),
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'فردي',
                                          style: TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          '$individualPiecesCount',
                                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // اسم الصنف كاملاً بدون قص + حالة التوفر في سطر واحد محكم
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(
                                      (cat['name'] ?? '').toString(),
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
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: completeSets > 0
                                                ? AppTheme.successBg(context)
                                                : (individualPiecesCount > 0 ? AppTheme.warningBg(context) : AppTheme.dangerBg(context)),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: completeSets > 0
                                                  ? AppTheme.successBorder(context)
                                                  : (individualPiecesCount > 0 ? AppTheme.warningBorder(context) : AppTheme.dangerBorder(context)),
                                            ),
                                          ),
                                          child: Text(
                                            completeSets > 0
                                                ? 'جاهز: $completeSets طقم${individualPiecesCount > 0 ? " + $individualPiecesCount فردي" : ""}'
                                                : (individualPiecesCount > 0 ? '$individualPiecesCount قطع فردية' : 'رصيد صفر'),
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: completeSets > 0
                                                  ? AppTheme.successFg(context)
                                                  : (individualPiecesCount > 0 ? AppTheme.warningFg(context) : AppTheme.dangerFg(context)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '($totalStockPieces قطعة)',
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textMuted(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 4),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: AppTheme.textMuted(context),
                              size: 24,
                            ),
                          ],
                        ),

                        // التفاصيل الكاملة وأزرار التعديل تظهر عند التوسيع فقط
                        if (isExpanded) ...[
                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 10),

                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'قطع الطقم ورصيدها الفعلي بالمخزن:',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.brown.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'إجمالي القطع: $totalStockPieces قطعة',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.brown),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          if (comps.isEmpty)
                            const Text('لم يتم سرد قطع بعد لهذا الطقم', style: TextStyle(color: Colors.grey, fontSize: 12))
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: comps.map((c) {
                                final String pieceName = (c['name'] ?? '').toString();
                                final int pieceCount = (c['qty'] is int)
                                    ? c['qty'] as int
                                    : (int.tryParse(c['qty']?.toString() ?? '0') ?? 0);

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: pieceCount > 0 ? AppTheme.infoBg(context) : AppTheme.subtleBg(context),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: pieceCount > 0 ? AppTheme.infoBorder(context) : AppTheme.borderColor(context),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.chair_rounded,
                                        size: 15,
                                        color: pieceCount > 0 ? AppTheme.infoFg(context) : AppTheme.textMuted(context),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        pieceName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: pieceCount > 0 ? AppTheme.infoFg(context) : AppTheme.textMuted(context),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: pieceCount > 0 ? AppTheme.primaryNavy : Colors.grey.shade400,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '$pieceCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 12),

                          // أزرار العمليات بالأسفل
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.accentOnSurface(context),
                                    side: BorderSide(color: AppTheme.accentOnSurface(context)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => _openMovementsModal(cat),
                                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                                  label: const Text('كشف الحركات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryNavy,
                                    foregroundColor: AppTheme.royalGold,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => _openEditDialog(cat),
                                  icon: const Icon(Icons.edit, size: 18),
                                  label: const Text('تعديل المخزون', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                                icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 22),
                                tooltip: 'حذف الصنف من المخزن',
                                onPressed: () => _confirmDeleteCategory(context, cat),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
}
}
