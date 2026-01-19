import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/theme_cubit.dart';

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return BlocBuilder<ThemeCubit, ThemeMode>(
      builder: (context, themeMode) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Appearance'),
          ),
          body: RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (mode) {
              if (mode == null) return;
              context.read<ThemeCubit>().setThemeMode(mode);
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(0, 8, 0, 16 + bottomPadding),
              children: [
                const _ThemeModeTile(
                  title: 'System default',
                  subtitle: 'Follow your device setting',
                  value: ThemeMode.system,
                ),
                const _ThemeModeTile(
                  title: 'Light',
                  value: ThemeMode.light,
                ),
                const _ThemeModeTile(
                  title: 'Dark',
                  value: ThemeMode.dark,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Tip: You can change your device theme any time when using System default.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final ThemeMode value;

  const _ThemeModeTile({
    required this.title,
    this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<ThemeMode>(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
    );
  }
}
