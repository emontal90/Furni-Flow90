import 'dart:convert';
import 'package:flutter/material.dart';
import '../../components/refreshable_empty_view.dart';
import '../../core/app_events.dart';
import '../../core/app_notification.dart';
import '../../core/app_theme.dart';
import '../../core/category_stock_helper.dart';
import '../../core/db_helper.dart';

class CategoriesTab extends StatefulWidget {
  const CategoriesTab({super.key});
  @override
  State<CategoriesTab> createState() => _CategoriesTabState();
}

/// عنصر يمثل قطعة ومقدارها التأسيسي في الطقم الواحد
class _MenuPieceItem {
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final bool isTable;

  _MenuPieceItem({String name = '', int qty = 1, this.isTable = false})
      : nameCtrl = TextEditingController(text: name),
        qtyCtrl = TextEditingController(text: qty > 0 ? qty.toString() : '1');

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
  }
}

class _CategoriesTabState extends State<CategoriesTab> {
  List<Map<String, dynamic>> _categories = [];
  final Set<int> _expandedCategoryIds = {};

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
    if (mounted) setState(() => _categories = data);
  }

  // رسالة تأكيد لحذف قطعة
  Future<void> _confirmDeletePiece(
    BuildContext context,
    String pieceName,
    VoidCallback onConfirmed,
  ) async {
    final displayName = pieceName.trim().isEmpty ? 'هذه القطعة' : '"$pieceName"';
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('تأكيد حذف القطعة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من رغبتك في حذف قطعة $displayName من مكونات هذا الطقم؟',
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
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      onConfirmed();
    }
  }

  // رسالة تأكيد لحذف صنف بالكامل
  Future<void> _confirmDeleteCategory(BuildContext callerCtx, Map<String, dynamic> cat) async {
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
          'هل أنت متأكد من حذف طقم "${cat['name']}" ومكوناته بالكامل من النظام؟\nلن يمكن التراجع عن هذا الإجراء.',
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
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = await DBHelper.instance.database;
      await db.delete('categories', where: 'id = ?', whereArgs: [cat['id']]);
      AppEvents.instance.notifyAll();
      if (!mounted) return;
      AppNotification.showError(context, 'تم حذف طقم "${cat['name']}" بنجاح');
    }
  }

  // ---------------------------------------------------------------------------
  // بناء صف إدخال قطعة (سواء كانت قطعة طقم أساسي أو قطعة ترابيزة)
  // ---------------------------------------------------------------------------
  Widget _buildPieceRow({
    required BuildContext ctx,
    required int idx,
    required _MenuPieceItem piece,
    required void Function(void Function()) setModalState,
    required VoidCallback onDelete,
    required bool canDelete,
    bool isTable = false,
  }) {
    final themeColor = isTable ? const Color(0xFF0D9488) : AppTheme.primaryNavy;
    final rowBg = isTable ? const Color(0xFFF0FDFA) : Colors.white;
    final rowBorder = isTable ? const Color(0xFF99F6E4) : Colors.grey.shade300;
    final iconData = isTable ? Icons.table_restaurant_rounded : Icons.chair_outlined;
    final labelText = isTable ? 'قطعة ترابيزة ${idx + 1}' : 'اسم القطعة ${idx + 1}';
    final hintText = isTable ? 'مثال: ترابيزة وسط، ترابيزة جانبية...' : 'مثال: فوتيه، كنبة...';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: rowBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: rowBorder),
      ),
      child: Row(
        children: [
          Icon(iconData, color: themeColor, size: 22),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: piece.nameCtrl,
              decoration: InputDecoration(
                labelText: labelText,
                hintText: hintText,
                labelStyle: TextStyle(color: isTable ? const Color(0xFF0F766E) : null),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: themeColor, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                int q = int.tryParse(piece.qtyCtrl.text.trim()) ?? 1;
                if (q > 1) {
                  setModalState(() {
                    piece.qtyCtrl.text = '${q - 1}';
                  });
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.remove, color: Colors.red, size: 22),
              ),
            ),
          ),
          Container(
            width: 46,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: TextField(
              controller: piece.qtyCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: themeColor),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: themeColor, width: 1.5),
                ),
              ),
            ),
          ),
          Material(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                int q = int.tryParse(piece.qtyCtrl.text.trim()) ?? 1;
                setModalState(() {
                  piece.qtyCtrl.text = '${q + 1}';
                });
              },
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.add, color: Colors.green, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
              tooltip: 'حذف القطعة',
              onPressed: () {
                _confirmDeletePiece(
                  ctx,
                  piece.nameCtrl.text,
                  onDelete,
                );
              },
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // نافذة إضافة صنف جديد (تحديد اسم الطقم ومكوناته والعدد الافتراضي لكل قطعة)
  // ---------------------------------------------------------------------------
  void _openAddDialog() {
    final nameCtrl = TextEditingController();

    // قائمة القطع التأسيسية مع أعدادها للطقم الواحد (مثلاً 2 فوتيه، 1 كنبة كبيرة)
    final List<_MenuPieceItem> pieces = [
      _MenuPieceItem(name: 'كنبة كبيرة', qty: 1),
      _MenuPieceItem(name: 'كنبة صغيرة', qty: 1),
      _MenuPieceItem(name: 'فوتيه', qty: 2),
    ];

    // قائمة قطع طقم الترابيزات التأسيسية (اختياري)
    final List<_MenuPieceItem> tablePieces = [];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: AppTheme.modalSheetPadding(ctx),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.add_box_rounded, color: AppTheme.primaryNavy, size: 26),
                        SizedBox(width: 8),
                        Text(
                          'إضافة صنف جديد',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryNavy),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'أدخل اسم الطقم وحدد مكونات الطقم الأساسي وكذلك طقم الترابيزات إن وجد.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 16),

                // 1. اسم الصنف أو الطقم
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الصنف أو الطقم *',
                    hintText: 'مثال: صالون كنز، أنتريه مودرن...',
                    prefixIcon: Icon(Icons.weekend),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),

                // 2. مكونات الطقم الأساسي
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'مكونات الطقم الأساسي (كنب، كراسي، فوتيهات):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppTheme.primaryNavy),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setModalState(() {
                          pieces.add(_MenuPieceItem(name: '', qty: 1));
                        });
                      },
                      icon: const Icon(Icons.add_circle, color: AppTheme.primaryNavy),
                      label: const Text('إضافة قطعة (+)', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // قائمة إدخال قطع الطقم الأساسي
                ...pieces.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final piece = entry.value;
                  return _buildPieceRow(
                    ctx: ctx,
                    idx: idx,
                    piece: piece,
                    setModalState: setModalState,
                    canDelete: pieces.length > 1,
                    isTable: false,
                    onDelete: () {
                      setModalState(() {
                        pieces.removeAt(idx);
                      });
                    },
                  );
                }),
                const SizedBox(height: 6),

                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                    side: const BorderSide(color: AppTheme.primaryNavy),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () {
                    setModalState(() {
                      pieces.add(_MenuPieceItem(name: '', qty: 1));
                    });
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة قطعة أخرى للطقم الأساسي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),

                const SizedBox(height: 16),

                // 3. فاصل وقسم طقم الترابيزات
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDFA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF5EEAD4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.table_restaurant_rounded, color: Color(0xFF0D9488), size: 20),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'قسم طقم الترابيزات (اختياري):',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F766E)),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setModalState(() {
                                tablePieces.add(_MenuPieceItem(name: '', qty: 1, isTable: true));
                              });
                            },
                            icon: const Icon(Icons.add_circle, color: Color(0xFF0D9488), size: 18),
                            label: const Text('إضافة ترابيزة (+)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D9488), fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'حدد قطع الترابيزات وأعدادها التأسيسية التابعة لهذا الصنف (مثال: ترابيزة وسط: 1، ترابيزات جانبية: 2).',
                        style: TextStyle(color: Color(0xFF115E59), fontSize: 11.5),
                      ),
                      if (tablePieces.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...tablePieces.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final piece = entry.value;
                          return _buildPieceRow(
                            ctx: ctx,
                            idx: idx,
                            piece: piece,
                            setModalState: setModalState,
                            canDelete: true,
                            isTable: true,
                            onDelete: () {
                              setModalState(() {
                                tablePieces.removeAt(idx);
                              });
                            },
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // زر الحفظ
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: AppTheme.royalGold,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    final catName = nameCtrl.text.trim();
                    if (catName.isEmpty) {
                      AppNotification.showError(ctx, 'يرجى إدخال اسم الصنف أو الطقم أولاً');
                      return;
                    }

                    final compsData = <Map<String, dynamic>>[];
                    for (final p in pieces) {
                      final pName = p.nameCtrl.text.trim();
                      if (pName.isNotEmpty) {
                        final pQty = int.tryParse(p.qtyCtrl.text.trim()) ?? 1;
                        final int safeQty = pQty > 0 ? pQty : 1;
                        compsData.add({
                          'name': pName,
                          'base_qty': safeQty,
                          'qty': 0, // رصيد صفر لكل القطع بالمخزن عند إدراج الصنف الجديد
                          'is_table': false,
                        });
                      }
                    }

                    for (final p in tablePieces) {
                      final pName = p.nameCtrl.text.trim();
                      if (pName.isNotEmpty) {
                        final pQty = int.tryParse(p.qtyCtrl.text.trim()) ?? 1;
                        final int safeQty = pQty > 0 ? pQty : 1;
                        compsData.add({
                          'name': pName,
                          'base_qty': safeQty,
                          'qty': 0,
                          'is_table': true,
                        });
                      }
                    }

                    if (compsData.isEmpty) {
                      AppNotification.showError(ctx, 'يرجى إدخال قطعة واحدة على الأقل للطقم');
                      return;
                    }

                    final db = await DBHelper.instance.database;
                    await db.insert('categories', {
                      'name': catName,
                      'components_json': jsonEncode(compsData),
                      'stock_qty': 0, // الرصيد الافتتاحي صفر ويتم تحديده في المخزن
                    });

                    AppEvents.instance.notifyAll();
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                    if (mounted) {
                      AppNotification.showSuccess(
                        context,
                        'تم حفظ طقم "$catName" بنجاح وإدراجه في قائمة المخزون',
                      );
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('حفظ الصنف ومكوناته', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      for (final p in pieces) {
        p.dispose();
      }
      for (final p in tablePieces) {
        p.dispose();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // نافذة تعديل الصنف ومكوناته وأعداده التأسيسية
  // ---------------------------------------------------------------------------
  void _openEditDialog(Map<String, dynamic> cat) {
    final nameCtrl = TextEditingController(text: cat['name'] ?? '');

    List rawComps = [];
    try {
      rawComps = jsonDecode(cat['components_json'] ?? '[]');
    } catch (_) {}

    final List<_MenuPieceItem> pieces = [];
    final List<_MenuPieceItem> tablePieces = [];

    for (final c in rawComps) {
      final String pName = (c['name'] ?? '').toString();
      final int pQty = (c['base_qty'] is int)
          ? c['base_qty'] as int
          : ((c['qty'] is int) ? c['qty'] as int : (int.tryParse(c['qty']?.toString() ?? '1') ?? 1));
      final bool isTable = CategoryStockHelper.isTablePiece(c);
      if (isTable) {
        tablePieces.add(_MenuPieceItem(name: pName, qty: pQty, isTable: true));
      } else {
        pieces.add(_MenuPieceItem(name: pName, qty: pQty, isTable: false));
      }
    }

    if (pieces.isEmpty) {
      pieces.add(_MenuPieceItem(name: 'كنبة كبيرة', qty: 1));
      pieces.add(_MenuPieceItem(name: 'فوتيه', qty: 2));
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: AppTheme.modalSheetPadding(ctx),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.edit_note, color: AppTheme.primaryNavy, size: 28),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'تعديل صنف: (${cat['name']})',
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
                const Text(
                  'تعديل اسم الطقم ومكونات الطقم الأساسي وكذلك طقم الترابيزات.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 16),

                // 1. اسم الصنف أو الطقم
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الصنف أو الطقم *',
                    hintText: 'مثال: صالون كنز، أنتريه مودرن...',
                    prefixIcon: Icon(Icons.weekend),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),

                // 2. مكونات الطقم الأساسي
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'مكونات الطقم الأساسي (كنب، كراسي، فوتيهات):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppTheme.primaryNavy),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setModalState(() {
                          pieces.add(_MenuPieceItem(name: '', qty: 1));
                        });
                      },
                      icon: const Icon(Icons.add_circle, color: AppTheme.primaryNavy),
                      label: const Text('إضافة قطعة (+)', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // قائمة قطع الطقم الأساسي
                ...pieces.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final piece = entry.value;
                  return _buildPieceRow(
                    ctx: ctx,
                    idx: idx,
                    piece: piece,
                    setModalState: setModalState,
                    canDelete: pieces.length > 1,
                    isTable: false,
                    onDelete: () {
                      setModalState(() {
                        pieces.removeAt(idx);
                      });
                    },
                  );
                }),
                const SizedBox(height: 6),

                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                    side: const BorderSide(color: AppTheme.primaryNavy),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () {
                    setModalState(() {
                      pieces.add(_MenuPieceItem(name: '', qty: 1));
                    });
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة قطعة أخرى للطقم الأساسي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),

                const SizedBox(height: 16),

                // 3. فاصل وقسم طقم الترابيزات
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDFA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF5EEAD4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.table_restaurant_rounded, color: Color(0xFF0D9488), size: 20),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'قسم طقم الترابيزات (اختياري):',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F766E)),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setModalState(() {
                                tablePieces.add(_MenuPieceItem(name: '', qty: 1, isTable: true));
                              });
                            },
                            icon: const Icon(Icons.add_circle, color: Color(0xFF0D9488), size: 18),
                            label: const Text('إضافة ترابيزة (+)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D9488), fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'حدد قطع الترابيزات وأعدادها التأسيسية التابعة لهذا الصنف.',
                        style: TextStyle(color: Color(0xFF115E59), fontSize: 11.5),
                      ),
                      if (tablePieces.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...tablePieces.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final piece = entry.value;
                          return _buildPieceRow(
                            ctx: ctx,
                            idx: idx,
                            piece: piece,
                            setModalState: setModalState,
                            canDelete: true,
                            isTable: true,
                            onDelete: () {
                              setModalState(() {
                                tablePieces.removeAt(idx);
                              });
                            },
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // زر حفظ التعديلات
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: AppTheme.royalGold,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    final newCatName = nameCtrl.text.trim();
                    if (newCatName.isEmpty) {
                      AppNotification.showError(ctx, 'يرجى إدخال اسم الصنف أو الطقم أولاً');
                      return;
                    }

                    final compsData = <Map<String, dynamic>>[];
                    for (final p in pieces) {
                      final pName = p.nameCtrl.text.trim();
                      if (pName.isNotEmpty) {
                        final pQty = int.tryParse(p.qtyCtrl.text.trim()) ?? 1;
                        final safeQty = pQty > 0 ? pQty : 1;

                        int currentPieceStock = 0;
                        final match = rawComps.firstWhere(
                          (c) => (c['name'] ?? '').toString().trim() == pName,
                          orElse: () => null,
                        );
                        if (match != null && match['qty'] != null) {
                          currentPieceStock = (match['qty'] is int)
                              ? match['qty'] as int
                              : (int.tryParse(match['qty'].toString()) ?? 0);
                        }

                        compsData.add({
                          'name': pName,
                          'base_qty': safeQty,
                          'qty': currentPieceStock,
                          'is_table': false,
                        });
                      }
                    }

                    for (final p in tablePieces) {
                      final pName = p.nameCtrl.text.trim();
                      if (pName.isNotEmpty) {
                        final pQty = int.tryParse(p.qtyCtrl.text.trim()) ?? 1;
                        final safeQty = pQty > 0 ? pQty : 1;

                        int currentPieceStock = 0;
                        final match = rawComps.firstWhere(
                          (c) => (c['name'] ?? '').toString().trim() == pName,
                          orElse: () => null,
                        );
                        if (match != null && match['qty'] != null) {
                          currentPieceStock = (match['qty'] is int)
                              ? match['qty'] as int
                              : (int.tryParse(match['qty'].toString()) ?? 0);
                        }

                        compsData.add({
                          'name': pName,
                          'base_qty': safeQty,
                          'qty': currentPieceStock,
                          'is_table': true,
                        });
                      }
                    }

                    if (compsData.isEmpty) {
                      AppNotification.showError(ctx, 'يرجى إدخال قطعة واحدة على الأقل للطقم');
                      return;
                    }

                    final db = await DBHelper.instance.database;
                    await db.transaction((txn) async {
                      await txn.update(
                        'categories',
                        {
                          'name': newCatName,
                          'components_json': jsonEncode(compsData),
                        },
                        where: 'id = ?',
                        whereArgs: [cat['id']],
                      );

                      if (newCatName != cat['name']) {
                        await txn.update('orders', {'category_name': newCatName},
                            where: 'category_id = ?', whereArgs: [cat['id']]);
                        await txn.update('archived_orders', {'category_name': newCatName},
                            where: 'category_id = ?', whereArgs: [cat['id']]);
                        await txn.update('upholsterer_batches', {'category_name': newCatName},
                            where: 'category_id = ?', whereArgs: [cat['id']]);
                        await txn.update('upholsterer_transactions', {'category_name': newCatName},
                            where: 'category_id = ?', whereArgs: [cat['id']]);
                        await txn.update('stock_movements', {'category_name': newCatName},
                            where: 'category_id = ?', whereArgs: [cat['id']]);
                      }
                    });

                    AppEvents.instance.notifyAll();
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                    if (mounted) {
                      AppNotification.showSuccess(context, 'تم حفظ تعديلات طقم "$newCatName" بنجاح');
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('حفظ التعديلات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      for (final p in pieces) {
        p.dispose();
      }
      for (final p in tablePieces) {
        p.dispose();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // واجهة عرض الأصناف ومكوناتها
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: _categories.isEmpty
            ? const RefreshableEmptyView(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'لا توجد أصناف مسجلة حالياً.\nاضغط على (إضافة صنف جديد) لإدراج الأطقم وقطعها.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 80),
              itemCount: _categories.length,
              itemBuilder: (ctx, i) {
                final cat = _categories[i];
                List comps = [];
                try {
                  comps = jsonDecode(cat['components_json']);
                } catch (_) {}

                final int catId = (cat['id'] as int?) ?? i;
                final bool isExpanded = _expandedCategoryIds.contains(catId);
                final mainComps = CategoryStockHelper.getMainComponents(comps);
                final tableComps = CategoryStockHelper.getTableComponents(comps);

                final String summaryText = mainComps.isEmpty
                    ? 'لا توجد قطع مسجلة لهذا الطقم'
                    : mainComps.map((c) {
                        final pName = (c['name'] ?? '').toString();
                        final int bQ = (c['base_qty'] is int)
                            ? c['base_qty'] as int
                            : ((c['qty'] is int) ? c['qty'] as int : (int.tryParse(c['qty']?.toString() ?? '1') ?? 1));
                        return '$bQ $pName';
                      }).join(' • ');

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  elevation: isExpanded ? 3 : 1.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: isExpanded
                          ? AppTheme.royalGold
                          : AppTheme.royalGold.withValues(alpha: 0.35),
                      width: isExpanded ? 1.5 : 1.1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedCategoryIds.remove(catId);
                        } else {
                          _expandedCategoryIds.add(catId);
                        }
                      });
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: isExpanded ? 12.0 : 10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ملخص مضغوط قبل التوسيع: اسم الصنف + ملخص مكوناته وأعدادها + الرصيد + سهم التوسيع
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.weekend_rounded,
                                  color: AppTheme.primaryNavy,
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
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
                                              (cat['name'] ?? '').toString(),
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: AppTheme.textPrimary(context),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.warningBg(context),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: AppTheme.warningBorder(context)),
                                          ),
                                          child: Text(
                                            'المخزن: ${CategoryStockHelper.formatStockSummary(cat)}',
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: AppTheme.warningFg(context),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'المكونات: $summaryText',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppTheme.textMuted(context),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (tableComps.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.35)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.table_restaurant_rounded, size: 12, color: Color(0xFF0D9488)),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                'طقم ترابيزات: ${tableComps.map((c) => '${c['base_qty'] ?? 1} ${c['name']}').join(' • ')}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: Color(0xFF0F766E),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: Colors.grey.shade600,
                                size: 24,
                              ),
                            ],
                          ),

                          // التفاصيل الكاملة وأزرار التعديل والحذف عند التوسيع فقط
                          if (isExpanded) ...[
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),

                            const Text(
                              'قطع ومكونات الطقم الأساسي (التأسيسية):',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppTheme.primaryNavy),
                            ),
                            const SizedBox(height: 8),

                            if (mainComps.isEmpty)
                              const Text('لا توجد قطع مسجلة لهذا الطقم', style: TextStyle(color: Colors.grey, fontSize: 12))
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: mainComps.map((c) {
                                  final pieceName = (c['name'] ?? '').toString();
                                  final int baseQ = (c['base_qty'] is int)
                                      ? c['base_qty'] as int
                                      : ((c['qty'] is int) ? c['qty'] as int : (int.tryParse(c['qty']?.toString() ?? '1') ?? 1));
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.infoBg(context),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppTheme.infoBorder(context)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.chair_rounded, size: 14, color: AppTheme.royalGold),
                                        const SizedBox(width: 6),
                                        Text(
                                          'عدد $baseQ $pieceName',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: AppTheme.infoFg(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),

                            if (tableComps.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const Text(
                                'قطع ومكونات طقم الترابيزات (التأسيسية):',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF0F766E)),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: tableComps.map((c) {
                                  final pieceName = (c['name'] ?? '').toString();
                                  final int baseQ = (c['base_qty'] is int)
                                      ? c['base_qty'] as int
                                      : ((c['qty'] is int) ? c['qty'] as int : (int.tryParse(c['qty']?.toString() ?? '1') ?? 1));
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0FDFA),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF5EEAD4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.table_restaurant_rounded, size: 14, color: Color(0xFF0D9488)),
                                        const SizedBox(width: 6),
                                        Text(
                                          'عدد $baseQ $pieceName',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Color(0xFF0F766E),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                            const SizedBox(height: 12),

                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryNavy,
                                      foregroundColor: AppTheme.royalGold,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => _openEditDialog(cat),
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    label: const Text('تعديل الصنف ومكوناته', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 22),
                                  tooltip: 'حذف الصنف',
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: AppTheme.royalGold,
        onPressed: _openAddDialog,
        icon: const Icon(Icons.add_box_rounded),
        label: const Text('إضافة صنف جديد', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
