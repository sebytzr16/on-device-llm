import 'package:flutter/material.dart';

import '../core/design/app_design.dart';
import '../core/motion/blur_switcher.dart';
import '../core/motion/pressable.dart';
import '../core/motion/spring_entrance.dart';
import '../data/storage/download_manager.dart';
import 'desktop_theme.dart';
import 'load_progress.dart';

/// The library section header: an amber bar and a bold title.
class ModelSectionLabel extends StatelessWidget {
  final String text;
  const ModelSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.md),
      child: Row(
        children: [
          Container(width: 3, height: 18, color: context.colors.accent),
          const SizedBox(width: AppDesign.sm + 2),
          Text(
            text,
            style: context.text.title.copyWith(
              fontWeight: FontWeight.w700,
              color: context.colors.text,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Rows rise into place one after another when the page opens.
class ModelRowCascade extends StatelessWidget {
  final int index;
  final Widget child;
  const ModelRowCascade({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) => SpringEntrance(
    delay: SpringEntrance.cascade(index),
    from: const Offset(0, 10),
    child: child,
  );
}

class ModelRowTable extends StatelessWidget {
  final List<Widget> children;
  const ModelRowTable({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppDesign.radius(AppDesign.rLg),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// The model's initials on a tinted square: rows tell apart at a glance
/// without a logo per maker.
class ModelArchBadge extends StatelessWidget {
  final String name;
  final bool active;
  const ModelArchBadge({super.key, required this.name, required this.active});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final words = name
        .split(RegExp(r'[\s\-_]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final initials = words.isEmpty
        ? '?'
        : (words.first[0] + (words.length > 1 ? words[1][0] : ''))
              .toUpperCase();
    return AnimatedContainer(
      duration: DesktopTheme.fast,
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? c.accent : c.surfaceRaised,
        borderRadius: AppDesign.radius(AppDesign.rMd),
        border: Border.all(color: active ? c.accent : c.hairline),
      ),
      child: Text(
        initials,
        style: context.text.mono.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: active ? c.onAccent : c.textMuted,
        ),
      ),
    );
  }
}

/// Shared desktop library row; adapters supply behavior, never their own layout.
class ModelRowShell extends StatefulWidget {
  const ModelRowShell({
    super.key,
    required this.name,
    required this.subtitle,
    required this.actions,
    this.active = false,
    this.tooltip,
    this.onTap,
    this.nameBadges = const [],
    this.details,
    this.progress,
  });
  final String name, subtitle;
  final Widget actions;
  final bool active;
  final String? tooltip;
  final VoidCallback? onTap;
  final List<Widget> nameBadges;
  final Widget? details, progress;

  @override
  State<ModelRowShell> createState() => _ModelRowShellState();
}

class _ModelRowShellState extends State<ModelRowShell> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: DesktopTheme.fast,
        constraints: const BoxConstraints(minHeight: AppDesign.rowHeight),
        decoration: BoxDecoration(
          color: widget.active
              ? c.accent.fade(0.06)
              : _hover
              ? c.text.fade(0.03)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: widget.active ? c.accent : Colors.transparent,
              width: AppSpace.xs - 1,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg - 1,
          AppSpace.md,
          AppSpace.lg + 2,
          AppSpace.md,
        ),
        child: Row(
          children: [
            ModelArchBadge(name: widget.name, active: widget.active),
            const SizedBox(width: AppSpace.md + 2),
            Expanded(
              flex: 5,
              child: InkWell(
                onTap: widget.onTap,
                child: Tooltip(
                  message: widget.tooltip ?? widget.name,
                  waitDuration: const Duration(milliseconds: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.name,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.body.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          ...widget.nameBadges,
                        ],
                      ),
                      const SizedBox(height: AppSpace.xs / 2),
                      Text(
                        widget.subtitle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: context.text.small,
                      ),
                      ?widget.details,
                      if (widget.progress != null) ...[
                        const SizedBox(height: AppSpace.row),
                        widget.progress!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.row),
            SizedBox(
              width: 270,
              child: BlurSwitcher(
                alignment: Alignment.centerRight,
                child: widget.actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The same progress/percent treatment for chat downloads and multi-file packs.
class ModelRowProgress extends StatelessWidget {
  const ModelRowProgress(this.progress, {super.key});
  final DownloadProgress progress;
  @override
  Widget build(BuildContext context) => DownloadProgressBar(progress);
}

class ModelRowButton extends StatelessWidget {
  const ModelRowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.accent = false,
    this.tonal = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool accent, tonal;
  @override
  Widget build(BuildContext context) => Pressable(
    child: ModelRowAction(
      accent: accent,
      tonal: tonal,
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}

class ModelRowAction extends StatelessWidget {
  const ModelRowAction({
    super.key,
    required this.child,
    required this.onPressed,
    this.accent = false,
    this.tonal = false,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final bool accent, tonal;
  @override
  Widget build(BuildContext context) => accent
      ? FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.accent,
            foregroundColor: context.colors.onAccent,
          ),
          onPressed: onPressed,
          child: child,
        )
      : tonal
      ? FilledButton.tonal(
          style: appTonalButtonStyle(context),
          onPressed: onPressed,
          child: child,
        )
      : OutlinedButton(onPressed: onPressed, child: child);
}

class ModelRowDeleteButton extends StatelessWidget {
  const ModelRowDeleteButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });
  final String tooltip;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: const Icon(Icons.delete_outline, size: 17),
  );
}
