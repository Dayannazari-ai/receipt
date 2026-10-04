import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// صفحهٔ اسکن بارکد (آفلاین، با دوربین). با pop مقدار بارکد (String) را
/// برمی‌گرداند؛ امضای قبلی (const BarcodeScannerScreen()) تغییر نکرده است.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.codabar,
    ],
  );

  static const String _readyText = 'دوربین آماده اسکن است';

  bool _handled = false;
  String _status = _readyText;
  bool _statusBad = false;
  String? _lastInvalid;
  DateTime _lastInvalidAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _resetTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resetTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_handled) unawaited(_safeStart());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_safeStop());
        break;
    }
  }

  Future<void> _safeStart() async {
    try {
      await _controller.start();
    } catch (_) {
      // خطا در state کنترلر ثبت می‌شود و errorBuilder آن را نشان می‌دهد.
    }
  }

  Future<void> _safeStop() async {
    try {
      await _controller.stop();
    } catch (_) {}
  }

  /// ارقام فارسی/عربی را به انگلیسی تبدیل می‌کند.
  String _normalizeDigits(String s) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final i = fa.indexOf(ch);
      final j = ar.indexOf(ch);
      if (i >= 0) {
        b.write(i);
      } else if (j >= 0) {
        b.write(j);
      } else {
        b.write(ch);
      }
    }
    return b.toString();
  }

  /// رقم کنترل EAN-13 / EAN-8 / UPC-A (وزن ۳ و ۱ از راست).
  bool _checkDigitOk(String v) {
    final n = v.length;
    int sum = 0;
    for (int i = 0; i < n - 1; i++) {
      final d = v.codeUnitAt(i) - 48;
      final posFromRight = n - 1 - i;
      sum += d * (posFromRight.isOdd ? 3 : 1);
    }
    final check = (10 - sum % 10) % 10;
    return check == v.codeUnitAt(n - 1) - 48;
  }

  bool _isValid(String v, BarcodeFormat f) {
    if (f == BarcodeFormat.ean13 || f == BarcodeFormat.ean8 || f == BarcodeFormat.upcA) {
      if (!RegExp(r'^\d+$').hasMatch(v)) return false;
      final len = f == BarcodeFormat.ean13 ? 13 : (f == BarcodeFormat.ean8 ? 8 : 12);
      if (v.length != len) return false;
      return _checkDigitOk(v);
    }
    return true;
  }

  void _markInvalid(String v) {
    final now = DateTime.now();
    if (_lastInvalid == v && now.difference(_lastInvalidAt) < const Duration(seconds: 2)) return;
    _lastInvalid = v;
    _lastInvalidAt = now;
    if (!mounted) return;
    setState(() {
      _status = 'بارکد نامعتبر است، دوباره اسکن کنید';
      _statusBad = true;
    });
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _handled) return;
      setState(() {
        _status = _readyText;
        _statusBad = false;
      });
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      if (!_isValid(raw, b.format)) {
        _markInvalid(raw);
        continue;
      }
      _handled = true;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(raw);
      return;
    }
  }

  Future<void> _manualEntry() async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ورود دستی بارکد'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'شماره بارکد'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('تأیید')),
        ],
      ),
    );
    if (value == null || !mounted || _handled) return;
    final v = _normalizeDigits(value).trim();
    if (v.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(v);
  }

  Widget _buildError(MobileScannerException error) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    const white = TextStyle(color: Colors.white, fontSize: 14);
    final btn = OutlinedButton.styleFrom(foregroundColor: Colors.white);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.no_photography_outlined, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          Text(
            denied
                ? 'دسترسی به دوربین وجود ندارد.\nاز تنظیمات گوشی، اجازهٔ دوربین را به برنامه بدهید.'
                : 'دوربین باز نشد.',
            style: white,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SelectableText(
            '${error.errorCode.name}\n${error.errorDetails?.message ?? ""}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(mainAxisSize: MainAxisSize.min, children: [
            OutlinedButton(style: btn, onPressed: _safeStart, child: const Text('تلاش دوباره')),
            const SizedBox(width: 8),
            OutlinedButton(style: btn, onPressed: _manualEntry, child: const Text('ورود دستی')),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('اسکن بارکد'),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final unavailable = state.torchState == TorchState.unavailable;
              final on = state.torchState == TorchState.on;
              return IconButton(
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
                onPressed: unavailable ? null : () => _controller.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error, child) => _buildError(error),
        ),
        Center(
          child: IgnorePointer(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: _statusBad ? Colors.redAccent : Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 24,
          left: 16,
          right: 16,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _statusBad ? Colors.red.shade700 : Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('ورود دستی بارکد'),
              onPressed: _manualEntry,
            ),
          ]),
        ),
      ]),
    );
  }
}
