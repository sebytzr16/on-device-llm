// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingScopeHint =>
      'Clear a value to use the default from the previous layer. Settings marked ↻ take effect when the model loads.';

  @override
  String get settingExplicit => 'Customized';

  @override
  String get settingInherited => 'Inherited';

  @override
  String get settingOnePerLine => 'One per line';

  @override
  String get nearbyHosts => 'Find nearby hosts';

  @override
  String get nearbyHostsHint =>
      'Find OnDevice LLM hosts on the same network. Select one, then enter its access key or use its pairing QR code.';

  @override
  String get nearbyHostsNone =>
      'No hosts found. Start hosting on the other device and check that both devices use the same network. Manual pairing remains available.';

  @override
  String get scanConfidence => 'Recognizer confidence';

  @override
  String get scanSettings => 'Text recognition';

  @override
  String get scanPageLimit => 'Scanned pages per PDF';

  @override
  String get scanLongHint =>
      'Text layers are read beyond this limit. Longer scans show progress and can be stopped.';

  @override
  String get scanLanguage => 'Recognition language';

  @override
  String get scanLatinHint =>
      'Android recognizes English, French, Spanish and other Latin-script text automatically, on this device.';

  @override
  String get scanQualityHint =>
      'Recognizer confidence can still be wrong. Check important text against the original.';

  @override
  String get modelSettingsAll => 'All model settings';

  @override
  String get modelSettingsGlobal => 'Your model settings';

  @override
  String get modelSettingsAllHint =>
      'Edit or reset the settings used by model profiles, presets and chats';

  @override
  String get removeProjectHint =>
      'Remove this project and its instructions? Its conversations and knowledge files will be kept.';

  @override
  String get downloadQueued => 'Waiting for a download slot';

  @override
  String get sourceMessage => 'Source message';

  @override
  String get sourceMessageMissing =>
      'This source message is no longer available.';

  @override
  String get openConversation => 'Open conversation';

  @override
  String get contextSummary => 'Review context summary';

  @override
  String get contextSummaryHint =>
      'Write a summary of these earlier messages. Review it before saving; later answers can use it in place of this part of the conversation.';

  @override
  String get contextSummaryTooShort =>
      'More conversation history is needed before making a summary.';

  @override
  String get memoryUsed => 'Memory used';

  @override
  String get unverifiedFeatures => 'Features requiring verification';

  @override
  String get restoreVersion => 'Use this version';

  @override
  String get originalFile => 'Share original file';

  @override
  String get previousVersion => 'Previous version';

  @override
  String get workspaceTitle => 'Projects and conversations';

  @override
  String get project => 'Project';

  @override
  String get projectName => 'Project name';

  @override
  String get projectInstructions => 'Instructions for this project';

  @override
  String get noProject => 'No project';

  @override
  String get archivedChats => 'Archived';

  @override
  String get trashChats => 'Trash';

  @override
  String get archiveChats => 'Archive';

  @override
  String get restoreChats => 'Restore';

  @override
  String get moveToTrash => 'Move to trash';

  @override
  String get permanentDeleteHint =>
      'Permanently remove these conversations and attachments from this device. This cannot be undone.';

  @override
  String get selectAllChats => 'Select all';

  @override
  String get temporaryChat => 'Temporary chat';

  @override
  String get temporaryChatHint =>
      'This chat and its draft stay in memory. Memory is off. Leaving discards it; remote and web requests still use your selected connection.';

  @override
  String get deleteAnswer => 'Delete answer';

  @override
  String get deleteQuestionAnswer => 'Delete question and answer';

  @override
  String get messageDeleted => 'Message deleted';

  @override
  String get undo => 'Undo';

  @override
  String get undoUnavailable =>
      'Undo is unavailable while another operation is running.';

  @override
  String get appTitle => 'OnDevice';

  @override
  String get noModelLoaded => 'no model loaded';

  @override
  String get newChat => 'New chat';

  @override
  String get drawerTemporary => 'Temporary';

  @override
  String get drawerWorkspace => 'Workspace';

  @override
  String get drawerProjects => 'Projects & conversations';

  @override
  String get drawerProjectsHint => 'Projects, archive and trash';

  @override
  String drawerProjectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projects',
      one: '1 project',
      zero: 'Group chats with shared instructions',
    );
    return '$_temp0';
  }

  @override
  String get previous7Days => 'Previous 7 days';

  @override
  String get previous30Days => 'Previous 30 days';

  @override
  String get olderChats => 'Older';

  @override
  String get chatOptions => 'Chat options';

  @override
  String get shareOrExport => 'Share or export';

  @override
  String get thisChatSection => 'This chat';

  @override
  String get conversations => 'Conversations';

  @override
  String get more => 'More';

  @override
  String get exportMarkdown => 'Export Markdown';

  @override
  String get exportJson => 'Export JSON';

  @override
  String get shareAsText => 'Share as text';

  @override
  String get createDocument => 'Create document';

  @override
  String get documentFormat => 'Format';

  @override
  String get answersOnly => 'Assistant answers only';

  @override
  String get includeBranches => 'Include earlier branches';

  @override
  String get includeReasoning => 'Include model reasoning';

  @override
  String get saveDocument => 'Save document';

  @override
  String get models => 'Models';

  @override
  String get settings => 'Settings';

  @override
  String get metrics => 'Metrics';

  @override
  String get loadingModel => 'Loading model into memory…';

  @override
  String get messageHint => 'Message your model…';

  @override
  String get listening => 'Listening…';

  @override
  String get chooseModel => 'Choose a model';

  @override
  String get think => 'Think';

  @override
  String get thinkOff => 'Off';

  @override
  String get thinkLow => 'Low';

  @override
  String get thinkMedium => 'Medium';

  @override
  String get thinkHigh => 'High';

  @override
  String get thinkOffHint => 'Answers right away. The fastest.';

  @override
  String get thinkLowHint => 'A short reasoning pass first (about 500 tokens).';

  @override
  String get thinkMediumHint =>
      'Reasons longer first (about 2,000 tokens), for harder questions.';

  @override
  String get thinkHighHint =>
      'Reasons at length first (about 8,000 tokens). The slowest.';

  @override
  String thinkLevelToast(String level) {
    return 'Thinking: $level';
  }

  @override
  String get thinkOffToast => 'Thinking off';

  @override
  String get attachTooltip => 'Attach a photo or file, or choose tools';

  @override
  String get dictate => 'Dictate';

  @override
  String get stopDictation => 'Stop dictation';

  @override
  String get send => 'Send message';

  @override
  String get stop => 'Stop generation';

  @override
  String get modelPill => 'Model';

  @override
  String get webLocal => 'Local';

  @override
  String get webAuto => 'auto';

  @override
  String get webAlways => 'always';

  @override
  String get emptyTitle => 'A little more intelligence.\nA lot more privacy.';

  @override
  String get emptyHasModel =>
      'Your model is here, running entirely on this device. Ask it anything.';

  @override
  String emptyRemote(String host) {
    return 'Answers come from your remote server ($host); your messages are sent there. Ask it anything.';
  }

  @override
  String get emptyNoModel =>
      'No model yet. Open Models to download a starter or import your own GGUF, then come back and ask anything.';

  @override
  String get askPhoto => 'Ask about a photo';

  @override
  String get askFile => 'Ask about a file';

  @override
  String get generating => 'generating…';

  @override
  String get runDetails => 'How this was made';

  @override
  String get answerWarning => 'What the source check doubted';

  @override
  String get copyRunDetails => 'Copy run details';

  @override
  String get runDetailsCopied => 'Run details copied';

  @override
  String get runMeasured => 'MEASURED';

  @override
  String get runSettings => 'Settings in force';

  @override
  String get runEngine => 'ENGINE';

  @override
  String get copyResponse => 'Copy response';

  @override
  String get copyQuestion => 'Copy question';

  @override
  String get responseCopied => 'Response copied';

  @override
  String get readAloud => 'Read aloud';

  @override
  String get stopReading => 'Stop reading';

  @override
  String get regenerate =>
      'Regenerate (keeps this answer as an earlier version)';

  @override
  String get continueAnswer => 'Continue this answer';

  @override
  String get compareWith => 'Compare with another model';

  @override
  String get editQuestion => 'Edit question';

  @override
  String get askAgain => 'Ask again';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get earlierQuestion => 'Earlier question';

  @override
  String get earlierAnswer => 'Earlier answer';

  @override
  String get restoreBranch => 'Restore this branch';

  @override
  String get stoppedPartial => 'Stopped · partial response';

  @override
  String get interruptedClosed =>
      'Interrupted · the app closed before the answer finished';

  @override
  String get interruptedPartial => 'Interrupted · partial response';

  @override
  String get interruptedError => 'Interrupted by an error';

  @override
  String get searchConversations => 'Search conversations';

  @override
  String get storedOnDevice => 'Stored only on this device';

  @override
  String get noConversations =>
      'No conversations yet.\nYour chats will appear here.';

  @override
  String nothingMatches(String query) {
    return 'Nothing matches “$query”.';
  }

  @override
  String get pinned => 'Pinned';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get earlier => 'Earlier';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Follow the phone';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageSpanish => 'Español';

  @override
  String get resetToDefaults => 'Reset to defaults';

  @override
  String get sectionAssistant => 'Assistant';

  @override
  String get thinkingMode => 'Thinking mode';

  @override
  String get thinkingModeHint =>
      'Show model-generated reasoning when supported. It may contain mistakes and is not proof of correctness.';

  @override
  String get webResearch => 'Web research (keyless)';

  @override
  String get webOffHint => 'Nothing leaves the phone.';

  @override
  String get webAutoHint =>
      'The question goes to DuckDuckGo and result pages are fetched when the message needs it.';

  @override
  String get webAlwaysHint =>
      'Every message is researched first. Slower, always current.';

  @override
  String get knowledgeLibrary => 'Knowledge library';

  @override
  String get knowledgeOff =>
      'Off · your documents, cited in answers when active';

  @override
  String knowledgeOn(Object collection) {
    return 'On · $collection';
  }

  @override
  String get memory => 'Memory';

  @override
  String get memoryOnHint =>
      'On · the assistant learns durable facts about you from chats';

  @override
  String get memoryOffHint => 'Off · nothing is remembered between chats';

  @override
  String get readAloudSetting => 'Read answers aloud';

  @override
  String get readAloudHint =>
      'Every finished answer is spoken with the phone\'s text-to-speech voice. The speaker icon on an answer reads it on demand either way.';

  @override
  String get dictationOnDevice => 'Dictation stays on the phone';

  @override
  String get dictationOnDeviceHint =>
      'Use only the on-device recognizer (needs an offline language pack in the phone\'s speech settings). Off allows the network recognizer.';

  @override
  String get customInstructions => 'Custom system instructions';

  @override
  String get customInstructionsHint => 'Add preferences for your assistant';

  @override
  String get sectionModel => 'Model';

  @override
  String get remoteServer => 'Remote server';

  @override
  String get sectionAdvanced => 'Advanced';

  @override
  String get contextAndBatch => 'Context & batch';

  @override
  String get hardware => 'Hardware';

  @override
  String get sampling => 'Sampling';

  @override
  String get reasoningAndSearch => 'Reasoning & search';

  @override
  String get sectionAbout => 'About';

  @override
  String get openSourceMit => 'Open source · MIT';

  @override
  String get builtOnLlama => 'Built on llama.cpp';

  @override
  String get builtOnLlamaHint => 'Inference engine by the ggml project';

  @override
  String get openSourceLicences => 'Open-source licences';

  @override
  String get openSourceLicencesHint =>
      'Packages, models and voices, with their licences';

  @override
  String get resetQuestion => 'Reset to defaults?';

  @override
  String get resetHint =>
      'All assistant, model and advanced settings return to the defaults for this device. Your chats are not affected.';

  @override
  String get reset => 'Reset';

  @override
  String get enableWebQuestion => 'Enable web search?';

  @override
  String get enableWebHint =>
      'The question is sent to DuckDuckGo and result pages are fetched directly from their websites (they see your IP address). No account or key is used; conversations, model and settings stay local.';

  @override
  String get enable => 'Enable';

  @override
  String get systemInstructions => 'System instructions';

  @override
  String get systemInstructionsHint =>
      'e.g. Answer briefly. Prefer metric units.';

  @override
  String get couldNotOpenLink => 'Could not open this link.';

  @override
  String get privateByDefault => 'Private by default';

  @override
  String get privateByDefaultHint =>
      'No accounts, analytics or cloud inference. Downloads and optional search are the only network features.';

  @override
  String get noModelLoadedTitle => 'No model loaded';

  @override
  String get chooseFromLibrary => 'Choose one from the library';

  @override
  String get obPrivateHeadline => 'Private by construction';

  @override
  String get obPrivateBody =>
      'A language model that runs on your phone’s own chip. There is no server on the other end.';

  @override
  String get obNoAccount => 'No account';

  @override
  String get obNoAccountHint => 'Nothing to sign up for, nothing to log in to.';

  @override
  String get obNoCloud => 'No cloud';

  @override
  String get obNoCloudHint =>
      'Every answer is computed here. Airplane mode works.';

  @override
  String get obStaysHere => 'Models and chats stay on this phone';

  @override
  String get obStaysHereHint => 'Delete the app and every byte goes with it.';

  @override
  String get continueLabel => 'Continue';

  @override
  String get obPickModel => 'Pick a starter model';

  @override
  String get phoneRamUnknown => 'This phone · RAM unknown';

  @override
  String phoneRam(Object gb) {
    return 'This phone · $gb GB RAM';
  }

  @override
  String get recommended => 'Recommended';

  @override
  String get orChooseAnother => 'Or choose another';

  @override
  String get acknowledgeLicense =>
      'I acknowledge the publisher’s model license';

  @override
  String get download => 'Download';

  @override
  String get later => 'Later';

  @override
  String get obReady => 'Ready.';

  @override
  String get startChatting => 'Start chatting';

  @override
  String get downloadInterrupted => 'Download interrupted';

  @override
  String get downloadInterruptedHint =>
      'You can retry now, or skip and download later from the model library. The app works without a model, it just cannot answer yet.';

  @override
  String get retry => 'Retry';

  @override
  String get skipForNow => 'Skip for now';

  @override
  String get verifyingSha => 'Verifying SHA-256…';

  @override
  String pausedOf(Object received, Object size) {
    return 'Paused · $received of $size';
  }

  @override
  String get starting => 'Starting…';

  @override
  String get downloading => 'Downloading';

  @override
  String get downloadingHint =>
      'Keep the app open. You can pause and resume; the file is checked against the publisher’s SHA-256 when it finishes.';

  @override
  String get resume => 'Resume';

  @override
  String get verifying => 'Verifying…';

  @override
  String get pause => 'Pause';

  @override
  String get skip => 'Skip';

  @override
  String get presets => 'Presets';

  @override
  String get newLabel => 'New';

  @override
  String get noExtraInstructions => 'No extra instructions';

  @override
  String get edit => 'Edit';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get delete => 'Delete';

  @override
  String get presetsHint =>
      'A preset adds its instructions to yours and can override temperature, thinking and web mode. Built-ins can be duplicated and edited.';

  @override
  String get newPreset => 'New preset';

  @override
  String get editPreset => 'Edit preset';

  @override
  String get name => 'Name';

  @override
  String get instructions => 'Instructions';

  @override
  String get instructionsHint => 'How should the assistant behave?';

  @override
  String get temperature => 'Temperature';

  @override
  String get useSetting => 'Use setting';

  @override
  String get thinking => 'Thinking';

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get webResearchShort => 'Web research';

  @override
  String get unpin => 'Unpin';

  @override
  String get pinToTop => 'Pin to top';

  @override
  String get rename => 'Rename';

  @override
  String get moveToFolder => 'Move to folder';

  @override
  String get tags => 'Tags';

  @override
  String get renameConversation => 'Rename conversation';

  @override
  String get tagsCommaSeparated => 'Tags (comma-separated)';

  @override
  String get newFolder => 'New folder…';

  @override
  String get removeFromFolder => 'Remove from folder';

  @override
  String get folderName => 'Folder name';

  @override
  String get deleteConversationQuestion => 'Delete conversation?';

  @override
  String get keep => 'Keep';

  @override
  String couldNotDelete(Object error) {
    return 'Could not delete: $error';
  }

  @override
  String get clear => 'Clear';

  @override
  String get all => 'All';

  @override
  String get knowledgeIntro =>
      'Import documents once — PDF, Word, text, code, EPUB… — and every question is answered with the best-matching passages from the active collection, cited like web sources. Retrieval runs entirely on the phone: full-text ranking, plus meaning once the embedding model is downloaded.';

  @override
  String get newCollection => 'New collection';

  @override
  String get useInChats => 'Use in chats';

  @override
  String get collectionOff => 'Off — no collection consulted';

  @override
  String collectionActive(Object collection) {
    return 'Active: $collection';
  }

  @override
  String get readingAndIndexing => 'Reading and indexing…';

  @override
  String get noCollections =>
      'No collections yet. Create one with the folder icon, then add files.';

  @override
  String get addFiles => 'Add files';

  @override
  String get deleteCollection => 'Delete collection';

  @override
  String get searchByMeaning => 'Search by meaning';

  @override
  String get ready => 'Ready';

  @override
  String indexForMeaning(Object count) {
    return 'Index $count passages for meaning';
  }

  @override
  String indexingProgress(Object done, Object total) {
    return 'Indexing for meaning… $done/$total';
  }

  @override
  String downloadMb(Object mb) {
    return 'Download · $mb MB';
  }

  @override
  String get addMemory => 'Add a memory';

  @override
  String get editMemory => 'Edit memory';

  @override
  String get forgetEverything => 'Forget everything';

  @override
  String get forgetEverythingQuestion => 'Forget everything?';

  @override
  String forgetEverythingHint(Object count) {
    return 'All $count remembered facts will be deleted. Chats are not affected.';
  }

  @override
  String get forget => 'Forget';

  @override
  String get rememberAboutMe => 'Remember things about me';

  @override
  String get rememberAboutMeHint =>
      'Remember durable facts you share, such as your job and preferences. Notes are saved on this device. Remote sharing and model extraction require the connection’s opt-in. You can edit or forget notes below.';

  @override
  String get memoryStorageHint =>
      'Notes are stored on this device. Each remote connection needs separate permission to receive or learn them.';

  @override
  String get memoryRemoteLocalHint =>
      'Clear statements such as your job or name can be saved locally when Memory is on. Enable sharing to let this connection use your notes, and learning to extract other durable facts.';

  @override
  String get whatAssistantRemembers => 'What the assistant remembers';

  @override
  String get nothingYetFills => 'Nothing yet. It fills in as you chat.';

  @override
  String get nothingStoredSwitch =>
      'Nothing stored. Turn the switch on, or add facts by hand with +.';

  @override
  String get switchModel => 'Switch model';

  @override
  String get nothingOnPhone => 'Nothing is on this phone yet.';

  @override
  String get modelsOnPhone =>
      'Models on this phone. The active one answers your chats.';

  @override
  String get modelUnloaded =>
      'Model unloaded. It loads again on your next message.';

  @override
  String get unloadModel => 'Unload model · free memory';

  @override
  String get openModelLibrary => 'Open model library';

  @override
  String get active => 'Active';

  @override
  String get pickerEmptyHint =>
      'Download a model from the library, or import a GGUF you already own. Chats need one model loaded; everything stays on this phone.';

  @override
  String get takePhoto => 'Take a photo';

  @override
  String get attachCamera => 'Camera';

  @override
  String get attachFile => 'File';

  @override
  String get attachGoalShort => 'Goal';

  @override
  String get photos => 'Photos';

  @override
  String get photosHint => 'JPEG, PNG, WebP, HEIC…';

  @override
  String get documentOrFile => 'Document or file';

  @override
  String get documentHint =>
      'PDF, Word, PowerPoint, Excel, OpenDocument, EPUB, RTF, text, code, CSV, JSON, HTML…';

  @override
  String couldNotOpenPicker(Object error) {
    return 'Could not open the picker: $error';
  }

  @override
  String get readingAttachments => 'Reading attachments…';

  @override
  String get turnOnWebQuestion => 'Turn on web search?';

  @override
  String get turnOnWebHint =>
      'When you paste a link, ask to search, or a question looks time-sensitive, the question is sent to DuckDuckGo and result pages (three by default, Settings > Reasoning & search) are fetched directly from their websites (they see your IP address). With local inference, everything else stays on this device. If Remote server is enabled, the question and supplied context are also sent to that server.';

  @override
  String get stayLocal => 'Stay local';

  @override
  String get turnOn => 'Turn on';

  @override
  String get compareWithTitle => 'Compare with…';

  @override
  String get compareHint =>
      'The same question and evidence, answered by another model. Shown beside this answer; not part of the conversation.';

  @override
  String shareFailed(Object error) {
    return 'Share failed: $error';
  }

  @override
  String exportFailed(Object error) {
    return 'Export failed: $error';
  }

  @override
  String get dismiss => 'Dismiss';

  @override
  String licenseLabel(Object license) {
    return 'License · $license';
  }

  @override
  String get resumeRetry => 'Resume / retry';

  @override
  String get useModel => 'Use model';

  @override
  String get remove => 'Remove';

  @override
  String get benchmark => 'Benchmark';

  @override
  String visionPercent(Object percent) {
    return 'Vision $percent%';
  }

  @override
  String get verifyingVision => 'Verifying vision…';

  @override
  String get visionReady => 'Vision ready';

  @override
  String addVisionMb(Object mb) {
    return 'Add vision · $mb MB';
  }

  @override
  String get addFromHf => 'Add from Hugging Face';

  @override
  String get importGguf => 'Import a GGUF';

  @override
  String get addFromHfHint =>
      'Paste the link to a public, single GGUF file. Its size, checksum and license will be shown before you download.';

  @override
  String get importGgufHint =>
      'Choose a GGUF you downloaded yourself. It will be copied into your private model library; allow enough space for a second copy.';

  @override
  String get ggufLink => 'GGUF file link';

  @override
  String get templateFallback => 'Template fallback';

  @override
  String get automaticMetadata => 'Automatic (model metadata)';

  @override
  String get ggufWarning =>
      'Text-generation models only. A GGUF may require more RAM than its download size. New architectures and split files may not be supported.';

  @override
  String get checkModel => 'Check model';

  @override
  String get chooseFile => 'Choose file';

  @override
  String get checkingMetadata => 'Checking model metadata…';

  @override
  String downloadQuestion(Object model) {
    return 'Download $model?';
  }

  @override
  String get modelCard => 'Model card';

  @override
  String get removeModelQuestion => 'Remove this model?';

  @override
  String removeModelHint(Object model, Object size) {
    return 'Delete $model from this app and free $size? Your chats will be kept.';
  }

  @override
  String get browseHf => 'Browse Hugging Face';

  @override
  String get yourModelLibrary => 'Your model library';

  @override
  String get libraryHint =>
      'Download a starter model, add a Hugging Face file link, or import a GGUF you already own. After download, inference works offline.';

  @override
  String get searchHf => 'Search Hugging Face';

  @override
  String get pasteLink => 'Paste link';

  @override
  String get importGgufButton => 'Import GGUF';

  @override
  String get checkingCopying => 'Checking and copying model…';

  @override
  String get preparingLibrary => 'Preparing your library…';

  @override
  String get onThisDevice => 'On this device';

  @override
  String get nothingDownloaded =>
      'Nothing downloaded yet. Pick a model below to get started.';

  @override
  String get availableToDownload => 'Available to download';

  @override
  String get everythingOnPhone => 'Everything in the catalog is on this phone.';

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(Object n) {
    return '$n min ago';
  }

  @override
  String hoursAgo(Object n) {
    return '$n h ago';
  }

  @override
  String get webModeOff => 'Off · stays local';

  @override
  String get webModeAuto =>
      'Auto · links, search requests and timely questions';

  @override
  String get webModeAlways => 'Always · research every message';

  @override
  String rememberedOne(Object fact) {
    return 'Remembered: $fact';
  }

  @override
  String rememberedMore(Object fact, Object more) {
    return 'Remembered: $fact (+$more)';
  }

  @override
  String get reviewMemory => 'Review what was remembered';

  @override
  String get memoryDialogTitle => 'Memory';

  @override
  String get memoryDialogHint =>
      'Memory keeps short facts you state about yourself so later chats already know them. It is stored only on this phone and you can change it any time under Settings > Memory. Here is what was just noted — edit it, keep it, or discard it.';

  @override
  String get memoryDialogFieldHint =>
      'One fact per line; empty lines are deleted';

  @override
  String get discard => 'Discard';

  @override
  String get goalDescribeFirst => 'Describe the goal first.';

  @override
  String get goalLimitsInvalid =>
      'Enter positive step, time, token and tool limits.';

  @override
  String get goalsTitle => 'Goals';

  @override
  String get goalIntro =>
      'Give the model a goal. It plans the questions to research, looks each one up, checks the findings against your criteria, fills the gaps, and writes a cited report.';

  @override
  String get goalWebOff =>
      'Web research is off, so the goal can only use what the model already knows. Turn it on with the globe pill in the chat composer for sourced research.';

  @override
  String get goalLabel => 'Goal';

  @override
  String get goalExample =>
      'Compare the three most popular electric cars in Canada for a family of four';

  @override
  String get goalKindTitle => 'Kind of research';

  @override
  String get goalCriteriaLabel => 'What a good result includes (optional)';

  @override
  String get goalBudgetTitle => 'How much work';

  @override
  String get goalMaxSteps => 'Maximum research steps';

  @override
  String get goalMaxMinutes => 'Maximum minutes';

  @override
  String get goalMaxTokens => 'Approximate token budget';

  @override
  String get goalMaxToolCalls => 'Maximum tool calls';

  @override
  String get goalKeepOpen =>
      'Keep the app open: Android may stop it in the background. Progress is saved after every step.';

  @override
  String get goalStart => 'Start goal';

  @override
  String get goalBudgetQuick => 'Quick';

  @override
  String get goalBudgetQuickHint => 'About 4 searches · up to 10 min';

  @override
  String get goalBudgetStandard => 'Standard';

  @override
  String get goalBudgetStandardHint => 'About 8 searches · up to 30 min';

  @override
  String get goalBudgetDeep => 'Deep';

  @override
  String get goalBudgetDeepHint => 'About 14 searches · up to 60 min';

  @override
  String get goalBudgetUnlimited => 'Unlimited';

  @override
  String get goalBudgetUnlimitedHint => 'Until done, paused or stopped';

  @override
  String get goalBudgetCustom => 'Custom';

  @override
  String get goalBudgetCustomHint => 'Set your own limits';

  @override
  String get goalPhasePlanning => 'Planning the research';

  @override
  String get goalPhaseResearching => 'Researching';

  @override
  String get goalPhaseChecking => 'Checking the findings against your criteria';

  @override
  String get goalPhaseWriting => 'Writing the report';

  @override
  String get goalPhaseDone => 'Done';

  @override
  String get goalPaused => 'Paused';

  @override
  String get goalPausedBudget => 'Paused — the budget is used up';

  @override
  String get goalCompleted => 'Completed';

  @override
  String get goalStopped => 'Stopped';

  @override
  String get goalFailed => 'Something went wrong';

  @override
  String get goalReady => 'Ready';

  @override
  String goalStepsOf(int done, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total steps',
      one: '1 step',
    );
    return '$done of $_temp0';
  }

  @override
  String goalSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources',
      one: '1 source',
    );
    return '$_temp0';
  }

  @override
  String get goalTokensWord => 'tokens';

  @override
  String get goalToolCallsWord => 'tool calls';

  @override
  String get goalPauseAfterStep => 'Pause after this step';

  @override
  String get goalStop => 'Stop';

  @override
  String get goalContinue => 'Continue';

  @override
  String get goalOpenChat => 'Open chat';

  @override
  String get goalNew => 'New goal';

  @override
  String get goalHowMade => 'How this report was made';

  @override
  String get goalPastTitle => 'Past goals';

  @override
  String get goalPastReopen => 'Refine or continue';

  @override
  String drawerGoalsPast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count past goals',
      one: '1 past goal',
    );
    return '$_temp0 · Start a new one';
  }

  @override
  String get goalReport => 'Report';

  @override
  String get goalInterimReport => 'Interim report';

  @override
  String get goalCopyReport => 'Copy report';

  @override
  String get goalReportCopied => 'Report copied';

  @override
  String get goalPlan => 'Plan';

  @override
  String get goalNotCovered => 'Not covered by the report';

  @override
  String get goalStillMissing => 'Still missing';

  @override
  String get goalSourcesTitle => 'Sources';

  @override
  String get goalKindGeneral => 'General';

  @override
  String get goalKindGeneralHint => 'Any topic: a balanced, cited report';

  @override
  String get goalKindGeneralCriteria =>
      'The goal answered completely, each claim with a source';

  @override
  String get goalKindCode => 'Code';

  @override
  String get goalKindCodeHint =>
      'APIs, errors, libraries: working code and versions';

  @override
  String get goalKindCodeCriteria =>
      'A working approach with code, the versions it applies to and known pitfalls';

  @override
  String get goalKindScience => 'Scientific';

  @override
  String get goalKindScienceHint =>
      'What the evidence says: studies, consensus, limits';

  @override
  String get goalKindScienceCriteria =>
      'The main findings with study type, year and size, where scientists agree and disagree, and the limitations';

  @override
  String get goalKindMath => 'Math';

  @override
  String get goalKindMathHint => 'Definitions, derivations, checked results';

  @override
  String get goalKindMathCriteria =>
      'The final result, every step of the derivation, and a check of the answer';

  @override
  String get goalKindNews => 'Current events';

  @override
  String get goalKindNewsHint => 'What happened, when, who says what';

  @override
  String get goalKindNewsCriteria =>
      'A dated timeline, the people and organisations involved, their positions, and what comes next';

  @override
  String get goalKindProduct => 'Product comparison';

  @override
  String get goalKindProductHint => 'Options side by side, then a pick';

  @override
  String get goalKindProductCriteria =>
      'Price, key specifications, strengths and weaknesses of each option, and which suits whom';

  @override
  String get drawerGoalsHint => 'Research with a plan and a cited report';

  @override
  String drawerGoalRunning(int step, int total) {
    return 'Running · step $step of $total';
  }

  @override
  String drawerGoalReport(String goal) {
    return 'Report ready · $goal';
  }

  @override
  String get emptyGoalTitle => 'Research a goal';

  @override
  String get emptyGoalHint =>
      'It plans the questions, researches each one and writes a cited report — for code, science, math, news or comparisons.';

  @override
  String get composerResearchGoal => 'Research this as a goal';

  @override
  String get composerManageShortcuts => 'Manage';

  @override
  String get shareNothing => 'Nothing to open in the share.';

  @override
  String get scheduledWaiting => 'Your scheduled prompt is in the message box.';

  @override
  String get shareMore => 'Only the first 8 files were opened.';

  @override
  String shareSkipped(String names) {
    return 'Not opened (empty or over 64 MB): $names';
  }

  @override
  String get attachGoal => 'Research as a goal';

  @override
  String get attachGoalHint => 'A plan, several searches, a cited report';

  @override
  String get batterySaver => 'Battery saver';

  @override
  String get batterySaverOff =>
      'Lighter answers on this phone when the battery is low or it is hot';

  @override
  String batterySaverOn(int level) {
    return 'Below $level% and not charging, or when the phone is hot: no thinking, shorter answers, fewer pages read';
  }

  @override
  String get batterySaverLevel => 'Battery saver starts at';

  @override
  String get scheduleTitle => 'Scheduled prompts';

  @override
  String get scheduleRowHint =>
      'A daily notification that asks a saved prompt when tapped';

  @override
  String get shortcutsTitle => 'Prompt shortcuts';

  @override
  String get shortcutsRowHint =>
      'Type / in a message: /summarize, /translate fr, your own';

  @override
  String get hostTitle => 'Use this device as a server';

  @override
  String get hostRowHint => 'Share a loaded model with another device';

  @override
  String get shortcutNew => 'New shortcut';

  @override
  String get shortcutsIntro =>
      'Type / in the message box to pick one. \"/summarize\" followed by your text sends the saved prompt with the text in it; \"/translate fr …\" takes a language first.';

  @override
  String get shortcutBuiltIn => 'built-in';

  @override
  String shortcutDelete(String name) {
    return 'Delete /$name';
  }

  @override
  String get shortcutNameRule =>
      'Lower-case letters, digits and dashes, up to 24.';

  @override
  String shortcutYourVersion(String name) {
    return 'Your version of /$name';
  }

  @override
  String shortcutEdit(String name) {
    return 'Edit /$name';
  }

  @override
  String get shortcutName => 'Name';

  @override
  String get shortcutDescription => 'Description';

  @override
  String get shortcutPrompt => 'Prompt';

  @override
  String shortcutPromptHelp(String token) {
    return '$token is replaced by the text after the command; without it the text is added at the end.';
  }

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String scheduleFailed(String error) {
    return 'Could not set the reminder: $error';
  }

  @override
  String get scheduleNeedsNotifications =>
      'Allow notifications when Android asks, or the reminder cannot appear.';

  @override
  String get scheduleNew => 'New';

  @override
  String get scheduleIntro =>
      'Once a day at the time you choose, a notification offers the prompt. Tap it and the app asks it in a new chat (or opens it as a goal). Nothing runs in the background and nothing is sent until you tap.';

  @override
  String get scheduleEmpty =>
      'None yet. Try a morning news briefing or a weekly goal.';

  @override
  String get scheduleChat => 'Chat';

  @override
  String get commonDelete => 'Delete';

  @override
  String get scheduleNewTitle => 'New scheduled prompt';

  @override
  String get commonEdit => 'Edit';

  @override
  String scheduleEveryDay(String time) {
    return 'Every day at $time';
  }

  @override
  String get scheduleAskChat => 'Ask in a chat';

  @override
  String get scheduleOpenGoal => 'Open as a goal';

  @override
  String get scheduleExample =>
      'What are the top news stories in Canada today?';

  @override
  String get scheduleNotificationTitle => 'Notification title (optional)';

  @override
  String get hostPortRange => 'Use a number from 1 to 65535.';

  @override
  String get hostPortReserved => 'Ports below 1024 are reserved on Android.';

  @override
  String hostCopied(String what) {
    return '$what copied';
  }

  @override
  String get hostPickModel => 'Model to serve';

  @override
  String get hostPickHint =>
      'Loading takes a few seconds. A running server restarts with the new model; connected devices keep the same address and token.';

  @override
  String get hostChangeModel => 'Change';

  @override
  String get hostManageModels => 'Download or import models';

  @override
  String get hostModel => 'Model';

  @override
  String get hostNoModel => 'No model loaded';

  @override
  String get hostLoadFirst => 'Choose a model to serve.';

  @override
  String get hostModelHint =>
      'Other devices chat with this model while the server runs.';

  @override
  String get hostConnection => 'Connection';

  @override
  String get hostPort => 'Port';

  @override
  String get hostPortHint => 'The other device connects to this port.';

  @override
  String get hostStarting => 'Starting…';

  @override
  String get hostStart => 'Start server';

  @override
  String get hostToken => 'Access token';

  @override
  String get hostRotate => 'Rotate access token';

  @override
  String get hostRotateHint =>
      'Devices using the current token must reconnect with the new one.';

  @override
  String get hostRotated => 'A new token is used on the next start.';

  @override
  String get hostWaiting => 'Serving · waiting for requests';

  @override
  String hostAnswering(String client) {
    return 'Answering $client';
  }

  @override
  String hostUp(String duration) {
    return 'up $duration';
  }

  @override
  String get hostLive => 'Live';

  @override
  String get hostAnswered => 'answered';

  @override
  String get hostRefused => 'refused';

  @override
  String get hostFailed => 'failed';

  @override
  String get hostTokensIn => 'tokens in';

  @override
  String get hostTokensOut => 'tokens out';

  @override
  String get hostAvgSpeed => 'avg speed';

  @override
  String get hostDevices => 'devices';

  @override
  String get hostBattery => 'battery';

  @override
  String get hostHeat => 'heat';

  @override
  String get hostLowBattery => 'Stop on low battery';

  @override
  String get hostLowBatteryHint =>
      'The server also stops when the phone reports severe heat. The screen stays on while it runs.';

  @override
  String get commonOff => 'Off';

  @override
  String get hostConnect => 'Connect another device';

  @override
  String get hostServerUrl => 'Server URL';

  @override
  String get hostModelId => 'Model ID';

  @override
  String get hostHideToken => 'Hide token';

  @override
  String get hostShowToken => 'Show token';

  @override
  String get hostCopyConnection => 'Copy connection';

  @override
  String get hostPairHint =>
      'On the other phone: scan this code with the camera and copy the text, or paste the copied connection, then in OnDevice LLM open Settings > Remote server > Add > Paste connection. Any OpenAI-compatible app works too, with the URL, model and token.';

  @override
  String get hostRecent => 'Recent requests';

  @override
  String get hostNoneYet => 'None yet.';

  @override
  String hostCopy(String what) {
    return 'Copy $what';
  }

  @override
  String hostInOut(int prompt, int completion) {
    return '$prompt in · $completion out';
  }

  @override
  String get remotePasteNone =>
      'The clipboard has no connection. On the other phone, tap Copy connection (or scan its QR code) first.';

  @override
  String remotePasted(String name) {
    return 'Added $name. Turn on Use remote server to chat with it.';
  }

  @override
  String get remotePaste => 'Paste connection';

  @override
  String get remoteAdd => 'Add connection';

  @override
  String get configCopied => 'Configuration copied as text';

  @override
  String get configTooLarge => 'That file is too large to be a configuration.';

  @override
  String get configNotAFile =>
      'That file is not an OnDevice LLM model configuration.';

  @override
  String get configNotInClipboard =>
      'The clipboard has no model configuration. Copy one first.';

  @override
  String configMadeFor(String model) {
    return 'Made for $model';
  }

  @override
  String get configNotDownloaded =>
      'This model is in the catalog but not downloaded: get it from Models, or apply to one you have.';

  @override
  String get configNotOnPhone =>
      'This model is not on this phone. Apply the settings to one you have:';

  @override
  String configSameModel(String model) {
    return '$model (same model)';
  }

  @override
  String get configEmpty =>
      'The card sets nothing: the model would run on your own settings.';

  @override
  String configLeftOut(String keys) {
    return 'Left out (web access, phone hardware, context size or unknown): $keys';
  }

  @override
  String get configApply => 'Apply';

  @override
  String get hostShowQr => 'Show pairing code';

  @override
  String get voiceConversation => 'Voice conversation';

  @override
  String get chatPinModel => 'Pin a model to this chat';

  @override
  String get chatPinHint =>
      'This chat always answers with the pinned model, whatever the model picker says.';

  @override
  String get chatPinNone => 'No pin: use the selected model';

  @override
  String chatPinned(String model) {
    return '📌 $model';
  }

  @override
  String get readerSummarize => 'Summarize article';

  @override
  String get readerKeyPoints => 'Key points';

  @override
  String get readerExplain => 'Explain simply';

  @override
  String readerSummarizePrompt(String url) {
    return 'Read this article and summarize it in a few short paragraphs, keeping names, figures and dates exact, and cite it: $url';
  }

  @override
  String readerKeyPointsPrompt(String url) {
    return 'Read this article and list its key points as short bullets, citing it: $url';
  }

  @override
  String readerExplainPrompt(String url) {
    return 'Read this article and explain what it says in plain language for someone new to the topic, citing it: $url';
  }

  @override
  String get readerNeedsWeb =>
      'Reading a link needs web research: turn it on with the globe pill.';

  @override
  String get saveToKnowledge => 'Save to knowledge';

  @override
  String get knowledgeSaveHint =>
      'Choose a collection and the messages to save. Only visible message text and its source links are included; private reasoning stays out.';

  @override
  String get knowledgeCollectionName => 'Collection name';

  @override
  String get knowledgeDocumentTitle => 'Document title';

  @override
  String get knowledgeSelectMessages => 'Messages to save';

  @override
  String get knowledgeChatTitle => 'Saved conversation';

  @override
  String get knowledgeNameRequired =>
      'Enter a collection name and document title.';

  @override
  String knowledgeSaved(String collection) {
    return 'Saved to $collection.';
  }

  @override
  String knowledgeSaveFailed(String error) {
    return 'Could not save to knowledge: $error';
  }

  @override
  String get you => 'You';

  @override
  String get assistant => 'Assistant';

  @override
  String get backupPasswordTooShort =>
      'Use at least 12 characters for the backup password.';

  @override
  String get backupPasswordsMismatch => 'The passwords do not match.';

  @override
  String get backupSaveDialog => 'Save encrypted backup';

  @override
  String get backupSaveCancelled => 'Save cancelled.';

  @override
  String get backupSavedNotice =>
      'Encrypted backup saved. Keep the password safe; it cannot be recovered.';

  @override
  String backupFailedNotice(String error) {
    return 'Backup failed: $error';
  }

  @override
  String get backupEnterPassword => 'Enter the backup password.';

  @override
  String get backupReplaceQuestion => 'Replace this device’s library?';

  @override
  String get backupReplaceHint =>
      'Restoring replaces chats, knowledge, attachments, and app settings the next time the app starts. Local model files and saved API keys are not included in the backup.';

  @override
  String get backupRestoreAction => 'Restore';

  @override
  String get backupTooLarge => 'Backup exceeds the safety limit.';

  @override
  String get backupVerifiedNotice =>
      'Backup verified. Fully close and reopen the app to apply the restore.';

  @override
  String backupRestoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get backupTitle => 'Encrypted backup';

  @override
  String get backupIntro =>
      'Back up chats, knowledge, attachments, Goals, and settings to a password-protected file. Model weights and saved API keys stay on this device. The backup limit is 96 MB.';

  @override
  String get backupPasswordLabel => 'Backup password';

  @override
  String get backupConfirmPassword => 'Confirm password for a new backup';

  @override
  String get backupCreateAction => 'Create encrypted backup';

  @override
  String get backupRestoreBackup => 'Restore backup';

  @override
  String get uiRemoteProfilePageDeleteConnection => 'Delete connection?';

  @override
  String get uiRemoteProfilePageCancel => 'Cancel';

  @override
  String get uiRemoteProfilePageDelete => 'Delete';

  @override
  String get uiRemoteProfilePageConnection => 'Connection';

  @override
  String get uiRemoteProfilePageThisConnectionWasRemoved =>
      'This connection was removed.';

  @override
  String get uiRemoteProfilePageDeleteConnection2 => 'Delete connection';

  @override
  String get uiRemoteProfilePageProvider => 'Provider';

  @override
  String get uiRemoteProfilePageName => 'Name';

  @override
  String get uiRemoteProfilePageServerURL => 'Server URL';

  @override
  String get uiRemoteProfilePageGetAKeyInTheBrowser =>
      'Get a key in the browser';

  @override
  String get uiRemoteProfilePageModel => 'Model';

  @override
  String get uiRemoteProfilePageModelsOnTheServer => 'Models on the server';

  @override
  String get uiRemoteProfilePageRequestsPerMinute => 'Requests per minute';

  @override
  String get uiRemoteProfilePageNone => 'none';

  @override
  String get uiRemoteProfilePageRequestsPerDay => 'Requests per day';

  @override
  String get uiRemoteProfilePageExtraHeaders => 'Extra headers';

  @override
  String get uiAdvancedPagesContextBatch => 'Context & batch';

  @override
  String get uiAdvancedPagesContextSize => 'Context size';

  @override
  String get uiAdvancedPagesTokensTheModelCanSeeAt =>
      'Tokens the model can see at once: the conversation, web evidence and the answer. Memory grows with it; if the phone cannot hold it, the model loads with a shorter context and a note says so.';

  @override
  String get uiAdvancedPagesContextSizeTokens => 'Context size (tokens)';

  @override
  String get uiAdvancedPagesBatchSize => 'Batch size';

  @override
  String get uiAdvancedPagesPromptTokensSubmittedPerStepAuto =>
      'Prompt tokens submitted per step. Auto is 512, the measured optimum on this phone; larger mostly helps GPU prefill of long prompts.';

  @override
  String get uiAdvancedPagesMicroBatch => 'Micro-batch';

  @override
  String get uiAdvancedPagesTokensPerComputeStepWithinA =>
      'Tokens per compute step within a batch. Auto matches the batch size. Never above the batch size.';

  @override
  String get uiAdvancedPagesKeepConversationInContext =>
      'Keep conversation in context';

  @override
  String get uiAdvancedPagesOnlyNewTextIsEvaluatedOn =>
      'Only new text is evaluated on each turn; earlier turns stay resident. Off re-reads the whole conversation every message.';

  @override
  String get uiAdvancedPagesHardware => 'Hardware';

  @override
  String get uiAdvancedPagesBackend => 'Backend';

  @override
  String get uiAdvancedPagesAutomaticUsesCPUOpenCL2Faster =>
      'Automatic uses CPU. OpenCL: ~2× faster prompt reading for research, ~15 % slower answers; the model reloads when you change it.';

  @override
  String get uiAdvancedPagesGPULayers => 'GPU layers';

  @override
  String get uiAdvancedPagesLayersOffloadedToTheGPUIgnored =>
      'Layers offloaded to the GPU. Ignored when the backend is CPU only.';

  @override
  String get uiAdvancedPagesCPUThreadsDecode => 'CPU threads (decode)';

  @override
  String get uiAdvancedPagesWorkerThreadsWhileTheAnswerStreams =>
      'Worker threads while the answer streams. Auto uses 6 on 8-core phones (measured fastest), otherwise half the cores.';

  @override
  String get uiAdvancedPagesCPUThreadsPrefill => 'CPU threads (prefill)';

  @override
  String get uiAdvancedPagesThreadsWhileThePromptIsRead =>
      'Threads while the prompt is read. Auto uses every core: prefill kept speeding up to 8 threads where decode slowed down.';

  @override
  String get uiAdvancedPagesFlashAttention => 'Flash attention';

  @override
  String get uiAdvancedPagesFasterAttentionKernelWithLowerMemory =>
      'Faster attention kernel with lower memory use.';

  @override
  String get uiAdvancedPagesKVCache => 'KV cache';

  @override
  String get uiAdvancedPagesPrecisionOfCachedAttentionState =>
      'Precision of cached attention state';

  @override
  String get uiAdvancedPagesSampling => 'Sampling';

  @override
  String get uiAdvancedPagesTemperature => 'Temperature';

  @override
  String get uiAdvancedPagesRandomnessLowerIsMoreFocusedHigher =>
      'Randomness. Lower is more focused, higher is more varied.';

  @override
  String get uiAdvancedPagesTopP => 'Top-P';

  @override
  String get uiAdvancedPagesSampleFromTheSmallestSetOf =>
      'Sample from the smallest set of tokens whose probability adds up to P.';

  @override
  String get uiAdvancedPagesMinP => 'Min-P';

  @override
  String get uiAdvancedPagesDropTokensLessLikelyThanThis =>
      'Drop tokens less likely than this fraction of the top token.';

  @override
  String get uiAdvancedPagesTopK => 'Top-K';

  @override
  String get uiAdvancedPagesOnlyTheKMostLikelyTokens =>
      'Only the K most likely tokens are considered. 0 disables.';

  @override
  String get uiAdvancedPagesRepetitionPenalty => 'Repetition penalty';

  @override
  String get uiAdvancedPagesDiscouragesRepeatingRecentTokens100 =>
      'Discourages repeating recent tokens. 1.00 is off.';

  @override
  String get uiAdvancedPagesMaxTokens => 'Max tokens';

  @override
  String get uiAdvancedPagesUpperBoundOnOneResponseReasoning =>
      'Upper bound on one response, reasoning included. It is reserved inside the context, so it must fit alongside the prompt.';

  @override
  String get uiAdvancedPagesMaxTokensPerResponse => 'Max tokens per response';

  @override
  String get uiAdvancedPagesReasoningSearch => 'Reasoning & search';

  @override
  String get uiAdvancedPagesThinkingMode => 'Thinking mode';

  @override
  String get uiAdvancedPagesShowModelGeneratedReasoningWhenSupported =>
      'Show model-generated reasoning when supported. It may contain mistakes and is not proof of correctness.';

  @override
  String get uiAdvancedPagesThinkingBudget => 'Thinking budget';

  @override
  String get uiAdvancedPagesReasoningTokensAllowedBeforeTheBlock =>
      'Reasoning tokens allowed before the block is closed and the answer starts. Bounds the wait on hard questions; unlimited lets the model decide.';

  @override
  String get uiAdvancedPagesThinkingBudgetTokens0Unlimited =>
      'Thinking budget (tokens, 0 = unlimited)';

  @override
  String get uiAdvancedPagesSearchAndNewsRegion => 'Search and news region';

  @override
  String get uiAdvancedPagesSearchResults => 'Search results';

  @override
  String get uiAdvancedPagesCandidatesTakenFromDuckDuckGoPerQuery =>
      'Candidates taken from DuckDuckGo per query.';

  @override
  String get uiAdvancedPagesPagesToRead => 'Pages to read';

  @override
  String get uiAdvancedPagesResultPagesFetchedAndRankedFor =>
      'Result pages fetched and ranked for evidence. Unreadable pages are skipped for the next candidate. More is slower and uses more context.';

  @override
  String get uiAdvancedPagesResearchTimeBudget => 'Research time budget';

  @override
  String get uiAdvancedPagesWallClockLimitForReadingAll =>
      'Wall-clock limit for reading all pages of one question. Slow sites are cut at the limit and the answer proceeds with what was read.';

  @override
  String get uiAdvancedPagesModelDrivenResearchExperimental =>
      'Model-driven research (experimental)';

  @override
  String get uiAdvancedPagesModelWritesTheSearchQueries =>
      'Model writes the search queries';

  @override
  String get uiAdvancedPagesTheLocalModelTurnsYourQuestion =>
      'The local model turns your question into one or two search-engine queries before searching. Costs a few seconds; off sends the question as typed.';

  @override
  String get uiAdvancedPagesPassagesGivenToTheModel =>
      'Passages given to the model';

  @override
  String get uiAdvancedPagesBestMatchingPassagesAbout250Tokens =>
      'Best-matching passages (about 250 tokens each) across all read pages. More evidence, longer prefill.';

  @override
  String get uiAdvancedPagesFlagUnsupportedFigures =>
      'Flag unsupported figures';

  @override
  String get uiAdvancedPagesAfterAGroundedAnswerNumbersVersions =>
      'After a grounded answer, numbers, versions and dates that appear in no supplied passage are called out as unverified.';

  @override
  String get supportCheckTitle => 'Check sentences by meaning';

  @override
  String get supportCheckHint =>
      'A small model (Qwen3 Reranker 0.6B) reads the closest source passage before a sentence is flagged, so a correct sentence in other words is not called unsupported. A separate download; it runs for a few seconds after an answer from sources.';

  @override
  String get uiHfSearchPageSearchHuggingFace => 'Search Hugging Face';

  @override
  String get uiHfSearchPageModelNameEGQwen34B =>
      'Model name, e.g. Qwen3 4B, Phi-4, Llama 3.2';

  @override
  String get uiHfSearchPageNoGGUFRepositoriesMatch =>
      'No GGUF repositories match.';

  @override
  String get uiHfSearchPageNoSingleFileGGUFWeightsIn =>
      'No single-file GGUF weights in this repository.';

  @override
  String get uiHfSearchPageNotAddableHere => 'Not addable here';

  @override
  String get uiBenchmarkDialogBenchmarkCopied => 'Benchmark copied';

  @override
  String get uiBenchmarkDialogCopy => 'Copy';

  @override
  String get uiBenchmarkDialogShare => 'Share';

  @override
  String get uiBenchmarkDialogDone => 'Done';

  @override
  String get uiModelReadinessPageModelReadiness => 'Model readiness';

  @override
  String get uiModelReadinessPageDeviceCapacity => 'Device capacity';

  @override
  String get uiModelReadinessPagePhysicalRAM => 'Physical RAM';

  @override
  String get uiModelReadinessPageModelStorageVolume => 'Model storage volume';

  @override
  String get uiModelReadinessPageInstalledModelWeights =>
      'Installed model weights';

  @override
  String get uiModelReadinessPageCurrentContextAndBackend =>
      'Current context and backend';

  @override
  String get uiModelReadinessPageModels => 'Models';

  @override
  String get uiModelReadinessPageRAMFitIsARoughEstimate =>
      'RAM fit is a rough estimate. Actual context memory and speed depend on the model, backend, and device temperature.';

  @override
  String get uiToolsQuickPanelLetTheModelCallTools =>
      'Let the model call tools';

  @override
  String get uiToolsQuickPanelTHISMODELMAYCALL => 'This model may call';

  @override
  String get uiToolsQuickPanelCalculator => 'calculator';

  @override
  String get uiToolsQuickPanelExactArithmetic => 'Exact arithmetic.';

  @override
  String get uiToolsQuickPanelSearchWebReadUrlFindIn =>
      'search_web · read_url · find_in_page';

  @override
  String get uiToolsQuickPanelSearchDocuments => 'search_documents';

  @override
  String get uiToolsQuickPanelToolUse => 'Tool use';

  @override
  String get uiToolsQuickPanelAuto => 'Auto';

  @override
  String get uiToolsQuickPanelRequired => 'Required';

  @override
  String get uiAdvancedAdaptersPageLoRAAdapters => 'LoRA adapters';

  @override
  String get uiAdvancedAdaptersPageImportAdapter => 'Import adapter';

  @override
  String get uiAdvancedAdaptersPageDelete => 'Delete';

  @override
  String get uiAdvancedAppearancePageAppearance => 'Appearance';

  @override
  String get uiAdvancedAppearancePageTheme => 'Theme';

  @override
  String get uiAdvancedAppearancePageDarkIsTheDesignedDefaultLight =>
      'Dark is the designed default; light follows the phone if you choose System.';

  @override
  String get uiAdvancedAppearancePageAccentColour => 'Accent colour';

  @override
  String get uiAdvancedAppearancePageTextSize => 'Text size';

  @override
  String get uiAdvancedAppearancePageCompactBubbles => 'Compact bubbles';

  @override
  String get uiAdvancedAppearancePageTighterSpacingInTheConversation =>
      'Tighter spacing in the conversation.';

  @override
  String get motionLabel => 'Motion';

  @override
  String get motionHint =>
      'Springs, morphing controls and soft blurs. Your phone\'s Remove animations setting turns motion off.';

  @override
  String get motionFull => 'Full';

  @override
  String get motionSubtle => 'Subtle';

  @override
  String get motionOff => 'Off';

  @override
  String islandLoadingModel(String model) {
    return 'Loading $model';
  }

  @override
  String get islandModelReady => 'Model ready';

  @override
  String get islandResearchDone => 'Research done';

  @override
  String get islandAnswered => 'Answered';

  @override
  String get jumpToLatest => 'Jump to the latest message';

  @override
  String get uiAdvancedMemoryRopePageMemoryRoPESpeculation =>
      'Memory, RoPE & speculation';

  @override
  String get uiAdvancedMemoryRopePageKCache => 'K cache';

  @override
  String get uiAdvancedMemoryRopePagePrecisionOfCachedKeys =>
      'Precision of cached keys';

  @override
  String get uiAdvancedMemoryRopePageVCache => 'V cache';

  @override
  String get uiAdvancedMemoryRopePagePrecisionOfCachedValuesQuantisingV =>
      'Precision of cached values. Quantising V needs flash attention, which is enabled automatically.';

  @override
  String get uiAdvancedMemoryRopePageRoPEScaling => 'RoPE scaling';

  @override
  String get uiAdvancedMemoryRopePageHowPositionsBeyondTheTrainedContext =>
      'How positions beyond the trained context are stretched. \"Model\" keeps what the GGUF declares; YaRN is the usual choice for longer contexts on models that support it.';

  @override
  String get uiAdvancedMemoryRopePageRoPEFrequencyBase => 'RoPE frequency base';

  @override
  String get uiAdvancedMemoryRopePageEG1000000ForModelsThat =>
      'e.g. 1000000 for models that document it';

  @override
  String get uiAdvancedMemoryRopePageRoPEFrequencyScale =>
      'RoPE frequency scale';

  @override
  String get uiAdvancedMemoryRopePage0Scale1EG0 =>
      '0 < scale ≤ 1, e.g. 0.25 for 4× the trained context';

  @override
  String get uiAdvancedMemoryRopePageYaRNOriginalContext =>
      'YaRN original context';

  @override
  String get uiAdvancedMemoryRopePageTheContextTheModelWasTrained =>
      'The context the model was trained for';

  @override
  String get uiAdvancedMemoryRopePageYaRNExtrapolationMix =>
      'YaRN extrapolation mix';

  @override
  String get uiAdvancedMemoryRopePage0InterpolationOnly1FullExtrapolation =>
      '0 = interpolation only, 1 = full extrapolation';

  @override
  String get uiAdvancedMemoryRopePageYaRNAttentionFactor =>
      'YaRN attention factor';

  @override
  String get uiAdvancedMemoryRopePageMagnitudeScalingUsually10 =>
      'Magnitude scaling, usually 1.0';

  @override
  String get uiAdvancedMemoryRopePageYaRNBetaFast => 'YaRN beta fast';

  @override
  String get uiAdvancedMemoryRopePageLowCorrectionDimension =>
      'Low correction dimension';

  @override
  String get uiAdvancedMemoryRopePageYaRNBetaSlow => 'YaRN beta slow';

  @override
  String get uiAdvancedMemoryRopePageHighCorrectionDimension =>
      'High correction dimension';

  @override
  String get uiAdvancedMemoryRopePageDraftModel => 'Draft model';

  @override
  String get uiAdvancedMemoryRopePageASmallerModelWithTheSame =>
      'A smaller model with the same vocabulary proposes several tokens; the main model verifies them in one pass. Helps on long, predictable answers; measure it — it costs memory and can be slower.';

  @override
  String get uiAdvancedMemoryRopePageDraftTokensPerRound =>
      'Draft tokens per round';

  @override
  String get uiAdvancedMemoryRopePageHowManyTokensTheDraftProposes =>
      'How many tokens the draft proposes before verification. Higher wins more when the draft is right and wastes more when it is wrong.';

  @override
  String get uiAdvancedPages2Cancel => 'Cancel';

  @override
  String get uiAdvancedPages2NotAValidValue => 'Not a valid value.';

  @override
  String get uiAdvancedPages2Save => 'Save';

  @override
  String get uiAdvancedSamplingPageMoreSampling => 'More sampling';

  @override
  String get uiAdvancedSamplingPageSeed => 'Seed';

  @override
  String get uiAdvancedSamplingPageSeed0Random => 'Seed (0 = random)';

  @override
  String get uiAdvancedSamplingPageStopSequences => 'Stop sequences';

  @override
  String get uiAdvancedSamplingPagePresencePenalty => 'Presence penalty';

  @override
  String get uiAdvancedSamplingPageOnceATokenHasAppearedIt =>
      'Once a token has appeared it is discouraged, regardless of how often. 0 is off; negatives encourage reuse.';

  @override
  String get uiAdvancedSamplingPageFrequencyPenalty => 'Frequency penalty';

  @override
  String get uiAdvancedSamplingPageEachRepetitionAddsToThePenalty =>
      'Each repetition adds to the penalty. 0 is off.';

  @override
  String get uiAdvancedSamplingPagePenaltyWindow => 'Penalty window';

  @override
  String get uiAdvancedSamplingPageHowManyRecentTokensTheRepetition =>
      'How many recent tokens the repetition, presence and frequency penalties look at. 0 turns them off.';

  @override
  String get uiAdvancedSamplingPageDRYMultiplier => 'DRY multiplier';

  @override
  String get uiAdvancedSamplingPageDRYPenalisesRepeatingWholeSequencesRather =>
      'DRY penalises repeating whole sequences rather than single tokens. 0 is off; 0.8 is the usual strength.';

  @override
  String get uiAdvancedSamplingPageDRYBase => 'DRY base';

  @override
  String get uiAdvancedSamplingPageGrowthOfThePenaltyWithThe =>
      'Growth of the penalty with the repeated length.';

  @override
  String get uiAdvancedSamplingPageDRYAllowedLength => 'DRY allowed length';

  @override
  String get uiAdvancedSamplingPageRepeatsShorterThanThisAreFree =>
      'Repeats shorter than this are free.';

  @override
  String get uiAdvancedSamplingPageTypicalP => 'Typical-P';

  @override
  String get uiAdvancedSamplingPageKeepsTokensWhoseSurpriseIsClose =>
      'Keeps tokens whose surprise is close to the expected one. 1.00 is off.';

  @override
  String get uiAdvancedSamplingPageXTCProbability => 'XTC probability';

  @override
  String get uiAdvancedSamplingPageWithThisProbabilityTheMostLikely =>
      'With this probability the most likely tokens above the threshold are removed, except the last one — for more varied prose. 0 is off.';

  @override
  String get uiAdvancedSamplingPageXTCThreshold => 'XTC threshold';

  @override
  String get uiAdvancedSamplingPageTokensAboveThisProbabilityAreCandidates =>
      'Tokens above this probability are candidates for removal.';

  @override
  String get uiAdvancedSamplingPageTopNSigma => 'Top-n-sigma';

  @override
  String get uiAdvancedSamplingPageKeepsTokensWithinNStandardDeviations =>
      'Keeps tokens within n standard deviations of the best logit; works well with high temperatures. Off at 0.';

  @override
  String get uiAdvancedSamplingPageResetOrder => 'Reset order';

  @override
  String get uiAdvancedSamplingPageOnePerLineUpTo8 =>
      'One per line, up to 8. The answer ends when one appears; it is never shown.';

  @override
  String get uiAdvancedSamplingPageCancel => 'Cancel';

  @override
  String get uiAdvancedSamplingPageSave => 'Save';

  @override
  String get uiAdvancedStructuredOutputPageStructuredOutput =>
      'Structured output';

  @override
  String get uiAdvancedStructuredOutputPageResponseFormat => 'Response format';

  @override
  String
  get uiAdvancedStructuredOutputPageConstrainsEveryTokenTheModelProduces =>
      'Constrains every token the model produces. Thinking is turned off for constrained answers, and tools are not offered.';

  @override
  String get uiAdvancedStructuredOutputPageJSONSchema => 'JSON schema';

  @override
  String get uiAdvancedStructuredOutputPageGBNFGrammar => 'GBNF grammar';

  @override
  String get uiAdvancedStructuredOutputPageCancel => 'Cancel';

  @override
  String get uiAdvancedStructuredOutputPageSave => 'Save';

  @override
  String get uiAdvancedToolsPageTools => 'Tools';

  @override
  String get uiAdvancedToolsPageLetTheModelCallTools =>
      'Let the model call tools';

  @override
  String get uiAdvancedToolsPageTheModelCanDecideToSearch =>
      'The model can decide to search the web, read a page, search your documents or calculate, then answer from the results. Each tool stays behind its own permission below.';

  @override
  String get uiAdvancedToolsPageToolUse => 'Tool use';

  @override
  String get uiAdvancedToolsPageAutoLetsTheModelDecideWhether =>
      'Auto lets the model decide whether a tool is needed. Required makes it call one before its first answer (later rounds are up to it again): use it when the model keeps answering from memory instead of searching.';

  @override
  String get uiAdvancedToolsPageRoundsPerAnswer => 'Rounds per answer';

  @override
  String get uiAdvancedToolsPageHowManyTimesTheModelMay =>
      'How many times the model may call tools before it must answer. Each round is another model pass.';

  @override
  String get uiAdvancedToolsPageCalculator => 'calculator';

  @override
  String get uiAdvancedToolsPageExactArithmeticNoPermissionNeeded =>
      'Exact arithmetic. No permission needed.';

  @override
  String get uiAdvancedToolsPageSearchWebReadUrlFindIn =>
      'search_web · read_url · find_in_page';

  @override
  String get uiAdvancedToolsPageSearchDocuments => 'search_documents';

  @override
  String get uiEffectiveSettingsPageEffectiveSettings => 'Effective settings';

  @override
  String get uiEffectiveSettingsPageAppliesWhenTheModelLoads =>
      'Applies when the model loads.';

  @override
  String get uiEffectiveSettingsPageClose => 'Close';

  @override
  String get uiKnowledgePageOK => 'OK';

  @override
  String get uiKnowledgePageVerifying => 'Verifying…';

  @override
  String get uiMemoryPageEGTheUserIsA =>
      'e.g. The user is a nurse in Lisbon and prefers metric units.';

  @override
  String get uiOverridesPageClearAll => 'Clear all';

  @override
  String get uiOverridesPageInherit => 'Inherit';

  @override
  String get uiOverridesPageOn => 'On';

  @override
  String get uiOverridesPageOff => 'Off';

  @override
  String get uiOverridesPageCancel => 'Cancel';

  @override
  String get uiOverridesPageNotAValidValue => 'Not a valid value.';

  @override
  String get uiOverridesPageSave => 'Save';

  @override
  String get uiRemoteServerPageUseRemoteServer => 'Use remote server';

  @override
  String get uiRemoteServerPageNoConnectionsYet => 'No connections yet';

  @override
  String get uiRemoteServerPageAddOneToChooseAProvider =>
      'Add one to choose a provider, URL, API key and model.';

  @override
  String get uiRemoteServerPageEditConnection => 'Edit connection';

  @override
  String get uiRemoteServerPageWebResearch => 'Web research';

  @override
  String get uiRemoteServerPageTheAppSearchesDuckDuckGoAndReads =>
      'The remote model decides whether a question needs the web, writes its own searches and picks the pages to read; the app runs them on DuckDuckGo and Wikipedia without a key.';

  @override
  String get uiRemoteServerPageImageUnderstanding => 'Image understanding';

  @override
  String get uiRemoteServerPageSendAttachedImagesToTheModel =>
      'Send attached images to the model. Enable only for a vision-capable model.';

  @override
  String get uiRemoteServerPageDocumentUnderstanding =>
      'Document understanding';

  @override
  String get uiRemoteServerPageExtractDocumentsSafelyOnThePhone =>
      'Extract documents safely on the phone, then send their text in the prompt. Original files are not uploaded.';

  @override
  String get uiRemoteServerPageStreamingIdleTimeout => 'Streaming idle timeout';

  @override
  String get uiRemoteServerPageHowLongToWaitBetweenResponse =>
      'How long to wait between response chunks from a slow or heavily loaded server.';

  @override
  String get uiRemoteServerPageChooseAProvider => 'Choose a provider';

  @override
  String get uiSettingsScreenEncryptedBackup => 'Encrypted backup';

  @override
  String get uiSettingsScreenMoreSampling => 'More sampling';

  @override
  String get uiSettingsScreenMemoryRoPESpeculation =>
      'Memory, RoPE & speculation';

  @override
  String get uiSettingsScreenStructuredOutput => 'Structured output';

  @override
  String get uiSettingsScreenTools => 'Tools';

  @override
  String get uiSettingsScreenLoRAAdapters => 'LoRA adapters';

  @override
  String get uiSettingsScreenEffectiveSettings => 'Effective settings';

  @override
  String get uiSettingsScreenAppearance => 'Appearance';

  @override
  String get uiMetricsSheetInstrumentPanel => 'Instrument panel';

  @override
  String get uiMetricsSheetDisplay => 'Display';

  @override
  String get uiMetricsSheetBenchmarkThisModel => 'Benchmark this model';

  @override
  String get uiMetricsSheetMeasuredOnThisDeviceNothingIs =>
      'Measured on this device. Nothing is transmitted.';

  @override
  String get uiMetricsSheetSendAMessageToSeeLive =>
      'Send a message to see live numbers.';

  @override
  String get uiMetricsSheetBackend => 'Backend';

  @override
  String get uiMetricsSheetNativeLibrary => 'Native library';

  @override
  String get uiMetricsSheetStages => 'Stages';

  @override
  String get uiMetricsSheetTokensSec => 'Tokens/sec';

  @override
  String get uiMetricsSheetFirstToken => 'First token';

  @override
  String get uiMetricsSheetTokens => 'Tokens';

  @override
  String get uiMetricsSheetContext => 'Context';

  @override
  String get uiMetricsSheetPeakRSS => 'Peak RSS';

  @override
  String get uiMetricsSheetTemplate => 'Template';

  @override
  String get uiMetricsSheetThinking => 'Thinking';

  @override
  String get uiMetricsSheetModel => 'Model';

  @override
  String get uiSettingsWidgetsCancel => 'Cancel';

  @override
  String get uiSettingsWidgetsApply => 'Apply';

  @override
  String get uiPresetSheet00Exact => '0.0 · exact';

  @override
  String get uiPresetSheet03Focused => '0.3 · focused';

  @override
  String get uiPresetSheet07Balanced => '0.7 · balanced';

  @override
  String get uiPresetSheet10Creative => '1.0 · creative';

  @override
  String get uiModelsScreenHttpsHuggingfaceCo => 'https://huggingface.co/…';

  @override
  String get uiModelsScreenModelReadiness => 'Model readiness';

  @override
  String get uiModelsScreenImportConfiguration => 'Import configuration';

  @override
  String get uiModelsScreenImportConfigurationFromClipboard =>
      'Import configuration from clipboard';

  @override
  String get uiModelsScreenImportConfigurationFromAFile =>
      'Import configuration from a file';

  @override
  String get uiModelsScreenShareOrImportAConfiguration =>
      'Share or import a configuration';

  @override
  String get uiModelsScreenShareConfiguration => 'Share configuration';

  @override
  String get uiModelsScreenCopyAsText => 'Copy as text';

  @override
  String get uiModelsScreenImportFromClipboard => 'Import from clipboard';

  @override
  String get uiModelsScreenImportFromAFile => 'Import from a file';

  @override
  String get uiModelCardRemoveFromList => 'Remove from list';

  @override
  String get uiModelPickerSheetRemoteConnections => 'Remote connections';

  @override
  String get uiModelPickerSheetAnswersComeFromTheConnectionInstead =>
      'Answers come from the connection instead of a model on this phone.';

  @override
  String get uiQrViewQRCodeWithTheConnectionDetails =>
      'QR code with the connection details';

  @override
  String get uiChatScreenActionsTitle => 'Title';

  @override
  String get uiChatScreenActionsDocumentType => 'Document type';

  @override
  String get uiChatScreenActionsWordDocx => 'Word (.docx)';

  @override
  String get uiChatScreenActionsPDF => 'PDF';

  @override
  String get uiChatScreenActionsPlainTextTxt => 'Plain text (.txt)';

  @override
  String get uiChatScreenActionsMarkdownMd => 'Markdown (.md)';

  @override
  String get uiChatScreenActionsHTML => 'HTML';

  @override
  String get uiChatScreenActionsSelectIndividualMessages =>
      'Select individual messages';

  @override
  String get uiChatScreenActionsRedactTermsCommaSeparated =>
      'Redact terms (comma separated)';

  @override
  String get uiChatScreenActionsChooseMessages => 'Choose messages';

  @override
  String get uiChatScreenActionsUseSelection => 'Use selection';

  @override
  String get uiChatScreenActionsReviewDocument => 'Review document';

  @override
  String get uiChatBubbleChooseQuestionVersion => 'Choose question version';

  @override
  String get uiChatBubbleSources => 'Sources';

  @override
  String get uiChatBubbleKnowledgeLibrary => 'Knowledge library';

  @override
  String get uiChatBubbleSponsoredNotUsed => 'Sponsored (not used)';

  @override
  String get uiChatBubbleOpenInBrowser => 'Open in browser';

  @override
  String get uiCodeBlockCopyCode => 'Copy code';

  @override
  String get uiCodeBlockCodeCopied => 'Code copied';

  @override
  String get readinessUnavailable => 'Unavailable on this device';

  @override
  String readinessMemory(Object total, Object available) {
    return '$total total · $available available now';
  }

  @override
  String readinessStorage(Object free, Object total) {
    return '$free free of $total';
  }

  @override
  String readinessInstalledWeights(Object size, Object count) {
    return '$size across $count models';
  }

  @override
  String readinessContext(Object count, Object backend) {
    return '$count tokens · $backend';
  }

  @override
  String get readinessInstalled => 'Installed';

  @override
  String readinessDownload(Object size) {
    return 'Download: $size';
  }

  @override
  String get readinessRamFits => 'RAM estimate: likely fits';

  @override
  String get readinessRamMayNotFit => 'RAM estimate: may not fit';

  @override
  String get readinessDiskAvailable => 'Disk space available';

  @override
  String get readinessDiskInsufficient => 'Disk space may be insufficient';

  @override
  String readinessMeasured(Object speed) {
    return 'Measured: $speed tok/s';
  }

  @override
  String benchmarkFailed(Object error) {
    return 'Benchmark failed: $error';
  }

  @override
  String benchmarkRunning(Object model, Object runs) {
    return 'Benchmarking $model…\nLoading, then $runs runs of a ~380-token prefill and 128 greedy tokens (first discarded, medians reported), then a chat with the app\'s system prompt, with and without the tools.';
  }

  @override
  String get hfIntro =>
      'Public GGUF repositories only, most downloaded first. Each download is pinned to the repository revision and verified against the Hub\'s SHA-256, like the built-in catalog. Vision projectors (mmproj) and split files are shown but cannot be added yet.';

  @override
  String hfAdded(Object model, Object size, Object template) {
    return '$model added · $size · template $template';
  }

  @override
  String get hfFromMetadata => 'from metadata';

  @override
  String hfRepoStats(Object downloads, Object likes) {
    return '$downloads downloads · $likes likes';
  }

  @override
  String get hfInLibrary => 'in library';

  @override
  String hfLicenseRevision(Object license, Object revision) {
    return 'License: $license · revision $revision';
  }

  @override
  String get hfVisionProjector => 'vision projector';

  @override
  String get hfSplitFile => 'split file';

  @override
  String remoteDeleteHint(Object name) {
    return '“$name” and its API key will be removed from this phone.';
  }

  @override
  String get remoteOwnServer => 'A server on your own hardware.';

  @override
  String get remoteHostedBilling => 'Hosted API billed to your key.';

  @override
  String get remoteNameHelp => 'How this connection is listed.';

  @override
  String remoteOwnUrlHelp(Object path) {
    return 'LM Studio: port 1234 · Ollama: 11434 · llama-server: 8080. “$path” is added automatically.';
  }

  @override
  String remoteHostedUrlHelp(Object provider) {
    return 'Prefilled for $provider; change it only for a proxy or a regional endpoint.';
  }

  @override
  String get remoteInvalidUrl => 'Enter an http(s) URL.';

  @override
  String get remoteApiKey => 'API key';

  @override
  String get remoteApiKeyOptional => 'API key (optional)';

  @override
  String remoteKeyHostedHelp(Object provider) {
    return 'Stored in the Android keystore; sent only to $provider.';
  }

  @override
  String get remoteKeySelfHelp =>
      'Only if the server was started with a key. Stored in the Android keystore.';

  @override
  String get remoteHideKey => 'Hide key';

  @override
  String get remoteShowKey => 'Show key';

  @override
  String get remoteServerDefaultModel => 'Leave empty for the server default';

  @override
  String get remoteModelId => 'Model ID';

  @override
  String get remoteModelListHelp =>
      'Test the connection to pick from the models this provider lists.';

  @override
  String get remoteModelManualHelp =>
      'This provider has no model list; type the ID from its docs.';

  @override
  String get remoteTestList => 'Test & list models';

  @override
  String get remoteTestConnection => 'Test connection';

  @override
  String get remoteExtraHeadersHelp =>
      'One “Name: value” per line, sent with every request (e.g. OpenAI-Organization, OpenRouter attribution). The key header is set for you.';

  @override
  String get remoteConnectedNoList =>
      'Connected. This provider has no model list; type the model ID.';

  @override
  String get remoteConnectedServerNoModels =>
      'Connected, but the server lists no models. Load one in LM Studio / start one in Ollama.';

  @override
  String get remoteConnectedNoModels =>
      'Connected, but no models were listed for this key.';

  @override
  String get remoteCapabilities => 'Capabilities';

  @override
  String get remoteRequestLimits => 'Request limits';

  @override
  String get remoteAdvanced => 'Advanced';

  @override
  String get remoteAnthropicNote =>
      'Anthropic: thinking mode enables adaptive thinking with summaries; temperature/top-p are not sent because the current models reject them. Tool calls, images and JSON-schema output are supported.';

  @override
  String get remoteGeminiNote =>
      'Gemini: thinking mode shows thought summaries; function calling, images and JSON output are supported. Function-call signatures are kept for the session.';

  @override
  String get remoteSelfHostedNote =>
      'Only connect to machines you control. The connection is as private as the network between them: use HTTPS or a VPN over the internet.';

  @override
  String remoteHostedNote(Object provider) {
    return 'Requests are billed to your $provider account. Set a daily cap above if you share the key across apps.';
  }

  @override
  String get remoteNoTools => 'none';

  @override
  String remoteToolsDetected(Object tools) {
    return ' Server tools detected: $tools; they are not executed automatically.';
  }

  @override
  String remoteContextWindow(Object count) {
    return ' Context window $count tokens.';
  }

  @override
  String remoteAdvertises(
    Object model,
    Object capabilities,
    Object context,
    Object tools,
  ) {
    return '$model advertises: $capabilities.$context$tools';
  }

  @override
  String remoteContextOnly(Object model, Object count, Object tools) {
    return '$model: context window $count tokens.$tools';
  }

  @override
  String remoteNoCapabilities(Object tools) {
    return 'This provider does not advertise capabilities for the selected model. Keep the switches on the previous page aligned with the model you use.$tools';
  }

  @override
  String get remoteDefaultModel => 'the default model';

  @override
  String remoteCapsHint(Object model) {
    return 'Caps for $model on this connection. The app refuses to send once a cap is reached; each tool round counts as one request. Empty means no cap.';
  }

  @override
  String remoteUsed(Object minute, Object day) {
    return 'Used: $minute this minute · $day today';
  }

  @override
  String remoteOtherCaps(Object models) {
    return 'Other models with caps here: $models.';
  }

  @override
  String scheduleLoadFailed(Object error) {
    return 'Could not load scheduled prompts: $error';
  }

  @override
  String get noticeCheckingSearch => 'Checking whether to search…';

  @override
  String get noticeResearchingTools => 'Researching with tools…';

  @override
  String get noticeNamingChat => 'Naming the chat…';

  @override
  String get noticeSearchingAgain =>
      'Searching again for what the pages left out…';

  @override
  String get noticeFollowUpSearch =>
      'The pages read earlier do not answer this. Searching again…';

  @override
  String answerSourcesDated(String date) {
    return 'Sources last updated $date.';
  }

  @override
  String get answerSourcesUndated =>
      'The sources do not say when they were last updated.';

  @override
  String sourceUpdated(String date) {
    return 'updated $date';
  }

  @override
  String get thinkOnSearchSetting => 'Think before answering from sources';

  @override
  String get thinkOnSearchHint =>
      'A model that can reason weighs the pages first (up to about 1,000 tokens), even with Thinking mode off.';

  @override
  String get searchAgainSetting => 'Search again when pages fall short';

  @override
  String get searchAgainHint =>
      'When the pages read leave part of the question unanswered, one more search and up to two more pages.';

  @override
  String get wikipediaLookupSetting => 'Add the Wikipedia article';

  @override
  String get wikipediaLookupHint =>
      'The Wikipedia article about the subject joins the sources, in the question\'s language, when one matches.';

  @override
  String get zimSetting => 'Offline Wikipedia';

  @override
  String get zimHint =>
      'Import a Kiwix .zim file (from library.kiwix.org) to answer from Wikipedia with no connection.';

  @override
  String get zimImport => 'Import';

  @override
  String get zimRemove => 'Remove';

  @override
  String zimImporting(String percent) {
    return 'Copying… $percent';
  }

  @override
  String get zimNotAZim => 'That file is not a .zim file.';

  @override
  String get autoTitlesSetting => 'Name chats automatically';

  @override
  String get autoTitlesHint =>
      'After the first answer the model gives the chat a short title. Off: the first message is the title.';

  @override
  String get webModeNote =>
      'Web research mode (Off / Auto / Always) is set on the main Settings screen or the composer pill.';

  @override
  String get thinkingBudgetUnlimited => 'Unlimited';

  @override
  String get adapterImporting => 'Checking and copying the adapter…';

  @override
  String get adapterEmpty =>
      'No adapters yet. Import a LoRA GGUF (made with llama.cpp\'s convert_lora_to_gguf.py) with +, then attach it to a model of the same architecture. The model is reloaded with the adapter applied at the chosen scale.';

  @override
  String get versionPrevious => 'Previous version';

  @override
  String get versionNext => 'Next version';

  @override
  String get sourceFallbackTitle => 'Source';

  @override
  String sourcePublished(String date) {
    return 'published $date';
  }

  @override
  String get sourceReadEarlier => 'read earlier';

  @override
  String get sourceMayBeOutdated => 'may be outdated';

  @override
  String get sourceSponsored => 'Sponsored result';

  @override
  String get sourceSponsoredDetail =>
      'Sponsored result · shown for transparency · not read or given to the model as evidence';

  @override
  String sourceNewsStory(String outlet) {
    return 'News story · $outlet';
  }

  @override
  String get sourceNewsGiven =>
      'the headline and summary below were given to the model';

  @override
  String get sourcePageRead => 'Page read';

  @override
  String get sourceKeptCopy =>
      'kept copy, the site could not be reached; may be outdated';

  @override
  String get sourcePassagesGiven =>
      'the passages below were given to the model';

  @override
  String sourceReadFailed(String error) {
    return 'Page could not be read ($error) · only the search snippet was available';
  }

  @override
  String get sourceSnippetOnly => 'Search snippet only · the page was not read';

  @override
  String get sourceHeadlineOnly =>
      'Headline and listing only · article body unavailable';

  @override
  String get sourceExtractedSection =>
      'Extracted passages · check the quoted text for support';

  @override
  String sourceArchiveSnapshot(String date, String language) {
    return 'Offline archive · $date · $language';
  }

  @override
  String get sourceOfflineLimitation =>
      'This archive cannot verify current or changing facts.';

  @override
  String get sourceArchiveUnavailable =>
      'The original archive is unavailable. Showing the saved excerpt.';

  @override
  String get sourceNoText => 'No text.';

  @override
  String get sourceGivenHeading => 'What the model was given';

  @override
  String sourcePassageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count passages',
      one: '1 passage',
    );
    return '$_temp0';
  }

  @override
  String sourceReadAt(String time) {
    return 'Read $time';
  }

  @override
  String get sourceOpenArchived => 'Open offline article';

  @override
  String get sourceCopyLink => 'Copy link';

  @override
  String get sourceLinkCopied => 'Link copied';

  @override
  String get sourceAddress => 'Full address';

  @override
  String sourceFromKnowledge(String title) {
    return 'From your knowledge library ($title).';
  }

  @override
  String get fitFits => 'Fits this phone';

  @override
  String get fitTight => 'Tight on RAM';

  @override
  String get fitTooLarge => 'Too large for this phone';

  @override
  String get configApplyNote =>
      'Applying replaces that model\'s profile. Web research and hardware stay as you set them.';

  @override
  String configApplied(String model) {
    return 'Applied to $model. It takes effect on the next answer.';
  }

  @override
  String get storageUnavailable => 'Unavailable on this device';

  @override
  String modelProfileTitle(String model) {
    return '$model profile';
  }

  @override
  String get modelProfileScope => 'Model profile';

  @override
  String conversationsLoadFailed(String error) {
    return 'Could not load conversations.\n$error';
  }

  @override
  String get adapterUnknownArchitecture => 'unknown architecture';

  @override
  String adapterAppliedAt(String scale) {
    return 'Applied at scale $scale';
  }

  @override
  String get adapterNotApplied => 'Not applied';

  @override
  String get noticeUpdatingMemory => 'Updating memory…';

  @override
  String noticeWeatherLoading(String place) {
    return 'Weather for $place from DuckDuckGo…';
  }

  @override
  String noticeWeatherDone(String place) {
    return 'Weather for $place from DuckDuckGo (Apple WeatherKit).';
  }

  @override
  String get noticeCollectingNews => 'Collecting the latest news…';

  @override
  String get noticeWebOffUnverified =>
      'Web search is off. Current information has not been verified.';

  @override
  String get noticeOpeningStory => 'Opening that story…';

  @override
  String get noticeStopping => 'Stopping…';

  @override
  String get noticeSearching => 'Searching DuckDuckGo…';

  @override
  String get noticeCheckingWikipedia => 'Checking Wikipedia…';

  @override
  String noticeRecallArticle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count earlier sources',
      one: '1 earlier source',
    );
    return 'Read the article behind that story, plus $_temp0 from this chat.';
  }

  @override
  String noticeRecallPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return 'Answering from $_temp0 already read in this chat.';
  }

  @override
  String get noticeImageRemoteOff =>
      'Image input is disabled for the remote server. Enable it in Remote server settings if the selected model supports vision.';

  @override
  String get noticeImageNoVision =>
      'This model cannot see photos. Add its vision file under Models, or pick a vision model.';

  @override
  String noticeKnowledgeDocs(int count, String collection) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documents',
      one: '1 document',
    );
    return '$_temp0 from “$collection”';
  }

  @override
  String noticePlusWebResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count web results',
      one: '1 web result',
    );
    return ' plus $_temp0';
  }

  @override
  String noticeUsingTool(String tool, String args) {
    return 'Using $tool$args…';
  }

  @override
  String get noticeStopped =>
      'Generation stopped. Any partial response was kept.';

  @override
  String noticeTrimmed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count earlier messages were',
      one: '1 earlier message was',
    );
    return '$_temp0 omitted from the model context; they remain in your history.';
  }

  @override
  String noticeTokenLimit(int count) {
    return 'The answer stopped at the $count-token limit. Tap Continue, or raise Max tokens under Settings > Sampling.';
  }

  @override
  String get noticeStopSequence => 'The answer ended at a stop sequence.';

  @override
  String get noticeResearchSkipped =>
      'The model answered without searching, so nothing here was verified this turn. Regenerate, or turn Model-driven research off to use the fixed search.';

  @override
  String get noticeNoSourcesWebOff =>
      'Web research is off, so the model had no sources. Tap the Local pill to turn it on.';

  @override
  String get noticeNoSourcesNoSearch =>
      'No search ran for this message, so the model had no sources. Switch the pill to Web · always, or ask with \"search for …\".';

  @override
  String noticeStoriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stories',
      one: '1 story',
    );
    return '$_temp0';
  }

  @override
  String noticeOutletsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count outlets',
      one: '1 outlet',
    );
    return '$_temp0';
  }

  @override
  String noticeArticlesRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles read',
      one: '1 article read',
    );
    return '$_temp0';
  }

  @override
  String noticeNewsSummary(
    String stories,
    String outlets,
    String articles,
    String seconds,
  ) {
    return '$stories from $outlets$articles in $seconds s.';
  }

  @override
  String get noticeLinkUnreadable => 'The linked page could not be read.';

  @override
  String get noticeNoWebResults =>
      'No web results. Current information could not be verified.';

  @override
  String noticeLinkedRead(int read, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total linked pages',
      one: '1 linked page',
    );
    return '$read of $_temp0 read.';
  }

  @override
  String noticePagesRead(int read, int results, String queries) {
    String _temp0 = intl.Intl.pluralLogic(
      read,
      locale: localeName,
      other: '$read pages',
      one: '1 page',
    );
    return '$_temp0 read from $results results$queries.';
  }

  @override
  String noticeQueries(int count) {
    return ' ($count queries)';
  }

  @override
  String get noticeEvidenceNoFit =>
      'Web evidence could not fit. Increase context or reduce response length.';

  @override
  String noticeWaitingServer(String client) {
    return 'Waiting for the device server to finish a request from $client…';
  }

  @override
  String noticeReadingPage(int n, int limit, String host) {
    return 'Reading $n of $limit$host…';
  }

  @override
  String noticeToolCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cuts',
      one: '1 cut',
    );
    return 'Tool results were cut to fit the context ($_temp0). Raise the context size or lower the per-tool output budget.';
  }

  @override
  String noticeDocCut(int percent) {
    return 'Attached text was cut to fit the context ($percent% kept). Raise the context size for the whole file.';
  }

  @override
  String noticeRefusal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources were',
      one: '1 source was',
    );
    return 'The model said it cannot browse even though $_temp0 supplied. Regenerate, or try a different model.';
  }

  @override
  String noticeNoCitations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count supplied sources',
      one: '1 supplied source',
    );
    return 'The answer cites none of the $_temp0; treat it as unverified.';
  }

  @override
  String noticeBogusCitations(String cited, int count) {
    return 'The answer cites source $cited, which was not supplied; only [1]–[$count] exist.';
  }

  @override
  String noticeFigures(String figures, String more) {
    return 'Not found in the sources: $figures$more. Treat these figures as unverified.';
  }

  @override
  String noticeFiguresMiscited(String figures, String more) {
    return 'Not in the source cited for them: $figures$more. Another source has them; check the citation.';
  }

  @override
  String get noticeCitationsMatched =>
      'The model cited no sources; the [n] marks were matched to the sources by their words and figures.';

  @override
  String noticeAndMore(int count) {
    return ' and $count more';
  }

  @override
  String get searchChallenge =>
      'DuckDuckGo asked for a bot check, so automatic search is paused for a minute. Pasted links still work.';

  @override
  String searchCooldown(int seconds) {
    return 'Search is paused after a DuckDuckGo block; it resumes in $seconds s. Pasted links still work.';
  }

  @override
  String get searchRateLimit =>
      'DuckDuckGo is rate-limiting searches; paused for a minute. Pasted links still work.';

  @override
  String get searchMarkup =>
      'DuckDuckGo changed its results page and they could not be parsed. Pasted links still work; an app update is needed for search.';

  @override
  String get searchUnavailable =>
      'Web search unavailable (no connection or DuckDuckGo unreachable). Current information could not be verified.';

  @override
  String noticeThrottle(int drop, String from, String to) {
    return 'Speed dropped $drop% ($from → $to tok/s). The phone may be throttling; try a shorter context, fewer GPU layers, or a smaller model.';
  }

  @override
  String get outputGrammarCut =>
      'The grammar-constrained output was cut at the token limit.';

  @override
  String get outputSchemaMismatch =>
      'The output is valid JSON but not the object the schema asks for.';

  @override
  String outputJsonCut(int count) {
    return 'The JSON output was cut at the $count-token limit and does not parse. Raise Max tokens.';
  }

  @override
  String get outputNotJson => 'The output is not valid JSON.';

  @override
  String noticeBatterySaver(String reason, int tokens) {
    return 'Battery saver ($reason): no thinking, answers up to $tokens tokens, fewer pages read.';
  }

  @override
  String saverReasonBattery(int level) {
    return 'battery $level%';
  }

  @override
  String saverReasonHot(String label) {
    return 'phone hot: $label';
  }

  @override
  String newsCollecting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count publishers',
      one: '1 publisher',
    );
    return 'Collecting today\'s stories from DuckDuckGo News and $_temp0…';
  }

  @override
  String newsReadingArticles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles',
      one: '1 article',
    );
    return 'Reading $_temp0…';
  }

  @override
  String get chatErrorNoModel =>
      'Add a model in the Models tab, then send your message.';

  @override
  String chatErrorSave(String error) {
    return 'Could not save response: $error. Copy the response before leaving this chat.';
  }

  @override
  String get chatErrorNoText =>
      'The model produced no text. Try a different template or model.';

  @override
  String chatErrorServing(String model) {
    return 'This phone is serving $model to another device. Stop the device server (Settings) to chat with another model.';
  }

  @override
  String chatErrorServerBusy(String client) {
    return 'The device server is still answering $client. Try again when it has finished.';
  }

  @override
  String get settingGroupGeneration => 'Generation';

  @override
  String get settingGroupReasoning => 'Reasoning';

  @override
  String get settingGroupWeb => 'Web research';

  @override
  String get settingGroupTools => 'Tools';

  @override
  String get settingGroupOutput => 'Structured output';

  @override
  String get settingGroupContext => 'Context';

  @override
  String get settingGroupHardware => 'Hardware';

  @override
  String get settingGroupPrompt => 'Prompt';

  @override
  String get settingLabelSystemPrompt => 'Custom instructions';

  @override
  String get settingLabelTemperature => 'Temperature';

  @override
  String get settingLabelTopP => 'Top-P';

  @override
  String get settingLabelMinP => 'Min-P';

  @override
  String get settingLabelTopK => 'Top-K';

  @override
  String get settingLabelTypicalP => 'Typical-P';

  @override
  String get settingLabelRepetitionPenalty => 'Repetition penalty';

  @override
  String get settingLabelPresencePenalty => 'Presence penalty';

  @override
  String get settingLabelFrequencyPenalty => 'Frequency penalty';

  @override
  String get settingLabelRepeatLastN => 'Penalty window (tokens)';

  @override
  String get settingLabelMaxTokens => 'Max tokens';

  @override
  String get settingLabelSeed => 'Seed (0 = random)';

  @override
  String get settingLabelStopSequences => 'Stop sequences';

  @override
  String get settingLabelThinkingModeEnabled => 'Thinking mode';

  @override
  String get settingLabelThinkingBudgetTokens =>
      'Thinking budget (0 = unlimited)';

  @override
  String get settingLabelWebMode => 'Web research';

  @override
  String get settingLabelResearchLoop => 'Model-driven research';

  @override
  String get settingLabelMaxPagesRead => 'Pages to read';

  @override
  String get settingLabelEvidencePassages => 'Passages given to the model';

  @override
  String get settingLabelKnowledgeCollection => 'Knowledge collection';

  @override
  String get settingLabelToolsEnabled => 'Tool calling';

  @override
  String get settingLabelToolChoice => 'Tool use';

  @override
  String get settingLabelToolMaxRounds => 'Tool rounds per answer';

  @override
  String get settingLabelResponseFormat => 'Response format';

  @override
  String get settingLabelJsonSchema => 'JSON schema';

  @override
  String get settingLabelGrammar => 'GBNF grammar';

  @override
  String get settingLabelContextSize => 'Context size';

  @override
  String get settingLabelPromptCache => 'Keep conversation in context';

  @override
  String get settingLabelBackend => 'Backend';

  @override
  String get settingLabelNGpuLayers => 'GPU layers';

  @override
  String get settingLabelCpuThreads => 'CPU threads (decode, 0 = auto)';

  @override
  String get settingLabelBatchThreads => 'CPU threads (prefill, 0 = auto)';

  @override
  String get settingLabelFlashAttention => 'Flash attention';

  @override
  String get settingLabelKvCacheType => 'K cache type';

  @override
  String get settingLabelVCacheType => 'V cache type (empty = same as K)';

  @override
  String get settingLabelRopeScaling => 'RoPE scaling';

  @override
  String get settingLabelDraftModelId => 'Draft model (speculative decoding)';

  @override
  String get hostLocalOnly => 'Local network and VPN only';

  @override
  String get hostLocalOnlyHint =>
      'Devices on this Wi-Fi, your hotspot or your VPN (Tailscale, WireGuard…) can connect with the token. Requests from the public internet are refused.';

  @override
  String settingEmptyMeans(String value) {
    return 'Empty = $value';
  }

  @override
  String settingEffectiveValue(String value) {
    return 'Effective: $value';
  }

  @override
  String settingInherit(String value) {
    return 'Inherit ($value)';
  }

  @override
  String get remoteScanQr => 'Scan QR code';

  @override
  String get remoteScanHint =>
      'Point the camera at the QR code on the other phone (Settings > Use this device as a server).';

  @override
  String get remoteScanInvalid =>
      'That QR code is not an OnDevice LLM connection. Keep aiming at the server’s code.';

  @override
  String remoteScanNoCamera(String error) {
    return 'The camera is unavailable: $error';
  }

  @override
  String get remoteNameConnection => 'Name this connection';

  @override
  String get remoteNameHint => 'For example: Living-room PC';

  @override
  String get answerFromMemory =>
      'From the model’s memory — may be out of date.';

  @override
  String get searchTheWeb => 'Search the web';

  @override
  String get searchMissesTitle => 'Questions sent to the web by hand';

  @override
  String searchMissesHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count questions. Copy them to improve the search keywords; they never leave this phone otherwise.',
      one:
          '1 question. Copy them to improve the search keywords; they never leave this phone otherwise.',
      zero:
          'None yet. When an answer came from memory and you tapped Search the web, the question is kept here (on this phone only) so the search keywords can be improved.',
    );
    return '$_temp0';
  }

  @override
  String get commonCopied => 'Copied.';

  @override
  String get settingsSearchSection => 'Search';

  @override
  String searchRegionHint(String region) {
    return 'Where news briefings and search results come from. Automatic follows the app language and the phone’s country setting (now $region).';
  }

  @override
  String get searchRegionAutomatic => 'Automatic';

  @override
  String get researchLoopHint =>
      'Questions that would be searched are researched by the model itself: it searches, picks pages to read, searches again if needed, then answers with citations. Pasted links are still read directly. Slower per question; compare on your own questions.';

  @override
  String get researchLoopNeedsTools =>
      'Needs tool calling on with the web tools (Settings > Tools).';

  @override
  String get selectionTitle => 'What should I do with the selected text?';

  @override
  String get selectionExplain => 'Explain it';

  @override
  String get selectionSummarize => 'Summarize it';

  @override
  String get selectionTranslate => 'Translate it';

  @override
  String get selectionFix => 'Fix spelling and grammar';

  @override
  String get selectionAsk => 'Ask about it';

  @override
  String get quickDescribe => 'Describe';

  @override
  String get quickDescribePrompt => 'Describe this photo in detail.';

  @override
  String get quickExtractText => 'Extract text';

  @override
  String get quickExtractTextPrompt =>
      'Transcribe all the text in this image exactly as written, keeping the layout.';

  @override
  String get quickTranslate => 'Translate';

  @override
  String get quickTranslatePrompt =>
      'Translate all the text in this image into English.';

  @override
  String get quickSolve => 'Solve';

  @override
  String get quickSolvePrompt =>
      'Solve the problem shown in this image and explain each step.';

  @override
  String get quickExplain => 'Explain';

  @override
  String get quickExplainPrompt =>
      'Explain what this image shows and why it matters.';

  @override
  String get quickIdentify => 'Identify';

  @override
  String get quickIdentifyPrompt =>
      'What is this? Identify it and tell me what you know about it.';

  @override
  String get quickSummarise => 'Summarise';

  @override
  String get quickSummarisePrompt =>
      'Summarise this document: one-sentence takeaway, then the key points.';

  @override
  String get quickKeyPoints => 'Key points';

  @override
  String get quickKeyPointsPrompt =>
      'List the key points of this document as short bullets.';

  @override
  String get quickExplainSimply => 'Explain simply';

  @override
  String get quickExplainSimplyPrompt =>
      'Explain this document in plain language for someone new to the topic.';

  @override
  String get quickActionItems => 'Action items';

  @override
  String get quickActionItemsPrompt =>
      'List every action item, deadline and decision in this document.';

  @override
  String get quickQuestions => 'Questions';

  @override
  String get quickQuestionsPrompt =>
      'What questions should I ask about this document before relying on it?';

  @override
  String get sectionVoice => 'Voice';

  @override
  String get sectionAutomation => 'Shortcuts & automation';

  @override
  String get sectionModelConnections => 'Model & connections';

  @override
  String get sectionAppearanceLanguage => 'Appearance & language';

  @override
  String get sectionData => 'Your data';

  @override
  String get advancedNote =>
      'The defaults work well. These are for fine-tuning speed, memory use and output.';

  @override
  String get remoteRowOff => 'Off · the model runs on this phone';

  @override
  String get backupRowHint => 'Save or restore chats, attachments and settings';

  @override
  String remoteRowOn(String name) {
    return 'On · $name';
  }

  @override
  String get sectionCachePrecision => 'Cache precision';

  @override
  String get sectionCapabilities => 'Capabilities';

  @override
  String get sectionConnections => 'Connections';

  @override
  String get sectionEvidence => 'Sources given to the model';

  @override
  String get sectionExtraSamplers => 'Extra samplers';

  @override
  String get sectionLayers => 'Layers, lowest first';

  @override
  String get sectionPenalties => 'Penalties';

  @override
  String get sectionRope => 'Position encoding (RoPE / YaRN)';

  @override
  String get sectionReasoning => 'Reasoning';

  @override
  String get sectionReproducibility => 'Reproducibility';

  @override
  String get sectionSamplerOrder => 'Sampler order';

  @override
  String get sectionSpeculative => 'Speculative decoding (experimental)';

  @override
  String get sectionTools => 'Tools';

  @override
  String get chatSettingsMenu => 'This chat\'s settings';

  @override
  String chatSettingsMenuCount(int count) {
    return 'This chat\'s settings · $count';
  }

  @override
  String remoteUsingSummary(String name, String host) {
    return 'Chats run on $name ($host). Local models are not loaded.';
  }

  @override
  String get remoteNeedsConnection => 'Add a connection below to turn it on.';

  @override
  String get remoteNeedsUrl =>
      'The selected connection needs a valid http(s) address.';

  @override
  String get remoteNoUrl => 'no address';

  @override
  String get remoteNoKey => 'no key';

  @override
  String get remoteScanShort => 'Scan QR';

  @override
  String get remotePasteShort => 'Paste';

  @override
  String get modelProfile => 'Profile';

  @override
  String modelProfileCount(int count) {
    return 'Profile · $count';
  }

  @override
  String get modelsFootnote =>
      'Larger models give better answers but are slower and use more memory. The badge on each model says whether it fits this phone.';

  @override
  String get benchmarkRunAgain => 'Run again';

  @override
  String benchmarkMeasuredAt(String date) {
    return 'Measured $date';
  }

  @override
  String get unloadShort => 'Unload';

  @override
  String get unsavedChanges => 'Unsaved changes';

  @override
  String get savedNotice => 'Saved';

  @override
  String get pickerLibrary => 'Library';

  @override
  String get pickerConnections => 'Connections';

  @override
  String get pickerReasoning => 'reasoning';

  @override
  String get pickerTightRam => 'tight on RAM';

  @override
  String get pickerTooLarge => 'too large for this phone';

  @override
  String get pickerNoKey => 'no key yet';

  @override
  String get goalPhaseVerifying => 'Checking the report against the findings';

  @override
  String get goalGuardrails => 'Guardrails';

  @override
  String get goalSubjectTitle => 'Stay on these names';

  @override
  String get goalSubjectHint =>
      'Found in your goal. The model must use them exactly; pages about similar models, versions or generations are left out.';

  @override
  String get goalSubjectNone =>
      'No names found yet: products, people and places in your goal appear here as you type.';

  @override
  String get goalSubjectAdd => 'Add a name';

  @override
  String get goalSubjectExample => 'e.g. Sony ZV-E10';

  @override
  String get goalSubjectReset => 'Reset';

  @override
  String get goalRulesLabel => 'Your rules (optional)';

  @override
  String get goalRulesHint =>
      'One per line, e.g. Prices in CAD · Only 2026 sources · No rumours';

  @override
  String get goalRulesBuiltIn => 'Rules every goal follows';

  @override
  String get goalRuleSubject =>
      'Uses your names exactly; never swaps in a similar model, version or generation.';

  @override
  String get goalRuleEvidence =>
      'States only facts from the sources, each with its citation; nothing from memory.';

  @override
  String get goalRuleOffTopic =>
      'Ignores sources about something else and says what is missing; never asks you for sources.';

  @override
  String get goalRuleFigures =>
      'Copies numbers, dates and prices exactly; gives both sides when sources disagree.';

  @override
  String get goalRuleThinking =>
      'Thinks briefly before the plan and the evidence review; the steps and the report answer directly, so a run is faster.';

  @override
  String get goalRuleCheck =>
      'Every step and the report are checked automatically; a failed check is redone once.';

  @override
  String goalCheckDrift(String names) {
    return 'Mentions $names, not the goal\'s subject';
  }

  @override
  String goalCheckOffTarget(String names) {
    return 'Researched $names instead: left out of the report';
  }

  @override
  String get goalCheckNoSources => 'No sources found';

  @override
  String get goalCheckNoCitations => 'Cites no sources';

  @override
  String goalCheckBadCitations(String numbers) {
    return 'Cites sources that do not exist: $numbers';
  }

  @override
  String goalCheckFigures(String figures) {
    return 'Figures found in no source: $figures';
  }

  @override
  String goalCheckDroppedFigures(String figures) {
    return 'Left out figures no source states: $figures';
  }

  @override
  String get goalCheckAskedUser => 'Asked you for information';

  @override
  String get goalCheckRetried => 'Researched again after a failed check';

  @override
  String get goalCheckRevised => 'Rewritten once to fix the check';

  @override
  String get goalReportChecked =>
      'Checked: names, citations and figures match the findings';

  @override
  String get goalStepSearched => 'Searched';

  @override
  String get goalStepTools => 'Tool calls';

  @override
  String get goalStepSources => 'Sources';

  @override
  String get goalStepReasoning => 'Reasoning';

  @override
  String goalStepStats(int prompt, int tokens, String seconds, String tps) {
    return '$prompt prompt + $tokens generated tokens · $seconds s · $tps tok/s';
  }

  @override
  String goalStepSearchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count searches',
      one: '1 search',
    );
    return '$_temp0';
  }

  @override
  String goalStepToolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tool calls',
      one: '1 tool call',
    );
    return '$_temp0';
  }

  @override
  String get goalPlanNotes => 'How the plan was made';

  @override
  String get goalReviewNotes => 'Reviewer\'s reasoning';

  @override
  String get goalCheckLeak => 'Reasoning that ran into the answer was removed';

  @override
  String goalSmallModel(String model) {
    return '$model is a small model: goals are much more accurate with Gemma 4 E2B or a larger model (it stays on the subject and cites its sources).';
  }

  @override
  String get goalPartial => 'Partial result — more evidence needed';

  @override
  String get goalCriteriaReview => 'Success criteria';

  @override
  String goalEvidenceSteps(String steps) {
    return 'Evidence: steps $steps';
  }

  @override
  String get backupExportReady =>
      'Encrypted backup handed to the export sheet.';

  @override
  String get remoteShareMemory => 'Share memory with this connection';

  @override
  String get remoteShareMemoryHint =>
      'Allow selected notes to be included in requests to this server.';

  @override
  String get remoteLearnMemory => 'Learn memory using this connection';

  @override
  String get remoteLearnMemoryHint =>
      'Allow a separate server request to extract durable facts from your messages. Simple explicit facts can still be saved locally when Memory is on.';

  @override
  String get memoryPin => 'Always consider this note';

  @override
  String get memoryUnpin => 'Unpin note';

  @override
  String get memoryReconfirm => 'Confirm this is still accurate';

  @override
  String get memoryExpire => 'Expire in 30 days';

  @override
  String get memoryNoExpiry => 'Remove expiry';

  @override
  String memoryExpires(String date) {
    return 'Expires $date';
  }

  @override
  String get settingsSearch => 'Search settings';

  @override
  String get settingsFaster => 'Faster replies';

  @override
  String get settingsDetailed => 'More detail';

  @override
  String get settingsLessMemory => 'Use less RAM';

  @override
  String get imageTokenBudget => 'Photo token budget';

  @override
  String get imageTokenBudgetHint =>
      'More detail uses more memory and time. Reloads the model.';

  @override
  String get documentPreview => 'Preview';

  @override
  String get documentEdit => 'Edit';

  @override
  String get documentDraftSaved => 'Draft saved on this device';

  @override
  String get documentVersions => 'Version history';

  @override
  String get goalQuestionsTitle => 'A few questions first';

  @override
  String get goalQuestionsHint =>
      'Your preferences can make the report more useful. Choose an answer, type your own, or skip. Research waits until you continue.';

  @override
  String get goalYourAnswer => 'Your answer (optional)';

  @override
  String get goalQuestionsLater => 'Later';

  @override
  String get goalQuestionsSkip => 'Skip and continue';

  @override
  String get goalPhaseClarifying =>
      'Checking whether clarification would help…';

  @override
  String get goalWaitingAnswers => 'Waiting for your answers';

  @override
  String get goalAnswerQuestions => 'Answer questions';

  @override
  String get goalClarificationAnswers => 'Your clarification answers';

  @override
  String get goalAssumptionsAllowed =>
      'Skipped — the report will state its assumptions.';

  @override
  String get goalSearchGuidance => 'Search and report direction';

  @override
  String get goalSearchGuidanceHint =>
      'Explain what the report missed, which questions to search, and what to emphasize.';

  @override
  String get goalRefineRun => 'Save and research';

  @override
  String get goalCriteriaSeparate =>
      'One requirement per line, so coverage can be measured.';

  @override
  String goalCoverage(Object percent, Object target) {
    return 'Supported requirements: $percent% · target $target%';
  }

  @override
  String get goalCompletionHint =>
      'Stop when this share of requirements is supported. Remaining gaps stay visible; citations and factual checks still apply.';

  @override
  String get goalCompletionTarget => 'Completion target';

  @override
  String get goalRefine => 'Edit goal / steer research';

  @override
  String memoryScanResult(Object count) {
    return 'Recovered $count memories from saved chats.';
  }

  @override
  String get memoryScanHistory => 'Scan saved chats for missed memories';

  @override
  String get goalEvidenceWorkspace => 'Compare evidence';

  @override
  String get goalEvidenceSnapshotHint =>
      'Compare the saved source excerpts with the step findings. These are the excerpts the model used; a page opened today may have changed. A source or a passed automatic check does not by itself prove a claim.';

  @override
  String get goalEvidenceSupported => 'Requirement supported';

  @override
  String get goalEvidenceGap => 'Requirement needs evidence';

  @override
  String get goalEvidenceMissing =>
      'No retrieved excerpt was saved for this source.';

  @override
  String get goalEvidenceFind => 'Find text in these sources';

  @override
  String get goalEvidencePublished => 'Published';

  @override
  String get goalEvidenceRetrieved => 'Retrieved';

  @override
  String get goalEvidenceOpen => 'Open page';

  @override
  String get goalEvidenceCopy => 'Copy excerpt';

  @override
  String get goalEvidenceNoMatch => 'No match in this saved excerpt.';

  @override
  String get goalEvidenceExcluded =>
      'This step was excluded from report evidence.';

  @override
  String get contextInspector => 'Context inspector';

  @override
  String get contextSnapshotHint =>
      'Saved context selection for this answer. Excerpts help you inspect it; they are not automatically used as summaries in future answers.';

  @override
  String get contextSnapshotMissing =>
      'This older answer has no saved context snapshot.';

  @override
  String get contextTokens => 'Context tokens';

  @override
  String get contextIsolated =>
      'This request used its current question without earlier chat turns.';

  @override
  String get contextInstructions => 'Instructions given to the model';

  @override
  String get contextCharacters => 'characters';

  @override
  String get contextMessages => 'Conversation messages';

  @override
  String get contextIncluded => 'Included';

  @override
  String get contextOmittedIsolated => 'Omitted for this independent request';

  @override
  String get contextOmittedLimit =>
      'Omitted to fit the context limit; kept in history';

  @override
  String get contextImages => 'images';

  @override
  String get contextDocuments => 'documents';

  @override
  String get contextSnippetOnly => 'Search snippet only; page was not read';

  @override
  String get contextStale => 'Cached evidence may be outdated';

  @override
  String get goalModelLabel => 'Model';

  @override
  String get goalModelNone => 'No local model ready';

  @override
  String get goalModelOnStart => 'loads when the Goal starts';

  @override
  String get contextOmitted => 'Omitted';

  @override
  String get contextEarlierHidden => 'Earlier message previews not shown';

  @override
  String contextCapTrain(String size) {
    return 'Context set to $size tokens, the most this model was trained for.';
  }

  @override
  String contextCapMemory(String size) {
    return 'Context set to $size tokens so the model fits in free memory.';
  }

  @override
  String notEnoughMemory(int need, int free) {
    final intl.NumberFormat needNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String needString = needNumberFormat.format(need);
    final intl.NumberFormat freeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String freeString = freeNumberFormat.format(free);

    return 'Not enough free memory for this model: it needs about $needString MB and $freeString MB is free. Close other apps or choose a smaller model.';
  }

  @override
  String contextTrainedFor(String size) {
    return 'The loaded model was trained for $size tokens.';
  }

  @override
  String contextTrainedForCapped(String size) {
    return 'The loaded model was trained for $size tokens. A larger context is shortened to that when the model loads, unless RoPE scaling is set under Memory, RoPE & speculation.';
  }

  @override
  String contextTrainedForStretched(String size) {
    return 'The loaded model was trained for $size tokens; RoPE scaling stretches it past that, and quality can drop.';
  }

  @override
  String get photosAndVoiceNotes => 'Photos and voice notes';

  @override
  String photosAndVoiceNotesBody(Object mb) {
    return 'Find photos by what they show and recordings by what they say, with the same questions as your documents. Runs on the phone; ~$mb MB once.';
  }

  @override
  String get photosAndVoiceNotesReady =>
      'Photos and recordings are matched by what they show or say.';

  @override
  String noticeClaimsNotInSources(String claims, String more) {
    return 'Not backed by the sources: $claims$more. Check these statements before relying on them.';
  }

  @override
  String noticeClaimsNames(String details) {
    return 'names or dates no source mentions: $details';
  }

  @override
  String get naturalVoiceTitle => 'Natural on-device voice';

  @override
  String get naturalVoiceHint =>
      'Whisper listens and Kokoro speaks, entirely on this phone. Falls back to the system voice when not downloaded.';

  @override
  String get talkOverTitle => 'Talk over the answer';

  @override
  String get talkOverHint =>
      'In a conversation, interrupt by speaking. The answer then sounds like a phone call. Off: clear sound, tap to interrupt.';

  @override
  String get spokenLengthTitle => 'Spoken answer length';

  @override
  String get spokenLengthHint =>
      'How much of an answer Conversation says out loud. Lists are always read in full.';

  @override
  String get spokenLengthShort => 'Short (3 sentences)';

  @override
  String get spokenLengthLonger => 'Longer (6 sentences)';

  @override
  String get spokenLengthFull => 'Whole answer';

  @override
  String get voiceListeningPack => 'Listening (Whisper)';

  @override
  String get voiceSpeakingPack => 'Speaking (Kokoro)';

  @override
  String get listeningModelTitle => 'Listening model';

  @override
  String get listeningModelHint =>
      'Parakeet v3 heard every test phrase on the phone and answers faster than Whisper; it also understands French and Spanish better. It is a separate download and uses more memory while you talk. Parakeet TDT 0.6B v3 by NVIDIA, CC BY 4.0.';

  @override
  String get listeningWhisper => 'Whisper base';

  @override
  String get listeningParakeet => 'Parakeet v3';

  @override
  String get voiceUnpacking => 'Unpacking…';

  @override
  String get voicePick => 'Voice';

  @override
  String get voiceTry => 'Try';

  @override
  String get voiceSample =>
      'Hi! This is how I sound when I read your answers aloud.';

  @override
  String get voiceDownloadBoth => 'Download the on-device voice';

  @override
  String get conversationTitle => 'Conversation';

  @override
  String get convListening => 'Listening…';

  @override
  String get convThinking => 'Thinking…';

  @override
  String get convLookingUp => 'Looking it up…';

  @override
  String get convSpeaking => 'Speaking · talk to interrupt';

  @override
  String get convSpeakingTap => 'Speaking · tap to interrupt';

  @override
  String get convPaused => 'Microphone off';

  @override
  String get convNeedsVoice =>
      'For a natural, hands-free conversation, download the on-device voice (about 290 MB). Until then the system voice is used.';

  @override
  String convModelMissing(String model) {
    return '$model is not downloaded, so another downloaded model answers. Download it in Models, or pick a model with the button at the top right.';
  }

  @override
  String get convNoModel => 'Load a model first.';

  @override
  String get convModelTitle => 'Conversation model';

  @override
  String get convModelHint =>
      'Conversation answers with Qwen3.5 0.8B on the phone: it starts speaking in a few seconds. With a remote connection on, its model can answer instead.';

  @override
  String get convModelRemote =>
      'Searches by itself when needed and remembers the whole conversation';

  @override
  String convRemoteFailed(String error) {
    return 'The remote connection did not answer ($error). Answering on the phone.';
  }

  @override
  String get convModelFastest => 'fastest';

  @override
  String get convMicDenied =>
      'The microphone is not allowed. Allow it in the phone\'s settings to talk.';

  @override
  String get convEnd => 'End conversation';

  @override
  String get convStopAnswer => 'Stop answer';

  @override
  String get convMute => 'Mute microphone';

  @override
  String get convUnmute => 'Turn microphone on';

  @override
  String convLoadingModel(String model) {
    return 'Loading $model…';
  }

  @override
  String get convHint =>
      'Just talk. I answer out loud; talk over me to interrupt.';

  @override
  String get convInterrupt => 'Interrupt';

  @override
  String get actionEvent => 'Add to calendar';

  @override
  String get actionReminder => 'Add reminder';

  @override
  String get actionAlarm => 'Set alarm';

  @override
  String get actionTimer => 'Start timer';

  @override
  String get actionMessage => 'Open draft';

  @override
  String get actionFile => 'Save or share';

  @override
  String get actionNoApp => 'No app on this phone can do this.';

  @override
  String get actionConfirmHint =>
      'Prepared for you: you confirm in the app that opens.';

  @override
  String get actionConfirmDone => 'I completed this action';

  @override
  String actionConfirmedAt(String time) {
    return 'Confirmed at $time';
  }

  @override
  String get goalAwaitingActions => 'Waiting for your action confirmation';

  @override
  String get actionReadyAnswer =>
      'Ready. Check the card below and tap its button to finish.';

  @override
  String get echoedAnswer =>
      'The model copied its instructions instead of answering, so no answer is shown. Open the sources below, or ask again in other words.';

  @override
  String get goalActionsTitle => 'Ready to do';

  @override
  String get goalSaveReport => 'Save report as file';

  @override
  String get goalWatch => 'Watch daily';

  @override
  String goalWatchSet(String time) {
    return 'Watching daily at $time. A background search checks for changes and notifies you when a new result or figure changes. The full goal runs again only when you ask.';
  }

  @override
  String get goalPreparingActions => 'Preparing actions…';

  @override
  String get goalPhaseDelivering => 'Preparing what the goal asked for';

  @override
  String goalNotPrepared(String item, String reason) {
    return 'Not prepared: $item ($reason)';
  }

  @override
  String goalDeliverableFile(String format) {
    return 'the $format file';
  }

  @override
  String get goalDeliverableEvent => 'the calendar event';

  @override
  String get goalDeliverableReminder => 'the reminder';

  @override
  String get goalDeliverableAlarm => 'the alarm';

  @override
  String get goalDeliverableTimer => 'the timer';

  @override
  String get goalDeliverableMessage => 'the message draft';

  @override
  String get goalNotPreparedStopped => 'the goal was stopped';

  @override
  String get goalNotPreparedBudget => 'the goal\'s budget ran out';

  @override
  String get goalNotPreparedUnreadable =>
      'the model\'s reply could not be read';

  @override
  String get goalNotPreparedTooLong => 'the report is too long for one file';

  @override
  String get goalNotPreparedNone => 'the model proposed none';

  @override
  String goalNotPreparedInvalid(String problem) {
    return 'the model\'s proposal was incomplete: $problem';
  }

  @override
  String get goalWatchesTitle => 'Watched goals';

  @override
  String get goalWatchChecking => 'Checking…';

  @override
  String get goalWatchWebOff => 'Web search is off';

  @override
  String get goalWatchNoResults => 'The search found nothing';

  @override
  String get goalWatchOffline => 'Could not search (offline?)';

  @override
  String get goalWatchNotYet => 'Not checked yet';

  @override
  String goalWatchBaseline(String when) {
    return 'First results kept $when';
  }

  @override
  String goalWatchNoChange(String when) {
    return 'No change · $when';
  }

  @override
  String goalWatchChanged(int fresh, int figures, String when) {
    return '$fresh new, $figures changed figures · $when';
  }

  @override
  String goalWatchDailyAt(String time) {
    return 'daily at $time';
  }

  @override
  String goalWatchNewResult(String title) {
    return 'New: $title';
  }

  @override
  String get goalWatchCheckNow => 'Check now';

  @override
  String get goalWatchRunAgain => 'Run the goal again';

  @override
  String get goalWatchStop => 'Stop watching';

  @override
  String actionOpenedAt(String time) {
    return 'Opened at $time: confirm it there';
  }

  @override
  String get remoteServerSettings => 'Use the server\'s own settings';

  @override
  String get remoteServerSettingsHint =>
      'Temperature, sampling, answer length and context come from the model on this connection (Gemini\'s defaults, the settings LM Studio loaded it with…), not from the phone\'s presets.';

  @override
  String get sheetAttachments => 'Attachments and tools';

  @override
  String get sheetNotice => 'Notice';
}
