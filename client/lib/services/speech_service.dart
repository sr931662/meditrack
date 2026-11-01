import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

abstract class SpeechService {
  Future<void> speak(String text, {double rate = .5});
  Future<void> stopSpeaking();
  Future<bool> get canListen;
  Future<void> listen(void Function(String text, bool isFinal) onResult, void Function(String error) onError);
  Future<void> stopListening();
}

/// Text-to-speech and speech-to-text from the device. Recognition language is configurable per senior
/// (`localeId`); on-device packs vary by handset, so the UI always offers a typed fallback.
class DeviceSpeechService implements SpeechService {
  final _tts = FlutterTts();
  final _stt = SpeechToText();
  String localeId = 'en_US';
  bool _ready = false;

  @override
  Future<void> speak(String text, {double rate = .5}) async {
    try {
      await _tts.setSpeechRate(rate);
      await _tts.setLanguage(localeId.replaceAll('_', '-'));
      await _tts.speak(text);
    } catch (_) {
      // TTS engines can be missing or busy; the on-screen reminder is always shown as well.
    }
  }

  @override
  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  @override
  Future<bool> get canListen async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize();
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<void> listen(void Function(String text, bool isFinal) onResult, void Function(String error) onError) async {
    if (!await canListen) return onError('unavailable');
    await _stt.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
        localeId: localeId,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 20),
      ),
    );
  }

  @override
  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
