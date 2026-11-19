import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../components/app_logo.dart';
import '../core/app_events.dart';
import '../core/app_notification.dart';
import '../core/app_settings_service.dart';
import '../core/app_theme.dart';
import '../core/db_helper.dart';
import '../core/delivered_statement_helper.dart';
import '../core/share_helper.dart';
import '../core/upholsterer_statement_helper.dart';

class DeliveredStatementScreen extends StatefulWidget {
  final String? initialCategoryFilter;
  final String? initialCustomerFilter;
  final List<Map<String, dynamic>>? preloadedOrders;
  final List<Map<String, dynamic>>? preloadedCategories;

  const DeliveredStatementScreen({
    super.key,
    this.initialCategoryFilter,
    this.initialCustomerFilter,
    this.preloadedOrders,
    this.preloadedCategories,
  });

  @override
  State<DeliveredStatementScreen> createState() =>
      _DeliveredStatementScreenState();
}

enum _DeliveredDatePreset { today, last7Days, thisMonth, lastMonth, all, custom }

class _DeliveredStatementScreenState extends State<DeliveredStatementScreen> {
  final GlobalKey _captureKey = GlobalKey();

  bool _isLoading = true;
  bool _isSharing = false;

  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _categories = [];

  _DeliveredDatePreset _activePreset = _DeliveredDatePreset.thisMonth;
  DateTime? _fromDate;
  DateTime? _toDate;
  String _selectedCategory = 'all';
  String _selectedCustomer = 'all';

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
    if (widget.initialCustomerFilter != null &&
        widget.initialCustomerFilter!.trim().isNotEmpty) {
      _selectedCustomer = widget.initialCustomerFilter!.trim();
    }

