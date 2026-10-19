import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'menu_screen.dart';
import 'progress.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // أي خطأ في الرسم يظهر كنص بدل شاشة سوداء فارغة
    ErrorWidget.builder = (details) => Material(
          color: const Color(0xFF0B1F2A),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                'حدث خطأ:\n${details.exceptionAsString()}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        );
    runApp(const WormApp());
  }, (error, stack) {});
}

class WormApp extends StatelessWidget {
  const WormApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'لعبة الدودة',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF26A69A),
        visualDensity: VisualDensity.compact,
      ),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: const TextScaler.linear(0.88)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const Bootstrap(),
    );
  }
}

/// شاشة تحميل تُظهر التقدم وأي خطأ، ثم تفتح القائمة.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]).catchError((_) {});
      await Store.i.init().timeout(const Duration(seconds: 6));
    } catch (e) {
      _error = '$e';
    }
    if (!mounted) return;
    if (_error == null) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
          .catchError((_) {});
      setState(() => _ready = true);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const MenuScreen();
    return Scaffold(
      backgroundColor: const Color(0xFF0B2A3A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🐍 لعبة الدودة',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text(Cfg.credit, style: TextStyle(color: Colors.white70)),
              const Text(Cfg.phone,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 20),
              if (_error == null)
                const CircularProgressIndicator()
              else ...[
                SelectableText('تعذّر تحميل البيانات المحفوظة:\n$_error',
                    style: const TextStyle(color: Colors.orangeAccent)),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () {
                    SystemChrome.setEnabledSystemUIMode(
                            SystemUiMode.immersiveSticky)
                        .catchError((_) {});
                    setState(() => _ready = true);
                  },
                  child: const Text('متابعة'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
