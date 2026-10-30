import '../features/models/domain/entities/model_info.dart';

bool desktopModelVisible(ModelInfo model, {required bool advanced}) {
  final name = '${model.id} ${model.fileName} ${model.displayName}'
      .toLowerCase();
  return advanced ||
      (!name.contains('bonsai') && !name.contains('diffusiongemma'));
}
