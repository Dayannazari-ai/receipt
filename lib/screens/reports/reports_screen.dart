import 'package:flutter/material.dart';
import '../invoices/invoices_screen.dart';
import 'reports_panel.dart';

/// صفحه‌ی «گزارش» (جای قبلیِ «فاکتورها» در نوار پایین).
/// تب اول: همان صفحه‌ی فاکتورها. تب دوم: گزارش‌ها (گزارش فاکتورها و گزارش مالی).
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
    _tab = TabController(length: 2, vsync: this);
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
          Tab(text: 'گزارش'),
        ]),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          InvoicesScreen(embedded: true),
          ReportsPanel(),
        ],
      ),
    );
  }
}
