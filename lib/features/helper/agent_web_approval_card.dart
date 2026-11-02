import 'package:flutter/material.dart';

import '../../core/design/app_design.dart';
import '../../core/l10n/l10n.dart';

class AgentWebApprovalCard extends StatelessWidget {
  final ValueChanged<bool> onAnswer;
  const AgentWebApprovalCard({super.key, required this.onAnswer});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppDesign.md),
    child: Material(
      key: const Key('agent-web-approval'),
      color: context.colors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: AppDesign.radius(AppDesign.rMd),
        side: BorderSide(color: context.colors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.agentWebApprovalTitle, style: context.text.body),
            Text(context.l10n.agentWebApprovalHint, style: context.text.small),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('agent-web-deny'),
                  onPressed: () => onAnswer(false),
                  child: Text(context.l10n.agentWebDeny),
                ),
                FilledButton.tonal(
                  key: const Key('agent-web-allow'),
                  onPressed: () => onAnswer(true),
                  child: Text(context.l10n.agentWebAllow),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
