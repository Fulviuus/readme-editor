/// In-window document tabs. One shared DocumentController/EditorController
/// pair serves the ACTIVE tab; every inactive tab holds its full state
/// (content, undo history, file binding) as a [DocumentState] snapshot,
/// swapped in and out on switches — so all existing consumers of the
/// controllers keep working untouched.
library;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../document/document_controller.dart';

class DocTabs extends ChangeNotifier {
  DocTabs(this._doc) {
    _doc.addListener(notifyListeners); // active tab's title/dirty dot
  }

  final DocumentController _doc;

  /// `state == null` marks the active tab (its state lives in the
  /// controller).
  final List<DocumentState?> _tabs = [null];
  int _active = 0;

  int get length => _tabs.length;
  int get activeIndex => _active;

  String? _pathOf(int i) =>
      _tabs[i] == null ? _doc.filePath : _tabs[i]!.filePath;

  String titleOf(int i) {
    final path = _pathOf(i);
    return path == null ? 'Untitled' : p.basename(path);
  }

  bool dirtyOf(int i) => _tabs[i] == null ? _doc.dirty : _tabs[i]!.dirty;

  /// Parks the active tab's live state back into its slot.
  void _captureActive() => _tabs[_active] = _doc.captureState();

  void select(int i) {
    if (i == _active || i < 0 || i >= _tabs.length) return;
    _captureActive();
    _doc.restoreState(_tabs[i]!);
    _tabs[i] = null;
    _active = i;
    notifyListeners();
  }

  /// Opens a fresh empty tab and makes it active.
  void newTab() {
    _captureActive();
    _tabs.add(null);
    _active = _tabs.length - 1;
    _doc.restoreState(DocumentState.empty());
    notifyListeners();
  }

  /// Removes tab [i]; never removes the last tab. Closing the active tab
  /// activates its right neighbour (or the new last tab). The caller is
  /// responsible for the confirm-if-dirty flow BEFORE calling this.
  void closeTab(int i) {
    if (_tabs.length <= 1 || i < 0 || i >= _tabs.length) return;
    if (i == _active) {
      _tabs.removeAt(i);
      _active = i.clamp(0, _tabs.length - 1);
      _doc.restoreState(_tabs[_active]!);
      _tabs[_active] = null;
    } else {
      _tabs.removeAt(i);
      if (i < _active) _active--;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _doc.removeListener(notifyListeners);
    super.dispose();
  }
}
