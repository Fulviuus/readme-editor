/// Owns the set of available themes (built-in JSON assets + user JSON files
/// in the app-support themes folder) and the persisted selection. No UI code
/// here — widgets observe this ChangeNotifier via the app layer.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'readme_theme.dart';

/// A user theme file that failed to load, with the reason. Recorded instead
/// of thrown so one malformed file never takes down startup.
class ThemeLoadError {
  const ThemeLoadError(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'ThemeLoadError($path: $message)';
}

class ThemeManager extends ChangeNotifier {
  static const _builtinIds = [
    'github',
    'gothic',
    'newsprint',
    'night',
    'pixyll',
    'whitey',
  ];
  static const _defaultId = 'github';
  static const _prefsKey = 'theme';
  static const _zoomKey = 'zoom';
  static const _zoomStep = 0.1;
  static const _zoomMin = 0.5;
  static const _zoomMax = 3.0;

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  final List<ReadmeTheme> _builtins = [];
  final List<ReadmeTheme> _userThemes = [];
  String _currentId = _defaultId;
  String? _userThemesDirectory;

  /// User theme files skipped during the last [reloadUserThemes] pass.
  final List<ThemeLoadError> loadErrors = [];

  /// Absolute path of the user themes folder, or null on web.
  String? get userThemesDirectory => _userThemesDirectory;

  /// Built-ins first (in canonical order), then user themes sorted by name.
  List<ReadmeTheme> get themes =>
      List.unmodifiable([..._builtins, ..._userThemes]);

  double _zoom = 1.0;

  /// UI zoom factor (View > Zoom In/Out), persisted; 1.0 = actual size.
  double get zoom => _zoom;

  ReadmeTheme get current {
    final theme =
        _themeById(_currentId) ?? _themeById(_defaultId) ?? themes.first;
    return _zoom == 1.0 ? theme : theme.scaled(_zoom);
  }

  Future<void> setZoom(double value) async {
    final clamped =
        double.parse(value.clamp(_zoomMin, _zoomMax).toStringAsFixed(2));
    if (clamped == _zoom) return;
    _zoom = clamped;
    notifyListeners();
    await _prefs.setDouble(_zoomKey, _zoom);
  }

  Future<void> zoomIn() => setZoom(_zoom + _zoomStep);
  Future<void> zoomOut() => setZoom(_zoom - _zoomStep);
  Future<void> resetZoom() => setZoom(1.0);

  /// Loads built-in theme assets and user themes, then restores the persisted
  /// selection. Call once at startup, after binding initialization.
  Future<void> init() async {
    await _loadBuiltins();
    await reloadUserThemes();
    final saved = await _prefs.getString(_prefsKey);
    if (saved != null && _themeById(saved) != null) {
      _currentId = saved;
    }
    final savedZoom = await _prefs.getDouble(_zoomKey);
    if (savedZoom != null) {
      _zoom = savedZoom.clamp(_zoomMin, _zoomMax);
    }
    notifyListeners();
  }

  /// Selects theme [id] (no-op if unknown) and persists the choice.
  Future<void> setTheme(String id) async {
    if (_themeById(id) == null || id == _currentId) return;
    _currentId = id;
    notifyListeners();
    await _prefs.setString(_prefsKey, id);
  }

  /// Rescans the user themes folder, creating it if missing. Malformed files
  /// are skipped and recorded in [loadErrors]; this never throws.
  Future<void> reloadUserThemes() async {
    loadErrors.clear();
    _userThemes.clear();
    if (!kIsWeb) {
      await _scanUserThemes();
    }
    notifyListeners();
  }

  Future<void> _loadBuiltins() async {
    _builtins.clear();
    for (final id in _builtinIds) {
      final raw = await rootBundle.loadString('assets/themes/$id.json');
      _builtins.add(
        ReadmeTheme.fromJson(id, jsonDecode(raw) as Map<String, dynamic>),
      );
    }
  }

  Future<void> _scanUserThemes() async {
    final Directory dir;
    try {
      final support = await getApplicationSupportDirectory();
      dir = Directory(p.join(support.path, 'themes'));
      await dir.create(recursive: true);
      _userThemesDirectory = dir.path;
    } catch (e) {
      loadErrors.add(ThemeLoadError('<themes directory>', '$e'));
      return;
    }

    final List<File> files;
    try {
      files = [
        await for (final entry in dir.list())
          if (entry is File && p.extension(entry.path).toLowerCase() == '.json')
            entry,
      ];
    } catch (e) {
      loadErrors.add(ThemeLoadError(dir.path, '$e'));
      return;
    }

    for (final file in files) {
      try {
        final id = p.basenameWithoutExtension(file.path);
        final json = jsonDecode(await file.readAsString());
        if (json is! Map<String, dynamic>) {
          throw const FormatException('top-level value is not a JSON object');
        }
        _userThemes.add(ReadmeTheme.fromJson(id, json));
      } catch (e) {
        loadErrors.add(ThemeLoadError(file.path, '$e'));
      }
    }
    _userThemes.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  ReadmeTheme? _themeById(String id) {
    for (final t in _builtins) {
      if (t.id == id) return t;
    }
    for (final t in _userThemes) {
      if (t.id == id) return t;
    }
    return null;
  }
}
