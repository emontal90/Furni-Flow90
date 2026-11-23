import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../core/category_stock_helper.dart';
import 'searchable_picker.dart';

/// مكون موحد لاختيار قطع فردية أو أطقم أو ترابيزات إضافية من طقم آخر (يُستخدم في إنشاء وتعديل الطلب)
class SecondaryCategoryPickerSection extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onToggleEnabled;
  final List<Map<String, dynamic>> otherCategories;
  final int? selectedSecondaryCategoryId;
  final ValueChanged<int?> onSecondaryCategoryChanged;
  final List<Map<String, dynamic>> editableComponents;
  final void Function(Map<String, dynamic> secCat, String pieceName, int newQty)
      onPieceQtyChanged;
  final void Function(Map<String, dynamic> secCat, int newSetsCount)?
      onSecondarySetsChanged;
  final void Function(Map<String, dynamic> secCat, bool includeTables)?
      onSecondaryTablesChanged;

  const SecondaryCategoryPickerSection({
    super.key,
    required this.enabled,
    required this.onToggleEnabled,
    required this.otherCategories,
    required this.selectedSecondaryCategoryId,
    required this.onSecondaryCategoryChanged,
    required this.editableComponents,
    required this.onPieceQtyChanged,
    this.onSecondarySetsChanged,
    this.onSecondaryTablesChanged,
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

  /// دالة مساعدة لتطبيق عدد أطقم كاملة من الصنف الآخر
  static void applySecondarySetsCount({
    required List<Map<String, dynamic>> editableComponents,
    required Map<String, dynamic> secCat,
    required int newSetsCount,
  }) {
    final catComps = CategoryStockHelper.getMainComponents(secCat['components_json']);
    for (final c in catComps) {
      final name = (c['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final base = (c['base_qty'] is int && (c['base_qty'] as int) > 0)
          ? (c['base_qty'] as int)
          : CategoryStockHelper.parseInt(c['base_qty'], fallback: 1);
      final finalBase = base > 0 ? base : 1;
      applySecondaryPieceQty(
        editableComponents: editableComponents,
        secCat: secCat,
        pieceName: name,
        newQty: newSetsCount * finalBase,
      );
    }
  }

  /// دالة مساعدة لتضمين أو استبعاد طقم ترابيزات الصنف الآخر
  static void applySecondaryTableSet({
    required List<Map<String, dynamic>> editableComponents,
    required Map<String, dynamic> secCat,
    required bool include,
  }) {
    final tableComps = CategoryStockHelper.getTableComponents(secCat['components_json']);
    final secCatId = secCat['id'] as int;
    final secCatName = (secCat['name'] ?? '').toString();
    for (final t in tableComps) {
      final name = (t['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final base = (t['base_qty'] is int && (t['base_qty'] as int) > 0)
          ? (t['base_qty'] as int)
          : CategoryStockHelper.parseInt(t['base_qty'], fallback: 1);
      final finalBase = base > 0 ? base : 1;
      final existingIdx = editableComponents.indexWhere(
        (c) => c['source_category_id'] == secCatId && c['source_piece_name'] == name,
      );
      if (!include) {
        if (existingIdx != -1) {
          editableComponents.removeAt(existingIdx);
        }
      } else {
        if (existingIdx != -1) {
          editableComponents[existingIdx]['qty'] = finalBase;
          editableComponents[existingIdx]['selected'] = true;
          editableComponents[existingIdx]['is_table'] = true;
        } else {
          editableComponents.add({
            'name': '$name ($secCatName)',
            'source_piece_name': name,
            'source_category_id': secCatId,
            'source_category_name': secCatName,
            'base_qty': finalBase,
            'qty': finalBase,
            'original_qty': finalBase,
            'selected': true,
            'is_custom': true,
            'is_table': true,
          });
        }
      }
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

  int _computeSecondarySets(Map<String, dynamic> secCat) {
    final catComps = CategoryStockHelper.getMainComponents(secCat['components_json']);
    if (catComps.isEmpty) return 0;
    int? minSets;
    final secId = secCat['id'] as int;
    for (final c in catComps) {
      final name = (c['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final base = (c['base_qty'] is int && (c['base_qty'] as int) > 0)
          ? (c['base_qty'] as int)
          : CategoryStockHelper.parseInt(c['base_qty'], fallback: 1);
      final finalBase = base > 0 ? base : 1;
      final q = _getSecondaryPieceQty(secId, name);
      final sets = q ~/ finalBase;
      if (minSets == null || sets < minSets) {
        minSets = sets;
      }
    }
    return minSets ?? 0;
  }

  bool _isSecondaryTableSetIncluded(Map<String, dynamic> secCat) {
    final tableComps = CategoryStockHelper.getTableComponents(secCat['components_json']);
    if (tableComps.isEmpty) return false;
    final secId = secCat['id'] as int;
    return tableComps.every((t) {
      final name = (t['name'] ?? '').toString().trim();
      return _getSecondaryPieceQty(secId, name) > 0;
    });
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

    final int secSets = secCat != null ? _computeSecondarySets(secCat) : 0;
    final bool secTablesIncluded =
        secCat != null ? _isSecondaryTableSetIncluded(secCat) : false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Divider(
                  color: Colors.teal.withValues(alpha: 0.4),
                  thickness: 1,
                ),
              ),
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
              Expanded(
                child: Divider(
                  color: Colors.teal.withValues(alpha: 0.4),
                  thickness: 1,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: isDark ? 0.08 : 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled
                  ? Colors.teal.withValues(alpha: 0.5)
                  : AppTheme.borderColor(context),
            ),
          ),
          child: Column(
            children: [
              CheckboxListTile(
                value: enabled,
                activeColor: const Color(0xFF0D9488),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                title: Row(
                  children: [
                    const Icon(Icons.add_box_outlined, color: Color(0xFF0D9488), size: 19),
                    const SizedBox(width: 8),
                    Text(
                      'إضافة قطع من طقم آخر',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: tealAccent,
                      ),
                    ),
                  ],
                ),
                onChanged: (checked) => onToggleEnabled(checked ?? false),
              ),
              if (enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: otherCategories.isEmpty
                      ? Text(
                          'لا توجد أصناف أخرى مسجلة حالياً.',
                          style: TextStyle(
                            color: AppTheme.textMuted(context),
                            fontSize: 12.5,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SearchableSelectFormField<int>(
                              key: ValueKey('sec_cat_${selectedSecondaryCategoryId ?? 'none'}'),
                              value: selectedSecondaryCategoryId,
                              labelText: 'اختر الطقم الآخر *',
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
                              const SizedBox(height: 8),
                              // 1. عداد الأطقم الكاملة من هذا الصنف
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: tealAccent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: tealAccent.withValues(alpha: 0.25)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.inventory_2_outlined, color: tealAccent, size: 17),
                                        const SizedBox(width: 6),
                                        Text(
                                          'أطقم كاملة من هذا الصنف:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                            color: tealAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Material(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(6),
                                            onTap: secSets > 0
                                                ? () {
                                                    final newCount = secSets - 1;
                                                    if (onSecondarySetsChanged != null) {
                                                      onSecondarySetsChanged!(secCat, newCount);
                                                    } else {
                                                      applySecondarySetsCount(
                                                        editableComponents: editableComponents,
                                                        secCat: secCat,
                                                        newSetsCount: newCount,
                                                      );
                                                    }
                                                  }
                                                : null,
                                            child: const Padding(
                                              padding: EdgeInsets.all(4.0),
                                              child: Icon(Icons.remove, color: Colors.red, size: 16),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          constraints: const BoxConstraints(minWidth: 30),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '$secSets',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: tealAccent,
                                            ),
                                          ),
                                        ),
                                        Material(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(6),
                                            onTap: () {
                                              final newCount = secSets + 1;
                                              if (onSecondarySetsChanged != null) {
                                                onSecondarySetsChanged!(secCat, newCount);
                                              } else {
                                                applySecondarySetsCount(
                                                  editableComponents: editableComponents,
                                                  secCat: secCat,
                                                  newSetsCount: newCount,
                                                );
                                              }
                                            },
                                            child: const Padding(
                                              padding: EdgeInsets.all(4.0),
                                              child: Icon(Icons.add, color: Colors.green, size: 16),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // 2. تضمين طقم ترابيزات هذا الصنف
                              if (CategoryStockHelper.hasTables(secCat)) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: secTablesIncluded
                                        ? const Color(0xFF0D9488).withValues(alpha: 0.08)
                                        : AppTheme.subtleBg(context),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: secTablesIncluded
                                          ? const Color(0xFF0D9488).withValues(alpha: 0.35)
                                          : AppTheme.borderColor(context),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Icon(
                                              Icons.table_restaurant_rounded,
                                              color: Color(0xFF0D9488),
                                              size: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'طقم ترابيزات الصنف كامل بمكوناته',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: Color(0xFF0F766E),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Transform.scale(
                                        scale: 0.85,
                                        child: Switch.adaptive(
                                          value: secTablesIncluded,
                                          activeThumbColor: const Color(0xFF0D9488),
                                          onChanged: (inc) {
                                            if (onSecondaryTablesChanged != null) {
                                              onSecondaryTablesChanged!(secCat, inc);
                                            } else {
                                              applySecondaryTableSet(
                                                editableComponents: editableComponents,
                                                secCat: secCat,
                                                include: inc,
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 8),
                              Text(
                                'القطع الفردية من هذا الطقم:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              ..._parseCategoryPieces(secCat).map((p) {
                                final String pName = p['name'] as String;
                                final int stockQ = p['stock_qty'] as int;
                                final int secId = secCat['id'] as int;
                                final int curQ = _getSecondaryPieceQty(secId, pName);

                                return Container(
                                  margin: const EdgeInsets.symmetric(vertical: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: curQ > 0
                                        ? AppTheme.cardBg(context)
                                        : AppTheme.cardBg(context).withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: curQ > 0
                                          ? Colors.teal.shade400
                                          : AppTheme.borderColor(context),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                pName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.5,
                                                  color: AppTheme.textBody(context),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '($stockQ بالمخزن)',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: AppTheme.textMuted(context),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                        icon: Icon(
                                          Icons.remove_circle_outline,
                                          color: curQ > 0 ? Colors.red.shade600 : Colors.grey,
                                          size: 19,
                                        ),
                                        onPressed: curQ > 0
                                            ? () => onPieceQtyChanged(secCat, pName, curQ - 1)
                                            : null,
                                      ),
                                      Container(
                                        constraints: const BoxConstraints(minWidth: 24),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '$curQ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13.5,
                                            color: AppTheme.textPrimary(context),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                        icon: Icon(
                                          Icons.add_circle_outline,
                                          color: Colors.green.shade600,
                                          size: 19,
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
