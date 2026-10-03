import 'package:flutter/foundation.dart';

import 'workspace_state_core.dart';

/// Flutter notification adapter for durable workspace drafts.
class WorkspaceState extends WorkspaceStateCore with ChangeNotifier {
  WorkspaceState(super.repository);

  @override
  void dispose() {
    releaseResources();
    super.dispose();
  }
}
