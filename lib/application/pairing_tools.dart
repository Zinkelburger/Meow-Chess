import 'dart:isolate';
import '../domain/model.dart';
import '../domain/simulation.dart';
import '../domain/swiss.dart';

// Top-level functions keep widget closures and BuildContexts out of the isolate
// message. A closure created inside a build callback can capture its UI scope.
Future<String> buildPairingChecklist(Event event, String? sectionId) =>
    Isolate.run(() => pairingChecklist(event, sectionId: sectionId));

Future<SimulationResult> generateSimulation(SimulationConfig config) =>
    Isolate.run(() => simulateTournament(config));
