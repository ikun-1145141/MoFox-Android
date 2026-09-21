import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/wizard/domain/wizard_step.dart';
import 'package:mofox_android/features/wizard/domain/wizard_validation.dart';

void main() {
  group('WizardValidation', () {
    test('validates QQ number length and digits', () {
      expect(WizardValidation.qq('', label: 'Bot QQ'), isNotNull);
      expect(WizardValidation.qq('1234', label: 'Bot QQ'), isNotNull);
      expect(WizardValidation.qq('12345a', label: 'Bot QQ'), isNotNull);
      expect(WizardValidation.qq('123456789', label: 'Bot QQ'), isNull);
    });

    test('validates port range', () {
      expect(WizardValidation.port(0), isNotNull);
      expect(WizardValidation.port(65536), isNotNull);
      expect(WizardValidation.port(8095), isNull);
    });

    test('rejects duplicate and path-like instance names', () {
      expect(WizardValidation.instanceName(r'bot/name'), isNotNull);
      expect(
        WizardValidation.instanceName(
          'My Bot',
          existingNames: const <String>['my bot'],
        ),
        isNotNull,
      );
      expect(WizardValidation.instanceName('家用 Bot'), isNull);
    });

    test('validates the complete draft', () {
      const valid = InstanceDraft(
        name: '家用 Bot',
        botQq: '123456789',
        ownerQq: '987654321',
        apiKey: 'sk-1234567890123456',
        wsPort: 8095,
        webuiApiKey: 'long-random-secret',
      );
      expect(WizardValidation.draftIsValid(valid), isTrue);
      expect(
        WizardValidation.draftIsValid(valid.copyWith(wsPort: 70000)),
        isFalse,
      );
    });
  });
}
