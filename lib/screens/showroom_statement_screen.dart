import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../components/app_logo.dart';
import '../core/app_events.dart';
import '../core/app_notification.dart';
import '../core/app_settings_service.dart';
import '../core/app_theme.dart';
import '../core/category_stock_helper.dart';
import '../core/db_helper.dart';
import '../core/share_helper.dart';
import '../core/showroom_statement_helper.dart';
import '../core/upholsterer_statement_helper.dart';

class ShowroomStatementScreen extends StatefulWidget {
  final String? initialCategoryFilter;

  const ShowroomStatementScreen({
    super.key,
    this.initialCategoryFilter,
  });

  @override
  State<ShowroomStatementScreen> createState() => _ShowroomStatementScreenState();
}

enum _ShowroomDatePreset { today, thisWeek, last7Days, thisMonth, lastMonth, all, custom }

class _ShowroomStatementScreenState extends State<ShowroomStatementScreen> {
  final GlobalKey _captureKey = GlobalKey();

  bool _isLoading = true;
  bool _isSharing = false;

  List<Map<String, dynamic>> _movements = [];
  List<Map<String, dynamic>> _categories = [];

  _ShowroomDatePreset _activePreset = _ShowroomDatePreset.thisMonth;
  DateTime? _fromDate;
  DateTime? _toDate;
  String _selectedCategory = 'all';
  String _selectedType = 'all';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = DateTime(now.year, now.month, now.day);

    if (widget.initialCategoryFilter != null &&
        widget.initialCategoryFilter!.trim().isNotEmpty) {
      _selectedCategory = widget.initialCategoryFilter!.trim();
    }

