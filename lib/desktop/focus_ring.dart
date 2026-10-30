import 'package:flutter/material.dart';

import '../core/design/app_design.dart';

/// Paints focus around custom rows and pills without adding a Tab stop.
class DesktopFocusRing extends StatefulWidget {
  final Widget child;
  final String? label;
  final ValueChanged<bool>? onFocusChange;
  const DesktopFocusRing({
    super.key,
    required this.child,
    this.label,
    this.onFocusChange,
  });
  @override
  State<DesktopFocusRing> createState() => _DesktopFocusRingState();
}

class _DesktopFocusRingState extends State<DesktopFocusRing> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (value) {
      setState(() => _focused = value);
      widget.onFocusChange?.call(value);
    },
    child: Semantics(
      label: widget.label,
      button: widget.label == null ? null : true,
      child: Container(
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: _focused
              ? Border.all(color: context.colors.accent, width: 2)
              : null,
        ),
        child: widget.child,
      ),
    ),
  );
}
