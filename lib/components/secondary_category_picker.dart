import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../core/category_stock_helper.dart';
import 'searchable_picker.dart';

/// مكون موحد لاختيار قطع فردية إضافية من طقم آخر (يُستخدم في إنشاء وتعديل الطلب لمنع التكرار)
class SecondaryCategoryPickerSection extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onToggleEnabled;
  final List<Map<String, dynamic>> otherCategories;
  final int? selectedSecondaryCategoryId;
  final ValueChanged<int?> onSecondaryCategoryChanged;
  final List<Map<String, dynamic>> editableComponents;
  final void Function(Map<String, dynamic> secCat, String pieceName, int newQty)
      onPieceQtyChanged;

  const SecondaryCategoryPickerSection({
    super.key,
    required this.enabled,
    required this.onToggleEnabled,
    required this.otherCategories,
    required this.selectedSecondaryCategoryId,
    required this.onSecondaryCategoryChanged,
    required this.editableComponents,
    required this.onPieceQtyChanged,
  });

  /// دالة مساعدة موحدة لتحديث قائمة المكونات عند تغيير كمية قطعة من طقم آخر
  static void applySecondaryPieceQty({
    required List<Map<String, dynamic>> editableComponents,
    required Map<String, dynamic> secCat,
    required String pieceName,
    required int newQty,
  }) {
    final int secCatId = secCat['id'] as int;
    final String secCatName = (secCat['name'] ?? '').toString();
    final existingIdx = editableComponents.indexWhere(
      (c) =>
          c['source_category_id'] == secCatId &&
          c['source_piece_name'] == pieceName,
    );
    if (newQty <= 0) {
      if (existingIdx != -1) {
        editableComponents.removeAt(existingIdx);
      }
    } else if (existingIdx != -1) {
      editableComponents[existingIdx]['qty'] = newQty;
      editableComponents[existingIdx]['selected'] = true;
    } else {
      editableComponents.add({
        'name': '$pieceName ($secCatName)',
        'source_piece_name': pieceName,
        'source_category_id': secCatId,
        'source_category_name': secCatName,
        'base_qty': 0,
        'qty': newQty,
        'original_qty': 0,
        'selected': true,
        'is_custom': true,
      });
    }
  }

  Map<String, dynamic>? get _secondaryCategory {
    for (final c in otherCategories) {
      if (c['id'] == selectedSecondaryCategoryId) return c;
    }
    return null;
  }

  int _getSecondaryPieceQty(int secCatId, String pieceName) {
    for (final c in editableComponents) {
      if (c['source_category_id'] == secCatId &&
          c['source_piece_name'] == pieceName) {
        return (c['qty'] as int?) ?? 0;
      }
    }
    return 0;
  }

  List<Map<String, dynamic>> _parseCategoryPieces(Map<String, dynamic> cat) {
    final comps = CategoryStockHelper.parseComponents(cat['components_json']);
    return comps
        .map((e) => {
              'name': (e['name'] ?? '').toString(),
              'stock_qty': CategoryStockHelper.parseInt(e['qty']),
            })
        .where((e) => (e['name'] as String).isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final secCat = _secondaryCategory;
    final tealAccent = isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(child: Divider(color: Colors.teal.withValues(alpha: 0.4), thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.style_outlined, size: 16, color: tealAccent),
                    const SizedBox(width: 5),
                    Text(
                      'قطع إضافية من أطقم أخرى',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: tealAccent,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: Divider(color: Colors.teal.withValues(alpha: 0.4), thickness: 1)),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? LinearGradient(
                    colors: enabled
                        ? [const Color(0xFF134E4A), const Color(0xFF1E293B)]
                        : [const Color(0xFF16273B), const Color(0xFF1A2740)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  )
                : LinearGradient(
                    colors: enabled
                        ? [const Color(0xFFE6FFFA), const Color(0xFFCCFBF1)]
                        : [const Color(0xFFF0FDFA), const Color(0xFFF8FAFC)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled ? const Color(0xFF0D9488) : Colors.teal.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D9488).withValues(alpha: enabled ? 0.12 : 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                value: enabled,
                activeColor: const Color(0xFF0F766E),
                checkColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                title: Row(
                  children: [
                    Icon(Icons.add_shopping_cart_rounded, size: 20, color: tealAccent),
                    const SizedBox(width: 8),
                    Text(
                      'إضافة قطع من طقم آخر',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: tealAccent,
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'مثل إضافة كنبة فرداني من صنف آخر ليتم خصمها من مخزونه عند التسليم',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.teal.shade200 : const Color(0xFF115E59),
                    ),
                  ),
                ),
                onChanged: (checked) => onToggleEnabled(checked ?? false),
              ),
              if (enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: otherCategories.isEmpty
                      ? Text(
                          'لا توجد أصناف أخرى مسجلة حالياً.',
                          style: TextStyle(color: AppTheme.textMuted(context), fontSize: 12.5),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SearchableSelectFormField<int>(
                              key: ValueKey('sec_cat_${selectedSecondaryCategoryId ?? 'none'}'),
                              value: selectedSecondaryCategoryId,
                              labelText: 'اختر الطقم الآخر *',
                              hintText: 'ابحث عن الطقم الآخر لاختيار قطع منه',
                              searchHint: 'اكتب اسم الطقم للتصفية...',
                              prefixIcon: Icon(
                                Icons.weekend_outlined,
                                color: AppTheme.accentOnSurface(context),
                              ),
                              items: otherCategories.map((c) {
                                return SearchableSelectItem<int>(
                                  value: c['id'] as int,
                                  label: (c['name'] ?? '').toString(),
                                  subtitle:
                                      'رصيد المعرض: ${CategoryStockHelper.formatStockSummary(c)}',
                                  badge: CategoryStockHelper.formatStockSummary(c),
                                  searchKey: (c['name'] ?? '').toString(),
                                );
                              }).toList(),
                              onChanged: onSecondaryCategoryChanged,
                            ),
                            if (secCat != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                'اختر القطع المطلوبة من هذا الطقم:',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                              const SizedBox(height: 6),
                              ..._parseCategoryPieces(secCat).map((p) {
                                final String pName = p['name'] as String;
                                final int stockQ = p['stock_qty'] as int;
                                final int secId = secCat['id'] as int;
                                final int curQ = _getSecondaryPieceQty(secId, pName);

                                return Container(
                                  margin: const EdgeInsets.symmetric(vertical: 3),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: curQ > 0
                                        ? AppTheme.cardBg(context)
                                        : AppTheme.cardBg(context).withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: curQ > 0
                                          ? Colors.teal.shade400
                                          : AppTheme.borderColor(context),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              pName,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: AppTheme.textBody(context),
                                              ),
                                            ),
                                            Text(
                                              'متاح بالمخزن: $stockQ قطعة',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.textMuted(context),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        icon: Icon(
                                          Icons.remove_circle_outline,
                                          color: curQ > 0 ? Colors.red.shade600 : Colors.grey,
                                          size: 22,
                                        ),
                                        onPressed: curQ > 0
                                            ? () => onPieceQtyChanged(secCat, pName, curQ - 1)
                                            : null,
                                      ),
                                      Container(
                                        constraints: const BoxConstraints(minWidth: 28),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '$curQ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            color: AppTheme.textPrimary(context),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        icon: Icon(
                                          Icons.add_circle_outline,
                                          color: Colors.green.shade600,
                                          size: 22,
                                        ),
                                        onPressed: () => onPieceQtyChanged(secCat, pName, curQ + 1),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
