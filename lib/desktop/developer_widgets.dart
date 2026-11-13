import 'package:flutter/material.dart';
import '../core/design/app_design.dart';
import '../core/motion/pressable.dart';
import '../core/motion/spring_entrance.dart';

class DeveloperCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const DeveloperCard({super.key, required this.title, required this.children});
  @override
  Widget build(BuildContext context) => SpringEntrance(
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.surfaceRaised,
        border: Border.all(color: context.colors.hairline),
        borderRadius: AppDesign.radius(AppDesign.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.text.title),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}

class DeveloperButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// The page's main action: filled amber instead of an outline.
  final bool primary;
  final IconData? icon;
  const DeveloperButton({
    super.key,
    required this.label,
    this.onPressed,
    this.primary = false,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => Pressable(
    enabled: onPressed != null,
    child: primary
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: icon == null ? null : Icon(icon, size: 18),
            label: Text(label),
          )
        : OutlinedButton.icon(
            style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
            onPressed: onPressed,
            icon: icon == null ? null : Icon(icon, size: 16),
            label: Text(label),
          ),
  );
}

/// A desktop page's heading: the serif title and one muted line under it.
class DeveloperPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const DeveloperPageHeader({super.key, required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.section),
    child: AppPageHeader(title: title, subtitle: subtitle),
  );
}
