import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('fr'),
  ];

  /// No description provided for @settingScopeHint.
  ///
  /// In en, this message translates to:
  /// **'Clear a value to use the default from the previous layer. Settings marked ↻ take effect when the model loads.'**
  String get settingScopeHint;

  /// No description provided for @settingExplicit.
  ///
  /// In en, this message translates to:
  /// **'Customized'**
  String get settingExplicit;

  /// No description provided for @settingInherited.
  ///
  /// In en, this message translates to:
  /// **'Inherited'**
  String get settingInherited;

  /// No description provided for @settingOnePerLine.
  ///
  /// In en, this message translates to:
  /// **'One per line'**
  String get settingOnePerLine;

  /// No description provided for @nearbyHosts.
  ///
  /// In en, this message translates to:
  /// **'Find nearby hosts'**
  String get nearbyHosts;

  /// No description provided for @nearbyHostsHint.
  ///
  /// In en, this message translates to:
  /// **'Find OnDevice LLM hosts on the same network. Select one, then enter its access key or use its pairing QR code.'**
  String get nearbyHostsHint;

  /// No description provided for @nearbyHostsNone.
  ///
  /// In en, this message translates to:
  /// **'No hosts found. Start hosting on the other device and check that both devices use the same network. Manual pairing remains available.'**
  String get nearbyHostsNone;

  /// No description provided for @scanConfidence.
  ///
  /// In en, this message translates to:
  /// **'Recognizer confidence'**
  String get scanConfidence;

  /// No description provided for @scanSettings.
  ///
  /// In en, this message translates to:
  /// **'Text recognition'**
  String get scanSettings;

  /// No description provided for @scanPageLimit.
  ///
  /// In en, this message translates to:
  /// **'Scanned pages per PDF'**
  String get scanPageLimit;

  /// No description provided for @scanLongHint.
  ///
  /// In en, this message translates to:
  /// **'Text layers are read beyond this limit. Longer scans show progress and can be stopped.'**
  String get scanLongHint;

  /// No description provided for @scanLanguage.
  ///
  /// In en, this message translates to:
  /// **'Recognition language'**
  String get scanLanguage;

  /// No description provided for @scanLatinHint.
  ///
  /// In en, this message translates to:
  /// **'Android recognizes English, French, Spanish and other Latin-script text automatically, on this device.'**
  String get scanLatinHint;

  /// No description provided for @scanQualityHint.
  ///
  /// In en, this message translates to:
  /// **'Recognizer confidence can still be wrong. Check important text against the original.'**
  String get scanQualityHint;

  /// No description provided for @modelSettingsAll.
  ///
  /// In en, this message translates to:
  /// **'All model settings'**
  String get modelSettingsAll;

  /// No description provided for @modelSettingsGlobal.
  ///
  /// In en, this message translates to:
  /// **'Your model settings'**
  String get modelSettingsGlobal;

  /// No description provided for @modelSettingsAllHint.
  ///
  /// In en, this message translates to:
  /// **'Edit or reset the settings used by model profiles, presets and chats'**
  String get modelSettingsAllHint;

  /// No description provided for @removeProjectHint.
  ///
  /// In en, this message translates to:
  /// **'Remove this project and its instructions? Its conversations and knowledge files will be kept.'**
  String get removeProjectHint;

  /// No description provided for @downloadQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a download slot'**
  String get downloadQueued;

  /// No description provided for @sourceMessage.
  ///
  /// In en, this message translates to:
  /// **'Source message'**
  String get sourceMessage;

  /// No description provided for @sourceMessageMissing.
  ///
  /// In en, this message translates to:
  /// **'This source message is no longer available.'**
  String get sourceMessageMissing;

  /// No description provided for @openConversation.
  ///
  /// In en, this message translates to:
  /// **'Open conversation'**
  String get openConversation;

  /// No description provided for @contextSummary.
  ///
  /// In en, this message translates to:
  /// **'Review context summary'**
  String get contextSummary;

  /// No description provided for @contextSummaryHint.
  ///
  /// In en, this message translates to:
  /// **'Write a summary of these earlier messages. Review it before saving; later answers can use it in place of this part of the conversation.'**
  String get contextSummaryHint;

  /// No description provided for @contextSummaryTooShort.
  ///
  /// In en, this message translates to:
  /// **'More conversation history is needed before making a summary.'**
  String get contextSummaryTooShort;

  /// No description provided for @memoryUsed.
  ///
  /// In en, this message translates to:
  /// **'Memory used'**
  String get memoryUsed;

  /// No description provided for @unverifiedFeatures.
  ///
  /// In en, this message translates to:
  /// **'Features requiring verification'**
  String get unverifiedFeatures;

  /// No description provided for @restoreVersion.
  ///
  /// In en, this message translates to:
  /// **'Use this version'**
  String get restoreVersion;

  /// No description provided for @originalFile.
  ///
  /// In en, this message translates to:
  /// **'Share original file'**
  String get originalFile;

  /// No description provided for @previousVersion.
  ///
  /// In en, this message translates to:
  /// **'Previous version'**
  String get previousVersion;

  /// No description provided for @workspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Projects and conversations'**
  String get workspaceTitle;

  /// No description provided for @project.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get project;

  /// No description provided for @projectName.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectName;

  /// No description provided for @projectInstructions.
  ///
  /// In en, this message translates to:
  /// **'Instructions for this project'**
  String get projectInstructions;

  /// No description provided for @noProject.
  ///
  /// In en, this message translates to:
  /// **'No project'**
  String get noProject;

  /// No description provided for @archivedChats.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archivedChats;

  /// No description provided for @trashChats.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trashChats;

  /// No description provided for @archiveChats.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archiveChats;

  /// No description provided for @restoreChats.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreChats;

  /// No description provided for @moveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to trash'**
  String get moveToTrash;

  /// No description provided for @permanentDeleteHint.
  ///
  /// In en, this message translates to:
  /// **'Permanently remove these conversations and attachments from this device. This cannot be undone.'**
  String get permanentDeleteHint;

  /// No description provided for @selectAllChats.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAllChats;

  /// No description provided for @temporaryChat.
  ///
  /// In en, this message translates to:
  /// **'Temporary chat'**
  String get temporaryChat;

  /// No description provided for @temporaryChatHint.
  ///
  /// In en, this message translates to:
  /// **'This chat and its draft stay in memory. Memory is off. Leaving discards it; remote and web requests still use your selected connection.'**
  String get temporaryChatHint;

  /// No description provided for @deleteAnswer.
  ///
  /// In en, this message translates to:
  /// **'Delete answer'**
  String get deleteAnswer;

  /// No description provided for @deleteQuestionAnswer.
  ///
  /// In en, this message translates to:
  /// **'Delete question and answer'**
  String get deleteQuestionAnswer;

  /// No description provided for @messageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get messageDeleted;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @undoUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Undo is unavailable while another operation is running.'**
  String get undoUnavailable;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'OnDevice'**
  String get appTitle;

  /// No description provided for @noModelLoaded.
  ///
  /// In en, this message translates to:
  /// **'no model loaded'**
  String get noModelLoaded;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @drawerTemporary.
  ///
  /// In en, this message translates to:
  /// **'Temporary'**
  String get drawerTemporary;

  /// No description provided for @drawerWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get drawerWorkspace;

  /// No description provided for @drawerProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects & conversations'**
  String get drawerProjects;

  /// No description provided for @drawerProjectsHint.
  ///
  /// In en, this message translates to:
  /// **'Projects, archive and trash'**
  String get drawerProjectsHint;

  /// No description provided for @drawerProjectsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Group chats with shared instructions} =1{1 project} other{{count} projects}}'**
  String drawerProjectsCount(int count);

  /// No description provided for @previous7Days.
  ///
  /// In en, this message translates to:
  /// **'Previous 7 days'**
  String get previous7Days;

  /// No description provided for @previous30Days.
  ///
  /// In en, this message translates to:
  /// **'Previous 30 days'**
  String get previous30Days;

  /// No description provided for @olderChats.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get olderChats;

  /// No description provided for @chatOptions.
  ///
  /// In en, this message translates to:
  /// **'Chat options'**
  String get chatOptions;

  /// No description provided for @shareOrExport.
  ///
  /// In en, this message translates to:
  /// **'Share or export'**
  String get shareOrExport;

  /// No description provided for @thisChatSection.
  ///
  /// In en, this message translates to:
  /// **'This chat'**
  String get thisChatSection;

  /// No description provided for @conversations.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get conversations;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @exportMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Export Markdown'**
  String get exportMarkdown;

  /// No description provided for @exportJson.
  ///
  /// In en, this message translates to:
  /// **'Export JSON'**
  String get exportJson;

  /// No description provided for @shareAsText.
  ///
  /// In en, this message translates to:
  /// **'Share as text'**
  String get shareAsText;

  /// No description provided for @createDocument.
  ///
  /// In en, this message translates to:
  /// **'Create document'**
  String get createDocument;

  /// No description provided for @documentFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get documentFormat;

  /// No description provided for @answersOnly.
  ///
  /// In en, this message translates to:
  /// **'Assistant answers only'**
  String get answersOnly;

  /// No description provided for @includeBranches.
  ///
  /// In en, this message translates to:
  /// **'Include earlier branches'**
  String get includeBranches;

  /// No description provided for @includeReasoning.
  ///
  /// In en, this message translates to:
  /// **'Include model reasoning'**
  String get includeReasoning;

  /// No description provided for @saveDocument.
  ///
  /// In en, this message translates to:
  /// **'Save document'**
  String get saveDocument;

  /// No description provided for @models.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get models;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @metrics.
  ///
  /// In en, this message translates to:
  /// **'Metrics'**
  String get metrics;

  /// No description provided for @loadingModel.
  ///
  /// In en, this message translates to:
  /// **'Loading model into memory…'**
  String get loadingModel;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Message your model…'**
  String get messageHint;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get listening;

  /// No description provided for @chooseModel.
  ///
  /// In en, this message translates to:
  /// **'Choose a model'**
  String get chooseModel;

  /// No description provided for @think.
  ///
  /// In en, this message translates to:
  /// **'Think'**
  String get think;

  /// No description provided for @thinkOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get thinkOff;

  /// No description provided for @thinkLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get thinkLow;

  /// No description provided for @thinkMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get thinkMedium;

  /// No description provided for @thinkHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get thinkHigh;

  /// No description provided for @thinkOffHint.
  ///
  /// In en, this message translates to:
  /// **'Answers right away. The fastest.'**
  String get thinkOffHint;

  /// No description provided for @thinkLowHint.
  ///
  /// In en, this message translates to:
  /// **'A short reasoning pass first (about 500 tokens).'**
  String get thinkLowHint;

  /// No description provided for @thinkMediumHint.
  ///
  /// In en, this message translates to:
  /// **'Reasons longer first (about 2,000 tokens), for harder questions.'**
  String get thinkMediumHint;

  /// No description provided for @thinkHighHint.
  ///
  /// In en, this message translates to:
  /// **'Reasons at length first (about 8,000 tokens). The slowest.'**
  String get thinkHighHint;

  /// No description provided for @thinkLevelToast.
  ///
  /// In en, this message translates to:
  /// **'Thinking: {level}'**
  String thinkLevelToast(String level);

  /// No description provided for @thinkOffToast.
  ///
  /// In en, this message translates to:
  /// **'Thinking off'**
  String get thinkOffToast;

  /// No description provided for @attachTooltip.
  ///
  /// In en, this message translates to:
  /// **'Attach a photo or file, or choose tools'**
  String get attachTooltip;

  /// No description provided for @dictate.
  ///
  /// In en, this message translates to:
  /// **'Dictate'**
  String get dictate;

  /// No description provided for @stopDictation.
  ///
  /// In en, this message translates to:
  /// **'Stop dictation'**
  String get stopDictation;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get send;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop generation'**
  String get stop;

  /// No description provided for @modelPill.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get modelPill;

  /// No description provided for @webLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get webLocal;

  /// No description provided for @webAuto.
  ///
  /// In en, this message translates to:
  /// **'auto'**
  String get webAuto;

  /// No description provided for @webAlways.
  ///
  /// In en, this message translates to:
  /// **'always'**
  String get webAlways;

  /// No description provided for @emptyTitle.
  ///
  /// In en, this message translates to:
  /// **'A little more intelligence.\nA lot more privacy.'**
  String get emptyTitle;

  /// No description provided for @emptyHasModel.
  ///
  /// In en, this message translates to:
  /// **'Your model is here, running entirely on this device. Ask it anything.'**
  String get emptyHasModel;

  /// No description provided for @emptyRemote.
  ///
  /// In en, this message translates to:
  /// **'Answers come from your remote server ({host}); your messages are sent there. Ask it anything.'**
  String emptyRemote(String host);

  /// No description provided for @emptyNoModel.
  ///
  /// In en, this message translates to:
  /// **'No model yet. Open Models to download a starter or import your own GGUF, then come back and ask anything.'**
  String get emptyNoModel;

  /// No description provided for @askPhoto.
  ///
  /// In en, this message translates to:
  /// **'Ask about a photo'**
  String get askPhoto;

  /// No description provided for @askFile.
  ///
  /// In en, this message translates to:
  /// **'Ask about a file'**
  String get askFile;

  /// No description provided for @generating.
  ///
  /// In en, this message translates to:
  /// **'generating…'**
  String get generating;

  /// No description provided for @runDetails.
  ///
  /// In en, this message translates to:
  /// **'How this was made'**
  String get runDetails;

  /// No description provided for @answerWarning.
  ///
  /// In en, this message translates to:
  /// **'What the source check doubted'**
  String get answerWarning;

  /// No description provided for @copyRunDetails.
  ///
  /// In en, this message translates to:
  /// **'Copy run details'**
  String get copyRunDetails;

  /// No description provided for @runDetailsCopied.
  ///
  /// In en, this message translates to:
  /// **'Run details copied'**
  String get runDetailsCopied;

  /// No description provided for @runMeasured.
  ///
  /// In en, this message translates to:
  /// **'MEASURED'**
  String get runMeasured;

  /// No description provided for @runSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings in force'**
  String get runSettings;

  /// No description provided for @runEngine.
  ///
  /// In en, this message translates to:
  /// **'ENGINE'**
  String get runEngine;

  /// No description provided for @copyResponse.
  ///
  /// In en, this message translates to:
  /// **'Copy response'**
  String get copyResponse;

  /// No description provided for @copyQuestion.
  ///
  /// In en, this message translates to:
  /// **'Copy question'**
  String get copyQuestion;

  /// No description provided for @responseCopied.
  ///
  /// In en, this message translates to:
  /// **'Response copied'**
  String get responseCopied;

  /// No description provided for @readAloud.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get readAloud;

  /// No description provided for @stopReading.
  ///
  /// In en, this message translates to:
  /// **'Stop reading'**
  String get stopReading;

  /// No description provided for @regenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate (keeps this answer as an earlier version)'**
  String get regenerate;

  /// No description provided for @continueAnswer.
  ///
  /// In en, this message translates to:
  /// **'Continue this answer'**
  String get continueAnswer;

  /// No description provided for @compareWith.
  ///
  /// In en, this message translates to:
  /// **'Compare with another model'**
  String get compareWith;

  /// No description provided for @editQuestion.
  ///
  /// In en, this message translates to:
  /// **'Edit question'**
  String get editQuestion;

  /// No description provided for @askAgain.
  ///
  /// In en, this message translates to:
  /// **'Ask again'**
  String get askAgain;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @earlierQuestion.
  ///
  /// In en, this message translates to:
  /// **'Earlier question'**
  String get earlierQuestion;

  /// No description provided for @earlierAnswer.
  ///
  /// In en, this message translates to:
  /// **'Earlier answer'**
  String get earlierAnswer;

  /// No description provided for @restoreBranch.
  ///
  /// In en, this message translates to:
  /// **'Restore this branch'**
  String get restoreBranch;

  /// No description provided for @stoppedPartial.
  ///
  /// In en, this message translates to:
  /// **'Stopped · partial response'**
  String get stoppedPartial;

  /// No description provided for @interruptedClosed.
  ///
  /// In en, this message translates to:
  /// **'Interrupted · the app closed before the answer finished'**
  String get interruptedClosed;

  /// No description provided for @interruptedPartial.
  ///
  /// In en, this message translates to:
  /// **'Interrupted · partial response'**
  String get interruptedPartial;

  /// No description provided for @interruptedError.
  ///
  /// In en, this message translates to:
  /// **'Interrupted by an error'**
  String get interruptedError;

  /// No description provided for @searchConversations.
  ///
  /// In en, this message translates to:
  /// **'Search conversations'**
  String get searchConversations;

  /// No description provided for @storedOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Stored only on this device'**
  String get storedOnDevice;

  /// No description provided for @noConversations.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet.\nYour chats will appear here.'**
  String get noConversations;

  /// No description provided for @nothingMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches “{query}”.'**
  String nothingMatches(String query);

  /// No description provided for @pinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinned;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @earlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get earlier;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow the phone'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageFrench.
  ///
  /// In en, this message translates to:
  /// **'Français'**
  String get languageFrench;

  /// No description provided for @languageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get languageSpanish;

  /// No description provided for @resetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get resetToDefaults;

  /// No description provided for @sectionAssistant.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get sectionAssistant;

  /// No description provided for @thinkingMode.
  ///
  /// In en, this message translates to:
  /// **'Thinking mode'**
  String get thinkingMode;

  /// No description provided for @thinkingModeHint.
  ///
  /// In en, this message translates to:
  /// **'Show model-generated reasoning when supported. It may contain mistakes and is not proof of correctness.'**
  String get thinkingModeHint;

  /// No description provided for @webResearch.
  ///
  /// In en, this message translates to:
  /// **'Web research (keyless)'**
  String get webResearch;

  /// No description provided for @webOffHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing leaves the phone.'**
  String get webOffHint;

  /// No description provided for @webAutoHint.
  ///
  /// In en, this message translates to:
  /// **'The question goes to DuckDuckGo and result pages are fetched when the message needs it.'**
  String get webAutoHint;

  /// No description provided for @webAlwaysHint.
  ///
  /// In en, this message translates to:
  /// **'Every message is researched first. Slower, always current.'**
  String get webAlwaysHint;

  /// No description provided for @knowledgeLibrary.
  ///
  /// In en, this message translates to:
  /// **'Knowledge library'**
  String get knowledgeLibrary;

  /// No description provided for @knowledgeOff.
  ///
  /// In en, this message translates to:
  /// **'Off · your documents, cited in answers when active'**
  String get knowledgeOff;

  /// No description provided for @knowledgeOn.
  ///
  /// In en, this message translates to:
  /// **'On · {collection}'**
  String knowledgeOn(Object collection);

  /// No description provided for @memory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memory;

  /// No description provided for @memoryOnHint.
  ///
  /// In en, this message translates to:
  /// **'On · the assistant learns durable facts about you from chats'**
  String get memoryOnHint;

  /// No description provided for @memoryOffHint.
  ///
  /// In en, this message translates to:
  /// **'Off · nothing is remembered between chats'**
  String get memoryOffHint;

  /// No description provided for @readAloudSetting.
  ///
  /// In en, this message translates to:
  /// **'Read answers aloud'**
  String get readAloudSetting;

  /// No description provided for @readAloudHint.
  ///
  /// In en, this message translates to:
  /// **'Every finished answer is spoken with the phone\'s text-to-speech voice. The speaker icon on an answer reads it on demand either way.'**
  String get readAloudHint;

  /// No description provided for @dictationOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Dictation stays on the phone'**
  String get dictationOnDevice;

  /// No description provided for @dictationOnDeviceHint.
  ///
  /// In en, this message translates to:
  /// **'Use only the on-device recognizer (needs an offline language pack in the phone\'s speech settings). Off allows the network recognizer.'**
  String get dictationOnDeviceHint;

  /// No description provided for @customInstructions.
  ///
  /// In en, this message translates to:
  /// **'Custom system instructions'**
  String get customInstructions;

  /// No description provided for @customInstructionsHint.
  ///
  /// In en, this message translates to:
  /// **'Add preferences for your assistant'**
  String get customInstructionsHint;

  /// No description provided for @sectionModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get sectionModel;

  /// No description provided for @remoteServer.
  ///
  /// In en, this message translates to:
  /// **'Remote server'**
  String get remoteServer;

  /// No description provided for @sectionAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get sectionAdvanced;

  /// No description provided for @contextAndBatch.
  ///
  /// In en, this message translates to:
  /// **'Context & batch'**
  String get contextAndBatch;

  /// No description provided for @hardware.
  ///
  /// In en, this message translates to:
  /// **'Hardware'**
  String get hardware;

  /// No description provided for @sampling.
  ///
  /// In en, this message translates to:
  /// **'Sampling'**
  String get sampling;

  /// No description provided for @reasoningAndSearch.
  ///
  /// In en, this message translates to:
  /// **'Reasoning & search'**
  String get reasoningAndSearch;

  /// No description provided for @sectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get sectionAbout;

  /// No description provided for @openSourceMit.
  ///
  /// In en, this message translates to:
  /// **'Open source · MIT'**
  String get openSourceMit;

  /// No description provided for @builtOnLlama.
  ///
  /// In en, this message translates to:
  /// **'Built on llama.cpp'**
  String get builtOnLlama;

  /// No description provided for @builtOnLlamaHint.
  ///
  /// In en, this message translates to:
  /// **'Inference engine by the ggml project'**
  String get builtOnLlamaHint;

  /// No description provided for @openSourceLicences.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get openSourceLicences;

  /// No description provided for @openSourceLicencesHint.
  ///
  /// In en, this message translates to:
  /// **'Packages, models and voices, with their licences'**
  String get openSourceLicencesHint;

  /// No description provided for @resetQuestion.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults?'**
  String get resetQuestion;

  /// No description provided for @resetHint.
  ///
  /// In en, this message translates to:
  /// **'All assistant, model and advanced settings return to the defaults for this device. Your chats are not affected.'**
  String get resetHint;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @enableWebQuestion.
  ///
  /// In en, this message translates to:
  /// **'Enable web search?'**
  String get enableWebQuestion;

  /// No description provided for @enableWebHint.
  ///
  /// In en, this message translates to:
  /// **'The question is sent to DuckDuckGo and result pages are fetched directly from their websites (they see your IP address). No account or key is used; conversations, model and settings stay local.'**
  String get enableWebHint;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @systemInstructions.
  ///
  /// In en, this message translates to:
  /// **'System instructions'**
  String get systemInstructions;

  /// No description provided for @systemInstructionsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Answer briefly. Prefer metric units.'**
  String get systemInstructionsHint;

  /// No description provided for @couldNotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open this link.'**
  String get couldNotOpenLink;

  /// No description provided for @privateByDefault.
  ///
  /// In en, this message translates to:
  /// **'Private by default'**
  String get privateByDefault;

  /// No description provided for @privateByDefaultHint.
  ///
  /// In en, this message translates to:
  /// **'No accounts, analytics or cloud inference. Downloads and optional search are the only network features.'**
  String get privateByDefaultHint;

  /// No description provided for @noModelLoadedTitle.
  ///
  /// In en, this message translates to:
  /// **'No model loaded'**
  String get noModelLoadedTitle;

  /// No description provided for @chooseFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Choose one from the library'**
  String get chooseFromLibrary;

  /// No description provided for @obPrivateHeadline.
  ///
  /// In en, this message translates to:
  /// **'Private by construction'**
  String get obPrivateHeadline;

  /// No description provided for @obPrivateBody.
  ///
  /// In en, this message translates to:
  /// **'A language model that runs on your phone’s own chip. There is no server on the other end.'**
  String get obPrivateBody;

  /// No description provided for @obNoAccount.
  ///
  /// In en, this message translates to:
  /// **'No account'**
  String get obNoAccount;

  /// No description provided for @obNoAccountHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing to sign up for, nothing to log in to.'**
  String get obNoAccountHint;

  /// No description provided for @obNoCloud.
  ///
  /// In en, this message translates to:
  /// **'No cloud'**
  String get obNoCloud;

  /// No description provided for @obNoCloudHint.
  ///
  /// In en, this message translates to:
  /// **'Every answer is computed here. Airplane mode works.'**
  String get obNoCloudHint;

  /// No description provided for @obStaysHere.
  ///
  /// In en, this message translates to:
  /// **'Models and chats stay on this phone'**
  String get obStaysHere;

  /// No description provided for @obStaysHereHint.
  ///
  /// In en, this message translates to:
  /// **'Delete the app and every byte goes with it.'**
  String get obStaysHereHint;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @obPickModel.
  ///
  /// In en, this message translates to:
  /// **'Pick a starter model'**
  String get obPickModel;

  /// No description provided for @phoneRamUnknown.
  ///
  /// In en, this message translates to:
  /// **'This phone · RAM unknown'**
  String get phoneRamUnknown;

  /// No description provided for @phoneRam.
  ///
  /// In en, this message translates to:
  /// **'This phone · {gb} GB RAM'**
  String phoneRam(Object gb);

  /// No description provided for @recommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommended;

  /// No description provided for @orChooseAnother.
  ///
  /// In en, this message translates to:
  /// **'Or choose another'**
  String get orChooseAnother;

  /// No description provided for @acknowledgeLicense.
  ///
  /// In en, this message translates to:
  /// **'I acknowledge the publisher’s model license'**
  String get acknowledgeLicense;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @obReady.
  ///
  /// In en, this message translates to:
  /// **'Ready.'**
  String get obReady;

  /// No description provided for @startChatting.
  ///
  /// In en, this message translates to:
  /// **'Start chatting'**
  String get startChatting;

  /// No description provided for @downloadInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Download interrupted'**
  String get downloadInterrupted;

  /// No description provided for @downloadInterruptedHint.
  ///
  /// In en, this message translates to:
  /// **'You can retry now, or skip and download later from the model library. The app works without a model, it just cannot answer yet.'**
  String get downloadInterruptedHint;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @skipForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get skipForNow;

  /// No description provided for @verifyingSha.
  ///
  /// In en, this message translates to:
  /// **'Verifying SHA-256…'**
  String get verifyingSha;

  /// No description provided for @pausedOf.
  ///
  /// In en, this message translates to:
  /// **'Paused · {received} of {size}'**
  String pausedOf(Object received, Object size);

  /// No description provided for @starting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get starting;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get downloading;

  /// No description provided for @downloadingHint.
  ///
  /// In en, this message translates to:
  /// **'Keep the app open. You can pause and resume; the file is checked against the publisher’s SHA-256 when it finishes.'**
  String get downloadingHint;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @verifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying…'**
  String get verifying;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @presets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get presets;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newLabel;

  /// No description provided for @noExtraInstructions.
  ///
  /// In en, this message translates to:
  /// **'No extra instructions'**
  String get noExtraInstructions;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @presetsHint.
  ///
  /// In en, this message translates to:
  /// **'A preset adds its instructions to yours and can override temperature, thinking and web mode. Built-ins can be duplicated and edited.'**
  String get presetsHint;

  /// No description provided for @newPreset.
  ///
  /// In en, this message translates to:
  /// **'New preset'**
  String get newPreset;

  /// No description provided for @editPreset.
  ///
  /// In en, this message translates to:
  /// **'Edit preset'**
  String get editPreset;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @instructions.
  ///
  /// In en, this message translates to:
  /// **'Instructions'**
  String get instructions;

  /// No description provided for @instructionsHint.
  ///
  /// In en, this message translates to:
  /// **'How should the assistant behave?'**
  String get instructionsHint;

  /// No description provided for @temperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get temperature;

  /// No description provided for @useSetting.
  ///
  /// In en, this message translates to:
  /// **'Use setting'**
  String get useSetting;

  /// No description provided for @thinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get thinking;

  /// No description provided for @on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get on;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @webResearchShort.
  ///
  /// In en, this message translates to:
  /// **'Web research'**
  String get webResearchShort;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @pinToTop.
  ///
  /// In en, this message translates to:
  /// **'Pin to top'**
  String get pinToTop;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @moveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get moveToFolder;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @renameConversation.
  ///
  /// In en, this message translates to:
  /// **'Rename conversation'**
  String get renameConversation;

  /// No description provided for @tagsCommaSeparated.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma-separated)'**
  String get tagsCommaSeparated;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder…'**
  String get newFolder;

  /// No description provided for @removeFromFolder.
  ///
  /// In en, this message translates to:
  /// **'Remove from folder'**
  String get removeFromFolder;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @deleteConversationQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation?'**
  String get deleteConversationQuestion;

  /// No description provided for @keep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// No description provided for @couldNotDelete.
  ///
  /// In en, this message translates to:
  /// **'Could not delete: {error}'**
  String couldNotDelete(Object error);

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @knowledgeIntro.
  ///
  /// In en, this message translates to:
  /// **'Import documents once — PDF, Word, text, code, EPUB… — and every question is answered with the best-matching passages from the active collection, cited like web sources. Retrieval runs entirely on the phone: full-text ranking, plus meaning once the embedding model is downloaded.'**
  String get knowledgeIntro;

  /// No description provided for @newCollection.
  ///
  /// In en, this message translates to:
  /// **'New collection'**
  String get newCollection;

  /// No description provided for @useInChats.
  ///
  /// In en, this message translates to:
  /// **'Use in chats'**
  String get useInChats;

  /// No description provided for @collectionOff.
  ///
  /// In en, this message translates to:
  /// **'Off — no collection consulted'**
  String get collectionOff;

  /// No description provided for @collectionActive.
  ///
  /// In en, this message translates to:
  /// **'Active: {collection}'**
  String collectionActive(Object collection);

  /// No description provided for @readingAndIndexing.
  ///
  /// In en, this message translates to:
  /// **'Reading and indexing…'**
  String get readingAndIndexing;

  /// No description provided for @noCollections.
  ///
  /// In en, this message translates to:
  /// **'No collections yet. Create one with the folder icon, then add files.'**
  String get noCollections;

  /// No description provided for @addFiles.
  ///
  /// In en, this message translates to:
  /// **'Add files'**
  String get addFiles;

  /// No description provided for @deleteCollection.
  ///
  /// In en, this message translates to:
  /// **'Delete collection'**
  String get deleteCollection;

  /// No description provided for @searchByMeaning.
  ///
  /// In en, this message translates to:
  /// **'Search by meaning'**
  String get searchByMeaning;

  /// No description provided for @ready.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get ready;

  /// No description provided for @indexForMeaning.
  ///
  /// In en, this message translates to:
  /// **'Index {count} passages for meaning'**
  String indexForMeaning(Object count);

  /// No description provided for @indexingProgress.
  ///
  /// In en, this message translates to:
  /// **'Indexing for meaning… {done}/{total}'**
  String indexingProgress(Object done, Object total);

  /// No description provided for @downloadMb.
  ///
  /// In en, this message translates to:
  /// **'Download · {mb} MB'**
  String downloadMb(Object mb);

  /// No description provided for @addMemory.
  ///
  /// In en, this message translates to:
  /// **'Add a memory'**
  String get addMemory;

  /// No description provided for @editMemory.
  ///
  /// In en, this message translates to:
  /// **'Edit memory'**
  String get editMemory;

  /// No description provided for @forgetEverything.
  ///
  /// In en, this message translates to:
  /// **'Forget everything'**
  String get forgetEverything;

  /// No description provided for @forgetEverythingQuestion.
  ///
  /// In en, this message translates to:
  /// **'Forget everything?'**
  String get forgetEverythingQuestion;

  /// No description provided for @forgetEverythingHint.
  ///
  /// In en, this message translates to:
  /// **'All {count} remembered facts will be deleted. Chats are not affected.'**
  String forgetEverythingHint(Object count);

  /// No description provided for @forget.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get forget;

  /// No description provided for @rememberAboutMe.
  ///
  /// In en, this message translates to:
  /// **'Remember things about me'**
  String get rememberAboutMe;

  /// No description provided for @rememberAboutMeHint.
  ///
  /// In en, this message translates to:
  /// **'Remember durable facts you share, such as your job and preferences. Notes are saved on this device. Remote sharing and model extraction require the connection’s opt-in. You can edit or forget notes below.'**
  String get rememberAboutMeHint;

  /// No description provided for @memoryStorageHint.
  ///
  /// In en, this message translates to:
  /// **'Notes are stored on this device. Each remote connection needs separate permission to receive or learn them.'**
  String get memoryStorageHint;

  /// No description provided for @memoryRemoteLocalHint.
  ///
  /// In en, this message translates to:
  /// **'Clear statements such as your job or name can be saved locally when Memory is on. Enable sharing to let this connection use your notes, and learning to extract other durable facts.'**
  String get memoryRemoteLocalHint;

  /// No description provided for @whatAssistantRemembers.
  ///
  /// In en, this message translates to:
  /// **'What the assistant remembers'**
  String get whatAssistantRemembers;

  /// No description provided for @nothingYetFills.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet. It fills in as you chat.'**
  String get nothingYetFills;

  /// No description provided for @nothingStoredSwitch.
  ///
  /// In en, this message translates to:
  /// **'Nothing stored. Turn the switch on, or add facts by hand with +.'**
  String get nothingStoredSwitch;

  /// No description provided for @switchModel.
  ///
  /// In en, this message translates to:
  /// **'Switch model'**
  String get switchModel;

  /// No description provided for @nothingOnPhone.
  ///
  /// In en, this message translates to:
  /// **'Nothing is on this phone yet.'**
  String get nothingOnPhone;

  /// No description provided for @modelsOnPhone.
  ///
  /// In en, this message translates to:
  /// **'Models on this phone. The active one answers your chats.'**
  String get modelsOnPhone;

  /// No description provided for @modelUnloaded.
  ///
  /// In en, this message translates to:
  /// **'Model unloaded. It loads again on your next message.'**
  String get modelUnloaded;

  /// No description provided for @unloadModel.
  ///
  /// In en, this message translates to:
  /// **'Unload model · free memory'**
  String get unloadModel;

  /// No description provided for @openModelLibrary.
  ///
  /// In en, this message translates to:
  /// **'Open model library'**
  String get openModelLibrary;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @pickerEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Download a model from the library, or import a GGUF you already own. Chats need one model loaded; everything stays on this phone.'**
  String get pickerEmptyHint;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get takePhoto;

  /// No description provided for @attachCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get attachCamera;

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get attachFile;

  /// No description provided for @attachGoalShort.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get attachGoalShort;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @photosHint.
  ///
  /// In en, this message translates to:
  /// **'JPEG, PNG, WebP, HEIC…'**
  String get photosHint;

  /// No description provided for @documentOrFile.
  ///
  /// In en, this message translates to:
  /// **'Document or file'**
  String get documentOrFile;

  /// No description provided for @documentHint.
  ///
  /// In en, this message translates to:
  /// **'PDF, Word, PowerPoint, Excel, OpenDocument, EPUB, RTF, text, code, CSV, JSON, HTML…'**
  String get documentHint;

  /// No description provided for @couldNotOpenPicker.
  ///
  /// In en, this message translates to:
  /// **'Could not open the picker: {error}'**
  String couldNotOpenPicker(Object error);

  /// No description provided for @readingAttachments.
  ///
  /// In en, this message translates to:
  /// **'Reading attachments…'**
  String get readingAttachments;

  /// No description provided for @turnOnWebQuestion.
  ///
  /// In en, this message translates to:
  /// **'Turn on web search?'**
  String get turnOnWebQuestion;

  /// No description provided for @turnOnWebHint.
  ///
  /// In en, this message translates to:
  /// **'When you paste a link, ask to search, or a question looks time-sensitive, the question is sent to DuckDuckGo and result pages (three by default, Settings > Reasoning & search) are fetched directly from their websites (they see your IP address). With local inference, everything else stays on this device. If Remote server is enabled, the question and supplied context are also sent to that server.'**
  String get turnOnWebHint;

  /// No description provided for @stayLocal.
  ///
  /// In en, this message translates to:
  /// **'Stay local'**
  String get stayLocal;

  /// No description provided for @turnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get turnOn;

  /// No description provided for @compareWithTitle.
  ///
  /// In en, this message translates to:
  /// **'Compare with…'**
  String get compareWithTitle;

  /// No description provided for @compareHint.
  ///
  /// In en, this message translates to:
  /// **'The same question and evidence, answered by another model. Shown beside this answer; not part of the conversation.'**
  String get compareHint;

  /// No description provided for @shareFailed.
  ///
  /// In en, this message translates to:
  /// **'Share failed: {error}'**
  String shareFailed(Object error);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(Object error);

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @licenseLabel.
  ///
  /// In en, this message translates to:
  /// **'License · {license}'**
  String licenseLabel(Object license);

  /// No description provided for @resumeRetry.
  ///
  /// In en, this message translates to:
  /// **'Resume / retry'**
  String get resumeRetry;

  /// No description provided for @useModel.
  ///
  /// In en, this message translates to:
  /// **'Use model'**
  String get useModel;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @benchmark.
  ///
  /// In en, this message translates to:
  /// **'Benchmark'**
  String get benchmark;

  /// No description provided for @visionPercent.
  ///
  /// In en, this message translates to:
  /// **'Vision {percent}%'**
  String visionPercent(Object percent);

  /// No description provided for @verifyingVision.
  ///
  /// In en, this message translates to:
  /// **'Verifying vision…'**
  String get verifyingVision;

  /// No description provided for @visionReady.
  ///
  /// In en, this message translates to:
  /// **'Vision ready'**
  String get visionReady;

  /// No description provided for @addVisionMb.
  ///
  /// In en, this message translates to:
  /// **'Add vision · {mb} MB'**
  String addVisionMb(Object mb);

  /// No description provided for @addFromHf.
  ///
  /// In en, this message translates to:
  /// **'Add from Hugging Face'**
  String get addFromHf;

  /// No description provided for @importGguf.
  ///
  /// In en, this message translates to:
  /// **'Import a GGUF'**
  String get importGguf;

  /// No description provided for @addFromHfHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the link to a public, single GGUF file. Its size, checksum and license will be shown before you download.'**
  String get addFromHfHint;

  /// No description provided for @importGgufHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a GGUF you downloaded yourself. It will be copied into your private model library; allow enough space for a second copy.'**
  String get importGgufHint;

  /// No description provided for @ggufLink.
  ///
  /// In en, this message translates to:
  /// **'GGUF file link'**
  String get ggufLink;

  /// No description provided for @templateFallback.
  ///
  /// In en, this message translates to:
  /// **'Template fallback'**
  String get templateFallback;

  /// No description provided for @automaticMetadata.
  ///
  /// In en, this message translates to:
  /// **'Automatic (model metadata)'**
  String get automaticMetadata;

  /// No description provided for @ggufWarning.
  ///
  /// In en, this message translates to:
  /// **'Text-generation models only. A GGUF may require more RAM than its download size. New architectures and split files may not be supported.'**
  String get ggufWarning;

  /// No description provided for @checkModel.
  ///
  /// In en, this message translates to:
  /// **'Check model'**
  String get checkModel;

  /// No description provided for @chooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get chooseFile;

  /// No description provided for @checkingMetadata.
  ///
  /// In en, this message translates to:
  /// **'Checking model metadata…'**
  String get checkingMetadata;

  /// No description provided for @downloadQuestion.
  ///
  /// In en, this message translates to:
  /// **'Download {model}?'**
  String downloadQuestion(Object model);

  /// No description provided for @modelCard.
  ///
  /// In en, this message translates to:
  /// **'Model card'**
  String get modelCard;

  /// No description provided for @removeModelQuestion.
  ///
  /// In en, this message translates to:
  /// **'Remove this model?'**
  String get removeModelQuestion;

  /// No description provided for @removeModelHint.
  ///
  /// In en, this message translates to:
  /// **'Delete {model} from this app and free {size}? Your chats will be kept.'**
  String removeModelHint(Object model, Object size);

  /// No description provided for @browseHf.
  ///
  /// In en, this message translates to:
  /// **'Browse Hugging Face'**
  String get browseHf;

  /// No description provided for @yourModelLibrary.
  ///
  /// In en, this message translates to:
  /// **'Your model library'**
  String get yourModelLibrary;

  /// No description provided for @libraryHint.
  ///
  /// In en, this message translates to:
  /// **'Download a starter model, add a Hugging Face file link, or import a GGUF you already own. After download, inference works offline.'**
  String get libraryHint;

  /// No description provided for @searchHf.
  ///
  /// In en, this message translates to:
  /// **'Search Hugging Face'**
  String get searchHf;

  /// No description provided for @pasteLink.
  ///
  /// In en, this message translates to:
  /// **'Paste link'**
  String get pasteLink;

  /// No description provided for @importGgufButton.
  ///
  /// In en, this message translates to:
  /// **'Import GGUF'**
  String get importGgufButton;

  /// No description provided for @checkingCopying.
  ///
  /// In en, this message translates to:
  /// **'Checking and copying model…'**
  String get checkingCopying;

  /// No description provided for @preparingLibrary.
  ///
  /// In en, this message translates to:
  /// **'Preparing your library…'**
  String get preparingLibrary;

  /// No description provided for @onThisDevice.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get onThisDevice;

  /// No description provided for @nothingDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Nothing downloaded yet. Pick a model below to get started.'**
  String get nothingDownloaded;

  /// No description provided for @availableToDownload.
  ///
  /// In en, this message translates to:
  /// **'Available to download'**
  String get availableToDownload;

  /// No description provided for @everythingOnPhone.
  ///
  /// In en, this message translates to:
  /// **'Everything in the catalog is on this phone.'**
  String get everythingOnPhone;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} min ago'**
  String minutesAgo(Object n);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} h ago'**
  String hoursAgo(Object n);

  /// No description provided for @webModeOff.
  ///
  /// In en, this message translates to:
  /// **'Off · stays local'**
  String get webModeOff;

  /// No description provided for @webModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto · links, search requests and timely questions'**
  String get webModeAuto;

  /// No description provided for @webModeAlways.
  ///
  /// In en, this message translates to:
  /// **'Always · research every message'**
  String get webModeAlways;

  /// No description provided for @rememberedOne.
  ///
  /// In en, this message translates to:
  /// **'Remembered: {fact}'**
  String rememberedOne(Object fact);

  /// No description provided for @rememberedMore.
  ///
  /// In en, this message translates to:
  /// **'Remembered: {fact} (+{more})'**
  String rememberedMore(Object fact, Object more);

  /// No description provided for @reviewMemory.
  ///
  /// In en, this message translates to:
  /// **'Review what was remembered'**
  String get reviewMemory;

  /// No description provided for @memoryDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memoryDialogTitle;

  /// No description provided for @memoryDialogHint.
  ///
  /// In en, this message translates to:
  /// **'Memory keeps short facts you state about yourself so later chats already know them. It is stored only on this phone and you can change it any time under Settings > Memory. Here is what was just noted — edit it, keep it, or discard it.'**
  String get memoryDialogHint;

  /// No description provided for @memoryDialogFieldHint.
  ///
  /// In en, this message translates to:
  /// **'One fact per line; empty lines are deleted'**
  String get memoryDialogFieldHint;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @goalDescribeFirst.
  ///
  /// In en, this message translates to:
  /// **'Describe the goal first.'**
  String get goalDescribeFirst;

  /// No description provided for @goalLimitsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter positive step, time, token and tool limits.'**
  String get goalLimitsInvalid;

  /// No description provided for @goalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get goalsTitle;

  /// No description provided for @goalIntro.
  ///
  /// In en, this message translates to:
  /// **'Give the model a goal. It plans the questions to research, looks each one up, checks the findings against your criteria, fills the gaps, and writes a cited report.'**
  String get goalIntro;

  /// No description provided for @goalWebOff.
  ///
  /// In en, this message translates to:
  /// **'Web research is off, so the goal can only use what the model already knows. Turn it on with the globe pill in the chat composer for sourced research.'**
  String get goalWebOff;

  /// No description provided for @goalLabel.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get goalLabel;

  /// No description provided for @goalExample.
  ///
  /// In en, this message translates to:
  /// **'Compare the three most popular electric cars in Canada for a family of four'**
  String get goalExample;

  /// No description provided for @goalKindTitle.
  ///
  /// In en, this message translates to:
  /// **'Kind of research'**
  String get goalKindTitle;

  /// No description provided for @goalCriteriaLabel.
  ///
  /// In en, this message translates to:
  /// **'What a good result includes (optional)'**
  String get goalCriteriaLabel;

  /// No description provided for @goalBudgetTitle.
  ///
  /// In en, this message translates to:
  /// **'How much work'**
  String get goalBudgetTitle;

  /// No description provided for @goalMaxSteps.
  ///
  /// In en, this message translates to:
  /// **'Maximum research steps'**
  String get goalMaxSteps;

  /// No description provided for @goalMaxMinutes.
  ///
  /// In en, this message translates to:
  /// **'Maximum minutes'**
  String get goalMaxMinutes;

  /// No description provided for @goalMaxTokens.
  ///
  /// In en, this message translates to:
  /// **'Approximate token budget'**
  String get goalMaxTokens;

  /// No description provided for @goalMaxToolCalls.
  ///
  /// In en, this message translates to:
  /// **'Maximum tool calls'**
  String get goalMaxToolCalls;

  /// No description provided for @goalKeepOpen.
  ///
  /// In en, this message translates to:
  /// **'Keep the app open: Android may stop it in the background. Progress is saved after every step.'**
  String get goalKeepOpen;

  /// No description provided for @goalStart.
  ///
  /// In en, this message translates to:
  /// **'Start goal'**
  String get goalStart;

  /// No description provided for @goalBudgetQuick.
  ///
  /// In en, this message translates to:
  /// **'Quick'**
  String get goalBudgetQuick;

  /// No description provided for @goalBudgetQuickHint.
  ///
  /// In en, this message translates to:
  /// **'About 4 searches · up to 10 min'**
  String get goalBudgetQuickHint;

  /// No description provided for @goalBudgetStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get goalBudgetStandard;

  /// No description provided for @goalBudgetStandardHint.
  ///
  /// In en, this message translates to:
  /// **'About 8 searches · up to 30 min'**
  String get goalBudgetStandardHint;

  /// No description provided for @goalBudgetDeep.
  ///
  /// In en, this message translates to:
  /// **'Deep'**
  String get goalBudgetDeep;

  /// No description provided for @goalBudgetDeepHint.
  ///
  /// In en, this message translates to:
  /// **'About 14 searches · up to 60 min'**
  String get goalBudgetDeepHint;

  /// No description provided for @goalBudgetUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get goalBudgetUnlimited;

  /// No description provided for @goalBudgetUnlimitedHint.
  ///
  /// In en, this message translates to:
  /// **'Until done, paused or stopped'**
  String get goalBudgetUnlimitedHint;

  /// No description provided for @goalBudgetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get goalBudgetCustom;

  /// No description provided for @goalBudgetCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Set your own limits'**
  String get goalBudgetCustomHint;

  /// No description provided for @goalPhasePlanning.
  ///
  /// In en, this message translates to:
  /// **'Planning the research'**
  String get goalPhasePlanning;

  /// No description provided for @goalPhaseResearching.
  ///
  /// In en, this message translates to:
  /// **'Researching'**
  String get goalPhaseResearching;

  /// No description provided for @goalPhaseChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking the findings against your criteria'**
  String get goalPhaseChecking;

  /// No description provided for @goalPhaseWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing the report'**
  String get goalPhaseWriting;

  /// No description provided for @goalPhaseDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get goalPhaseDone;

  /// No description provided for @goalPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get goalPaused;

  /// No description provided for @goalPausedBudget.
  ///
  /// In en, this message translates to:
  /// **'Paused — the budget is used up'**
  String get goalPausedBudget;

  /// No description provided for @goalCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get goalCompleted;

  /// No description provided for @goalStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get goalStopped;

  /// No description provided for @goalFailed.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get goalFailed;

  /// No description provided for @goalReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get goalReady;

  /// No description provided for @goalStepsOf.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total, plural, =1{1 step} other{{total} steps}}'**
  String goalStepsOf(int done, int total);

  /// No description provided for @goalSources.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 source} other{{count} sources}}'**
  String goalSources(int count);

  /// No description provided for @goalTokensWord.
  ///
  /// In en, this message translates to:
  /// **'tokens'**
  String get goalTokensWord;

  /// No description provided for @goalToolCallsWord.
  ///
  /// In en, this message translates to:
  /// **'tool calls'**
  String get goalToolCallsWord;

  /// No description provided for @goalPauseAfterStep.
  ///
  /// In en, this message translates to:
  /// **'Pause after this step'**
  String get goalPauseAfterStep;

  /// No description provided for @goalStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get goalStop;

  /// No description provided for @goalContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get goalContinue;

  /// No description provided for @goalOpenChat.
  ///
  /// In en, this message translates to:
  /// **'Open chat'**
  String get goalOpenChat;

  /// No description provided for @goalNew.
  ///
  /// In en, this message translates to:
  /// **'New goal'**
  String get goalNew;

  /// No description provided for @goalHowMade.
  ///
  /// In en, this message translates to:
  /// **'How this report was made'**
  String get goalHowMade;

  /// No description provided for @goalPastTitle.
  ///
  /// In en, this message translates to:
  /// **'Past goals'**
  String get goalPastTitle;

  /// No description provided for @goalPastReopen.
  ///
  /// In en, this message translates to:
  /// **'Refine or continue'**
  String get goalPastReopen;

  /// No description provided for @drawerGoalsPast.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 past goal} other{{count} past goals}} · Start a new one'**
  String drawerGoalsPast(int count);

  /// No description provided for @goalReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get goalReport;

  /// No description provided for @goalInterimReport.
  ///
  /// In en, this message translates to:
  /// **'Interim report'**
  String get goalInterimReport;

  /// No description provided for @goalCopyReport.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get goalCopyReport;

  /// No description provided for @goalReportCopied.
  ///
  /// In en, this message translates to:
  /// **'Report copied'**
  String get goalReportCopied;

  /// No description provided for @goalPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get goalPlan;

  /// No description provided for @goalNotCovered.
  ///
  /// In en, this message translates to:
  /// **'Not covered by the report'**
  String get goalNotCovered;

  /// No description provided for @goalStillMissing.
  ///
  /// In en, this message translates to:
  /// **'Still missing'**
  String get goalStillMissing;

  /// No description provided for @goalSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get goalSourcesTitle;

  /// No description provided for @goalKindGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get goalKindGeneral;

  /// No description provided for @goalKindGeneralHint.
  ///
  /// In en, this message translates to:
  /// **'Any topic: a balanced, cited report'**
  String get goalKindGeneralHint;

  /// No description provided for @goalKindGeneralCriteria.
  ///
  /// In en, this message translates to:
  /// **'The goal answered completely, each claim with a source'**
  String get goalKindGeneralCriteria;

  /// No description provided for @goalKindCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get goalKindCode;

  /// No description provided for @goalKindCodeHint.
  ///
  /// In en, this message translates to:
  /// **'APIs, errors, libraries: working code and versions'**
  String get goalKindCodeHint;

  /// No description provided for @goalKindCodeCriteria.
  ///
  /// In en, this message translates to:
  /// **'A working approach with code, the versions it applies to and known pitfalls'**
  String get goalKindCodeCriteria;

  /// No description provided for @goalKindScience.
  ///
  /// In en, this message translates to:
  /// **'Scientific'**
  String get goalKindScience;

  /// No description provided for @goalKindScienceHint.
  ///
  /// In en, this message translates to:
  /// **'What the evidence says: studies, consensus, limits'**
  String get goalKindScienceHint;

  /// No description provided for @goalKindScienceCriteria.
  ///
  /// In en, this message translates to:
  /// **'The main findings with study type, year and size, where scientists agree and disagree, and the limitations'**
  String get goalKindScienceCriteria;

  /// No description provided for @goalKindMath.
  ///
  /// In en, this message translates to:
  /// **'Math'**
  String get goalKindMath;

  /// No description provided for @goalKindMathHint.
  ///
  /// In en, this message translates to:
  /// **'Definitions, derivations, checked results'**
  String get goalKindMathHint;

  /// No description provided for @goalKindMathCriteria.
  ///
  /// In en, this message translates to:
  /// **'The final result, every step of the derivation, and a check of the answer'**
  String get goalKindMathCriteria;

  /// No description provided for @goalKindNews.
  ///
  /// In en, this message translates to:
  /// **'Current events'**
  String get goalKindNews;

  /// No description provided for @goalKindNewsHint.
  ///
  /// In en, this message translates to:
  /// **'What happened, when, who says what'**
  String get goalKindNewsHint;

  /// No description provided for @goalKindNewsCriteria.
  ///
  /// In en, this message translates to:
  /// **'A dated timeline, the people and organisations involved, their positions, and what comes next'**
  String get goalKindNewsCriteria;

  /// No description provided for @goalKindProduct.
  ///
  /// In en, this message translates to:
  /// **'Product comparison'**
  String get goalKindProduct;

  /// No description provided for @goalKindProductHint.
  ///
  /// In en, this message translates to:
  /// **'Options side by side, then a pick'**
  String get goalKindProductHint;

  /// No description provided for @goalKindProductCriteria.
  ///
  /// In en, this message translates to:
  /// **'Price, key specifications, strengths and weaknesses of each option, and which suits whom'**
  String get goalKindProductCriteria;

  /// No description provided for @drawerGoalsHint.
  ///
  /// In en, this message translates to:
  /// **'Research with a plan and a cited report'**
  String get drawerGoalsHint;

  /// No description provided for @drawerGoalRunning.
  ///
  /// In en, this message translates to:
  /// **'Running · step {step} of {total}'**
  String drawerGoalRunning(int step, int total);

  /// No description provided for @drawerGoalReport.
  ///
  /// In en, this message translates to:
  /// **'Report ready · {goal}'**
  String drawerGoalReport(String goal);

  /// No description provided for @emptyGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Research a goal'**
  String get emptyGoalTitle;

  /// No description provided for @emptyGoalHint.
  ///
  /// In en, this message translates to:
  /// **'It plans the questions, researches each one and writes a cited report — for code, science, math, news or comparisons.'**
  String get emptyGoalHint;

  /// No description provided for @composerResearchGoal.
  ///
  /// In en, this message translates to:
  /// **'Research this as a goal'**
  String get composerResearchGoal;

  /// No description provided for @composerManageShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get composerManageShortcuts;

  /// No description provided for @shareNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to open in the share.'**
  String get shareNothing;

  /// No description provided for @scheduledWaiting.
  ///
  /// In en, this message translates to:
  /// **'Your scheduled prompt is in the message box.'**
  String get scheduledWaiting;

  /// No description provided for @shareMore.
  ///
  /// In en, this message translates to:
  /// **'Only the first 8 files were opened.'**
  String get shareMore;

  /// No description provided for @shareSkipped.
  ///
  /// In en, this message translates to:
  /// **'Not opened (empty or over 64 MB): {names}'**
  String shareSkipped(String names);

  /// No description provided for @attachGoal.
  ///
  /// In en, this message translates to:
  /// **'Research as a goal'**
  String get attachGoal;

  /// No description provided for @attachGoalHint.
  ///
  /// In en, this message translates to:
  /// **'A plan, several searches, a cited report'**
  String get attachGoalHint;

  /// No description provided for @batterySaver.
  ///
  /// In en, this message translates to:
  /// **'Battery saver'**
  String get batterySaver;

  /// No description provided for @batterySaverOff.
  ///
  /// In en, this message translates to:
  /// **'Lighter answers on this phone when the battery is low or it is hot'**
  String get batterySaverOff;

  /// No description provided for @batterySaverOn.
  ///
  /// In en, this message translates to:
  /// **'Below {level}% and not charging, or when the phone is hot: no thinking, shorter answers, fewer pages read'**
  String batterySaverOn(int level);

  /// No description provided for @batterySaverLevel.
  ///
  /// In en, this message translates to:
  /// **'Battery saver starts at'**
  String get batterySaverLevel;

  /// No description provided for @scheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Scheduled prompts'**
  String get scheduleTitle;

  /// No description provided for @scheduleRowHint.
  ///
  /// In en, this message translates to:
  /// **'A daily notification that asks a saved prompt when tapped'**
  String get scheduleRowHint;

  /// No description provided for @shortcutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Prompt shortcuts'**
  String get shortcutsTitle;

  /// No description provided for @shortcutsRowHint.
  ///
  /// In en, this message translates to:
  /// **'Type / in a message: /summarize, /translate fr, your own'**
  String get shortcutsRowHint;

  /// No description provided for @hostTitle.
  ///
  /// In en, this message translates to:
  /// **'Use this device as a server'**
  String get hostTitle;

  /// No description provided for @hostRowHint.
  ///
  /// In en, this message translates to:
  /// **'Share a loaded model with another device'**
  String get hostRowHint;

  /// No description provided for @shortcutNew.
  ///
  /// In en, this message translates to:
  /// **'New shortcut'**
  String get shortcutNew;

  /// No description provided for @shortcutsIntro.
  ///
  /// In en, this message translates to:
  /// **'Type / in the message box to pick one. \"/summarize\" followed by your text sends the saved prompt with the text in it; \"/translate fr …\" takes a language first.'**
  String get shortcutsIntro;

  /// No description provided for @shortcutBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'built-in'**
  String get shortcutBuiltIn;

  /// No description provided for @shortcutDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete /{name}'**
  String shortcutDelete(String name);

  /// No description provided for @shortcutNameRule.
  ///
  /// In en, this message translates to:
  /// **'Lower-case letters, digits and dashes, up to 24.'**
  String get shortcutNameRule;

  /// No description provided for @shortcutYourVersion.
  ///
  /// In en, this message translates to:
  /// **'Your version of /{name}'**
  String shortcutYourVersion(String name);

  /// No description provided for @shortcutEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit /{name}'**
  String shortcutEdit(String name);

  /// No description provided for @shortcutName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get shortcutName;

  /// No description provided for @shortcutDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get shortcutDescription;

  /// No description provided for @shortcutPrompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get shortcutPrompt;

  /// No description provided for @shortcutPromptHelp.
  ///
  /// In en, this message translates to:
  /// **'{token} is replaced by the text after the command; without it the text is added at the end.'**
  String shortcutPromptHelp(String token);

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @scheduleFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not set the reminder: {error}'**
  String scheduleFailed(String error);

  /// No description provided for @scheduleNeedsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications when Android asks, or the reminder cannot appear.'**
  String get scheduleNeedsNotifications;

  /// No description provided for @scheduleNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get scheduleNew;

  /// No description provided for @scheduleIntro.
  ///
  /// In en, this message translates to:
  /// **'Once a day at the time you choose, a notification offers the prompt. Tap it and the app asks it in a new chat (or opens it as a goal). Nothing runs in the background and nothing is sent until you tap.'**
  String get scheduleIntro;

  /// No description provided for @scheduleEmpty.
  ///
  /// In en, this message translates to:
  /// **'None yet. Try a morning news briefing or a weekly goal.'**
  String get scheduleEmpty;

  /// No description provided for @scheduleChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get scheduleChat;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @scheduleNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New scheduled prompt'**
  String get scheduleNewTitle;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @scheduleEveryDay.
  ///
  /// In en, this message translates to:
  /// **'Every day at {time}'**
  String scheduleEveryDay(String time);

  /// No description provided for @scheduleAskChat.
  ///
  /// In en, this message translates to:
  /// **'Ask in a chat'**
  String get scheduleAskChat;

  /// No description provided for @scheduleOpenGoal.
  ///
  /// In en, this message translates to:
  /// **'Open as a goal'**
  String get scheduleOpenGoal;

  /// No description provided for @scheduleExample.
  ///
  /// In en, this message translates to:
  /// **'What are the top news stories in Canada today?'**
  String get scheduleExample;

  /// No description provided for @scheduleNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification title (optional)'**
  String get scheduleNotificationTitle;

  /// No description provided for @hostPortRange.
  ///
  /// In en, this message translates to:
  /// **'Use a number from 1 to 65535.'**
  String get hostPortRange;

  /// No description provided for @hostPortReserved.
  ///
  /// In en, this message translates to:
  /// **'Ports below 1024 are reserved on Android.'**
  String get hostPortReserved;

  /// No description provided for @hostCopied.
  ///
  /// In en, this message translates to:
  /// **'{what} copied'**
  String hostCopied(String what);

  /// No description provided for @hostPickModel.
  ///
  /// In en, this message translates to:
  /// **'Model to serve'**
  String get hostPickModel;

  /// No description provided for @hostPickHint.
  ///
  /// In en, this message translates to:
  /// **'Loading takes a few seconds. A running server restarts with the new model; connected devices keep the same address and token.'**
  String get hostPickHint;

  /// No description provided for @hostChangeModel.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get hostChangeModel;

  /// No description provided for @hostManageModels.
  ///
  /// In en, this message translates to:
  /// **'Download or import models'**
  String get hostManageModels;

  /// No description provided for @hostModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get hostModel;

  /// No description provided for @hostNoModel.
  ///
  /// In en, this message translates to:
  /// **'No model loaded'**
  String get hostNoModel;

  /// No description provided for @hostLoadFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose a model to serve.'**
  String get hostLoadFirst;

  /// No description provided for @hostModelHint.
  ///
  /// In en, this message translates to:
  /// **'Other devices chat with this model while the server runs.'**
  String get hostModelHint;

  /// No description provided for @hostConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get hostConnection;

  /// No description provided for @hostPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get hostPort;

  /// No description provided for @hostPortHint.
  ///
  /// In en, this message translates to:
  /// **'The other device connects to this port.'**
  String get hostPortHint;

  /// No description provided for @hostStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get hostStarting;

  /// No description provided for @hostStart.
  ///
  /// In en, this message translates to:
  /// **'Start server'**
  String get hostStart;

  /// No description provided for @hostToken.
  ///
  /// In en, this message translates to:
  /// **'Access token'**
  String get hostToken;

  /// No description provided for @hostRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate access token'**
  String get hostRotate;

  /// No description provided for @hostRotateHint.
  ///
  /// In en, this message translates to:
  /// **'Devices using the current token must reconnect with the new one.'**
  String get hostRotateHint;

  /// No description provided for @hostRotated.
  ///
  /// In en, this message translates to:
  /// **'A new token is used on the next start.'**
  String get hostRotated;

  /// No description provided for @hostWaiting.
  ///
  /// In en, this message translates to:
  /// **'Serving · waiting for requests'**
  String get hostWaiting;

  /// No description provided for @hostAnswering.
  ///
  /// In en, this message translates to:
  /// **'Answering {client}'**
  String hostAnswering(String client);

  /// No description provided for @hostUp.
  ///
  /// In en, this message translates to:
  /// **'up {duration}'**
  String hostUp(String duration);

  /// No description provided for @hostLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get hostLive;

  /// No description provided for @hostAnswered.
  ///
  /// In en, this message translates to:
  /// **'answered'**
  String get hostAnswered;

  /// No description provided for @hostRefused.
  ///
  /// In en, this message translates to:
  /// **'refused'**
  String get hostRefused;

  /// No description provided for @hostFailed.
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get hostFailed;

  /// No description provided for @hostTokensIn.
  ///
  /// In en, this message translates to:
  /// **'tokens in'**
  String get hostTokensIn;

  /// No description provided for @hostTokensOut.
  ///
  /// In en, this message translates to:
  /// **'tokens out'**
  String get hostTokensOut;

  /// No description provided for @hostAvgSpeed.
  ///
  /// In en, this message translates to:
  /// **'avg speed'**
  String get hostAvgSpeed;

  /// No description provided for @hostDevices.
  ///
  /// In en, this message translates to:
  /// **'devices'**
  String get hostDevices;

  /// No description provided for @hostBattery.
  ///
  /// In en, this message translates to:
  /// **'battery'**
  String get hostBattery;

  /// No description provided for @hostHeat.
  ///
  /// In en, this message translates to:
  /// **'heat'**
  String get hostHeat;

  /// No description provided for @hostLowBattery.
  ///
  /// In en, this message translates to:
  /// **'Stop on low battery'**
  String get hostLowBattery;

  /// No description provided for @hostLowBatteryHint.
  ///
  /// In en, this message translates to:
  /// **'The server also stops when the phone reports severe heat. The screen stays on while it runs.'**
  String get hostLowBatteryHint;

  /// No description provided for @commonOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get commonOff;

  /// No description provided for @hostConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect another device'**
  String get hostConnect;

  /// No description provided for @hostServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get hostServerUrl;

  /// No description provided for @hostModelId.
  ///
  /// In en, this message translates to:
  /// **'Model ID'**
  String get hostModelId;

  /// No description provided for @hostHideToken.
  ///
  /// In en, this message translates to:
  /// **'Hide token'**
  String get hostHideToken;

  /// No description provided for @hostShowToken.
  ///
  /// In en, this message translates to:
  /// **'Show token'**
  String get hostShowToken;

  /// No description provided for @hostCopyConnection.
  ///
  /// In en, this message translates to:
  /// **'Copy connection'**
  String get hostCopyConnection;

  /// No description provided for @hostPairHint.
  ///
  /// In en, this message translates to:
  /// **'On the other phone: scan this code with the camera and copy the text, or paste the copied connection, then in OnDevice LLM open Settings > Remote server > Add > Paste connection. Any OpenAI-compatible app works too, with the URL, model and token.'**
  String get hostPairHint;

  /// No description provided for @hostRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent requests'**
  String get hostRecent;

  /// No description provided for @hostNoneYet.
  ///
  /// In en, this message translates to:
  /// **'None yet.'**
  String get hostNoneYet;

  /// No description provided for @hostCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy {what}'**
  String hostCopy(String what);

  /// No description provided for @hostInOut.
  ///
  /// In en, this message translates to:
  /// **'{prompt} in · {completion} out'**
  String hostInOut(int prompt, int completion);

  /// No description provided for @remotePasteNone.
  ///
  /// In en, this message translates to:
  /// **'The clipboard has no connection. On the other phone, tap Copy connection (or scan its QR code) first.'**
  String get remotePasteNone;

  /// No description provided for @remotePasted.
  ///
  /// In en, this message translates to:
  /// **'Added {name}. Turn on Use remote server to chat with it.'**
  String remotePasted(String name);

  /// No description provided for @remotePaste.
  ///
  /// In en, this message translates to:
  /// **'Paste connection'**
  String get remotePaste;

  /// No description provided for @remoteAdd.
  ///
  /// In en, this message translates to:
  /// **'Add connection'**
  String get remoteAdd;

  /// No description provided for @configCopied.
  ///
  /// In en, this message translates to:
  /// **'Configuration copied as text'**
  String get configCopied;

  /// No description provided for @configTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That file is too large to be a configuration.'**
  String get configTooLarge;

  /// No description provided for @configNotAFile.
  ///
  /// In en, this message translates to:
  /// **'That file is not an OnDevice LLM model configuration.'**
  String get configNotAFile;

  /// No description provided for @configNotInClipboard.
  ///
  /// In en, this message translates to:
  /// **'The clipboard has no model configuration. Copy one first.'**
  String get configNotInClipboard;

  /// No description provided for @configMadeFor.
  ///
  /// In en, this message translates to:
  /// **'Made for {model}'**
  String configMadeFor(String model);

  /// No description provided for @configNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'This model is in the catalog but not downloaded: get it from Models, or apply to one you have.'**
  String get configNotDownloaded;

  /// No description provided for @configNotOnPhone.
  ///
  /// In en, this message translates to:
  /// **'This model is not on this phone. Apply the settings to one you have:'**
  String get configNotOnPhone;

  /// No description provided for @configSameModel.
  ///
  /// In en, this message translates to:
  /// **'{model} (same model)'**
  String configSameModel(String model);

  /// No description provided for @configEmpty.
  ///
  /// In en, this message translates to:
  /// **'The card sets nothing: the model would run on your own settings.'**
  String get configEmpty;

  /// No description provided for @configLeftOut.
  ///
  /// In en, this message translates to:
  /// **'Left out (web access, phone hardware, context size or unknown): {keys}'**
  String configLeftOut(String keys);

  /// No description provided for @configApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get configApply;

  /// No description provided for @hostShowQr.
  ///
  /// In en, this message translates to:
  /// **'Show pairing code'**
  String get hostShowQr;

  /// No description provided for @voiceConversation.
  ///
  /// In en, this message translates to:
  /// **'Voice conversation'**
  String get voiceConversation;

  /// No description provided for @chatPinModel.
  ///
  /// In en, this message translates to:
  /// **'Pin a model to this chat'**
  String get chatPinModel;

  /// No description provided for @chatPinHint.
  ///
  /// In en, this message translates to:
  /// **'This chat always answers with the pinned model, whatever the model picker says.'**
  String get chatPinHint;

  /// No description provided for @chatPinNone.
  ///
  /// In en, this message translates to:
  /// **'No pin: use the selected model'**
  String get chatPinNone;

  /// No description provided for @chatPinned.
  ///
  /// In en, this message translates to:
  /// **'📌 {model}'**
  String chatPinned(String model);

  /// No description provided for @readerSummarize.
  ///
  /// In en, this message translates to:
  /// **'Summarize article'**
  String get readerSummarize;

  /// No description provided for @readerKeyPoints.
  ///
  /// In en, this message translates to:
  /// **'Key points'**
  String get readerKeyPoints;

  /// No description provided for @readerExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain simply'**
  String get readerExplain;

  /// No description provided for @readerSummarizePrompt.
  ///
  /// In en, this message translates to:
  /// **'Read this article and summarize it in a few short paragraphs, keeping names, figures and dates exact, and cite it: {url}'**
  String readerSummarizePrompt(String url);

  /// No description provided for @readerKeyPointsPrompt.
  ///
  /// In en, this message translates to:
  /// **'Read this article and list its key points as short bullets, citing it: {url}'**
  String readerKeyPointsPrompt(String url);

  /// No description provided for @readerExplainPrompt.
  ///
  /// In en, this message translates to:
  /// **'Read this article and explain what it says in plain language for someone new to the topic, citing it: {url}'**
  String readerExplainPrompt(String url);

  /// No description provided for @readerNeedsWeb.
  ///
  /// In en, this message translates to:
  /// **'Reading a link needs web research: turn it on with the globe pill.'**
  String get readerNeedsWeb;

  /// No description provided for @saveToKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Save to knowledge'**
  String get saveToKnowledge;

  /// No description provided for @knowledgeSaveHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a collection and the messages to save. Only visible message text and its source links are included; private reasoning stays out.'**
  String get knowledgeSaveHint;

  /// No description provided for @knowledgeCollectionName.
  ///
  /// In en, this message translates to:
  /// **'Collection name'**
  String get knowledgeCollectionName;

  /// No description provided for @knowledgeDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Document title'**
  String get knowledgeDocumentTitle;

  /// No description provided for @knowledgeSelectMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages to save'**
  String get knowledgeSelectMessages;

  /// No description provided for @knowledgeChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved conversation'**
  String get knowledgeChatTitle;

  /// No description provided for @knowledgeNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a collection name and document title.'**
  String get knowledgeNameRequired;

  /// No description provided for @knowledgeSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to {collection}.'**
  String knowledgeSaved(String collection);

  /// No description provided for @knowledgeSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save to knowledge: {error}'**
  String knowledgeSaveFailed(String error);

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @assistant.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get assistant;

  /// No description provided for @backupPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 12 characters for the backup password.'**
  String get backupPasswordTooShort;

  /// No description provided for @backupPasswordsMismatch.
  ///
  /// In en, this message translates to:
  /// **'The passwords do not match.'**
  String get backupPasswordsMismatch;

  /// No description provided for @backupSaveDialog.
  ///
  /// In en, this message translates to:
  /// **'Save encrypted backup'**
  String get backupSaveDialog;

  /// No description provided for @backupSaveCancelled.
  ///
  /// In en, this message translates to:
  /// **'Save cancelled.'**
  String get backupSaveCancelled;

  /// No description provided for @backupSavedNotice.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup saved. Keep the password safe; it cannot be recovered.'**
  String get backupSavedNotice;

  /// No description provided for @backupFailedNotice.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String backupFailedNotice(String error);

  /// No description provided for @backupEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter the backup password.'**
  String get backupEnterPassword;

  /// No description provided for @backupReplaceQuestion.
  ///
  /// In en, this message translates to:
  /// **'Replace this device’s library?'**
  String get backupReplaceQuestion;

  /// No description provided for @backupReplaceHint.
  ///
  /// In en, this message translates to:
  /// **'Restoring replaces chats, knowledge, attachments, and app settings the next time the app starts. Local model files and saved API keys are not included in the backup.'**
  String get backupReplaceHint;

  /// No description provided for @backupRestoreAction.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get backupRestoreAction;

  /// No description provided for @backupTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Backup exceeds the safety limit.'**
  String get backupTooLarge;

  /// No description provided for @backupVerifiedNotice.
  ///
  /// In en, this message translates to:
  /// **'Backup verified. Fully close and reopen the app to apply the restore.'**
  String get backupVerifiedNotice;

  /// No description provided for @backupRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String backupRestoreFailed(String error);

  /// No description provided for @backupTitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup'**
  String get backupTitle;

  /// No description provided for @backupIntro.
  ///
  /// In en, this message translates to:
  /// **'Back up chats, knowledge, attachments, Goals, and settings to a password-protected file. Model weights and saved API keys stay on this device. The backup limit is 96 MB.'**
  String get backupIntro;

  /// No description provided for @backupPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get backupPasswordLabel;

  /// No description provided for @backupConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password for a new backup'**
  String get backupConfirmPassword;

  /// No description provided for @backupCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create encrypted backup'**
  String get backupCreateAction;

  /// No description provided for @backupRestoreBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get backupRestoreBackup;

  /// No description provided for @uiRemoteProfilePageDeleteConnection.
  ///
  /// In en, this message translates to:
  /// **'Delete connection?'**
  String get uiRemoteProfilePageDeleteConnection;

  /// No description provided for @uiRemoteProfilePageCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get uiRemoteProfilePageCancel;

  /// No description provided for @uiRemoteProfilePageDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get uiRemoteProfilePageDelete;

  /// No description provided for @uiRemoteProfilePageConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get uiRemoteProfilePageConnection;

  /// No description provided for @uiRemoteProfilePageThisConnectionWasRemoved.
  ///
  /// In en, this message translates to:
  /// **'This connection was removed.'**
  String get uiRemoteProfilePageThisConnectionWasRemoved;

  /// No description provided for @uiRemoteProfilePageDeleteConnection2.
  ///
  /// In en, this message translates to:
  /// **'Delete connection'**
  String get uiRemoteProfilePageDeleteConnection2;

  /// No description provided for @uiRemoteProfilePageProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get uiRemoteProfilePageProvider;

  /// No description provided for @uiRemoteProfilePageName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get uiRemoteProfilePageName;

  /// No description provided for @uiRemoteProfilePageServerURL.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get uiRemoteProfilePageServerURL;

  /// No description provided for @uiRemoteProfilePageGetAKeyInTheBrowser.
  ///
  /// In en, this message translates to:
  /// **'Get a key in the browser'**
  String get uiRemoteProfilePageGetAKeyInTheBrowser;

  /// No description provided for @uiRemoteProfilePageModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get uiRemoteProfilePageModel;

  /// No description provided for @uiRemoteProfilePageModelsOnTheServer.
  ///
  /// In en, this message translates to:
  /// **'Models on the server'**
  String get uiRemoteProfilePageModelsOnTheServer;

  /// No description provided for @uiRemoteProfilePageRequestsPerMinute.
  ///
  /// In en, this message translates to:
  /// **'Requests per minute'**
  String get uiRemoteProfilePageRequestsPerMinute;

  /// No description provided for @uiRemoteProfilePageNone.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get uiRemoteProfilePageNone;

  /// No description provided for @uiRemoteProfilePageRequestsPerDay.
  ///
  /// In en, this message translates to:
  /// **'Requests per day'**
  String get uiRemoteProfilePageRequestsPerDay;

  /// No description provided for @uiRemoteProfilePageExtraHeaders.
  ///
  /// In en, this message translates to:
  /// **'Extra headers'**
  String get uiRemoteProfilePageExtraHeaders;

  /// No description provided for @uiAdvancedPagesContextBatch.
  ///
  /// In en, this message translates to:
  /// **'Context & batch'**
  String get uiAdvancedPagesContextBatch;

  /// No description provided for @uiAdvancedPagesContextSize.
  ///
  /// In en, this message translates to:
  /// **'Context size'**
  String get uiAdvancedPagesContextSize;

  /// No description provided for @uiAdvancedPagesTokensTheModelCanSeeAt.
  ///
  /// In en, this message translates to:
  /// **'Tokens the model can see at once: the conversation, web evidence and the answer. Memory grows with it; if the phone cannot hold it, the model loads with a shorter context and a note says so.'**
  String get uiAdvancedPagesTokensTheModelCanSeeAt;

  /// No description provided for @uiAdvancedPagesContextSizeTokens.
  ///
  /// In en, this message translates to:
  /// **'Context size (tokens)'**
  String get uiAdvancedPagesContextSizeTokens;

  /// No description provided for @uiAdvancedPagesBatchSize.
  ///
  /// In en, this message translates to:
  /// **'Batch size'**
  String get uiAdvancedPagesBatchSize;

  /// No description provided for @uiAdvancedPagesPromptTokensSubmittedPerStepAuto.
  ///
  /// In en, this message translates to:
  /// **'Prompt tokens submitted per step. Auto is 512, the measured optimum on this phone; larger mostly helps GPU prefill of long prompts.'**
  String get uiAdvancedPagesPromptTokensSubmittedPerStepAuto;

  /// No description provided for @uiAdvancedPagesMicroBatch.
  ///
  /// In en, this message translates to:
  /// **'Micro-batch'**
  String get uiAdvancedPagesMicroBatch;

  /// No description provided for @uiAdvancedPagesTokensPerComputeStepWithinA.
  ///
  /// In en, this message translates to:
  /// **'Tokens per compute step within a batch. Auto matches the batch size. Never above the batch size.'**
  String get uiAdvancedPagesTokensPerComputeStepWithinA;

  /// No description provided for @uiAdvancedPagesKeepConversationInContext.
  ///
  /// In en, this message translates to:
  /// **'Keep conversation in context'**
  String get uiAdvancedPagesKeepConversationInContext;

  /// No description provided for @uiAdvancedPagesOnlyNewTextIsEvaluatedOn.
  ///
  /// In en, this message translates to:
  /// **'Only new text is evaluated on each turn; earlier turns stay resident. Off re-reads the whole conversation every message.'**
  String get uiAdvancedPagesOnlyNewTextIsEvaluatedOn;

  /// No description provided for @uiAdvancedPagesHardware.
  ///
  /// In en, this message translates to:
  /// **'Hardware'**
  String get uiAdvancedPagesHardware;

  /// No description provided for @uiAdvancedPagesBackend.
  ///
  /// In en, this message translates to:
  /// **'Backend'**
  String get uiAdvancedPagesBackend;

  /// No description provided for @uiAdvancedPagesAutomaticUsesCPUOpenCL2Faster.
  ///
  /// In en, this message translates to:
  /// **'Automatic uses CPU. OpenCL: ~2× faster prompt reading for research, ~15 % slower answers; the model reloads when you change it.'**
  String get uiAdvancedPagesAutomaticUsesCPUOpenCL2Faster;

  /// No description provided for @uiAdvancedPagesGPULayers.
  ///
  /// In en, this message translates to:
  /// **'GPU layers'**
  String get uiAdvancedPagesGPULayers;

  /// No description provided for @uiAdvancedPagesLayersOffloadedToTheGPUIgnored.
  ///
  /// In en, this message translates to:
  /// **'Layers offloaded to the GPU. Ignored when the backend is CPU only.'**
  String get uiAdvancedPagesLayersOffloadedToTheGPUIgnored;

  /// No description provided for @uiAdvancedPagesCPUThreadsDecode.
  ///
  /// In en, this message translates to:
  /// **'CPU threads (decode)'**
  String get uiAdvancedPagesCPUThreadsDecode;

  /// No description provided for @uiAdvancedPagesWorkerThreadsWhileTheAnswerStreams.
  ///
  /// In en, this message translates to:
  /// **'Worker threads while the answer streams. Auto uses 6 on 8-core phones (measured fastest), otherwise half the cores.'**
  String get uiAdvancedPagesWorkerThreadsWhileTheAnswerStreams;

  /// No description provided for @uiAdvancedPagesCPUThreadsPrefill.
  ///
  /// In en, this message translates to:
  /// **'CPU threads (prefill)'**
  String get uiAdvancedPagesCPUThreadsPrefill;

  /// No description provided for @uiAdvancedPagesThreadsWhileThePromptIsRead.
  ///
  /// In en, this message translates to:
  /// **'Threads while the prompt is read. Auto uses every core: prefill kept speeding up to 8 threads where decode slowed down.'**
  String get uiAdvancedPagesThreadsWhileThePromptIsRead;

  /// No description provided for @uiAdvancedPagesFlashAttention.
  ///
  /// In en, this message translates to:
  /// **'Flash attention'**
  String get uiAdvancedPagesFlashAttention;

  /// No description provided for @uiAdvancedPagesFasterAttentionKernelWithLowerMemory.
  ///
  /// In en, this message translates to:
  /// **'Faster attention kernel with lower memory use.'**
  String get uiAdvancedPagesFasterAttentionKernelWithLowerMemory;

  /// No description provided for @uiAdvancedPagesKVCache.
  ///
  /// In en, this message translates to:
  /// **'KV cache'**
  String get uiAdvancedPagesKVCache;

  /// No description provided for @uiAdvancedPagesPrecisionOfCachedAttentionState.
  ///
  /// In en, this message translates to:
  /// **'Precision of cached attention state'**
  String get uiAdvancedPagesPrecisionOfCachedAttentionState;

  /// No description provided for @uiAdvancedPagesSampling.
  ///
  /// In en, this message translates to:
  /// **'Sampling'**
  String get uiAdvancedPagesSampling;

  /// No description provided for @uiAdvancedPagesTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get uiAdvancedPagesTemperature;

  /// No description provided for @uiAdvancedPagesRandomnessLowerIsMoreFocusedHigher.
  ///
  /// In en, this message translates to:
  /// **'Randomness. Lower is more focused, higher is more varied.'**
  String get uiAdvancedPagesRandomnessLowerIsMoreFocusedHigher;

  /// No description provided for @uiAdvancedPagesTopP.
  ///
  /// In en, this message translates to:
  /// **'Top-P'**
  String get uiAdvancedPagesTopP;

  /// No description provided for @uiAdvancedPagesSampleFromTheSmallestSetOf.
  ///
  /// In en, this message translates to:
  /// **'Sample from the smallest set of tokens whose probability adds up to P.'**
  String get uiAdvancedPagesSampleFromTheSmallestSetOf;

  /// No description provided for @uiAdvancedPagesMinP.
  ///
  /// In en, this message translates to:
  /// **'Min-P'**
  String get uiAdvancedPagesMinP;

  /// No description provided for @uiAdvancedPagesDropTokensLessLikelyThanThis.
  ///
  /// In en, this message translates to:
  /// **'Drop tokens less likely than this fraction of the top token.'**
  String get uiAdvancedPagesDropTokensLessLikelyThanThis;

  /// No description provided for @uiAdvancedPagesTopK.
  ///
  /// In en, this message translates to:
  /// **'Top-K'**
  String get uiAdvancedPagesTopK;

  /// No description provided for @uiAdvancedPagesOnlyTheKMostLikelyTokens.
  ///
  /// In en, this message translates to:
  /// **'Only the K most likely tokens are considered. 0 disables.'**
  String get uiAdvancedPagesOnlyTheKMostLikelyTokens;

  /// No description provided for @uiAdvancedPagesRepetitionPenalty.
  ///
  /// In en, this message translates to:
  /// **'Repetition penalty'**
  String get uiAdvancedPagesRepetitionPenalty;

  /// No description provided for @uiAdvancedPagesDiscouragesRepeatingRecentTokens100.
  ///
  /// In en, this message translates to:
  /// **'Discourages repeating recent tokens. 1.00 is off.'**
  String get uiAdvancedPagesDiscouragesRepeatingRecentTokens100;

  /// No description provided for @uiAdvancedPagesMaxTokens.
  ///
  /// In en, this message translates to:
  /// **'Max tokens'**
  String get uiAdvancedPagesMaxTokens;

  /// No description provided for @uiAdvancedPagesUpperBoundOnOneResponseReasoning.
  ///
  /// In en, this message translates to:
  /// **'Upper bound on one response, reasoning included. It is reserved inside the context, so it must fit alongside the prompt.'**
  String get uiAdvancedPagesUpperBoundOnOneResponseReasoning;

  /// No description provided for @uiAdvancedPagesMaxTokensPerResponse.
  ///
  /// In en, this message translates to:
  /// **'Max tokens per response'**
  String get uiAdvancedPagesMaxTokensPerResponse;

  /// No description provided for @uiAdvancedPagesReasoningSearch.
  ///
  /// In en, this message translates to:
  /// **'Reasoning & search'**
  String get uiAdvancedPagesReasoningSearch;

  /// No description provided for @uiAdvancedPagesThinkingMode.
  ///
  /// In en, this message translates to:
  /// **'Thinking mode'**
  String get uiAdvancedPagesThinkingMode;

  /// No description provided for @uiAdvancedPagesShowModelGeneratedReasoningWhenSupported.
  ///
  /// In en, this message translates to:
  /// **'Show model-generated reasoning when supported. It may contain mistakes and is not proof of correctness.'**
  String get uiAdvancedPagesShowModelGeneratedReasoningWhenSupported;

  /// No description provided for @uiAdvancedPagesThinkingBudget.
  ///
  /// In en, this message translates to:
  /// **'Thinking budget'**
  String get uiAdvancedPagesThinkingBudget;

  /// No description provided for @uiAdvancedPagesReasoningTokensAllowedBeforeTheBlock.
  ///
  /// In en, this message translates to:
  /// **'Reasoning tokens allowed before the block is closed and the answer starts. Bounds the wait on hard questions; unlimited lets the model decide.'**
  String get uiAdvancedPagesReasoningTokensAllowedBeforeTheBlock;

  /// No description provided for @uiAdvancedPagesThinkingBudgetTokens0Unlimited.
  ///
  /// In en, this message translates to:
  /// **'Thinking budget (tokens, 0 = unlimited)'**
  String get uiAdvancedPagesThinkingBudgetTokens0Unlimited;

  /// No description provided for @uiAdvancedPagesSearchAndNewsRegion.
  ///
  /// In en, this message translates to:
  /// **'Search and news region'**
  String get uiAdvancedPagesSearchAndNewsRegion;

  /// No description provided for @uiAdvancedPagesSearchResults.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get uiAdvancedPagesSearchResults;

  /// No description provided for @uiAdvancedPagesCandidatesTakenFromDuckDuckGoPerQuery.
  ///
  /// In en, this message translates to:
  /// **'Candidates taken from DuckDuckGo per query.'**
  String get uiAdvancedPagesCandidatesTakenFromDuckDuckGoPerQuery;

  /// No description provided for @uiAdvancedPagesPagesToRead.
  ///
  /// In en, this message translates to:
  /// **'Pages to read'**
  String get uiAdvancedPagesPagesToRead;

  /// No description provided for @uiAdvancedPagesResultPagesFetchedAndRankedFor.
  ///
  /// In en, this message translates to:
  /// **'Result pages fetched and ranked for evidence. Unreadable pages are skipped for the next candidate. More is slower and uses more context.'**
  String get uiAdvancedPagesResultPagesFetchedAndRankedFor;

  /// No description provided for @uiAdvancedPagesResearchTimeBudget.
  ///
  /// In en, this message translates to:
  /// **'Research time budget'**
  String get uiAdvancedPagesResearchTimeBudget;

  /// No description provided for @uiAdvancedPagesWallClockLimitForReadingAll.
  ///
  /// In en, this message translates to:
  /// **'Wall-clock limit for reading all pages of one question. Slow sites are cut at the limit and the answer proceeds with what was read.'**
  String get uiAdvancedPagesWallClockLimitForReadingAll;

  /// No description provided for @uiAdvancedPagesModelDrivenResearchExperimental.
  ///
  /// In en, this message translates to:
  /// **'Model-driven research (experimental)'**
  String get uiAdvancedPagesModelDrivenResearchExperimental;

  /// No description provided for @uiAdvancedPagesModelWritesTheSearchQueries.
  ///
  /// In en, this message translates to:
  /// **'Model writes the search queries'**
  String get uiAdvancedPagesModelWritesTheSearchQueries;

  /// No description provided for @uiAdvancedPagesTheLocalModelTurnsYourQuestion.
  ///
  /// In en, this message translates to:
  /// **'The local model turns your question into one or two search-engine queries before searching. Costs a few seconds; off sends the question as typed.'**
  String get uiAdvancedPagesTheLocalModelTurnsYourQuestion;

  /// No description provided for @uiAdvancedPagesPassagesGivenToTheModel.
  ///
  /// In en, this message translates to:
  /// **'Passages given to the model'**
  String get uiAdvancedPagesPassagesGivenToTheModel;

  /// No description provided for @uiAdvancedPagesBestMatchingPassagesAbout250Tokens.
  ///
  /// In en, this message translates to:
  /// **'Best-matching passages (about 250 tokens each) across all read pages. More evidence, longer prefill.'**
  String get uiAdvancedPagesBestMatchingPassagesAbout250Tokens;

  /// No description provided for @uiAdvancedPagesFlagUnsupportedFigures.
  ///
  /// In en, this message translates to:
  /// **'Flag unsupported figures'**
  String get uiAdvancedPagesFlagUnsupportedFigures;

  /// No description provided for @uiAdvancedPagesAfterAGroundedAnswerNumbersVersions.
  ///
  /// In en, this message translates to:
  /// **'After a grounded answer, numbers, versions and dates that appear in no supplied passage are called out as unverified.'**
  String get uiAdvancedPagesAfterAGroundedAnswerNumbersVersions;

  /// No description provided for @supportCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Check sentences by meaning'**
  String get supportCheckTitle;

  /// No description provided for @supportCheckHint.
  ///
  /// In en, this message translates to:
  /// **'A small model (Qwen3 Reranker 0.6B) reads the closest source passage before a sentence is flagged, so a correct sentence in other words is not called unsupported. A separate download; it runs for a few seconds after an answer from sources.'**
  String get supportCheckHint;

  /// No description provided for @uiHfSearchPageSearchHuggingFace.
  ///
  /// In en, this message translates to:
  /// **'Search Hugging Face'**
  String get uiHfSearchPageSearchHuggingFace;

  /// No description provided for @uiHfSearchPageModelNameEGQwen34B.
  ///
  /// In en, this message translates to:
  /// **'Model name, e.g. Qwen3 4B, Phi-4, Llama 3.2'**
  String get uiHfSearchPageModelNameEGQwen34B;

  /// No description provided for @uiHfSearchPageNoGGUFRepositoriesMatch.
  ///
  /// In en, this message translates to:
  /// **'No GGUF repositories match.'**
  String get uiHfSearchPageNoGGUFRepositoriesMatch;

  /// No description provided for @uiHfSearchPageNoSingleFileGGUFWeightsIn.
  ///
  /// In en, this message translates to:
  /// **'No single-file GGUF weights in this repository.'**
  String get uiHfSearchPageNoSingleFileGGUFWeightsIn;

  /// No description provided for @uiHfSearchPageNotAddableHere.
  ///
  /// In en, this message translates to:
  /// **'Not addable here'**
  String get uiHfSearchPageNotAddableHere;

  /// No description provided for @uiBenchmarkDialogBenchmarkCopied.
  ///
  /// In en, this message translates to:
  /// **'Benchmark copied'**
  String get uiBenchmarkDialogBenchmarkCopied;

  /// No description provided for @uiBenchmarkDialogCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get uiBenchmarkDialogCopy;

  /// No description provided for @uiBenchmarkDialogShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get uiBenchmarkDialogShare;

  /// No description provided for @uiBenchmarkDialogDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get uiBenchmarkDialogDone;

  /// No description provided for @uiModelReadinessPageModelReadiness.
  ///
  /// In en, this message translates to:
  /// **'Model readiness'**
  String get uiModelReadinessPageModelReadiness;

  /// No description provided for @uiModelReadinessPageDeviceCapacity.
  ///
  /// In en, this message translates to:
  /// **'Device capacity'**
  String get uiModelReadinessPageDeviceCapacity;

  /// No description provided for @uiModelReadinessPagePhysicalRAM.
  ///
  /// In en, this message translates to:
  /// **'Physical RAM'**
  String get uiModelReadinessPagePhysicalRAM;

  /// No description provided for @uiModelReadinessPageModelStorageVolume.
  ///
  /// In en, this message translates to:
  /// **'Model storage volume'**
  String get uiModelReadinessPageModelStorageVolume;

  /// No description provided for @uiModelReadinessPageInstalledModelWeights.
  ///
  /// In en, this message translates to:
  /// **'Installed model weights'**
  String get uiModelReadinessPageInstalledModelWeights;

  /// No description provided for @uiModelReadinessPageCurrentContextAndBackend.
  ///
  /// In en, this message translates to:
  /// **'Current context and backend'**
  String get uiModelReadinessPageCurrentContextAndBackend;

  /// No description provided for @uiModelReadinessPageModels.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get uiModelReadinessPageModels;

  /// No description provided for @uiModelReadinessPageRAMFitIsARoughEstimate.
  ///
  /// In en, this message translates to:
  /// **'RAM fit is a rough estimate. Actual context memory and speed depend on the model, backend, and device temperature.'**
  String get uiModelReadinessPageRAMFitIsARoughEstimate;

  /// No description provided for @uiToolsQuickPanelLetTheModelCallTools.
  ///
  /// In en, this message translates to:
  /// **'Let the model call tools'**
  String get uiToolsQuickPanelLetTheModelCallTools;

  /// No description provided for @uiToolsQuickPanelTHISMODELMAYCALL.
  ///
  /// In en, this message translates to:
  /// **'This model may call'**
  String get uiToolsQuickPanelTHISMODELMAYCALL;

  /// No description provided for @uiToolsQuickPanelCalculator.
  ///
  /// In en, this message translates to:
  /// **'calculator'**
  String get uiToolsQuickPanelCalculator;

  /// No description provided for @uiToolsQuickPanelExactArithmetic.
  ///
  /// In en, this message translates to:
  /// **'Exact arithmetic.'**
  String get uiToolsQuickPanelExactArithmetic;

  /// No description provided for @uiToolsQuickPanelSearchWebReadUrlFindIn.
  ///
  /// In en, this message translates to:
  /// **'search_web · read_url · find_in_page'**
  String get uiToolsQuickPanelSearchWebReadUrlFindIn;

  /// No description provided for @uiToolsQuickPanelSearchDocuments.
  ///
  /// In en, this message translates to:
  /// **'search_documents'**
  String get uiToolsQuickPanelSearchDocuments;

  /// No description provided for @uiToolsQuickPanelToolUse.
  ///
  /// In en, this message translates to:
  /// **'Tool use'**
  String get uiToolsQuickPanelToolUse;

  /// No description provided for @uiToolsQuickPanelAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get uiToolsQuickPanelAuto;

  /// No description provided for @uiToolsQuickPanelRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get uiToolsQuickPanelRequired;

  /// No description provided for @uiAdvancedAdaptersPageLoRAAdapters.
  ///
  /// In en, this message translates to:
  /// **'LoRA adapters'**
  String get uiAdvancedAdaptersPageLoRAAdapters;

  /// No description provided for @uiAdvancedAdaptersPageImportAdapter.
  ///
  /// In en, this message translates to:
  /// **'Import adapter'**
  String get uiAdvancedAdaptersPageImportAdapter;

  /// No description provided for @uiAdvancedAdaptersPageDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get uiAdvancedAdaptersPageDelete;

  /// No description provided for @uiAdvancedAppearancePageAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get uiAdvancedAppearancePageAppearance;

  /// No description provided for @uiAdvancedAppearancePageTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get uiAdvancedAppearancePageTheme;

  /// No description provided for @uiAdvancedAppearancePageDarkIsTheDesignedDefaultLight.
  ///
  /// In en, this message translates to:
  /// **'Dark is the designed default; light follows the phone if you choose System.'**
  String get uiAdvancedAppearancePageDarkIsTheDesignedDefaultLight;

  /// No description provided for @uiAdvancedAppearancePageAccentColour.
  ///
  /// In en, this message translates to:
  /// **'Accent colour'**
  String get uiAdvancedAppearancePageAccentColour;

  /// No description provided for @uiAdvancedAppearancePageTextSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get uiAdvancedAppearancePageTextSize;

  /// No description provided for @uiAdvancedAppearancePageCompactBubbles.
  ///
  /// In en, this message translates to:
  /// **'Compact bubbles'**
  String get uiAdvancedAppearancePageCompactBubbles;

  /// No description provided for @uiAdvancedAppearancePageTighterSpacingInTheConversation.
  ///
  /// In en, this message translates to:
  /// **'Tighter spacing in the conversation.'**
  String get uiAdvancedAppearancePageTighterSpacingInTheConversation;

  /// No description provided for @motionLabel.
  ///
  /// In en, this message translates to:
  /// **'Motion'**
  String get motionLabel;

  /// No description provided for @motionHint.
  ///
  /// In en, this message translates to:
  /// **'Springs, morphing controls and soft blurs. Your phone\'s Remove animations setting turns motion off.'**
  String get motionHint;

  /// No description provided for @motionFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get motionFull;

  /// No description provided for @motionSubtle.
  ///
  /// In en, this message translates to:
  /// **'Subtle'**
  String get motionSubtle;

  /// No description provided for @motionOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get motionOff;

  /// No description provided for @islandLoadingModel.
  ///
  /// In en, this message translates to:
  /// **'Loading {model}'**
  String islandLoadingModel(String model);

  /// No description provided for @islandModelReady.
  ///
  /// In en, this message translates to:
  /// **'Model ready'**
  String get islandModelReady;

  /// No description provided for @islandResearchDone.
  ///
  /// In en, this message translates to:
  /// **'Research done'**
  String get islandResearchDone;

  /// No description provided for @islandAnswered.
  ///
  /// In en, this message translates to:
  /// **'Answered'**
  String get islandAnswered;

  /// No description provided for @jumpToLatest.
  ///
  /// In en, this message translates to:
  /// **'Jump to the latest message'**
  String get jumpToLatest;

  /// No description provided for @uiAdvancedMemoryRopePageMemoryRoPESpeculation.
  ///
  /// In en, this message translates to:
  /// **'Memory, RoPE & speculation'**
  String get uiAdvancedMemoryRopePageMemoryRoPESpeculation;

  /// No description provided for @uiAdvancedMemoryRopePageKCache.
  ///
  /// In en, this message translates to:
  /// **'K cache'**
  String get uiAdvancedMemoryRopePageKCache;

  /// No description provided for @uiAdvancedMemoryRopePagePrecisionOfCachedKeys.
  ///
  /// In en, this message translates to:
  /// **'Precision of cached keys'**
  String get uiAdvancedMemoryRopePagePrecisionOfCachedKeys;

  /// No description provided for @uiAdvancedMemoryRopePageVCache.
  ///
  /// In en, this message translates to:
  /// **'V cache'**
  String get uiAdvancedMemoryRopePageVCache;

  /// No description provided for @uiAdvancedMemoryRopePagePrecisionOfCachedValuesQuantisingV.
  ///
  /// In en, this message translates to:
  /// **'Precision of cached values. Quantising V needs flash attention, which is enabled automatically.'**
  String get uiAdvancedMemoryRopePagePrecisionOfCachedValuesQuantisingV;

  /// No description provided for @uiAdvancedMemoryRopePageRoPEScaling.
  ///
  /// In en, this message translates to:
  /// **'RoPE scaling'**
  String get uiAdvancedMemoryRopePageRoPEScaling;

  /// No description provided for @uiAdvancedMemoryRopePageHowPositionsBeyondTheTrainedContext.
  ///
  /// In en, this message translates to:
  /// **'How positions beyond the trained context are stretched. \"Model\" keeps what the GGUF declares; YaRN is the usual choice for longer contexts on models that support it.'**
  String get uiAdvancedMemoryRopePageHowPositionsBeyondTheTrainedContext;

  /// No description provided for @uiAdvancedMemoryRopePageRoPEFrequencyBase.
  ///
  /// In en, this message translates to:
  /// **'RoPE frequency base'**
  String get uiAdvancedMemoryRopePageRoPEFrequencyBase;

  /// No description provided for @uiAdvancedMemoryRopePageEG1000000ForModelsThat.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1000000 for models that document it'**
  String get uiAdvancedMemoryRopePageEG1000000ForModelsThat;

  /// No description provided for @uiAdvancedMemoryRopePageRoPEFrequencyScale.
  ///
  /// In en, this message translates to:
  /// **'RoPE frequency scale'**
  String get uiAdvancedMemoryRopePageRoPEFrequencyScale;

  /// No description provided for @uiAdvancedMemoryRopePage0Scale1EG0.
  ///
  /// In en, this message translates to:
  /// **'0 < scale ≤ 1, e.g. 0.25 for 4× the trained context'**
  String get uiAdvancedMemoryRopePage0Scale1EG0;

  /// No description provided for @uiAdvancedMemoryRopePageYaRNOriginalContext.
  ///
  /// In en, this message translates to:
  /// **'YaRN original context'**
  String get uiAdvancedMemoryRopePageYaRNOriginalContext;

  /// No description provided for @uiAdvancedMemoryRopePageTheContextTheModelWasTrained.
  ///
  /// In en, this message translates to:
  /// **'The context the model was trained for'**
  String get uiAdvancedMemoryRopePageTheContextTheModelWasTrained;

  /// No description provided for @uiAdvancedMemoryRopePageYaRNExtrapolationMix.
  ///
  /// In en, this message translates to:
  /// **'YaRN extrapolation mix'**
  String get uiAdvancedMemoryRopePageYaRNExtrapolationMix;

  /// No description provided for @uiAdvancedMemoryRopePage0InterpolationOnly1FullExtrapolation.
  ///
  /// In en, this message translates to:
  /// **'0 = interpolation only, 1 = full extrapolation'**
  String get uiAdvancedMemoryRopePage0InterpolationOnly1FullExtrapolation;

  /// No description provided for @uiAdvancedMemoryRopePageYaRNAttentionFactor.
  ///
  /// In en, this message translates to:
  /// **'YaRN attention factor'**
  String get uiAdvancedMemoryRopePageYaRNAttentionFactor;

  /// No description provided for @uiAdvancedMemoryRopePageMagnitudeScalingUsually10.
  ///
  /// In en, this message translates to:
  /// **'Magnitude scaling, usually 1.0'**
  String get uiAdvancedMemoryRopePageMagnitudeScalingUsually10;

  /// No description provided for @uiAdvancedMemoryRopePageYaRNBetaFast.
  ///
  /// In en, this message translates to:
  /// **'YaRN beta fast'**
  String get uiAdvancedMemoryRopePageYaRNBetaFast;

  /// No description provided for @uiAdvancedMemoryRopePageLowCorrectionDimension.
  ///
  /// In en, this message translates to:
  /// **'Low correction dimension'**
  String get uiAdvancedMemoryRopePageLowCorrectionDimension;

  /// No description provided for @uiAdvancedMemoryRopePageYaRNBetaSlow.
  ///
  /// In en, this message translates to:
  /// **'YaRN beta slow'**
  String get uiAdvancedMemoryRopePageYaRNBetaSlow;

  /// No description provided for @uiAdvancedMemoryRopePageHighCorrectionDimension.
  ///
  /// In en, this message translates to:
  /// **'High correction dimension'**
  String get uiAdvancedMemoryRopePageHighCorrectionDimension;

  /// No description provided for @uiAdvancedMemoryRopePageDraftModel.
  ///
  /// In en, this message translates to:
  /// **'Draft model'**
  String get uiAdvancedMemoryRopePageDraftModel;

  /// No description provided for @uiAdvancedMemoryRopePageASmallerModelWithTheSame.
  ///
  /// In en, this message translates to:
  /// **'A smaller model with the same vocabulary proposes several tokens; the main model verifies them in one pass. Helps on long, predictable answers; measure it — it costs memory and can be slower.'**
  String get uiAdvancedMemoryRopePageASmallerModelWithTheSame;

  /// No description provided for @uiAdvancedMemoryRopePageDraftTokensPerRound.
  ///
  /// In en, this message translates to:
  /// **'Draft tokens per round'**
  String get uiAdvancedMemoryRopePageDraftTokensPerRound;

  /// No description provided for @uiAdvancedMemoryRopePageHowManyTokensTheDraftProposes.
  ///
  /// In en, this message translates to:
  /// **'How many tokens the draft proposes before verification. Higher wins more when the draft is right and wastes more when it is wrong.'**
  String get uiAdvancedMemoryRopePageHowManyTokensTheDraftProposes;

  /// No description provided for @uiAdvancedPages2Cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get uiAdvancedPages2Cancel;

  /// No description provided for @uiAdvancedPages2NotAValidValue.
  ///
  /// In en, this message translates to:
  /// **'Not a valid value.'**
  String get uiAdvancedPages2NotAValidValue;

  /// No description provided for @uiAdvancedPages2Save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get uiAdvancedPages2Save;

  /// No description provided for @uiAdvancedSamplingPageMoreSampling.
  ///
  /// In en, this message translates to:
  /// **'More sampling'**
  String get uiAdvancedSamplingPageMoreSampling;

  /// No description provided for @uiAdvancedSamplingPageSeed.
  ///
  /// In en, this message translates to:
  /// **'Seed'**
  String get uiAdvancedSamplingPageSeed;

  /// No description provided for @uiAdvancedSamplingPageSeed0Random.
  ///
  /// In en, this message translates to:
  /// **'Seed (0 = random)'**
  String get uiAdvancedSamplingPageSeed0Random;

  /// No description provided for @uiAdvancedSamplingPageStopSequences.
  ///
  /// In en, this message translates to:
  /// **'Stop sequences'**
  String get uiAdvancedSamplingPageStopSequences;

  /// No description provided for @uiAdvancedSamplingPagePresencePenalty.
  ///
  /// In en, this message translates to:
  /// **'Presence penalty'**
  String get uiAdvancedSamplingPagePresencePenalty;

  /// No description provided for @uiAdvancedSamplingPageOnceATokenHasAppearedIt.
  ///
  /// In en, this message translates to:
  /// **'Once a token has appeared it is discouraged, regardless of how often. 0 is off; negatives encourage reuse.'**
  String get uiAdvancedSamplingPageOnceATokenHasAppearedIt;

  /// No description provided for @uiAdvancedSamplingPageFrequencyPenalty.
  ///
  /// In en, this message translates to:
  /// **'Frequency penalty'**
  String get uiAdvancedSamplingPageFrequencyPenalty;

  /// No description provided for @uiAdvancedSamplingPageEachRepetitionAddsToThePenalty.
  ///
  /// In en, this message translates to:
  /// **'Each repetition adds to the penalty. 0 is off.'**
  String get uiAdvancedSamplingPageEachRepetitionAddsToThePenalty;

  /// No description provided for @uiAdvancedSamplingPagePenaltyWindow.
  ///
  /// In en, this message translates to:
  /// **'Penalty window'**
  String get uiAdvancedSamplingPagePenaltyWindow;

  /// No description provided for @uiAdvancedSamplingPageHowManyRecentTokensTheRepetition.
  ///
  /// In en, this message translates to:
  /// **'How many recent tokens the repetition, presence and frequency penalties look at. 0 turns them off.'**
  String get uiAdvancedSamplingPageHowManyRecentTokensTheRepetition;

  /// No description provided for @uiAdvancedSamplingPageDRYMultiplier.
  ///
  /// In en, this message translates to:
  /// **'DRY multiplier'**
  String get uiAdvancedSamplingPageDRYMultiplier;

  /// No description provided for @uiAdvancedSamplingPageDRYPenalisesRepeatingWholeSequencesRather.
  ///
  /// In en, this message translates to:
  /// **'DRY penalises repeating whole sequences rather than single tokens. 0 is off; 0.8 is the usual strength.'**
  String get uiAdvancedSamplingPageDRYPenalisesRepeatingWholeSequencesRather;

  /// No description provided for @uiAdvancedSamplingPageDRYBase.
  ///
  /// In en, this message translates to:
  /// **'DRY base'**
  String get uiAdvancedSamplingPageDRYBase;

  /// No description provided for @uiAdvancedSamplingPageGrowthOfThePenaltyWithThe.
  ///
  /// In en, this message translates to:
  /// **'Growth of the penalty with the repeated length.'**
  String get uiAdvancedSamplingPageGrowthOfThePenaltyWithThe;

  /// No description provided for @uiAdvancedSamplingPageDRYAllowedLength.
  ///
  /// In en, this message translates to:
  /// **'DRY allowed length'**
  String get uiAdvancedSamplingPageDRYAllowedLength;

  /// No description provided for @uiAdvancedSamplingPageRepeatsShorterThanThisAreFree.
  ///
  /// In en, this message translates to:
  /// **'Repeats shorter than this are free.'**
  String get uiAdvancedSamplingPageRepeatsShorterThanThisAreFree;

  /// No description provided for @uiAdvancedSamplingPageTypicalP.
  ///
  /// In en, this message translates to:
  /// **'Typical-P'**
  String get uiAdvancedSamplingPageTypicalP;

  /// No description provided for @uiAdvancedSamplingPageKeepsTokensWhoseSurpriseIsClose.
  ///
  /// In en, this message translates to:
  /// **'Keeps tokens whose surprise is close to the expected one. 1.00 is off.'**
  String get uiAdvancedSamplingPageKeepsTokensWhoseSurpriseIsClose;

  /// No description provided for @uiAdvancedSamplingPageXTCProbability.
  ///
  /// In en, this message translates to:
  /// **'XTC probability'**
  String get uiAdvancedSamplingPageXTCProbability;

  /// No description provided for @uiAdvancedSamplingPageWithThisProbabilityTheMostLikely.
  ///
  /// In en, this message translates to:
  /// **'With this probability the most likely tokens above the threshold are removed, except the last one — for more varied prose. 0 is off.'**
  String get uiAdvancedSamplingPageWithThisProbabilityTheMostLikely;

  /// No description provided for @uiAdvancedSamplingPageXTCThreshold.
  ///
  /// In en, this message translates to:
  /// **'XTC threshold'**
  String get uiAdvancedSamplingPageXTCThreshold;

  /// No description provided for @uiAdvancedSamplingPageTokensAboveThisProbabilityAreCandidates.
  ///
  /// In en, this message translates to:
  /// **'Tokens above this probability are candidates for removal.'**
  String get uiAdvancedSamplingPageTokensAboveThisProbabilityAreCandidates;

  /// No description provided for @uiAdvancedSamplingPageTopNSigma.
  ///
  /// In en, this message translates to:
  /// **'Top-n-sigma'**
  String get uiAdvancedSamplingPageTopNSigma;

  /// No description provided for @uiAdvancedSamplingPageKeepsTokensWithinNStandardDeviations.
  ///
  /// In en, this message translates to:
  /// **'Keeps tokens within n standard deviations of the best logit; works well with high temperatures. Off at 0.'**
  String get uiAdvancedSamplingPageKeepsTokensWithinNStandardDeviations;

  /// No description provided for @uiAdvancedSamplingPageResetOrder.
  ///
  /// In en, this message translates to:
  /// **'Reset order'**
  String get uiAdvancedSamplingPageResetOrder;

  /// No description provided for @uiAdvancedSamplingPageOnePerLineUpTo8.
  ///
  /// In en, this message translates to:
  /// **'One per line, up to 8. The answer ends when one appears; it is never shown.'**
  String get uiAdvancedSamplingPageOnePerLineUpTo8;

  /// No description provided for @uiAdvancedSamplingPageCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get uiAdvancedSamplingPageCancel;

  /// No description provided for @uiAdvancedSamplingPageSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get uiAdvancedSamplingPageSave;

  /// No description provided for @uiAdvancedStructuredOutputPageStructuredOutput.
  ///
  /// In en, this message translates to:
  /// **'Structured output'**
  String get uiAdvancedStructuredOutputPageStructuredOutput;

  /// No description provided for @uiAdvancedStructuredOutputPageResponseFormat.
  ///
  /// In en, this message translates to:
  /// **'Response format'**
  String get uiAdvancedStructuredOutputPageResponseFormat;

  /// No description provided for @uiAdvancedStructuredOutputPageConstrainsEveryTokenTheModelProduces.
  ///
  /// In en, this message translates to:
  /// **'Constrains every token the model produces. Thinking is turned off for constrained answers, and tools are not offered.'**
  String get uiAdvancedStructuredOutputPageConstrainsEveryTokenTheModelProduces;

  /// No description provided for @uiAdvancedStructuredOutputPageJSONSchema.
  ///
  /// In en, this message translates to:
  /// **'JSON schema'**
  String get uiAdvancedStructuredOutputPageJSONSchema;

  /// No description provided for @uiAdvancedStructuredOutputPageGBNFGrammar.
  ///
  /// In en, this message translates to:
  /// **'GBNF grammar'**
  String get uiAdvancedStructuredOutputPageGBNFGrammar;

  /// No description provided for @uiAdvancedStructuredOutputPageCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get uiAdvancedStructuredOutputPageCancel;

  /// No description provided for @uiAdvancedStructuredOutputPageSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get uiAdvancedStructuredOutputPageSave;

  /// No description provided for @uiAdvancedToolsPageTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get uiAdvancedToolsPageTools;

  /// No description provided for @uiAdvancedToolsPageLetTheModelCallTools.
  ///
  /// In en, this message translates to:
  /// **'Let the model call tools'**
  String get uiAdvancedToolsPageLetTheModelCallTools;

  /// No description provided for @uiAdvancedToolsPageTheModelCanDecideToSearch.
  ///
  /// In en, this message translates to:
  /// **'The model can decide to search the web, read a page, search your documents or calculate, then answer from the results. Each tool stays behind its own permission below.'**
  String get uiAdvancedToolsPageTheModelCanDecideToSearch;

  /// No description provided for @uiAdvancedToolsPageToolUse.
  ///
  /// In en, this message translates to:
  /// **'Tool use'**
  String get uiAdvancedToolsPageToolUse;

  /// No description provided for @uiAdvancedToolsPageAutoLetsTheModelDecideWhether.
  ///
  /// In en, this message translates to:
  /// **'Auto lets the model decide whether a tool is needed. Required makes it call one before its first answer (later rounds are up to it again): use it when the model keeps answering from memory instead of searching.'**
  String get uiAdvancedToolsPageAutoLetsTheModelDecideWhether;

  /// No description provided for @uiAdvancedToolsPageRoundsPerAnswer.
  ///
  /// In en, this message translates to:
  /// **'Rounds per answer'**
  String get uiAdvancedToolsPageRoundsPerAnswer;

  /// No description provided for @uiAdvancedToolsPageHowManyTimesTheModelMay.
  ///
  /// In en, this message translates to:
  /// **'How many times the model may call tools before it must answer. Each round is another model pass.'**
  String get uiAdvancedToolsPageHowManyTimesTheModelMay;

  /// No description provided for @uiAdvancedToolsPageCalculator.
  ///
  /// In en, this message translates to:
  /// **'calculator'**
  String get uiAdvancedToolsPageCalculator;

  /// No description provided for @uiAdvancedToolsPageExactArithmeticNoPermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Exact arithmetic. No permission needed.'**
  String get uiAdvancedToolsPageExactArithmeticNoPermissionNeeded;

  /// No description provided for @uiAdvancedToolsPageSearchWebReadUrlFindIn.
  ///
  /// In en, this message translates to:
  /// **'search_web · read_url · find_in_page'**
  String get uiAdvancedToolsPageSearchWebReadUrlFindIn;

  /// No description provided for @uiAdvancedToolsPageSearchDocuments.
  ///
  /// In en, this message translates to:
  /// **'search_documents'**
  String get uiAdvancedToolsPageSearchDocuments;

  /// No description provided for @uiEffectiveSettingsPageEffectiveSettings.
  ///
  /// In en, this message translates to:
  /// **'Effective settings'**
  String get uiEffectiveSettingsPageEffectiveSettings;

  /// No description provided for @uiEffectiveSettingsPageAppliesWhenTheModelLoads.
  ///
  /// In en, this message translates to:
  /// **'Applies when the model loads.'**
  String get uiEffectiveSettingsPageAppliesWhenTheModelLoads;

  /// No description provided for @uiEffectiveSettingsPageClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get uiEffectiveSettingsPageClose;

  /// No description provided for @uiKnowledgePageOK.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get uiKnowledgePageOK;

  /// No description provided for @uiKnowledgePageVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying…'**
  String get uiKnowledgePageVerifying;

  /// No description provided for @uiMemoryPageEGTheUserIsA.
  ///
  /// In en, this message translates to:
  /// **'e.g. The user is a nurse in Lisbon and prefers metric units.'**
  String get uiMemoryPageEGTheUserIsA;

  /// No description provided for @uiOverridesPageClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get uiOverridesPageClearAll;

  /// No description provided for @uiOverridesPageInherit.
  ///
  /// In en, this message translates to:
  /// **'Inherit'**
  String get uiOverridesPageInherit;

  /// No description provided for @uiOverridesPageOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get uiOverridesPageOn;

  /// No description provided for @uiOverridesPageOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get uiOverridesPageOff;

  /// No description provided for @uiOverridesPageCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get uiOverridesPageCancel;

  /// No description provided for @uiOverridesPageNotAValidValue.
  ///
  /// In en, this message translates to:
  /// **'Not a valid value.'**
  String get uiOverridesPageNotAValidValue;

  /// No description provided for @uiOverridesPageSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get uiOverridesPageSave;

  /// No description provided for @uiRemoteServerPageUseRemoteServer.
  ///
  /// In en, this message translates to:
  /// **'Use remote server'**
  String get uiRemoteServerPageUseRemoteServer;

  /// No description provided for @uiRemoteServerPageNoConnectionsYet.
  ///
  /// In en, this message translates to:
  /// **'No connections yet'**
  String get uiRemoteServerPageNoConnectionsYet;

  /// No description provided for @uiRemoteServerPageAddOneToChooseAProvider.
  ///
  /// In en, this message translates to:
  /// **'Add one to choose a provider, URL, API key and model.'**
  String get uiRemoteServerPageAddOneToChooseAProvider;

  /// No description provided for @uiRemoteServerPageEditConnection.
  ///
  /// In en, this message translates to:
  /// **'Edit connection'**
  String get uiRemoteServerPageEditConnection;

  /// No description provided for @uiRemoteServerPageWebResearch.
  ///
  /// In en, this message translates to:
  /// **'Web research'**
  String get uiRemoteServerPageWebResearch;

  /// No description provided for @uiRemoteServerPageTheAppSearchesDuckDuckGoAndReads.
  ///
  /// In en, this message translates to:
  /// **'The remote model decides whether a question needs the web, writes its own searches and picks the pages to read; the app runs them on DuckDuckGo and Wikipedia without a key.'**
  String get uiRemoteServerPageTheAppSearchesDuckDuckGoAndReads;

  /// No description provided for @uiRemoteServerPageImageUnderstanding.
  ///
  /// In en, this message translates to:
  /// **'Image understanding'**
  String get uiRemoteServerPageImageUnderstanding;

  /// No description provided for @uiRemoteServerPageSendAttachedImagesToTheModel.
  ///
  /// In en, this message translates to:
  /// **'Send attached images to the model. Enable only for a vision-capable model.'**
  String get uiRemoteServerPageSendAttachedImagesToTheModel;

  /// No description provided for @uiRemoteServerPageDocumentUnderstanding.
  ///
  /// In en, this message translates to:
  /// **'Document understanding'**
  String get uiRemoteServerPageDocumentUnderstanding;

  /// No description provided for @uiRemoteServerPageExtractDocumentsSafelyOnThePhone.
  ///
  /// In en, this message translates to:
  /// **'Extract documents safely on the phone, then send their text in the prompt. Original files are not uploaded.'**
  String get uiRemoteServerPageExtractDocumentsSafelyOnThePhone;

  /// No description provided for @uiRemoteServerPageStreamingIdleTimeout.
  ///
  /// In en, this message translates to:
  /// **'Streaming idle timeout'**
  String get uiRemoteServerPageStreamingIdleTimeout;

  /// No description provided for @uiRemoteServerPageHowLongToWaitBetweenResponse.
  ///
  /// In en, this message translates to:
  /// **'How long to wait between response chunks from a slow or heavily loaded server.'**
  String get uiRemoteServerPageHowLongToWaitBetweenResponse;

  /// No description provided for @uiRemoteServerPageChooseAProvider.
  ///
  /// In en, this message translates to:
  /// **'Choose a provider'**
  String get uiRemoteServerPageChooseAProvider;

  /// No description provided for @uiSettingsScreenEncryptedBackup.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup'**
  String get uiSettingsScreenEncryptedBackup;

  /// No description provided for @uiSettingsScreenMoreSampling.
  ///
  /// In en, this message translates to:
  /// **'More sampling'**
  String get uiSettingsScreenMoreSampling;

  /// No description provided for @uiSettingsScreenMemoryRoPESpeculation.
  ///
  /// In en, this message translates to:
  /// **'Memory, RoPE & speculation'**
  String get uiSettingsScreenMemoryRoPESpeculation;

  /// No description provided for @uiSettingsScreenStructuredOutput.
  ///
  /// In en, this message translates to:
  /// **'Structured output'**
  String get uiSettingsScreenStructuredOutput;

  /// No description provided for @uiSettingsScreenTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get uiSettingsScreenTools;

  /// No description provided for @uiSettingsScreenLoRAAdapters.
  ///
  /// In en, this message translates to:
  /// **'LoRA adapters'**
  String get uiSettingsScreenLoRAAdapters;

  /// No description provided for @uiSettingsScreenEffectiveSettings.
  ///
  /// In en, this message translates to:
  /// **'Effective settings'**
  String get uiSettingsScreenEffectiveSettings;

  /// No description provided for @uiSettingsScreenAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get uiSettingsScreenAppearance;

  /// No description provided for @uiMetricsSheetInstrumentPanel.
  ///
  /// In en, this message translates to:
  /// **'Instrument panel'**
  String get uiMetricsSheetInstrumentPanel;

  /// No description provided for @uiMetricsSheetDisplay.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get uiMetricsSheetDisplay;

  /// No description provided for @uiMetricsSheetBenchmarkThisModel.
  ///
  /// In en, this message translates to:
  /// **'Benchmark this model'**
  String get uiMetricsSheetBenchmarkThisModel;

  /// No description provided for @uiMetricsSheetMeasuredOnThisDeviceNothingIs.
  ///
  /// In en, this message translates to:
  /// **'Measured on this device. Nothing is transmitted.'**
  String get uiMetricsSheetMeasuredOnThisDeviceNothingIs;

  /// No description provided for @uiMetricsSheetSendAMessageToSeeLive.
  ///
  /// In en, this message translates to:
  /// **'Send a message to see live numbers.'**
  String get uiMetricsSheetSendAMessageToSeeLive;

  /// No description provided for @uiMetricsSheetBackend.
  ///
  /// In en, this message translates to:
  /// **'Backend'**
  String get uiMetricsSheetBackend;

  /// No description provided for @uiMetricsSheetNativeLibrary.
  ///
  /// In en, this message translates to:
  /// **'Native library'**
  String get uiMetricsSheetNativeLibrary;

  /// No description provided for @uiMetricsSheetStages.
  ///
  /// In en, this message translates to:
  /// **'Stages'**
  String get uiMetricsSheetStages;

  /// No description provided for @uiMetricsSheetTokensSec.
  ///
  /// In en, this message translates to:
  /// **'Tokens/sec'**
  String get uiMetricsSheetTokensSec;

  /// No description provided for @uiMetricsSheetFirstToken.
  ///
  /// In en, this message translates to:
  /// **'First token'**
  String get uiMetricsSheetFirstToken;

  /// No description provided for @uiMetricsSheetTokens.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get uiMetricsSheetTokens;

  /// No description provided for @uiMetricsSheetContext.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get uiMetricsSheetContext;

  /// No description provided for @uiMetricsSheetPeakRSS.
  ///
  /// In en, this message translates to:
  /// **'Peak RSS'**
  String get uiMetricsSheetPeakRSS;

  /// No description provided for @uiMetricsSheetTemplate.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get uiMetricsSheetTemplate;

  /// No description provided for @uiMetricsSheetThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get uiMetricsSheetThinking;

  /// No description provided for @uiMetricsSheetModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get uiMetricsSheetModel;

  /// No description provided for @uiSettingsWidgetsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get uiSettingsWidgetsCancel;

  /// No description provided for @uiSettingsWidgetsApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get uiSettingsWidgetsApply;

  /// No description provided for @uiPresetSheet00Exact.
  ///
  /// In en, this message translates to:
  /// **'0.0 · exact'**
  String get uiPresetSheet00Exact;

  /// No description provided for @uiPresetSheet03Focused.
  ///
  /// In en, this message translates to:
  /// **'0.3 · focused'**
  String get uiPresetSheet03Focused;

  /// No description provided for @uiPresetSheet07Balanced.
  ///
  /// In en, this message translates to:
  /// **'0.7 · balanced'**
  String get uiPresetSheet07Balanced;

  /// No description provided for @uiPresetSheet10Creative.
  ///
  /// In en, this message translates to:
  /// **'1.0 · creative'**
  String get uiPresetSheet10Creative;

  /// No description provided for @uiModelsScreenHttpsHuggingfaceCo.
  ///
  /// In en, this message translates to:
  /// **'https://huggingface.co/…'**
  String get uiModelsScreenHttpsHuggingfaceCo;

  /// No description provided for @uiModelsScreenModelReadiness.
  ///
  /// In en, this message translates to:
  /// **'Model readiness'**
  String get uiModelsScreenModelReadiness;

  /// No description provided for @uiModelsScreenImportConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Import configuration'**
  String get uiModelsScreenImportConfiguration;

  /// No description provided for @uiModelsScreenImportConfigurationFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Import configuration from clipboard'**
  String get uiModelsScreenImportConfigurationFromClipboard;

  /// No description provided for @uiModelsScreenImportConfigurationFromAFile.
  ///
  /// In en, this message translates to:
  /// **'Import configuration from a file'**
  String get uiModelsScreenImportConfigurationFromAFile;

  /// No description provided for @uiModelsScreenShareOrImportAConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Share or import a configuration'**
  String get uiModelsScreenShareOrImportAConfiguration;

  /// No description provided for @uiModelsScreenShareConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Share configuration'**
  String get uiModelsScreenShareConfiguration;

  /// No description provided for @uiModelsScreenCopyAsText.
  ///
  /// In en, this message translates to:
  /// **'Copy as text'**
  String get uiModelsScreenCopyAsText;

  /// No description provided for @uiModelsScreenImportFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Import from clipboard'**
  String get uiModelsScreenImportFromClipboard;

  /// No description provided for @uiModelsScreenImportFromAFile.
  ///
  /// In en, this message translates to:
  /// **'Import from a file'**
  String get uiModelsScreenImportFromAFile;

  /// No description provided for @uiModelCardRemoveFromList.
  ///
  /// In en, this message translates to:
  /// **'Remove from list'**
  String get uiModelCardRemoveFromList;

  /// No description provided for @uiModelPickerSheetRemoteConnections.
  ///
  /// In en, this message translates to:
  /// **'Remote connections'**
  String get uiModelPickerSheetRemoteConnections;

  /// No description provided for @uiModelPickerSheetAnswersComeFromTheConnectionInstead.
  ///
  /// In en, this message translates to:
  /// **'Answers come from the connection instead of a model on this phone.'**
  String get uiModelPickerSheetAnswersComeFromTheConnectionInstead;

  /// No description provided for @uiQrViewQRCodeWithTheConnectionDetails.
  ///
  /// In en, this message translates to:
  /// **'QR code with the connection details'**
  String get uiQrViewQRCodeWithTheConnectionDetails;

  /// No description provided for @uiChatScreenActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get uiChatScreenActionsTitle;

  /// No description provided for @uiChatScreenActionsDocumentType.
  ///
  /// In en, this message translates to:
  /// **'Document type'**
  String get uiChatScreenActionsDocumentType;

  /// No description provided for @uiChatScreenActionsWordDocx.
  ///
  /// In en, this message translates to:
  /// **'Word (.docx)'**
  String get uiChatScreenActionsWordDocx;

  /// No description provided for @uiChatScreenActionsPDF.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get uiChatScreenActionsPDF;

  /// No description provided for @uiChatScreenActionsPlainTextTxt.
  ///
  /// In en, this message translates to:
  /// **'Plain text (.txt)'**
  String get uiChatScreenActionsPlainTextTxt;

  /// No description provided for @uiChatScreenActionsMarkdownMd.
  ///
  /// In en, this message translates to:
  /// **'Markdown (.md)'**
  String get uiChatScreenActionsMarkdownMd;

  /// No description provided for @uiChatScreenActionsHTML.
  ///
  /// In en, this message translates to:
  /// **'HTML'**
  String get uiChatScreenActionsHTML;

  /// No description provided for @uiChatScreenActionsSelectIndividualMessages.
  ///
  /// In en, this message translates to:
  /// **'Select individual messages'**
  String get uiChatScreenActionsSelectIndividualMessages;

  /// No description provided for @uiChatScreenActionsRedactTermsCommaSeparated.
  ///
  /// In en, this message translates to:
  /// **'Redact terms (comma separated)'**
  String get uiChatScreenActionsRedactTermsCommaSeparated;

  /// No description provided for @uiChatScreenActionsChooseMessages.
  ///
  /// In en, this message translates to:
  /// **'Choose messages'**
  String get uiChatScreenActionsChooseMessages;

  /// No description provided for @uiChatScreenActionsUseSelection.
  ///
  /// In en, this message translates to:
  /// **'Use selection'**
  String get uiChatScreenActionsUseSelection;

  /// No description provided for @uiChatScreenActionsReviewDocument.
  ///
  /// In en, this message translates to:
  /// **'Review document'**
  String get uiChatScreenActionsReviewDocument;

  /// No description provided for @uiChatBubbleChooseQuestionVersion.
  ///
  /// In en, this message translates to:
  /// **'Choose question version'**
  String get uiChatBubbleChooseQuestionVersion;

  /// No description provided for @uiChatBubbleSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get uiChatBubbleSources;

  /// No description provided for @uiChatBubbleKnowledgeLibrary.
  ///
  /// In en, this message translates to:
  /// **'Knowledge library'**
  String get uiChatBubbleKnowledgeLibrary;

  /// No description provided for @uiChatBubbleSponsoredNotUsed.
  ///
  /// In en, this message translates to:
  /// **'Sponsored (not used)'**
  String get uiChatBubbleSponsoredNotUsed;

  /// No description provided for @uiChatBubbleOpenInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get uiChatBubbleOpenInBrowser;

  /// No description provided for @uiCodeBlockCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get uiCodeBlockCopyCode;

  /// No description provided for @uiCodeBlockCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get uiCodeBlockCodeCopied;

  /// No description provided for @readinessUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable on this device'**
  String get readinessUnavailable;

  /// No description provided for @readinessMemory.
  ///
  /// In en, this message translates to:
  /// **'{total} total · {available} available now'**
  String readinessMemory(Object total, Object available);

  /// No description provided for @readinessStorage.
  ///
  /// In en, this message translates to:
  /// **'{free} free of {total}'**
  String readinessStorage(Object free, Object total);

  /// No description provided for @readinessInstalledWeights.
  ///
  /// In en, this message translates to:
  /// **'{size} across {count} models'**
  String readinessInstalledWeights(Object size, Object count);

  /// No description provided for @readinessContext.
  ///
  /// In en, this message translates to:
  /// **'{count} tokens · {backend}'**
  String readinessContext(Object count, Object backend);

  /// No description provided for @readinessInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get readinessInstalled;

  /// No description provided for @readinessDownload.
  ///
  /// In en, this message translates to:
  /// **'Download: {size}'**
  String readinessDownload(Object size);

  /// No description provided for @readinessRamFits.
  ///
  /// In en, this message translates to:
  /// **'RAM estimate: likely fits'**
  String get readinessRamFits;

  /// No description provided for @readinessRamMayNotFit.
  ///
  /// In en, this message translates to:
  /// **'RAM estimate: may not fit'**
  String get readinessRamMayNotFit;

  /// No description provided for @readinessDiskAvailable.
  ///
  /// In en, this message translates to:
  /// **'Disk space available'**
  String get readinessDiskAvailable;

  /// No description provided for @readinessDiskInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Disk space may be insufficient'**
  String get readinessDiskInsufficient;

  /// No description provided for @readinessMeasured.
  ///
  /// In en, this message translates to:
  /// **'Measured: {speed} tok/s'**
  String readinessMeasured(Object speed);

  /// No description provided for @benchmarkFailed.
  ///
  /// In en, this message translates to:
  /// **'Benchmark failed: {error}'**
  String benchmarkFailed(Object error);

  /// No description provided for @benchmarkRunning.
  ///
  /// In en, this message translates to:
  /// **'Benchmarking {model}…\nLoading, then {runs} runs of a ~380-token prefill and 128 greedy tokens (first discarded, medians reported), then a chat with the app\'s system prompt, with and without the tools.'**
  String benchmarkRunning(Object model, Object runs);

  /// No description provided for @hfIntro.
  ///
  /// In en, this message translates to:
  /// **'Public GGUF repositories only, most downloaded first. Each download is pinned to the repository revision and verified against the Hub\'s SHA-256, like the built-in catalog. Vision projectors (mmproj) and split files are shown but cannot be added yet.'**
  String get hfIntro;

  /// No description provided for @hfAdded.
  ///
  /// In en, this message translates to:
  /// **'{model} added · {size} · template {template}'**
  String hfAdded(Object model, Object size, Object template);

  /// No description provided for @hfFromMetadata.
  ///
  /// In en, this message translates to:
  /// **'from metadata'**
  String get hfFromMetadata;

  /// No description provided for @hfRepoStats.
  ///
  /// In en, this message translates to:
  /// **'{downloads} downloads · {likes} likes'**
  String hfRepoStats(Object downloads, Object likes);

  /// No description provided for @hfInLibrary.
  ///
  /// In en, this message translates to:
  /// **'in library'**
  String get hfInLibrary;

  /// No description provided for @hfLicenseRevision.
  ///
  /// In en, this message translates to:
  /// **'License: {license} · revision {revision}'**
  String hfLicenseRevision(Object license, Object revision);

  /// No description provided for @hfVisionProjector.
  ///
  /// In en, this message translates to:
  /// **'vision projector'**
  String get hfVisionProjector;

  /// No description provided for @hfSplitFile.
  ///
  /// In en, this message translates to:
  /// **'split file'**
  String get hfSplitFile;

  /// No description provided for @remoteDeleteHint.
  ///
  /// In en, this message translates to:
  /// **'“{name}” and its API key will be removed from this phone.'**
  String remoteDeleteHint(Object name);

  /// No description provided for @remoteOwnServer.
  ///
  /// In en, this message translates to:
  /// **'A server on your own hardware.'**
  String get remoteOwnServer;

  /// No description provided for @remoteHostedBilling.
  ///
  /// In en, this message translates to:
  /// **'Hosted API billed to your key.'**
  String get remoteHostedBilling;

  /// No description provided for @remoteNameHelp.
  ///
  /// In en, this message translates to:
  /// **'How this connection is listed.'**
  String get remoteNameHelp;

  /// No description provided for @remoteOwnUrlHelp.
  ///
  /// In en, this message translates to:
  /// **'LM Studio: port 1234 · Ollama: 11434 · llama-server: 8080. “{path}” is added automatically.'**
  String remoteOwnUrlHelp(Object path);

  /// No description provided for @remoteHostedUrlHelp.
  ///
  /// In en, this message translates to:
  /// **'Prefilled for {provider}; change it only for a proxy or a regional endpoint.'**
  String remoteHostedUrlHelp(Object provider);

  /// No description provided for @remoteInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter an http(s) URL.'**
  String get remoteInvalidUrl;

  /// No description provided for @remoteApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get remoteApiKey;

  /// No description provided for @remoteApiKeyOptional.
  ///
  /// In en, this message translates to:
  /// **'API key (optional)'**
  String get remoteApiKeyOptional;

  /// No description provided for @remoteKeyHostedHelp.
  ///
  /// In en, this message translates to:
  /// **'Stored in the Android keystore; sent only to {provider}.'**
  String remoteKeyHostedHelp(Object provider);

  /// No description provided for @remoteKeySelfHelp.
  ///
  /// In en, this message translates to:
  /// **'Only if the server was started with a key. Stored in the Android keystore.'**
  String get remoteKeySelfHelp;

  /// No description provided for @remoteHideKey.
  ///
  /// In en, this message translates to:
  /// **'Hide key'**
  String get remoteHideKey;

  /// No description provided for @remoteShowKey.
  ///
  /// In en, this message translates to:
  /// **'Show key'**
  String get remoteShowKey;

  /// No description provided for @remoteServerDefaultModel.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for the server default'**
  String get remoteServerDefaultModel;

  /// No description provided for @remoteModelId.
  ///
  /// In en, this message translates to:
  /// **'Model ID'**
  String get remoteModelId;

  /// No description provided for @remoteModelListHelp.
  ///
  /// In en, this message translates to:
  /// **'Test the connection to pick from the models this provider lists.'**
  String get remoteModelListHelp;

  /// No description provided for @remoteModelManualHelp.
  ///
  /// In en, this message translates to:
  /// **'This provider has no model list; type the ID from its docs.'**
  String get remoteModelManualHelp;

  /// No description provided for @remoteTestList.
  ///
  /// In en, this message translates to:
  /// **'Test & list models'**
  String get remoteTestList;

  /// No description provided for @remoteTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get remoteTestConnection;

  /// No description provided for @remoteExtraHeadersHelp.
  ///
  /// In en, this message translates to:
  /// **'One “Name: value” per line, sent with every request (e.g. OpenAI-Organization, OpenRouter attribution). The key header is set for you.'**
  String get remoteExtraHeadersHelp;

  /// No description provided for @remoteConnectedNoList.
  ///
  /// In en, this message translates to:
  /// **'Connected. This provider has no model list; type the model ID.'**
  String get remoteConnectedNoList;

  /// No description provided for @remoteConnectedServerNoModels.
  ///
  /// In en, this message translates to:
  /// **'Connected, but the server lists no models. Load one in LM Studio / start one in Ollama.'**
  String get remoteConnectedServerNoModels;

  /// No description provided for @remoteConnectedNoModels.
  ///
  /// In en, this message translates to:
  /// **'Connected, but no models were listed for this key.'**
  String get remoteConnectedNoModels;

  /// No description provided for @remoteCapabilities.
  ///
  /// In en, this message translates to:
  /// **'Capabilities'**
  String get remoteCapabilities;

  /// No description provided for @remoteRequestLimits.
  ///
  /// In en, this message translates to:
  /// **'Request limits'**
  String get remoteRequestLimits;

  /// No description provided for @remoteAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get remoteAdvanced;

  /// No description provided for @remoteAnthropicNote.
  ///
  /// In en, this message translates to:
  /// **'Anthropic: thinking mode enables adaptive thinking with summaries; temperature/top-p are not sent because the current models reject them. Tool calls, images and JSON-schema output are supported.'**
  String get remoteAnthropicNote;

  /// No description provided for @remoteGeminiNote.
  ///
  /// In en, this message translates to:
  /// **'Gemini: thinking mode shows thought summaries; function calling, images and JSON output are supported. Function-call signatures are kept for the session.'**
  String get remoteGeminiNote;

  /// No description provided for @remoteSelfHostedNote.
  ///
  /// In en, this message translates to:
  /// **'Only connect to machines you control. The connection is as private as the network between them: use HTTPS or a VPN over the internet.'**
  String get remoteSelfHostedNote;

  /// No description provided for @remoteHostedNote.
  ///
  /// In en, this message translates to:
  /// **'Requests are billed to your {provider} account. Set a daily cap above if you share the key across apps.'**
  String remoteHostedNote(Object provider);

  /// No description provided for @remoteNoTools.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get remoteNoTools;

  /// No description provided for @remoteToolsDetected.
  ///
  /// In en, this message translates to:
  /// **' Server tools detected: {tools}; they are not executed automatically.'**
  String remoteToolsDetected(Object tools);

  /// No description provided for @remoteContextWindow.
  ///
  /// In en, this message translates to:
  /// **' Context window {count} tokens.'**
  String remoteContextWindow(Object count);

  /// No description provided for @remoteAdvertises.
  ///
  /// In en, this message translates to:
  /// **'{model} advertises: {capabilities}.{context}{tools}'**
  String remoteAdvertises(
    Object model,
    Object capabilities,
    Object context,
    Object tools,
  );

  /// No description provided for @remoteContextOnly.
  ///
  /// In en, this message translates to:
  /// **'{model}: context window {count} tokens.{tools}'**
  String remoteContextOnly(Object model, Object count, Object tools);

  /// No description provided for @remoteNoCapabilities.
  ///
  /// In en, this message translates to:
  /// **'This provider does not advertise capabilities for the selected model. Keep the switches on the previous page aligned with the model you use.{tools}'**
  String remoteNoCapabilities(Object tools);

  /// No description provided for @remoteDefaultModel.
  ///
  /// In en, this message translates to:
  /// **'the default model'**
  String get remoteDefaultModel;

  /// No description provided for @remoteCapsHint.
  ///
  /// In en, this message translates to:
  /// **'Caps for {model} on this connection. The app refuses to send once a cap is reached; each tool round counts as one request. Empty means no cap.'**
  String remoteCapsHint(Object model);

  /// No description provided for @remoteUsed.
  ///
  /// In en, this message translates to:
  /// **'Used: {minute} this minute · {day} today'**
  String remoteUsed(Object minute, Object day);

  /// No description provided for @remoteOtherCaps.
  ///
  /// In en, this message translates to:
  /// **'Other models with caps here: {models}.'**
  String remoteOtherCaps(Object models);

  /// No description provided for @scheduleLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load scheduled prompts: {error}'**
  String scheduleLoadFailed(Object error);

  /// No description provided for @noticeCheckingSearch.
  ///
  /// In en, this message translates to:
  /// **'Checking whether to search…'**
  String get noticeCheckingSearch;

  /// No description provided for @noticeResearchingTools.
  ///
  /// In en, this message translates to:
  /// **'Researching with tools…'**
  String get noticeResearchingTools;

  /// No description provided for @noticeNamingChat.
  ///
  /// In en, this message translates to:
  /// **'Naming the chat…'**
  String get noticeNamingChat;

  /// No description provided for @noticeSearchingAgain.
  ///
  /// In en, this message translates to:
  /// **'Searching again for what the pages left out…'**
  String get noticeSearchingAgain;

  /// No description provided for @noticeFollowUpSearch.
  ///
  /// In en, this message translates to:
  /// **'The pages read earlier do not answer this. Searching again…'**
  String get noticeFollowUpSearch;

  /// No description provided for @answerSourcesDated.
  ///
  /// In en, this message translates to:
  /// **'Sources last updated {date}.'**
  String answerSourcesDated(String date);

  /// No description provided for @answerSourcesUndated.
  ///
  /// In en, this message translates to:
  /// **'The sources do not say when they were last updated.'**
  String get answerSourcesUndated;

  /// No description provided for @sourceUpdated.
  ///
  /// In en, this message translates to:
  /// **'updated {date}'**
  String sourceUpdated(String date);

  /// No description provided for @thinkOnSearchSetting.
  ///
  /// In en, this message translates to:
  /// **'Think before answering from sources'**
  String get thinkOnSearchSetting;

  /// No description provided for @thinkOnSearchHint.
  ///
  /// In en, this message translates to:
  /// **'A model that can reason weighs the pages first (up to about 1,000 tokens), even with Thinking mode off.'**
  String get thinkOnSearchHint;

  /// No description provided for @searchAgainSetting.
  ///
  /// In en, this message translates to:
  /// **'Search again when pages fall short'**
  String get searchAgainSetting;

  /// No description provided for @searchAgainHint.
  ///
  /// In en, this message translates to:
  /// **'When the pages read leave part of the question unanswered, one more search and up to two more pages.'**
  String get searchAgainHint;

  /// No description provided for @wikipediaLookupSetting.
  ///
  /// In en, this message translates to:
  /// **'Add the Wikipedia article'**
  String get wikipediaLookupSetting;

  /// No description provided for @wikipediaLookupHint.
  ///
  /// In en, this message translates to:
  /// **'The Wikipedia article about the subject joins the sources, in the question\'s language, when one matches.'**
  String get wikipediaLookupHint;

  /// No description provided for @zimSetting.
  ///
  /// In en, this message translates to:
  /// **'Offline Wikipedia'**
  String get zimSetting;

  /// No description provided for @zimHint.
  ///
  /// In en, this message translates to:
  /// **'Import a Kiwix .zim file (from library.kiwix.org) to answer from Wikipedia with no connection.'**
  String get zimHint;

  /// No description provided for @zimImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get zimImport;

  /// No description provided for @zimRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get zimRemove;

  /// No description provided for @zimImporting.
  ///
  /// In en, this message translates to:
  /// **'Copying… {percent}'**
  String zimImporting(String percent);

  /// No description provided for @zimNotAZim.
  ///
  /// In en, this message translates to:
  /// **'That file is not a .zim file.'**
  String get zimNotAZim;

  /// No description provided for @autoTitlesSetting.
  ///
  /// In en, this message translates to:
  /// **'Name chats automatically'**
  String get autoTitlesSetting;

  /// No description provided for @autoTitlesHint.
  ///
  /// In en, this message translates to:
  /// **'After the first answer the model gives the chat a short title. Off: the first message is the title.'**
  String get autoTitlesHint;

  /// No description provided for @webModeNote.
  ///
  /// In en, this message translates to:
  /// **'Web research mode (Off / Auto / Always) is set on the main Settings screen or the composer pill.'**
  String get webModeNote;

  /// No description provided for @thinkingBudgetUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get thinkingBudgetUnlimited;

  /// No description provided for @adapterImporting.
  ///
  /// In en, this message translates to:
  /// **'Checking and copying the adapter…'**
  String get adapterImporting;

  /// No description provided for @adapterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No adapters yet. Import a LoRA GGUF (made with llama.cpp\'s convert_lora_to_gguf.py) with +, then attach it to a model of the same architecture. The model is reloaded with the adapter applied at the chosen scale.'**
  String get adapterEmpty;

  /// No description provided for @versionPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous version'**
  String get versionPrevious;

  /// No description provided for @versionNext.
  ///
  /// In en, this message translates to:
  /// **'Next version'**
  String get versionNext;

  /// No description provided for @sourceFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get sourceFallbackTitle;

  /// No description provided for @sourcePublished.
  ///
  /// In en, this message translates to:
  /// **'published {date}'**
  String sourcePublished(String date);

  /// No description provided for @sourceReadEarlier.
  ///
  /// In en, this message translates to:
  /// **'read earlier'**
  String get sourceReadEarlier;

  /// No description provided for @sourceMayBeOutdated.
  ///
  /// In en, this message translates to:
  /// **'may be outdated'**
  String get sourceMayBeOutdated;

  /// No description provided for @sourceSponsored.
  ///
  /// In en, this message translates to:
  /// **'Sponsored result'**
  String get sourceSponsored;

  /// No description provided for @sourceSponsoredDetail.
  ///
  /// In en, this message translates to:
  /// **'Sponsored result · shown for transparency · not read or given to the model as evidence'**
  String get sourceSponsoredDetail;

  /// No description provided for @sourceNewsStory.
  ///
  /// In en, this message translates to:
  /// **'News story · {outlet}'**
  String sourceNewsStory(String outlet);

  /// No description provided for @sourceNewsGiven.
  ///
  /// In en, this message translates to:
  /// **'the headline and summary below were given to the model'**
  String get sourceNewsGiven;

  /// No description provided for @sourcePageRead.
  ///
  /// In en, this message translates to:
  /// **'Page read'**
  String get sourcePageRead;

  /// No description provided for @sourceKeptCopy.
  ///
  /// In en, this message translates to:
  /// **'kept copy, the site could not be reached; may be outdated'**
  String get sourceKeptCopy;

  /// No description provided for @sourcePassagesGiven.
  ///
  /// In en, this message translates to:
  /// **'the passages below were given to the model'**
  String get sourcePassagesGiven;

  /// No description provided for @sourceReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Page could not be read ({error}) · only the search snippet was available'**
  String sourceReadFailed(String error);

  /// No description provided for @sourceSnippetOnly.
  ///
  /// In en, this message translates to:
  /// **'Search snippet only · the page was not read'**
  String get sourceSnippetOnly;

  /// No description provided for @sourceHeadlineOnly.
  ///
  /// In en, this message translates to:
  /// **'Headline and listing only · article body unavailable'**
  String get sourceHeadlineOnly;

  /// No description provided for @sourceExtractedSection.
  ///
  /// In en, this message translates to:
  /// **'Extracted passages · check the quoted text for support'**
  String get sourceExtractedSection;

  /// No description provided for @sourceArchiveSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Offline archive · {date} · {language}'**
  String sourceArchiveSnapshot(String date, String language);

  /// No description provided for @sourceOfflineLimitation.
  ///
  /// In en, this message translates to:
  /// **'This archive cannot verify current or changing facts.'**
  String get sourceOfflineLimitation;

  /// No description provided for @sourceArchiveUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The original archive is unavailable. Showing the saved excerpt.'**
  String get sourceArchiveUnavailable;

  /// No description provided for @sourceNoText.
  ///
  /// In en, this message translates to:
  /// **'No text.'**
  String get sourceNoText;

  /// No description provided for @sourceGivenHeading.
  ///
  /// In en, this message translates to:
  /// **'What the model was given'**
  String get sourceGivenHeading;

  /// No description provided for @sourcePassageCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 passage} other{{count} passages}}'**
  String sourcePassageCount(int count);

  /// No description provided for @sourceReadAt.
  ///
  /// In en, this message translates to:
  /// **'Read {time}'**
  String sourceReadAt(String time);

  /// No description provided for @sourceOpenArchived.
  ///
  /// In en, this message translates to:
  /// **'Open offline article'**
  String get sourceOpenArchived;

  /// No description provided for @sourceCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get sourceCopyLink;

  /// No description provided for @sourceLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get sourceLinkCopied;

  /// No description provided for @sourceAddress.
  ///
  /// In en, this message translates to:
  /// **'Full address'**
  String get sourceAddress;

  /// No description provided for @sourceFromKnowledge.
  ///
  /// In en, this message translates to:
  /// **'From your knowledge library ({title}).'**
  String sourceFromKnowledge(String title);

  /// No description provided for @fitFits.
  ///
  /// In en, this message translates to:
  /// **'Fits this phone'**
  String get fitFits;

  /// No description provided for @fitTight.
  ///
  /// In en, this message translates to:
  /// **'Tight on RAM'**
  String get fitTight;

  /// No description provided for @fitTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Too large for this phone'**
  String get fitTooLarge;

  /// No description provided for @configApplyNote.
  ///
  /// In en, this message translates to:
  /// **'Applying replaces that model\'s profile. Web research and hardware stay as you set them.'**
  String get configApplyNote;

  /// No description provided for @configApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied to {model}. It takes effect on the next answer.'**
  String configApplied(String model);

  /// No description provided for @storageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable on this device'**
  String get storageUnavailable;

  /// No description provided for @modelProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'{model} profile'**
  String modelProfileTitle(String model);

  /// No description provided for @modelProfileScope.
  ///
  /// In en, this message translates to:
  /// **'Model profile'**
  String get modelProfileScope;

  /// No description provided for @conversationsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load conversations.\n{error}'**
  String conversationsLoadFailed(String error);

  /// No description provided for @adapterUnknownArchitecture.
  ///
  /// In en, this message translates to:
  /// **'unknown architecture'**
  String get adapterUnknownArchitecture;

  /// No description provided for @adapterAppliedAt.
  ///
  /// In en, this message translates to:
  /// **'Applied at scale {scale}'**
  String adapterAppliedAt(String scale);

  /// No description provided for @adapterNotApplied.
  ///
  /// In en, this message translates to:
  /// **'Not applied'**
  String get adapterNotApplied;

  /// No description provided for @noticeUpdatingMemory.
  ///
  /// In en, this message translates to:
  /// **'Updating memory…'**
  String get noticeUpdatingMemory;

  /// No description provided for @noticeWeatherLoading.
  ///
  /// In en, this message translates to:
  /// **'Weather for {place} from DuckDuckGo…'**
  String noticeWeatherLoading(String place);

  /// No description provided for @noticeWeatherDone.
  ///
  /// In en, this message translates to:
  /// **'Weather for {place} from DuckDuckGo (Apple WeatherKit).'**
  String noticeWeatherDone(String place);

  /// No description provided for @noticeCollectingNews.
  ///
  /// In en, this message translates to:
  /// **'Collecting the latest news…'**
  String get noticeCollectingNews;

  /// No description provided for @noticeWebOffUnverified.
  ///
  /// In en, this message translates to:
  /// **'Web search is off. Current information has not been verified.'**
  String get noticeWebOffUnverified;

  /// No description provided for @noticeOpeningStory.
  ///
  /// In en, this message translates to:
  /// **'Opening that story…'**
  String get noticeOpeningStory;

  /// No description provided for @noticeStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping…'**
  String get noticeStopping;

  /// No description provided for @noticeSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching DuckDuckGo…'**
  String get noticeSearching;

  /// No description provided for @noticeCheckingWikipedia.
  ///
  /// In en, this message translates to:
  /// **'Checking Wikipedia…'**
  String get noticeCheckingWikipedia;

  /// No description provided for @noticeRecallArticle.
  ///
  /// In en, this message translates to:
  /// **'Read the article behind that story, plus {count, plural, =1{1 earlier source} other{{count} earlier sources}} from this chat.'**
  String noticeRecallArticle(int count);

  /// No description provided for @noticeRecallPages.
  ///
  /// In en, this message translates to:
  /// **'Answering from {count, plural, =1{1 page} other{{count} pages}} already read in this chat.'**
  String noticeRecallPages(int count);

  /// No description provided for @noticeImageRemoteOff.
  ///
  /// In en, this message translates to:
  /// **'Image input is disabled for the remote server. Enable it in Remote server settings if the selected model supports vision.'**
  String get noticeImageRemoteOff;

  /// No description provided for @noticeImageNoVision.
  ///
  /// In en, this message translates to:
  /// **'This model cannot see photos. Add its vision file under Models, or pick a vision model.'**
  String get noticeImageNoVision;

  /// No description provided for @noticeKnowledgeDocs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 document} other{{count} documents}} from “{collection}”'**
  String noticeKnowledgeDocs(int count, String collection);

  /// No description provided for @noticePlusWebResults.
  ///
  /// In en, this message translates to:
  /// **' plus {count, plural, =1{1 web result} other{{count} web results}}'**
  String noticePlusWebResults(int count);

  /// No description provided for @noticeUsingTool.
  ///
  /// In en, this message translates to:
  /// **'Using {tool}{args}…'**
  String noticeUsingTool(String tool, String args);

  /// No description provided for @noticeStopped.
  ///
  /// In en, this message translates to:
  /// **'Generation stopped. Any partial response was kept.'**
  String get noticeStopped;

  /// No description provided for @noticeTrimmed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 earlier message was} other{{count} earlier messages were}} omitted from the model context; they remain in your history.'**
  String noticeTrimmed(int count);

  /// No description provided for @noticeTokenLimit.
  ///
  /// In en, this message translates to:
  /// **'The answer stopped at the {count}-token limit. Tap Continue, or raise Max tokens under Settings > Sampling.'**
  String noticeTokenLimit(int count);

  /// No description provided for @noticeStopSequence.
  ///
  /// In en, this message translates to:
  /// **'The answer ended at a stop sequence.'**
  String get noticeStopSequence;

  /// No description provided for @noticeResearchSkipped.
  ///
  /// In en, this message translates to:
  /// **'The model answered without searching, so nothing here was verified this turn. Regenerate, or turn Model-driven research off to use the fixed search.'**
  String get noticeResearchSkipped;

  /// No description provided for @noticeNoSourcesWebOff.
  ///
  /// In en, this message translates to:
  /// **'Web research is off, so the model had no sources. Tap the Local pill to turn it on.'**
  String get noticeNoSourcesWebOff;

  /// No description provided for @noticeNoSourcesNoSearch.
  ///
  /// In en, this message translates to:
  /// **'No search ran for this message, so the model had no sources. Switch the pill to Web · always, or ask with \"search for …\".'**
  String get noticeNoSourcesNoSearch;

  /// No description provided for @noticeStoriesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 story} other{{count} stories}}'**
  String noticeStoriesCount(int count);

  /// No description provided for @noticeOutletsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 outlet} other{{count} outlets}}'**
  String noticeOutletsCount(int count);

  /// No description provided for @noticeArticlesRead.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 article read} other{{count} articles read}}'**
  String noticeArticlesRead(int count);

  /// No description provided for @noticeNewsSummary.
  ///
  /// In en, this message translates to:
  /// **'{stories} from {outlets}{articles} in {seconds} s.'**
  String noticeNewsSummary(
    String stories,
    String outlets,
    String articles,
    String seconds,
  );

  /// No description provided for @noticeLinkUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The linked page could not be read.'**
  String get noticeLinkUnreadable;

  /// No description provided for @noticeNoWebResults.
  ///
  /// In en, this message translates to:
  /// **'No web results. Current information could not be verified.'**
  String get noticeNoWebResults;

  /// No description provided for @noticeLinkedRead.
  ///
  /// In en, this message translates to:
  /// **'{read} of {total, plural, =1{1 linked page} other{{total} linked pages}} read.'**
  String noticeLinkedRead(int read, int total);

  /// No description provided for @noticePagesRead.
  ///
  /// In en, this message translates to:
  /// **'{read, plural, =1{1 page} other{{read} pages}} read from {results} results{queries}.'**
  String noticePagesRead(int read, int results, String queries);

  /// No description provided for @noticeQueries.
  ///
  /// In en, this message translates to:
  /// **' ({count} queries)'**
  String noticeQueries(int count);

  /// No description provided for @noticeEvidenceNoFit.
  ///
  /// In en, this message translates to:
  /// **'Web evidence could not fit. Increase context or reduce response length.'**
  String get noticeEvidenceNoFit;

  /// No description provided for @noticeWaitingServer.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the device server to finish a request from {client}…'**
  String noticeWaitingServer(String client);

  /// No description provided for @noticeReadingPage.
  ///
  /// In en, this message translates to:
  /// **'Reading {n} of {limit}{host}…'**
  String noticeReadingPage(int n, int limit, String host);

  /// No description provided for @noticeToolCut.
  ///
  /// In en, this message translates to:
  /// **'Tool results were cut to fit the context ({count, plural, =1{1 cut} other{{count} cuts}}). Raise the context size or lower the per-tool output budget.'**
  String noticeToolCut(int count);

  /// No description provided for @noticeDocCut.
  ///
  /// In en, this message translates to:
  /// **'Attached text was cut to fit the context ({percent}% kept). Raise the context size for the whole file.'**
  String noticeDocCut(int percent);

  /// No description provided for @noticeRefusal.
  ///
  /// In en, this message translates to:
  /// **'The model said it cannot browse even though {count, plural, =1{1 source was} other{{count} sources were}} supplied. Regenerate, or try a different model.'**
  String noticeRefusal(int count);

  /// No description provided for @noticeNoCitations.
  ///
  /// In en, this message translates to:
  /// **'The answer cites none of the {count, plural, =1{1 supplied source} other{{count} supplied sources}}; treat it as unverified.'**
  String noticeNoCitations(int count);

  /// No description provided for @noticeBogusCitations.
  ///
  /// In en, this message translates to:
  /// **'The answer cites source {cited}, which was not supplied; only [1]–[{count}] exist.'**
  String noticeBogusCitations(String cited, int count);

  /// No description provided for @noticeFigures.
  ///
  /// In en, this message translates to:
  /// **'Not found in the sources: {figures}{more}. Treat these figures as unverified.'**
  String noticeFigures(String figures, String more);

  /// No description provided for @noticeFiguresMiscited.
  ///
  /// In en, this message translates to:
  /// **'Not in the source cited for them: {figures}{more}. Another source has them; check the citation.'**
  String noticeFiguresMiscited(String figures, String more);

  /// No description provided for @noticeCitationsMatched.
  ///
  /// In en, this message translates to:
  /// **'The model cited no sources; the [n] marks were matched to the sources by their words and figures.'**
  String get noticeCitationsMatched;

  /// No description provided for @noticeAndMore.
  ///
  /// In en, this message translates to:
  /// **' and {count} more'**
  String noticeAndMore(int count);

  /// No description provided for @searchChallenge.
  ///
  /// In en, this message translates to:
  /// **'DuckDuckGo asked for a bot check, so automatic search is paused for a minute. Pasted links still work.'**
  String get searchChallenge;

  /// No description provided for @searchCooldown.
  ///
  /// In en, this message translates to:
  /// **'Search is paused after a DuckDuckGo block; it resumes in {seconds} s. Pasted links still work.'**
  String searchCooldown(int seconds);

  /// No description provided for @searchRateLimit.
  ///
  /// In en, this message translates to:
  /// **'DuckDuckGo is rate-limiting searches; paused for a minute. Pasted links still work.'**
  String get searchRateLimit;

  /// No description provided for @searchMarkup.
  ///
  /// In en, this message translates to:
  /// **'DuckDuckGo changed its results page and they could not be parsed. Pasted links still work; an app update is needed for search.'**
  String get searchMarkup;

  /// No description provided for @searchUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Web search unavailable (no connection or DuckDuckGo unreachable). Current information could not be verified.'**
  String get searchUnavailable;

  /// No description provided for @noticeThrottle.
  ///
  /// In en, this message translates to:
  /// **'Speed dropped {drop}% ({from} → {to} tok/s). The phone may be throttling; try a shorter context, fewer GPU layers, or a smaller model.'**
  String noticeThrottle(int drop, String from, String to);

  /// No description provided for @outputGrammarCut.
  ///
  /// In en, this message translates to:
  /// **'The grammar-constrained output was cut at the token limit.'**
  String get outputGrammarCut;

  /// No description provided for @outputSchemaMismatch.
  ///
  /// In en, this message translates to:
  /// **'The output is valid JSON but not the object the schema asks for.'**
  String get outputSchemaMismatch;

  /// No description provided for @outputJsonCut.
  ///
  /// In en, this message translates to:
  /// **'The JSON output was cut at the {count}-token limit and does not parse. Raise Max tokens.'**
  String outputJsonCut(int count);

  /// No description provided for @outputNotJson.
  ///
  /// In en, this message translates to:
  /// **'The output is not valid JSON.'**
  String get outputNotJson;

  /// No description provided for @noticeBatterySaver.
  ///
  /// In en, this message translates to:
  /// **'Battery saver ({reason}): no thinking, answers up to {tokens} tokens, fewer pages read.'**
  String noticeBatterySaver(String reason, int tokens);

  /// No description provided for @saverReasonBattery.
  ///
  /// In en, this message translates to:
  /// **'battery {level}%'**
  String saverReasonBattery(int level);

  /// No description provided for @saverReasonHot.
  ///
  /// In en, this message translates to:
  /// **'phone hot: {label}'**
  String saverReasonHot(String label);

  /// No description provided for @newsCollecting.
  ///
  /// In en, this message translates to:
  /// **'Collecting today\'s stories from DuckDuckGo News and {count, plural, =1{1 publisher} other{{count} publishers}}…'**
  String newsCollecting(int count);

  /// No description provided for @newsReadingArticles.
  ///
  /// In en, this message translates to:
  /// **'Reading {count, plural, =1{1 article} other{{count} articles}}…'**
  String newsReadingArticles(int count);

  /// No description provided for @chatErrorNoModel.
  ///
  /// In en, this message translates to:
  /// **'Add a model in the Models tab, then send your message.'**
  String get chatErrorNoModel;

  /// No description provided for @chatErrorSave.
  ///
  /// In en, this message translates to:
  /// **'Could not save response: {error}. Copy the response before leaving this chat.'**
  String chatErrorSave(String error);

  /// No description provided for @chatErrorNoText.
  ///
  /// In en, this message translates to:
  /// **'The model produced no text. Try a different template or model.'**
  String get chatErrorNoText;

  /// No description provided for @chatErrorServing.
  ///
  /// In en, this message translates to:
  /// **'This phone is serving {model} to another device. Stop the device server (Settings) to chat with another model.'**
  String chatErrorServing(String model);

  /// No description provided for @chatErrorServerBusy.
  ///
  /// In en, this message translates to:
  /// **'The device server is still answering {client}. Try again when it has finished.'**
  String chatErrorServerBusy(String client);

  /// No description provided for @settingGroupGeneration.
  ///
  /// In en, this message translates to:
  /// **'Generation'**
  String get settingGroupGeneration;

  /// No description provided for @settingGroupReasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get settingGroupReasoning;

  /// No description provided for @settingGroupWeb.
  ///
  /// In en, this message translates to:
  /// **'Web research'**
  String get settingGroupWeb;

  /// No description provided for @settingGroupTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get settingGroupTools;

  /// No description provided for @settingGroupOutput.
  ///
  /// In en, this message translates to:
  /// **'Structured output'**
  String get settingGroupOutput;

  /// No description provided for @settingGroupContext.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get settingGroupContext;

  /// No description provided for @settingGroupHardware.
  ///
  /// In en, this message translates to:
  /// **'Hardware'**
  String get settingGroupHardware;

  /// No description provided for @settingGroupPrompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get settingGroupPrompt;

  /// No description provided for @settingLabelSystemPrompt.
  ///
  /// In en, this message translates to:
  /// **'Custom instructions'**
  String get settingLabelSystemPrompt;

  /// No description provided for @settingLabelTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get settingLabelTemperature;

  /// No description provided for @settingLabelTopP.
  ///
  /// In en, this message translates to:
  /// **'Top-P'**
  String get settingLabelTopP;

  /// No description provided for @settingLabelMinP.
  ///
  /// In en, this message translates to:
  /// **'Min-P'**
  String get settingLabelMinP;

  /// No description provided for @settingLabelTopK.
  ///
  /// In en, this message translates to:
  /// **'Top-K'**
  String get settingLabelTopK;

  /// No description provided for @settingLabelTypicalP.
  ///
  /// In en, this message translates to:
  /// **'Typical-P'**
  String get settingLabelTypicalP;

  /// No description provided for @settingLabelRepetitionPenalty.
  ///
  /// In en, this message translates to:
  /// **'Repetition penalty'**
  String get settingLabelRepetitionPenalty;

  /// No description provided for @settingLabelPresencePenalty.
  ///
  /// In en, this message translates to:
  /// **'Presence penalty'**
  String get settingLabelPresencePenalty;

  /// No description provided for @settingLabelFrequencyPenalty.
  ///
  /// In en, this message translates to:
  /// **'Frequency penalty'**
  String get settingLabelFrequencyPenalty;

  /// No description provided for @settingLabelRepeatLastN.
  ///
  /// In en, this message translates to:
  /// **'Penalty window (tokens)'**
  String get settingLabelRepeatLastN;

  /// No description provided for @settingLabelMaxTokens.
  ///
  /// In en, this message translates to:
  /// **'Max tokens'**
  String get settingLabelMaxTokens;

  /// No description provided for @settingLabelSeed.
  ///
  /// In en, this message translates to:
  /// **'Seed (0 = random)'**
  String get settingLabelSeed;

  /// No description provided for @settingLabelStopSequences.
  ///
  /// In en, this message translates to:
  /// **'Stop sequences'**
  String get settingLabelStopSequences;

  /// No description provided for @settingLabelThinkingModeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Thinking mode'**
  String get settingLabelThinkingModeEnabled;

  /// No description provided for @settingLabelThinkingBudgetTokens.
  ///
  /// In en, this message translates to:
  /// **'Thinking budget (0 = unlimited)'**
  String get settingLabelThinkingBudgetTokens;

  /// No description provided for @settingLabelWebMode.
  ///
  /// In en, this message translates to:
  /// **'Web research'**
  String get settingLabelWebMode;

  /// No description provided for @settingLabelResearchLoop.
  ///
  /// In en, this message translates to:
  /// **'Model-driven research'**
  String get settingLabelResearchLoop;

  /// No description provided for @settingLabelMaxPagesRead.
  ///
  /// In en, this message translates to:
  /// **'Pages to read'**
  String get settingLabelMaxPagesRead;

  /// No description provided for @settingLabelEvidencePassages.
  ///
  /// In en, this message translates to:
  /// **'Passages given to the model'**
  String get settingLabelEvidencePassages;

  /// No description provided for @settingLabelKnowledgeCollection.
  ///
  /// In en, this message translates to:
  /// **'Knowledge collection'**
  String get settingLabelKnowledgeCollection;

  /// No description provided for @settingLabelToolsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Tool calling'**
  String get settingLabelToolsEnabled;

  /// No description provided for @settingLabelToolChoice.
  ///
  /// In en, this message translates to:
  /// **'Tool use'**
  String get settingLabelToolChoice;

  /// No description provided for @settingLabelToolMaxRounds.
  ///
  /// In en, this message translates to:
  /// **'Tool rounds per answer'**
  String get settingLabelToolMaxRounds;

  /// No description provided for @settingLabelResponseFormat.
  ///
  /// In en, this message translates to:
  /// **'Response format'**
  String get settingLabelResponseFormat;

  /// No description provided for @settingLabelJsonSchema.
  ///
  /// In en, this message translates to:
  /// **'JSON schema'**
  String get settingLabelJsonSchema;

  /// No description provided for @settingLabelGrammar.
  ///
  /// In en, this message translates to:
  /// **'GBNF grammar'**
  String get settingLabelGrammar;

  /// No description provided for @settingLabelContextSize.
  ///
  /// In en, this message translates to:
  /// **'Context size'**
  String get settingLabelContextSize;

  /// No description provided for @settingLabelPromptCache.
  ///
  /// In en, this message translates to:
  /// **'Keep conversation in context'**
  String get settingLabelPromptCache;

  /// No description provided for @settingLabelBackend.
  ///
  /// In en, this message translates to:
  /// **'Backend'**
  String get settingLabelBackend;

  /// No description provided for @settingLabelNGpuLayers.
  ///
  /// In en, this message translates to:
  /// **'GPU layers'**
  String get settingLabelNGpuLayers;

  /// No description provided for @settingLabelCpuThreads.
  ///
  /// In en, this message translates to:
  /// **'CPU threads (decode, 0 = auto)'**
  String get settingLabelCpuThreads;

  /// No description provided for @settingLabelBatchThreads.
  ///
  /// In en, this message translates to:
  /// **'CPU threads (prefill, 0 = auto)'**
  String get settingLabelBatchThreads;

  /// No description provided for @settingLabelFlashAttention.
  ///
  /// In en, this message translates to:
  /// **'Flash attention'**
  String get settingLabelFlashAttention;

  /// No description provided for @settingLabelKvCacheType.
  ///
  /// In en, this message translates to:
  /// **'K cache type'**
  String get settingLabelKvCacheType;

  /// No description provided for @settingLabelVCacheType.
  ///
  /// In en, this message translates to:
  /// **'V cache type (empty = same as K)'**
  String get settingLabelVCacheType;

  /// No description provided for @settingLabelRopeScaling.
  ///
  /// In en, this message translates to:
  /// **'RoPE scaling'**
  String get settingLabelRopeScaling;

  /// No description provided for @settingLabelDraftModelId.
  ///
  /// In en, this message translates to:
  /// **'Draft model (speculative decoding)'**
  String get settingLabelDraftModelId;

  /// No description provided for @hostLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'Local network and VPN only'**
  String get hostLocalOnly;

  /// No description provided for @hostLocalOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Devices on this Wi-Fi, your hotspot or your VPN (Tailscale, WireGuard…) can connect with the token. Requests from the public internet are refused.'**
  String get hostLocalOnlyHint;

  /// No description provided for @settingEmptyMeans.
  ///
  /// In en, this message translates to:
  /// **'Empty = {value}'**
  String settingEmptyMeans(String value);

  /// No description provided for @settingEffectiveValue.
  ///
  /// In en, this message translates to:
  /// **'Effective: {value}'**
  String settingEffectiveValue(String value);

  /// No description provided for @settingInherit.
  ///
  /// In en, this message translates to:
  /// **'Inherit ({value})'**
  String settingInherit(String value);

  /// No description provided for @remoteScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get remoteScanQr;

  /// No description provided for @remoteScanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code on the other phone (Settings > Use this device as a server).'**
  String get remoteScanHint;

  /// No description provided for @remoteScanInvalid.
  ///
  /// In en, this message translates to:
  /// **'That QR code is not an OnDevice LLM connection. Keep aiming at the server’s code.'**
  String get remoteScanInvalid;

  /// No description provided for @remoteScanNoCamera.
  ///
  /// In en, this message translates to:
  /// **'The camera is unavailable: {error}'**
  String remoteScanNoCamera(String error);

  /// No description provided for @remoteNameConnection.
  ///
  /// In en, this message translates to:
  /// **'Name this connection'**
  String get remoteNameConnection;

  /// No description provided for @remoteNameHint.
  ///
  /// In en, this message translates to:
  /// **'For example: Living-room PC'**
  String get remoteNameHint;

  /// No description provided for @answerFromMemory.
  ///
  /// In en, this message translates to:
  /// **'From the model’s memory — may be out of date.'**
  String get answerFromMemory;

  /// No description provided for @searchTheWeb.
  ///
  /// In en, this message translates to:
  /// **'Search the web'**
  String get searchTheWeb;

  /// No description provided for @searchMissesTitle.
  ///
  /// In en, this message translates to:
  /// **'Questions sent to the web by hand'**
  String get searchMissesTitle;

  /// No description provided for @searchMissesHint.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None yet. When an answer came from memory and you tapped Search the web, the question is kept here (on this phone only) so the search keywords can be improved.} =1{1 question. Copy them to improve the search keywords; they never leave this phone otherwise.} other{{count} questions. Copy them to improve the search keywords; they never leave this phone otherwise.}}'**
  String searchMissesHint(int count);

  /// No description provided for @commonCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied.'**
  String get commonCopied;

  /// No description provided for @settingsSearchSection.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get settingsSearchSection;

  /// No description provided for @searchRegionHint.
  ///
  /// In en, this message translates to:
  /// **'Where news briefings and search results come from. Automatic follows the app language and the phone’s country setting (now {region}).'**
  String searchRegionHint(String region);

  /// No description provided for @searchRegionAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get searchRegionAutomatic;

  /// No description provided for @researchLoopHint.
  ///
  /// In en, this message translates to:
  /// **'Questions that would be searched are researched by the model itself: it searches, picks pages to read, searches again if needed, then answers with citations. Pasted links are still read directly. Slower per question; compare on your own questions.'**
  String get researchLoopHint;

  /// No description provided for @researchLoopNeedsTools.
  ///
  /// In en, this message translates to:
  /// **'Needs tool calling on with the web tools (Settings > Tools).'**
  String get researchLoopNeedsTools;

  /// No description provided for @selectionTitle.
  ///
  /// In en, this message translates to:
  /// **'What should I do with the selected text?'**
  String get selectionTitle;

  /// No description provided for @selectionExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain it'**
  String get selectionExplain;

  /// No description provided for @selectionSummarize.
  ///
  /// In en, this message translates to:
  /// **'Summarize it'**
  String get selectionSummarize;

  /// No description provided for @selectionTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate it'**
  String get selectionTranslate;

  /// No description provided for @selectionFix.
  ///
  /// In en, this message translates to:
  /// **'Fix spelling and grammar'**
  String get selectionFix;

  /// No description provided for @selectionAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask about it'**
  String get selectionAsk;

  /// No description provided for @quickDescribe.
  ///
  /// In en, this message translates to:
  /// **'Describe'**
  String get quickDescribe;

  /// No description provided for @quickDescribePrompt.
  ///
  /// In en, this message translates to:
  /// **'Describe this photo in detail.'**
  String get quickDescribePrompt;

  /// No description provided for @quickExtractText.
  ///
  /// In en, this message translates to:
  /// **'Extract text'**
  String get quickExtractText;

  /// No description provided for @quickExtractTextPrompt.
  ///
  /// In en, this message translates to:
  /// **'Transcribe all the text in this image exactly as written, keeping the layout.'**
  String get quickExtractTextPrompt;

  /// No description provided for @quickTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get quickTranslate;

  /// No description provided for @quickTranslatePrompt.
  ///
  /// In en, this message translates to:
  /// **'Translate all the text in this image into English.'**
  String get quickTranslatePrompt;

  /// No description provided for @quickSolve.
  ///
  /// In en, this message translates to:
  /// **'Solve'**
  String get quickSolve;

  /// No description provided for @quickSolvePrompt.
  ///
  /// In en, this message translates to:
  /// **'Solve the problem shown in this image and explain each step.'**
  String get quickSolvePrompt;

  /// No description provided for @quickExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain'**
  String get quickExplain;

  /// No description provided for @quickExplainPrompt.
  ///
  /// In en, this message translates to:
  /// **'Explain what this image shows and why it matters.'**
  String get quickExplainPrompt;

  /// No description provided for @quickIdentify.
  ///
  /// In en, this message translates to:
  /// **'Identify'**
  String get quickIdentify;

  /// No description provided for @quickIdentifyPrompt.
  ///
  /// In en, this message translates to:
  /// **'What is this? Identify it and tell me what you know about it.'**
  String get quickIdentifyPrompt;

  /// No description provided for @quickSummarise.
  ///
  /// In en, this message translates to:
  /// **'Summarise'**
  String get quickSummarise;

  /// No description provided for @quickSummarisePrompt.
  ///
  /// In en, this message translates to:
  /// **'Summarise this document: one-sentence takeaway, then the key points.'**
  String get quickSummarisePrompt;

  /// No description provided for @quickKeyPoints.
  ///
  /// In en, this message translates to:
  /// **'Key points'**
  String get quickKeyPoints;

  /// No description provided for @quickKeyPointsPrompt.
  ///
  /// In en, this message translates to:
  /// **'List the key points of this document as short bullets.'**
  String get quickKeyPointsPrompt;

  /// No description provided for @quickExplainSimply.
  ///
  /// In en, this message translates to:
  /// **'Explain simply'**
  String get quickExplainSimply;

  /// No description provided for @quickExplainSimplyPrompt.
  ///
  /// In en, this message translates to:
  /// **'Explain this document in plain language for someone new to the topic.'**
  String get quickExplainSimplyPrompt;

  /// No description provided for @quickActionItems.
  ///
  /// In en, this message translates to:
  /// **'Action items'**
  String get quickActionItems;

  /// No description provided for @quickActionItemsPrompt.
  ///
  /// In en, this message translates to:
  /// **'List every action item, deadline and decision in this document.'**
  String get quickActionItemsPrompt;

  /// No description provided for @quickQuestions.
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get quickQuestions;

  /// No description provided for @quickQuestionsPrompt.
  ///
  /// In en, this message translates to:
  /// **'What questions should I ask about this document before relying on it?'**
  String get quickQuestionsPrompt;

  /// No description provided for @sectionVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get sectionVoice;

  /// No description provided for @sectionAutomation.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts & automation'**
  String get sectionAutomation;

  /// No description provided for @sectionModelConnections.
  ///
  /// In en, this message translates to:
  /// **'Model & connections'**
  String get sectionModelConnections;

  /// No description provided for @sectionAppearanceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Appearance & language'**
  String get sectionAppearanceLanguage;

  /// No description provided for @sectionData.
  ///
  /// In en, this message translates to:
  /// **'Your data'**
  String get sectionData;

  /// No description provided for @advancedNote.
  ///
  /// In en, this message translates to:
  /// **'The defaults work well. These are for fine-tuning speed, memory use and output.'**
  String get advancedNote;

  /// No description provided for @remoteRowOff.
  ///
  /// In en, this message translates to:
  /// **'Off · the model runs on this phone'**
  String get remoteRowOff;

  /// No description provided for @backupRowHint.
  ///
  /// In en, this message translates to:
  /// **'Save or restore chats, attachments and settings'**
  String get backupRowHint;

  /// No description provided for @remoteRowOn.
  ///
  /// In en, this message translates to:
  /// **'On · {name}'**
  String remoteRowOn(String name);

  /// No description provided for @sectionCachePrecision.
  ///
  /// In en, this message translates to:
  /// **'Cache precision'**
  String get sectionCachePrecision;

  /// No description provided for @sectionCapabilities.
  ///
  /// In en, this message translates to:
  /// **'Capabilities'**
  String get sectionCapabilities;

  /// No description provided for @sectionConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get sectionConnections;

  /// No description provided for @sectionEvidence.
  ///
  /// In en, this message translates to:
  /// **'Sources given to the model'**
  String get sectionEvidence;

  /// No description provided for @sectionExtraSamplers.
  ///
  /// In en, this message translates to:
  /// **'Extra samplers'**
  String get sectionExtraSamplers;

  /// No description provided for @sectionLayers.
  ///
  /// In en, this message translates to:
  /// **'Layers, lowest first'**
  String get sectionLayers;

  /// No description provided for @sectionPenalties.
  ///
  /// In en, this message translates to:
  /// **'Penalties'**
  String get sectionPenalties;

  /// No description provided for @sectionRope.
  ///
  /// In en, this message translates to:
  /// **'Position encoding (RoPE / YaRN)'**
  String get sectionRope;

  /// No description provided for @sectionReasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get sectionReasoning;

  /// No description provided for @sectionReproducibility.
  ///
  /// In en, this message translates to:
  /// **'Reproducibility'**
  String get sectionReproducibility;

  /// No description provided for @sectionSamplerOrder.
  ///
  /// In en, this message translates to:
  /// **'Sampler order'**
  String get sectionSamplerOrder;

  /// No description provided for @sectionSpeculative.
  ///
  /// In en, this message translates to:
  /// **'Speculative decoding (experimental)'**
  String get sectionSpeculative;

  /// No description provided for @sectionTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get sectionTools;

  /// No description provided for @chatSettingsMenu.
  ///
  /// In en, this message translates to:
  /// **'This chat\'s settings'**
  String get chatSettingsMenu;

  /// No description provided for @chatSettingsMenuCount.
  ///
  /// In en, this message translates to:
  /// **'This chat\'s settings · {count}'**
  String chatSettingsMenuCount(int count);

  /// No description provided for @remoteUsingSummary.
  ///
  /// In en, this message translates to:
  /// **'Chats run on {name} ({host}). Local models are not loaded.'**
  String remoteUsingSummary(String name, String host);

  /// No description provided for @remoteNeedsConnection.
  ///
  /// In en, this message translates to:
  /// **'Add a connection below to turn it on.'**
  String get remoteNeedsConnection;

  /// No description provided for @remoteNeedsUrl.
  ///
  /// In en, this message translates to:
  /// **'The selected connection needs a valid http(s) address.'**
  String get remoteNeedsUrl;

  /// No description provided for @remoteNoUrl.
  ///
  /// In en, this message translates to:
  /// **'no address'**
  String get remoteNoUrl;

  /// No description provided for @remoteNoKey.
  ///
  /// In en, this message translates to:
  /// **'no key'**
  String get remoteNoKey;

  /// No description provided for @remoteScanShort.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get remoteScanShort;

  /// No description provided for @remotePasteShort.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get remotePasteShort;

  /// No description provided for @modelProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get modelProfile;

  /// No description provided for @modelProfileCount.
  ///
  /// In en, this message translates to:
  /// **'Profile · {count}'**
  String modelProfileCount(int count);

  /// No description provided for @modelsFootnote.
  ///
  /// In en, this message translates to:
  /// **'Larger models give better answers but are slower and use more memory. The badge on each model says whether it fits this phone.'**
  String get modelsFootnote;

  /// No description provided for @benchmarkRunAgain.
  ///
  /// In en, this message translates to:
  /// **'Run again'**
  String get benchmarkRunAgain;

  /// No description provided for @benchmarkMeasuredAt.
  ///
  /// In en, this message translates to:
  /// **'Measured {date}'**
  String benchmarkMeasuredAt(String date);

  /// No description provided for @unloadShort.
  ///
  /// In en, this message translates to:
  /// **'Unload'**
  String get unloadShort;

  /// No description provided for @unsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedChanges;

  /// No description provided for @savedNotice.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedNotice;

  /// No description provided for @pickerLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get pickerLibrary;

  /// No description provided for @pickerConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get pickerConnections;

  /// No description provided for @pickerReasoning.
  ///
  /// In en, this message translates to:
  /// **'reasoning'**
  String get pickerReasoning;

  /// No description provided for @pickerTightRam.
  ///
  /// In en, this message translates to:
  /// **'tight on RAM'**
  String get pickerTightRam;

  /// No description provided for @pickerTooLarge.
  ///
  /// In en, this message translates to:
  /// **'too large for this phone'**
  String get pickerTooLarge;

  /// No description provided for @pickerNoKey.
  ///
  /// In en, this message translates to:
  /// **'no key yet'**
  String get pickerNoKey;

  /// No description provided for @goalPhaseVerifying.
  ///
  /// In en, this message translates to:
  /// **'Checking the report against the findings'**
  String get goalPhaseVerifying;

  /// No description provided for @goalGuardrails.
  ///
  /// In en, this message translates to:
  /// **'Guardrails'**
  String get goalGuardrails;

  /// No description provided for @goalSubjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Stay on these names'**
  String get goalSubjectTitle;

  /// No description provided for @goalSubjectHint.
  ///
  /// In en, this message translates to:
  /// **'Found in your goal. The model must use them exactly; pages about similar models, versions or generations are left out.'**
  String get goalSubjectHint;

  /// No description provided for @goalSubjectNone.
  ///
  /// In en, this message translates to:
  /// **'No names found yet: products, people and places in your goal appear here as you type.'**
  String get goalSubjectNone;

  /// No description provided for @goalSubjectAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a name'**
  String get goalSubjectAdd;

  /// No description provided for @goalSubjectExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. Sony ZV-E10'**
  String get goalSubjectExample;

  /// No description provided for @goalSubjectReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get goalSubjectReset;

  /// No description provided for @goalRulesLabel.
  ///
  /// In en, this message translates to:
  /// **'Your rules (optional)'**
  String get goalRulesLabel;

  /// No description provided for @goalRulesHint.
  ///
  /// In en, this message translates to:
  /// **'One per line, e.g. Prices in CAD · Only 2026 sources · No rumours'**
  String get goalRulesHint;

  /// No description provided for @goalRulesBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Rules every goal follows'**
  String get goalRulesBuiltIn;

  /// No description provided for @goalRuleSubject.
  ///
  /// In en, this message translates to:
  /// **'Uses your names exactly; never swaps in a similar model, version or generation.'**
  String get goalRuleSubject;

  /// No description provided for @goalRuleEvidence.
  ///
  /// In en, this message translates to:
  /// **'States only facts from the sources, each with its citation; nothing from memory.'**
  String get goalRuleEvidence;

  /// No description provided for @goalRuleOffTopic.
  ///
  /// In en, this message translates to:
  /// **'Ignores sources about something else and says what is missing; never asks you for sources.'**
  String get goalRuleOffTopic;

  /// No description provided for @goalRuleFigures.
  ///
  /// In en, this message translates to:
  /// **'Copies numbers, dates and prices exactly; gives both sides when sources disagree.'**
  String get goalRuleFigures;

  /// No description provided for @goalRuleThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinks briefly before the plan and the evidence review; the steps and the report answer directly, so a run is faster.'**
  String get goalRuleThinking;

  /// No description provided for @goalRuleCheck.
  ///
  /// In en, this message translates to:
  /// **'Every step and the report are checked automatically; a failed check is redone once.'**
  String get goalRuleCheck;

  /// No description provided for @goalCheckDrift.
  ///
  /// In en, this message translates to:
  /// **'Mentions {names}, not the goal\'s subject'**
  String goalCheckDrift(String names);

  /// No description provided for @goalCheckOffTarget.
  ///
  /// In en, this message translates to:
  /// **'Researched {names} instead: left out of the report'**
  String goalCheckOffTarget(String names);

  /// No description provided for @goalCheckNoSources.
  ///
  /// In en, this message translates to:
  /// **'No sources found'**
  String get goalCheckNoSources;

  /// No description provided for @goalCheckNoCitations.
  ///
  /// In en, this message translates to:
  /// **'Cites no sources'**
  String get goalCheckNoCitations;

  /// No description provided for @goalCheckBadCitations.
  ///
  /// In en, this message translates to:
  /// **'Cites sources that do not exist: {numbers}'**
  String goalCheckBadCitations(String numbers);

  /// No description provided for @goalCheckFigures.
  ///
  /// In en, this message translates to:
  /// **'Figures found in no source: {figures}'**
  String goalCheckFigures(String figures);

  /// No description provided for @goalCheckDroppedFigures.
  ///
  /// In en, this message translates to:
  /// **'Left out figures no source states: {figures}'**
  String goalCheckDroppedFigures(String figures);

  /// No description provided for @goalCheckAskedUser.
  ///
  /// In en, this message translates to:
  /// **'Asked you for information'**
  String get goalCheckAskedUser;

  /// No description provided for @goalCheckRetried.
  ///
  /// In en, this message translates to:
  /// **'Researched again after a failed check'**
  String get goalCheckRetried;

  /// No description provided for @goalCheckRevised.
  ///
  /// In en, this message translates to:
  /// **'Rewritten once to fix the check'**
  String get goalCheckRevised;

  /// No description provided for @goalReportChecked.
  ///
  /// In en, this message translates to:
  /// **'Checked: names, citations and figures match the findings'**
  String get goalReportChecked;

  /// No description provided for @goalStepSearched.
  ///
  /// In en, this message translates to:
  /// **'Searched'**
  String get goalStepSearched;

  /// No description provided for @goalStepTools.
  ///
  /// In en, this message translates to:
  /// **'Tool calls'**
  String get goalStepTools;

  /// No description provided for @goalStepSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get goalStepSources;

  /// No description provided for @goalStepReasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get goalStepReasoning;

  /// No description provided for @goalStepStats.
  ///
  /// In en, this message translates to:
  /// **'{prompt} prompt + {tokens} generated tokens · {seconds} s · {tps} tok/s'**
  String goalStepStats(int prompt, int tokens, String seconds, String tps);

  /// No description provided for @goalStepSearchCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 search} other{{count} searches}}'**
  String goalStepSearchCount(int count);

  /// No description provided for @goalStepToolCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tool call} other{{count} tool calls}}'**
  String goalStepToolCount(int count);

  /// No description provided for @goalPlanNotes.
  ///
  /// In en, this message translates to:
  /// **'How the plan was made'**
  String get goalPlanNotes;

  /// No description provided for @goalReviewNotes.
  ///
  /// In en, this message translates to:
  /// **'Reviewer\'s reasoning'**
  String get goalReviewNotes;

  /// No description provided for @goalCheckLeak.
  ///
  /// In en, this message translates to:
  /// **'Reasoning that ran into the answer was removed'**
  String get goalCheckLeak;

  /// No description provided for @goalSmallModel.
  ///
  /// In en, this message translates to:
  /// **'{model} is a small model: goals are much more accurate with Gemma 4 E2B or a larger model (it stays on the subject and cites its sources).'**
  String goalSmallModel(String model);

  /// No description provided for @goalPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial result — more evidence needed'**
  String get goalPartial;

  /// No description provided for @goalCriteriaReview.
  ///
  /// In en, this message translates to:
  /// **'Success criteria'**
  String get goalCriteriaReview;

  /// No description provided for @goalEvidenceSteps.
  ///
  /// In en, this message translates to:
  /// **'Evidence: steps {steps}'**
  String goalEvidenceSteps(String steps);

  /// No description provided for @backupExportReady.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup handed to the export sheet.'**
  String get backupExportReady;

  /// No description provided for @remoteShareMemory.
  ///
  /// In en, this message translates to:
  /// **'Share memory with this connection'**
  String get remoteShareMemory;

  /// No description provided for @remoteShareMemoryHint.
  ///
  /// In en, this message translates to:
  /// **'Allow selected notes to be included in requests to this server.'**
  String get remoteShareMemoryHint;

  /// No description provided for @remoteLearnMemory.
  ///
  /// In en, this message translates to:
  /// **'Learn memory using this connection'**
  String get remoteLearnMemory;

  /// No description provided for @remoteLearnMemoryHint.
  ///
  /// In en, this message translates to:
  /// **'Allow a separate server request to extract durable facts from your messages. Simple explicit facts can still be saved locally when Memory is on.'**
  String get remoteLearnMemoryHint;

  /// No description provided for @memoryPin.
  ///
  /// In en, this message translates to:
  /// **'Always consider this note'**
  String get memoryPin;

  /// No description provided for @memoryUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin note'**
  String get memoryUnpin;

  /// No description provided for @memoryReconfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm this is still accurate'**
  String get memoryReconfirm;

  /// No description provided for @memoryExpire.
  ///
  /// In en, this message translates to:
  /// **'Expire in 30 days'**
  String get memoryExpire;

  /// No description provided for @memoryNoExpiry.
  ///
  /// In en, this message translates to:
  /// **'Remove expiry'**
  String get memoryNoExpiry;

  /// No description provided for @memoryExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String memoryExpires(String date);

  /// No description provided for @settingsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get settingsSearch;

  /// No description provided for @settingsFaster.
  ///
  /// In en, this message translates to:
  /// **'Faster replies'**
  String get settingsFaster;

  /// No description provided for @settingsDetailed.
  ///
  /// In en, this message translates to:
  /// **'More detail'**
  String get settingsDetailed;

  /// No description provided for @settingsLessMemory.
  ///
  /// In en, this message translates to:
  /// **'Use less RAM'**
  String get settingsLessMemory;

  /// No description provided for @imageTokenBudget.
  ///
  /// In en, this message translates to:
  /// **'Photo token budget'**
  String get imageTokenBudget;

  /// No description provided for @imageTokenBudgetHint.
  ///
  /// In en, this message translates to:
  /// **'More detail uses more memory and time. Reloads the model.'**
  String get imageTokenBudgetHint;

  /// No description provided for @documentPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get documentPreview;

  /// No description provided for @documentEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get documentEdit;

  /// No description provided for @documentDraftSaved.
  ///
  /// In en, this message translates to:
  /// **'Draft saved on this device'**
  String get documentDraftSaved;

  /// No description provided for @documentVersions.
  ///
  /// In en, this message translates to:
  /// **'Version history'**
  String get documentVersions;

  /// No description provided for @goalQuestionsTitle.
  ///
  /// In en, this message translates to:
  /// **'A few questions first'**
  String get goalQuestionsTitle;

  /// No description provided for @goalQuestionsHint.
  ///
  /// In en, this message translates to:
  /// **'Your preferences can make the report more useful. Choose an answer, type your own, or skip. Research waits until you continue.'**
  String get goalQuestionsHint;

  /// No description provided for @goalYourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Your answer (optional)'**
  String get goalYourAnswer;

  /// No description provided for @goalQuestionsLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get goalQuestionsLater;

  /// No description provided for @goalQuestionsSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip and continue'**
  String get goalQuestionsSkip;

  /// No description provided for @goalPhaseClarifying.
  ///
  /// In en, this message translates to:
  /// **'Checking whether clarification would help…'**
  String get goalPhaseClarifying;

  /// No description provided for @goalWaitingAnswers.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your answers'**
  String get goalWaitingAnswers;

  /// No description provided for @goalAnswerQuestions.
  ///
  /// In en, this message translates to:
  /// **'Answer questions'**
  String get goalAnswerQuestions;

  /// No description provided for @goalClarificationAnswers.
  ///
  /// In en, this message translates to:
  /// **'Your clarification answers'**
  String get goalClarificationAnswers;

  /// No description provided for @goalAssumptionsAllowed.
  ///
  /// In en, this message translates to:
  /// **'Skipped — the report will state its assumptions.'**
  String get goalAssumptionsAllowed;

  /// No description provided for @goalSearchGuidance.
  ///
  /// In en, this message translates to:
  /// **'Search and report direction'**
  String get goalSearchGuidance;

  /// No description provided for @goalSearchGuidanceHint.
  ///
  /// In en, this message translates to:
  /// **'Explain what the report missed, which questions to search, and what to emphasize.'**
  String get goalSearchGuidanceHint;

  /// No description provided for @goalRefineRun.
  ///
  /// In en, this message translates to:
  /// **'Save and research'**
  String get goalRefineRun;

  /// No description provided for @goalCriteriaSeparate.
  ///
  /// In en, this message translates to:
  /// **'One requirement per line, so coverage can be measured.'**
  String get goalCriteriaSeparate;

  /// No description provided for @goalCoverage.
  ///
  /// In en, this message translates to:
  /// **'Supported requirements: {percent}% · target {target}%'**
  String goalCoverage(Object percent, Object target);

  /// No description provided for @goalCompletionHint.
  ///
  /// In en, this message translates to:
  /// **'Stop when this share of requirements is supported. Remaining gaps stay visible; citations and factual checks still apply.'**
  String get goalCompletionHint;

  /// No description provided for @goalCompletionTarget.
  ///
  /// In en, this message translates to:
  /// **'Completion target'**
  String get goalCompletionTarget;

  /// No description provided for @goalRefine.
  ///
  /// In en, this message translates to:
  /// **'Edit goal / steer research'**
  String get goalRefine;

  /// No description provided for @memoryScanResult.
  ///
  /// In en, this message translates to:
  /// **'Recovered {count} memories from saved chats.'**
  String memoryScanResult(Object count);

  /// No description provided for @memoryScanHistory.
  ///
  /// In en, this message translates to:
  /// **'Scan saved chats for missed memories'**
  String get memoryScanHistory;

  /// No description provided for @goalEvidenceWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Compare evidence'**
  String get goalEvidenceWorkspace;

  /// No description provided for @goalEvidenceSnapshotHint.
  ///
  /// In en, this message translates to:
  /// **'Compare the saved source excerpts with the step findings. These are the excerpts the model used; a page opened today may have changed. A source or a passed automatic check does not by itself prove a claim.'**
  String get goalEvidenceSnapshotHint;

  /// No description provided for @goalEvidenceSupported.
  ///
  /// In en, this message translates to:
  /// **'Requirement supported'**
  String get goalEvidenceSupported;

  /// No description provided for @goalEvidenceGap.
  ///
  /// In en, this message translates to:
  /// **'Requirement needs evidence'**
  String get goalEvidenceGap;

  /// No description provided for @goalEvidenceMissing.
  ///
  /// In en, this message translates to:
  /// **'No retrieved excerpt was saved for this source.'**
  String get goalEvidenceMissing;

  /// No description provided for @goalEvidenceFind.
  ///
  /// In en, this message translates to:
  /// **'Find text in these sources'**
  String get goalEvidenceFind;

  /// No description provided for @goalEvidencePublished.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get goalEvidencePublished;

  /// No description provided for @goalEvidenceRetrieved.
  ///
  /// In en, this message translates to:
  /// **'Retrieved'**
  String get goalEvidenceRetrieved;

  /// No description provided for @goalEvidenceOpen.
  ///
  /// In en, this message translates to:
  /// **'Open page'**
  String get goalEvidenceOpen;

  /// No description provided for @goalEvidenceCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy excerpt'**
  String get goalEvidenceCopy;

  /// No description provided for @goalEvidenceNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No match in this saved excerpt.'**
  String get goalEvidenceNoMatch;

  /// No description provided for @goalEvidenceExcluded.
  ///
  /// In en, this message translates to:
  /// **'This step was excluded from report evidence.'**
  String get goalEvidenceExcluded;

  /// No description provided for @contextInspector.
  ///
  /// In en, this message translates to:
  /// **'Context inspector'**
  String get contextInspector;

  /// No description provided for @contextSnapshotHint.
  ///
  /// In en, this message translates to:
  /// **'Saved context selection for this answer. Excerpts help you inspect it; they are not automatically used as summaries in future answers.'**
  String get contextSnapshotHint;

  /// No description provided for @contextSnapshotMissing.
  ///
  /// In en, this message translates to:
  /// **'This older answer has no saved context snapshot.'**
  String get contextSnapshotMissing;

  /// No description provided for @contextTokens.
  ///
  /// In en, this message translates to:
  /// **'Context tokens'**
  String get contextTokens;

  /// No description provided for @contextIsolated.
  ///
  /// In en, this message translates to:
  /// **'This request used its current question without earlier chat turns.'**
  String get contextIsolated;

  /// No description provided for @contextInstructions.
  ///
  /// In en, this message translates to:
  /// **'Instructions given to the model'**
  String get contextInstructions;

  /// No description provided for @contextCharacters.
  ///
  /// In en, this message translates to:
  /// **'characters'**
  String get contextCharacters;

  /// No description provided for @contextMessages.
  ///
  /// In en, this message translates to:
  /// **'Conversation messages'**
  String get contextMessages;

  /// No description provided for @contextIncluded.
  ///
  /// In en, this message translates to:
  /// **'Included'**
  String get contextIncluded;

  /// No description provided for @contextOmittedIsolated.
  ///
  /// In en, this message translates to:
  /// **'Omitted for this independent request'**
  String get contextOmittedIsolated;

  /// No description provided for @contextOmittedLimit.
  ///
  /// In en, this message translates to:
  /// **'Omitted to fit the context limit; kept in history'**
  String get contextOmittedLimit;

  /// No description provided for @contextImages.
  ///
  /// In en, this message translates to:
  /// **'images'**
  String get contextImages;

  /// No description provided for @contextDocuments.
  ///
  /// In en, this message translates to:
  /// **'documents'**
  String get contextDocuments;

  /// No description provided for @contextSnippetOnly.
  ///
  /// In en, this message translates to:
  /// **'Search snippet only; page was not read'**
  String get contextSnippetOnly;

  /// No description provided for @contextStale.
  ///
  /// In en, this message translates to:
  /// **'Cached evidence may be outdated'**
  String get contextStale;

  /// No description provided for @goalModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get goalModelLabel;

  /// No description provided for @goalModelNone.
  ///
  /// In en, this message translates to:
  /// **'No local model ready'**
  String get goalModelNone;

  /// No description provided for @goalModelOnStart.
  ///
  /// In en, this message translates to:
  /// **'loads when the Goal starts'**
  String get goalModelOnStart;

  /// No description provided for @contextOmitted.
  ///
  /// In en, this message translates to:
  /// **'Omitted'**
  String get contextOmitted;

  /// No description provided for @contextEarlierHidden.
  ///
  /// In en, this message translates to:
  /// **'Earlier message previews not shown'**
  String get contextEarlierHidden;

  /// No description provided for @contextCapTrain.
  ///
  /// In en, this message translates to:
  /// **'Context set to {size} tokens, the most this model was trained for.'**
  String contextCapTrain(String size);

  /// No description provided for @contextCapMemory.
  ///
  /// In en, this message translates to:
  /// **'Context set to {size} tokens so the model fits in free memory.'**
  String contextCapMemory(String size);

  /// No description provided for @notEnoughMemory.
  ///
  /// In en, this message translates to:
  /// **'Not enough free memory for this model: it needs about {need} MB and {free} MB is free. Close other apps or choose a smaller model.'**
  String notEnoughMemory(int need, int free);

  /// No description provided for @contextTrainedFor.
  ///
  /// In en, this message translates to:
  /// **'The loaded model was trained for {size} tokens.'**
  String contextTrainedFor(String size);

  /// No description provided for @contextTrainedForCapped.
  ///
  /// In en, this message translates to:
  /// **'The loaded model was trained for {size} tokens. A larger context is shortened to that when the model loads, unless RoPE scaling is set under Memory, RoPE & speculation.'**
  String contextTrainedForCapped(String size);

  /// No description provided for @contextTrainedForStretched.
  ///
  /// In en, this message translates to:
  /// **'The loaded model was trained for {size} tokens; RoPE scaling stretches it past that, and quality can drop.'**
  String contextTrainedForStretched(String size);

  /// No description provided for @photosAndVoiceNotes.
  ///
  /// In en, this message translates to:
  /// **'Photos and voice notes'**
  String get photosAndVoiceNotes;

  /// No description provided for @photosAndVoiceNotesBody.
  ///
  /// In en, this message translates to:
  /// **'Find photos by what they show and recordings by what they say, with the same questions as your documents. Runs on the phone; ~{mb} MB once.'**
  String photosAndVoiceNotesBody(Object mb);

  /// No description provided for @photosAndVoiceNotesReady.
  ///
  /// In en, this message translates to:
  /// **'Photos and recordings are matched by what they show or say.'**
  String get photosAndVoiceNotesReady;

  /// No description provided for @noticeClaimsNotInSources.
  ///
  /// In en, this message translates to:
  /// **'Not backed by the sources: {claims}{more}. Check these statements before relying on them.'**
  String noticeClaimsNotInSources(String claims, String more);

  /// No description provided for @noticeClaimsNames.
  ///
  /// In en, this message translates to:
  /// **'names or dates no source mentions: {details}'**
  String noticeClaimsNames(String details);

  /// No description provided for @naturalVoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Natural on-device voice'**
  String get naturalVoiceTitle;

  /// No description provided for @naturalVoiceHint.
  ///
  /// In en, this message translates to:
  /// **'Whisper listens and Kokoro speaks, entirely on this phone. Falls back to the system voice when not downloaded.'**
  String get naturalVoiceHint;

  /// No description provided for @talkOverTitle.
  ///
  /// In en, this message translates to:
  /// **'Talk over the answer'**
  String get talkOverTitle;

  /// No description provided for @talkOverHint.
  ///
  /// In en, this message translates to:
  /// **'In a conversation, interrupt by speaking. The answer then sounds like a phone call. Off: clear sound, tap to interrupt.'**
  String get talkOverHint;

  /// No description provided for @spokenLengthTitle.
  ///
  /// In en, this message translates to:
  /// **'Spoken answer length'**
  String get spokenLengthTitle;

  /// No description provided for @spokenLengthHint.
  ///
  /// In en, this message translates to:
  /// **'How much of an answer Conversation says out loud. Lists are always read in full.'**
  String get spokenLengthHint;

  /// No description provided for @spokenLengthShort.
  ///
  /// In en, this message translates to:
  /// **'Short (3 sentences)'**
  String get spokenLengthShort;

  /// No description provided for @spokenLengthLonger.
  ///
  /// In en, this message translates to:
  /// **'Longer (6 sentences)'**
  String get spokenLengthLonger;

  /// No description provided for @spokenLengthFull.
  ///
  /// In en, this message translates to:
  /// **'Whole answer'**
  String get spokenLengthFull;

  /// No description provided for @voiceListeningPack.
  ///
  /// In en, this message translates to:
  /// **'Listening (Whisper)'**
  String get voiceListeningPack;

  /// No description provided for @voiceSpeakingPack.
  ///
  /// In en, this message translates to:
  /// **'Speaking (Kokoro)'**
  String get voiceSpeakingPack;

  /// No description provided for @listeningModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Listening model'**
  String get listeningModelTitle;

  /// No description provided for @listeningModelHint.
  ///
  /// In en, this message translates to:
  /// **'Parakeet v3 heard every test phrase on the phone and answers faster than Whisper; it also understands French and Spanish better. It is a separate download and uses more memory while you talk. Parakeet TDT 0.6B v3 by NVIDIA, CC BY 4.0.'**
  String get listeningModelHint;

  /// No description provided for @listeningWhisper.
  ///
  /// In en, this message translates to:
  /// **'Whisper base'**
  String get listeningWhisper;

  /// No description provided for @listeningParakeet.
  ///
  /// In en, this message translates to:
  /// **'Parakeet v3'**
  String get listeningParakeet;

  /// No description provided for @voiceUnpacking.
  ///
  /// In en, this message translates to:
  /// **'Unpacking…'**
  String get voiceUnpacking;

  /// No description provided for @voicePick.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voicePick;

  /// No description provided for @voiceTry.
  ///
  /// In en, this message translates to:
  /// **'Try'**
  String get voiceTry;

  /// No description provided for @voiceSample.
  ///
  /// In en, this message translates to:
  /// **'Hi! This is how I sound when I read your answers aloud.'**
  String get voiceSample;

  /// No description provided for @voiceDownloadBoth.
  ///
  /// In en, this message translates to:
  /// **'Download the on-device voice'**
  String get voiceDownloadBoth;

  /// No description provided for @conversationTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get conversationTitle;

  /// No description provided for @convListening.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get convListening;

  /// No description provided for @convThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get convThinking;

  /// No description provided for @convLookingUp.
  ///
  /// In en, this message translates to:
  /// **'Looking it up…'**
  String get convLookingUp;

  /// No description provided for @convSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Speaking · talk to interrupt'**
  String get convSpeaking;

  /// No description provided for @convSpeakingTap.
  ///
  /// In en, this message translates to:
  /// **'Speaking · tap to interrupt'**
  String get convSpeakingTap;

  /// No description provided for @convPaused.
  ///
  /// In en, this message translates to:
  /// **'Microphone off'**
  String get convPaused;

  /// No description provided for @convNeedsVoice.
  ///
  /// In en, this message translates to:
  /// **'For a natural, hands-free conversation, download the on-device voice (about 290 MB). Until then the system voice is used.'**
  String get convNeedsVoice;

  /// No description provided for @convModelMissing.
  ///
  /// In en, this message translates to:
  /// **'{model} is not downloaded, so another downloaded model answers. Download it in Models, or pick a model with the button at the top right.'**
  String convModelMissing(String model);

  /// No description provided for @convNoModel.
  ///
  /// In en, this message translates to:
  /// **'Load a model first.'**
  String get convNoModel;

  /// No description provided for @convModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation model'**
  String get convModelTitle;

  /// No description provided for @convModelHint.
  ///
  /// In en, this message translates to:
  /// **'Conversation answers with Qwen3.5 0.8B on the phone: it starts speaking in a few seconds. With a remote connection on, its model can answer instead.'**
  String get convModelHint;

  /// No description provided for @convModelRemote.
  ///
  /// In en, this message translates to:
  /// **'Searches by itself when needed and remembers the whole conversation'**
  String get convModelRemote;

  /// No description provided for @convRemoteFailed.
  ///
  /// In en, this message translates to:
  /// **'The remote connection did not answer ({error}). Answering on the phone.'**
  String convRemoteFailed(String error);

  /// No description provided for @convModelFastest.
  ///
  /// In en, this message translates to:
  /// **'fastest'**
  String get convModelFastest;

  /// No description provided for @convMicDenied.
  ///
  /// In en, this message translates to:
  /// **'The microphone is not allowed. Allow it in the phone\'s settings to talk.'**
  String get convMicDenied;

  /// No description provided for @convEnd.
  ///
  /// In en, this message translates to:
  /// **'End conversation'**
  String get convEnd;

  /// No description provided for @convStopAnswer.
  ///
  /// In en, this message translates to:
  /// **'Stop answer'**
  String get convStopAnswer;

  /// No description provided for @convMute.
  ///
  /// In en, this message translates to:
  /// **'Mute microphone'**
  String get convMute;

  /// No description provided for @convUnmute.
  ///
  /// In en, this message translates to:
  /// **'Turn microphone on'**
  String get convUnmute;

  /// No description provided for @convLoadingModel.
  ///
  /// In en, this message translates to:
  /// **'Loading {model}…'**
  String convLoadingModel(String model);

  /// No description provided for @convHint.
  ///
  /// In en, this message translates to:
  /// **'Just talk. I answer out loud; talk over me to interrupt.'**
  String get convHint;

  /// No description provided for @convInterrupt.
  ///
  /// In en, this message translates to:
  /// **'Interrupt'**
  String get convInterrupt;

  /// No description provided for @actionEvent.
  ///
  /// In en, this message translates to:
  /// **'Add to calendar'**
  String get actionEvent;

  /// No description provided for @actionReminder.
  ///
  /// In en, this message translates to:
  /// **'Add reminder'**
  String get actionReminder;

  /// No description provided for @actionAlarm.
  ///
  /// In en, this message translates to:
  /// **'Set alarm'**
  String get actionAlarm;

  /// No description provided for @actionTimer.
  ///
  /// In en, this message translates to:
  /// **'Start timer'**
  String get actionTimer;

  /// No description provided for @actionMessage.
  ///
  /// In en, this message translates to:
  /// **'Open draft'**
  String get actionMessage;

  /// No description provided for @actionFile.
  ///
  /// In en, this message translates to:
  /// **'Save or share'**
  String get actionFile;

  /// No description provided for @actionNoApp.
  ///
  /// In en, this message translates to:
  /// **'No app on this phone can do this.'**
  String get actionNoApp;

  /// No description provided for @actionConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Prepared for you: you confirm in the app that opens.'**
  String get actionConfirmHint;

  /// No description provided for @actionConfirmDone.
  ///
  /// In en, this message translates to:
  /// **'I completed this action'**
  String get actionConfirmDone;

  /// No description provided for @actionConfirmedAt.
  ///
  /// In en, this message translates to:
  /// **'Confirmed at {time}'**
  String actionConfirmedAt(String time);

  /// No description provided for @goalAwaitingActions.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your action confirmation'**
  String get goalAwaitingActions;

  /// The answer text when the model prepared a phone action but wrote nothing.
  ///
  /// In en, this message translates to:
  /// **'Ready. Check the card below and tap its button to finish.'**
  String get actionReadyAnswer;

  /// The answer text when the model copied its prompt twice instead of answering from the sources.
  ///
  /// In en, this message translates to:
  /// **'The model copied its instructions instead of answering, so no answer is shown. Open the sources below, or ask again in other words.'**
  String get echoedAnswer;

  /// No description provided for @goalActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready to do'**
  String get goalActionsTitle;

  /// No description provided for @goalSaveReport.
  ///
  /// In en, this message translates to:
  /// **'Save report as file'**
  String get goalSaveReport;

  /// No description provided for @goalWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch daily'**
  String get goalWatch;

  /// No description provided for @goalWatchSet.
  ///
  /// In en, this message translates to:
  /// **'Watching daily at {time}. A background search checks for changes and notifies you when a new result or figure changes. The full goal runs again only when you ask.'**
  String goalWatchSet(String time);

  /// No description provided for @goalPreparingActions.
  ///
  /// In en, this message translates to:
  /// **'Preparing actions…'**
  String get goalPreparingActions;

  /// No description provided for @goalPhaseDelivering.
  ///
  /// In en, this message translates to:
  /// **'Preparing what the goal asked for'**
  String get goalPhaseDelivering;

  /// No description provided for @goalNotPrepared.
  ///
  /// In en, this message translates to:
  /// **'Not prepared: {item} ({reason})'**
  String goalNotPrepared(String item, String reason);

  /// No description provided for @goalDeliverableFile.
  ///
  /// In en, this message translates to:
  /// **'the {format} file'**
  String goalDeliverableFile(String format);

  /// No description provided for @goalDeliverableEvent.
  ///
  /// In en, this message translates to:
  /// **'the calendar event'**
  String get goalDeliverableEvent;

  /// No description provided for @goalDeliverableReminder.
  ///
  /// In en, this message translates to:
  /// **'the reminder'**
  String get goalDeliverableReminder;

  /// No description provided for @goalDeliverableAlarm.
  ///
  /// In en, this message translates to:
  /// **'the alarm'**
  String get goalDeliverableAlarm;

  /// No description provided for @goalDeliverableTimer.
  ///
  /// In en, this message translates to:
  /// **'the timer'**
  String get goalDeliverableTimer;

  /// No description provided for @goalDeliverableMessage.
  ///
  /// In en, this message translates to:
  /// **'the message draft'**
  String get goalDeliverableMessage;

  /// No description provided for @goalNotPreparedStopped.
  ///
  /// In en, this message translates to:
  /// **'the goal was stopped'**
  String get goalNotPreparedStopped;

  /// No description provided for @goalNotPreparedBudget.
  ///
  /// In en, this message translates to:
  /// **'the goal\'s budget ran out'**
  String get goalNotPreparedBudget;

  /// No description provided for @goalNotPreparedUnreadable.
  ///
  /// In en, this message translates to:
  /// **'the model\'s reply could not be read'**
  String get goalNotPreparedUnreadable;

  /// No description provided for @goalNotPreparedTooLong.
  ///
  /// In en, this message translates to:
  /// **'the report is too long for one file'**
  String get goalNotPreparedTooLong;

  /// No description provided for @goalNotPreparedNone.
  ///
  /// In en, this message translates to:
  /// **'the model proposed none'**
  String get goalNotPreparedNone;

  /// No description provided for @goalNotPreparedInvalid.
  ///
  /// In en, this message translates to:
  /// **'the model\'s proposal was incomplete: {problem}'**
  String goalNotPreparedInvalid(String problem);

  /// No description provided for @goalWatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Watched goals'**
  String get goalWatchesTitle;

  /// No description provided for @goalWatchChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get goalWatchChecking;

  /// No description provided for @goalWatchWebOff.
  ///
  /// In en, this message translates to:
  /// **'Web search is off'**
  String get goalWatchWebOff;

  /// No description provided for @goalWatchNoResults.
  ///
  /// In en, this message translates to:
  /// **'The search found nothing'**
  String get goalWatchNoResults;

  /// No description provided for @goalWatchOffline.
  ///
  /// In en, this message translates to:
  /// **'Could not search (offline?)'**
  String get goalWatchOffline;

  /// No description provided for @goalWatchNotYet.
  ///
  /// In en, this message translates to:
  /// **'Not checked yet'**
  String get goalWatchNotYet;

  /// No description provided for @goalWatchBaseline.
  ///
  /// In en, this message translates to:
  /// **'First results kept {when}'**
  String goalWatchBaseline(String when);

  /// No description provided for @goalWatchNoChange.
  ///
  /// In en, this message translates to:
  /// **'No change · {when}'**
  String goalWatchNoChange(String when);

  /// No description provided for @goalWatchChanged.
  ///
  /// In en, this message translates to:
  /// **'{fresh} new, {figures} changed figures · {when}'**
  String goalWatchChanged(int fresh, int figures, String when);

  /// No description provided for @goalWatchDailyAt.
  ///
  /// In en, this message translates to:
  /// **'daily at {time}'**
  String goalWatchDailyAt(String time);

  /// No description provided for @goalWatchNewResult.
  ///
  /// In en, this message translates to:
  /// **'New: {title}'**
  String goalWatchNewResult(String title);

  /// No description provided for @goalWatchCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get goalWatchCheckNow;

  /// No description provided for @goalWatchRunAgain.
  ///
  /// In en, this message translates to:
  /// **'Run the goal again'**
  String get goalWatchRunAgain;

  /// No description provided for @goalWatchStop.
  ///
  /// In en, this message translates to:
  /// **'Stop watching'**
  String get goalWatchStop;

  /// No description provided for @actionOpenedAt.
  ///
  /// In en, this message translates to:
  /// **'Opened at {time}: confirm it there'**
  String actionOpenedAt(String time);

  /// No description provided for @remoteServerSettings.
  ///
  /// In en, this message translates to:
  /// **'Use the server\'s own settings'**
  String get remoteServerSettings;

  /// No description provided for @remoteServerSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Temperature, sampling, answer length and context come from the model on this connection (Gemini\'s defaults, the settings LM Studio loaded it with…), not from the phone\'s presets.'**
  String get remoteServerSettingsHint;

  /// No description provided for @sheetAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments and tools'**
  String get sheetAttachments;

  /// No description provided for @sheetNotice.
  ///
  /// In en, this message translates to:
  /// **'Notice'**
  String get sheetNotice;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
