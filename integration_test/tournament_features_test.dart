import 'package:integration_test/integration_test.dart';
import '../test/ui/tournament_features_test.dart' as scenarios;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.main();
}