    if (widget.preloadedOrders != null || widget.preloadedCategories != null) {
      _orders = widget.preloadedOrders ?? const [];
      _categories = widget.preloadedCategories ?? const [];
      _isLoading = false;
    } else {
      _loadData();
      AppEvents.instance.refreshNotifier.addListener(_loadData);
    }
  }

  @override
  void dispose() {
    if (widget.preloadedOrders == null && widget.preloadedCategories == null) {
      AppEvents.instance.refreshNotifier.removeListener(_loadData);
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    final db = await DBHelper.instance.database;
    final orders = await db.query('orders', where: "status = 'delivered'", orderBy: 'id DESC');
    final categories = await db.query('categories', orderBy: 'name ASC');

    if (mounted) {
      setState(() {
        _orders = orders;
        _categories = categories;
        _isLoading = false;
      });
    }
  }

  void _applyPreset(_DeliveredDatePreset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _activePreset = preset;
      switch (preset) {
        case _DeliveredDatePreset.today:
          _fromDate = today;
          _toDate = today;
          break;
        case _DeliveredDatePreset.last7Days:
          _fromDate = today.subtract(const Duration(days: 6));
          _toDate = today;
          break;
        case _DeliveredDatePreset.thisMonth:
          _fromDate = DateTime(now.year, now.month, 1);
          _toDate = today;
          break;
        case _DeliveredDatePreset.lastMonth:
          final prevMonthEnd = DateTime(now.year, now.month, 0);
          _fromDate = DateTime(prevMonthEnd.year, prevMonthEnd.month, 1);
          _toDate = prevMonthEnd;
          break;
        case _DeliveredDatePreset.all:
          _fromDate = null;
          _toDate = null;
          break;
        case _DeliveredDatePreset.custom:
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
      _activePreset = _DeliveredDatePreset.custom;
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

  Future<void> _shareAsImage() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final showroomName = AppSettingsService.showroomProfileNotifier.value.displayName;
      final errorMsg = await ShareHelper.captureAndShareToWhatsApp(
        boundaryKey: _captureKey,
        fileNamePrefix: 'delivered_statement',
        captionText: 'كشف حساب التسليمات - $showroomName',
      );
      if (mounted && errorMsg != null) {
        AppNotification.showInfo(context, errorMsg);
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(context, 'تعذر تصدير صورة كشف الحساب: $e');
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
    for (final o in _orders) {
      final n = (o['category_name'] ?? '').toString().trim();
      if (n.isNotEmpty) names.add(n);
    }
    return names.toList()..sort();
  }

  List<String> _collectCustomers() {
    final Set<String> names = {};
    for (final o in _orders) {
      final n = (o['customer_name'] ?? '').toString().trim();
      if (n.isNotEmpty) names.add(n);
    }
    return names.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final availableCategories = _collectCategories();
    final availableCustomers = _collectCustomers();

    final String effectiveCat = (_selectedCategory != 'all' &&
            !availableCategories.contains(_selectedCategory))
        ? 'all'
        : _selectedCategory;
    final String effectiveCust = (_selectedCustomer != 'all' &&
            !availableCustomers.contains(_selectedCustomer))
        ? 'all'
        : _selectedCustomer;

    final report = DeliveredStatementHelper.buildStatement(
      deliveredOrders: _orders,
      categories: _categories,
      fromDate: _fromDate,
      toDate: _toDate,
      categoryNameFilter: effectiveCat,
      customerNameFilter: effectiveCust,
    );

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg(context),
      appBar: AppBar(
        title: const AppBarTitleWithLogo(title: 'كشف حساب التسليمات'),
        actions: [
          IconButton(
            tooltip: 'مشاركة كشف الحساب على واتساب كصورة',
            onPressed: _isLoading || _isSharing ? null : _shareAsImage,
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
                  availableCustomers: availableCustomers,
                  effectiveCat: effectiveCat,
                  effectiveCust: effectiveCust,
                ),
                if (report.isEmpty && report.totalOrdersBeforeDateFilter > 0)
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
                            'لا توجد تسليمات في هذه الفترة، رغم وجود (${report.totalOrdersBeforeDateFilter}) طلب في فترات أخرى.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.warningFg(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _applyPreset(_DeliveredDatePreset.all),
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
                      child: _DeliveredReceiptCard(
                        report: report,
                        periodLabel: _periodDisplayLabel(),
                        categoryLabel: effectiveCat == 'all' ? 'جميع الأصناف' : effectiveCat,
                        customerLabel: effectiveCust == 'all' ? 'جميع العملاء' : effectiveCust,
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
            onPressed: _isLoading || _isSharing ? null : _shareAsImage,
            icon: _isSharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : const Icon(Icons.share_rounded, size: 22),
            label: Text(
              _isSharing ? 'جاري تجهيز صورة الكشف...' : 'مشاركة كشف الحساب على واتساب (صورة)',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFiltersBar({
    required List<String> availableCategories,
    required List<String> availableCustomers,
    required String effectiveCat,
    required String effectiveCust,
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
                _buildPresetChip('اليوم', _DeliveredDatePreset.today),
                const SizedBox(width: 6),
                _buildPresetChip('آخر 7 أيام', _DeliveredDatePreset.last7Days),
                const SizedBox(width: 6),
                _buildPresetChip('هذا الشهر', _DeliveredDatePreset.thisMonth),
                const SizedBox(width: 6),
                _buildPresetChip('الشهر الماضي', _DeliveredDatePreset.lastMonth),
                const SizedBox(width: 6),
                _buildPresetChip('الكل', _DeliveredDatePreset.all),
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
                  key: ValueKey('deliv_cat_$effectiveCat'),
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
                    ...availableCategories.map((cat) => DropdownMenuItem<String>(
                          value: cat,
                          child: Text(cat, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('deliv_cust_$effectiveCust'),
                  initialValue: effectiveCust,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'اسم العميل',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('جميع العملاء', overflow: TextOverflow.ellipsis),
                    ),
                    ...availableCustomers.map((c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCustomer = val);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, _DeliveredDatePreset preset) {
    final selected = _activePreset == preset;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _applyPreset(preset),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryNavy : AppTheme.subtleBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.brightGold : AppTheme.borderColor(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? AppTheme.brightGold : AppTheme.textBody(context),
          ),
        ),
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.subtleBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_rounded, size: 18, color: AppTheme.accentOnSurface(context)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 10, color: AppTheme.textMuted(context))),
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

/// بطاقة كشف حساب تم التسليم الرسمية (خلفية بيضاء نظيفة دائماً للتصوير والمشاركة كإيصال رسمي)
class _DeliveredReceiptCard extends StatelessWidget {
  final DeliveredStatementReport report;
  final String periodLabel;
  final String categoryLabel;
  final String customerLabel;

  const _DeliveredReceiptCard({
    required this.report,
    required this.periodLabel,
    required this.categoryLabel,
    required this.customerLabel,
  });

  @override
  Widget build(BuildContext context) {
    final showroomName = AppSettingsService.showroomProfileNotifier.value.displayName;
    final issuedAt = intl.DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now());
    final summaryBadge = UpholstererStatementHelper.formatSetsAndIndividual(
      report.totalSets,
      report.totalIndividualPieces,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.2), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. الترويسة الرسمية
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryNavy, Color(0xFF15803D)],
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
                        'كشف حساب الطلبات المسلّمة',
                        maxLines: 1,
                        style: TextStyle(
                          color: AppTheme.royalGold,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ملخص التسليمات للعملاء • $showroomName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.royalGold.withValues(alpha: 0.6)),
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

          // 2. شريط الفلاتر النشطة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: const Color(0xFFF1F5F9),
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _ReceiptBadge(icon: Icons.date_range_rounded, label: 'الفترة:', value: periodLabel),
                _ReceiptBadge(icon: Icons.weekend_rounded, label: 'الصنف:', value: categoryLabel),
                if (customerLabel != 'جميع العملاء')
                  _ReceiptBadge(icon: Icons.person_rounded, label: 'العميل:', value: customerLabel),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 3. بطاقة الملخص الإجمالي
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBBF7D0), width: 1.2),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.task_alt_rounded, size: 18, color: Color(0xFF15803D)),
                          SizedBox(width: 6),
                          Text(
                            'إجمالي ما تم تسليمه للعملاء',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '${report.totalSets}',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF15803D),
                                  ),
                                ),
                                const Text('طقم كامل', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 32, color: const Color(0xFFBBF7D0)),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '${report.totalIndividualPieces}',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFD97706),
                                  ),
                                ),
                                const Text('قطعة فردي', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 32, color: const Color(0xFFBBF7D0)),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '${report.ordersCount}',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primaryNavy,
                                  ),
                                ),
                                const Text('طلبية مسلّمة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'إجمالي القطع المسلّمة: ${report.totalPieces} قطعة • الإجمالي: $summaryBadge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 4. تفصيل الأصناف المسلّمة بنمط الكشكول اليدوي
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        color: const Color(0xFFF0FDF4),
                        child: Row(
                          children: [
                            const Icon(Icons.weekend_rounded, size: 18, color: Color(0xFF15803D)),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'ملخص الأصناف المسلّمة',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF15803D),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                report.isEmpty ? '0' : summaryBadge,
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
                      if (report.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 20),
                          child: Text(
                            'لا توجد تسليمات مسجلة خلال هذه الفترة.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Column(
                            children: report.categorySummaries.asMap().entries.map((entry) {
                              final idx = entry.key + 1;
                              final cat = entry.value;
                              final compactText = UpholstererStatementHelper.formatCompactLine(
                                categoryName: cat.categoryName,
                                sets: cat.sets,
                                excessPieces: cat.excessPieceTotals,
                              );
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.blueGrey.shade100),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF15803D).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '$idx',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF15803D),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: AlignmentDirectional.centerStart,
                                        child: Text(
                                          compactText,
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryNavy,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '(${cat.totalPieces} ق)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                Divider(color: Colors.grey.shade200, height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$showroomName • كشف حساب التسليمات',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      issuedAt,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ReceiptBadge({
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
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.5, color: AppTheme.primaryNavy),
          const SizedBox(width: 4),
          Text('$label ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 11.5, color: AppTheme.primaryNavy, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
