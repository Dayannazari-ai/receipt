import 'package:flutter/material.dart';
import '../invoices/invoices_screen.dart';
import 'reports_panel.dart';

/// صفحه‌ی «گزارش» (جای قبلیِ «فاکتورها» در نوار پایین).
/// تب‌ها: «فاکتورها» (همان صفحه‌ی قبلی)، «مالی خدمات» و «مالی کالا».
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارش'),
        bottom: TabBar(controller: _tab, tabs: const [
          Tab(text: 'فاکتورها'),
          Tab(text: 'مالی خدمات'),
          Tab(text: 'مالی کالا'),
        ]),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          InvoicesScreen(embedded: true),
          ReportsPanel(goods: false),
          ReportsPanel(goods: true),
        ],
      ),
    );
  }
}
