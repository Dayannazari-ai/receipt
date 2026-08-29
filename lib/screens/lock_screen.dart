import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// صفحه‌ی قفل: قبل از ورود به برنامه (در صورت تنظیم رمز) نمایش داده می‌شود.
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _authService = AuthService();
  final _ctrl = TextEditingController();
  String? _error;
  bool _obscure = true;

  Future<void> _submit() async {
    final ok = await _authService.verify(_ctrl.text);
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = 'رمز عبور اشتباه است');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              const Text('ورود به برنامه', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: _ctrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'رمز عبور',
                  errorText: _error,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _submit, child: const Text('ورود')),
            ]),
          ),
        ),
      ),
    );
  }
}
