import 'package:flutter/material.dart';
import '../../components/app_logo.dart';
import '../../core/app_theme.dart';
import '../showroom_statement_screen.dart';
import 'customers_tab.dart';
import 'categories_tab.dart';
import 'showroom_stock_tab.dart';

class ManagementHubScreen extends StatefulWidget {
  final int initialTabIndex;
  const ManagementHubScreen({super.key, this.initialTabIndex = 0});

  @override
  State<ManagementHubScreen> createState() => ManagementHubScreenState();
}

class ManagementHubScreenState extends State<ManagementHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController tabController;

  @override
  void initState() {
    super.initState();
    tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
  }

  @override
  void didUpdateWidget(covariant ManagementHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTabIndex != oldWidget.initialTabIndex) {
      tabController.animateTo(widget.initialTabIndex.clamp(0, 2));
    }
  }

  void switchToTab(int index) {
    if (mounted && index >= 0 && index < tabController.length) {
      tabController.animateTo(index);
    }
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitleWithLogo(title: 'إدارة المخزن والأصناف والعملاء'),
        actions: [
          AnimatedBuilder(
            animation: tabController,
            builder: (context, _) {
              if (tabController.index != 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: AppTheme.royalGold,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => const ShowroomStatementScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long_rounded, size: 17),
                  label: const Text(
                    'كشف حساب',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.warehouse_rounded),
              child: FittedBox(fit: BoxFit.scaleDown, child: Text('مخزن المعرض', maxLines: 1)),
            ),
            Tab(
              icon: Icon(Icons.weekend_rounded),
              child: FittedBox(fit: BoxFit.scaleDown, child: Text('الأصناف ومكوناتها', maxLines: 1)),
            ),
            Tab(
              icon: Icon(Icons.people_alt_rounded),
              child: FittedBox(fit: BoxFit.scaleDown, child: Text('العملاء', maxLines: 1)),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: const [
          ShowroomStockTab(),
          CategoriesTab(),
          CustomersTab(),
        ],
      ),
    );
  }
}
