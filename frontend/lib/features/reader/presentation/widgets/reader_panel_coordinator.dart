/// 阅读器互斥面板类型。
enum ReaderPanelType { contents, settings, search, annotations, shortcuts }

/// 维护阅读器控制面板的单一打开状态。
class ReaderPanelCoordinator {
  ReaderPanelType? _active;

  ReaderPanelType? get active => _active;
  bool get isOpen => _active != null;

  bool toggle(ReaderPanelType panel) {
    final next = _active == panel ? null : panel;
    if (next == _active) {
      return false;
    }
    _active = next;
    return true;
  }

  bool open(ReaderPanelType panel) {
    if (_active == panel) {
      return false;
    }
    _active = panel;
    return true;
  }

  bool close() {
    if (_active == null) {
      return false;
    }
    _active = null;
    return true;
  }
}
