import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../repositories/customer_repository.dart';
import '../../utils/persian_date.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _repo = CustomerRepository();
  final _searchCtrl = TextEditingController();
  List<Customer> _customers = [];
  bool _loading = true;
  bool _debtorsOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    List<Customer> list;
    if (_debtorsOnly) {
      list = await _repo.getDebtors();
      if (_searchCtrl.text.trim().isNotEmpty) {
        final q = _searchCtrl.text.trim();
        list = list.where((c) => c.name.contains(q) || c.mobile.contains(q)).toList();
      }
    } else {
      list = _searchCtrl.text.trim().isEmpty ? await _repo.getAll() : await _repo.search(_searchCtrl.text.trim());
    }
    if (!mounted) return;
    setState(() {
      _customers = list;
      _loading = false;
    });
  }

  Future<void> _addOrEdit({Customer? customer}) async {
    final nameCtrl = TextEditingController(text: customer?.name ?? '');
    final mobileCtrl = TextEditingController(text: customer?.mobile ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(customer == null ? 'مشتری جدید' : 'ویرایش مشتری',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'نام مشتری')),
          const SizedBox(height: 12),
          TextField(
              controller: mobileCtrl,
              decoration: const InputDecoration(labelText: 'شماره تماس'),
              keyboardType: TextInputType.phone),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              if (customer == null) {
                await _repo.insert(Customer(name: nameCtrl.text.trim(), mobile: mobileCtrl.text.trim()));
              } else {
                await _repo.update(Customer(
                    id: customer.id,
                    name: nameCtrl.text.trim(),
                    mobile: mobileCtrl.text.trim(),
                    createdAt: customer.createdAt));
              }
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: Text(customer == null ? 'ثبت مشتری' : 'ذخیره تغییرات'),
          ),
          if (customer != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await _repo.softDelete(customer.id!);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('حذف مشتری', style: TextStyle(color: Colors.red)),
            ),
          ],
        ]),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مشتریان'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(hintText: 'جستجوی مشتری', prefixIcon: Icon(Icons.search)),
            onChanged: (_) => _load(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilterChip(
              label: const Text('مشتریان بدهکار'),
              avatar: const Icon(Icons.warning_amber, size: 18, color: Colors.red),
              selected: _debtorsOnly,
              onSelected: (v) {
                setState(() => _debtorsOnly = v);
                _load();
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _customers.isEmpty
                  ? Center(child: Text(_debtorsOnly ? 'مشتری بدهکاری ثبت نشده است' : 'مشتری ثبت نشده است'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _customers.length,
                      itemBuilder: (context, i) {
                        final c = _customers[i];
                        return Card(
                          color: _debtorsOnly ? Colors.red.shade50 : null,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _debtorsOnly ? Colors.red.shade100 : null,
                              child: Icon(_debtorsOnly ? Icons.warning_amber : Icons.person),
                            ),
                            title: Text(c.name),
                            subtitle: Text(PersianDateUtil.toPersianDigits(c.mobile)),
                            onTap: () => _addOrEdit(customer: c),
                          ),
                        );
                      },
                    ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('افزودن مشتری'),
        onPressed: () => _addOrEdit(),
      ),
    );
  }
}
