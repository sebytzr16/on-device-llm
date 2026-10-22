import '../../../core/l10n/l10n.dart';
import '../goal_specialization.dart';

/// The user-facing names of the kinds of research, in the app's language.
/// (The planner, step and report instructions stay in English: they are
/// written for the model, which is told to answer in the goal's language.)
extension GoalKindText on GoalSpecialization {
  String labelIn(AppLocalizations t) => switch (this) {
    GoalSpecialization.general => t.goalKindGeneral,
    GoalSpecialization.code => t.goalKindCode,
    GoalSpecialization.science => t.goalKindScience,
    GoalSpecialization.math => t.goalKindMath,
    GoalSpecialization.news => t.goalKindNews,
    GoalSpecialization.product => t.goalKindProduct,
  };

  String descriptionIn(AppLocalizations t) => switch (this) {
    GoalSpecialization.general => t.goalKindGeneralHint,
    GoalSpecialization.code => t.goalKindCodeHint,
    GoalSpecialization.science => t.goalKindScienceHint,
    GoalSpecialization.math => t.goalKindMathHint,
    GoalSpecialization.news => t.goalKindNewsHint,
    GoalSpecialization.product => t.goalKindProductHint,
  };

  String criteriaIn(AppLocalizations t) => switch (this) {
    GoalSpecialization.general => t.goalKindGeneralCriteria,
    GoalSpecialization.code => t.goalKindCodeCriteria,
    GoalSpecialization.science => t.goalKindScienceCriteria,
    GoalSpecialization.math => t.goalKindMathCriteria,
    GoalSpecialization.news => t.goalKindNewsCriteria,
    GoalSpecialization.product => t.goalKindProductCriteria,
  };
}