    _loadData();
    AppEvents.instance.refreshNotifier.addListener(_loadData);
  }

  @override
  void dispose() {
    AppEvents.instance.refreshNotifier.removeListener(_loadData);
    super.dispose();
  }

  Future<void> _loadData() async {
    final db = await DBHelper.instance.database;
    final movements = await db.query('stock_movements', orderBy: 'id DESC');
    final categories = await db.query('categories', orderBy: 'name ASC');

    if (mounted) {
      setState(() {
        _movements = movements;
        _categories = categories;
        _isLoading = false;
      });
    }
  }

  void _applyPreset(_ShowroomDatePreset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _activePreset = preset;
      switch (preset) {
        case _ShowroomDatePreset.today:
          _fromDate = today;
          _toDate = today;
          break;
        case _ShowroomDatePreset.thisWeek:
          final int daysSinceSaturday = (today.weekday + 1) % 7;
          final saturday = today.subtract(Duration(days: daysSinceSaturday));
          final thursday = saturday.add(const Duration(days: 5));
          _fromDate = saturday;
          _toDate = thursday;
          break;
        case _ShowroomDatePreset.last7Days:
          _fromDate = today.subtract(const Duration(days: 6));
          _toDate = today;
          break;
        case _ShowroomDatePreset.thisMonth:
          _fromDate = DateTime(now.year, now.month, 1);
          _toDate = today;
          break;
        case _ShowroomDatePreset.lastMonth:
          final prevMonthEnd = DateTime(now.year, now.month, 0);
          _fromDate = DateTime(prevMonthEnd.year, prevMonthEnd.month, 1);
          _toDate = prevMonthEnd;
          break;
        case _ShowroomDatePreset.all:
          _fromDate = null;
          _toDate = null;
          break;
        case _ShowroomDatePreset.custom:
          break;
      }
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_fromDate ?? DateTime(now.year, now.month, 1))
        : (_toDate ?? DateTime(now.year, now.month, now.day));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('ar', 'EG'),
      helpText: isFrom ? 'اختر تاريخ البداية (من)' : 'اختر تاريخ النهاية (إلى)',
    );
    if (picked == null || !mounted) return;

    setState(() {
      _activePreset = _ShowroomDatePreset.custom;
      final clean = DateTime(picked.year, picked.month, picked.day);
      if (isFrom) {
        _fromDate = clean;
        if (_toDate != null && _toDate!.isBefore(clean)) {
          _toDate = clean;
        }
      } else {
        _toDate = clean;
        if (_fromDate != null && _fromDate!.isAfter(clean)) {
          _fromDate = clean;
        }
      }
    });
  }

  String _periodDisplayLabel() {
    if (_fromDate == null && _toDate == null) return 'جميع الفترات';
    final fromStr = _fromDate != null
        ? UpholstererStatementHelper.formatIsoDate(_fromDate!)
        : 'البداية';
    final toStr = _toDate != null
        ? UpholstererStatementHelper.formatIsoDate(_toDate!)
        : 'الآن';
    return 'من $fromStr إلى $toStr';
  }

  String _typeDisplayLabel() {
    switch (_selectedType) {
      case 'in':
        return 'وارد / إضافة للمخزن';
      case 'out':
        return 'صادر / خصم من المخزن';
      default:
        return 'جميع الحركات';
    }
  }

  Future<void> _shareStatement() async {
    if (_isSharing) return;

    final format = await ShareHelper.showExportFormatDialog(context);
    if (format == null || !mounted) return;

    setState(() => _isSharing = true);
    try {
      final showroomName = AppSettingsService.showroomProfileNotifier.value.displayName;
      final errorMsg = await ShareHelper.shareStatementToWhatsApp(
        boundaryKey: _captureKey,
        fileNamePrefix: 'showroom_statement',
        format: format,
        captionText: 'كشف حساب مخزن المعرض - $showroomName',
      );
      if (mounted && errorMsg != null) {
        AppNotification.showInfo(context, errorMsg);
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(context, 'تعذر مشاركة كشف الحساب: $e');
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  List<String> _collectCategories() {
    final Set<String> names = {};
    for (final c in _categories) {
      final n = (c['name'] ?? '').toString().trim();
      if (n.isNotEmpty) names.add(n);
    }
    for (final m in _movements) {
      final n = (m['category_name'] ?? '').toString().trim();
      if (n.isNotEmpty) names.add(n);
    }
    return names.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final availableCategories = _collectCategories();
    final String effectiveCat = (_selectedCategory != 'all' &&
            !availableCategories.contains(_selectedCategory))
        ? 'all'
        : _selectedCategory;

    final report = ShowroomStatementHelper.buildStatement(
      movements: _movements,
      categories: _categories,
      fromDate: _fromDate,
      toDate: _toDate,
      categoryNameFilter: effectiveCat,
      typeFilter: _selectedType,
    );

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg(context),
      appBar: AppBar(
        title: const AppBarTitleWithLogo(title: 'كشف حساب مخزن المعرض'),
        actions: [
          IconButton(
            tooltip: 'مشاركة كشف الحساب على واتساب (صورة / PDF)',
            onPressed: _isLoading || _isSharing ? null : _shareStatement,
            icon: _isSharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_rounded, color: Color(0xFF128C7E)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFiltersBar(
                  availableCategories: availableCategories,
                  effectiveCat: effectiveCat,
                ),
                if (report.movementsCount == 0 && report.totalMovementsBeforeDateFilter > 0)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.warningBg(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.warningBorder(context)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: AppTheme.warningFg(context), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'لا توجد حركات مخزن في هذه الفترة، رغم وجود (${report.totalMovementsBeforeDateFilter}) حركة في فترات أخرى.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.warningFg(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _applyPreset(_ShowroomDatePreset.all),
                          child: const Text('عرض الكل',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    child: RepaintBoundary(
                      key: _captureKey,
                      child: _ShowroomReceiptCard(
                        report: report,
                        periodLabel: _periodDisplayLabel(),
                        categoryLabel: effectiveCat == 'all' ? 'جميع الأصناف' : effectiveCat,
                        typeLabel: _typeDisplayLabel(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.filterBarBg(context),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF128C7E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            onPressed: _isLoading || _isSharing ? null : _shareStatement,
            icon: _isSharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : const Icon(Icons.share_rounded, size: 22),
            label: Text(
              _isSharing ? 'جاري تجهيز كشف الحساب...' : 'مشاركة كشف الحساب على واتساب (صورة / PDF)',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFiltersBar({
    required List<String> availableCategories,
    required String effectiveCat,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.filterBarBg(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPresetChip('اليوم', _ShowroomDatePreset.today),
                const SizedBox(width: 6),
                _buildPresetChip('هذا الأسبوع', _ShowroomDatePreset.thisWeek),
                const SizedBox(width: 6),
                _buildPresetChip('آخر 7 أيام', _ShowroomDatePreset.last7Days),
                const SizedBox(width: 6),
                _buildPresetChip('هذا الشهر', _ShowroomDatePreset.thisMonth),
                const SizedBox(width: 6),
                _buildPresetChip('الشهر الماضي', _ShowroomDatePreset.lastMonth),
                const SizedBox(width: 6),
                _buildPresetChip('الكل', _ShowroomDatePreset.all),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DatePickTile(
                  label: 'من تاريخ',
                  value: _fromDate != null
                      ? UpholstererStatementHelper.formatIsoDate(_fromDate!)
                      : 'البداية',
                  onTap: () => _pickDate(isFrom: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DatePickTile(
                  label: 'إلى تاريخ',
                  value: _toDate != null
                      ? UpholstererStatementHelper.formatIsoDate(_toDate!)
                      : 'الآن',
                  onTap: () => _pickDate(isFrom: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('showroom_cat_$effectiveCat'),
                  initialValue: effectiveCat,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'اسم الطقم / الصنف',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('جميع الأصناف', overflow: TextOverflow.ellipsis),
                    ),
                    ...availableCategories.map(
                      (c) => DropdownMenuItem<String>(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedCategory = v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('showroom_type_$_selectedType'),
                  initialValue: _selectedType,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'نوع الحركة',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: const [
                    DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('جميع الحركات', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem<String>(
                      value: 'in',
                      child: Text('وارد / إضافة (+)', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem<String>(
                      value: 'out',
                      child: Text('صادر / خصم (-)', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedType = v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, _ShowroomDatePreset preset) {
    final bool selected = _activePreset == preset;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: selected ? Colors.white : AppTheme.textPrimary(context),
        ),
      ),
      selected: selected,
      selectedColor: AppTheme.primaryNavy,
      backgroundColor: AppTheme.subtleBg(context),
      side: BorderSide(
        color: selected ? AppTheme.primaryNavy : AppTheme.borderColor(context),
      ),
      visualDensity: VisualDensity.compact,
      onSelected: (_) => _applyPreset(preset),
    );
  }
}

class _DatePickTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DatePickTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 15, color: AppTheme.accentOnSurface(context)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted(context)),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
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
}

/// بطاقة كشف حساب مخزن المعرض الرسمية القابلة للمشاركة كصورة أو PDF
class _ShowroomReceiptCard extends StatelessWidget {
  final ShowroomStatementReport report;
  final String periodLabel;
  final String categoryLabel;
  final String typeLabel;

  const _ShowroomReceiptCard({
    required this.report,
    required this.periodLabel,
    required this.categoryLabel,
    required this.typeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final issuedAt = intl.DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now());
    final currentStockSummary = CategoryStockHelper.formatSetsAndIndividual(
      report.totalCurrentSets,
      report.totalCurrentIndividualPieces,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.18), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. الترويسة الرسمية للكشف
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryNavy, Color(0xFF28507D)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: Row(
              children: [
                const AppLogo(size: 46),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'كشف حساب مخزن المعرض',
                        style: TextStyle(
                          color: AppTheme.royalGold,
                          fontWeight: FontWeight.bold,
                          fontSize: 16.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'جرد وحركات المخزن • ${AppSettingsService.showroomProfileNotifier.value.displayName}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.royalGold.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    UpholstererStatementHelper.formatIsoDate(DateTime.now()),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. شريط معايير الفلتر النشط
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: const Color(0xFFF1F5F9),
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _MetaBadge(
                  icon: Icons.date_range_rounded,
                  label: 'الفترة:',
                  value: periodLabel,
                ),
                _MetaBadge(
                  icon: Icons.weekend_rounded,
                  label: 'الصنف:',
                  value: categoryLabel,
                ),
                _MetaBadge(
                  icon: Icons.swap_vert_rounded,
                  label: 'النوع:',
                  value: typeLabel,
                ),
              ],
            ),
          ),

          // 3. بطاقات الملخص الإجمالي
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SummaryBox(
                        title: 'الرصيد الحالي بالمخزن',
                        value: currentStockSummary,
                        subtitle: '${report.totalCurrentPieces} قطعة إجمالاً',
                        color: AppTheme.primaryNavy,
                        bgColor: const Color(0xFFEFF6FF),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryBox(
                        title: 'إجمالي الحركات',
                        value: '${report.movementsCount} حركة',
                        subtitle: 'وارد: ${report.incomingCount} | صادر: ${report.outgoingCount}',
                        color: const Color(0xFF0F766E),
                        bgColor: const Color(0xFFF0FDFA),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4. ملخص الأصناف بالمخزن
                const _SectionTitle(
                  icon: Icons.inventory_2_rounded,
                  title: 'ملخص الرصيد والحركات حسب الصنف',
                ),
                const SizedBox(height: 8),
                if (report.categorySummaries.isEmpty)
                  const _EmptySectionBox(message: 'لا توجد أصناف مطابقة للفلاتر المحددة.')
                else
                  ...report.categorySummaries.map((cat) {
                    final catStock = CategoryStockHelper.formatSetsAndIndividual(
                      cat.currentSets,
                      cat.currentIndividualPieces,
                    );
                    return Container(
                      margin: const EdgeInsets.only(bottom: 7),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cat.categoryName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                    color: AppTheme.primaryNavy,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'حركات الفترة: ${cat.movementsCount} (وارد ${cat.incomingCount} • صادر ${cat.outgoingCount})',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$catStock (${cat.currentTotalPieces} ق)',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryNavy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                const SizedBox(height: 16),

                // 5. سجل الحركات التفصيلي
                const _SectionTitle(
                  icon: Icons.receipt_long_rounded,
                  title: 'سجل حركات المخزن التفصيلي',
                ),
                const SizedBox(height: 8),
                if (report.items.isEmpty)
                  const _EmptySectionBox(message: 'لا توجد حركات مسجلة في هذه الفترة.')
                else
                  ...report.items.map((item) {
                    final Color badgeColor = item.isIncoming
                        ? const Color(0xFF15803D)
                        : (item.isOutgoing ? const Color(0xFFB91C1C) : AppTheme.primaryNavy);
                    final Color badgeBg = item.isIncoming
                        ? const Color(0xFFDCFCE7)
                        : (item.isOutgoing ? const Color(0xFFFEE2E2) : const Color(0xFFDBEAFE));

                    return Container(
                      margin: const EdgeInsets.only(bottom: 7),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.categoryName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppTheme.primaryNavy,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.typeLabel,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: badgeColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (item.notes.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.notes,
                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item.dateDisplay,
                                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                              ),
                              Text(
                                item.qtyChange != 0
                                    ? 'التغير: ${item.qtyChange > 0 ? '+' : ''}${item.qtyChange} | الرصيد: ${item.stockAfter}'
                                    : 'الرصيد بعد الحركة: ${item.stockAfter}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),

          // 6. التذييل الرسمي
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: const Color(0xFFF8FAFC),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'تاريخ الإصدار: $issuedAt',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                ),
                Text(
                  AppSettingsService.showroomProfileNotifier.value.displayName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryNavy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaBadge({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.primaryNavy),
          const SizedBox(width: 4),
          Text(
            '$label ',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryNavy,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final Color bgColor;

  const _SummaryBox({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppTheme.primaryNavy),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryNavy,
          ),
        ),
      ],
    );
  }
}

class _EmptySectionBox extends StatelessWidget {
  final String message;

  const _EmptySectionBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
    );
  }
}
