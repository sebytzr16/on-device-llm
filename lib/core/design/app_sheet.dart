import 'package:flutter/material.dart';

import '../motion/motion.dart';
import 'app_design.dart';

/// Keeps sheet actions reachable while long content and the keyboard scroll.
/// The route owns the surface and grabber; this widget owns the content.
class AppSheet extends StatelessWidget {
  final String title;
  final String? meta;
  final Widget? leading;
  final List<Widget> children;
  final Widget? primary, secondary;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  const AppSheet({
    super.key,
    required this.title,
    this.meta,
    this.leading,
    required this.children,
    this.primary,
    this.secondary,
    this.scrollable = true,
    this.padding = const EdgeInsets.symmetric(horizontal: AppDesign.lg),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final actions = primary != null || secondary != null;
    final body = scrollable
        ? SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppDesign.md,
              children: children,
            ),
          )
        : Padding(
            padding: padding,
            child: children.length == 1
                ? children.single
                : Column(mainAxisSize: MainAxisSize.min, children: children),
          );
    const buttonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, AppDesign.actionHeight)),
      shape: WidgetStatePropertyAll(StadiumBorder()),
    );
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      duration: context.motion.fade(AppMotion.track),
      curve: AppMotion.ease,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDesign.lg,
              AppDesign.sm,
              AppDesign.sm,
              AppDesign.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: AppDesign.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.headline),
                      if (meta != null) ...[
                        const SizedBox(height: AppDesign.xs),
                        Text(
                          meta!,
                          style: context.text.small.copyWith(
                            color: c.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ],
            ),
          ),
          Flexible(child: body),
          if (actions) ...[
            Divider(height: 1, thickness: 1, color: c.hairline),
            Padding(
              key: const Key('app-sheet-actions'),
              padding: EdgeInsets.fromLTRB(
                AppDesign.lg,
                AppDesign.md,
                AppDesign.lg,
                AppDesign.md + MediaQuery.viewPaddingOf(context).bottom,
              ),
              // Merged over the app's button themes: a bare theme here would
              // replace them and drop the accent fill, text style and padding.
              child: FilledButtonTheme(
                data: FilledButtonThemeData(
                  style: buttonStyle.merge(FilledButtonTheme.of(context).style),
                ),
                child: OutlinedButtonTheme(
                  data: OutlinedButtonThemeData(
                    style: buttonStyle.merge(
                      OutlinedButtonTheme.of(context).style,
                    ),
                  ),
                  child: TextButtonTheme(
                    data: TextButtonThemeData(
                      style: buttonStyle.merge(
                        TextButtonTheme.of(context).style,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (secondary != null) Expanded(child: secondary!),
                        if (secondary != null && primary != null)
                          const SizedBox(width: AppDesign.md),
                        if (primary != null) Expanded(child: primary!),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ] else
            SizedBox(
              height: AppDesign.md + MediaQuery.viewPaddingOf(context).bottom,
            ),
        ],
      ),
    );
  }
}

/// A grouped surface inside a sheet, using the smaller sheet-card radius.
class AppSheetCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AppSheetCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppDesign.lg),
  });

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    padding: padding,
    decoration: BoxDecoration(
      color: context.colors.surfaceRaised,
      border: Border.all(color: context.colors.hairline),
      borderRadius: AppDesign.radius(AppDesign.rMd),
    ),
    child: child,
  );
}
