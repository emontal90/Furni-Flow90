import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import '../components/app_logo.dart';
import '../core/app_notification.dart';
import '../core/app_theme.dart';
import '../core/cloud_service.dart';
import '../core/license_service.dart';

class SubscriptionScreen extends StatefulWidget {
  final String deviceCode;
  const SubscriptionScreen({super.key, required this.deviceCode});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  // Step 0: Plan Selection, Step 1: Payment Details, Step 2: Awaiting Activation
  int _currentStep = 0;
  SubscriptionPlan _selectedPlan = SubscriptionPlan.plans[1]; // 6 months default
  PaymentMethod _paymentMethod = PaymentMethod.vodafoneCash;

  final TextEditingController _senderPhoneController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  bool _isCheckingStatus = false;
  CloudSubscriptionData? _currentCloudSub;

  @override
  void initState() {
    super.initState();
    _checkInitialStatus();
  }

  @override
  void dispose() {
    _senderPhoneController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialStatus() async {
    setState(() => _isCheckingStatus = true);
    final sub = await CloudService.checkAndSyncSubscriptionStatus(widget.deviceCode);
    if (mounted) {
      setState(() {
        _currentCloudSub = sub;
        _isCheckingStatus = false;
        if (sub != null && sub.isPending) {
          _currentStep = 2; // مباشرة لصفحة انتظار التفعيل
        }
      });
    }
  }

  Future<void> _manualCheckActivation() async {
    setState(() => _isCheckingStatus = true);
    final sub = await CloudService.checkAndSyncSubscriptionStatus(widget.deviceCode);
    if (mounted) {
      setState(() {
        _currentCloudSub = sub;
        _isCheckingStatus = false;
      });

      if (sub != null && sub.isActive) {
        AppNotification.showSuccess(
          context,
          'تهانينا! تم تفعيل اشتراكك التجاري بنجاح حتى ${sub.expiresAt != null ? intl.DateFormat('yyyy-MM-dd').format(sub.expiresAt!) : 'دائم'}',
        );
        Navigator.pop(context, true);
      } else if (sub != null && sub.isPaused) {
        AppNotification.showError(
          context,
          'اشتراكك متوقف مؤقتاً من قِبل الإدارة. يرجى مراجعة الدعم الفني.',
        );
      } else {
        AppNotification.showInfo(
          context,
          'طلبك قيد المراجعة والمطابقة المالية لدى الإدارة. يرجى المحاولة بعد لحظات.',
        );
      }
    }
  }

  Future<void> _showOfflineActivationDialog() async {
    final keyCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: AppTheme.accentOnSurface(dCtx)),
            const SizedBox(width: 8),
            const Text('إدخال كود التفعيل اليدوي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'إذا حصلت على كود تفعيل مباشر من الإدارة، يمكنك لصقه هنا للتفعيل فوراً بدون اتصال سحابي:',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted(dCtx)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyCtrl,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'كود التفعيل التجاري',
                hintText: 'MTK-PERM-XXXXXXXX',
                prefixIcon: Icon(Icons.vpn_key_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: AppTheme.royalGold,
            ),
            onPressed: () async {
              final err = await LicenseService.activateWithKey(keyCtrl.text);
              if (err != null) {
                if (mounted) AppNotification.showError(context, err);
                return;
              }
              if (dCtx.mounted) Navigator.pop(dCtx);
              if (mounted) {
                AppNotification.showSuccess(context, 'تم تفعيل النسخة بنجاح!');
                Navigator.pop(context, true);
              }
            },
            child: const Text('تفعيل الآن', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showConfirmationDialog() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = _senderPhoneController.text.trim();
    final ref = _referenceController.text.trim();
    final methodName = _paymentMethod == PaymentMethod.vodafoneCash ? 'فودافون كاش (Vodafone Cash)' : 'انستا باي (InstaPay)';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: AppTheme.accentOnSurface(dCtx), size: 26),
            const SizedBox(width: 8),
            const Text('تأكيد بيانات التحويل', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'يرجى مراجعة ملخص عملية الدفع قبل الإرسال للإدارة:',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted(dCtx)),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.subtleBg(dCtx),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor(dCtx)),
              ),
              child: Column(
                children: [
                  _summaryRow(dCtx, 'الباقة المختارة:', '${_selectedPlan.title} (${_selectedPlan.durationText})'),
                  const Divider(height: 16),
                  _summaryRow(dCtx, 'المبلغ المطلوب:', '${_selectedPlan.price} جنيه مصري', highlight: true),
                  const Divider(height: 16),
                  _summaryRow(dCtx, 'طريقة الدفع:', methodName),
                  const Divider(height: 16),
                  _summaryRow(dCtx, 'رقم المحفظة المحول منها:', phone),
                  const Divider(height: 16),
                  _summaryRow(dCtx, 'رقم العملية / المرجع:', ref),
                  const Divider(height: 16),
                  _summaryRow(dCtx, 'معرف جهازك:', widget.deviceCode),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('تعديل البيانات'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('تأكيد وإرسال للإدارة', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _executePaymentSubmission();
    }
  }

  Future<void> _executePaymentSubmission() async {
    setState(() => _isSubmitting = true);

    final res = await CloudService.submitSubscriptionRequest(
      deviceCode: widget.deviceCode,
      senderPhone: _senderPhoneController.text.trim(),
      referenceNo: _referenceController.text.trim(),
      paymentMethod: _paymentMethod,
      plan: _selectedPlan,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (res.success) {
        setState(() {
          _currentCloudSub = res.data;
          _currentStep = 2; // انتقال لصفحة انتظار التفعيل
        });
        AppNotification.showSuccess(
          context,
          'تم إرسال طلب الاشتراك بنجاح وهو قيد التأكيد والمراجعة من الإدارة.',
        );
      } else {
        AppNotification.showError(context, res.error ?? 'فشل إرسال طلب الاشتراك.');
      }
    }
  }

  Widget _summaryRow(BuildContext ctx, String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted(ctx))),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w900 : FontWeight.bold,
              color: highlight ? AppTheme.royalGold : AppTheme.textPrimary(ctx),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitleWithLogo(title: 'الاشتراكات والتفعيل السحابي'),
        actions: [
          IconButton(
            tooltip: 'تحديث حالة الاشتراك',
            icon: _isCheckingStatus
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _isCheckingStatus ? null : _manualCheckActivation,
          ),
        ],
      ),
      body: SafeArea(
        child: _currentStep == 0
            ? _buildPlansStep()
            : _currentStep == 1
                ? _buildPaymentStep()
                : _buildAwaitingActivationStep(),
      ),
    );
  }

  // -------------------------------------------------------------
  // الخطوة 1: عرض باقات الاشتراك بشكل أنيق وبسيط
  // -------------------------------------------------------------
  Widget _buildPlansStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // شريط معرف الجهاز
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.subtleBg(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Row(
              children: [
                Icon(Icons.computer_rounded, color: AppTheme.accentOnSurface(context), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'معرف هذا الجهاز الثابت:',
                        style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted(context)),
                      ),
                      SelectableText(
                        widget.deviceCode,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'نسخ المعرف',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.deviceCode));
                    AppNotification.showSuccess(context, 'تم نسخ معرف الجهاز');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'اختر باقة الاشتراك المناسبة لك',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'تشمل كافة الباقات: إدارة كاملة للمخازن والورش، نسخ احتياطي سحابي يومي، ودعم فني متواصل',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted(context)),
          ),
          const SizedBox(height: 20),

          // كروت الباقات الثلاثة
          ...SubscriptionPlan.plans.map((plan) => _buildPlanCard(plan)),

          const SizedBox(height: 18),

          // زر الدخول لصفحة الدفع
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: AppTheme.royalGold,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
            ),
            onPressed: () {
              setState(() => _currentStep = 1);
            },
            icon: const Icon(Icons.payment_rounded, size: 22),
            label: Text(
              'متابعة إلى خيارات الدفع (${_selectedPlan.price} ج.م)',
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(height: 14),

          // رابط إدخال كود يدوي للعملاء الحاليين
          Center(
            child: TextButton.icon(
              onPressed: _showOfflineActivationDialog,
              icon: const Icon(Icons.vpn_key_outlined, size: 16),
              label: const Text(
                'هل تمتلك كود تفعيل تجاري جاهز بالفعل؟ انقر هنا',
                style: TextStyle(fontSize: 12.5, decoration: TextDecoration.underline),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan) {
    final isSelected = _selectedPlan.id == plan.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => _selectedPlan = plan),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppTheme.royalGold.withValues(alpha: 0.12) : const Color(0xFFFFF9E6))
              : AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.royalGold : AppTheme.borderColor(context),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.royalGold.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.royalGold : Colors.grey,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.royalGold,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        plan.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      if (plan.badgeText.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: plan.isPopular
                                ? Colors.orange.shade700
                                : AppTheme.primaryNavy,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            plan.badgeText,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plan.durationText,
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted(context)),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${plan.price} ج.م',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? AppTheme.royalGold : AppTheme.textPrimary(context),
                  ),
                ),
                Text(
                  '${(plan.price / (plan.days / 30)).round()} ج / شهر',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // الخطوة 2: صفحة الدفع (فودافون كاش أو انستا باي)
  // -------------------------------------------------------------
  Widget _buildPaymentStep() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // زر العودة للباقات
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () => setState(() => _currentStep = 0),
                  tooltip: 'العودة للباقات',
                ),
                const SizedBox(width: 4),
                Text(
                  'خيارات الدفع وتأكيد التحويل',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // كارت ملخص الباقة المختارة
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.subtleBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedPlan.title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      Text(
                        _selectedPlan.durationText,
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
                      ),
                    ],
                  ),
                  Text(
                    '${_selectedPlan.price} جنيه',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.royalGold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            Text(
              'اختر وسيلة الدفع المعتمدة:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 10),

            // التبديل بين فودافون كاش وانستا باي باستخدام الأيقونات المرفقة
            Row(
              children: [
                Expanded(
                  child: _buildPaymentMethodCard(
                    title: 'فودافون كاش',
                    method: PaymentMethod.vodafoneCash,
                    imagePath: 'assets/images/vodafone_cash.png',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildPaymentMethodCard(
                    title: 'انستا باي',
                    method: PaymentMethod.instapay,
                    imagePath: 'assets/images/instapay.png',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // حقل رقم التحويل المعتمد 01094085228 مع زر نسخ
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.royalGold.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_rounded, color: Colors.green.shade700, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'رقم التحويل المعتمد للإدارة:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.subtleBg(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SelectableText(
                          CloudService.approvedPaymentNumber,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: Colors.green,
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          onPressed: () {
                            Clipboard.setData(
                              const ClipboardData(text: CloudService.approvedPaymentNumber),
                            );
                            AppNotification.showSuccess(context, 'تم نسخ رقم التحويل بنجاح');
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('نسخ الرقم', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'قم بتحويل مبلغ (${_selectedPlan.price} ج.م) للرقم أعلاه عبر ${_paymentMethod == PaymentMethod.vodafoneCash ? "فودافون كاش" : "انستا باي"}، ثم اكتب بيانات العملية بالأسفل:',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // حقل رقم الهاتف الذي تم منه التحويل
            TextFormField(
              controller: _senderPhoneController,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف / المحفظة الذي تم منه التحويل *',
                hintText: '01xxxxxxxxx',
                prefixIcon: Icon(Icons.phone_android_rounded),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'يرجى إدخال رقم الهاتف الذي حولت منه';
                }
                if (v.trim().length < 9) {
                  return 'رقم الهاتف قصير جداً';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),

            // حقل رقم عملية الدفع \ الرقم المرجعي
            TextFormField(
              controller: _referenceController,
              keyboardType: TextInputType.text,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رقم عملية الدفع / الرقم المرجعي للتحويل *',
                hintText: 'مثال: 94821048201',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'يرجى إدخال رقم العملية أو الرقم المرجعي';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // زر تنفيذ عملية الدفع
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: AppTheme.royalGold,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 2,
              ),
              onPressed: _isSubmitting ? null : _showConfirmationDialog,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
              label: Text(
                _isSubmitting ? 'جاري الإرسال...' : 'تنفيذ عملية الدفع',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodCard({
    required String title,
    required PaymentMethod method,
    required String imagePath,
  }) {
    final isSelected = _paymentMethod == method;
    return InkWell(
      onTap: () => setState(() => _paymentMethod = method),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.royalGold.withValues(alpha: 0.12)
              : AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.royalGold : AppTheme.borderColor(context),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Image.asset(imagePath, fit: BoxFit.contain),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? AppTheme.royalGold : AppTheme.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // الخطوة 3: صفحة انتظار التفعيل
  // -------------------------------------------------------------
  Widget _buildAwaitingActivationStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.hourglass_top_rounded, size: 44, color: Colors.amber.shade900),
          ),
          const SizedBox(height: 18),
          Text(
            'طلبك قيد المراجعة والتأكيد',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'تم استلام بيانات التحويل بنجاح، ويقوم فريق الإدارة حالياً بمطابقة المعاملة البنكية لتنشيط حسابك لحظياً.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: AppTheme.textMuted(context), height: 1.4),
          ),
          const SizedBox(height: 24),

          // كرت تفاصيل الطلب المرسل
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Column(
              children: [
                _summaryRow(context, 'معرف الجهاز:', widget.deviceCode),
                const Divider(height: 16),
                _summaryRow(
                  context,
                  'حالة الطلب الآن:',
                  _currentCloudSub?.isActive == true
                      ? 'مفعّل بنجاح ✓'
                      : _currentCloudSub?.isPaused == true
                          ? 'متوقف مؤقتاً'
                          : 'بانتظار الموافقة...',
                  highlight: true,
                ),
                if (_currentCloudSub?.senderPhone != null) ...[
                  const Divider(height: 16),
                  _summaryRow(context, 'رقم هاتف المحول:', _currentCloudSub!.senderPhone!),
                ],
                if (_currentCloudSub?.referenceNo != null) ...[
                  const Divider(height: 16),
                  _summaryRow(context, 'الرقم المرجعي:', _currentCloudSub!.referenceNo!),
                ],
                if (_currentCloudSub?.amount != null && _currentCloudSub!.amount > 0) ...[
                  const Divider(height: 16),
                  _summaryRow(context, 'المبلغ المطلوب:', '${_currentCloudSub!.amount} ج.م'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 26),

          // زر التحديث اللحظي للتحقق من موافقة الإدارة
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
            ),
            onPressed: _isCheckingStatus ? null : _manualCheckActivation,
            icon: _isCheckingStatus
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded, size: 22),
            label: Text(
              _isCheckingStatus ? 'جاري التحقق من التفعيل...' : 'تحديث والتحقق من التنشيط الآن',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 14),

          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('العودة للتطبيق ومتابعة العمل'),
          ),
        ],
      ),
    );
  }
}
