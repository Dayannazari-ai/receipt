import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../main.dart';
import '../../models/backup_models.dart';
import '../../repositories/settings_repository.dart';
import '../../services/backup_service.dart';
import '../../utils/persian_date.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});
  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  final _backupService = BackupService();
  bool _busy = false;

  void _showMsg(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ==================== Export ====================

  Future<void> _doExport(BackupType type) async {
    setState(() => _busy = true);
    try {
      final file = await _backupService.exportByType(type);
      await _backupService.shareBackup(file);
    } catch (e) {
      _showMsg('خطا در تهیه‌ی Backup: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ==================== Restore ====================

  Future<void> _doRestore() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return;
    final pickedPath = result.files.single.path!;

    BackupEnvelope envelope;
    try {
      envelope = await _backupService.readBackupFile(pickedPath);
    } catch (e) {
      _showMsg('این فایل یک Backup معتبر نیست: $e');
      return;
    }

    if (!mounted) return;

    RestoreMode mode;
    if (envelope.backupType == BackupType.settings) {
      // بازیابی تنظیمات حالت افزودن/جایگزینی ندارد.
      final ok = await _showSettingsRestoreDialog(envelope);
      if (ok != true) return;
      mode = RestoreMode.merge;
    } else {
      final picked = await _showRestoreSummaryDialog(envelope);
      if (picked == null) return;
      mode = picked;
      if (mode == RestoreMode.replace) {
        final confirmed = await _confirmReplace(envelope);
        if (confirmed != true) return;
      }
    }

    setState(() => _busy = true);
    try {
      final report = await _backupService.restore(envelope, mode);

      // رنگ اصلی برنامه جزو تنظیمات است؛ بعد از بازیابی بلافاصله اعمال شود.
      if (report.settingsRestored) {
        final s = await SettingsRepository().getSettings();
        if (mounted) ReceiptApp.of(context)?.updateColor(s.primaryColorHex);
      }

      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('نتیجه‌ی بازیابی'),
            content: SingleChildScrollView(child: Text(report.summary().isEmpty ? 'تغییری اعمال نشد.' : report.summary())),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('باشه'))],
          ),
        );
      }
    } catch (e) {
      _showMsg('خطا در بازیابی: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _backupInfo(BackupEnvelope envelope) {
    final countsText = envelope.recordCounts.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('نوع: ${envelope.backupType.label}'),
      const SizedBox(height: 4),
      Text('تاریخ ایجاد: ${PersianDateUtil.formatDateTime(envelope.createdAt)}'),
      const SizedBox(height: 4),
      Text('آخرین به‌روزرسانی: ${PersianDateUtil.formatDateTime(envelope.updatedAt)}'),
      const SizedBox(height: 10),
      const Text('تعداد رکوردها:', style: TextStyle(fontWeight: FontWeight.bold)),
      Text(countsText),
    ]);
  }

  Future<bool?> _showSettingsRestoreDialog(BackupEnvelope envelope) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('بازیابی تنظیمات'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _backupInfo(envelope),
            const SizedBox(height: 16),
            const Text(
              'فقط تنظیمات برنامه، قالب فاکتور و عکس مهر بازیابی می‌شوند و شماره کارت/شبای جدید اضافه می‌شود. '
              'مشتریان، خودروها، محصولات، خدمات و فاکتورها تغییر نمی‌کنند. رمز عبور برنامه جزو Backup نیست.',
              style: TextStyle(fontSize: 12),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('بازیابی تنظیمات')),
        ],
      ),
    );
  }

  Future<RestoreMode?> _showRestoreSummaryDialog(BackupEnvelope envelope) {
    return showDialog<RestoreMode>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Backup ${envelope.backupType.label}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _backupInfo(envelope),
            if (envelope.backupType == BackupType.full) ...[
              const SizedBox(height: 10),
              const Text(
                'در حالت «افزودن»، تنظیمات برنامه تغییر نمی‌کند. برای بازیابی تنظیمات از «جایگزینی کامل» یا از Backup تنظیمات استفاده کنید.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),
            const Text('حالت بازیابی را انتخاب کنید:', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(context, RestoreMode.merge),
              child: const Text('افزودن به اطلاعات فعلی')),
          TextButton(
              onPressed: () => Navigator.pop(context, RestoreMode.replace),
              child: const Text('جایگزینی کامل', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Future<bool?> _confirmReplace(BackupEnvelope envelope) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأیید جایگزینی'),
        content: Text(
            'این عملیات اطلاعات فعلی بخش «${envelope.backupType.label}» را حذف کرده و اطلاعات Backup را جایگزین می‌کند.\nآیا مطمئن هستید؟',
            style: const TextStyle(color: Colors.red)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('جایگزینی', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // ==================== به‌روزرسانی Backup موجود ====================

  Future<void> _doUpdateExisting() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return;
    final pickedPath = result.files.single.path!;

    setState(() => _busy = true);
    try {
      final file = await _backupService.updateExistingBackup(pickedPath);
      _showMsg('Backup به‌روزرسانی شد: ${file.path.split('/').last}');
    } catch (e) {
      _showMsg('خطا در به‌روزرسانی Backup: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پشتیبان‌گیری و بازیابی')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('تهیه‌ی پشتیبان (Backup)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('هر بخش را جداگانه پشتیبان‌گیری کنید؛ فایل حاصل قابل اشتراک‌گذاری و ذخیره در محل دلخواه است.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.people_outline),
            label: const Text('پشتیبان مشتریان (و خودروها)'),
            onPressed: () => _doExport(BackupType.customers),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('پشتیبان محصولات'),
            onPressed: () => _doExport(BackupType.products),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.build_outlined),
            label: const Text('پشتیبان خدمات'),
            onPressed: () => _doExport(BackupType.services),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('پشتیبان فاکتورها'),
            onPressed: () => _doExport(BackupType.invoices),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.settings_backup_restore_outlined),
            label: const Text('پشتیبان تنظیمات'),
            onPressed: () => _doExport(BackupType.settings),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.backup_outlined),
            label: const Text('پشتیبان کامل'),
            onPressed: () => _doExport(BackupType.full),
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          const Text('بازیابی (Restore)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('یک فایل Backup را انتخاب کنید؛ نوع، تاریخ و تعداد رکوردهای آن قبل از بازیابی نمایش داده می‌شود.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.restore_outlined),
            label: const Text('انتخاب فایل Backup برای بازیابی'),
            onPressed: _doRestore,
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          const Text('به‌روزرسانی Backup موجود', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('یک فایل Backup قبلی را انتخاب کنید تا با اطلاعات فعلی به‌روزرسانی شود.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.update_outlined),
            label: const Text('به‌روزرسانی یک Backup موجود'),
            onPressed: _doUpdateExisting,
          ),
          if (_busy) ...[const SizedBox(height: 24), const Center(child: CircularProgressIndicator())],
        ]),
      ),
    );
  }
}
