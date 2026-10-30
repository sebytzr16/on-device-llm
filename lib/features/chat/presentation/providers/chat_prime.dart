part of 'chat_provider.dart';

void _primeThinking(
  StringBuffer system,
  InferenceSettings settings,
  TextEngine engine,
) {
  if (settings.thinkingModeEnabled &&
      engine.metrics['supportsThinking'] != true) {
    system.write(
      '\nIf your model supports reasoning, put your explanation in <think> and </think> before your final answer.',
    );
  }
}
