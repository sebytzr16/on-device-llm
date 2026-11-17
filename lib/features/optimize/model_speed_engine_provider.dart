import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/shared_providers.dart';
import '../../inference/engine/text_engine.dart';

final modelSpeedEngineProvider = Provider<TextEngine>(
  (ref) => ref.read(llamaEngineProvider),
);
