import 'package:flutter/foundation.dart';

import 'tournament_controller_core.dart';
import 'workspace_state.dart';

export 'tournament_controller_core.dart'
    show NonReporterTreatment, PairingBatch, fideRatingsLocked;

/// Flutter notifications over the same commands used by the standalone CLI.
class TournamentController extends TournamentControllerCore
    with ChangeNotifier {
  TournamentController(super.repository);

  late final _flutterWorkspaceState = WorkspaceState(repository);
  @override
  WorkspaceState get workspaceState => _flutterWorkspaceState;

  @override
  void dispose() {
    releaseResources();
    super.dispose();
  }
}
