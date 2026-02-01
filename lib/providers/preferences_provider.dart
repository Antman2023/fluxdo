import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart';

class AppPreferences {
  final bool autoPanguSpacing;
  final bool anonymousShare;

  const AppPreferences({
    required this.autoPanguSpacing,
    required this.anonymousShare,
  });

  AppPreferences copyWith({
    bool? autoPanguSpacing,
    bool? anonymousShare,
  }) {
    return AppPreferences(
      autoPanguSpacing: autoPanguSpacing ?? this.autoPanguSpacing,
      anonymousShare: anonymousShare ?? this.anonymousShare,
    );
  }
}

class PreferencesNotifier extends StateNotifier<AppPreferences> {
  static const String _autoPanguSpacingKey = 'pref_auto_pangu_spacing';
  static const String _anonymousShareKey = 'pref_anonymous_share';

  PreferencesNotifier(this._prefs)
      : super(
          AppPreferences(
            autoPanguSpacing: _prefs.getBool(_autoPanguSpacingKey) ?? false,
            anonymousShare: _prefs.getBool(_anonymousShareKey) ?? false,
          ),
        );

  final SharedPreferences _prefs;

  Future<void> setAutoPanguSpacing(bool enabled) async {
    state = state.copyWith(autoPanguSpacing: enabled);
    await _prefs.setBool(_autoPanguSpacingKey, enabled);
  }

  Future<void> setAnonymousShare(bool enabled) async {
    state = state.copyWith(anonymousShare: enabled);
    await _prefs.setBool(_anonymousShareKey, enabled);
  }
}

final preferencesProvider =
    StateNotifierProvider<PreferencesNotifier, AppPreferences>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PreferencesNotifier(prefs);
});
