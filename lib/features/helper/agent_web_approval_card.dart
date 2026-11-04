import 'package:flutter/material.dart';

import '../../core/design/app_design.dart';
import '../../core/l10n/l10n.dart';

class AgentWebApprovalCard extends StatelessWidget {
  final ValueChanged<bool> onAnswer;
  final String? description;
  const AgentWebApprovalCard({
    super.key,
    required this.onAnswer,
    this.description,
  });

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
            Text(
              description == null
                  ? context.l10n.agentWebApprovalTitle
                  : context.l10n.workspaceApprovalTitle,
              style: context.text.body,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(
                  description ?? context.l10n.agentWebApprovalHint,
                  style: context.text.small,
                ),
              ),
            ),
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
