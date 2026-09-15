import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppTheme { standard, egyptianGold }

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;
  void setTheme(ThemeMode value) => state = value;
}

final appThemeProvider = NotifierProvider<AppThemeNotifier, AppTheme>(AppThemeNotifier.new);

class AppThemeNotifier extends Notifier<AppTheme> {
  @override
  AppTheme build() => AppTheme.standard;
  void setTheme(AppTheme value) => state = value;
}

final notificationsEnabledProvider = NotifierProvider<NotificationsEnabledNotifier, bool>(NotificationsEnabledNotifier.new);

class NotificationsEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void toggle(bool value) => state = value;
}
