import 'package:flutter/material.dart';
import 'memo_list_page.dart';
import 'package:provider/provider.dart';
import 'memo_store.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MemoStore(),
      child: MaterialApp(
        title: 'Clipboard Notes',
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          tabBarTheme: const TabBarThemeData(
            indicatorColor: Colors.deepPurple,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: Colors.deepPurple,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelColor: Colors.grey,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          tabBarTheme: const TabBarThemeData(
            indicatorColor: Colors.deepPurpleAccent,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: Colors.deepPurpleAccent,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelColor: Colors.grey,
          ),
        ),
        home: const MemoListPage(),
      ),
    );
  }
}
