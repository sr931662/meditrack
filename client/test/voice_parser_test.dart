import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/features/home/voice_parser.dart';

void main() {
  VoiceKind k(String s) => parseVoiceCommand(s).kind;

  test('recognises the five senior responses', () {
    expect(k('I have taken it'), VoiceKind.taken);
    expect(k('I took my medicine'), VoiceKind.taken);
    expect(k('I need help'), VoiceKind.help);
    expect(k('Remind me again'), VoiceKind.remindLater);
    expect(k('I cannot find my medicine'), VoiceKind.cannotFind);
    expect(k("I can't find my pills"), VoiceKind.cannotFind);
    expect(k('I am not feeling well'), VoiceKind.unwell);
    expect(k("I don't feel well"), VoiceKind.unwell);
  });

  test('negated statements are never treated as taken (safety)', () {
    expect(k('I have not taken it'), isNot(VoiceKind.taken));
    expect(k("I haven't taken my medicine"), isNot(VoiceKind.taken));
    expect(k("I didn't take it yet"), isNot(VoiceKind.taken));
    expect(k('not yet'), isNot(VoiceKind.taken));
  });

  test('remind-me extracts minutes, defaulting to 15', () {
    expect(parseVoiceCommand('remind me in 20 minutes').minutes, 20);
    expect(parseVoiceCommand('remind me in 2 hours').minutes, 120);
    expect(parseVoiceCommand('remind me later').minutes, 15);
  });

  test('unrelated speech is unknown, never guessed', () {
    expect(k('what is the weather'), VoiceKind.unknown);
    expect(k(''), VoiceKind.unknown);
  });

  test('"show my next medicine" opens the next dose', () {
    expect(k('Show my next medicine'), VoiceKind.showNext);
  });
}
