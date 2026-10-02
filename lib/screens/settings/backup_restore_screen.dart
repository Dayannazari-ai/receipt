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
  //
  // مراحل ایمن: انتخاب فایل ← اعتبارسنجی ← Preview و انتخاب حالت ←
  // Backup اضطراری از وضعیت فعلی ← Restore آزمایشی روی کپی ایزوله ←
  // تأیید نهایی ← Restore واقعی (تراکنشی) ← اعتبارسنجی بعد از Restore
  // (با امکان برگشت به Backup اضطراری).

  Future<void> _applyThemeColorFromSettings() async {
    final s = await SettingsRepository().getSettings();
    if (mounted) ReceiptApp.of(context)?.updateColor(s.primaryColorHex);
  }

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

    final validation = _backupService.validateEnvelope(envelope, path: pickedPath);
    if (!validation.isValid) {
      await _showIssuesDialog('این Backup قابل بازیابی نیست', validation.errors);
      return;
    }
    if (!mounted) return;

    // انتخاب حالت
    RestoreMode mode;
    if (envelope.backupType == BackupType.settings) {
      final ok = await _showSettingsRestoreDialog(envelope, validation.warnings);
      if (ok != true) return;
      mode = RestoreMode.merge; // برای تنظیمات تأثیری ندارد
    } else {
      final picked = await _showRestoreSummaryDialog(envelope, validation.warnings);
      if (picked == null) return;
      mode = picked;
    }

    // Backup اضطراری + Restore آزمایشی
    File? snapshot;
    setState(() => _busy = true);
    try {
      snapshot = await _backupService.createPreRestoreSnapshot();
      final dry = await _backupService.dryRun(envelope, mode);
      if (dry.issues.isNotEmpty) {
        if (mounted) setState(() => _busy = false);
        await _showIssuesDialog('Restore آزمایشی مشکل پیدا کرد؛ Restore واقعی انجام نشد', dry.issues);
        return;
      }
    } catch (e) {
      _showMsg('Restore انجام نشد و اطلاعات شما تغییری نکرد: $e');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (snapshot == null || !mounted) return;

    // تأیید نهایی
    final go = await _confirmFinalRestore(envelope, mode, snapshot);
    if (go != true) return;

    // Restore واقعی
    setState(() => _busy = true);
    try {
      final report = await _backupService.restore(envelope, mode, snapshot: snapshot);
      if (report.settingsRestored) await _applyThemeColorFromSettings();
      if (!mounted) return;

      if (report.issues.isNotEmpty) {
        final rollback = await _showPostRestoreIssuesDialog(report);
        if (rollback == true) {
          await _backupService.rollbackToSnapshot(snapshot);
          await _applyThemeColorFromSettings();
          _showMsg('اطلاعات به وضعیت قبل از Restore برگردانده شد.');
        }
      } else {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('نتیجه‌ی بازیابی'),
            content: SingleChildScrollView(
                child: Text(report.summary().isEmpty ? 'تغییری اعمال نشد.' : report.summary())),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('باشه'))],
          ),
        );
      }
    } catch (e) {
      _showMsg('خطا در بازیابی (اطلاعات قبلی دست‌نخورده ماند): $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- دیالوگ‌ها ----------------

  Widget _backupInfo(BackupEnvelope envelope, List<String> warnings) {
    final counts = envelope.recordCounts.entries
        .where((e) => e.key != 'invoice_layout' && e.key != 'stamp_image')
        .map((e) => '${BackupService.sectionLabel(e.key)}: ${e.value}')
        .join('\n');
    final hasSettings = envelope.data['app_settings'] is Map;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('نوع: ${envelope.backupType.label}'),
      const SizedBox(height: 4),
      Text('تاریخ ایجاد: ${PersianDateUtil.formatDateTime(envelope.createdAt)}'),
      const SizedBox(height: 4),
      Text('آخرین به‌روزرسانی: ${PersianDateUtil.formatDateTime(envelope.updatedAt)}'),
      const SizedBox(height: 4),
      Text('نسخه‌ی Backup: ${envelope.backupVersion}'),
      const SizedBox(height: 4),
      Text('تنظیمات برنامه داخل Backup: ${hasSettings ? 'دارد' : 'ندارد'}'),
      const SizedBox(height: 10),
      const Text('تعداد رکوردها:', style: TextStyle(fontWeight: FontWeight.bold)),
      Text(counts.isEmpty ? '—' : counts),
      for (final w in warnings) ...[
        const SizedBox(height: 8),
        Text(w, style: const TextStyle(fontSize: 12, color: Colors.orange)),
      ],
    ]);
  }

  Future<void> _showIssuesDialog(String title, List<String> issues) {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final i in issues) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $i')),
            const SizedBox(height: 8),
            const Text('هیچ تغییری روی اطلاعات شما اعمال نشد.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('باشه'))],
      ),
    );
  }

  Future<bool?> _showSettingsRestoreDialog(BackupEnvelope envelope, List<String> warnings) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('بازیابی تنظیمات'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _backupInfo(envelope, warnings),
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
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ادامه')),
        ],
      ),
    );
  }

  Future<RestoreMode?> _showRestoreSummaryDialog(BackupEnvelope envelope, List<String> warnings) {
    return showDialog<RestoreMode>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Backup ${envelope.backupType.label}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _backupInfo(envelope, warnings),
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

  Future<bool?> _confirmFinalRestore(BackupEnvelope envelope, RestoreMode mode, File snapshot) {
    final replace = envelope.backupType != BackupType.settings && mode == RestoreMode.replace;
    final snapName = snapshot.path.split('/').last;
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأیید نهایی بازیابی'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('قبل از Restore یک Backup اضطراری از اطلاعات فعلی تهیه شده است ($snapName) و Restore آزمایشی هم موفق بود.'),
            const SizedBox(height: 10),
            if (replace)
              Text(
                'این عملیات اطلاعات فعلی بخش «${envelope.backupType.label}» را حذف کرده و اطلاعات Backup را جایگزین می‌کند.',
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 10),
            const Text('آیا مطمئن هستید که می‌خواهید این Backup را بازیابی کنید؟',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لغو')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('ادامه Restore', style: TextStyle(color: replace ? Colors.red : null))),
        ],
      ),
    );
  }

  Future<bool?> _showPostRestoreIssuesDialog(RestoreReport report) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('بعد از بازیابی مشکل پیدا شد'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final i in report.issues) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $i')),
            const SizedBox(height: 8),
            const Text(
              'می‌توانید اطلاعات را به وضعیت قبل از Restore برگردانید (از Backup اضطراری).',
              style: TextStyle(fontSize: 12),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('همین‌طور بماند')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('برگشت به قبل از Restore', style: TextStyle(color: Colors.red))),
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
          const Text(
              'یک فایل Backup را انتخاب کنید؛ نوع، تاریخ و تعداد رکوردهای آن قبل از بازیابی نمایش داده می‌شود. '
              'قبل از هر بازیابی یک Backup اضطراری از اطلاعات فعلی گرفته و یک بازیابی آزمایشی روی کپی انجام می‌شود.',
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
