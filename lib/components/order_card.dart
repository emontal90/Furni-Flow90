import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../core/order_delivery_helper.dart';
import '../core/stock_movement_helper.dart';

class OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<dynamic>? categoryComponents;
  final VoidCallback? onDeliverPressed;
  final VoidCallback? onEditPressed;
  final VoidCallback? onDeletePressed;
  final bool isDelivered;
  final bool collapsible;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;

  const OrderCard({
    super.key,
    required this.order,
    this.categoryComponents,
    this.onDeliverPressed,
    this.onEditPressed,
    this.onDeletePressed,
    this.isDelivered = false,
    this.collapsible = false,
    this.isExpanded = true,
    this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    List comps = [];
    try {
      comps = jsonDecode(order['selected_components_json']);
    } catch (_) {}

    final createdAtRaw = order['created_at']?.toString() ?? '';
    final createdAtFormatted = createdAtRaw.isNotEmpty
        ? StockMovementHelper.formatDateString12(createdAtRaw)
        : '';

    final int? setsCount = (order['sets_count'] as int?);
    final summary = OrderDeliveryHelper.summarizeOrder(
      orderComps: comps,
      rawCategoryComps: categoryComponents ?? const [],
      fallbackSetsCount: setsCount ?? 0,
    );
    final String? statusBadgeText = summary.toStatusBadgeLabel();
    final Color statusBadgeColor = summary.status == OrderCompletenessStatus.complete
        ? const Color(0xFFEF6C00) // برتقالي للـ كامل
        : const Color(0xFFA16207); // أصفر غامق للـ زائد والناقص

    final String orderTypeStr = (order['order_type'] ?? '').toString().trim();
    final bool isCustomOrderType =
        orderTypeStr != 'نمطي' && orderTypeStr != 'نمطى' && orderTypeStr.isNotEmpty;
    final Color orderTypeBgColor =
        isCustomOrderType ? Colors.red.shade700 : AppTheme.primaryNavy;

    final int totalPieces = summary.totalPieces;
    final String deliveryDateStr = order['delivery_date']?.toString() ?? 'غير محدد';
    final double totalPrice = (order['total_price'] is num)
        ? (order['total_price'] as num).toDouble()
        : (double.tryParse('${order['total_price'] ?? 0}') ?? 0.0);
    final double paidAmount = (order['paid_amount'] is num)
        ? (order['paid_amount'] as num).toDouble()
        : (double.tryParse('${order['paid_amount'] ?? 0}') ?? 0.0);
    final double remainingAmount = (totalPrice - paidAmount) > 0 ? (totalPrice - paidAmount) : 0.0;
    final bool hasFinancials = totalPrice > 0 || paidAmount > 0;
    final bool showDetails = !collapsible || isExpanded;

    final Widget cardBody = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 12.0,
        vertical: collapsible && !isExpanded ? 10.0 : 12.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // الصف الأول: اسم العميل وموعد التسليم (ملخص مضغوط بارتفاع صغير)
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(collapsible ? 6 : 8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.person_pin_rounded,
                  color: AppTheme.primaryNavy,
                  size: collapsible ? 20 : 24,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        '${order['customer_name']}',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: collapsible ? 15.5 : 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                    if (collapsible) ...[
                      const SizedBox(height: 3),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(
                            'طقم: ${order['category_name']}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: AppTheme.textBody(context),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: orderTypeBgColor,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              orderTypeStr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (statusBadgeText != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: statusBadgeColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                statusBadgeText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (totalPieces > 0)
                            Text(
                              '($totalPieces قطعة)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.brown.shade700,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // موعد التسليم المميز
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDelivered
                        ? [const Color(0xFF15803D), const Color(0xFF166534)]
                        : [const Color(0xFFD97706), const Color(0xFFB45309)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: (isDelivered ? Colors.green : Colors.amber.shade900)
                          .withValues(alpha: 0.22),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDelivered ? Icons.task_alt_rounded : Icons.alarm_on_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isDelivered ? 'تم التسليم' : 'التسليم:',
                          style: const TextStyle(
                            fontSize: 8.5,
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          deliveryDateStr,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (collapsible) ...[
                const SizedBox(width: 4),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey.shade600,
                  size: 24,
                ),
              ],
            ],
          ),

          if (showDetails) ...[
            if (!collapsible) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              // الصف الثاني (للكروت غير المطوية كقائمة تم التسليم)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.12)),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    const Icon(Icons.weekend_rounded, size: 18, color: AppTheme.primaryNavy),
                    Text(
                      'طقم: ${order['category_name']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppTheme.primaryNavy),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: orderTypeBgColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        orderTypeStr,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (statusBadgeText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusBadgeColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          statusBadgeText,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
            ],
            const SizedBox(height: 8),

            // الصف الثالث: عرض مكونات وقطع الطلب
            Text(
              'قطع ومكونات الطلب:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textBody(context)),
            ),
            const SizedBox(height: 6),
            if (comps.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: comps.map((c) {
                  final String pieceName = (c['name'] ?? '').toString();
                  final int pieceCount = (c['qty'] is int)
                      ? c['qty'] as int
                      : (int.tryParse(c['qty']?.toString() ?? '0') ?? 0);

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: pieceCount > 0 ? AppTheme.infoBg(context) : AppTheme.subtleBg(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: pieceCount > 0 ? AppTheme.infoBorder(context) : AppTheme.borderColor(context),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chair_rounded,
                          size: 14,
                          color: pieceCount > 0 ? AppTheme.infoFg(context) : AppTheme.textMuted(context),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          pieceName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            color: pieceCount > 0 ? AppTheme.infoFg(context) : AppTheme.textMuted(context),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: pieceCount > 0 ? AppTheme.primaryNavy : Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '$pieceCount',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              )
            else
              Text(
                'طقم ${order['category_name']} كامل بجميع قطعه',
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),

            // المواصفات إن وجدت
            if (order['specs'] != null && order['specs'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.warningBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.warningBorder(context)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notes_rounded, size: 16, color: Colors.amber.shade900),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'المواصفات: ${order['specs']}',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.warningFg(context),
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // الملخص المالي الاختياري (يظهر فقط عند إدخال سعر أو عربون)
            if (hasFinancials) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: AppTheme.isDark(context) ? 0.14 : 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.withValues(alpha: 0.35)),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      'الإجمالي: ${totalPrice.toStringAsFixed(0)} ج',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    Text(
                      'المدفوع: ${paidAmount.toStringAsFixed(0)} ج',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                    Text(
                      'المتبقي: ${remainingAmount.toStringAsFixed(0)} ج',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: remainingAmount > 0 ? Colors.red.shade600 : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // تاريخ ووقت تسجيل الطلب بخط صغير
            if (createdAtFormatted.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'تاريخ تسجيل الطلب: $createdAtFormatted',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],

            // أزرار العمليات للطلبات المسلّمة (زر الحذف بسلة المهملات الصغير كما في تسليم المنجد)
            if (isDelivered && onDeletePressed != null) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'حذف هذا الطلب المسلّم',
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onDeletePressed,
                  ),
                  const SizedBox.shrink(),
                ],
              ),
            ],

            // أزرار العمليات (إلغاء الطلب / تعديل الطلب / تسليم الطلب)
            if (!isDelivered && (onDeletePressed != null || onEditPressed != null || onDeliverPressed != null)) ...[
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (onDeletePressed != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: onDeletePressed,
                      icon: const Icon(Icons.cancel_outlined, size: 14),
                      label: const Text(
                        'إلغاء الطلب',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                      ),
                    ),
                  if (onEditPressed != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: AppTheme.royalGold,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: onEditPressed,
                      icon: const Icon(Icons.edit, size: 14),
                      label: const Text(
                        'تعديل الطلب',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                      ),
                    ),
                  if (onDeliverPressed != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: onDeliverPressed,
                      icon: const Icon(Icons.check_circle, size: 14),
                      label: const Text(
                        'تسليم الطلب',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );

    return Card(
      elevation: (collapsible && isExpanded) ? 3 : 1.5,
      margin: EdgeInsets.symmetric(vertical: collapsible ? 5 : 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDelivered
              ? (collapsible && isExpanded
                  ? Colors.green.shade500
                  : Colors.green.shade200)
              : (collapsible && isExpanded
                  ? AppTheme.royalGold
                  : AppTheme.royalGold.withValues(alpha: 0.4)),
          width: (collapsible && isExpanded) ? 1.5 : 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: collapsible
          ? InkWell(
              onTap: onToggleExpand,
              borderRadius: BorderRadius.circular(16),
              child: cardBody,
            )
          : cardBody,
    );
  }
}
