import 'package:flutter/material.dart';
import 'receipt/receipt_screen.dart';
import 'customers/customers_screen.dart';
import 'products/products_screen.dart';
import 'services/services_screen.dart';
import 'invoices/invoices_screen.dart';
import 'settings/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 5; // شروع از صفحه‌ی «رسید»

  final _pages = const [
    SettingsScreen(),
    CustomersScreen(),
    ProductsScreen(),
    ServicesScreen(),
    InvoicesScreen(),
    ReceiptScreen(),
  ];

  final _titles = const ['تنظیمات', 'مشتریان', 'محصولات', 'خدمات', 'فاکتورها', 'رسید'];

  final _icons = const [
    Icons.settings_outlined,
    Icons.person_outline,
    Icons.shopping_cart_outlined,
    Icons.build_outlined,
    Icons.description_outlined,
    Icons.add_shopping_cart,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: List.generate(
          _titles.length,
          (i) => NavigationDestination(icon: Icon(_icons[i]), label: _titles[i]),
        ),
      ),
    );
  }
}
