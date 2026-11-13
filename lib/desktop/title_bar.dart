import '../features/models/presentation/widgets/download_center.dart';
import '../core/platform/desktop_preferences.dart';
import 'model_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import '../core/motion/blur_switcher.dart';
import '../core/motion/pressable.dart';
import '../features/chat/presentation/providers/chat_provider.dart';
import '../features/models/domain/entities/model_info.dart';
import '../features/models/presentation/widgets/model_categories.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/settings/presentation/providers/settings_provider.dart';
import 'desktop_app.dart';
import 'desktop_theme.dart';
import 'focus_ring.dart';
import 'load_progress.dart';

/// The window's own title bar: sidebar toggle and app mark on the left, the
/// model picker in the middle, Windows caption buttons on the right. Empty
/// space drags the window; a double-click maximises it.
class DesktopTitleBar extends ConsumerWidget {
  final VoidCallback onToggleSidebar;
  const DesktopTitleBar({super.key, required this.onToggleSidebar});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return SizedBox(
      height: DesktopTheme.titleBarHeight,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DragToMoveArea(child: SizedBox.expand()),
          ),
          Row(
            children: [
              const SizedBox(width: 6),
              _BarButton(
                icon: Icons.view_sidebar_outlined,
                tooltip: '${context.l10n.desktopToggleSidebar} (Ctrl+B)',
                onPressed: onToggleSidebar,
              ),
              const SizedBox(width: 6),
              // The phone's app icon and its Fraunces wordmark.
              ClipRRect(
                borderRadius: AppDesign.radius(6),
                child: Image.asset(
                  'assets/brand/icon-1024.png',
                  width: 22,
                  height: 22,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              const SizedBox(width: 10),
              IgnorePointer(
                child: Text.rich(
                  TextSpan(
                    text: 'OnDevice ',
                    children: [
                      TextSpan(
                        text: 'LLM',
                        style: TextStyle(color: c.accent),
                      ),
                    ],
                  ),
                  style: context.text.display.copyWith(
                    fontSize: 16,
                    height: 1,
                    color: c.text,
                  ),
                ),
              ),
              const Spacer(),
              const DownloadsButton(onlyWhenActive: true),
              const _CaptionButtons(),
            ],
          ),
          const Align(child: ModelPickerChip()),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    style: IconButton.styleFrom(
      minimumSize: const Size(34, 30),
      fixedSize: const Size(34, 30),
      shape: const StadiumBorder(),
    ),
  );
}

/// The loaded model, and a menu to load another one or open the manager.
class ModelPickerChip extends ConsumerWidget {
  const ModelPickerChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final models = ref.watch(modelManagerProvider);
    final busy =
        ref.watch(chatProvider.select((s) => s.isGenerating)) ||
        models.isImporting;
    final loaded = models.loadedModel;
    final local = models.catalog
        .where(
          (m) =>
              m.isDownloaded &&
              // Draft/DFlash files, embedders and projectors cannot chat.
              modelCategory(m.fileName) == ModelCategory.llm &&
              desktopModelVisible(
                m,
                advanced: ref.watch(desktopPreferencesProvider).advanced,
              ),
        )
        .toList();
    final loading = models.isLoadingModel
        ? models.catalog.where((m) => m.id == models.loadingModelId).firstOrNull
        : null;
    final progress = models.isLoadingModel ? models.loadProgress : null;
    final label = models.isLoadingModel
        ? loading?.displayName ?? context.l10n.loadingModel
        : loaded?.displayName ?? context.l10n.desktopPickModel;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: const MenuStyle(minimumSize: WidgetStatePropertyAll(Size(340, 0))),
      menuChildren: [
        if (local.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppDesign.md),
            child: SizedBox(
              width: 300,
              child: Text(
                context.l10n.desktopNoModels,
                style: context.text.small,
              ),
            ),
          ),
        for (final m in local)
          MenuItemButton(
            leadingIcon: Icon(
              m.id == models.loadedModelId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 16,
              color: m.id == models.loadedModelId ? c.accent : c.textFaint,
            ),
            trailingIcon: Text(
              '${_quant(m)} · ${m.sizeLabel}',
              style: context.text.mono.copyWith(fontSize: 11),
            ),
            onPressed: busy || models.isLoadingModel
                ? null
                : () => _load(context, ref, m),
            child: Text(m.displayName),
          ),
        if (models.isLoadingModel)
          MenuItemButton(
            leadingIcon: const Icon(Icons.stop_rounded, size: 16),
            onPressed: () => ref.read(modelManagerProvider.notifier).stopLoad(),
            child: Text(context.l10n.desktopStopLoading),
          ),
        const Divider(height: 9),
        if (loaded != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.eject_outlined, size: 16),
            onPressed: () =>
                ref.read(modelManagerProvider.notifier).unloadModel(),
            child: Text(context.l10n.desktopEject),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.view_list_outlined, size: 16),
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyM,
            control: true,
          ),
          onPressed: () => ref
              .read(desktopSectionProvider.notifier)
              .show(DesktopSection.models),
          child: Text(context.l10n.models),
        ),
      ],
      builder: (context, controller, _) => Pressable(
        pressedScale: 0.97,
        child: Material(
          color: c.surfaceRaised.fade(0.9),
          shape: RoundedRectangleBorder(
            borderRadius: AppDesign.radius(AppDesign.rFull),
            side: BorderSide(color: c.hairline),
          ),
          child: DesktopFocusRing(
            label: context.l10n.desktopPickModel,
            child: InkWell(
              borderRadius: AppDesign.radius(AppDesign.rFull),
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 260, maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  // A newly loaded model blurs in over the old name.
                  child: BlurSwitcher(
                    child: Row(
                      key: ValueKey((label, models.isLoadingModel)),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (models.isLoadingModel)
                          SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              value: progress == null || progress <= 0
                                  ? null
                                  : progress,
                            ),
                          )
                        else
                          Icon(
                            Icons.memory_rounded,
                            size: 15,
                            color: loaded != null ? c.accent : c.textFaint,
                          ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.small.copyWith(
                              color: loaded != null ? c.text : c.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        if (models.isLoadingModel) ...[
                          const SizedBox(width: 8),
                          Text(
                            loadPhaseLabel(
                              context,
                              progress,
                              hasProjector: loading?.projector != null,
                            ),
                            style: context.text.mono.copyWith(
                              fontSize: 11,
                              color: c.accent,
                            ),
                          ),
                        ] else if (loaded != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _quant(loaded),
                            style: context.text.mono.copyWith(fontSize: 11),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: c.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _quant(ModelInfo m) => m.quantLabel;

  static Future<void> _load(
    BuildContext context,
    WidgetRef ref,
    ModelInfo m,
  ) async {
    // Choosing a model on this PC means answering here, as on the phone.
    final settings = ref.read(settingsProvider);
    if (settings.remoteEnabled) {
      await ref
          .read(settingsProvider.notifier)
          .update(settings.copyWith(remoteEnabled: false));
    }
    try {
      await ref.read(modelManagerProvider.notifier).loadModel(m);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

/// Minimise, maximise/restore and close, drawn like Windows 11's own: 46 px
/// wide, Segoe Fluent Icons glyphs, the red close hover.
class _CaptionButtons extends StatefulWidget {
  const _CaptionButtons();

  @override
  State<_CaptionButtons> createState() => _CaptionButtonsState();
}

class _CaptionButtonsState extends State<_CaptionButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Caption(
          glyph: '',
          tooltip: l10n.desktopMinimize,
          onPressed: windowManager.minimize,
        ),
        _Caption(
          glyph: _maximized ? '' : '',
          tooltip: _maximized ? l10n.desktopRestore : l10n.desktopMaximize,
          onPressed: () async => await windowManager.isMaximized()
              ? windowManager.unmaximize()
              : windowManager.maximize(),
        ),
        _Caption(
          glyph: '',
          tooltip: l10n.desktopClose,
          close: true,
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

class _Caption extends StatefulWidget {
  final String glyph, tooltip;
  final bool close;
  final VoidCallback onPressed;
  const _Caption({
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.close = false,
  });

  @override
  State<_Caption> createState() => _CaptionState();
}

class _CaptionState extends State<_Caption> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = widget.close
        ? (_down
              ? const Color(0xFFC42B1C).fade(0.85)
              : _hover
              ? const Color(0xFFC42B1C)
              : Colors.transparent)
        : (_down
              ? c.text.fade(0.06)
              : _hover
              ? c.text.fade(0.09)
              : Colors.transparent);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = _down = false),
      child: DesktopFocusRing(
        label: widget.tooltip,
        child: InkWell(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTap: () {
            setState(() => _down = false);
            widget.onPressed();
          },
          child: Tooltip(
            message: widget.tooltip,
            child: AnimatedContainer(
              duration: DesktopTheme.fast,
              width: 46,
              height: DesktopTheme.titleBarHeight,
              color: bg,
              alignment: Alignment.center,
              child: Text(
                widget.glyph,
                style: TextStyle(
                  fontFamily: 'Segoe Fluent Icons',
                  fontFamilyFallback: const ['Segoe MDL2 Assets'],
                  fontSize: 10,
                  color: widget.close && _hover ? Colors.white : c.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
