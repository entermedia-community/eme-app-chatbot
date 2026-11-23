import 'dart:ui';

import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/chat_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DioUtil.init();

  const defaultSiteRoot = kReleaseMode
      ? 'https://eme.world'
      : 'http://localhost:8080';
  const siteRoot = String.fromEnvironment(
    'SITEROOT',
    defaultValue: defaultSiteRoot,
  );
  const mediaDb = String.fromEnvironment(
    'MEDIADB',
    defaultValue: '$siteRoot/site/mediadb',
  );

  await OpenI().initialize({
    'mediadb': mediaDb,
    'siteroot': siteRoot,
    'catalogid': 'site/catalog',
  });

  runApp(const ProviderScope(child: EmeChatbotApp()));
}

/// Keeps the chat from stretching on wide viewports.
const double _maxChatWidth = 720;

class EmeChatbotApp extends StatelessWidget {
  const EmeChatbotApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF006466);
    return MaterialApp(
      title: 'EME Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      builder: (context, child) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxChatWidth),
            child: ClipRect(child: child),
          ),
        ),
      ),
      home: const ChatScreen(),
    );
  }
}
