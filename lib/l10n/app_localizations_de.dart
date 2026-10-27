// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get settingScopeHint =>
      'Leere einen Wert, um den Standard der vorherigen Ebene zu verwenden. Mit ↻ markierte Einstellungen greifen beim Laden des Modells.';

  @override
  String get settingExplicit => 'Angepasst';

  @override
  String get settingInherited => 'Übernommen';

  @override
  String get settingOnePerLine => 'Einer pro Zeile';

  @override
  String get nearbyHosts => 'Hosts in der Nähe finden';

  @override
  String get nearbyHostsHint =>
      'Finde OnDevice-LLM-Hosts im selben Netzwerk. Wähle einen aus und gib dann seinen Zugangsschlüssel ein oder nutze seinen Kopplungs-QR-Code.';

  @override
  String get nearbyHostsNone =>
      'Keine Hosts gefunden. Starte das Hosting auf dem anderen Gerät und prüfe, ob beide Geräte im selben Netzwerk sind. Manuelles Koppeln ist weiterhin möglich.';

  @override
  String get scanConfidence => 'Erkennungssicherheit';

  @override
  String get scanSettings => 'Texterkennung';

  @override
  String get scanPageLimit => 'Gescannte Seiten pro PDF';

  @override
  String get scanLongHint =>
      'Textebenen werden auch über dieses Limit hinaus gelesen. Längere Scans zeigen den Fortschritt an und lassen sich abbrechen.';

  @override
  String get scanLanguage => 'Erkennungssprache';

  @override
  String get scanLatinHint =>
      'Android erkennt Englisch, Französisch, Spanisch, Deutsch und andere Texte in lateinischer Schrift automatisch auf diesem Gerät.';

  @override
  String get scanQualityHint =>
      'Auch bei hoher Erkennungssicherheit kann der Text falsch sein. Prüfe wichtige Stellen am Original.';

  @override
  String get modelSettingsAll => 'Alle Modelleinstellungen';

  @override
  String get modelSettingsGlobal => 'Deine Modelleinstellungen';

  @override
  String get modelSettingsAllHint =>
      'Einstellungen von Modellprofilen, Vorlagen und Chats bearbeiten oder zurücksetzen';

  @override
  String get removeProjectHint =>
      'Dieses Projekt und seine Anweisungen entfernen? Seine Unterhaltungen und Wissensdateien bleiben erhalten.';

  @override
  String get downloadQueued => 'Wartet auf einen freien Download-Platz';

  @override
  String get sourceMessage => 'Ursprungsnachricht';

  @override
  String get sourceMessageMissing =>
      'Diese Ursprungsnachricht ist nicht mehr verfügbar.';

  @override
  String get openConversation => 'Unterhaltung öffnen';

  @override
  String get contextSummary => 'Kontextzusammenfassung prüfen';

  @override
  String get contextSummaryHint =>
      'Schreibe eine Zusammenfassung dieser früheren Nachrichten. Prüfe sie vor dem Speichern; spätere Antworten können sie anstelle dieses Teils der Unterhaltung verwenden.';

  @override
  String get contextSummaryTooShort =>
      'Für eine Zusammenfassung ist mehr Gesprächsverlauf nötig.';

  @override
  String get memoryUsed => 'Verwendete Erinnerungen';

  @override
  String get unverifiedFeatures => 'Zu prüfende Funktionen';

  @override
  String get restoreVersion => 'Diese Version verwenden';

  @override
  String get originalFile => 'Originaldatei teilen';

  @override
  String get previousVersion => 'Vorherige Version';

  @override
  String get workspaceTitle => 'Projekte und Unterhaltungen';

  @override
  String get project => 'Projekt';

  @override
  String get projectName => 'Projektname';

  @override
  String get projectInstructions => 'Anweisungen für dieses Projekt';

  @override
  String get noProject => 'Kein Projekt';

  @override
  String get archivedChats => 'Archiviert';

  @override
  String get trashChats => 'Papierkorb';

  @override
  String get archiveChats => 'Archivieren';

  @override
  String get restoreChats => 'Wiederherstellen';

  @override
  String get moveToTrash => 'In den Papierkorb';

  @override
  String get permanentDeleteHint =>
      'Diese Unterhaltungen und Anhänge endgültig von diesem Gerät entfernen. Das kann nicht rückgängig gemacht werden.';

  @override
  String get selectAllChats => 'Alle auswählen';

  @override
  String get temporaryChat => 'Temporärer Chat';

  @override
  String get temporaryChatHint =>
      'Dieser Chat und sein Entwurf bleiben nur im Arbeitsspeicher. Die Erinnerung ist aus. Beim Verlassen wird er verworfen; Remote- und Webanfragen nutzen weiterhin deine gewählte Verbindung.';

  @override
  String get deleteAnswer => 'Antwort löschen';

  @override
  String get deleteQuestionAnswer => 'Frage und Antwort löschen';

  @override
  String get messageDeleted => 'Nachricht gelöscht';

  @override
  String get undo => 'Rückgängig';

  @override
  String get undoUnavailable =>
      'Rückgängig ist nicht möglich, solange ein anderer Vorgang läuft.';

  @override
  String get appTitle => 'OnDevice';

  @override
  String get noModelLoaded => 'kein Modell geladen';

  @override
  String get newChat => 'Neuer Chat';

  @override
  String get drawerTemporary => 'Temporär';

  @override
  String get drawerWorkspace => 'Arbeitsbereich';

  @override
  String get drawerProjects => 'Projekte & Unterhaltungen';

  @override
  String get drawerProjectsHint => 'Projekte, Archiv und Papierkorb';

  @override
  String drawerProjectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Projekte',
      one: '1 Projekt',
      zero: 'Chats mit gemeinsamen Anweisungen gruppieren',
    );
    return '$_temp0';
  }

  @override
  String get previous7Days => 'Letzte 7 Tage';

  @override
  String get previous30Days => 'Letzte 30 Tage';

  @override
  String get olderChats => 'Älter';

  @override
  String get chatOptions => 'Chat-Optionen';

  @override
  String get shareOrExport => 'Teilen oder exportieren';

  @override
  String get thisChatSection => 'Dieser Chat';

  @override
  String get conversations => 'Unterhaltungen';

  @override
  String get more => 'Mehr';

  @override
  String get exportMarkdown => 'Als Markdown exportieren';

  @override
  String get exportJson => 'Als JSON exportieren';

  @override
  String get shareAsText => 'Als Text teilen';

  @override
  String get createDocument => 'Dokument erstellen';

  @override
  String get documentFormat => 'Format';

  @override
  String get answersOnly => 'Nur Antworten des Assistenten';

  @override
  String get includeBranches => 'Frühere Zweige einbeziehen';

  @override
  String get includeReasoning => 'Denkprozess des Modells einbeziehen';

  @override
  String get saveDocument => 'Dokument speichern';

  @override
  String get models => 'Modelle';

  @override
  String get settings => 'Einstellungen';

  @override
  String get metrics => 'Messwerte';

  @override
  String get loadingModel => 'Modell wird in den Speicher geladen …';

  @override
  String get messageHint => 'Nachricht an dein Modell …';

  @override
  String get listening => 'Hört zu …';

  @override
  String get chooseModel => 'Modell auswählen';

  @override
  String get think => 'Denken';

  @override
  String get thinkOff => 'Aus';

  @override
  String get thinkLow => 'Wenig';

  @override
  String get thinkMedium => 'Mittel';

  @override
  String get thinkHigh => 'Viel';

  @override
  String get thinkOffHint => 'Antwortet sofort. Am schnellsten.';

  @override
  String get thinkLowHint => 'Zuerst ein kurzer Denkschritt (etwa 500 Tokens).';

  @override
  String get thinkMediumHint =>
      'Denkt zuerst länger nach (etwa 2.000 Tokens), für schwierigere Fragen.';

  @override
  String get thinkHighHint =>
      'Denkt zuerst ausführlich nach (etwa 8.000 Tokens). Am langsamsten.';

  @override
  String thinkLevelToast(String level) {
    return 'Denken: $level';
  }

  @override
  String get thinkOffToast => 'Denken aus';

  @override
  String get attachTooltip => 'Foto oder Datei anhängen oder Werkzeuge wählen';

  @override
  String get dictate => 'Diktieren';

  @override
  String get stopDictation => 'Diktat beenden';

  @override
  String get send => 'Nachricht senden';

  @override
  String get stop => 'Generierung stoppen';

  @override
  String get modelPill => 'Modell';

  @override
  String get webLocal => 'Lokal';

  @override
  String get webAuto => 'auto';

  @override
  String get webAlways => 'immer';

  @override
  String get emptyTitle =>
      'Ein bisschen mehr Intelligenz.\nViel mehr Privatsphäre.';

  @override
  String get emptyHasModel =>
      'Dein Modell ist da und läuft komplett auf diesem Gerät. Frag es, was du willst.';

  @override
  String emptyRemote(String host) {
    return 'Die Antworten kommen von deinem Remote-Server ($host); deine Nachrichten werden dorthin gesendet. Frag, was du willst.';
  }

  @override
  String get emptyNoModel =>
      'Noch kein Modell. Öffne „Modelle“, um ein Startmodell herunterzuladen oder dein eigenes GGUF zu importieren, und komm dann zurück.';

  @override
  String get askPhoto => 'Frage zu einem Foto';

  @override
  String get askFile => 'Frage zu einer Datei';

  @override
  String get generating => 'wird erzeugt …';

  @override
  String get runDetails => 'So entstand diese Antwort';

  @override
  String get answerWarning => 'Was die Quellenprüfung bezweifelt hat';

  @override
  String get copyRunDetails => 'Laufdetails kopieren';

  @override
  String get runDetailsCopied => 'Laufdetails kopiert';

  @override
  String get runMeasured => 'GEMESSEN';

  @override
  String get runSettings => 'Aktive Einstellungen';

  @override
  String get runEngine => 'ENGINE';

  @override
  String get copyResponse => 'Antwort kopieren';

  @override
  String get copyQuestion => 'Frage kopieren';

  @override
  String get responseCopied => 'Antwort kopiert';

  @override
  String get readAloud => 'Vorlesen';

  @override
  String get stopReading => 'Vorlesen beenden';

  @override
  String get regenerate =>
      'Neu erzeugen (diese Antwort bleibt als frühere Version erhalten)';

  @override
  String get continueAnswer => 'Antwort fortsetzen';

  @override
  String get compareWith => 'Mit anderem Modell vergleichen';

  @override
  String get editQuestion => 'Frage bearbeiten';

  @override
  String get askAgain => 'Erneut fragen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get save => 'Speichern';

  @override
  String get earlierQuestion => 'Frühere Frage';

  @override
  String get earlierAnswer => 'Frühere Antwort';

  @override
  String get restoreBranch => 'Diesen Zweig wiederherstellen';

  @override
  String get stoppedPartial => 'Gestoppt · unvollständige Antwort';

  @override
  String get interruptedClosed =>
      'Unterbrochen · die App wurde vor Ende der Antwort geschlossen';

  @override
  String get interruptedPartial => 'Unterbrochen · unvollständige Antwort';

  @override
  String get interruptedError => 'Durch einen Fehler unterbrochen';

  @override
  String get searchConversations => 'Unterhaltungen durchsuchen';

  @override
  String get storedOnDevice => 'Nur auf diesem Gerät gespeichert';

  @override
  String get noConversations =>
      'Noch keine Unterhaltungen.\nDeine Chats erscheinen hier.';

  @override
  String nothingMatches(String query) {
    return 'Keine Treffer für „$query“.';
  }

  @override
  String get pinned => 'Angeheftet';

  @override
  String get today => 'Heute';

  @override
  String get yesterday => 'Gestern';

  @override
  String get earlier => 'Früher';

  @override
  String get language => 'Sprache';

  @override
  String get languageSystem => 'Wie das Telefon';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageSpanish => 'Español';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get resetToDefaults => 'Auf Standard zurücksetzen';

  @override
  String get sectionAssistant => 'Assistent';

  @override
  String get thinkingMode => 'Denkmodus';

  @override
  String get thinkingModeHint =>
      'Zeigt den vom Modell erzeugten Denkprozess an, sofern unterstützt. Er kann Fehler enthalten und ist kein Beweis für Richtigkeit.';

  @override
  String get webResearch => 'Webrecherche (ohne Schlüssel)';

  @override
  String get webOffHint => 'Nichts verlässt das Telefon.';

  @override
  String get webAutoHint =>
      'Die Frage geht an DuckDuckGo und Ergebnisseiten werden abgerufen, wenn die Nachricht es erfordert.';

  @override
  String get webAlwaysHint =>
      'Jede Nachricht wird zuerst recherchiert. Langsamer, aber immer aktuell.';

  @override
  String get knowledgeLibrary => 'Wissensbibliothek';

  @override
  String get knowledgeOff =>
      'Aus · deine Dokumente, in Antworten zitiert, wenn aktiv';

  @override
  String knowledgeOn(Object collection) {
    return 'An · $collection';
  }

  @override
  String get memory => 'Erinnerung';

  @override
  String get memoryOnHint =>
      'An · der Assistent lernt aus Chats dauerhafte Fakten über dich';

  @override
  String get memoryOffHint => 'Aus · zwischen Chats wird nichts gemerkt';

  @override
  String get readAloudSetting => 'Antworten vorlesen';

  @override
  String get readAloudHint =>
      'Jede fertige Antwort wird mit der Sprachausgabe des Telefons vorgelesen. Über das Lautsprecher-Symbol an einer Antwort kannst du sie in jedem Fall auf Wunsch vorlesen lassen.';

  @override
  String get dictationOnDevice => 'Diktat bleibt auf dem Telefon';

  @override
  String get dictationOnDeviceHint =>
      'Nur die Spracherkennung auf dem Gerät verwenden (benötigt ein Offline-Sprachpaket in den Spracheinstellungen des Telefons). Aus erlaubt die Erkennung über das Netzwerk.';

  @override
  String get customInstructions => 'Eigene Systemanweisungen';

  @override
  String get customInstructionsHint =>
      'Füge Vorlieben für deinen Assistenten hinzu';

  @override
  String get sectionModel => 'Modell';

  @override
  String get remoteServer => 'Remote-Server';

  @override
  String get sectionAdvanced => 'Erweitert';

  @override
  String get contextAndBatch => 'Kontext & Batch';

  @override
  String get hardware => 'Hardware';

  @override
  String get sampling => 'Sampling';

  @override
  String get reasoningAndSearch => 'Denken & Suche';

  @override
  String get sectionAbout => 'Über';

  @override
  String get openSourceMit => 'Open Source · MIT';

  @override
  String get builtOnLlama => 'Basiert auf llama.cpp';

  @override
  String get builtOnLlamaHint => 'Inferenz-Engine des ggml-Projekts';

  @override
  String get openSourceLicences => 'Open-Source-Lizenzen';

  @override
  String get openSourceLicencesHint =>
      'Pakete, Modelle und Stimmen mit ihren Lizenzen';

  @override
  String get resetQuestion => 'Auf Standard zurücksetzen?';

  @override
  String get resetHint =>
      'Alle Assistenten-, Modell- und erweiterten Einstellungen werden auf die Standardwerte für dieses Gerät zurückgesetzt. Deine Chats bleiben unberührt.';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get enableWebQuestion => 'Websuche aktivieren?';

  @override
  String get enableWebHint =>
      'Die Frage wird an DuckDuckGo gesendet und Ergebnisseiten werden direkt von den jeweiligen Websites abgerufen (diese sehen deine IP-Adresse). Es wird kein Konto und kein Schlüssel verwendet; Unterhaltungen, Modell und Einstellungen bleiben lokal.';

  @override
  String get enable => 'Aktivieren';

  @override
  String get systemInstructions => 'Systemanweisungen';

  @override
  String get systemInstructionsHint =>
      'z. B. Antworte kurz. Bevorzuge metrische Einheiten.';

  @override
  String get couldNotOpenLink => 'Dieser Link konnte nicht geöffnet werden.';

  @override
  String get privateByDefault => 'Standardmäßig privat';

  @override
  String get privateByDefaultHint =>
      'Keine Konten, keine Analysen, keine Cloud-Inferenz. Downloads und die optionale Suche sind die einzigen Netzwerkfunktionen.';

  @override
  String get noModelLoadedTitle => 'Kein Modell geladen';

  @override
  String get chooseFromLibrary => 'Wähle eines aus der Bibliothek';

  @override
  String get obPrivateHeadline => 'Privat durch Bauweise';

  @override
  String get obPrivateBody =>
      'Ein Sprachmodell, das auf dem eigenen Chip deines Telefons läuft. Am anderen Ende gibt es keinen Server.';

  @override
  String get obNoAccount => 'Kein Konto';

  @override
  String get obNoAccountHint => 'Keine Registrierung, keine Anmeldung.';

  @override
  String get obNoCloud => 'Keine Cloud';

  @override
  String get obNoCloudHint =>
      'Jede Antwort wird hier berechnet. Funktioniert auch im Flugmodus.';

  @override
  String get obStaysHere => 'Modelle und Chats bleiben auf diesem Telefon';

  @override
  String get obStaysHereHint =>
      'Lösche die App, und jedes Byte verschwindet mit ihr.';

  @override
  String get continueLabel => 'Weiter';

  @override
  String get obPickModel => 'Wähle ein Startmodell';

  @override
  String get phoneRamUnknown => 'Dieses Telefon · RAM unbekannt';

  @override
  String phoneRam(Object gb) {
    return 'Dieses Telefon · $gb GB RAM';
  }

  @override
  String get recommended => 'Empfohlen';

  @override
  String get orChooseAnother => 'Oder wähle ein anderes';

  @override
  String get acknowledgeLicense =>
      'Ich erkenne die Modelllizenz des Herausgebers an';

  @override
  String get download => 'Herunterladen';

  @override
  String get later => 'Später';

  @override
  String get obReady => 'Bereit.';

  @override
  String get startChatting => 'Loslegen';

  @override
  String get downloadInterrupted => 'Download unterbrochen';

  @override
  String get downloadInterruptedHint =>
      'Du kannst es jetzt erneut versuchen oder überspringen und später aus der Modellbibliothek herunterladen. Die App funktioniert ohne Modell, sie kann nur noch nicht antworten.';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get skipForNow => 'Vorerst überspringen';

  @override
  String get verifyingSha => 'SHA-256 wird geprüft …';

  @override
  String pausedOf(Object received, Object size) {
    return 'Pausiert · $received von $size';
  }

  @override
  String get starting => 'Startet …';

  @override
  String get downloading => 'Wird heruntergeladen';

  @override
  String get downloadingHint =>
      'Lass die App geöffnet. Du kannst pausieren und fortsetzen; nach Abschluss wird die Datei mit der SHA-256-Prüfsumme des Herausgebers verglichen.';

  @override
  String get resume => 'Fortsetzen';

  @override
  String get verifying => 'Wird geprüft …';

  @override
  String get pause => 'Pausieren';

  @override
  String get skip => 'Überspringen';

  @override
  String get presets => 'Vorlagen';

  @override
  String get newLabel => 'Neu';

  @override
  String get noExtraInstructions => 'Keine zusätzlichen Anweisungen';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get duplicate => 'Duplizieren';

  @override
  String get delete => 'Löschen';

  @override
  String get presetsHint =>
      'Eine Vorlage ergänzt deine Anweisungen um ihre eigenen und kann Temperatur, Denken und Webmodus überschreiben. Integrierte Vorlagen lassen sich duplizieren und bearbeiten.';

  @override
  String get newPreset => 'Neue Vorlage';

  @override
  String get editPreset => 'Vorlage bearbeiten';

  @override
  String get name => 'Name';

  @override
  String get instructions => 'Anweisungen';

  @override
  String get instructionsHint => 'Wie soll sich der Assistent verhalten?';

  @override
  String get temperature => 'Temperatur';

  @override
  String get useSetting => 'Einstellung verwenden';

  @override
  String get thinking => 'Denken';

  @override
  String get on => 'An';

  @override
  String get off => 'Aus';

  @override
  String get webResearchShort => 'Webrecherche';

  @override
  String get unpin => 'Lösen';

  @override
  String get pinToTop => 'Oben anheften';

  @override
  String get rename => 'Umbenennen';

  @override
  String get moveToFolder => 'In Ordner verschieben';

  @override
  String get tags => 'Tags';

  @override
  String get renameConversation => 'Unterhaltung umbenennen';

  @override
  String get tagsCommaSeparated => 'Tags (durch Kommas getrennt)';

  @override
  String get newFolder => 'Neuer Ordner …';

  @override
  String get removeFromFolder => 'Aus Ordner entfernen';

  @override
  String get folderName => 'Ordnername';

  @override
  String get deleteConversationQuestion => 'Unterhaltung löschen?';

  @override
  String get keep => 'Behalten';

  @override
  String couldNotDelete(Object error) {
    return 'Löschen fehlgeschlagen: $error';
  }

  @override
  String get clear => 'Leeren';

  @override
  String get all => 'Alle';

  @override
  String get knowledgeIntro =>
      'Importiere Dokumente einmal – PDF, Word, Text, Code, EPUB … – und jede Frage wird mit den passendsten Abschnitten aus der aktiven Sammlung beantwortet, zitiert wie Webquellen. Die Suche läuft komplett auf dem Telefon: Volltext-Ranking, plus Bedeutungssuche, sobald das Embedding-Modell heruntergeladen ist.';

  @override
  String get newCollection => 'Neue Sammlung';

  @override
  String get useInChats => 'In Chats verwenden';

  @override
  String get collectionOff => 'Aus – keine Sammlung wird herangezogen';

  @override
  String collectionActive(Object collection) {
    return 'Aktiv: $collection';
  }

  @override
  String get readingAndIndexing => 'Wird gelesen und indexiert …';

  @override
  String get noCollections =>
      'Noch keine Sammlungen. Erstelle eine über das Ordnersymbol und füge dann Dateien hinzu.';

  @override
  String get addFiles => 'Dateien hinzufügen';

  @override
  String get deleteCollection => 'Sammlung löschen';

  @override
  String get searchByMeaning => 'Nach Bedeutung suchen';

  @override
  String get ready => 'Bereit';

  @override
  String indexForMeaning(Object count) {
    return '$count Abschnitte nach Bedeutung indexieren';
  }

  @override
  String indexingProgress(Object done, Object total) {
    return 'Indexierung nach Bedeutung … $done/$total';
  }

  @override
  String downloadMb(Object mb) {
    return 'Herunterladen · $mb MB';
  }

  @override
  String get addMemory => 'Erinnerung hinzufügen';

  @override
  String get editMemory => 'Erinnerung bearbeiten';

  @override
  String get forgetEverything => 'Alles vergessen';

  @override
  String get forgetEverythingQuestion => 'Alles vergessen?';

  @override
  String forgetEverythingHint(Object count) {
    return 'Alle $count gemerkten Fakten werden gelöscht. Chats bleiben unberührt.';
  }

  @override
  String get forget => 'Vergessen';

  @override
  String get rememberAboutMe => 'Dinge über mich merken';

  @override
  String get rememberAboutMeHint =>
      'Merkt sich dauerhafte Fakten, die du teilst, etwa deinen Beruf und deine Vorlieben. Notizen werden auf diesem Gerät gespeichert. Teilen mit Remote-Verbindungen und Extraktion durch das Modell erfordern die Zustimmung für die jeweilige Verbindung. Unten kannst du Notizen bearbeiten oder vergessen.';

  @override
  String get memoryStorageHint =>
      'Notizen werden auf diesem Gerät gespeichert. Jede Remote-Verbindung braucht eine eigene Erlaubnis, um sie zu erhalten oder daraus zu lernen.';

  @override
  String get memoryRemoteLocalHint =>
      'Eindeutige Angaben wie dein Beruf oder Name können lokal gespeichert werden, wenn die Erinnerung an ist. Aktiviere das Teilen, damit diese Verbindung deine Notizen nutzen kann, und das Lernen, damit sie weitere dauerhafte Fakten extrahiert.';

  @override
  String get whatAssistantRemembers => 'Was sich der Assistent merkt';

  @override
  String get nothingYetFills =>
      'Noch nichts. Das füllt sich, während du chattest.';

  @override
  String get nothingStoredSwitch =>
      'Nichts gespeichert. Schalte den Schalter ein oder füge Fakten mit + von Hand hinzu.';

  @override
  String get switchModel => 'Modell wechseln';

  @override
  String get nothingOnPhone => 'Noch nichts auf diesem Telefon.';

  @override
  String get modelsOnPhone =>
      'Modelle auf diesem Telefon. Das aktive beantwortet deine Chats.';

  @override
  String get modelUnloaded =>
      'Modell entladen. Es wird bei deiner nächsten Nachricht wieder geladen.';

  @override
  String get unloadModel => 'Modell entladen · Speicher freigeben';

  @override
  String get openModelLibrary => 'Modellbibliothek öffnen';

  @override
  String get active => 'Aktiv';

  @override
  String get pickerEmptyHint =>
      'Lade ein Modell aus der Bibliothek herunter oder importiere ein GGUF, das du schon hast. Für Chats muss ein Modell geladen sein; alles bleibt auf diesem Telefon.';

  @override
  String get takePhoto => 'Foto aufnehmen';

  @override
  String get attachCamera => 'Kamera';

  @override
  String get attachFile => 'Datei';

  @override
  String get attachGoalShort => 'Ziel';

  @override
  String get photos => 'Fotos';

  @override
  String get photosHint => 'JPEG, PNG, WebP, HEIC …';

  @override
  String get documentOrFile => 'Dokument oder Datei';

  @override
  String get documentHint =>
      'PDF, Word, PowerPoint, Excel, OpenDocument, EPUB, RTF, Text, Code, CSV, JSON, HTML …';

  @override
  String couldNotOpenPicker(Object error) {
    return 'Die Auswahl konnte nicht geöffnet werden: $error';
  }

  @override
  String get readingAttachments => 'Anhänge werden gelesen …';

  @override
  String get turnOnWebQuestion => 'Websuche einschalten?';

  @override
  String get turnOnWebHint =>
      'Wenn du einen Link einfügst, um eine Suche bittest oder eine Frage zeitkritisch wirkt, wird die Frage an DuckDuckGo gesendet und Ergebnisseiten (standardmäßig drei, Einstellungen > Denken & Suche) werden direkt von den jeweiligen Websites abgerufen (diese sehen deine IP-Adresse). Bei lokaler Inferenz bleibt alles andere auf diesem Gerät. Ist ein Remote-Server aktiviert, werden die Frage und der mitgegebene Kontext auch an diesen Server gesendet.';

  @override
  String get stayLocal => 'Lokal bleiben';

  @override
  String get turnOn => 'Einschalten';

  @override
  String get compareWithTitle => 'Vergleichen mit …';

  @override
  String get compareHint =>
      'Dieselbe Frage mit denselben Belegen, beantwortet von einem anderen Modell. Wird neben dieser Antwort angezeigt und ist nicht Teil der Unterhaltung.';

  @override
  String shareFailed(Object error) {
    return 'Teilen fehlgeschlagen: $error';
  }

  @override
  String exportFailed(Object error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String get dismiss => 'Schließen';

  @override
  String licenseLabel(Object license) {
    return 'Lizenz · $license';
  }

  @override
  String get resumeRetry => 'Fortsetzen / erneut versuchen';

  @override
  String get useModel => 'Modell verwenden';

  @override
  String get remove => 'Entfernen';

  @override
  String get benchmark => 'Benchmark';

  @override
  String visionPercent(Object percent) {
    return 'Bildverständnis $percent %';
  }

  @override
  String get verifyingVision => 'Bildverständnis wird geprüft …';

  @override
  String get visionReady => 'Bildverständnis bereit';

  @override
  String addVisionMb(Object mb) {
    return 'Bildverständnis hinzufügen · $mb MB';
  }

  @override
  String get addFromHf => 'Von Hugging Face hinzufügen';

  @override
  String get importGguf => 'GGUF importieren';

  @override
  String get addFromHfHint =>
      'Füge den Link zu einer öffentlichen, einzelnen GGUF-Datei ein. Größe, Prüfsumme und Lizenz werden vor dem Download angezeigt.';

  @override
  String get importGgufHint =>
      'Wähle ein GGUF, das du selbst heruntergeladen hast. Es wird in deine private Modellbibliothek kopiert; sorge für genug Platz für eine zweite Kopie.';

  @override
  String get ggufLink => 'Link zur GGUF-Datei';

  @override
  String get templateFallback => 'Ersatz-Vorlage';

  @override
  String get automaticMetadata => 'Automatisch (Modell-Metadaten)';

  @override
  String get ggufWarning =>
      'Nur Textgenerierungsmodelle. Ein GGUF kann mehr RAM benötigen als seine Downloadgröße. Neue Architekturen und aufgeteilte Dateien werden eventuell nicht unterstützt.';

  @override
  String get checkModel => 'Modell prüfen';

  @override
  String get chooseFile => 'Datei auswählen';

  @override
  String get checkingMetadata => 'Modell-Metadaten werden geprüft …';

  @override
  String downloadQuestion(Object model) {
    return '$model herunterladen?';
  }

  @override
  String get modelCard => 'Modellkarte';

  @override
  String get removeModelQuestion => 'Dieses Modell entfernen?';

  @override
  String removeModelHint(Object model, Object size) {
    return '$model aus dieser App löschen und $size freigeben? Deine Chats bleiben erhalten.';
  }

  @override
  String get browseHf => 'Hugging Face durchsuchen';

  @override
  String get yourModelLibrary => 'Deine Modellbibliothek';

  @override
  String get libraryHint =>
      'Lade ein Startmodell herunter, füge einen Hugging-Face-Dateilink hinzu oder importiere ein GGUF, das du schon hast. Nach dem Download funktioniert die Inferenz offline.';

  @override
  String get searchHf => 'Hugging Face durchsuchen';

  @override
  String get pasteLink => 'Link einfügen';

  @override
  String get importGgufButton => 'GGUF importieren';

  @override
  String get checkingCopying => 'Modell wird geprüft und kopiert …';

  @override
  String get preparingLibrary => 'Deine Bibliothek wird vorbereitet …';

  @override
  String get onThisDevice => 'Auf diesem Gerät';

  @override
  String get nothingDownloaded =>
      'Noch nichts heruntergeladen. Wähle unten ein Modell, um loszulegen.';

  @override
  String get availableToDownload => 'Zum Download verfügbar';

  @override
  String get everythingOnPhone =>
      'Alles aus dem Katalog ist bereits auf diesem Telefon.';

  @override
  String get justNow => 'gerade eben';

  @override
  String minutesAgo(Object n) {
    return 'vor $n Min.';
  }

  @override
  String hoursAgo(Object n) {
    return 'vor $n Std.';
  }

  @override
  String get webModeOff => 'Aus · bleibt lokal';

  @override
  String get webModeAuto => 'Auto · Links, Suchanfragen und aktuelle Fragen';

  @override
  String get webModeAlways => 'Immer · jede Nachricht recherchieren';

  @override
  String rememberedOne(Object fact) {
    return 'Gemerkt: $fact';
  }

  @override
  String rememberedMore(Object fact, Object more) {
    return 'Gemerkt: $fact (+$more)';
  }

  @override
  String get reviewMemory => 'Gemerktes prüfen';

  @override
  String get memoryDialogTitle => 'Erinnerung';

  @override
  String get memoryDialogHint =>
      'Die Erinnerung speichert kurze Fakten, die du über dich nennst, damit spätere Chats sie schon kennen. Sie wird nur auf diesem Telefon gespeichert und du kannst sie jederzeit unter Einstellungen > Erinnerung ändern. Das wurde gerade notiert – bearbeite es, behalte es oder verwirf es.';

  @override
  String get memoryDialogFieldHint =>
      'Ein Fakt pro Zeile; leere Zeilen werden gelöscht';

  @override
  String get discard => 'Verwerfen';

  @override
  String get goalDescribeFirst => 'Beschreibe zuerst das Ziel.';

  @override
  String get goalLimitsInvalid =>
      'Gib positive Limits für Schritte, Zeit, Tokens und Werkzeugaufrufe ein.';

  @override
  String get goalsTitle => 'Ziele';

  @override
  String get goalIntro =>
      'Gib dem Modell ein Ziel. Es plant die zu recherchierenden Fragen, schlägt jede nach, prüft die Ergebnisse anhand deiner Kriterien, schließt Lücken und schreibt einen Bericht mit Quellen.';

  @override
  String get goalWebOff =>
      'Die Webrecherche ist aus, daher kann das Ziel nur nutzen, was das Modell bereits weiß. Schalte sie über das Globus-Symbol im Eingabefeld ein, um mit Quellen zu recherchieren.';

  @override
  String get goalLabel => 'Ziel';

  @override
  String get goalExample =>
      'Vergleiche die drei beliebtesten Elektroautos in Deutschland für eine vierköpfige Familie';

  @override
  String get goalKindTitle => 'Art der Recherche';

  @override
  String get goalCriteriaLabel => 'Was ein gutes Ergebnis enthält (optional)';

  @override
  String get goalBudgetTitle => 'Wie viel Aufwand';

  @override
  String get goalMaxSteps => 'Maximale Rechercheschritte';

  @override
  String get goalMaxMinutes => 'Maximale Minuten';

  @override
  String get goalMaxTokens => 'Ungefähres Token-Budget';

  @override
  String get goalMaxToolCalls => 'Maximale Werkzeugaufrufe';

  @override
  String get goalKeepOpen =>
      'Lass die App geöffnet: Android kann sie im Hintergrund beenden. Der Fortschritt wird nach jedem Schritt gespeichert.';

  @override
  String get goalStart => 'Ziel starten';

  @override
  String get goalBudgetQuick => 'Schnell';

  @override
  String get goalBudgetQuickHint => 'Etwa 4 Suchen · bis zu 10 Min.';

  @override
  String get goalBudgetStandard => 'Standard';

  @override
  String get goalBudgetStandardHint => 'Etwa 8 Suchen · bis zu 30 Min.';

  @override
  String get goalBudgetDeep => 'Gründlich';

  @override
  String get goalBudgetDeepHint => 'Etwa 14 Suchen · bis zu 60 Min.';

  @override
  String get goalBudgetUnlimited => 'Unbegrenzt';

  @override
  String get goalBudgetUnlimitedHint => 'Bis fertig, pausiert oder gestoppt';

  @override
  String get goalBudgetCustom => 'Eigene';

  @override
  String get goalBudgetCustomHint => 'Eigene Limits festlegen';

  @override
  String get goalPhasePlanning => 'Recherche wird geplant';

  @override
  String get goalPhaseResearching => 'Recherchiert';

  @override
  String get goalPhaseChecking =>
      'Ergebnisse werden mit deinen Kriterien abgeglichen';

  @override
  String get goalPhaseWriting => 'Bericht wird geschrieben';

  @override
  String get goalPhaseDone => 'Fertig';

  @override
  String get goalPaused => 'Pausiert';

  @override
  String get goalPausedBudget => 'Pausiert – das Budget ist aufgebraucht';

  @override
  String get goalCompleted => 'Abgeschlossen';

  @override
  String get goalStopped => 'Gestoppt';

  @override
  String get goalFailed => 'Etwas ist schiefgelaufen';

  @override
  String get goalReady => 'Bereit';

  @override
  String goalStepsOf(int done, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total Schritten',
      one: '1 Schritt',
    );
    return '$done von $_temp0';
  }

  @override
  String goalSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Quellen',
      one: '1 Quelle',
    );
    return '$_temp0';
  }

  @override
  String get goalTokensWord => 'Tokens';

  @override
  String get goalToolCallsWord => 'Werkzeugaufrufe';

  @override
  String get goalPauseAfterStep => 'Nach diesem Schritt pausieren';

  @override
  String get goalStop => 'Stoppen';

  @override
  String get goalContinue => 'Fortsetzen';

  @override
  String get goalOpenChat => 'Chat öffnen';

  @override
  String get goalNew => 'Neues Ziel';

  @override
  String get goalHowMade => 'So entstand dieser Bericht';

  @override
  String get goalPastTitle => 'Frühere Ziele';

  @override
  String get goalPastReopen => 'Verfeinern oder fortsetzen';

  @override
  String drawerGoalsPast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count frühere Ziele',
      one: '1 früheres Ziel',
    );
    return '$_temp0 · Neues starten';
  }

  @override
  String get goalReport => 'Bericht';

  @override
  String get goalInterimReport => 'Zwischenbericht';

  @override
  String get goalCopyReport => 'Bericht kopieren';

  @override
  String get goalReportCopied => 'Bericht kopiert';

  @override
  String get goalPlan => 'Plan';

  @override
  String get goalNotCovered => 'Nicht im Bericht abgedeckt';

  @override
  String get goalStillMissing => 'Fehlt noch';

  @override
  String get goalSourcesTitle => 'Quellen';

  @override
  String get goalKindGeneral => 'Allgemein';

  @override
  String get goalKindGeneralHint =>
      'Jedes Thema: ein ausgewogener Bericht mit Quellen';

  @override
  String get goalKindGeneralCriteria =>
      'Das Ziel vollständig beantwortet, jede Aussage mit Quelle';

  @override
  String get goalKindCode => 'Code';

  @override
  String get goalKindCodeHint =>
      'APIs, Fehler, Bibliotheken: funktionierender Code und Versionen';

  @override
  String get goalKindCodeCriteria =>
      'Ein funktionierender Ansatz mit Code, den Versionen, für die er gilt, und bekannten Stolperfallen';

  @override
  String get goalKindScience => 'Wissenschaftlich';

  @override
  String get goalKindScienceHint =>
      'Was die Belege sagen: Studien, Konsens, Grenzen';

  @override
  String get goalKindScienceCriteria =>
      'Die wichtigsten Ergebnisse mit Studientyp, Jahr und Umfang, wo sich Fachleute einig sind und wo nicht, sowie die Einschränkungen';

  @override
  String get goalKindMath => 'Mathe';

  @override
  String get goalKindMathHint =>
      'Definitionen, Herleitungen, geprüfte Ergebnisse';

  @override
  String get goalKindMathCriteria =>
      'Das Endergebnis, jeder Schritt der Herleitung und eine Probe der Antwort';

  @override
  String get goalKindNews => 'Aktuelles';

  @override
  String get goalKindNewsHint => 'Was passiert ist, wann, wer was sagt';

  @override
  String get goalKindNewsCriteria =>
      'Eine datierte Zeitleiste, die beteiligten Personen und Organisationen, ihre Positionen und wie es weitergeht';

  @override
  String get goalKindProduct => 'Produktvergleich';

  @override
  String get goalKindProductHint =>
      'Optionen nebeneinander, dann eine Empfehlung';

  @override
  String get goalKindProductCriteria =>
      'Preis, wichtige Daten, Stärken und Schwächen jeder Option und welche für wen passt';

  @override
  String get drawerGoalsHint => 'Recherche mit Plan und Bericht mit Quellen';

  @override
  String drawerGoalRunning(int step, int total) {
    return 'Läuft · Schritt $step von $total';
  }

  @override
  String drawerGoalReport(String goal) {
    return 'Bericht fertig · $goal';
  }

  @override
  String get emptyGoalTitle => 'Ein Ziel recherchieren';

  @override
  String get emptyGoalHint =>
      'Plant die Fragen, recherchiert jede einzelne und schreibt einen Bericht mit Quellen – für Code, Wissenschaft, Mathe, Nachrichten oder Vergleiche.';

  @override
  String get composerResearchGoal => 'Als Ziel recherchieren';

  @override
  String get composerManageShortcuts => 'Verwalten';

  @override
  String get shareNothing => 'In der Freigabe gibt es nichts zu öffnen.';

  @override
  String get scheduledWaiting => 'Dein geplanter Prompt steht im Eingabefeld.';

  @override
  String get shareMore => 'Nur die ersten 8 Dateien wurden geöffnet.';

  @override
  String shareSkipped(String names) {
    return 'Nicht geöffnet (leer oder über 64 MB): $names';
  }

  @override
  String get attachGoal => 'Als Ziel recherchieren';

  @override
  String get attachGoalHint =>
      'Ein Plan, mehrere Suchen, ein Bericht mit Quellen';

  @override
  String get batterySaver => 'Energiesparen';

  @override
  String get batterySaverOff =>
      'Sparsamere Antworten auf diesem Telefon, wenn der Akku schwach oder das Gerät heiß ist';

  @override
  String batterySaverOn(int level) {
    return 'Unter $level % und nicht am Laden oder wenn das Telefon heiß ist: kein Denken, kürzere Antworten, weniger gelesene Seiten';
  }

  @override
  String get batterySaverLevel => 'Energiesparen beginnt bei';

  @override
  String get scheduleTitle => 'Geplante Prompts';

  @override
  String get scheduleRowHint =>
      'Eine tägliche Benachrichtigung, die beim Antippen einen gespeicherten Prompt stellt';

  @override
  String get shortcutsTitle => 'Prompt-Kürzel';

  @override
  String get shortcutsRowHint =>
      'Tippe / in eine Nachricht: /summarize, /translate de, deine eigenen';

  @override
  String get hostTitle => 'Dieses Gerät als Server nutzen';

  @override
  String get hostRowHint =>
      'Ein geladenes Modell mit einem anderen Gerät teilen';

  @override
  String get shortcutNew => 'Neues Kürzel';

  @override
  String get shortcutsIntro =>
      'Tippe / in das Eingabefeld, um eines auszuwählen. „/summarize“ gefolgt von deinem Text sendet den gespeicherten Prompt mit dem Text darin; „/translate en …“ erwartet zuerst eine Sprache.';

  @override
  String get shortcutBuiltIn => 'integriert';

  @override
  String shortcutDelete(String name) {
    return '/$name löschen';
  }

  @override
  String get shortcutNameRule =>
      'Kleinbuchstaben, Ziffern und Bindestriche, bis zu 24.';

  @override
  String shortcutYourVersion(String name) {
    return 'Deine Version von /$name';
  }

  @override
  String shortcutEdit(String name) {
    return '/$name bearbeiten';
  }

  @override
  String get shortcutName => 'Name';

  @override
  String get shortcutDescription => 'Beschreibung';

  @override
  String get shortcutPrompt => 'Prompt';

  @override
  String shortcutPromptHelp(String token) {
    return '$token wird durch den Text nach dem Befehl ersetzt; ohne den Platzhalter wird der Text am Ende angehängt.';
  }

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonSave => 'Speichern';

  @override
  String scheduleFailed(String error) {
    return 'Die Erinnerung konnte nicht eingerichtet werden: $error';
  }

  @override
  String get scheduleNeedsNotifications =>
      'Erlaube Benachrichtigungen, wenn Android fragt, sonst kann die Erinnerung nicht erscheinen.';

  @override
  String get scheduleNew => 'Neu';

  @override
  String get scheduleIntro =>
      'Einmal täglich zur gewählten Uhrzeit bietet eine Benachrichtigung den Prompt an. Tippst du darauf, stellt die App ihn in einem neuen Chat (oder öffnet ihn als Ziel). Im Hintergrund läuft nichts und es wird nichts gesendet, bis du tippst.';

  @override
  String get scheduleEmpty =>
      'Noch keine. Probier ein morgendliches Nachrichten-Briefing oder ein wöchentliches Ziel.';

  @override
  String get scheduleChat => 'Chat';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get scheduleNewTitle => 'Neuer geplanter Prompt';

  @override
  String get commonEdit => 'Bearbeiten';

  @override
  String scheduleEveryDay(String time) {
    return 'Täglich um $time';
  }

  @override
  String get scheduleAskChat => 'In einem Chat fragen';

  @override
  String get scheduleOpenGoal => 'Als Ziel öffnen';

  @override
  String get scheduleExample =>
      'Was sind heute die wichtigsten Nachrichten in Deutschland?';

  @override
  String get scheduleNotificationTitle =>
      'Titel der Benachrichtigung (optional)';

  @override
  String get hostPortRange => 'Verwende eine Zahl von 1 bis 65535.';

  @override
  String get hostPortReserved =>
      'Ports unter 1024 sind unter Android reserviert.';

  @override
  String hostCopied(String what) {
    return '$what kopiert';
  }

  @override
  String get hostPickModel => 'Bereitzustellendes Modell';

  @override
  String get hostPickHint =>
      'Das Laden dauert ein paar Sekunden. Ein laufender Server startet mit dem neuen Modell neu; verbundene Geräte behalten Adresse und Token.';

  @override
  String get hostChangeModel => 'Ändern';

  @override
  String get hostManageModels => 'Modelle herunterladen oder importieren';

  @override
  String get hostModel => 'Modell';

  @override
  String get hostNoModel => 'Kein Modell geladen';

  @override
  String get hostLoadFirst => 'Wähle ein Modell zum Bereitstellen.';

  @override
  String get hostModelHint =>
      'Andere Geräte chatten mit diesem Modell, solange der Server läuft.';

  @override
  String get hostConnection => 'Verbindung';

  @override
  String get hostPort => 'Port';

  @override
  String get hostPortHint => 'Das andere Gerät verbindet sich mit diesem Port.';

  @override
  String get hostStarting => 'Startet …';

  @override
  String get hostStart => 'Server starten';

  @override
  String get hostToken => 'Zugangstoken';

  @override
  String get hostRotate => 'Zugangstoken erneuern';

  @override
  String get hostRotateHint =>
      'Geräte mit dem aktuellen Token müssen sich mit dem neuen erneut verbinden.';

  @override
  String get hostRotated =>
      'Beim nächsten Start wird ein neues Token verwendet.';

  @override
  String get hostWaiting => 'Bereit · wartet auf Anfragen';

  @override
  String hostAnswering(String client) {
    return 'Antwortet $client';
  }

  @override
  String hostUp(String duration) {
    return 'läuft seit $duration';
  }

  @override
  String get hostLive => 'Live';

  @override
  String get hostAnswered => 'beantwortet';

  @override
  String get hostRefused => 'abgelehnt';

  @override
  String get hostFailed => 'fehlgeschlagen';

  @override
  String get hostTokensIn => 'Tokens rein';

  @override
  String get hostTokensOut => 'Tokens raus';

  @override
  String get hostAvgSpeed => 'Ø Tempo';

  @override
  String get hostDevices => 'Geräte';

  @override
  String get hostBattery => 'Akku';

  @override
  String get hostHeat => 'Wärme';

  @override
  String get hostLowBattery => 'Bei schwachem Akku stoppen';

  @override
  String get hostLowBatteryHint =>
      'Der Server stoppt auch, wenn das Telefon starke Hitze meldet. Der Bildschirm bleibt an, solange er läuft.';

  @override
  String get commonOff => 'Aus';

  @override
  String get hostConnect => 'Anderes Gerät verbinden';

  @override
  String get hostServerUrl => 'Server-URL';

  @override
  String get hostModelId => 'Modell-ID';

  @override
  String get hostHideToken => 'Token verbergen';

  @override
  String get hostShowToken => 'Token anzeigen';

  @override
  String get hostCopyConnection => 'Verbindung kopieren';

  @override
  String get hostPairHint =>
      'Auf dem anderen Telefon: Scanne diesen Code mit der Kamera und kopiere den Text oder füge die kopierte Verbindung ein, dann öffne in OnDevice LLM Einstellungen > Remote-Server > Hinzufügen > Verbindung einfügen. Jede OpenAI-kompatible App funktioniert auch, mit URL, Modell und Token.';

  @override
  String get hostRecent => 'Letzte Anfragen';

  @override
  String get hostNoneYet => 'Noch keine.';

  @override
  String hostCopy(String what) {
    return '$what kopieren';
  }

  @override
  String hostInOut(int prompt, int completion) {
    return '$prompt rein · $completion raus';
  }

  @override
  String get remotePasteNone =>
      'In der Zwischenablage ist keine Verbindung. Tippe auf dem anderen Telefon zuerst auf „Verbindung kopieren“ (oder scanne seinen QR-Code).';

  @override
  String remotePasted(String name) {
    return '$name hinzugefügt. Schalte „Remote-Server verwenden“ ein, um damit zu chatten.';
  }

  @override
  String get remotePaste => 'Verbindung einfügen';

  @override
  String get remoteAdd => 'Verbindung hinzufügen';

  @override
  String get configCopied => 'Konfiguration als Text kopiert';

  @override
  String get configTooLarge =>
      'Diese Datei ist zu groß für eine Konfiguration.';

  @override
  String get configNotAFile =>
      'Diese Datei ist keine Modellkonfiguration von OnDevice LLM.';

  @override
  String get configNotInClipboard =>
      'In der Zwischenablage ist keine Modellkonfiguration. Kopiere zuerst eine.';

  @override
  String configMadeFor(String model) {
    return 'Erstellt für $model';
  }

  @override
  String get configNotDownloaded =>
      'Dieses Modell ist im Katalog, aber nicht heruntergeladen: Hol es dir unter „Modelle“ oder wende die Konfiguration auf ein vorhandenes an.';

  @override
  String get configNotOnPhone =>
      'Dieses Modell ist nicht auf diesem Telefon. Wende die Einstellungen auf ein vorhandenes an:';

  @override
  String configSameModel(String model) {
    return '$model (gleiches Modell)';
  }

  @override
  String get configEmpty =>
      'Die Karte legt nichts fest: Das Modell liefe mit deinen eigenen Einstellungen.';

  @override
  String configLeftOut(String keys) {
    return 'Weggelassen (Webzugriff, Telefon-Hardware, Kontextgröße oder unbekannt): $keys';
  }

  @override
  String get configApply => 'Anwenden';

  @override
  String get hostShowQr => 'Kopplungscode anzeigen';

  @override
  String get voiceConversation => 'Sprachunterhaltung';

  @override
  String get chatPinModel => 'Modell an diesen Chat anheften';

  @override
  String get chatPinHint =>
      'Dieser Chat antwortet immer mit dem angehefteten Modell, egal was in der Modellauswahl steht.';

  @override
  String get chatPinNone => 'Nicht angeheftet: ausgewähltes Modell verwenden';

  @override
  String chatPinned(String model) {
    return '📌 $model';
  }

  @override
  String get readerSummarize => 'Artikel zusammenfassen';

  @override
  String get readerKeyPoints => 'Kernpunkte';

  @override
  String get readerExplain => 'Einfach erklären';

  @override
  String readerSummarizePrompt(String url) {
    return 'Lies diesen Artikel und fasse ihn in einigen kurzen Absätzen zusammen, mit exakten Namen, Zahlen und Daten, und zitiere ihn: $url';
  }

  @override
  String readerKeyPointsPrompt(String url) {
    return 'Lies diesen Artikel und liste seine Kernpunkte als kurze Stichpunkte auf, mit Quellenangabe: $url';
  }

  @override
  String readerExplainPrompt(String url) {
    return 'Lies diesen Artikel und erkläre in einfacher Sprache, was er sagt, für jemanden, der neu im Thema ist, mit Quellenangabe: $url';
  }

  @override
  String get readerNeedsWeb =>
      'Zum Lesen eines Links ist Webrecherche nötig: Schalte sie über das Globus-Symbol ein.';

  @override
  String get saveToKnowledge => 'Im Wissen speichern';

  @override
  String get knowledgeSaveHint =>
      'Wähle eine Sammlung und die zu speichernden Nachrichten. Nur sichtbarer Nachrichtentext und seine Quellenlinks werden übernommen; privater Denkprozess bleibt außen vor.';

  @override
  String get knowledgeCollectionName => 'Name der Sammlung';

  @override
  String get knowledgeDocumentTitle => 'Dokumenttitel';

  @override
  String get knowledgeSelectMessages => 'Zu speichernde Nachrichten';

  @override
  String get knowledgeChatTitle => 'Gespeicherte Unterhaltung';

  @override
  String get knowledgeNameRequired =>
      'Gib einen Sammlungsnamen und einen Dokumenttitel ein.';

  @override
  String knowledgeSaved(String collection) {
    return 'In $collection gespeichert.';
  }

  @override
  String knowledgeSaveFailed(String error) {
    return 'Speichern im Wissen fehlgeschlagen: $error';
  }

  @override
  String get you => 'Du';

  @override
  String get assistant => 'Assistent';

  @override
  String get backupPasswordTooShort =>
      'Verwende mindestens 12 Zeichen für das Backup-Passwort.';

  @override
  String get backupPasswordsMismatch => 'Die Passwörter stimmen nicht überein.';

  @override
  String get backupSaveDialog => 'Verschlüsseltes Backup speichern';

  @override
  String get backupSaveCancelled => 'Speichern abgebrochen.';

  @override
  String get backupSavedNotice =>
      'Verschlüsseltes Backup gespeichert. Bewahre das Passwort sicher auf; es kann nicht wiederhergestellt werden.';

  @override
  String backupFailedNotice(String error) {
    return 'Backup fehlgeschlagen: $error';
  }

  @override
  String get backupEnterPassword => 'Gib das Backup-Passwort ein.';

  @override
  String get backupReplaceQuestion => 'Bibliothek dieses Geräts ersetzen?';

  @override
  String get backupReplaceHint =>
      'Die Wiederherstellung ersetzt beim nächsten App-Start Chats, Wissen, Anhänge und App-Einstellungen. Lokale Modelldateien und gespeicherte API-Schlüssel sind nicht im Backup enthalten.';

  @override
  String get backupRestoreAction => 'Wiederherstellen';

  @override
  String get backupTooLarge => 'Das Backup überschreitet das Sicherheitslimit.';

  @override
  String get backupVerifiedNotice =>
      'Backup geprüft. Schließe die App vollständig und öffne sie erneut, um die Wiederherstellung anzuwenden.';

  @override
  String backupRestoreFailed(String error) {
    return 'Wiederherstellung fehlgeschlagen: $error';
  }

  @override
  String get backupTitle => 'Verschlüsseltes Backup';

  @override
  String get backupIntro =>
      'Sichere Chats, Wissen, Anhänge, Ziele und Einstellungen in einer passwortgeschützten Datei. Modellgewichte und gespeicherte API-Schlüssel bleiben auf diesem Gerät. Das Backup-Limit liegt bei 96 MB.';

  @override
  String get backupPasswordLabel => 'Backup-Passwort';

  @override
  String get backupConfirmPassword =>
      'Passwort für ein neues Backup bestätigen';

  @override
  String get backupCreateAction => 'Verschlüsseltes Backup erstellen';

  @override
  String get backupRestoreBackup => 'Backup wiederherstellen';

  @override
  String get uiRemoteProfilePageDeleteConnection => 'Verbindung löschen?';

  @override
  String get uiRemoteProfilePageCancel => 'Abbrechen';

  @override
  String get uiRemoteProfilePageDelete => 'Löschen';

  @override
  String get uiRemoteProfilePageConnection => 'Verbindung';

  @override
  String get uiRemoteProfilePageThisConnectionWasRemoved =>
      'Diese Verbindung wurde entfernt.';

  @override
  String get uiRemoteProfilePageDeleteConnection2 => 'Verbindung löschen';

  @override
  String get uiRemoteProfilePageProvider => 'Anbieter';

  @override
  String get uiRemoteProfilePageName => 'Name';

  @override
  String get uiRemoteProfilePageServerURL => 'Server-URL';

  @override
  String get uiRemoteProfilePageGetAKeyInTheBrowser =>
      'Schlüssel im Browser holen';

  @override
  String get uiRemoteProfilePageModel => 'Modell';

  @override
  String get uiRemoteProfilePageModelsOnTheServer => 'Modelle auf dem Server';

  @override
  String get uiRemoteProfilePageRequestsPerMinute => 'Anfragen pro Minute';

  @override
  String get uiRemoteProfilePageNone => 'keine';

  @override
  String get uiRemoteProfilePageRequestsPerDay => 'Anfragen pro Tag';

  @override
  String get uiRemoteProfilePageExtraHeaders => 'Zusätzliche Header';

  @override
  String get uiAdvancedPagesContextBatch => 'Kontext & Batch';

  @override
  String get uiAdvancedPagesContextSize => 'Kontextgröße';

  @override
  String get uiAdvancedPagesTokensTheModelCanSeeAt =>
      'Tokens, die das Modell gleichzeitig sehen kann: die Unterhaltung, Belege aus dem Web und die Antwort. Der Speicherbedarf wächst mit; reicht der Speicher des Telefons nicht, lädt das Modell mit kürzerem Kontext und ein Hinweis weist darauf hin.';

  @override
  String get uiAdvancedPagesContextSizeTokens => 'Kontextgröße (Tokens)';

  @override
  String get uiAdvancedPagesBatchSize => 'Batchgröße';

  @override
  String get uiAdvancedPagesPromptTokensSubmittedPerStepAuto =>
      'Prompt-Tokens pro Schritt. Auto ist 512, das gemessene Optimum auf diesem Telefon; größere Werte helfen vor allem beim GPU-Prefill langer Prompts.';

  @override
  String get uiAdvancedPagesMicroBatch => 'Micro-Batch';

  @override
  String get uiAdvancedPagesTokensPerComputeStepWithinA =>
      'Tokens pro Rechenschritt innerhalb eines Batches. Auto entspricht der Batchgröße. Nie größer als die Batchgröße.';

  @override
  String get uiAdvancedPagesKeepConversationInContext =>
      'Unterhaltung im Kontext behalten';

  @override
  String get uiAdvancedPagesOnlyNewTextIsEvaluatedOn =>
      'Pro Runde wird nur neuer Text ausgewertet; frühere Runden bleiben im Speicher. Aus liest bei jeder Nachricht die ganze Unterhaltung neu.';

  @override
  String get uiAdvancedPagesHardware => 'Hardware';

  @override
  String get uiAdvancedPagesBackend => 'Backend';

  @override
  String get uiAdvancedPagesAutomaticUsesCPUOpenCL2Faster =>
      'Automatisch nutzt die CPU. OpenCL: ~2× schnelleres Einlesen des Prompts bei Recherchen, ~15 % langsamere Antworten; das Modell wird beim Wechsel neu geladen.';

  @override
  String get uiAdvancedPagesGPULayers => 'GPU-Schichten';

  @override
  String get uiAdvancedPagesLayersOffloadedToTheGPUIgnored =>
      'Auf die GPU ausgelagerte Schichten. Wird ignoriert, wenn das Backend nur CPU ist.';

  @override
  String get uiAdvancedPagesCPUThreadsDecode => 'CPU-Threads (Decode)';

  @override
  String get uiAdvancedPagesWorkerThreadsWhileTheAnswerStreams =>
      'Worker-Threads, während die Antwort gestreamt wird. Auto nutzt 6 auf Telefonen mit 8 Kernen (gemessen am schnellsten), sonst die Hälfte der Kerne.';

  @override
  String get uiAdvancedPagesCPUThreadsPrefill => 'CPU-Threads (Prefill)';

  @override
  String get uiAdvancedPagesThreadsWhileThePromptIsRead =>
      'Threads, während der Prompt gelesen wird. Auto nutzt alle Kerne: Prefill wurde bis 8 Threads schneller, wo Decode langsamer wurde.';

  @override
  String get uiAdvancedPagesFlashAttention => 'Flash Attention';

  @override
  String get uiAdvancedPagesFasterAttentionKernelWithLowerMemory =>
      'Schnellerer Attention-Kernel mit geringerem Speicherbedarf.';

  @override
  String get uiAdvancedPagesKVCache => 'KV-Cache';

  @override
  String get uiAdvancedPagesPrecisionOfCachedAttentionState =>
      'Genauigkeit des zwischengespeicherten Attention-Zustands';

  @override
  String get uiAdvancedPagesSampling => 'Sampling';

  @override
  String get uiAdvancedPagesTemperature => 'Temperatur';

  @override
  String get uiAdvancedPagesRandomnessLowerIsMoreFocusedHigher =>
      'Zufälligkeit. Niedriger ist fokussierter, höher ist abwechslungsreicher.';

  @override
  String get uiAdvancedPagesTopP => 'Top-P';

  @override
  String get uiAdvancedPagesSampleFromTheSmallestSetOf =>
      'Wählt aus der kleinsten Menge an Tokens, deren Wahrscheinlichkeit zusammen P ergibt.';

  @override
  String get uiAdvancedPagesMinP => 'Min-P';

  @override
  String get uiAdvancedPagesDropTokensLessLikelyThanThis =>
      'Verwirft Tokens, die unwahrscheinlicher sind als dieser Anteil des wahrscheinlichsten Tokens.';

  @override
  String get uiAdvancedPagesTopK => 'Top-K';

  @override
  String get uiAdvancedPagesOnlyTheKMostLikelyTokens =>
      'Nur die K wahrscheinlichsten Tokens werden berücksichtigt. 0 deaktiviert.';

  @override
  String get uiAdvancedPagesRepetitionPenalty => 'Wiederholungsstrafe';

  @override
  String get uiAdvancedPagesDiscouragesRepeatingRecentTokens100 =>
      'Erschwert das Wiederholen kürzlich verwendeter Tokens. 1,00 ist aus.';

  @override
  String get uiAdvancedPagesMaxTokens => 'Max. Tokens';

  @override
  String get uiAdvancedPagesUpperBoundOnOneResponseReasoning =>
      'Obergrenze für eine Antwort, Denkprozess eingeschlossen. Sie wird im Kontext reserviert und muss daher neben den Prompt passen.';

  @override
  String get uiAdvancedPagesMaxTokensPerResponse => 'Max. Tokens pro Antwort';

  @override
  String get uiAdvancedPagesReasoningSearch => 'Denken & Suche';

  @override
  String get uiAdvancedPagesThinkingMode => 'Denkmodus';

  @override
  String get uiAdvancedPagesShowModelGeneratedReasoningWhenSupported =>
      'Zeigt den vom Modell erzeugten Denkprozess an, sofern unterstützt. Er kann Fehler enthalten und ist kein Beweis für Richtigkeit.';

  @override
  String get uiAdvancedPagesThinkingBudget => 'Denkbudget';

  @override
  String get uiAdvancedPagesReasoningTokensAllowedBeforeTheBlock =>
      'Erlaubte Denk-Tokens, bevor der Block geschlossen wird und die Antwort beginnt. Begrenzt die Wartezeit bei schweren Fragen; unbegrenzt lässt das Modell entscheiden.';

  @override
  String get uiAdvancedPagesThinkingBudgetTokens0Unlimited =>
      'Denkbudget (Tokens, 0 = unbegrenzt)';

  @override
  String get uiAdvancedPagesSearchAndNewsRegion =>
      'Region für Suche und Nachrichten';

  @override
  String get uiAdvancedPagesSearchResults => 'Suchergebnisse';

  @override
  String get uiAdvancedPagesCandidatesTakenFromDuckDuckGoPerQuery =>
      'Von DuckDuckGo übernommene Kandidaten pro Suchanfrage.';

  @override
  String get uiAdvancedPagesPagesToRead => 'Zu lesende Seiten';

  @override
  String get uiAdvancedPagesResultPagesFetchedAndRankedFor =>
      'Ergebnisseiten, die abgerufen und nach Belegen gewichtet werden. Nicht lesbare Seiten werden zugunsten des nächsten Kandidaten übersprungen. Mehr ist langsamer und braucht mehr Kontext.';

  @override
  String get uiAdvancedPagesResearchTimeBudget => 'Zeitbudget für Recherche';

  @override
  String get uiAdvancedPagesWallClockLimitForReadingAll =>
      'Zeitlimit für das Lesen aller Seiten einer Frage. Langsame Seiten werden beim Limit abgebrochen und die Antwort arbeitet mit dem bis dahin Gelesenen.';

  @override
  String get uiAdvancedPagesModelDrivenResearchExperimental =>
      'Modellgesteuerte Recherche (experimentell)';

  @override
  String get uiAdvancedPagesModelWritesTheSearchQueries =>
      'Modell formuliert die Suchanfragen';

  @override
  String get uiAdvancedPagesTheLocalModelTurnsYourQuestion =>
      'Das lokale Modell macht vor der Suche aus deiner Frage ein oder zwei Suchmaschinenanfragen. Kostet ein paar Sekunden; aus sendet die Frage so, wie du sie getippt hast.';

  @override
  String get uiAdvancedPagesPassagesGivenToTheModel =>
      'An das Modell übergebene Abschnitte';

  @override
  String get uiAdvancedPagesBestMatchingPassagesAbout250Tokens =>
      'Die passendsten Abschnitte (je etwa 250 Tokens) aus allen gelesenen Seiten. Mehr Belege, längerer Prefill.';

  @override
  String get uiAdvancedPagesFlagUnsupportedFigures =>
      'Unbelegte Zahlen markieren';

  @override
  String get uiAdvancedPagesAfterAGroundedAnswerNumbersVersions =>
      'Nach einer belegten Antwort werden Zahlen, Versionen und Daten, die in keinem gelieferten Abschnitt vorkommen, als ungeprüft gekennzeichnet.';

  @override
  String get supportCheckTitle => 'Sätze nach Bedeutung prüfen';

  @override
  String get supportCheckHint =>
      'Ein kleines Modell (Qwen3 Reranker 0.6B) liest den nächstliegenden Quellabschnitt, bevor ein Satz markiert wird, damit ein korrekter Satz in anderen Worten nicht als unbelegt gilt. Separater Download; läuft nach einer Antwort aus Quellen ein paar Sekunden lang.';

  @override
  String get uiHfSearchPageSearchHuggingFace => 'Hugging Face durchsuchen';

  @override
  String get uiHfSearchPageModelNameEGQwen34B =>
      'Modellname, z. B. Qwen3 4B, Phi-4, Llama 3.2';

  @override
  String get uiHfSearchPageNoGGUFRepositoriesMatch =>
      'Keine passenden GGUF-Repositorys.';

  @override
  String get uiHfSearchPageNoSingleFileGGUFWeightsIn =>
      'Keine GGUF-Gewichte als Einzeldatei in diesem Repository.';

  @override
  String get uiHfSearchPageNotAddableHere => 'Hier nicht hinzufügbar';

  @override
  String get uiBenchmarkDialogBenchmarkCopied => 'Benchmark kopiert';

  @override
  String get uiBenchmarkDialogCopy => 'Kopieren';

  @override
  String get uiBenchmarkDialogShare => 'Teilen';

  @override
  String get uiBenchmarkDialogDone => 'Fertig';

  @override
  String get uiModelReadinessPageModelReadiness => 'Modell-Eignung';

  @override
  String get uiModelReadinessPageDeviceCapacity => 'Gerätekapazität';

  @override
  String get uiModelReadinessPagePhysicalRAM => 'Physischer RAM';

  @override
  String get uiModelReadinessPageModelStorageVolume =>
      'Speicherort der Modelle';

  @override
  String get uiModelReadinessPageInstalledModelWeights =>
      'Installierte Modellgewichte';

  @override
  String get uiModelReadinessPageCurrentContextAndBackend =>
      'Aktueller Kontext und Backend';

  @override
  String get uiModelReadinessPageModels => 'Modelle';

  @override
  String get uiModelReadinessPageRAMFitIsARoughEstimate =>
      'Die RAM-Eignung ist eine grobe Schätzung. Tatsächlicher Kontextspeicher und Tempo hängen von Modell, Backend und Gerätetemperatur ab.';

  @override
  String get uiToolsQuickPanelLetTheModelCallTools =>
      'Modell darf Werkzeuge aufrufen';

  @override
  String get uiToolsQuickPanelTHISMODELMAYCALL => 'Dieses Modell darf aufrufen';

  @override
  String get uiToolsQuickPanelCalculator => 'Rechner';

  @override
  String get uiToolsQuickPanelExactArithmetic => 'Exakte Rechnungen.';

  @override
  String get uiToolsQuickPanelSearchWebReadUrlFindIn =>
      'search_web · read_url · find_in_page';

  @override
  String get uiToolsQuickPanelSearchDocuments => 'search_documents';

  @override
  String get uiToolsQuickPanelToolUse => 'Werkzeugnutzung';

  @override
  String get uiToolsQuickPanelAuto => 'Auto';

  @override
  String get uiToolsQuickPanelRequired => 'Erforderlich';

  @override
  String get uiAdvancedAdaptersPageLoRAAdapters => 'LoRA-Adapter';

  @override
  String get uiAdvancedAdaptersPageImportAdapter => 'Adapter importieren';

  @override
  String get uiAdvancedAdaptersPageDelete => 'Löschen';

  @override
  String get uiAdvancedAppearancePageAppearance => 'Darstellung';

  @override
  String get uiAdvancedAppearancePageTheme => 'Design';

  @override
  String get uiAdvancedAppearancePageDarkIsTheDesignedDefaultLight =>
      'Dunkel ist der vorgesehene Standard; Hell folgt dem Telefon, wenn du „System“ wählst.';

  @override
  String get uiAdvancedAppearancePageAccentColour => 'Akzentfarbe';

  @override
  String get uiAdvancedAppearancePageTextSize => 'Textgröße';

  @override
  String get uiAdvancedAppearancePageCompactBubbles => 'Kompakte Sprechblasen';

  @override
  String get uiAdvancedAppearancePageTighterSpacingInTheConversation =>
      'Engere Abstände in der Unterhaltung.';

  @override
  String get motionLabel => 'Bewegung';

  @override
  String get motionHint =>
      'Federeffekte, sich verwandelnde Bedienelemente und weiche Unschärfe. Die Einstellung „Animationen entfernen“ deines Telefons schaltet Bewegung aus.';

  @override
  String get motionFull => 'Voll';

  @override
  String get motionSubtle => 'Dezent';

  @override
  String get motionOff => 'Aus';

  @override
  String islandLoadingModel(String model) {
    return '$model wird geladen';
  }

  @override
  String get islandModelReady => 'Modell bereit';

  @override
  String get islandResearchDone => 'Recherche fertig';

  @override
  String get islandAnswered => 'Beantwortet';

  @override
  String get jumpToLatest => 'Zur neuesten Nachricht springen';

  @override
  String get uiAdvancedMemoryRopePageMemoryRoPESpeculation =>
      'Speicher, RoPE & Spekulation';

  @override
  String get uiAdvancedMemoryRopePageKCache => 'K-Cache';

  @override
  String get uiAdvancedMemoryRopePagePrecisionOfCachedKeys =>
      'Genauigkeit der zwischengespeicherten Keys';

  @override
  String get uiAdvancedMemoryRopePageVCache => 'V-Cache';

  @override
  String get uiAdvancedMemoryRopePagePrecisionOfCachedValuesQuantisingV =>
      'Genauigkeit der zwischengespeicherten Values. Das Quantisieren von V braucht Flash Attention, die automatisch aktiviert wird.';

  @override
  String get uiAdvancedMemoryRopePageRoPEScaling => 'RoPE-Skalierung';

  @override
  String get uiAdvancedMemoryRopePageHowPositionsBeyondTheTrainedContext =>
      'Wie Positionen jenseits des trainierten Kontexts gestreckt werden. „Modell“ behält bei, was das GGUF angibt; YaRN ist die übliche Wahl für längere Kontexte bei Modellen, die es unterstützen.';

  @override
  String get uiAdvancedMemoryRopePageRoPEFrequencyBase => 'RoPE-Frequenzbasis';

  @override
  String get uiAdvancedMemoryRopePageEG1000000ForModelsThat =>
      'z. B. 1000000 für Modelle, die das dokumentieren';

  @override
  String get uiAdvancedMemoryRopePageRoPEFrequencyScale => 'RoPE-Frequenzskala';

  @override
  String get uiAdvancedMemoryRopePage0Scale1EG0 =>
      '0 < Skala ≤ 1, z. B. 0,25 für den 4-fachen trainierten Kontext';

  @override
  String get uiAdvancedMemoryRopePageYaRNOriginalContext =>
      'YaRN-Originalkontext';

  @override
  String get uiAdvancedMemoryRopePageTheContextTheModelWasTrained =>
      'Der Kontext, für den das Modell trainiert wurde';

  @override
  String get uiAdvancedMemoryRopePageYaRNExtrapolationMix =>
      'YaRN-Extrapolationsanteil';

  @override
  String get uiAdvancedMemoryRopePage0InterpolationOnly1FullExtrapolation =>
      '0 = nur Interpolation, 1 = volle Extrapolation';

  @override
  String get uiAdvancedMemoryRopePageYaRNAttentionFactor =>
      'YaRN-Attention-Faktor';

  @override
  String get uiAdvancedMemoryRopePageMagnitudeScalingUsually10 =>
      'Betragsskalierung, meist 1,0';

  @override
  String get uiAdvancedMemoryRopePageYaRNBetaFast => 'YaRN Beta fast';

  @override
  String get uiAdvancedMemoryRopePageLowCorrectionDimension =>
      'Untere Korrekturdimension';

  @override
  String get uiAdvancedMemoryRopePageYaRNBetaSlow => 'YaRN Beta slow';

  @override
  String get uiAdvancedMemoryRopePageHighCorrectionDimension =>
      'Obere Korrekturdimension';

  @override
  String get uiAdvancedMemoryRopePageDraftModel => 'Entwurfsmodell';

  @override
  String get uiAdvancedMemoryRopePageASmallerModelWithTheSame =>
      'Ein kleineres Modell mit demselben Vokabular schlägt mehrere Tokens vor; das Hauptmodell prüft sie in einem Durchgang. Hilft bei langen, vorhersehbaren Antworten; miss es nach – es kostet Speicher und kann langsamer sein.';

  @override
  String get uiAdvancedMemoryRopePageDraftTokensPerRound =>
      'Entwurfs-Tokens pro Runde';

  @override
  String get uiAdvancedMemoryRopePageHowManyTokensTheDraftProposes =>
      'Wie viele Tokens der Entwurf vor der Prüfung vorschlägt. Höher bringt mehr, wenn der Entwurf stimmt, und verschwendet mehr, wenn er falsch ist.';

  @override
  String get uiAdvancedPages2Cancel => 'Abbrechen';

  @override
  String get uiAdvancedPages2NotAValidValue => 'Kein gültiger Wert.';

  @override
  String get uiAdvancedPages2Save => 'Speichern';

  @override
  String get uiAdvancedSamplingPageMoreSampling => 'Weiteres Sampling';

  @override
  String get uiAdvancedSamplingPageSeed => 'Seed';

  @override
  String get uiAdvancedSamplingPageSeed0Random => 'Seed (0 = zufällig)';

  @override
  String get uiAdvancedSamplingPageStopSequences => 'Stoppsequenzen';

  @override
  String get uiAdvancedSamplingPagePresencePenalty => 'Präsenzstrafe';

  @override
  String get uiAdvancedSamplingPageOnceATokenHasAppearedIt =>
      'Sobald ein Token vorkam, wird es benachteiligt, unabhängig davon, wie oft. 0 ist aus; negative Werte fördern Wiederverwendung.';

  @override
  String get uiAdvancedSamplingPageFrequencyPenalty => 'Häufigkeitsstrafe';

  @override
  String get uiAdvancedSamplingPageEachRepetitionAddsToThePenalty =>
      'Jede Wiederholung erhöht die Strafe. 0 ist aus.';

  @override
  String get uiAdvancedSamplingPagePenaltyWindow => 'Strafenfenster';

  @override
  String get uiAdvancedSamplingPageHowManyRecentTokensTheRepetition =>
      'Wie viele der letzten Tokens Wiederholungs-, Präsenz- und Häufigkeitsstrafe betrachten. 0 schaltet sie aus.';

  @override
  String get uiAdvancedSamplingPageDRYMultiplier => 'DRY-Multiplikator';

  @override
  String get uiAdvancedSamplingPageDRYPenalisesRepeatingWholeSequencesRather =>
      'DRY bestraft das Wiederholen ganzer Sequenzen statt einzelner Tokens. 0 ist aus; 0,8 ist die übliche Stärke.';

  @override
  String get uiAdvancedSamplingPageDRYBase => 'DRY-Basis';

  @override
  String get uiAdvancedSamplingPageGrowthOfThePenaltyWithThe =>
      'Wachstum der Strafe mit der wiederholten Länge.';

  @override
  String get uiAdvancedSamplingPageDRYAllowedLength => 'DRY erlaubte Länge';

  @override
  String get uiAdvancedSamplingPageRepeatsShorterThanThisAreFree =>
      'Kürzere Wiederholungen sind straffrei.';

  @override
  String get uiAdvancedSamplingPageTypicalP => 'Typical-P';

  @override
  String get uiAdvancedSamplingPageKeepsTokensWhoseSurpriseIsClose =>
      'Behält Tokens, deren Überraschung nahe an der erwarteten liegt. 1,00 ist aus.';

  @override
  String get uiAdvancedSamplingPageXTCProbability => 'XTC-Wahrscheinlichkeit';

  @override
  String get uiAdvancedSamplingPageWithThisProbabilityTheMostLikely =>
      'Mit dieser Wahrscheinlichkeit werden die wahrscheinlichsten Tokens über dem Schwellenwert entfernt, außer dem letzten – für abwechslungsreichere Texte. 0 ist aus.';

  @override
  String get uiAdvancedSamplingPageXTCThreshold => 'XTC-Schwellenwert';

  @override
  String get uiAdvancedSamplingPageTokensAboveThisProbabilityAreCandidates =>
      'Tokens über dieser Wahrscheinlichkeit kommen für die Entfernung infrage.';

  @override
  String get uiAdvancedSamplingPageTopNSigma => 'Top-n-Sigma';

  @override
  String get uiAdvancedSamplingPageKeepsTokensWithinNStandardDeviations =>
      'Behält Tokens innerhalb von n Standardabweichungen vom besten Logit; funktioniert gut mit hohen Temperaturen. Aus bei 0.';

  @override
  String get uiAdvancedSamplingPageResetOrder => 'Reihenfolge zurücksetzen';

  @override
  String get uiAdvancedSamplingPageOnePerLineUpTo8 =>
      'Eine pro Zeile, bis zu 8. Die Antwort endet, sobald eine erscheint; sie selbst wird nie angezeigt.';

  @override
  String get uiAdvancedSamplingPageCancel => 'Abbrechen';

  @override
  String get uiAdvancedSamplingPageSave => 'Speichern';

  @override
  String get uiAdvancedStructuredOutputPageStructuredOutput =>
      'Strukturierte Ausgabe';

  @override
  String get uiAdvancedStructuredOutputPageResponseFormat => 'Antwortformat';

  @override
  String
  get uiAdvancedStructuredOutputPageConstrainsEveryTokenTheModelProduces =>
      'Beschränkt jedes Token, das das Modell erzeugt. Für beschränkte Antworten wird das Denken ausgeschaltet und es werden keine Werkzeuge angeboten.';

  @override
  String get uiAdvancedStructuredOutputPageJSONSchema => 'JSON-Schema';

  @override
  String get uiAdvancedStructuredOutputPageGBNFGrammar => 'GBNF-Grammatik';

  @override
  String get uiAdvancedStructuredOutputPageCancel => 'Abbrechen';

  @override
  String get uiAdvancedStructuredOutputPageSave => 'Speichern';

  @override
  String get uiAdvancedToolsPageTools => 'Werkzeuge';

  @override
  String get uiAdvancedToolsPageLetTheModelCallTools =>
      'Modell darf Werkzeuge aufrufen';

  @override
  String get uiAdvancedToolsPageTheModelCanDecideToSearch =>
      'Das Modell kann entscheiden, im Web zu suchen, eine Seite zu lesen, deine Dokumente zu durchsuchen oder zu rechnen, und dann anhand der Ergebnisse antworten. Jedes Werkzeug hat unten seine eigene Berechtigung.';

  @override
  String get uiAdvancedToolsPageToolUse => 'Werkzeugnutzung';

  @override
  String get uiAdvancedToolsPageAutoLetsTheModelDecideWhether =>
      'Bei Auto entscheidet das Modell, ob ein Werkzeug nötig ist. Erforderlich zwingt es, vor seiner ersten Antwort eines aufzurufen (spätere Runden entscheidet es wieder selbst): Nutze das, wenn das Modell immer aus dem Gedächtnis antwortet statt zu suchen.';

  @override
  String get uiAdvancedToolsPageRoundsPerAnswer => 'Runden pro Antwort';

  @override
  String get uiAdvancedToolsPageHowManyTimesTheModelMay =>
      'Wie oft das Modell Werkzeuge aufrufen darf, bevor es antworten muss. Jede Runde ist ein weiterer Modelldurchlauf.';

  @override
  String get uiAdvancedToolsPageCalculator => 'Rechner';

  @override
  String get uiAdvancedToolsPageExactArithmeticNoPermissionNeeded =>
      'Exakte Rechnungen. Keine Berechtigung nötig.';

  @override
  String get uiAdvancedToolsPageSearchWebReadUrlFindIn =>
      'search_web · read_url · find_in_page';

  @override
  String get uiAdvancedToolsPageSearchDocuments => 'search_documents';

  @override
  String get uiEffectiveSettingsPageEffectiveSettings =>
      'Wirksame Einstellungen';

  @override
  String get uiEffectiveSettingsPageAppliesWhenTheModelLoads =>
      'Gilt, sobald das Modell geladen wird.';

  @override
  String get uiEffectiveSettingsPageClose => 'Schließen';

  @override
  String get uiKnowledgePageOK => 'OK';

  @override
  String get uiKnowledgePageVerifying => 'Wird geprüft …';

  @override
  String get uiMemoryPageEGTheUserIsA =>
      'z. B. Die Person ist Pflegekraft in Lissabon und bevorzugt metrische Einheiten.';

  @override
  String get uiOverridesPageClearAll => 'Alle leeren';

  @override
  String get uiOverridesPageInherit => 'Übernehmen';

  @override
  String get uiOverridesPageOn => 'An';

  @override
  String get uiOverridesPageOff => 'Aus';

  @override
  String get uiOverridesPageCancel => 'Abbrechen';

  @override
  String get uiOverridesPageNotAValidValue => 'Kein gültiger Wert.';

  @override
  String get uiOverridesPageSave => 'Speichern';

  @override
  String get uiRemoteServerPageUseRemoteServer => 'Remote-Server verwenden';

  @override
  String get uiRemoteServerPageNoConnectionsYet => 'Noch keine Verbindungen';

  @override
  String get uiRemoteServerPageAddOneToChooseAProvider =>
      'Füge eine hinzu, um Anbieter, URL, API-Schlüssel und Modell zu wählen.';

  @override
  String get uiRemoteServerPageEditConnection => 'Verbindung bearbeiten';

  @override
  String get uiRemoteServerPageWebResearch => 'Webrecherche';

  @override
  String get uiRemoteServerPageTheAppSearchesDuckDuckGoAndReads =>
      'Das Remote-Modell entscheidet, ob eine Frage das Web braucht, formuliert eigene Suchanfragen und wählt die zu lesenden Seiten; die App führt sie ohne Schlüssel über DuckDuckGo und Wikipedia aus.';

  @override
  String get uiRemoteServerPageImageUnderstanding => 'Bildverständnis';

  @override
  String get uiRemoteServerPageSendAttachedImagesToTheModel =>
      'Angehängte Bilder an das Modell senden. Nur für Modelle mit Bildverständnis aktivieren.';

  @override
  String get uiRemoteServerPageDocumentUnderstanding => 'Dokumentverständnis';

  @override
  String get uiRemoteServerPageExtractDocumentsSafelyOnThePhone =>
      'Dokumente sicher auf dem Telefon auslesen und dann ihren Text im Prompt senden. Originaldateien werden nicht hochgeladen.';

  @override
  String get uiRemoteServerPageStreamingIdleTimeout =>
      'Streaming-Leerlaufzeitlimit';

  @override
  String get uiRemoteServerPageHowLongToWaitBetweenResponse =>
      'Wie lange zwischen Antwortteilen eines langsamen oder stark ausgelasteten Servers gewartet wird.';

  @override
  String get uiRemoteServerPageChooseAProvider => 'Anbieter auswählen';

  @override
  String get uiSettingsScreenEncryptedBackup => 'Verschlüsseltes Backup';

  @override
  String get uiSettingsScreenMoreSampling => 'Weiteres Sampling';

  @override
  String get uiSettingsScreenMemoryRoPESpeculation =>
      'Speicher, RoPE & Spekulation';

  @override
  String get uiSettingsScreenStructuredOutput => 'Strukturierte Ausgabe';

  @override
  String get uiSettingsScreenTools => 'Werkzeuge';

  @override
  String get uiSettingsScreenLoRAAdapters => 'LoRA-Adapter';

  @override
  String get uiSettingsScreenEffectiveSettings => 'Wirksame Einstellungen';

  @override
  String get uiSettingsScreenAppearance => 'Darstellung';

  @override
  String get uiMetricsSheetInstrumentPanel => 'Instrumententafel';

  @override
  String get uiMetricsSheetDisplay => 'Anzeige';

  @override
  String get uiMetricsSheetBenchmarkThisModel => 'Dieses Modell benchmarken';

  @override
  String get uiMetricsSheetMeasuredOnThisDeviceNothingIs =>
      'Auf diesem Gerät gemessen. Es wird nichts übertragen.';

  @override
  String get uiMetricsSheetSendAMessageToSeeLive =>
      'Sende eine Nachricht, um Live-Werte zu sehen.';

  @override
  String get uiMetricsSheetBackend => 'Backend';

  @override
  String get uiMetricsSheetNativeLibrary => 'Native Bibliothek';

  @override
  String get uiMetricsSheetStages => 'Phasen';

  @override
  String get uiMetricsSheetTokensSec => 'Tokens/s';

  @override
  String get uiMetricsSheetFirstToken => 'Erstes Token';

  @override
  String get uiMetricsSheetTokens => 'Tokens';

  @override
  String get uiMetricsSheetContext => 'Kontext';

  @override
  String get uiMetricsSheetPeakRSS => 'Spitzen-RSS';

  @override
  String get uiMetricsSheetTemplate => 'Vorlage';

  @override
  String get uiMetricsSheetThinking => 'Denken';

  @override
  String get uiMetricsSheetModel => 'Modell';

  @override
  String get uiSettingsWidgetsCancel => 'Abbrechen';

  @override
  String get uiSettingsWidgetsApply => 'Anwenden';

  @override
  String get uiPresetSheet00Exact => '0,0 · exakt';

  @override
  String get uiPresetSheet03Focused => '0,3 · fokussiert';

  @override
  String get uiPresetSheet07Balanced => '0,7 · ausgewogen';

  @override
  String get uiPresetSheet10Creative => '1,0 · kreativ';

  @override
  String get uiModelsScreenHttpsHuggingfaceCo => 'https://huggingface.co/…';

  @override
  String get uiModelsScreenModelReadiness => 'Modell-Eignung';

  @override
  String get uiModelsScreenImportConfiguration => 'Konfiguration importieren';

  @override
  String get uiModelsScreenImportConfigurationFromClipboard =>
      'Konfiguration aus Zwischenablage importieren';

  @override
  String get uiModelsScreenImportConfigurationFromAFile =>
      'Konfiguration aus Datei importieren';

  @override
  String get uiModelsScreenShareOrImportAConfiguration =>
      'Konfiguration teilen oder importieren';

  @override
  String get uiModelsScreenShareConfiguration => 'Konfiguration teilen';

  @override
  String get uiModelsScreenCopyAsText => 'Als Text kopieren';

  @override
  String get uiModelsScreenImportFromClipboard =>
      'Aus Zwischenablage importieren';

  @override
  String get uiModelsScreenImportFromAFile => 'Aus Datei importieren';

  @override
  String get uiModelCardRemoveFromList => 'Aus Liste entfernen';

  @override
  String get uiModelPickerSheetRemoteConnections => 'Remote-Verbindungen';

  @override
  String get uiModelPickerSheetAnswersComeFromTheConnectionInstead =>
      'Die Antworten kommen von der Verbindung statt von einem Modell auf diesem Telefon.';

  @override
  String get uiQrViewQRCodeWithTheConnectionDetails =>
      'QR-Code mit den Verbindungsdaten';

  @override
  String get uiChatScreenActionsTitle => 'Titel';

  @override
  String get uiChatScreenActionsDocumentType => 'Dokumenttyp';

  @override
  String get uiChatScreenActionsWordDocx => 'Word (.docx)';

  @override
  String get uiChatScreenActionsPDF => 'PDF';

  @override
  String get uiChatScreenActionsPlainTextTxt => 'Reiner Text (.txt)';

  @override
  String get uiChatScreenActionsMarkdownMd => 'Markdown (.md)';

  @override
  String get uiChatScreenActionsHTML => 'HTML';

  @override
  String get uiChatScreenActionsSelectIndividualMessages =>
      'Einzelne Nachrichten auswählen';

  @override
  String get uiChatScreenActionsRedactTermsCommaSeparated =>
      'Begriffe schwärzen (durch Kommas getrennt)';

  @override
  String get uiChatScreenActionsChooseMessages => 'Nachrichten auswählen';

  @override
  String get uiChatScreenActionsUseSelection => 'Auswahl verwenden';

  @override
  String get uiChatScreenActionsReviewDocument => 'Dokument prüfen';

  @override
  String get uiChatBubbleChooseQuestionVersion => 'Version der Frage wählen';

  @override
  String get uiChatBubbleSources => 'Quellen';

  @override
  String get uiChatBubbleKnowledgeLibrary => 'Wissensbibliothek';

  @override
  String get uiChatBubbleSponsoredNotUsed => 'Gesponsert (nicht verwendet)';

  @override
  String get uiChatBubbleOpenInBrowser => 'Im Browser öffnen';

  @override
  String get uiCodeBlockCopyCode => 'Code kopieren';

  @override
  String get uiCodeBlockCodeCopied => 'Code kopiert';

  @override
  String get readinessUnavailable => 'Auf diesem Gerät nicht verfügbar';

  @override
  String readinessMemory(Object total, Object available) {
    return '$total gesamt · $available jetzt verfügbar';
  }

  @override
  String readinessStorage(Object free, Object total) {
    return '$free von $total frei';
  }

  @override
  String readinessInstalledWeights(Object size, Object count) {
    return '$size in $count Modellen';
  }

  @override
  String readinessContext(Object count, Object backend) {
    return '$count Tokens · $backend';
  }

  @override
  String get readinessInstalled => 'Installiert';

  @override
  String readinessDownload(Object size) {
    return 'Download: $size';
  }

  @override
  String get readinessRamFits => 'RAM-Schätzung: passt wahrscheinlich';

  @override
  String get readinessRamMayNotFit => 'RAM-Schätzung: passt eventuell nicht';

  @override
  String get readinessDiskAvailable => 'Speicherplatz verfügbar';

  @override
  String get readinessDiskInsufficient =>
      'Speicherplatz reicht eventuell nicht';

  @override
  String readinessMeasured(Object speed) {
    return 'Gemessen: $speed Tok/s';
  }

  @override
  String benchmarkFailed(Object error) {
    return 'Benchmark fehlgeschlagen: $error';
  }

  @override
  String benchmarkRunning(Object model, Object runs) {
    return 'Benchmark von $model …\nLaden, dann $runs Durchläufe mit ~380 Tokens Prefill und 128 Greedy-Tokens (erster verworfen, Mediane angegeben), dann ein Chat mit dem System-Prompt der App, mit und ohne Werkzeuge.';
  }

  @override
  String get hfIntro =>
      'Nur öffentliche GGUF-Repositorys, die meistgeladenen zuerst. Jeder Download ist an die Repository-Revision gebunden und wird wie beim integrierten Katalog gegen die SHA-256 des Hubs geprüft. Vision-Projektoren (mmproj) und aufgeteilte Dateien werden angezeigt, können aber noch nicht hinzugefügt werden.';

  @override
  String hfAdded(Object model, Object size, Object template) {
    return '$model hinzugefügt · $size · Vorlage $template';
  }

  @override
  String get hfFromMetadata => 'aus Metadaten';

  @override
  String hfRepoStats(Object downloads, Object likes) {
    return '$downloads Downloads · $likes Likes';
  }

  @override
  String get hfInLibrary => 'in der Bibliothek';

  @override
  String hfLicenseRevision(Object license, Object revision) {
    return 'Lizenz: $license · Revision $revision';
  }

  @override
  String get hfVisionProjector => 'Vision-Projektor';

  @override
  String get hfSplitFile => 'aufgeteilte Datei';

  @override
  String remoteDeleteHint(Object name) {
    return '„$name“ und sein API-Schlüssel werden von diesem Telefon entfernt.';
  }

  @override
  String get remoteOwnServer => 'Ein Server auf deiner eigenen Hardware.';

  @override
  String get remoteHostedBilling =>
      'Gehostete API, abgerechnet über deinen Schlüssel.';

  @override
  String get remoteNameHelp => 'Wie diese Verbindung in der Liste erscheint.';

  @override
  String remoteOwnUrlHelp(Object path) {
    return 'LM Studio: Port 1234 · Ollama: 11434 · llama-server: 8080. „$path“ wird automatisch ergänzt.';
  }

  @override
  String remoteHostedUrlHelp(Object provider) {
    return 'Für $provider vorausgefüllt; ändere sie nur für einen Proxy oder einen regionalen Endpunkt.';
  }

  @override
  String get remoteInvalidUrl => 'Gib eine http(s)-URL ein.';

  @override
  String get remoteApiKey => 'API-Schlüssel';

  @override
  String get remoteApiKeyOptional => 'API-Schlüssel (optional)';

  @override
  String remoteKeyHostedHelp(Object provider) {
    return 'Im Android-Schlüsselspeicher abgelegt; wird nur an $provider gesendet.';
  }

  @override
  String get remoteKeySelfHelp =>
      'Nur wenn der Server mit einem Schlüssel gestartet wurde. Im Android-Schlüsselspeicher abgelegt.';

  @override
  String get remoteHideKey => 'Schlüssel verbergen';

  @override
  String get remoteShowKey => 'Schlüssel anzeigen';

  @override
  String get remoteServerDefaultModel =>
      'Leer lassen für den Standard des Servers';

  @override
  String get remoteModelId => 'Modell-ID';

  @override
  String get remoteModelListHelp =>
      'Teste die Verbindung, um aus den Modellen dieses Anbieters zu wählen.';

  @override
  String get remoteModelManualHelp =>
      'Dieser Anbieter hat keine Modellliste; gib die ID aus seiner Dokumentation ein.';

  @override
  String get remoteTestList => 'Testen & Modelle auflisten';

  @override
  String get remoteTestConnection => 'Verbindung testen';

  @override
  String get remoteExtraHeadersHelp =>
      'Ein „Name: Wert“ pro Zeile, wird mit jeder Anfrage gesendet (z. B. OpenAI-Organization, OpenRouter-Attribution). Der Schlüssel-Header wird automatisch gesetzt.';

  @override
  String get remoteConnectedNoList =>
      'Verbunden. Dieser Anbieter hat keine Modellliste; gib die Modell-ID ein.';

  @override
  String get remoteConnectedServerNoModels =>
      'Verbunden, aber der Server listet keine Modelle. Lade eines in LM Studio bzw. starte eines in Ollama.';

  @override
  String get remoteConnectedNoModels =>
      'Verbunden, aber für diesen Schlüssel wurden keine Modelle gelistet.';

  @override
  String get remoteCapabilities => 'Fähigkeiten';

  @override
  String get remoteRequestLimits => 'Anfragelimits';

  @override
  String get remoteAdvanced => 'Erweitert';

  @override
  String get remoteAnthropicNote =>
      'Anthropic: Der Denkmodus aktiviert adaptives Denken mit Zusammenfassungen; Temperatur/Top-P werden nicht gesendet, da die aktuellen Modelle sie ablehnen. Werkzeugaufrufe, Bilder und JSON-Schema-Ausgabe werden unterstützt.';

  @override
  String get remoteGeminiNote =>
      'Gemini: Der Denkmodus zeigt Gedankenzusammenfassungen; Funktionsaufrufe, Bilder und JSON-Ausgabe werden unterstützt. Signaturen von Funktionsaufrufen bleiben für die Sitzung erhalten.';

  @override
  String get remoteSelfHostedNote =>
      'Verbinde dich nur mit Rechnern, die du selbst kontrollierst. Die Verbindung ist so privat wie das Netzwerk dazwischen: Nutze über das Internet HTTPS oder ein VPN.';

  @override
  String remoteHostedNote(Object provider) {
    return 'Anfragen werden über dein $provider-Konto abgerechnet. Lege oben ein Tageslimit fest, wenn du den Schlüssel in mehreren Apps nutzt.';
  }

  @override
  String get remoteNoTools => 'keine';

  @override
  String remoteToolsDetected(Object tools) {
    return ' Server-Werkzeuge erkannt: $tools; sie werden nicht automatisch ausgeführt.';
  }

  @override
  String remoteContextWindow(Object count) {
    return ' Kontextfenster $count Tokens.';
  }

  @override
  String remoteAdvertises(
    Object model,
    Object capabilities,
    Object context,
    Object tools,
  ) {
    return '$model meldet: $capabilities.$context$tools';
  }

  @override
  String remoteContextOnly(Object model, Object count, Object tools) {
    return '$model: Kontextfenster $count Tokens.$tools';
  }

  @override
  String remoteNoCapabilities(Object tools) {
    return 'Dieser Anbieter meldet keine Fähigkeiten für das gewählte Modell. Stimme die Schalter auf der vorherigen Seite auf das verwendete Modell ab.$tools';
  }

  @override
  String get remoteDefaultModel => 'das Standardmodell';

  @override
  String remoteCapsHint(Object model) {
    return 'Limits für $model bei dieser Verbindung. Ist ein Limit erreicht, sendet die App nichts mehr; jede Werkzeugrunde zählt als eine Anfrage. Leer bedeutet kein Limit.';
  }

  @override
  String remoteUsed(Object minute, Object day) {
    return 'Genutzt: $minute in dieser Minute · $day heute';
  }

  @override
  String remoteOtherCaps(Object models) {
    return 'Weitere Modelle mit Limits hier: $models.';
  }

  @override
  String scheduleLoadFailed(Object error) {
    return 'Geplante Prompts konnten nicht geladen werden: $error';
  }

  @override
  String get noticeCheckingSearch => 'Prüfe, ob gesucht werden soll …';

  @override
  String get noticeResearchingTools => 'Recherchiere mit Werkzeugen …';

  @override
  String get noticeNamingChat => 'Chat wird benannt …';

  @override
  String get noticeSearchingAgain =>
      'Suche erneut nach dem, was die Seiten ausgelassen haben …';

  @override
  String get noticeFollowUpSearch =>
      'Die zuvor gelesenen Seiten beantworten das nicht. Suche erneut …';

  @override
  String answerSourcesDated(String date) {
    return 'Quellen zuletzt aktualisiert am $date.';
  }

  @override
  String get answerSourcesUndated =>
      'Die Quellen geben nicht an, wann sie zuletzt aktualisiert wurden.';

  @override
  String sourceUpdated(String date) {
    return 'aktualisiert am $date';
  }

  @override
  String get thinkOnSearchSetting => 'Vor Antworten aus Quellen nachdenken';

  @override
  String get thinkOnSearchHint =>
      'Ein denkfähiges Modell wägt zuerst die Seiten ab (bis etwa 1.000 Tokens), auch wenn der Denkmodus aus ist.';

  @override
  String get searchAgainSetting => 'Erneut suchen, wenn Seiten nicht reichen';

  @override
  String get searchAgainHint =>
      'Wenn die gelesenen Seiten einen Teil der Frage offenlassen: eine weitere Suche und bis zu zwei weitere Seiten.';

  @override
  String get wikipediaLookupSetting => 'Wikipedia-Artikel hinzufügen';

  @override
  String get wikipediaLookupHint =>
      'Der Wikipedia-Artikel zum Thema kommt in der Sprache der Frage zu den Quellen hinzu, sofern einer passt.';

  @override
  String get zimSetting => 'Offline-Wikipedia';

  @override
  String get zimHint =>
      'Importiere eine Kiwix-.zim-Datei (von library.kiwix.org), um ohne Verbindung aus Wikipedia zu antworten.';

  @override
  String get zimImport => 'Importieren';

  @override
  String get zimRemove => 'Entfernen';

  @override
  String zimImporting(String percent) {
    return 'Wird kopiert … $percent';
  }

  @override
  String get zimNotAZim => 'Diese Datei ist keine .zim-Datei.';

  @override
  String get autoTitlesSetting => 'Chats automatisch benennen';

  @override
  String get autoTitlesHint =>
      'Nach der ersten Antwort gibt das Modell dem Chat einen kurzen Titel. Aus: Die erste Nachricht ist der Titel.';

  @override
  String get webModeNote =>
      'Der Webrecherche-Modus (Aus / Auto / Immer) wird auf dem Haupt-Einstellungsbildschirm oder über den Schalter im Eingabefeld festgelegt.';

  @override
  String get thinkingBudgetUnlimited => 'Unbegrenzt';

  @override
  String get adapterImporting => 'Adapter wird geprüft und kopiert …';

  @override
  String get adapterEmpty =>
      'Noch keine Adapter. Importiere mit + ein LoRA-GGUF (erstellt mit convert_lora_to_gguf.py von llama.cpp) und hänge es an ein Modell derselben Architektur. Das Modell wird mit dem Adapter in der gewählten Stärke neu geladen.';

  @override
  String get versionPrevious => 'Vorherige Version';

  @override
  String get versionNext => 'Nächste Version';

  @override
  String get sourceFallbackTitle => 'Quelle';

  @override
  String sourcePublished(String date) {
    return 'veröffentlicht am $date';
  }

  @override
  String get sourceReadEarlier => 'früher gelesen';

  @override
  String get sourceMayBeOutdated => 'möglicherweise veraltet';

  @override
  String get sourceSponsored => 'Gesponsertes Ergebnis';

  @override
  String get sourceSponsoredDetail =>
      'Gesponsertes Ergebnis · zur Transparenz angezeigt · nicht gelesen und dem Modell nicht als Beleg gegeben';

  @override
  String sourceNewsStory(String outlet) {
    return 'Nachricht · $outlet';
  }

  @override
  String get sourceNewsGiven =>
      'die Schlagzeile und Zusammenfassung unten wurden dem Modell gegeben';

  @override
  String get sourcePageRead => 'Seite gelesen';

  @override
  String get sourceKeptCopy =>
      'gespeicherte Kopie, die Website war nicht erreichbar; möglicherweise veraltet';

  @override
  String get sourcePassagesGiven =>
      'die Abschnitte unten wurden dem Modell gegeben';

  @override
  String sourceReadFailed(String error) {
    return 'Seite konnte nicht gelesen werden ($error) · nur das Such-Snippet war verfügbar';
  }

  @override
  String get sourceSnippetOnly =>
      'Nur Such-Snippet · die Seite wurde nicht gelesen';

  @override
  String get sourceHeadlineOnly =>
      'Nur Schlagzeile und Eintrag · Artikeltext nicht verfügbar';

  @override
  String get sourceExtractedSection =>
      'Extrahierte Abschnitte · prüfe den zitierten Text auf Belege';

  @override
  String sourceArchiveSnapshot(String date, String language) {
    return 'Offline-Archiv · $date · $language';
  }

  @override
  String get sourceOfflineLimitation =>
      'Dieses Archiv kann aktuelle oder sich ändernde Fakten nicht bestätigen.';

  @override
  String get sourceArchiveUnavailable =>
      'Das Originalarchiv ist nicht verfügbar. Der gespeicherte Auszug wird angezeigt.';

  @override
  String get sourceNoText => 'Kein Text.';

  @override
  String get sourceGivenHeading => 'Was das Modell erhalten hat';

  @override
  String sourcePassageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Abschnitte',
      one: '1 Abschnitt',
    );
    return '$_temp0';
  }

  @override
  String sourceReadAt(String time) {
    return 'Gelesen $time';
  }

  @override
  String get sourceOpenArchived => 'Offline-Artikel öffnen';

  @override
  String get sourceCopyLink => 'Link kopieren';

  @override
  String get sourceLinkCopied => 'Link kopiert';

  @override
  String get sourceAddress => 'Vollständige Adresse';

  @override
  String sourceFromKnowledge(String title) {
    return 'Aus deiner Wissensbibliothek ($title).';
  }

  @override
  String get fitFits => 'Passt auf dieses Telefon';

  @override
  String get fitTight => 'Knapp beim RAM';

  @override
  String get fitTooLarge => 'Zu groß für dieses Telefon';

  @override
  String get configApplyNote =>
      'Das Anwenden ersetzt das Profil dieses Modells. Webrecherche und Hardware bleiben, wie du sie eingestellt hast.';

  @override
  String configApplied(String model) {
    return 'Auf $model angewendet. Gilt ab der nächsten Antwort.';
  }

  @override
  String get storageUnavailable => 'Auf diesem Gerät nicht verfügbar';

  @override
  String modelProfileTitle(String model) {
    return 'Profil von $model';
  }

  @override
  String get modelProfileScope => 'Modellprofil';

  @override
  String conversationsLoadFailed(String error) {
    return 'Unterhaltungen konnten nicht geladen werden.\n$error';
  }

  @override
  String get adapterUnknownArchitecture => 'unbekannte Architektur';

  @override
  String adapterAppliedAt(String scale) {
    return 'Angewendet mit Stärke $scale';
  }

  @override
  String get adapterNotApplied => 'Nicht angewendet';

  @override
  String get noticeUpdatingMemory => 'Erinnerung wird aktualisiert …';

  @override
  String noticeWeatherLoading(String place) {
    return 'Wetter für $place von DuckDuckGo …';
  }

  @override
  String noticeWeatherDone(String place) {
    return 'Wetter für $place von DuckDuckGo (Apple WeatherKit).';
  }

  @override
  String get noticeCollectingNews =>
      'Die neuesten Nachrichten werden gesammelt …';

  @override
  String get noticeWebOffUnverified =>
      'Die Websuche ist aus. Aktuelle Informationen wurden nicht überprüft.';

  @override
  String get noticeOpeningStory => 'Diese Meldung wird geöffnet …';

  @override
  String get noticeStopping => 'Wird gestoppt …';

  @override
  String get noticeSearching => 'Suche bei DuckDuckGo …';

  @override
  String get noticeCheckingWikipedia => 'Prüfe Wikipedia …';

  @override
  String noticeRecallArticle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count frühere Quellen',
      one: '1 frühere Quelle',
    );
    return 'Den Artikel hinter dieser Meldung gelesen, dazu $_temp0 aus diesem Chat.';
  }

  @override
  String noticeRecallPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '1 Seite',
    );
    return 'Antwort aus $_temp0, die in diesem Chat schon gelesen wurden.';
  }

  @override
  String get noticeImageRemoteOff =>
      'Bildeingabe ist für den Remote-Server deaktiviert. Aktiviere sie in den Remote-Server-Einstellungen, wenn das gewählte Modell Bilder versteht.';

  @override
  String get noticeImageNoVision =>
      'Dieses Modell kann keine Fotos sehen. Füge seine Vision-Datei unter „Modelle“ hinzu oder wähle ein Modell mit Bildverständnis.';

  @override
  String noticeKnowledgeDocs(int count, String collection) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dokumente',
      one: '1 Dokument',
    );
    return '$_temp0 aus „$collection“';
  }

  @override
  String noticePlusWebResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Webergebnisse',
      one: '1 Webergebnis',
    );
    return ' plus $_temp0';
  }

  @override
  String noticeUsingTool(String tool, String args) {
    return 'Verwende $tool$args …';
  }

  @override
  String get noticeStopped =>
      'Generierung gestoppt. Eine unvollständige Antwort wurde behalten.';

  @override
  String noticeTrimmed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count frühere Nachrichten wurden',
      one: '1 frühere Nachricht wurde',
    );
    return '$_temp0 aus dem Modellkontext ausgelassen; sie bleiben in deinem Verlauf.';
  }

  @override
  String noticeTokenLimit(int count) {
    return 'Die Antwort endete beim Limit von $count Tokens. Tippe auf „Fortsetzen“ oder erhöhe „Max. Tokens“ unter Einstellungen > Sampling.';
  }

  @override
  String get noticeStopSequence => 'Die Antwort endete an einer Stoppsequenz.';

  @override
  String get noticeResearchSkipped =>
      'Das Modell hat ohne Suche geantwortet, daher wurde in dieser Runde nichts überprüft. Erzeuge die Antwort neu oder schalte die modellgesteuerte Recherche aus, um die feste Suche zu nutzen.';

  @override
  String get noticeNoSourcesWebOff =>
      'Die Webrecherche ist aus, daher hatte das Modell keine Quellen. Tippe auf den Schalter „Lokal“, um sie einzuschalten.';

  @override
  String get noticeNoSourcesNoSearch =>
      'Für diese Nachricht lief keine Suche, daher hatte das Modell keine Quellen. Stelle den Schalter auf Web · immer oder frag mit „suche nach …“.';

  @override
  String noticeStoriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Meldungen',
      one: '1 Meldung',
    );
    return '$_temp0';
  }

  @override
  String noticeOutletsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Medien',
      one: '1 Medium',
    );
    return '$_temp0';
  }

  @override
  String noticeArticlesRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Artikel gelesen',
      one: '1 Artikel gelesen',
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
    return '$stories aus $outlets$articles in $seconds s.';
  }

  @override
  String get noticeLinkUnreadable =>
      'Die verlinkte Seite konnte nicht gelesen werden.';

  @override
  String get noticeNoWebResults =>
      'Keine Webergebnisse. Aktuelle Informationen konnten nicht überprüft werden.';

  @override
  String noticeLinkedRead(int read, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total verlinkten Seiten',
      one: '1 verlinkten Seite',
    );
    return '$read von $_temp0 gelesen.';
  }

  @override
  String noticePagesRead(int read, int results, String queries) {
    String _temp0 = intl.Intl.pluralLogic(
      read,
      locale: localeName,
      other: '$read Seiten',
      one: '1 Seite',
    );
    return '$_temp0 aus $results Ergebnissen gelesen$queries.';
  }

  @override
  String noticeQueries(int count) {
    return ' ($count Suchanfragen)';
  }

  @override
  String get noticeEvidenceNoFit =>
      'Die Belege aus dem Web passten nicht in den Kontext. Erhöhe den Kontext oder verringere die Antwortlänge.';

  @override
  String noticeWaitingServer(String client) {
    return 'Warte, bis der Geräteserver eine Anfrage von $client abgeschlossen hat …';
  }

  @override
  String noticeReadingPage(int n, int limit, String host) {
    return 'Lese $n von $limit$host …';
  }

  @override
  String noticeToolCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kürzungen',
      one: '1 Kürzung',
    );
    return 'Werkzeugergebnisse wurden gekürzt, um in den Kontext zu passen ($_temp0). Erhöhe die Kontextgröße oder senke das Ausgabebudget pro Werkzeug.';
  }

  @override
  String noticeDocCut(int percent) {
    return 'Der angehängte Text wurde gekürzt, um in den Kontext zu passen ($percent % behalten). Erhöhe die Kontextgröße für die ganze Datei.';
  }

  @override
  String noticeRefusal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Quellen bereitgestellt wurden',
      one: '1 Quelle bereitgestellt wurde',
    );
    return 'Das Modell sagte, es könne nicht im Web surfen, obwohl $_temp0. Erzeuge die Antwort neu oder probiere ein anderes Modell.';
  }

  @override
  String noticeNoCitations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bereitgestellten Quellen',
      one: '1 bereitgestellten Quelle',
    );
    return 'Die Antwort zitiert keine der $_temp0; betrachte sie als ungeprüft.';
  }

  @override
  String noticeBogusCitations(String cited, int count) {
    return 'Die Antwort zitiert Quelle $cited, die nicht bereitgestellt wurde; es gibt nur [1]–[$count].';
  }

  @override
  String noticeFigures(String figures, String more) {
    return 'Nicht in den Quellen gefunden: $figures$more. Betrachte diese Zahlen als ungeprüft.';
  }

  @override
  String noticeFiguresMiscited(String figures, String more) {
    return 'Nicht in der dafür zitierten Quelle: $figures$more. Eine andere Quelle enthält sie; prüfe die Quellenangabe.';
  }

  @override
  String get noticeCitationsMatched =>
      'Das Modell hat keine Quellen zitiert; die [n]-Markierungen wurden anhand von Wörtern und Zahlen den Quellen zugeordnet.';

  @override
  String noticeAndMore(int count) {
    return ' und $count weitere';
  }

  @override
  String get searchChallenge =>
      'DuckDuckGo hat eine Bot-Prüfung verlangt, daher ist die automatische Suche für eine Minute pausiert. Eingefügte Links funktionieren weiterhin.';

  @override
  String searchCooldown(int seconds) {
    return 'Die Suche ist nach einer DuckDuckGo-Sperre pausiert; sie geht in $seconds s weiter. Eingefügte Links funktionieren weiterhin.';
  }

  @override
  String get searchRateLimit =>
      'DuckDuckGo drosselt Suchanfragen; für eine Minute pausiert. Eingefügte Links funktionieren weiterhin.';

  @override
  String get searchMarkup =>
      'DuckDuckGo hat seine Ergebnisseite geändert und die Ergebnisse konnten nicht ausgewertet werden. Eingefügte Links funktionieren weiterhin; für die Suche ist ein App-Update nötig.';

  @override
  String get searchUnavailable =>
      'Websuche nicht verfügbar (keine Verbindung oder DuckDuckGo nicht erreichbar). Aktuelle Informationen konnten nicht überprüft werden.';

  @override
  String noticeThrottle(int drop, String from, String to) {
    return 'Tempo um $drop % gesunken ($from → $to Tok/s). Das Telefon drosselt eventuell; probiere einen kürzeren Kontext, weniger GPU-Schichten oder ein kleineres Modell.';
  }

  @override
  String get outputGrammarCut =>
      'Die grammatikbeschränkte Ausgabe wurde beim Token-Limit abgeschnitten.';

  @override
  String get outputSchemaMismatch =>
      'Die Ausgabe ist gültiges JSON, aber nicht das Objekt, das das Schema verlangt.';

  @override
  String outputJsonCut(int count) {
    return 'Die JSON-Ausgabe wurde beim Limit von $count Tokens abgeschnitten und ist nicht lesbar. Erhöhe „Max. Tokens“.';
  }

  @override
  String get outputNotJson => 'Die Ausgabe ist kein gültiges JSON.';

  @override
  String noticeBatterySaver(String reason, int tokens) {
    return 'Energiesparen ($reason): kein Denken, Antworten bis $tokens Tokens, weniger gelesene Seiten.';
  }

  @override
  String saverReasonBattery(int level) {
    return 'Akku $level %';
  }

  @override
  String saverReasonHot(String label) {
    return 'Telefon heiß: $label';
  }

  @override
  String newsCollecting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Verlagen',
      one: '1 Verlag',
    );
    return 'Sammle die heutigen Meldungen von DuckDuckGo News und $_temp0 …';
  }

  @override
  String newsReadingArticles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Artikel',
      one: '1 Artikel',
    );
    return 'Lese $_temp0 …';
  }

  @override
  String get chatErrorNoModel =>
      'Füge im Tab „Modelle“ ein Modell hinzu und sende dann deine Nachricht.';

  @override
  String chatErrorSave(String error) {
    return 'Antwort konnte nicht gespeichert werden: $error. Kopiere die Antwort, bevor du diesen Chat verlässt.';
  }

  @override
  String get chatErrorNoText =>
      'Das Modell hat keinen Text erzeugt. Probiere eine andere Vorlage oder ein anderes Modell.';

  @override
  String chatErrorServing(String model) {
    return 'Dieses Telefon stellt $model für ein anderes Gerät bereit. Stoppe den Geräteserver (Einstellungen), um mit einem anderen Modell zu chatten.';
  }

  @override
  String chatErrorServerBusy(String client) {
    return 'Der Geräteserver beantwortet noch $client. Versuche es erneut, wenn er fertig ist.';
  }

  @override
  String get settingGroupGeneration => 'Generierung';

  @override
  String get settingGroupReasoning => 'Denken';

  @override
  String get settingGroupWeb => 'Webrecherche';

  @override
  String get settingGroupTools => 'Werkzeuge';

  @override
  String get settingGroupOutput => 'Strukturierte Ausgabe';

  @override
  String get settingGroupContext => 'Kontext';

  @override
  String get settingGroupHardware => 'Hardware';

  @override
  String get settingGroupPrompt => 'Prompt';

  @override
  String get settingLabelSystemPrompt => 'Eigene Anweisungen';

  @override
  String get settingLabelTemperature => 'Temperatur';

  @override
  String get settingLabelTopP => 'Top-P';

  @override
  String get settingLabelMinP => 'Min-P';

  @override
  String get settingLabelTopK => 'Top-K';

  @override
  String get settingLabelTypicalP => 'Typical-P';

  @override
  String get settingLabelRepetitionPenalty => 'Wiederholungsstrafe';

  @override
  String get settingLabelPresencePenalty => 'Präsenzstrafe';

  @override
  String get settingLabelFrequencyPenalty => 'Häufigkeitsstrafe';

  @override
  String get settingLabelRepeatLastN => 'Strafenfenster (Tokens)';

  @override
  String get settingLabelMaxTokens => 'Max. Tokens';

  @override
  String get settingLabelSeed => 'Seed (0 = zufällig)';

  @override
  String get settingLabelStopSequences => 'Stoppsequenzen';

  @override
  String get settingLabelThinkingModeEnabled => 'Denkmodus';

  @override
  String get settingLabelThinkingBudgetTokens => 'Denkbudget (0 = unbegrenzt)';

  @override
  String get settingLabelWebMode => 'Webrecherche';

  @override
  String get settingLabelResearchLoop => 'Modellgesteuerte Recherche';

  @override
  String get settingLabelMaxPagesRead => 'Zu lesende Seiten';

  @override
  String get settingLabelEvidencePassages =>
      'An das Modell übergebene Abschnitte';

  @override
  String get settingLabelKnowledgeCollection => 'Wissenssammlung';

  @override
  String get settingLabelToolsEnabled => 'Werkzeugaufrufe';

  @override
  String get settingLabelToolChoice => 'Werkzeugnutzung';

  @override
  String get settingLabelToolMaxRounds => 'Werkzeugrunden pro Antwort';

  @override
  String get settingLabelResponseFormat => 'Antwortformat';

  @override
  String get settingLabelJsonSchema => 'JSON-Schema';

  @override
  String get settingLabelGrammar => 'GBNF-Grammatik';

  @override
  String get settingLabelContextSize => 'Kontextgröße';

  @override
  String get settingLabelPromptCache => 'Unterhaltung im Kontext behalten';

  @override
  String get settingLabelBackend => 'Backend';

  @override
  String get settingLabelNGpuLayers => 'GPU-Schichten';

  @override
  String get settingLabelCpuThreads => 'CPU-Threads (Decode, 0 = auto)';

  @override
  String get settingLabelBatchThreads => 'CPU-Threads (Prefill, 0 = auto)';

  @override
  String get settingLabelFlashAttention => 'Flash Attention';

  @override
  String get settingLabelKvCacheType => 'K-Cache-Typ';

  @override
  String get settingLabelVCacheType => 'V-Cache-Typ (leer = wie K)';

  @override
  String get settingLabelRopeScaling => 'RoPE-Skalierung';

  @override
  String get settingLabelDraftModelId =>
      'Entwurfsmodell (spekulatives Decoding)';

  @override
  String get hostLocalOnly => 'Nur lokales Netzwerk und VPN';

  @override
  String get hostLocalOnlyHint =>
      'Geräte in diesem WLAN, deinem Hotspot oder deinem VPN (Tailscale, WireGuard …) können sich mit dem Token verbinden. Anfragen aus dem öffentlichen Internet werden abgelehnt.';

  @override
  String settingEmptyMeans(String value) {
    return 'Leer = $value';
  }

  @override
  String settingEffectiveValue(String value) {
    return 'Wirksam: $value';
  }

  @override
  String settingInherit(String value) {
    return 'Übernehmen ($value)';
  }

  @override
  String get remoteScanQr => 'QR-Code scannen';

  @override
  String get remoteScanHint =>
      'Richte die Kamera auf den QR-Code auf dem anderen Telefon (Einstellungen > Dieses Gerät als Server nutzen).';

  @override
  String get remoteScanInvalid =>
      'Dieser QR-Code ist keine OnDevice-LLM-Verbindung. Ziele weiter auf den Code des Servers.';

  @override
  String remoteScanNoCamera(String error) {
    return 'Die Kamera ist nicht verfügbar: $error';
  }

  @override
  String get remoteNameConnection => 'Verbindung benennen';

  @override
  String get remoteNameHint => 'Zum Beispiel: Wohnzimmer-PC';

  @override
  String get answerFromMemory =>
      'Aus dem Gedächtnis des Modells – möglicherweise veraltet.';

  @override
  String get searchTheWeb => 'Im Web suchen';

  @override
  String get searchMissesTitle => 'Von Hand ans Web geschickte Fragen';

  @override
  String searchMissesHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Fragen. Kopiere sie, um die Suchbegriffe zu verbessern; ansonsten verlassen sie dieses Telefon nie.',
      one:
          '1 Frage. Kopiere sie, um die Suchbegriffe zu verbessern; ansonsten verlassen sie dieses Telefon nie.',
      zero:
          'Noch keine. Wenn eine Antwort aus dem Gedächtnis kam und du auf „Im Web suchen“ getippt hast, wird die Frage hier aufbewahrt (nur auf diesem Telefon), damit die Suchbegriffe verbessert werden können.',
    );
    return '$_temp0';
  }

  @override
  String get commonCopied => 'Kopiert.';

  @override
  String get settingsSearchSection => 'Suche';

  @override
  String searchRegionHint(String region) {
    return 'Woher Nachrichten-Briefings und Suchergebnisse kommen. Automatisch folgt der App-Sprache und der Ländereinstellung des Telefons (derzeit $region).';
  }

  @override
  String get searchRegionAutomatic => 'Automatisch';

  @override
  String get researchLoopHint =>
      'Fragen, die gesucht würden, recherchiert das Modell selbst: Es sucht, wählt zu lesende Seiten, sucht bei Bedarf erneut und antwortet dann mit Quellen. Eingefügte Links werden weiterhin direkt gelesen. Langsamer pro Frage; vergleiche mit deinen eigenen Fragen.';

  @override
  String get researchLoopNeedsTools =>
      'Benötigt eingeschaltete Werkzeugaufrufe mit den Web-Werkzeugen (Einstellungen > Werkzeuge).';

  @override
  String get selectionTitle => 'Was soll ich mit dem markierten Text machen?';

  @override
  String get selectionExplain => 'Erklären';

  @override
  String get selectionSummarize => 'Zusammenfassen';

  @override
  String get selectionTranslate => 'Übersetzen';

  @override
  String get selectionFix => 'Rechtschreibung und Grammatik korrigieren';

  @override
  String get selectionAsk => 'Dazu fragen';

  @override
  String get quickDescribe => 'Beschreiben';

  @override
  String get quickDescribePrompt => 'Beschreibe dieses Foto ausführlich.';

  @override
  String get quickExtractText => 'Text auslesen';

  @override
  String get quickExtractTextPrompt =>
      'Gib den gesamten Text in diesem Bild genau so wieder, wie er geschrieben ist, und behalte das Layout bei.';

  @override
  String get quickTranslate => 'Übersetzen';

  @override
  String get quickTranslatePrompt =>
      'Übersetze den gesamten Text in diesem Bild ins Deutsche.';

  @override
  String get quickSolve => 'Lösen';

  @override
  String get quickSolvePrompt =>
      'Löse die Aufgabe in diesem Bild und erkläre jeden Schritt.';

  @override
  String get quickExplain => 'Erklären';

  @override
  String get quickExplainPrompt =>
      'Erkläre, was dieses Bild zeigt und warum es wichtig ist.';

  @override
  String get quickIdentify => 'Erkennen';

  @override
  String get quickIdentifyPrompt =>
      'Was ist das? Bestimme es und erzähl mir, was du darüber weißt.';

  @override
  String get quickSummarise => 'Zusammenfassen';

  @override
  String get quickSummarisePrompt =>
      'Fasse dieses Dokument zusammen: zuerst die Kernaussage in einem Satz, dann die wichtigsten Punkte.';

  @override
  String get quickKeyPoints => 'Kernpunkte';

  @override
  String get quickKeyPointsPrompt =>
      'Liste die Kernpunkte dieses Dokuments als kurze Stichpunkte auf.';

  @override
  String get quickExplainSimply => 'Einfach erklären';

  @override
  String get quickExplainSimplyPrompt =>
      'Erkläre dieses Dokument in einfacher Sprache für jemanden, der neu im Thema ist.';

  @override
  String get quickActionItems => 'Aufgaben';

  @override
  String get quickActionItemsPrompt =>
      'Liste alle Aufgaben, Fristen und Entscheidungen in diesem Dokument auf.';

  @override
  String get quickQuestions => 'Fragen';

  @override
  String get quickQuestionsPrompt =>
      'Welche Fragen sollte ich zu diesem Dokument stellen, bevor ich mich darauf verlasse?';

  @override
  String get sectionVoice => 'Stimme';

  @override
  String get sectionAutomation => 'Kürzel & Automatisierung';

  @override
  String get sectionModelConnections => 'Modell & Verbindungen';

  @override
  String get sectionAppearanceLanguage => 'Darstellung & Sprache';

  @override
  String get sectionData => 'Deine Daten';

  @override
  String get advancedNote =>
      'Die Standardwerte funktionieren gut. Diese hier dienen der Feinabstimmung von Tempo, Speicherverbrauch und Ausgabe.';

  @override
  String get remoteRowOff => 'Aus · das Modell läuft auf diesem Telefon';

  @override
  String get backupRowHint =>
      'Chats, Anhänge und Einstellungen sichern oder wiederherstellen';

  @override
  String remoteRowOn(String name) {
    return 'An · $name';
  }

  @override
  String get sectionCachePrecision => 'Cache-Genauigkeit';

  @override
  String get sectionCapabilities => 'Fähigkeiten';

  @override
  String get sectionConnections => 'Verbindungen';

  @override
  String get sectionEvidence => 'An das Modell übergebene Quellen';

  @override
  String get sectionExtraSamplers => 'Zusätzliche Sampler';

  @override
  String get sectionLayers => 'Schichten, niedrigste zuerst';

  @override
  String get sectionPenalties => 'Strafen';

  @override
  String get sectionRope => 'Positionskodierung (RoPE / YaRN)';

  @override
  String get sectionReasoning => 'Denken';

  @override
  String get sectionReproducibility => 'Reproduzierbarkeit';

  @override
  String get sectionSamplerOrder => 'Sampler-Reihenfolge';

  @override
  String get sectionSpeculative => 'Spekulatives Decoding (experimentell)';

  @override
  String get sectionTools => 'Werkzeuge';

  @override
  String get chatSettingsMenu => 'Einstellungen dieses Chats';

  @override
  String chatSettingsMenuCount(int count) {
    return 'Einstellungen dieses Chats · $count';
  }

  @override
  String remoteUsingSummary(String name, String host) {
    return 'Chats laufen auf $name ($host). Lokale Modelle werden nicht geladen.';
  }

  @override
  String get remoteNeedsConnection =>
      'Füge unten eine Verbindung hinzu, um dies einzuschalten.';

  @override
  String get remoteNeedsUrl =>
      'Die gewählte Verbindung braucht eine gültige http(s)-Adresse.';

  @override
  String get remoteNoUrl => 'keine Adresse';

  @override
  String get remoteNoKey => 'kein Schlüssel';

  @override
  String get remoteScanShort => 'QR scannen';

  @override
  String get remotePasteShort => 'Einfügen';

  @override
  String get modelProfile => 'Profil';

  @override
  String modelProfileCount(int count) {
    return 'Profil · $count';
  }

  @override
  String get modelsFootnote =>
      'Größere Modelle geben bessere Antworten, sind aber langsamer und brauchen mehr Speicher. Das Abzeichen an jedem Modell zeigt, ob es auf dieses Telefon passt.';

  @override
  String get benchmarkRunAgain => 'Erneut ausführen';

  @override
  String benchmarkMeasuredAt(String date) {
    return 'Gemessen am $date';
  }

  @override
  String get unloadShort => 'Entladen';

  @override
  String get unsavedChanges => 'Ungespeicherte Änderungen';

  @override
  String get savedNotice => 'Gespeichert';

  @override
  String get pickerLibrary => 'Bibliothek';

  @override
  String get pickerConnections => 'Verbindungen';

  @override
  String get pickerReasoning => 'denkt';

  @override
  String get pickerTightRam => 'knapp beim RAM';

  @override
  String get pickerTooLarge => 'zu groß für dieses Telefon';

  @override
  String get pickerNoKey => 'noch kein Schlüssel';

  @override
  String get goalPhaseVerifying =>
      'Bericht wird mit den Ergebnissen abgeglichen';

  @override
  String get goalGuardrails => 'Leitplanken';

  @override
  String get goalSubjectTitle => 'Bei diesen Namen bleiben';

  @override
  String get goalSubjectHint =>
      'In deinem Ziel gefunden. Das Modell muss sie exakt verwenden; Seiten über ähnliche Modelle, Versionen oder Generationen werden ausgelassen.';

  @override
  String get goalSubjectNone =>
      'Noch keine Namen gefunden: Produkte, Personen und Orte aus deinem Ziel erscheinen hier, während du tippst.';

  @override
  String get goalSubjectAdd => 'Namen hinzufügen';

  @override
  String get goalSubjectExample => 'z. B. Sony ZV-E10';

  @override
  String get goalSubjectReset => 'Zurücksetzen';

  @override
  String get goalRulesLabel => 'Deine Regeln (optional)';

  @override
  String get goalRulesHint =>
      'Eine pro Zeile, z. B. Preise in EUR · Nur Quellen von 2026 · Keine Gerüchte';

  @override
  String get goalRulesBuiltIn => 'Regeln, die jedes Ziel befolgt';

  @override
  String get goalRuleSubject =>
      'Verwendet deine Namen exakt; ersetzt sie nie durch ein ähnliches Modell, eine ähnliche Version oder Generation.';

  @override
  String get goalRuleEvidence =>
      'Nennt nur Fakten aus den Quellen, jeweils mit Quellenangabe; nichts aus dem Gedächtnis.';

  @override
  String get goalRuleOffTopic =>
      'Ignoriert Quellen zu anderen Themen und sagt, was fehlt; fragt dich nie nach Quellen.';

  @override
  String get goalRuleFigures =>
      'Übernimmt Zahlen, Daten und Preise exakt; nennt beide Seiten, wenn Quellen sich widersprechen.';

  @override
  String get goalRuleThinking =>
      'Denkt kurz vor dem Plan und der Belegprüfung nach; Schritte und Bericht antworten direkt, damit ein Durchlauf schneller geht.';

  @override
  String get goalRuleCheck =>
      'Jeder Schritt und der Bericht werden automatisch geprüft; eine fehlgeschlagene Prüfung wird einmal wiederholt.';

  @override
  String goalCheckDrift(String names) {
    return 'Erwähnt $names, nicht das Thema des Ziels';
  }

  @override
  String goalCheckOffTarget(String names) {
    return 'Stattdessen $names recherchiert: aus dem Bericht ausgelassen';
  }

  @override
  String get goalCheckNoSources => 'Keine Quellen gefunden';

  @override
  String get goalCheckNoCitations => 'Zitiert keine Quellen';

  @override
  String goalCheckBadCitations(String numbers) {
    return 'Zitiert nicht existierende Quellen: $numbers';
  }

  @override
  String goalCheckFigures(String figures) {
    return 'Zahlen, die in keiner Quelle stehen: $figures';
  }

  @override
  String goalCheckDroppedFigures(String figures) {
    return 'Zahlen ohne Quelle weggelassen: $figures';
  }

  @override
  String get goalCheckAskedUser => 'Hat dich nach Informationen gefragt';

  @override
  String get goalCheckRetried =>
      'Nach fehlgeschlagener Prüfung erneut recherchiert';

  @override
  String get goalCheckRevised =>
      'Einmal umgeschrieben, um die Prüfung zu bestehen';

  @override
  String get goalReportChecked =>
      'Geprüft: Namen, Quellenangaben und Zahlen stimmen mit den Ergebnissen überein';

  @override
  String get goalStepSearched => 'Gesucht';

  @override
  String get goalStepTools => 'Werkzeugaufrufe';

  @override
  String get goalStepSources => 'Quellen';

  @override
  String get goalStepReasoning => 'Denkprozess';

  @override
  String goalStepStats(int prompt, int tokens, String seconds, String tps) {
    return '$prompt Prompt- + $tokens erzeugte Tokens · $seconds s · $tps Tok/s';
  }

  @override
  String goalStepSearchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Suchen',
      one: '1 Suche',
    );
    return '$_temp0';
  }

  @override
  String goalStepToolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Werkzeugaufrufe',
      one: '1 Werkzeugaufruf',
    );
    return '$_temp0';
  }

  @override
  String get goalPlanNotes => 'So entstand der Plan';

  @override
  String get goalReviewNotes => 'Überlegungen der Prüfung';

  @override
  String get goalCheckLeak =>
      'In die Antwort geratener Denkprozess wurde entfernt';

  @override
  String goalSmallModel(String model) {
    return '$model ist ein kleines Modell: Ziele werden mit Gemma 4 E2B oder einem größeren Modell deutlich genauer (es bleibt beim Thema und zitiert seine Quellen).';
  }

  @override
  String get goalPartial => 'Teilergebnis – weitere Belege nötig';

  @override
  String get goalCriteriaReview => 'Erfolgskriterien';

  @override
  String goalEvidenceSteps(String steps) {
    return 'Belege: Schritte $steps';
  }

  @override
  String get backupExportReady =>
      'Verschlüsseltes Backup an das Exportmenü übergeben.';

  @override
  String get remoteShareMemory => 'Erinnerung mit dieser Verbindung teilen';

  @override
  String get remoteShareMemoryHint =>
      'Erlaubt, ausgewählte Notizen in Anfragen an diesen Server mitzusenden.';

  @override
  String get remoteLearnMemory => 'Erinnerung über diese Verbindung lernen';

  @override
  String get remoteLearnMemoryHint =>
      'Erlaubt eine separate Serveranfrage, um dauerhafte Fakten aus deinen Nachrichten zu extrahieren. Einfache, eindeutige Fakten können weiterhin lokal gespeichert werden, wenn die Erinnerung an ist.';

  @override
  String get memoryPin => 'Diese Notiz immer berücksichtigen';

  @override
  String get memoryUnpin => 'Notiz lösen';

  @override
  String get memoryReconfirm => 'Bestätigen, dass das noch stimmt';

  @override
  String get memoryExpire => 'In 30 Tagen ablaufen lassen';

  @override
  String get memoryNoExpiry => 'Ablauf entfernen';

  @override
  String memoryExpires(String date) {
    return 'Läuft ab am $date';
  }

  @override
  String get settingsSearch => 'Einstellungen durchsuchen';

  @override
  String get settingsFaster => 'Schnellere Antworten';

  @override
  String get settingsDetailed => 'Mehr Details';

  @override
  String get settingsLessMemory => 'Weniger RAM nutzen';

  @override
  String get imageTokenBudget => 'Token-Budget für Fotos';

  @override
  String get imageTokenBudgetHint =>
      'Mehr Details brauchen mehr Speicher und Zeit. Lädt das Modell neu.';

  @override
  String get documentPreview => 'Vorschau';

  @override
  String get documentEdit => 'Bearbeiten';

  @override
  String get documentDraftSaved => 'Entwurf auf diesem Gerät gespeichert';

  @override
  String get documentVersions => 'Versionsverlauf';

  @override
  String get goalQuestionsTitle => 'Zuerst ein paar Fragen';

  @override
  String get goalQuestionsHint =>
      'Deine Vorlieben können den Bericht nützlicher machen. Wähle eine Antwort, schreib deine eigene oder überspringe. Die Recherche wartet, bis du weitermachst.';

  @override
  String get goalYourAnswer => 'Deine Antwort (optional)';

  @override
  String get goalQuestionsLater => 'Später';

  @override
  String get goalQuestionsSkip => 'Überspringen und weiter';

  @override
  String get goalPhaseClarifying => 'Prüfe, ob Rückfragen helfen würden …';

  @override
  String get goalWaitingAnswers => 'Wartet auf deine Antworten';

  @override
  String get goalAnswerQuestions => 'Fragen beantworten';

  @override
  String get goalClarificationAnswers => 'Deine Antworten auf Rückfragen';

  @override
  String get goalAssumptionsAllowed =>
      'Übersprungen – der Bericht nennt seine Annahmen.';

  @override
  String get goalSearchGuidance => 'Richtung für Suche und Bericht';

  @override
  String get goalSearchGuidanceHint =>
      'Erkläre, was der Bericht verpasst hat, welche Fragen gesucht werden sollen und was betont werden soll.';

  @override
  String get goalRefineRun => 'Speichern und recherchieren';

  @override
  String get goalCriteriaSeparate =>
      'Eine Anforderung pro Zeile, damit die Abdeckung messbar ist.';

  @override
  String goalCoverage(Object percent, Object target) {
    return 'Belegte Anforderungen: $percent % · Ziel $target %';
  }

  @override
  String get goalCompletionHint =>
      'Stoppt, wenn dieser Anteil der Anforderungen belegt ist. Verbleibende Lücken bleiben sichtbar; Quellenangaben und Faktenprüfungen gelten weiterhin.';

  @override
  String get goalCompletionTarget => 'Abschlussziel';

  @override
  String get goalRefine => 'Ziel bearbeiten / Recherche lenken';

  @override
  String memoryScanResult(Object count) {
    return '$count Erinnerungen aus gespeicherten Chats wiederhergestellt.';
  }

  @override
  String get memoryScanHistory =>
      'Gespeicherte Chats nach verpassten Erinnerungen durchsuchen';

  @override
  String get goalEvidenceWorkspace => 'Belege vergleichen';

  @override
  String get goalEvidenceSnapshotHint =>
      'Vergleiche die gespeicherten Quellauszüge mit den Ergebnissen der Schritte. Das sind die Auszüge, die das Modell genutzt hat; eine heute geöffnete Seite kann sich geändert haben. Eine Quelle oder eine bestandene automatische Prüfung beweist für sich allein noch keine Aussage.';

  @override
  String get goalEvidenceSupported => 'Anforderung belegt';

  @override
  String get goalEvidenceGap => 'Anforderung braucht Belege';

  @override
  String get goalEvidenceMissing =>
      'Für diese Quelle wurde kein abgerufener Auszug gespeichert.';

  @override
  String get goalEvidenceFind => 'Text in diesen Quellen finden';

  @override
  String get goalEvidencePublished => 'Veröffentlicht';

  @override
  String get goalEvidenceRetrieved => 'Abgerufen';

  @override
  String get goalEvidenceOpen => 'Seite öffnen';

  @override
  String get goalEvidenceCopy => 'Auszug kopieren';

  @override
  String get goalEvidenceNoMatch =>
      'Kein Treffer in diesem gespeicherten Auszug.';

  @override
  String get goalEvidenceExcluded =>
      'Dieser Schritt wurde von den Belegen des Berichts ausgeschlossen.';

  @override
  String get contextInspector => 'Kontext-Inspektor';

  @override
  String get contextSnapshotHint =>
      'Gespeicherte Kontextauswahl für diese Antwort. Die Auszüge helfen dir beim Prüfen; sie werden in künftigen Antworten nicht automatisch als Zusammenfassung verwendet.';

  @override
  String get contextSnapshotMissing =>
      'Für diese ältere Antwort ist kein Kontext-Schnappschuss gespeichert.';

  @override
  String get contextTokens => 'Kontext-Tokens';

  @override
  String get contextIsolated =>
      'Diese Anfrage nutzte die aktuelle Frage ohne frühere Chat-Runden.';

  @override
  String get contextInstructions => 'Dem Modell gegebene Anweisungen';

  @override
  String get contextCharacters => 'Zeichen';

  @override
  String get contextMessages => 'Nachrichten der Unterhaltung';

  @override
  String get contextIncluded => 'Einbezogen';

  @override
  String get contextOmittedIsolated =>
      'Für diese unabhängige Anfrage ausgelassen';

  @override
  String get contextOmittedLimit =>
      'Ausgelassen, um ins Kontextlimit zu passen; im Verlauf erhalten';

  @override
  String get contextImages => 'Bilder';

  @override
  String get contextDocuments => 'Dokumente';

  @override
  String get contextSnippetOnly =>
      'Nur Such-Snippet; Seite wurde nicht gelesen';

  @override
  String get contextStale =>
      'Zwischengespeicherte Belege sind eventuell veraltet';

  @override
  String get goalModelLabel => 'Modell';

  @override
  String get goalModelNone => 'Kein lokales Modell bereit';

  @override
  String get goalModelOnStart => 'wird beim Start des Ziels geladen';

  @override
  String get contextOmitted => 'Ausgelassen';

  @override
  String get contextEarlierHidden =>
      'Vorschau früherer Nachrichten nicht angezeigt';

  @override
  String contextCapTrain(String size) {
    return 'Kontext auf $size Tokens gesetzt, das Maximum, für das dieses Modell trainiert wurde.';
  }

  @override
  String contextCapMemory(String size) {
    return 'Kontext auf $size Tokens gesetzt, damit das Modell in den freien Speicher passt.';
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

    return 'Nicht genug freier Speicher für dieses Modell: Es braucht etwa $needString MB und $freeString MB sind frei. Schließe andere Apps oder wähle ein kleineres Modell.';
  }

  @override
  String contextTrainedFor(String size) {
    return 'Das geladene Modell wurde für $size Tokens trainiert.';
  }

  @override
  String contextTrainedForCapped(String size) {
    return 'Das geladene Modell wurde für $size Tokens trainiert. Ein größerer Kontext wird beim Laden darauf gekürzt, sofern unter „Speicher, RoPE & Spekulation“ keine RoPE-Skalierung eingestellt ist.';
  }

  @override
  String contextTrainedForStretched(String size) {
    return 'Das geladene Modell wurde für $size Tokens trainiert; die RoPE-Skalierung dehnt es darüber hinaus, wobei die Qualität sinken kann.';
  }

  @override
  String get photosAndVoiceNotes => 'Fotos und Sprachnotizen';

  @override
  String photosAndVoiceNotesBody(Object mb) {
    return 'Finde Fotos nach dem, was sie zeigen, und Aufnahmen nach dem, was gesagt wird – mit denselben Fragen wie bei deinen Dokumenten. Läuft auf dem Telefon; einmalig ~$mb MB.';
  }

  @override
  String get photosAndVoiceNotesReady =>
      'Fotos und Aufnahmen werden nach dem zugeordnet, was sie zeigen oder sagen.';

  @override
  String noticeClaimsNotInSources(String claims, String more) {
    return 'Nicht durch die Quellen gedeckt: $claims$more. Prüfe diese Aussagen, bevor du dich darauf verlässt.';
  }

  @override
  String noticeClaimsNames(String details) {
    return 'Namen oder Daten, die keine Quelle erwähnt: $details';
  }

  @override
  String get naturalVoiceTitle => 'Natürliche Stimme auf dem Gerät';

  @override
  String get naturalVoiceHint =>
      'Whisper hört zu und Piper spricht (Stimme „Thorsten“), komplett auf diesem Telefon. Ohne Download wird die Systemstimme verwendet.';

  @override
  String get talkOverTitle => 'In die Antwort hineinsprechen';

  @override
  String get talkOverHint =>
      'Unterbrich in einer Unterhaltung, indem du sprichst. Die Antwort klingt dann wie ein Telefonat. Aus: klarer Klang, zum Unterbrechen tippen.';

  @override
  String get spokenLengthTitle => 'Länge gesprochener Antworten';

  @override
  String get spokenLengthHint =>
      'Wie viel einer Antwort in der Unterhaltung laut gesprochen wird. Listen werden immer vollständig vorgelesen.';

  @override
  String get spokenLengthShort => 'Kurz (3 Sätze)';

  @override
  String get spokenLengthLonger => 'Länger (6 Sätze)';

  @override
  String get spokenLengthFull => 'Ganze Antwort';

  @override
  String get voiceListeningPack => 'Zuhören (Whisper)';

  @override
  String get voiceSpeakingPack => 'Sprechen (Piper)';

  @override
  String get listeningModelTitle => 'Modell zum Zuhören';

  @override
  String get listeningModelHint =>
      'Parakeet v3 hat auf dem Telefon jeden Testsatz verstanden und antwortet schneller als Whisper; außerdem versteht es Deutsch, Französisch und Spanisch besser. Es ist ein separater Download und braucht mehr Speicher, während du sprichst. Parakeet TDT 0.6B v3 von NVIDIA, CC BY 4.0.';

  @override
  String get listeningWhisper => 'Whisper base';

  @override
  String get listeningParakeet => 'Parakeet v3';

  @override
  String get voiceUnpacking => 'Wird entpackt …';

  @override
  String get voicePick => 'Stimme';

  @override
  String get voiceTry => 'Anhören';

  @override
  String get voiceSample =>
      'Hallo! So klinge ich, wenn ich deine Antworten vorlese.';

  @override
  String get voiceDownloadBoth => 'Stimme für das Gerät herunterladen';

  @override
  String get conversationTitle => 'Unterhaltung';

  @override
  String get convListening => 'Hört zu …';

  @override
  String get convThinking => 'Denkt nach …';

  @override
  String get convLookingUp => 'Schlägt nach …';

  @override
  String get convSpeaking => 'Spricht · zum Unterbrechen sprechen';

  @override
  String get convSpeakingTap => 'Spricht · zum Unterbrechen tippen';

  @override
  String get convPaused => 'Mikrofon aus';

  @override
  String get convNeedsVoice =>
      'Für eine natürliche Unterhaltung ohne Hände lade die Stimme für das Gerät herunter (etwa 230 MB). Bis dahin wird die Systemstimme verwendet.';

  @override
  String convModelMissing(String model) {
    return '$model ist nicht heruntergeladen, daher antwortet ein anderes heruntergeladenes Modell. Lade es unter „Modelle“ herunter oder wähle über den Button oben rechts ein Modell.';
  }

  @override
  String get convNoModel => 'Lade zuerst ein Modell.';

  @override
  String get convModelTitle => 'Modell für Unterhaltungen';

  @override
  String get convModelHint =>
      'Die Unterhaltung antwortet mit Qwen3.5 0.8B auf dem Telefon: Es beginnt nach wenigen Sekunden zu sprechen. Bei aktiver Remote-Verbindung kann stattdessen deren Modell antworten.';

  @override
  String get convModelRemote =>
      'Sucht bei Bedarf selbst und merkt sich die ganze Unterhaltung';

  @override
  String convRemoteFailed(String error) {
    return 'Die Remote-Verbindung hat nicht geantwortet ($error). Antwort kommt vom Telefon.';
  }

  @override
  String get convModelFastest => 'am schnellsten';

  @override
  String get convMicDenied =>
      'Das Mikrofon ist nicht erlaubt. Erlaube es in den Telefoneinstellungen, um zu sprechen.';

  @override
  String get convEnd => 'Unterhaltung beenden';

  @override
  String get convStopAnswer => 'Antwort stoppen';

  @override
  String get convMute => 'Mikrofon stummschalten';

  @override
  String get convUnmute => 'Mikrofon einschalten';

  @override
  String convLoadingModel(String model) {
    return '$model wird geladen …';
  }

  @override
  String get convHint =>
      'Sprich einfach. Ich antworte laut; sprich dazwischen, um mich zu unterbrechen.';

  @override
  String get convInterrupt => 'Unterbrechen';

  @override
  String get actionEvent => 'Zum Kalender hinzufügen';

  @override
  String get actionReminder => 'Erinnerung hinzufügen';

  @override
  String get actionAlarm => 'Wecker stellen';

  @override
  String get actionTimer => 'Timer starten';

  @override
  String get actionMessage => 'Entwurf öffnen';

  @override
  String get actionFile => 'Speichern oder teilen';

  @override
  String get actionNoApp => 'Keine App auf diesem Telefon kann das.';

  @override
  String get actionConfirmHint =>
      'Für dich vorbereitet: Du bestätigst in der App, die sich öffnet.';

  @override
  String get actionConfirmDone => 'Ich habe diese Aktion erledigt';

  @override
  String actionConfirmedAt(String time) {
    return 'Bestätigt um $time';
  }

  @override
  String get goalAwaitingActions => 'Wartet auf deine Bestätigung der Aktion';

  @override
  String get actionReadyAnswer =>
      'Fertig. Prüfe die Karte unten und tippe auf ihren Button, um abzuschließen.';

  @override
  String get echoedAnswer =>
      'Das Modell hat seine Anweisungen kopiert, statt zu antworten, daher wird keine Antwort angezeigt. Öffne die Quellen unten oder frag noch einmal mit anderen Worten.';

  @override
  String get goalActionsTitle => 'Bereit zur Ausführung';

  @override
  String get goalSaveReport => 'Bericht als Datei speichern';

  @override
  String get goalWatch => 'Täglich beobachten';

  @override
  String goalWatchSet(String time) {
    return 'Wird täglich um $time beobachtet. Eine Hintergrundsuche prüft auf Änderungen und benachrichtigt dich, wenn ein neues Ergebnis erscheint oder sich eine Zahl ändert. Das ganze Ziel läuft nur dann erneut, wenn du es möchtest.';
  }

  @override
  String get goalPreparingActions => 'Aktionen werden vorbereitet …';

  @override
  String get goalPhaseDelivering => 'Bereite vor, was das Ziel verlangt hat';

  @override
  String goalNotPrepared(String item, String reason) {
    return 'Nicht vorbereitet: $item ($reason)';
  }

  @override
  String goalDeliverableFile(String format) {
    return 'die $format-Datei';
  }

  @override
  String get goalDeliverableEvent => 'der Kalendertermin';

  @override
  String get goalDeliverableReminder => 'die Erinnerung';

  @override
  String get goalDeliverableAlarm => 'der Wecker';

  @override
  String get goalDeliverableTimer => 'der Timer';

  @override
  String get goalDeliverableMessage => 'der Nachrichtenentwurf';

  @override
  String get goalNotPreparedStopped => 'das Ziel wurde gestoppt';

  @override
  String get goalNotPreparedBudget => 'das Budget des Ziels war aufgebraucht';

  @override
  String get goalNotPreparedUnreadable =>
      'die Antwort des Modells konnte nicht gelesen werden';

  @override
  String get goalNotPreparedTooLong => 'der Bericht ist zu lang für eine Datei';

  @override
  String get goalNotPreparedNone => 'das Modell hat nichts vorgeschlagen';

  @override
  String goalNotPreparedInvalid(String problem) {
    return 'der Vorschlag des Modells war unvollständig: $problem';
  }

  @override
  String get goalWatchesTitle => 'Beobachtete Ziele';

  @override
  String get goalWatchChecking => 'Wird geprüft …';

  @override
  String get goalWatchWebOff => 'Websuche ist aus';

  @override
  String get goalWatchNoResults => 'Die Suche hat nichts gefunden';

  @override
  String get goalWatchOffline => 'Suche nicht möglich (offline?)';

  @override
  String get goalWatchNotYet => 'Noch nicht geprüft';

  @override
  String goalWatchBaseline(String when) {
    return 'Erste Ergebnisse gespeichert $when';
  }

  @override
  String goalWatchNoChange(String when) {
    return 'Keine Änderung · $when';
  }

  @override
  String goalWatchChanged(int fresh, int figures, String when) {
    return '$fresh neu, $figures geänderte Zahlen · $when';
  }

  @override
  String goalWatchDailyAt(String time) {
    return 'täglich um $time';
  }

  @override
  String goalWatchNewResult(String title) {
    return 'Neu: $title';
  }

  @override
  String get goalWatchCheckNow => 'Jetzt prüfen';

  @override
  String get goalWatchRunAgain => 'Ziel erneut ausführen';

  @override
  String get goalWatchStop => 'Nicht mehr beobachten';

  @override
  String actionOpenedAt(String time) {
    return 'Geöffnet um $time: bestätige es dort';
  }

  @override
  String get remoteServerSettings =>
      'Eigene Einstellungen des Servers verwenden';

  @override
  String get remoteServerSettingsHint =>
      'Temperatur, Sampling, Antwortlänge und Kontext kommen vom Modell dieser Verbindung (die Standardwerte von Gemini, die Einstellungen, mit denen LM Studio es geladen hat …), nicht von den Vorlagen des Telefons.';

  @override
  String get sheetAttachments => 'Anhänge und Werkzeuge';

  @override
  String get sheetNotice => 'Hinweis';
}
