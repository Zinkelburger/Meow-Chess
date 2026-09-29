import '../domain/model.dart';
import 'tournament_controller.dart';

void populatePractice(TournamentController controller) {
  controller.create('Saturday at the club', practice: true);
  const names = [
    'Alex Chen',
    'Morgan Lee',
    'Jamie Patel',
    'Sam Rivera',
    'Taylor Brooks',
    'Casey Park',
    'Jordan Ellis',
    'Riley Santos',
    'Avery Kim',
    'Quinn Taylor',
    'Robin Wells',
    'Drew Martin',
    'Cameron Reed',
    'Skyler Jones',
    'Finley Price',
    'Reese Clark',
    'Dakota Hall',
    'Sage Wilson',
    'Emery Davis',
    'Blair Lewis',
    'Rowan Walker',
    'Charlie Scott',
  ];
  controller.importPlayers([
    for (final (i, name) in names.indexed)
      Player(
        id: controller.newId(),
        name: name,
        rating: 2100 - i * 45,
        checkedIn: true,
        source: 'Synthetic practice fixture',
      ),
  ]);
  controller.applyQuads(controller.quadPreview(), controller.event!.revision);
}
