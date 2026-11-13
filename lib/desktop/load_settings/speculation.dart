part of '../load_settings_dialog.dart';

// Speculative decoding: the MTP head and the draft/DFlash model.

/// Profile value prefix for a draft model picked from a file path.
const _draftPathPrefix = 'draft:';

extension _SpeculationSection on _LoadSettingsDialogState {
  Future<void> _readSpeculationCapability() async {
    try {
      final info = await ref.read(llamaEstimatorProvider).probe();
      if (mounted) {
        _update(() => _dflashSupported = info['supportsDFlash'] == true);
      }
    } catch (_) {
      // Older or unavailable libraries must not advertise a working driver.
    }
  }

  String _speculationMode(InferenceSettings s) {
    if (s.speculationMode != 'auto') return s.speculationMode;
    if (s.draftModelId == '$mtpHeadPrefix$mtpOff') return s.mtp ? 'mtp' : 'off';
    if (s.draftModelId.isNotEmpty && !s.draftModelId.startsWith(mtpHeadPrefix))
      return 'draft';
    return s.mtp ||
            _autoHead != null ||
            s.draftModelId.startsWith(mtpHeadPrefix)
        ? 'mtp'
        : 'off';
  }

  Future<void> _pickDraft(String mode) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
    );
    final path = picked.singleOrNull?.path;
    if (path == null || !mounted) return;
    try {
      final metadata = await GgufMetadata.inspect(path);
      if (!mounted) return;
      final t = context.l10n;
      if (metadata.architecture == 'dflash-draft') {
        throw StateError(t.desktopDFlashConvert);
      }
      if (path == m.localPath ||
          metadata.isMtpOnly ||
          (mode == 'dflash') != metadata.isDFlash) {
        throw StateError(t.desktopDraftModeMismatch);
      }
      _set('draftModelId', 'draft:$path');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _speculation(InferenceSettings s) {
    final t = context.l10n;
    final mode = _speculationMode(s);
    final drafts = ref
        .watch(modelManagerProvider)
        .catalog
        .where(
          (candidate) =>
              candidate.id != m.id &&
              candidate.isDownloaded &&
              candidate.localPath != null,
        );
    final ids = {for (final candidate in drafts) candidate.id};
    final selected = s.draftModelId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.desktopSpeculationMode, style: context.text.label),
        DropdownButton<String>(
          key: const Key('desktop-speculation-mode'),
          value: mode,
          isExpanded: true,
          items: [
            DropdownMenuItem(value: 'off', child: Text(t.desktopMtpHeadOff)),
            DropdownMenuItem(value: 'mtp', child: Text(t.desktopMtpLabel)),
            DropdownMenuItem(value: 'draft', child: Text(t.desktopDraftModel)),
            DropdownMenuItem(
              value: 'dflash',
              enabled: _dflashSupported,
              child: Text(t.desktopDFlash),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            _set('speculationMode', value);
            _set('mtp', value == 'mtp');
            _set('draftModelId', value == 'mtp' ? '' : '$mtpHeadPrefix$mtpOff');
          },
        ),
        if (!_dflashSupported)
          Text(t.desktopDFlashUnavailable, style: context.text.caption),
        if (mode == 'mtp') _mtpHead(s),
        if (mode == 'draft' || mode == 'dflash') ...[
          DropdownButtonFormField<String>(
            key: Key('desktop-draft-model-$selected'),
            initialValue: ids.contains(selected) ? selected : '',
            isExpanded: true,
            decoration: InputDecoration(labelText: t.desktopDraftModel),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(
                  selected.startsWith(_draftPathPrefix)
                      ? p.basename(selected.substring(_draftPathPrefix.length))
                      : t.desktopDraftRequired,
                ),
              ),
              for (final candidate in drafts)
                DropdownMenuItem(
                  value: candidate.id,
                  child: Text(
                    candidate.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null && value.isNotEmpty)
                _set('draftModelId', value);
            },
          ),
          TextButton(
            onPressed: mode == 'dflash' && !_dflashSupported
                ? null
                : () => _pickDraft(mode),
            child: Text(t.desktopDraftBrowse),
          ),
        ],
      ],
    );
  }

  Future<void> _listMtpHeads() async {
    // A head only fits its own base size; others are refused at load.
    final size = gemma4Size(m.fileName);
    final selected = _resolved().draftModelId;
    final heads = <String>[];
    GgufMetadata? target;
    if (m.localPath != null && await File(m.localPath!).exists()) {
      try {
        target = await GgufMetadata.inspect(m.localPath!);
      } catch (_) {
        /* Report invalid target at load. */
      }
    }
    if (!mounted) return;
    final candidates = {
      ...await mtpHeadFiles(),
      if (selected.startsWith(mtpHeadPrefix) &&
          selected != '$mtpHeadPrefix$mtpOff')
        selected.substring(mtpHeadPrefix.length),
    };
    if (!mounted) return;
    for (final h in candidates) {
      if (size != null &&
          gemma4Size(p.basename(h)) != null &&
          gemma4Size(p.basename(h)) != size) {
        continue;
      }
      try {
        final metadata = await GgufMetadata.inspect(h);
        if (!mounted) return;
        final issue = target == null
            ? context.l10n.mtpNeedsTarget
            : metadata.mtpHeadIssueFor(target, strings: context.l10n);
        if (issue == null) {
          heads.add(h);
        } else {
          _headIssues[h] = issue;
        }
      } catch (e) {
        _headIssues[h] = context.l10n.mtpReadFailed('$e');
      }
    }
    final auto = m.localPath == null ? null : await autoMtpHead(m.localPath!);
    if (mounted) {
      _update(() {
        _mtpHeads = heads;
        _autoHead = auto;
      });
    }
  }

  /// Copies a picked MTP head (LM Studio's `mtp-*.gguf` sidecar, say) into
  /// the models folder, so it outlives the app it came from.
  Future<void> _addMtpHead() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
    );
    final source = picked.singleOrNull?.path;
    if (source == null || !mounted) return;
    try {
      final metadata = await GgufMetadata.inspect(source);
      if (!mounted) return;
      final target = m.localPath == null
          ? null
          : await GgufMetadata.inspect(m.localPath!);
      if (!mounted) return;
      final issue = target == null
          ? context.l10n.mtpNeedsTarget
          : metadata.mtpHeadIssueFor(target, strings: context.l10n);
      if (issue != null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(issue)));
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.mtpReadFailed('$e'))),
        );
      }
      return;
    }
    var name = p.basename(source);
    if (!isMtpHeadFile(name)) name = 'mtp-$name';
    final dir = await ModelStorage.modelsDir();
    final target = await importMtpHead(source, dir.path, name);
    if (!mounted) return;
    await _listMtpHeads();
    if (!mounted) return;
    _set('draftModelId', '$mtpHeadPrefix$target');
  }

  /// The MTP head picker: Auto (the matching head on disk, found beside
  /// the model or in LM Studio's folder), Off, or a chosen head file, and
  /// how many tokens a chosen head drafts per step.
  Widget _mtpHead(InferenceSettings s) {
    final t = context.l10n, c = context.colors;
    final current = s.draftModelId.startsWith(mtpHeadPrefix)
        ? s.draftModelId.substring(mtpHeadPrefix.length)
        : '';
    final heads = {
      ..._mtpHeads,
      if (current.isNotEmpty && current != mtpOff) current,
    }.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(t.desktopMtpHeadLabel, style: context.text.label),
            const SizedBox(width: 12),
            // A dropdown sizes to its widest item; a long head file name
            // squeezed the label to one letter per line.
            Expanded(
              child: DropdownButton<String>(
                key: const Key('desktop-mtp-head'),
                value: current,
                isExpanded: true,
                borderRadius: AppDesign.radius(AppDesign.rMd),
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(
                      _autoHead == null
                          ? t.desktopMtpHeadAutoNone
                          : t.desktopMtpHeadAuto(p.basename(_autoHead!)),
                    ),
                  ),
                  DropdownMenuItem(
                    value: mtpOff,
                    child: Text(t.desktopMtpHeadOff),
                  ),
                  for (final h in heads)
                    DropdownMenuItem(
                      value: h,
                      child: Text(
                        p.basename(h),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  DropdownMenuItem(
                    value: '+',
                    child: Text(t.desktopMtpHeadAdd),
                  ),
                ],
                onChanged: (v) {
                  if (v == '+') {
                    _addMtpHead();
                  } else if (v != null) {
                    _set('draftModelId', v.isEmpty ? null : '$mtpHeadPrefix$v');
                  }
                },
              ),
            ),
          ],
        ),
        Text(
          t.desktopMtpHeadHint,
          style: context.text.caption.copyWith(color: c.textMuted),
        ),
        if (_headIssues[current] != null)
          Text(
            _headIssues[current]!,
            style: context.text.caption.copyWith(color: c.textMuted),
          ),
        if (current.isNotEmpty && current != mtpOff)
          DesktopSlider(
            label: t.desktopMtpHeadTokens,
            value: s.draftMaxTokens.clamp(1, 8).toDouble(),
            min: 1,
            max: 8,
            divisions: 7,
            format: (v) => '${v.round()}',
            onChanged: (v) => _set('draftMaxTokens', v.round()),
          ),
      ],
    );
  }
}

/// Preserve a different file with the same basename, including equal-size files.
Future<String> importMtpHead(
  String source,
  String directory,
  String name,
) async {
  final input = File(source);
  final sourceSize = await input.length();
  String? digest;
  var target = p.join(directory, name);
  var suffix = 1;
  while (await File(target).exists()) {
    if (await File(target).length() == sourceSize) {
      digest ??= (await sha256.bind(input.openRead()).first).toString();
      final existing = (await sha256.bind(File(target).openRead()).first)
          .toString();
      if (digest == existing) return target;
    }
    target = p.join(
      directory,
      '${p.basenameWithoutExtension(name)}-${suffix++}${p.extension(name)}',
    );
  }
  await input.copy(target);
  return target;
}
