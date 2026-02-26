import 'package:code/core/ai/router_schema_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final RouterSchemaValidator validator = RouterSchemaValidator();

  test('router schema validator accepts valid payload', () {
    final result = validator.validate({
      'action': 'create_todo',
      'confidence': 0.92,
      'payload': {
        'title': '买牛奶',
        'priority': 'high',
        'tags': ['生活'],
      },
    });

    expect(result.isValid, isTrue);
  });

  test('router schema validator rejects invalid payloads', () {
    final missingField = validator.validate({
      'action': 'create_todo',
      'payload': {'title': 'x', 'priority': 'high', 'tags': []},
    });
    expect(missingField.isValid, isFalse);

    final invalidAction = validator.validate({
      'action': 'unknown',
      'confidence': 0.5,
      'payload': {},
    });
    expect(invalidAction.isValid, isFalse);

    final extraField = validator.validate({
      'action': 'create_bookmark',
      'confidence': 0.7,
      'payload': {'url': 'https://example.com'},
      'extra': 1,
    });
    expect(extraField.isValid, isFalse);

    final invalidBookmarkUrl = validator.validate({
      'action': 'create_bookmark',
      'confidence': 0.7,
      'payload': {'url': 'http://example.com'},
    });
    expect(invalidBookmarkUrl.isValid, isFalse);

    final invalidRemindAt = validator.validate({
      'action': 'create_todo',
      'confidence': 0.8,
      'payload': {
        'title': 'x',
        'priority': 'medium',
        'tags': <String>[],
        'remind_at': 'tomorrow 8pm',
      },
    });
    expect(invalidRemindAt.isValid, isFalse);
  });
}
