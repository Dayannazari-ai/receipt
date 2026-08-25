import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'repositories/settings_repository.dart';
import 'services/seed_service.dart';
import 'utils/app_theme.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SeedService().seedIfEmpty();
  final settings = await SettingsRepository().getSettings();
  runApp(ReceiptApp(primaryColorHex: settings.primaryColorHex));
}

class ReceiptApp extends StatefulWidget {
  final String primaryColorHex;
  const ReceiptApp({super.key, required this.primaryColorHex});

  static _ReceiptAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_ReceiptAppState>();

  @override
  State<ReceiptApp> createState() => _ReceiptAppState();
}

class _ReceiptAppState extends State<ReceiptApp> {
  late String _colorHex;

  @override
  void initState() {
    super.initState();
    _colorHex = widget.primaryColorHex;
  }

  void updateColor(String hex) {
    setState(() => _colorHex = hex);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'رسید و فاکتور',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFrom(AppTheme.hexToColor(_colorHex)),
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
      home: const HomeShell(),
    );
  }
}
