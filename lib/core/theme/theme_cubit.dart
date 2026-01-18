import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../settings/app_settings_store.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  final AppSettingsStore _settings;

  ThemeCubit({required AppSettingsStore settings})
      : _settings = settings,
        super(settings.getThemeMode());

  Future<void> setThemeMode(ThemeMode mode) async {
    if (state == mode) return;
    emit(mode);
    await _settings.setThemeMode(mode);
  }
}
