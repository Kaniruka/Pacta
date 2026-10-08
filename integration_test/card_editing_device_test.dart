import 'package:integration_test/integration_test.dart';

import '../test/national_focus/card_editing_test.dart' as card_editing;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  card_editing.main();
}
