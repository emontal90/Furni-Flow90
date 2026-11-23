import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// عنصر يمثل خياراً ضمن القائمة القابلة للبحث
class SearchableSelectItem<T> {
  final T value;
  final String label;
  final String? subtitle;
  final String? badge;
  final String? searchKey;

  const SearchableSelectItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.badge,
    this.searchKey,
  });
}

/// حقل اختيار منسدل مزوّد بنافذة بحث سريعة وفورية للأصناف والعملاء
class SearchableSelectFormField<T> extends StatelessWidget {
  final T? value;
  final List<SearchableSelectItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String labelText;
  final String? hintText;
  final String searchHint;
  final Widget? prefixIcon;
  final Widget? actionButton;
  final bool isExpanded;
  final bool enabled;

  const SearchableSelectFormField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.labelText,
    this.hintText,
    this.searchHint = 'اكتب للبحث السريع...',
    this.prefixIcon,
    this.actionButton,
    this.isExpanded = true,
    this.enabled = true,
  });

  SearchableSelectItem<T>? get _selectedItem {
    try {
      return items.firstWhere((item) => item.value == value);
    } catch (_) {
      return null;
    }
  }

  static String normalizeArabic(String text) {
    return text
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '') // إزالة التشكيل
        .trim()
        .toLowerCase();
  }

  void _openSearchModal(BuildContext context) {
    if (!enabled) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return _SearchablePickerSheet<T>(
          title: labelText.replaceAll('*', '').trim(),
          items: items,
          selectedValue: value,
          searchHint: searchHint,
          actionButton: actionButton,
          onSelected: (val) {
            Navigator.pop(modalCtx);
            onChanged(val);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedItem;

    return InkWell(
      onTap: enabled ? () => _openSearchModal(context) : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          prefixIcon: prefixIcon,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 18, color: Colors.grey.shade500),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, color: AppTheme.accentOnSurface(context)),
              const SizedBox(width: 8),
            ],
          ),
          filled: true,
          fillColor: enabled ? AppTheme.cardBg(context) : AppTheme.subtleBg(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        isEmpty: selected == null,
        child: selected == null
            ? (hintText != null && hintText!.isNotEmpty
                ? Text(
                    hintText!,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                  )
                : const SizedBox.shrink())
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      selected.label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected.badge != null && selected.badge!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: AppTheme.royalGold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.royalGold.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        selected.badge!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF854D0E),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _SearchablePickerSheet<T> extends StatefulWidget {
  final String title;
  final List<SearchableSelectItem<T>> items;
  final T? selectedValue;
  final String searchHint;
  final Widget? actionButton;
  final ValueChanged<T> onSelected;

  const _SearchablePickerSheet({
    required this.title,
    required this.items,
    required this.selectedValue,
    required this.searchHint,
    this.actionButton,
    required this.onSelected,
  });

  @override
  State<_SearchablePickerSheet<T>> createState() => _SearchablePickerSheetState<T>();
}

class _SearchablePickerSheetState<T> extends State<_SearchablePickerSheet<T>> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<SearchableSelectItem<T>> get _filteredItems {
    if (_query.trim().isEmpty) return widget.items;
    final normalizedQuery = SearchableSelectFormField.normalizeArabic(_query);
    return widget.items.where((item) {
      final normLabel = SearchableSelectFormField.normalizeArabic(item.label);
      if (normLabel.contains(normalizedQuery)) return true;
      if (item.searchKey != null) {
        final normKey = SearchableSelectFormField.normalizeArabic(item.searchKey!);
        if (normKey.contains(normalizedQuery)) return true;
      }
      if (item.subtitle != null) {
        final normSub = SearchableSelectFormField.normalizeArabic(item.subtitle!);
        if (normSub.contains(normalizedQuery)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final filtered = _filteredItems;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // مقبض السحب
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // ترويسة النافذة
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.manage_search_rounded, color: AppTheme.primaryNavy, size: 24),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.items.length}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryNavy),
                  ),
                ),
                const Spacer(),
                if (widget.actionButton != null) widget.actionButton!,
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // حقل البحث الفوري
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (val) => setState(() => _query = val),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search, color: AppTheme.primaryNavy, size: 22),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.subtleBg(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryNavy, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),

          // قائمة النتائج
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text(
                          'لا توجد نتائج مطابقة لـ "$_query"',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 14, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'تأكد من كتابة الاسم بشكل صحيح أو جرب كلمات أخرى',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 8, endIndent: 8),
                    itemBuilder: (ctx, idx) {
                      final item = filtered[idx];
                      final bool isSelected = item.value == widget.selectedValue;

                      return InkWell(
                        onTap: () => widget.onSelected(item.value),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primaryNavy.withValues(alpha: 0.08) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: isSelected
                                ? Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.3))
                                : null,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryNavy
                                      : AppTheme.primaryNavy.withValues(alpha: 0.06),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isSelected ? Icons.check_rounded : Icons.fiber_manual_record,
                                  size: isSelected ? 15 : 9,
                                  color: isSelected ? AppTheme.royalGold : AppTheme.primaryNavy,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.label,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        color: isSelected ? AppTheme.accentOnSurface(context) : AppTheme.textBody(context),
                                      ),
                                    ),
                                    if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.subtitle!,
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (item.badge != null && item.badge!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: Text(
                                    item.badge!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
