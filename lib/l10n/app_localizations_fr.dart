// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get settingScopeHint =>
      'Effacez une valeur pour utiliser celle du niveau précédent. Les réglages marqués ↻ prennent effet au chargement du modèle.';

  @override
  String get settingExplicit => 'Personnalisé';

  @override
  String get settingInherited => 'Hérité';

  @override
  String get settingOnePerLine => 'Une valeur par ligne';

  @override
  String get nearbyHosts => 'Trouver les hôtes à proximité';

  @override
  String get nearbyHostsHint =>
      'Trouvez les hôtes OnDevice LLM sur le même réseau. Sélectionnez-en un, puis saisissez sa clé d’accès ou utilisez son code QR.';

  @override
  String get nearbyHostsNone =>
      'Aucun hôte trouvé. Activez l’hébergement sur l’autre appareil et vérifiez que les deux utilisent le même réseau. Le jumelage manuel reste disponible.';

  @override
  String get scanConfidence => 'Confiance du moteur';

  @override
  String get scanSettings => 'Reconnaissance de texte';

  @override
  String get scanPageLimit => 'Pages numérisées par PDF';

  @override
  String get scanLongHint =>
      'Le texte intégré est lu au-delà de cette limite. Les longues analyses affichent la progression et peuvent être arrêtées.';

  @override
  String get scanLanguage => 'Langue de reconnaissance';

  @override
  String get scanLatinHint =>
      'Android reconnaît automatiquement l’anglais, le français, l’espagnol et les autres textes en alphabet latin sur cet appareil.';

  @override
  String get scanQualityHint =>
      'La confiance du moteur peut être trompeuse. Vérifiez le texte important dans l’original.';

  @override
  String get modelSettingsAll => 'Tous les réglages du modèle';

  @override
  String get modelSettingsGlobal => 'Vos réglages du modèle';

  @override
  String get modelSettingsAllHint =>
      'Modifier ou réinitialiser les réglages des profils, préréglages et conversations';

  @override
  String get removeProjectHint =>
      'Supprimer ce projet et ses instructions ? Ses conversations et fichiers seront conservés.';

  @override
  String get downloadQueued => 'En attente d’un créneau de téléchargement';

  @override
  String get sourceMessage => 'Message source';

  @override
  String get sourceMessageMissing => 'Ce message source n’est plus disponible.';

  @override
  String get openConversation => 'Ouvrir la conversation';

  @override
  String get contextSummary => 'Vérifier le résumé du contexte';

  @override
  String get contextSummaryHint =>
      'Rédigez un résumé de ces anciens messages. Vérifiez-le avant de l’enregistrer ; les réponses suivantes pourront remplacer cette partie de la conversation par ce résumé.';

  @override
  String get contextSummaryTooShort =>
      'Il faut davantage d’historique pour créer un résumé.';

  @override
  String get memoryUsed => 'Mémoire utilisée';

  @override
  String get unverifiedFeatures => 'Caractéristiques à vérifier';

  @override
  String get restoreVersion => 'Utiliser cette version';

  @override
  String get originalFile => 'Partager le fichier original';

  @override
  String get previousVersion => 'Version précédente';

  @override
  String get workspaceTitle => 'Projets et discussions';

  @override
  String get project => 'Projet';

  @override
  String get projectName => 'Nom du projet';

  @override
  String get projectInstructions => 'Instructions pour ce projet';

  @override
  String get noProject => 'Aucun projet';

  @override
  String get archivedChats => 'Archives';

  @override
  String get trashChats => 'Corbeille';

  @override
  String get archiveChats => 'Archiver';

  @override
  String get restoreChats => 'Restaurer';

  @override
  String get moveToTrash => 'Mettre à la corbeille';

  @override
  String get permanentDeleteHint =>
      'Supprimer définitivement ces discussions et pièces jointes de cet appareil. Cette action est irréversible.';

  @override
  String get selectAllChats => 'Tout sélectionner';

  @override
  String get temporaryChat => 'Discussion temporaire';

  @override
  String get temporaryChatHint =>
      'Cette discussion et son brouillon restent en mémoire. La mémoire personnelle est désactivée. Quitter les efface ; les requêtes distantes et web utilisent toujours la connexion choisie.';

  @override
  String get deleteAnswer => 'Supprimer la réponse';

  @override
  String get deleteQuestionAnswer => 'Supprimer la question et la réponse';

  @override
  String get messageDeleted => 'Message supprimé';

  @override
  String get undo => 'Annuler';

  @override
  String get undoUnavailable =>
      'Impossible d’annuler pendant une autre opération.';

  @override
  String get appTitle => 'OnDevice';

  @override
  String get noModelLoaded => 'aucun modèle chargé';

  @override
  String get newChat => 'Nouvelle discussion';

  @override
  String get drawerTemporary => 'Temporaire';

  @override
  String get drawerWorkspace => 'Espace de travail';

  @override
  String get drawerProjects => 'Projets et discussions';

  @override
  String get drawerProjectsHint => 'Projets, archives et corbeille';

  @override
  String drawerProjectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projets',
      one: '1 projet',
      zero: 'Regroupez des discussions avec des instructions communes',
    );
    return '$_temp0';
  }

  @override
  String get previous7Days => '7 derniers jours';

  @override
  String get previous30Days => '30 derniers jours';

  @override
  String get olderChats => 'Plus anciennes';

  @override
  String get chatOptions => 'Options de la discussion';

  @override
  String get shareOrExport => 'Partager ou exporter';

  @override
  String get thisChatSection => 'Cette discussion';

  @override
  String get conversations => 'Discussions';

  @override
  String get more => 'Plus';

  @override
  String get exportMarkdown => 'Exporter en Markdown';

  @override
  String get exportJson => 'Exporter en JSON';

  @override
  String get shareAsText => 'Partager en texte';

  @override
  String get createDocument => 'Créer un document';

  @override
  String get documentFormat => 'Format';

  @override
  String get answersOnly => 'Réponses de l’assistant uniquement';

  @override
  String get includeBranches => 'Inclure les anciennes branches';

  @override
  String get includeReasoning => 'Inclure le raisonnement du modèle';

  @override
  String get saveDocument => 'Enregistrer le document';

  @override
  String get models => 'Modèles';

  @override
  String get settings => 'Réglages';

  @override
  String get metrics => 'Mesures';

  @override
  String get loadingModel => 'Chargement du modèle en mémoire…';

  @override
  String get messageHint => 'Écrivez à votre modèle…';

  @override
  String get listening => 'À l\'écoute…';

  @override
  String get chooseModel => 'Choisir un modèle';

  @override
  String get think => 'Réfléchir';

  @override
  String get thinkOff => 'Désactivée';

  @override
  String get thinkLow => 'Faible';

  @override
  String get thinkMedium => 'Moyenne';

  @override
  String get thinkHigh => 'Élevée';

  @override
  String get thinkOffHint => 'Répond tout de suite. Le plus rapide.';

  @override
  String get thinkLowHint =>
      'Une courte réflexion d\'abord (environ 500 jetons).';

  @override
  String get thinkMediumHint =>
      'Réfléchit plus longtemps d\'abord (environ 2 000 jetons), pour les questions difficiles.';

  @override
  String get thinkHighHint =>
      'Réfléchit longuement d\'abord (environ 8 000 jetons). Le plus lent.';

  @override
  String thinkLevelToast(String level) {
    return 'Réflexion : $level';
  }

  @override
  String get thinkOffToast => 'Réflexion désactivée';

  @override
  String get attachTooltip =>
      'Joindre une photo ou un fichier, ou choisir les outils';

  @override
  String get dictate => 'Dicter';

  @override
  String get stopDictation => 'Arrêter la dictée';

  @override
  String get send => 'Envoyer';

  @override
  String get stop => 'Arrêter la génération';

  @override
  String get modelPill => 'Modèle';

  @override
  String get webLocal => 'Local';

  @override
  String get webAuto => 'auto';

  @override
  String get webAlways => 'toujours';

  @override
  String get emptyTitle =>
      'Un peu plus d\'intelligence.\nBeaucoup plus de confidentialité.';

  @override
  String get emptyHasModel =>
      'Votre modèle est là, il tourne entièrement sur cet appareil. Posez-lui vos questions.';

  @override
  String emptyRemote(String host) {
    return 'Les réponses viennent de votre serveur distant ($host) ; vos messages y sont envoyés. Posez-lui vos questions.';
  }

  @override
  String get emptyNoModel =>
      'Pas encore de modèle. Ouvrez Modèles pour télécharger un modèle de départ ou importer votre propre GGUF, puis revenez poser vos questions.';

  @override
  String get askPhoto => 'Question sur une photo';

  @override
  String get askFile => 'Question sur un fichier';

  @override
  String get generating => 'génération…';

  @override
  String get runDetails => 'Comment c’est produit';

  @override
  String get answerWarning => 'Ce que la vérification des sources met en doute';

  @override
  String get copyRunDetails => 'Copier les détails';

  @override
  String get runDetailsCopied => 'Détails copiés';

  @override
  String get runMeasured => 'Mesuré';

  @override
  String get runSettings => 'Réglages en vigueur';

  @override
  String get runEngine => 'MOTEUR';

  @override
  String get copyResponse => 'Copier la réponse';

  @override
  String get copyQuestion => 'Copier la question';

  @override
  String get responseCopied => 'Réponse copiée';

  @override
  String get readAloud => 'Lire à voix haute';

  @override
  String get stopReading => 'Arrêter la lecture';

  @override
  String get regenerate =>
      'Régénérer (cette réponse est conservée comme version antérieure)';

  @override
  String get continueAnswer => 'Poursuivre cette réponse';

  @override
  String get compareWith => 'Comparer avec un autre modèle';

  @override
  String get editQuestion => 'Modifier la question';

  @override
  String get askAgain => 'Redemander';

  @override
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get earlierQuestion => 'Question précédente';

  @override
  String get earlierAnswer => 'Réponse précédente';

  @override
  String get restoreBranch => 'Restaurer cette branche';

  @override
  String get stoppedPartial => 'Arrêté · réponse partielle';

  @override
  String get interruptedClosed =>
      'Interrompu · l\'application s\'est fermée avant la fin de la réponse';

  @override
  String get interruptedPartial => 'Interrompu · réponse partielle';

  @override
  String get interruptedError => 'Interrompu par une erreur';

  @override
  String get searchConversations => 'Rechercher dans les discussions';

  @override
  String get storedOnDevice => 'Conservé uniquement sur cet appareil';

  @override
  String get noConversations =>
      'Pas encore de discussion.\nVos échanges apparaîtront ici.';

  @override
  String nothingMatches(String query) {
    return 'Rien ne correspond à « $query ».';
  }

  @override
  String get pinned => 'Épinglées';

  @override
  String get today => 'Aujourd\'hui';

  @override
  String get yesterday => 'Hier';

  @override
  String get earlier => 'Plus tôt';

  @override
  String get language => 'Langue';

  @override
  String get languageSystem => 'Suivre le téléphone';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageSpanish => 'Español';

  @override
  String get resetToDefaults => 'Rétablir les valeurs par défaut';

  @override
  String get sectionAssistant => 'Assistant';

  @override
  String get thinkingMode => 'Mode réflexion';

  @override
  String get thinkingModeHint =>
      'Affiche le raisonnement généré par le modèle quand il est pris en charge. Il peut contenir des erreurs et ne prouve rien.';

  @override
  String get webResearch => 'Recherche web (sans clé)';

  @override
  String get webOffHint => 'Rien ne quitte le téléphone.';

  @override
  String get webAutoHint =>
      'La question est envoyée à DuckDuckGo et les pages de résultats sont lues quand le message en a besoin.';

  @override
  String get webAlwaysHint =>
      'Chaque message est d’abord recherché. Plus lent, toujours à jour.';

  @override
  String get knowledgeLibrary => 'Bibliothèque de connaissances';

  @override
  String get knowledgeOff =>
      'Désactivée · vos documents, cités dans les réponses quand elle est active';

  @override
  String knowledgeOn(Object collection) {
    return 'Activée · $collection';
  }

  @override
  String get memory => 'Mémoire';

  @override
  String get memoryOnHint =>
      'Activée · l’assistant retient des faits durables vous concernant';

  @override
  String get memoryOffHint =>
      'Désactivée · rien n’est retenu d’une conversation à l’autre';

  @override
  String get readAloudSetting => 'Lire les réponses à voix haute';

  @override
  String get readAloudHint =>
      'Chaque réponse terminée est lue par la voix de synthèse du téléphone. L’icône haut-parleur d’une réponse la lit à la demande dans tous les cas.';

  @override
  String get dictationOnDevice => 'La dictée reste sur le téléphone';

  @override
  String get dictationOnDeviceHint =>
      'N’utilise que la reconnaissance vocale de l’appareil (nécessite un pack de langue hors ligne dans les réglages vocaux du téléphone). Désactivé, la reconnaissance réseau est permise.';

  @override
  String get customInstructions => 'Instructions système personnalisées';

  @override
  String get customInstructionsHint =>
      'Ajoutez des préférences pour votre assistant';

  @override
  String get sectionModel => 'Modèle';

  @override
  String get remoteServer => 'Serveur distant';

  @override
  String get sectionAdvanced => 'Avancé';

  @override
  String get contextAndBatch => 'Contexte et lots';

  @override
  String get hardware => 'Matériel';

  @override
  String get sampling => 'Échantillonnage';

  @override
  String get reasoningAndSearch => 'Raisonnement et recherche';

  @override
  String get sectionAbout => 'À propos';

  @override
  String get openSourceMit => 'Open source · MIT';

  @override
  String get builtOnLlama => 'Basé sur llama.cpp';

  @override
  String get builtOnLlamaHint => 'Moteur d’inférence du projet ggml';

  @override
  String get openSourceLicences => 'Licences open source';

  @override
  String get openSourceLicencesHint =>
      'Paquets, modèles et voix, avec leurs licences';

  @override
  String get resetQuestion => 'Rétablir les valeurs par défaut ?';

  @override
  String get resetHint =>
      'Tous les réglages assistant, modèle et avancés reviennent aux valeurs par défaut de cet appareil. Vos conversations ne sont pas touchées.';

  @override
  String get reset => 'Rétablir';

  @override
  String get enableWebQuestion => 'Activer la recherche web ?';

  @override
  String get enableWebHint =>
      'La question est envoyée à DuckDuckGo et les pages de résultats sont lues directement depuis leurs sites (ils voient votre adresse IP). Aucun compte ni clé ; conversations, modèle et réglages restent en local.';

  @override
  String get enable => 'Activer';

  @override
  String get systemInstructions => 'Instructions système';

  @override
  String get systemInstructionsHint =>
      'p. ex. Réponds brièvement. Préfère les unités métriques.';

  @override
  String get couldNotOpenLink => 'Impossible d’ouvrir ce lien.';

  @override
  String get privateByDefault => 'Privé par défaut';

  @override
  String get privateByDefaultHint =>
      'Ni compte, ni analytique, ni inférence dans le nuage. Les téléchargements et la recherche optionnelle sont les seules fonctions réseau.';

  @override
  String get noModelLoadedTitle => 'Aucun modèle chargé';

  @override
  String get chooseFromLibrary => 'Choisissez-en un dans la bibliothèque';

  @override
  String get obPrivateHeadline => 'Privé par construction';

  @override
  String get obPrivateBody =>
      'Un modèle de langage qui tourne sur la puce de votre téléphone. Il n’y a aucun serveur de l’autre côté.';

  @override
  String get obNoAccount => 'Aucun compte';

  @override
  String get obNoAccountHint => 'Rien à créer, rien où se connecter.';

  @override
  String get obNoCloud => 'Aucun nuage';

  @override
  String get obNoCloudHint =>
      'Chaque réponse est calculée ici. Le mode avion fonctionne.';

  @override
  String get obStaysHere => 'Modèles et conversations restent sur ce téléphone';

  @override
  String get obStaysHereHint =>
      'Supprimez l’app et chaque octet part avec elle.';

  @override
  String get continueLabel => 'Continuer';

  @override
  String get obPickModel => 'Choisissez un premier modèle';

  @override
  String get phoneRamUnknown => 'Ce téléphone · RAM inconnue';

  @override
  String phoneRam(Object gb) {
    return 'Ce téléphone · $gb Go de RAM';
  }

  @override
  String get recommended => 'Recommandé';

  @override
  String get orChooseAnother => 'Ou choisissez-en un autre';

  @override
  String get acknowledgeLicense =>
      'J’accepte la licence du modèle de l’éditeur';

  @override
  String get download => 'Télécharger';

  @override
  String get later => 'Plus tard';

  @override
  String get obReady => 'Prêt.';

  @override
  String get startChatting => 'Commencer à discuter';

  @override
  String get downloadInterrupted => 'Téléchargement interrompu';

  @override
  String get downloadInterruptedHint =>
      'Vous pouvez réessayer maintenant, ou passer et télécharger plus tard depuis la bibliothèque. L’app fonctionne sans modèle, elle ne peut simplement pas encore répondre.';

  @override
  String get retry => 'Réessayer';

  @override
  String get skipForNow => 'Passer pour l’instant';

  @override
  String get verifyingSha => 'Vérification SHA-256…';

  @override
  String pausedOf(Object received, Object size) {
    return 'En pause · $received sur $size';
  }

  @override
  String get starting => 'Démarrage…';

  @override
  String get downloading => 'Téléchargement';

  @override
  String get downloadingHint =>
      'Gardez l’app ouverte. Vous pouvez mettre en pause et reprendre ; le fichier est vérifié avec le SHA-256 de l’éditeur à la fin.';

  @override
  String get resume => 'Reprendre';

  @override
  String get verifying => 'Vérification…';

  @override
  String get pause => 'Pause';

  @override
  String get skip => 'Passer';

  @override
  String get presets => 'Préréglages';

  @override
  String get newLabel => 'Nouveau';

  @override
  String get noExtraInstructions => 'Aucune instruction supplémentaire';

  @override
  String get edit => 'Modifier';

  @override
  String get duplicate => 'Dupliquer';

  @override
  String get delete => 'Supprimer';

  @override
  String get presetsHint =>
      'Un préréglage ajoute ses instructions aux vôtres et peut remplacer la température, la réflexion et le mode web. Les préréglages intégrés peuvent être dupliqués et modifiés.';

  @override
  String get newPreset => 'Nouveau préréglage';

  @override
  String get editPreset => 'Modifier le préréglage';

  @override
  String get name => 'Nom';

  @override
  String get instructions => 'Instructions';

  @override
  String get instructionsHint => 'Comment l’assistant doit-il se comporter ?';

  @override
  String get temperature => 'Température';

  @override
  String get useSetting => 'Suivre le réglage';

  @override
  String get thinking => 'Réflexion';

  @override
  String get on => 'Activé';

  @override
  String get off => 'Désactivé';

  @override
  String get webResearchShort => 'Recherche web';

  @override
  String get unpin => 'Désépingler';

  @override
  String get pinToTop => 'Épingler en haut';

  @override
  String get rename => 'Renommer';

  @override
  String get moveToFolder => 'Déplacer dans un dossier';

  @override
  String get tags => 'Étiquettes';

  @override
  String get renameConversation => 'Renommer la conversation';

  @override
  String get tagsCommaSeparated => 'Étiquettes (séparées par des virgules)';

  @override
  String get newFolder => 'Nouveau dossier…';

  @override
  String get removeFromFolder => 'Retirer du dossier';

  @override
  String get folderName => 'Nom du dossier';

  @override
  String get deleteConversationQuestion => 'Supprimer la conversation ?';

  @override
  String get keep => 'Garder';

  @override
  String couldNotDelete(Object error) {
    return 'Suppression impossible : $error';
  }

  @override
  String get clear => 'Effacer';

  @override
  String get all => 'Tout';

  @override
  String get knowledgeIntro =>
      'Importez vos documents une fois — PDF, Word, texte, code, EPUB… — et chaque question est répondue avec les meilleurs passages de la collection active, cités comme des sources web. La recherche tourne entièrement sur le téléphone : classement plein texte, plus le sens une fois le modèle d’embedding téléchargé.';

  @override
  String get newCollection => 'Nouvelle collection';

  @override
  String get useInChats => 'Utiliser dans les conversations';

  @override
  String get collectionOff => 'Désactivée — aucune collection consultée';

  @override
  String collectionActive(Object collection) {
    return 'Active : $collection';
  }

  @override
  String get readingAndIndexing => 'Lecture et indexation…';

  @override
  String get noCollections =>
      'Aucune collection pour l’instant. Créez-en une avec l’icône dossier, puis ajoutez des fichiers.';

  @override
  String get addFiles => 'Ajouter des fichiers';

  @override
  String get deleteCollection => 'Supprimer la collection';

  @override
  String get searchByMeaning => 'Recherche par le sens';

  @override
  String get ready => 'Prêt';

  @override
  String indexForMeaning(Object count) {
    return 'Indexer $count passages par le sens';
  }

  @override
  String indexingProgress(Object done, Object total) {
    return 'Indexation par le sens… $done/$total';
  }

  @override
  String downloadMb(Object mb) {
    return 'Télécharger · $mb Mo';
  }

  @override
  String get addMemory => 'Ajouter un souvenir';

  @override
  String get editMemory => 'Modifier le souvenir';

  @override
  String get forgetEverything => 'Tout oublier';

  @override
  String get forgetEverythingQuestion => 'Tout oublier ?';

  @override
  String forgetEverythingHint(Object count) {
    return 'Les $count faits retenus seront supprimés. Les conversations ne sont pas touchées.';
  }

  @override
  String get forget => 'Oublier';

  @override
  String get rememberAboutMe => 'Retenir des choses sur moi';

  @override
  String get rememberAboutMeHint =>
      'Retenir les faits durables que vous partagez, comme votre métier et vos préférences. Les notes sont enregistrées sur cet appareil. Le partage et l’extraction par un modèle distant nécessitent votre accord pour cette connexion. Vous pouvez modifier ou supprimer les notes ci-dessous.';

  @override
  String get memoryStorageHint =>
      'Les notes sont stockées sur cet appareil. Chaque connexion distante nécessite une autorisation distincte pour les recevoir ou les mémoriser.';

  @override
  String get memoryRemoteLocalHint =>
      'Les déclarations claires, comme votre métier ou votre nom, peuvent être mémorisées localement. Activez le partage pour que cette connexion utilise vos notes, et l’apprentissage pour extraire d’autres faits durables.';

  @override
  String get whatAssistantRemembers => 'Ce que l’assistant retient';

  @override
  String get nothingYetFills =>
      'Rien pour l’instant. Ça se remplit au fil des conversations.';

  @override
  String get nothingStoredSwitch =>
      'Rien d’enregistré. Activez l’interrupteur, ou ajoutez des faits à la main avec +.';

  @override
  String get switchModel => 'Changer de modèle';

  @override
  String get nothingOnPhone => 'Rien n’est encore sur ce téléphone.';

  @override
  String get modelsOnPhone =>
      'Les modèles de ce téléphone. Le modèle actif répond à vos conversations.';

  @override
  String get modelUnloaded =>
      'Modèle déchargé. Il se recharge à votre prochain message.';

  @override
  String get unloadModel => 'Décharger le modèle · libérer la mémoire';

  @override
  String get openModelLibrary => 'Ouvrir la bibliothèque de modèles';

  @override
  String get active => 'Actif';

  @override
  String get pickerEmptyHint =>
      'Téléchargez un modèle depuis la bibliothèque, ou importez un GGUF que vous possédez déjà. Une conversation a besoin d’un modèle chargé ; tout reste sur ce téléphone.';

  @override
  String get takePhoto => 'Prendre une photo';

  @override
  String get attachCamera => 'Appareil photo';

  @override
  String get attachFile => 'Fichier';

  @override
  String get attachGoalShort => 'Objectif';

  @override
  String get photos => 'Photos';

  @override
  String get photosHint => 'JPEG, PNG, WebP, HEIC…';

  @override
  String get documentOrFile => 'Document ou fichier';

  @override
  String get documentHint =>
      'PDF, Word, PowerPoint, Excel, OpenDocument, EPUB, RTF, texte, code, CSV, JSON, HTML…';

  @override
  String couldNotOpenPicker(Object error) {
    return 'Impossible d’ouvrir le sélecteur : $error';
  }

  @override
  String get readingAttachments => 'Lecture des pièces jointes…';

  @override
  String get turnOnWebQuestion => 'Activer la recherche web ?';

  @override
  String get turnOnWebHint =>
      'Quand vous collez un lien, demandez une recherche, ou qu’une question semble d’actualité, la question est envoyée à DuckDuckGo et les pages de résultats (trois par défaut, Réglages > Raisonnement et recherche) sont lues directement depuis leurs sites (ils voient votre adresse IP). Avec l’inférence locale, tout le reste demeure sur cet appareil. Si le serveur distant est activé, la question et le contexte fourni lui sont aussi envoyés.';

  @override
  String get stayLocal => 'Rester en local';

  @override
  String get turnOn => 'Activer';

  @override
  String get compareWithTitle => 'Comparer avec…';

  @override
  String get compareHint =>
      'La même question et les mêmes preuves, répondues par un autre modèle. Affiché à côté de cette réponse ; hors de la conversation.';

  @override
  String shareFailed(Object error) {
    return 'Partage impossible : $error';
  }

  @override
  String exportFailed(Object error) {
    return 'Export impossible : $error';
  }

  @override
  String get dismiss => 'Fermer';

  @override
  String licenseLabel(Object license) {
    return 'Licence · $license';
  }

  @override
  String get resumeRetry => 'Reprendre / réessayer';

  @override
  String get useModel => 'Utiliser ce modèle';

  @override
  String get remove => 'Retirer';

  @override
  String get benchmark => 'Banc d’essai';

  @override
  String visionPercent(Object percent) {
    return 'Vision $percent %';
  }

  @override
  String get verifyingVision => 'Vérification de la vision…';

  @override
  String get visionReady => 'Vision prête';

  @override
  String addVisionMb(Object mb) {
    return 'Ajouter la vision · $mb Mo';
  }

  @override
  String get addFromHf => 'Ajouter depuis Hugging Face';

  @override
  String get importGguf => 'Importer un GGUF';

  @override
  String get addFromHfHint =>
      'Collez le lien d’un fichier GGUF public unique. Sa taille, sa somme de contrôle et sa licence seront affichées avant le téléchargement.';

  @override
  String get importGgufHint =>
      'Choisissez un GGUF que vous avez téléchargé vous-même. Il sera copié dans votre bibliothèque privée ; prévoyez l’espace d’une seconde copie.';

  @override
  String get ggufLink => 'Lien du fichier GGUF';

  @override
  String get templateFallback => 'Gabarit de repli';

  @override
  String get automaticMetadata => 'Automatique (métadonnées du modèle)';

  @override
  String get ggufWarning =>
      'Modèles de génération de texte seulement. Un GGUF peut exiger plus de RAM que sa taille. Les nouvelles architectures et les fichiers scindés peuvent ne pas être pris en charge.';

  @override
  String get checkModel => 'Vérifier le modèle';

  @override
  String get chooseFile => 'Choisir un fichier';

  @override
  String get checkingMetadata => 'Vérification des métadonnées…';

  @override
  String downloadQuestion(Object model) {
    return 'Télécharger $model ?';
  }

  @override
  String get modelCard => 'Fiche du modèle';

  @override
  String get removeModelQuestion => 'Retirer ce modèle ?';

  @override
  String removeModelHint(Object model, Object size) {
    return 'Supprimer $model de cette app et libérer $size ? Vos conversations seront conservées.';
  }

  @override
  String get browseHf => 'Parcourir Hugging Face';

  @override
  String get yourModelLibrary => 'Votre bibliothèque de modèles';

  @override
  String get libraryHint =>
      'Téléchargez un premier modèle, ajoutez un lien de fichier Hugging Face, ou importez un GGUF que vous possédez. Après le téléchargement, l’inférence fonctionne hors ligne.';

  @override
  String get searchHf => 'Chercher sur Hugging Face';

  @override
  String get pasteLink => 'Coller un lien';

  @override
  String get importGgufButton => 'Importer un GGUF';

  @override
  String get checkingCopying => 'Vérification et copie du modèle…';

  @override
  String get preparingLibrary => 'Préparation de votre bibliothèque…';

  @override
  String get onThisDevice => 'Sur cet appareil';

  @override
  String get nothingDownloaded =>
      'Rien de téléchargé pour l’instant. Choisissez un modèle ci-dessous pour commencer.';

  @override
  String get availableToDownload => 'Disponibles au téléchargement';

  @override
  String get everythingOnPhone => 'Tout le catalogue est sur ce téléphone.';

  @override
  String get justNow => 'à l’instant';

  @override
  String minutesAgo(Object n) {
    return 'il y a $n min';
  }

  @override
  String hoursAgo(Object n) {
    return 'il y a $n h';
  }

  @override
  String get webModeOff => 'Désactivée · reste en local';

  @override
  String get webModeAuto =>
      'Auto · liens, demandes de recherche et questions d’actualité';

  @override
  String get webModeAlways => 'Toujours · recherche à chaque message';

  @override
  String rememberedOne(Object fact) {
    return 'Retenu : $fact';
  }

  @override
  String rememberedMore(Object fact, Object more) {
    return 'Retenu : $fact (+$more)';
  }

  @override
  String get reviewMemory => 'Vérifier ce qui a été retenu';

  @override
  String get memoryDialogTitle => 'Mémoire';

  @override
  String get memoryDialogHint =>
      'La mémoire garde de courts faits que vous énoncez sur vous-même pour que les prochaines conversations les connaissent déjà. Elle est stockée uniquement sur ce téléphone et se modifie à tout moment dans Réglages > Mémoire. Voici ce qui vient d’être noté — modifiez, gardez ou supprimez.';

  @override
  String get memoryDialogFieldHint =>
      'Un fait par ligne ; les lignes vides sont supprimées';

  @override
  String get discard => 'Ignorer';

  @override
  String get goalDescribeFirst => 'Décrivez d\'abord l\'objectif.';

  @override
  String get goalLimitsInvalid =>
      'Saisissez des limites positives d\'étapes, de temps, de jetons et d\'outils.';

  @override
  String get goalsTitle => 'Objectifs';

  @override
  String get goalIntro =>
      'Donnez un objectif au modèle. Il planifie les questions à rechercher, les examine une à une, vérifie les résultats selon vos critères, comble les lacunes et rédige un rapport sourcé.';

  @override
  String get goalWebOff =>
      'La recherche web est désactivée : l\'objectif ne peut utiliser que ce que le modèle sait déjà. Activez-la avec la pastille globe du champ de message pour une recherche sourcée.';

  @override
  String get goalLabel => 'Objectif';

  @override
  String get goalExample =>
      'Comparer les trois voitures électriques les plus populaires au Canada pour une famille de quatre';

  @override
  String get goalKindTitle => 'Type de recherche';

  @override
  String get goalCriteriaLabel =>
      'Ce qu\'un bon résultat contient (facultatif)';

  @override
  String get goalBudgetTitle => 'Quantité de travail';

  @override
  String get goalMaxSteps => 'Étapes de recherche maximum';

  @override
  String get goalMaxMinutes => 'Minutes maximum';

  @override
  String get goalMaxTokens => 'Budget approximatif de jetons';

  @override
  String get goalMaxToolCalls => 'Appels d\'outils maximum';

  @override
  String get goalKeepOpen =>
      'Gardez l\'application ouverte : Android peut l\'arrêter en arrière-plan. La progression est enregistrée après chaque étape.';

  @override
  String get goalStart => 'Lancer l\'objectif';

  @override
  String get goalBudgetQuick => 'Rapide';

  @override
  String get goalBudgetQuickHint => 'Environ 4 recherches · jusqu\'à 10 min';

  @override
  String get goalBudgetStandard => 'Standard';

  @override
  String get goalBudgetStandardHint => 'Environ 8 recherches · jusqu\'à 30 min';

  @override
  String get goalBudgetDeep => 'Approfondi';

  @override
  String get goalBudgetDeepHint => 'Environ 14 recherches · jusqu\'à 60 min';

  @override
  String get goalBudgetUnlimited => 'Illimité';

  @override
  String get goalBudgetUnlimitedHint =>
      'Jusqu\'à la fin, une pause ou un arrêt';

  @override
  String get goalBudgetCustom => 'Personnalisé';

  @override
  String get goalBudgetCustomHint => 'Fixez vos propres limites';

  @override
  String get goalPhasePlanning => 'Planification de la recherche';

  @override
  String get goalPhaseResearching => 'Recherche en cours';

  @override
  String get goalPhaseChecking =>
      'Vérification des résultats selon vos critères';

  @override
  String get goalPhaseWriting => 'Rédaction du rapport';

  @override
  String get goalPhaseDone => 'Terminé';

  @override
  String get goalPaused => 'En pause';

  @override
  String get goalPausedBudget => 'En pause — le budget est épuisé';

  @override
  String get goalCompleted => 'Terminé';

  @override
  String get goalStopped => 'Arrêté';

  @override
  String get goalFailed => 'Un problème est survenu';

  @override
  String get goalReady => 'Prêt';

  @override
  String goalStepsOf(int done, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total étapes',
      one: '1 étape',
    );
    return '$done sur $_temp0';
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
  String get goalTokensWord => 'jetons';

  @override
  String get goalToolCallsWord => 'appels d\'outils';

  @override
  String get goalPauseAfterStep => 'Pause après cette étape';

  @override
  String get goalStop => 'Arrêter';

  @override
  String get goalContinue => 'Continuer';

  @override
  String get goalOpenChat => 'Ouvrir la conversation';

  @override
  String get goalNew => 'Nouvel objectif';

  @override
  String get goalHowMade => 'Comment ce rapport a été fait';

  @override
  String get goalPastTitle => 'Objectifs passés';

  @override
  String get goalPastReopen => 'Affiner ou continuer';

  @override
  String drawerGoalsPast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count objectifs passés',
      one: '1 objectif passé',
    );
    return '$_temp0 · En commencer un nouveau';
  }

  @override
  String get goalReport => 'Rapport';

  @override
  String get goalInterimReport => 'Rapport intermédiaire';

  @override
  String get goalCopyReport => 'Copier le rapport';

  @override
  String get goalReportCopied => 'Rapport copié';

  @override
  String get goalPlan => 'Plan';

  @override
  String get goalNotCovered => 'Non couvert par le rapport';

  @override
  String get goalStillMissing => 'Encore manquant';

  @override
  String get goalSourcesTitle => 'Sources';

  @override
  String get goalKindGeneral => 'Général';

  @override
  String get goalKindGeneralHint =>
      'Tout sujet : un rapport équilibré et sourcé';

  @override
  String get goalKindGeneralCriteria =>
      'L\'objectif entièrement traité, chaque affirmation avec une source';

  @override
  String get goalKindCode => 'Code';

  @override
  String get goalKindCodeHint =>
      'API, erreurs, bibliothèques : du code qui fonctionne et les versions';

  @override
  String get goalKindCodeCriteria =>
      'Une approche fonctionnelle avec du code, les versions concernées et les pièges connus';

  @override
  String get goalKindScience => 'Scientifique';

  @override
  String get goalKindScienceHint =>
      'Ce que disent les données : études, consensus, limites';

  @override
  String get goalKindScienceCriteria =>
      'Les principaux résultats avec le type d\'étude, l\'année et la taille, les points d\'accord et de désaccord, et les limites';

  @override
  String get goalKindMath => 'Maths';

  @override
  String get goalKindMathHint =>
      'Définitions, démonstrations, résultats vérifiés';

  @override
  String get goalKindMathCriteria =>
      'Le résultat final, chaque étape de la démonstration et une vérification de la réponse';

  @override
  String get goalKindNews => 'Actualité';

  @override
  String get goalKindNewsHint => 'Ce qui s\'est passé, quand, qui dit quoi';

  @override
  String get goalKindNewsCriteria =>
      'Une chronologie datée, les personnes et organisations impliquées, leurs positions et la suite';

  @override
  String get goalKindProduct => 'Comparatif de produits';

  @override
  String get goalKindProductHint => 'Les options côte à côte, puis un choix';

  @override
  String get goalKindProductCriteria =>
      'Prix, caractéristiques clés, forces et faiblesses de chaque option, et à qui chacune convient';

  @override
  String get drawerGoalsHint => 'Une recherche planifiée et un rapport sourcé';

  @override
  String drawerGoalRunning(int step, int total) {
    return 'En cours · étape $step sur $total';
  }

  @override
  String drawerGoalReport(String goal) {
    return 'Rapport prêt · $goal';
  }

  @override
  String get emptyGoalTitle => 'Mener une recherche';

  @override
  String get emptyGoalHint =>
      'Elle planifie les questions, recherche chacune et rédige un rapport sourcé — pour le code, les sciences, les maths, l\'actualité ou les comparatifs.';

  @override
  String get composerResearchGoal => 'En faire un objectif de recherche';

  @override
  String get composerManageShortcuts => 'Gérer';

  @override
  String get shareNothing => 'Rien à ouvrir dans ce partage.';

  @override
  String get scheduledWaiting =>
      'Votre invite programmée est dans le champ de message.';

  @override
  String get shareMore => 'Seuls les 8 premiers fichiers ont été ouverts.';

  @override
  String shareSkipped(String names) {
    return 'Non ouverts (vides ou de plus de 64 Mo) : $names';
  }

  @override
  String get attachGoal => 'Recherche en objectif';

  @override
  String get attachGoalHint =>
      'Un plan, plusieurs recherches, un rapport sourcé';

  @override
  String get batterySaver => 'Économiseur de batterie';

  @override
  String get batterySaverOff =>
      'Des réponses plus légères sur ce téléphone quand la batterie est faible ou qu\'il chauffe';

  @override
  String batterySaverOn(int level) {
    return 'Sous $level % hors charge, ou quand le téléphone chauffe : sans réflexion, réponses plus courtes, moins de pages lues';
  }

  @override
  String get batterySaverLevel => 'L\'économiseur démarre à';

  @override
  String get scheduleTitle => 'Invites programmées';

  @override
  String get scheduleRowHint =>
      'Une notification quotidienne qui pose une invite enregistrée quand vous la touchez';

  @override
  String get shortcutsTitle => 'Raccourcis d\'invite';

  @override
  String get shortcutsRowHint =>
      'Tapez / dans un message : /summarize, /translate fr, les vôtres';

  @override
  String get hostTitle => 'Utiliser cet appareil comme serveur';

  @override
  String get hostRowHint => 'Partager un modèle chargé avec un autre appareil';

  @override
  String get shortcutNew => 'Nouveau raccourci';

  @override
  String get shortcutsIntro =>
      'Tapez / dans le champ de message pour en choisir un. « /summarize » suivi de votre texte envoie l\'invite enregistrée avec ce texte ; « /translate fr … » prend d\'abord une langue.';

  @override
  String get shortcutBuiltIn => 'intégré';

  @override
  String shortcutDelete(String name) {
    return 'Supprimer /$name';
  }

  @override
  String get shortcutNameRule => 'Minuscules, chiffres et tirets, 24 au plus.';

  @override
  String shortcutYourVersion(String name) {
    return 'Votre version de /$name';
  }

  @override
  String shortcutEdit(String name) {
    return 'Modifier /$name';
  }

  @override
  String get shortcutName => 'Nom';

  @override
  String get shortcutDescription => 'Description';

  @override
  String get shortcutPrompt => 'Invite';

  @override
  String shortcutPromptHelp(String token) {
    return '$token est remplacé par le texte qui suit la commande ; sans lui, le texte est ajouté à la fin.';
  }

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String scheduleFailed(String error) {
    return 'Impossible de programmer le rappel : $error';
  }

  @override
  String get scheduleNeedsNotifications =>
      'Autorisez les notifications quand Android le demande, sinon le rappel ne pourra pas s\'afficher.';

  @override
  String get scheduleNew => 'Nouvelle';

  @override
  String get scheduleIntro =>
      'Une fois par jour à l\'heure choisie, une notification propose l\'invite. Touchez-la et l\'application la pose dans une nouvelle conversation (ou l\'ouvre en objectif). Rien ne s\'exécute en arrière-plan et rien n\'est envoyé avant votre geste.';

  @override
  String get scheduleEmpty =>
      'Aucune pour l\'instant. Essayez un point d\'actualité le matin ou un objectif hebdomadaire.';

  @override
  String get scheduleChat => 'Conversation';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get scheduleNewTitle => 'Nouvelle invite programmée';

  @override
  String get commonEdit => 'Modifier';

  @override
  String scheduleEveryDay(String time) {
    return 'Tous les jours à $time';
  }

  @override
  String get scheduleAskChat => 'Poser dans une conversation';

  @override
  String get scheduleOpenGoal => 'Ouvrir en objectif';

  @override
  String get scheduleExample =>
      'Quelles sont les principales nouvelles au Canada aujourd\'hui ?';

  @override
  String get scheduleNotificationTitle =>
      'Titre de la notification (facultatif)';

  @override
  String get hostPortRange => 'Utilisez un nombre de 1 à 65535.';

  @override
  String get hostPortReserved =>
      'Les ports inférieurs à 1024 sont réservés sur Android.';

  @override
  String hostCopied(String what) {
    return '$what copié';
  }

  @override
  String get hostPickModel => 'Modèle à servir';

  @override
  String get hostPickHint =>
      'Le chargement prend quelques secondes. Un serveur en marche redémarre avec le nouveau modèle ; les appareils connectés gardent la même adresse et le même jeton.';

  @override
  String get hostChangeModel => 'Changer';

  @override
  String get hostManageModels => 'Télécharger ou importer des modèles';

  @override
  String get hostModel => 'Modèle';

  @override
  String get hostNoModel => 'Aucun modèle chargé';

  @override
  String get hostLoadFirst => 'Choisissez un modèle à servir.';

  @override
  String get hostModelHint =>
      'D\'autres appareils discutent avec ce modèle tant que le serveur tourne.';

  @override
  String get hostConnection => 'Connexion';

  @override
  String get hostPort => 'Port';

  @override
  String get hostPortHint => 'L\'autre appareil se connecte à ce port.';

  @override
  String get hostStarting => 'Démarrage…';

  @override
  String get hostStart => 'Démarrer le serveur';

  @override
  String get hostToken => 'Jeton d\'accès';

  @override
  String get hostRotate => 'Renouveler le jeton d\'accès';

  @override
  String get hostRotateHint =>
      'Les appareils qui utilisent le jeton actuel devront se reconnecter avec le nouveau.';

  @override
  String get hostRotated =>
      'Un nouveau jeton sera utilisé au prochain démarrage.';

  @override
  String get hostWaiting => 'En service · en attente de requêtes';

  @override
  String hostAnswering(String client) {
    return 'Répond à $client';
  }

  @override
  String hostUp(String duration) {
    return 'actif depuis $duration';
  }

  @override
  String get hostLive => 'En direct';

  @override
  String get hostAnswered => 'réponses';

  @override
  String get hostRefused => 'refusées';

  @override
  String get hostFailed => 'échecs';

  @override
  String get hostTokensIn => 'jetons reçus';

  @override
  String get hostTokensOut => 'jetons générés';

  @override
  String get hostAvgSpeed => 'vitesse moy.';

  @override
  String get hostDevices => 'appareils';

  @override
  String get hostBattery => 'batterie';

  @override
  String get hostHeat => 'chaleur';

  @override
  String get hostLowBattery => 'Arrêt si batterie faible';

  @override
  String get hostLowBatteryHint =>
      'Le serveur s\'arrête aussi quand le téléphone signale une forte chaleur. L\'écran reste allumé pendant qu\'il tourne.';

  @override
  String get commonOff => 'Désactivé';

  @override
  String get hostConnect => 'Connecter un autre appareil';

  @override
  String get hostServerUrl => 'URL du serveur';

  @override
  String get hostModelId => 'ID du modèle';

  @override
  String get hostHideToken => 'Masquer le jeton';

  @override
  String get hostShowToken => 'Afficher le jeton';

  @override
  String get hostCopyConnection => 'Copier la connexion';

  @override
  String get hostPairHint =>
      'Sur l\'autre téléphone : scannez ce code avec l\'appareil photo et copiez le texte, ou collez la connexion copiée, puis dans OnDevice LLM ouvrez Réglages > Serveur distant > Coller la connexion. Toute application compatible OpenAI fonctionne aussi, avec l\'URL, le modèle et le jeton.';

  @override
  String get hostRecent => 'Requêtes récentes';

  @override
  String get hostNoneYet => 'Aucune pour l\'instant.';

  @override
  String hostCopy(String what) {
    return 'Copier : $what';
  }

  @override
  String hostInOut(int prompt, int completion) {
    return '$prompt reçus · $completion générés';
  }

  @override
  String get remotePasteNone =>
      'Le presse-papiers ne contient aucune connexion. Sur l\'autre téléphone, touchez d\'abord Copier la connexion (ou scannez son code QR).';

  @override
  String remotePasted(String name) {
    return '$name ajouté. Activez « Utiliser le serveur distant » pour discuter avec lui.';
  }

  @override
  String get remotePaste => 'Coller la connexion';

  @override
  String get remoteAdd => 'Ajouter une connexion';

  @override
  String get configCopied => 'Configuration copiée en texte';

  @override
  String get configTooLarge =>
      'Ce fichier est trop volumineux pour être une configuration.';

  @override
  String get configNotAFile =>
      'Ce fichier n\'est pas une configuration de modèle OnDevice LLM.';

  @override
  String get configNotInClipboard =>
      'Le presse-papiers ne contient aucune configuration de modèle. Copiez-en une d\'abord.';

  @override
  String configMadeFor(String model) {
    return 'Conçue pour $model';
  }

  @override
  String get configNotDownloaded =>
      'Ce modèle est au catalogue mais pas téléchargé : récupérez-le dans Modèles, ou appliquez à un modèle que vous avez.';

  @override
  String get configNotOnPhone =>
      'Ce modèle n\'est pas sur ce téléphone. Appliquez les réglages à un modèle que vous avez :';

  @override
  String configSameModel(String model) {
    return '$model (même modèle)';
  }

  @override
  String get configEmpty =>
      'La fiche ne règle rien : le modèle tournerait avec vos propres réglages.';

  @override
  String configLeftOut(String keys) {
    return 'Écartés (accès web, matériel du téléphone, taille de contexte ou inconnus) : $keys';
  }

  @override
  String get configApply => 'Appliquer';

  @override
  String get hostShowQr => 'Afficher le code d\'appairage';

  @override
  String get voiceConversation => 'Conversation vocale';

  @override
  String get chatPinModel => 'Épingler un modèle à cette conversation';

  @override
  String get chatPinHint =>
      'Cette conversation répond toujours avec le modèle épinglé, quel que soit le modèle choisi ailleurs.';

  @override
  String get chatPinNone => 'Aucun : utiliser le modèle sélectionné';

  @override
  String chatPinned(String model) {
    return '📌 $model';
  }

  @override
  String get readerSummarize => 'Résumer l\'article';

  @override
  String get readerKeyPoints => 'Points clés';

  @override
  String get readerExplain => 'Expliquer simplement';

  @override
  String readerSummarizePrompt(String url) {
    return 'Lis cet article et résume-le en quelques paragraphes courts, en gardant exacts les noms, les chiffres et les dates, et cite-le : $url';
  }

  @override
  String readerKeyPointsPrompt(String url) {
    return 'Lis cet article et donne ses points clés en courtes puces, en le citant : $url';
  }

  @override
  String readerExplainPrompt(String url) {
    return 'Lis cet article et explique ce qu\'il dit simplement, pour quelqu\'un qui découvre le sujet, en le citant : $url';
  }

  @override
  String get readerNeedsWeb =>
      'Lire un lien nécessite la recherche web : activez-la avec la pastille globe.';

  @override
  String get saveToKnowledge => 'Enregistrer dans la bibliothèque';

  @override
  String get knowledgeSaveHint =>
      'Choisissez une collection et les messages à enregistrer. Seuls les textes visibles et leurs liens sources sont inclus; le raisonnement privé reste exclu.';

  @override
  String get knowledgeCollectionName => 'Nom de la collection';

  @override
  String get knowledgeDocumentTitle => 'Titre du document';

  @override
  String get knowledgeSelectMessages => 'Messages à enregistrer';

  @override
  String get knowledgeChatTitle => 'Conversation enregistrée';

  @override
  String get knowledgeNameRequired =>
      'Saisissez un nom de collection et un titre de document.';

  @override
  String knowledgeSaved(String collection) {
    return 'Enregistré dans $collection.';
  }

  @override
  String knowledgeSaveFailed(String error) {
    return 'Impossible d’enregistrer dans la bibliothèque : $error';
  }

  @override
  String get you => 'Vous';

  @override
  String get assistant => 'Assistant';

  @override
  String get backupPasswordTooShort =>
      'Utilisez au moins 12 caractères pour le mot de passe de sauvegarde.';

  @override
  String get backupPasswordsMismatch =>
      'Les mots de passe ne correspondent pas.';

  @override
  String get backupSaveDialog => 'Enregistrer la sauvegarde chiffrée';

  @override
  String get backupSaveCancelled => 'Enregistrement annulé.';

  @override
  String get backupSavedNotice =>
      'Sauvegarde chiffrée enregistrée. Conservez le mot de passe : il ne peut pas être récupéré.';

  @override
  String backupFailedNotice(String error) {
    return 'Échec de la sauvegarde : $error';
  }

  @override
  String get backupEnterPassword => 'Saisissez le mot de passe de sauvegarde.';

  @override
  String get backupReplaceQuestion =>
      'Remplacer la bibliothèque de cet appareil ?';

  @override
  String get backupReplaceHint =>
      'La restauration remplacera les discussions, la bibliothèque, les pièces jointes et les paramètres au prochain démarrage. Les modèles locaux et les clés API enregistrées ne sont pas inclus.';

  @override
  String get backupRestoreAction => 'Restaurer';

  @override
  String get backupTooLarge => 'La sauvegarde dépasse la limite de sécurité.';

  @override
  String get backupVerifiedNotice =>
      'Sauvegarde vérifiée. Fermez complètement l’application, puis rouvrez-la pour appliquer la restauration.';

  @override
  String backupRestoreFailed(String error) {
    return 'Échec de la restauration : $error';
  }

  @override
  String get backupTitle => 'Sauvegarde chiffrée';

  @override
  String get backupIntro =>
      'Enregistrez les discussions, la bibliothèque, les pièces jointes, les objectifs et les paramètres dans un fichier protégé par mot de passe. Les modèles et les clés API restent sur cet appareil. La limite est de 96 Mo.';

  @override
  String get backupPasswordLabel => 'Mot de passe de sauvegarde';

  @override
  String get backupConfirmPassword =>
      'Confirmer le mot de passe de la nouvelle sauvegarde';

  @override
  String get backupCreateAction => 'Créer une sauvegarde chiffrée';

  @override
  String get backupRestoreBackup => 'Restaurer une sauvegarde';

  @override
  String get uiRemoteProfilePageDeleteConnection => 'Supprimer la connexion ?';

  @override
  String get uiRemoteProfilePageCancel => 'Annuler';

  @override
  String get uiRemoteProfilePageDelete => 'Supprimer';

  @override
  String get uiRemoteProfilePageConnection => 'Connexion';

  @override
  String get uiRemoteProfilePageThisConnectionWasRemoved =>
      'Cette connexion a été supprimée.';

  @override
  String get uiRemoteProfilePageDeleteConnection2 => 'Supprimer la connexion';

  @override
  String get uiRemoteProfilePageProvider => 'Fournisseur';

  @override
  String get uiRemoteProfilePageName => 'Nom';

  @override
  String get uiRemoteProfilePageServerURL => 'URL du serveur';

  @override
  String get uiRemoteProfilePageGetAKeyInTheBrowser =>
      'Obtenez une clé dans le navigateur';

  @override
  String get uiRemoteProfilePageModel => 'Modèle';

  @override
  String get uiRemoteProfilePageModelsOnTheServer => 'Modèles sur le serveur';

  @override
  String get uiRemoteProfilePageRequestsPerMinute => 'Requêtes par minute';

  @override
  String get uiRemoteProfilePageNone => 'aucun';

  @override
  String get uiRemoteProfilePageRequestsPerDay => 'Demandes par jour';

  @override
  String get uiRemoteProfilePageExtraHeaders => 'En-têtes supplémentaires';

  @override
  String get uiAdvancedPagesContextBatch => 'Contexte & lot';

  @override
  String get uiAdvancedPagesContextSize => 'Taille du contexte';

  @override
  String get uiAdvancedPagesTokensTheModelCanSeeAt =>
      'Jetons que le modèle peut voir immédiatement : la conversation, les preuves Web et la réponse. La mémoire grandit avec elle ; si le téléphone ne peut pas la retenir, le modèle se charge avec un contexte plus court et une note le signale.';

  @override
  String get uiAdvancedPagesContextSizeTokens => 'Taille du contexte (jetons)';

  @override
  String get uiAdvancedPagesBatchSize => 'Taille du lot';

  @override
  String get uiAdvancedPagesPromptTokensSubmittedPerStepAuto =>
      'Jetons d’invite soumis par étape. Auto est 512, l\'optimum mesuré sur ce téléphone ; plus grand aide principalement le GPU à préremplir les longues invites.';

  @override
  String get uiAdvancedPagesMicroBatch => 'Micro-lot';

  @override
  String get uiAdvancedPagesTokensPerComputeStepWithinA =>
      'Jetons par étape de calcul au sein d\'un lot. Correspond automatiquement à la taille du lot. Jamais au-dessus de la taille du lot.';

  @override
  String get uiAdvancedPagesKeepConversationInContext =>
      'Gardez la conversation dans son contexte';

  @override
  String get uiAdvancedPagesOnlyNewTextIsEvaluatedOn =>
      'Seul le nouveau texte est évalué à chaque tour ; les tours précédents restent résidents. Off relit toute la conversation à chaque message.';

  @override
  String get uiAdvancedPagesHardware => 'Matériel';

  @override
  String get uiAdvancedPagesBackend => 'Back-end';

  @override
  String get uiAdvancedPagesAutomaticUsesCPUOpenCL2Faster =>
      'Automatique utilise le processeur. OpenCL : lecture rapide environ 2 fois plus rapide pour la recherche, réponses environ 15 % plus lentes ; le modèle se recharge lorsque vous le modifiez.';

  @override
  String get uiAdvancedPagesGPULayers => 'Couches GPU';

  @override
  String get uiAdvancedPagesLayersOffloadedToTheGPUIgnored =>
      'Couches déchargées sur le GPU. Ignoré lorsque le backend est uniquement CPU.';

  @override
  String get uiAdvancedPagesCPUThreadsDecode => 'Threads CPU (décodage)';

  @override
  String get uiAdvancedPagesWorkerThreadsWhileTheAnswerStreams =>
      'Les threads de travail pendant que la réponse est diffusée. Auto en utilise 6 sur les téléphones à 8 cœurs (mesurés le plus rapidement), sinon la moitié des cœurs.';

  @override
  String get uiAdvancedPagesCPUThreadsPrefill =>
      'Threads CPU (pré-remplissage)';

  @override
  String get uiAdvancedPagesThreadsWhileThePromptIsRead =>
      'Discussions pendant la lecture de l\'invite. Auto utilise chaque cœur : le pré-remplissage continue d\'accélérer jusqu\'à 8 threads où le décodage est ralenti.';

  @override
  String get uiAdvancedPagesFlashAttention => 'Attention éclair';

  @override
  String get uiAdvancedPagesFasterAttentionKernelWithLowerMemory =>
      'Noyau d’attention plus rapide avec une utilisation moindre de la mémoire.';

  @override
  String get uiAdvancedPagesKVCache => 'Cache KV';

  @override
  String get uiAdvancedPagesPrecisionOfCachedAttentionState =>
      'Précision de l\'état d\'attention mis en cache';

  @override
  String get uiAdvancedPagesSampling => 'Échantillonnage';

  @override
  String get uiAdvancedPagesTemperature => 'Température';

  @override
  String get uiAdvancedPagesRandomnessLowerIsMoreFocusedHigher =>
      'Le hasard. Le niveau inférieur est plus ciblé, le niveau supérieur est plus varié.';

  @override
  String get uiAdvancedPagesTopP => 'Haut-P';

  @override
  String get uiAdvancedPagesSampleFromTheSmallestSetOf =>
      'Échantillon à partir du plus petit ensemble de jetons dont la probabilité totalise P.';

  @override
  String get uiAdvancedPagesMinP => 'Min-P';

  @override
  String get uiAdvancedPagesDropTokensLessLikelyThanThis =>
      'Il est moins probable que les jetons soient abandonnés que cette fraction du jeton supérieur.';

  @override
  String get uiAdvancedPagesTopK => 'Top-K';

  @override
  String get uiAdvancedPagesOnlyTheKMostLikelyTokens =>
      'Seuls les K jetons les plus probables sont pris en compte. 0 désactive.';

  @override
  String get uiAdvancedPagesRepetitionPenalty => 'Pénalité de répétition';

  @override
  String get uiAdvancedPagesDiscouragesRepeatingRecentTokens100 =>
      'Décourage la répétition des jetons récents. 1h00 est éteint.';

  @override
  String get uiAdvancedPagesMaxTokens => 'Nombre maximum de jetons';

  @override
  String get uiAdvancedPagesUpperBoundOnOneResponseReasoning =>
      'Borne supérieure d\'une réponse, raisonnement inclus. Il est réservé à l\'intérieur du contexte, il doit donc s\'adapter à l\'invite.';

  @override
  String get uiAdvancedPagesMaxTokensPerResponse =>
      'Nombre maximum de jetons par réponse';

  @override
  String get uiAdvancedPagesReasoningSearch => 'Raisonnement et recherche';

  @override
  String get uiAdvancedPagesThinkingMode => 'Mode réflexion';

  @override
  String get uiAdvancedPagesShowModelGeneratedReasoningWhenSupported =>
      'Afficher le raisonnement généré par le modèle lorsqu\'il est pris en charge. Il peut contenir des erreurs et ne constitue pas une preuve d’exactitude.';

  @override
  String get uiAdvancedPagesThinkingBudget => 'Penser le budget';

  @override
  String get uiAdvancedPagesReasoningTokensAllowedBeforeTheBlock =>
      'Jetons de raisonnement autorisés avant la fermeture du bloc et le début de la réponse. Limite l\'attente pour les questions difficiles ; illimité laisse le modèle décider.';

  @override
  String get uiAdvancedPagesThinkingBudgetTokens0Unlimited =>
      'Budget de réflexion (jetons, 0 = illimité)';

  @override
  String get uiAdvancedPagesSearchAndNewsRegion =>
      'Région de recherche et d\'actualités';

  @override
  String get uiAdvancedPagesSearchResults => 'Résultats de la recherche';

  @override
  String get uiAdvancedPagesCandidatesTakenFromDuckDuckGoPerQuery =>
      'Candidats extraits de DuckDuckGo par requête.';

  @override
  String get uiAdvancedPagesPagesToRead => 'Pages à lire';

  @override
  String get uiAdvancedPagesResultPagesFetchedAndRankedFor =>
      'Pages de résultats récupérées et classées à titre de preuve. Les pages illisibles sont ignorées pour le candidat suivant. Plus est plus lent et utilise plus de contexte.';

  @override
  String get uiAdvancedPagesResearchTimeBudget => 'Budget temps de recherche';

  @override
  String get uiAdvancedPagesWallClockLimitForReadingAll =>
      'Limite d\'horloge murale pour lire toutes les pages d\'une question. Les sites lents sont coupés à la limite et la réponse continue avec ce qui a été lu.';

  @override
  String get uiAdvancedPagesModelDrivenResearchExperimental =>
      'Recherche basée sur des modèles (expérimentale)';

  @override
  String get uiAdvancedPagesModelWritesTheSearchQueries =>
      'Le modèle écrit les requêtes de recherche';

  @override
  String get uiAdvancedPagesTheLocalModelTurnsYourQuestion =>
      'Le modèle local transforme votre question en une ou deux requêtes de moteur de recherche avant la recherche. Cela coûte quelques secondes ; off envoie la question telle que saisie.';

  @override
  String get uiAdvancedPagesPassagesGivenToTheModel =>
      'Passages donnés au modèle';

  @override
  String get uiAdvancedPagesBestMatchingPassagesAbout250Tokens =>
      'Passages les mieux adaptés (environ 250 jetons chacun) sur toutes les pages lues. Plus de preuves, un pré-remplissage plus long.';

  @override
  String get uiAdvancedPagesFlagUnsupportedFigures =>
      'Signaler les chiffres non pris en charge';

  @override
  String get uiAdvancedPagesAfterAGroundedAnswerNumbersVersions =>
      'Après une réponse motivée, les numéros, versions et dates qui n\'apparaissent dans aucun passage fourni sont signalés comme non vérifiés.';

  @override
  String get supportCheckTitle => 'Vérifier les phrases par le sens';

  @override
  String get supportCheckHint =>
      'Un petit modèle (Qwen3 Reranker 0.6B) lit le passage source le plus proche avant de signaler une phrase : une phrase juste formulée autrement n\'est pas déclarée non étayée. Téléchargement séparé ; il tourne quelques secondes après une réponse tirée de sources.';

  @override
  String get uiHfSearchPageSearchHuggingFace => 'Rechercher un visage câlin';

  @override
  String get uiHfSearchPageModelNameEGQwen34B =>
      'Nom du modèle, par ex. Qwen3 4B, Phi-4, Lama 3.2';

  @override
  String get uiHfSearchPageNoGGUFRepositoriesMatch =>
      'Aucun référentiel GGUF ne correspond.';

  @override
  String get uiHfSearchPageNoSingleFileGGUFWeightsIn =>
      'Aucun poids GGUF à fichier unique dans ce référentiel.';

  @override
  String get uiHfSearchPageNotAddableHere => 'Non ajoutable ici';

  @override
  String get uiBenchmarkDialogBenchmarkCopied => 'Benchmark copié';

  @override
  String get uiBenchmarkDialogCopy => 'Copier';

  @override
  String get uiBenchmarkDialogShare => 'Partager';

  @override
  String get uiBenchmarkDialogDone => 'Terminé';

  @override
  String get uiModelReadinessPageModelReadiness => 'Préparation du modèle';

  @override
  String get uiModelReadinessPageDeviceCapacity => 'Capacité de l\'appareil';

  @override
  String get uiModelReadinessPagePhysicalRAM => 'RAM physique';

  @override
  String get uiModelReadinessPageModelStorageVolume =>
      'Volume de stockage du modèle';

  @override
  String get uiModelReadinessPageInstalledModelWeights =>
      'Poids du modèle installé';

  @override
  String get uiModelReadinessPageCurrentContextAndBackend =>
      'Contexte actuel et backend';

  @override
  String get uiModelReadinessPageModels => 'Modèles';

  @override
  String get uiModelReadinessPageRAMFitIsARoughEstimate =>
      'L\'ajustement de la RAM est une estimation approximative. La mémoire contextuelle et la vitesse réelles dépendent du modèle, du backend et de la température de l\'appareil.';

  @override
  String get uiToolsQuickPanelLetTheModelCallTools =>
      'Laissez le modèle appeler les outils';

  @override
  String get uiToolsQuickPanelTHISMODELMAYCALL => 'Ce modèle peut appeler';

  @override
  String get uiToolsQuickPanelCalculator => 'calculatrice';

  @override
  String get uiToolsQuickPanelExactArithmetic => 'Arithmétique exacte.';

  @override
  String get uiToolsQuickPanelSearchWebReadUrlFindIn =>
      'search_web · read_url · find_in_page';

  @override
  String get uiToolsQuickPanelSearchDocuments => 'search_documents';

  @override
  String get uiToolsQuickPanelToolUse => 'Utilisation des outils';

  @override
  String get uiToolsQuickPanelAuto => 'Automatique';

  @override
  String get uiToolsQuickPanelRequired => 'Obligatoire';

  @override
  String get uiAdvancedAdaptersPageLoRAAdapters => 'Adaptateurs LoRA';

  @override
  String get uiAdvancedAdaptersPageImportAdapter => 'Adaptateur d\'importation';

  @override
  String get uiAdvancedAdaptersPageDelete => 'Supprimer';

  @override
  String get uiAdvancedAppearancePageAppearance => 'Apparence';

  @override
  String get uiAdvancedAppearancePageTheme => 'Thème';

  @override
  String get uiAdvancedAppearancePageDarkIsTheDesignedDefaultLight =>
      'Sombre est la valeur par défaut conçue ; la lumière suit le téléphone si vous choisissez Système.';

  @override
  String get uiAdvancedAppearancePageAccentColour => 'Couleur d\'accentuation';

  @override
  String get uiAdvancedAppearancePageTextSize => 'Taille du texte';

  @override
  String get uiAdvancedAppearancePageCompactBubbles => 'Bulles compactes';

  @override
  String get uiAdvancedAppearancePageTighterSpacingInTheConversation =>
      'Espacement plus serré dans la conversation.';

  @override
  String get motionLabel => 'Animations';

  @override
  String get motionHint =>
      'Ressorts, commandes qui se transforment et flous doux. Le réglage Supprimer les animations du téléphone les coupe.';

  @override
  String get motionFull => 'Complètes';

  @override
  String get motionSubtle => 'Discrètes';

  @override
  String get motionOff => 'Désactivées';

  @override
  String islandLoadingModel(String model) {
    return 'Chargement de $model';
  }

  @override
  String get islandModelReady => 'Modèle prêt';

  @override
  String get islandResearchDone => 'Recherche terminée';

  @override
  String get islandAnswered => 'Réponse terminée';

  @override
  String get jumpToLatest => 'Aller au dernier message';

  @override
  String get uiAdvancedMemoryRopePageMemoryRoPESpeculation =>
      'Mémoire, RoPE et spéculation';

  @override
  String get uiAdvancedMemoryRopePageKCache => 'K-cache';

  @override
  String get uiAdvancedMemoryRopePagePrecisionOfCachedKeys =>
      'Précision des clés mises en cache';

  @override
  String get uiAdvancedMemoryRopePageVCache => 'V-cache';

  @override
  String get uiAdvancedMemoryRopePagePrecisionOfCachedValuesQuantisingV =>
      'Précision des valeurs mises en cache. La quantification de V nécessite une attention flash, qui est activée automatiquement.';

  @override
  String get uiAdvancedMemoryRopePageRoPEScaling => 'Mise à l’échelle RoPE';

  @override
  String get uiAdvancedMemoryRopePageHowPositionsBeyondTheTrainedContext =>
      'Comment les postes au-delà du contexte formé sont étendus. « Modèle » conserve ce que déclare le GGUF ; YaRN est le choix habituel pour les contextes plus longs sur les modèles qui le prennent en charge.';

  @override
  String get uiAdvancedMemoryRopePageRoPEFrequencyBase =>
      'Fréquence de base RoPE';

  @override
  String get uiAdvancedMemoryRopePageEG1000000ForModelsThat =>
      'par ex. 1000000 pour les modèles qui le documentent';

  @override
  String get uiAdvancedMemoryRopePageRoPEFrequencyScale =>
      'Échelle de fréquence RoPE';

  @override
  String get uiAdvancedMemoryRopePage0Scale1EG0 =>
      '0 < échelle ≤ 1, par ex. 0,25 pour 4 × le contexte entraîné';

  @override
  String get uiAdvancedMemoryRopePageYaRNOriginalContext =>
      'Contexte original de YaRN';

  @override
  String get uiAdvancedMemoryRopePageTheContextTheModelWasTrained =>
      'Le contexte pour lequel le modèle a été formé';

  @override
  String get uiAdvancedMemoryRopePageYaRNExtrapolationMix =>
      'Mélange d\'extrapolation YaRN';

  @override
  String get uiAdvancedMemoryRopePage0InterpolationOnly1FullExtrapolation =>
      '0 = interpolation uniquement, 1 = extrapolation complète';

  @override
  String get uiAdvancedMemoryRopePageYaRNAttentionFactor =>
      'Facteur d\'attention YaRN';

  @override
  String get uiAdvancedMemoryRopePageMagnitudeScalingUsually10 =>
      'Mise à l\'échelle de la magnitude, généralement 1,0';

  @override
  String get uiAdvancedMemoryRopePageYaRNBetaFast => 'YaRN bêta rapide';

  @override
  String get uiAdvancedMemoryRopePageLowCorrectionDimension =>
      'Faible dimension de correction';

  @override
  String get uiAdvancedMemoryRopePageYaRNBetaSlow => 'YaRN bêta lente';

  @override
  String get uiAdvancedMemoryRopePageHighCorrectionDimension =>
      'Dimension de correction élevée';

  @override
  String get uiAdvancedMemoryRopePageDraftModel => 'Projet de modèle';

  @override
  String get uiAdvancedMemoryRopePageASmallerModelWithTheSame =>
      'Un modèle plus petit avec le même vocabulaire propose plusieurs jetons ; le modèle principal les vérifie en un seul passage. Aide aux réponses longues et prévisibles ; mesurez-le - cela coûte de la mémoire et peut être plus lent.';

  @override
  String get uiAdvancedMemoryRopePageDraftTokensPerRound =>
      'Draft de jetons par tour';

  @override
  String get uiAdvancedMemoryRopePageHowManyTokensTheDraftProposes =>
      'Combien de jetons le projet propose avant vérification. Plus haut gagne plus quand le projet est bon et gaspille plus quand il est mauvais.';

  @override
  String get uiAdvancedPages2Cancel => 'Annuler';

  @override
  String get uiAdvancedPages2NotAValidValue =>
      'Ce n\'est pas une valeur valide.';

  @override
  String get uiAdvancedPages2Save => 'Enregistrer';

  @override
  String get uiAdvancedSamplingPageMoreSampling => 'Plus d\'échantillonnage';

  @override
  String get uiAdvancedSamplingPageSeed => 'Semence';

  @override
  String get uiAdvancedSamplingPageSeed0Random => 'Graine (0 = aléatoire)';

  @override
  String get uiAdvancedSamplingPageStopSequences => 'Séquences d\'arrêt';

  @override
  String get uiAdvancedSamplingPagePresencePenalty => 'Pénalité de présence';

  @override
  String get uiAdvancedSamplingPageOnceATokenHasAppearedIt =>
      'Une fois qu’un jeton est apparu, il est déconseillé, quelle que soit sa fréquence. 0 est éteint ; les négatifs encouragent la réutilisation.';

  @override
  String get uiAdvancedSamplingPageFrequencyPenalty => 'Pénalité de fréquence';

  @override
  String get uiAdvancedSamplingPageEachRepetitionAddsToThePenalty =>
      'Chaque répétition ajoute à la pénalité. 0 est éteint.';

  @override
  String get uiAdvancedSamplingPagePenaltyWindow => 'Fenêtre de pénalité';

  @override
  String get uiAdvancedSamplingPageHowManyRecentTokensTheRepetition =>
      'Sur combien de jetons récents les pénalités de répétition, de présence et de fréquence sont prises en compte. 0 les désactive.';

  @override
  String get uiAdvancedSamplingPageDRYMultiplier => 'Multiplicateur DRY';

  @override
  String get uiAdvancedSamplingPageDRYPenalisesRepeatingWholeSequencesRather =>
      'DRY pénalise la répétition de séquences entières plutôt que de jetons uniques. 0 est éteint ; 0,8 est la force habituelle.';

  @override
  String get uiAdvancedSamplingPageDRYBase => 'Base DRY';

  @override
  String get uiAdvancedSamplingPageGrowthOfThePenaltyWithThe =>
      'Augmentation de la pénalité avec la longueur répétée.';

  @override
  String get uiAdvancedSamplingPageDRYAllowedLength => 'Longueur autorisée DRY';

  @override
  String get uiAdvancedSamplingPageRepeatsShorterThanThisAreFree =>
      'Les répétitions plus courtes sont gratuites.';

  @override
  String get uiAdvancedSamplingPageTypicalP => 'Typique-P';

  @override
  String get uiAdvancedSamplingPageKeepsTokensWhoseSurpriseIsClose =>
      'Conserve les jetons dont la surprise est proche de celle attendue. 1h00 est éteint.';

  @override
  String get uiAdvancedSamplingPageXTCProbability => 'Probabilité XTC';

  @override
  String get uiAdvancedSamplingPageWithThisProbabilityTheMostLikely =>
      'Avec cette probabilité, les jetons les plus probables au-dessus du seuil sont supprimés, à l\'exception du dernier — pour une prose plus variée. 0 est éteint.';

  @override
  String get uiAdvancedSamplingPageXTCThreshold => 'Seuil XTC';

  @override
  String get uiAdvancedSamplingPageTokensAboveThisProbabilityAreCandidates =>
      'Les jetons supérieurs à cette probabilité sont candidats à la suppression.';

  @override
  String get uiAdvancedSamplingPageTopNSigma => 'Top-n-sigma';

  @override
  String get uiAdvancedSamplingPageKeepsTokensWithinNStandardDeviations =>
      'Conserve les jetons dans les n écarts types du meilleur logit ; fonctionne bien avec des températures élevées. Éteint à 0.';

  @override
  String get uiAdvancedSamplingPageResetOrder => 'Réinitialiser la commande';

  @override
  String get uiAdvancedSamplingPageOnePerLineUpTo8 =>
      'Un par ligne, jusqu\'à 8. La réponse se termine lorsqu\'elle apparaît ; il n\'est jamais montré.';

  @override
  String get uiAdvancedSamplingPageCancel => 'Annuler';

  @override
  String get uiAdvancedSamplingPageSave => 'Enregistrer';

  @override
  String get uiAdvancedStructuredOutputPageStructuredOutput =>
      'Sortie structurée';

  @override
  String get uiAdvancedStructuredOutputPageResponseFormat =>
      'Format de réponse';

  @override
  String
  get uiAdvancedStructuredOutputPageConstrainsEveryTokenTheModelProduces =>
      'Contraint chaque jeton produit par le modèle. La réflexion est désactivée pour les réponses contraintes et les outils ne sont pas proposés.';

  @override
  String get uiAdvancedStructuredOutputPageJSONSchema => 'Schéma JSON';

  @override
  String get uiAdvancedStructuredOutputPageGBNFGrammar => 'grammaire GBNF';

  @override
  String get uiAdvancedStructuredOutputPageCancel => 'Annuler';

  @override
  String get uiAdvancedStructuredOutputPageSave => 'Enregistrer';

  @override
  String get uiAdvancedToolsPageTools => 'Outils';

  @override
  String get uiAdvancedToolsPageLetTheModelCallTools =>
      'Laissez le modèle appeler les outils';

  @override
  String get uiAdvancedToolsPageTheModelCanDecideToSearch =>
      'Le modèle peut décider de rechercher sur le web, lire une page, rechercher vos documents ou calculer, puis répondre à partir des résultats. Chaque outil reste derrière sa propre autorisation ci-dessous.';

  @override
  String get uiAdvancedToolsPageToolUse => 'Utilisation des outils';

  @override
  String get uiAdvancedToolsPageAutoLetsTheModelDecideWhether =>
      'Auto permet au modèle de décider si un outil est nécessaire. Requis lui fait en appeler un avant sa première réponse (les tours ultérieurs dépendent à nouveau) : utilisez-le lorsque le modèle continue de répondre à partir de la mémoire au lieu de chercher.';

  @override
  String get uiAdvancedToolsPageRoundsPerAnswer => 'Tours par réponse';

  @override
  String get uiAdvancedToolsPageHowManyTimesTheModelMay =>
      'Combien de fois le modèle peut appeler les outils avant de devoir répondre. Chaque tour est une autre passe de modèle.';

  @override
  String get uiAdvancedToolsPageCalculator => 'calculatrice';

  @override
  String get uiAdvancedToolsPageExactArithmeticNoPermissionNeeded =>
      'Arithmétique exacte. Aucune autorisation nécessaire.';

  @override
  String get uiAdvancedToolsPageSearchWebReadUrlFindIn =>
      'search_web · read_url · find_in_page';

  @override
  String get uiAdvancedToolsPageSearchDocuments => 'search_documents';

  @override
  String get uiEffectiveSettingsPageEffectiveSettings => 'Paramètres efficaces';

  @override
  String get uiEffectiveSettingsPageAppliesWhenTheModelLoads =>
      'S\'applique lors du chargement du modèle.';

  @override
  String get uiEffectiveSettingsPageClose => 'Fermer';

  @override
  String get uiKnowledgePageOK => 'D\'accord';

  @override
  String get uiKnowledgePageVerifying => 'Vérification…';

  @override
  String get uiMemoryPageEGTheUserIsA =>
      'par ex. L\'utilisateur est une infirmière à Lisbonne et préfère les unités métriques.';

  @override
  String get uiOverridesPageClearAll => 'Tout effacer';

  @override
  String get uiOverridesPageInherit => 'Hériter';

  @override
  String get uiOverridesPageOn => 'Sur';

  @override
  String get uiOverridesPageOff => 'Désactivé';

  @override
  String get uiOverridesPageCancel => 'Annuler';

  @override
  String get uiOverridesPageNotAValidValue =>
      'Ce n\'est pas une valeur valide.';

  @override
  String get uiOverridesPageSave => 'Enregistrer';

  @override
  String get uiRemoteServerPageUseRemoteServer => 'Utiliser un serveur distant';

  @override
  String get uiRemoteServerPageNoConnectionsYet =>
      'Aucune connexion pour l\'instant';

  @override
  String get uiRemoteServerPageAddOneToChooseAProvider =>
      'Ajoutez-en un pour choisir un fournisseur, une URL, une clé API et un modèle.';

  @override
  String get uiRemoteServerPageEditConnection => 'Modifier la connexion';

  @override
  String get uiRemoteServerPageWebResearch => 'Recherche sur le Web';

  @override
  String get uiRemoteServerPageTheAppSearchesDuckDuckGoAndReads =>
      'Le modèle à distance décide si une question demande le web, écrit ses propres recherches et choisit les pages à lire ; l\'application les lance sur DuckDuckGo et Wikipédia sans clé.';

  @override
  String get uiRemoteServerPageImageUnderstanding => 'Compréhension des images';

  @override
  String get uiRemoteServerPageSendAttachedImagesToTheModel =>
      'Envoyez les images jointes au modèle. Activer uniquement pour un modèle compatible avec la vision.';

  @override
  String get uiRemoteServerPageDocumentUnderstanding =>
      'Compréhension des documents';

  @override
  String get uiRemoteServerPageExtractDocumentsSafelyOnThePhone =>
      'Extrayez des documents en toute sécurité sur le téléphone, puis envoyez leur texte dans l\'invite. Les fichiers originaux ne sont pas téléchargés.';

  @override
  String get uiRemoteServerPageStreamingIdleTimeout =>
      'Délai d\'inactivité du streaming';

  @override
  String get uiRemoteServerPageHowLongToWaitBetweenResponse =>
      'Combien de temps attendre entre les morceaux de réponse d\'un serveur lent ou très chargé.';

  @override
  String get uiRemoteServerPageChooseAProvider => 'Choisissez un fournisseur';

  @override
  String get uiSettingsScreenEncryptedBackup => 'Sauvegarde cryptée';

  @override
  String get uiSettingsScreenMoreSampling => 'Plus d\'échantillonnage';

  @override
  String get uiSettingsScreenMemoryRoPESpeculation =>
      'Mémoire, RoPE et spéculation';

  @override
  String get uiSettingsScreenStructuredOutput => 'Sortie structurée';

  @override
  String get uiSettingsScreenTools => 'Outils';

  @override
  String get uiSettingsScreenLoRAAdapters => 'Adaptateurs LoRA';

  @override
  String get uiSettingsScreenEffectiveSettings => 'Paramètres efficaces';

  @override
  String get uiSettingsScreenAppearance => 'Apparence';

  @override
  String get uiMetricsSheetInstrumentPanel => 'Tableau de bord';

  @override
  String get uiMetricsSheetDisplay => 'Affichage';

  @override
  String get uiMetricsSheetBenchmarkThisModel => 'Comparez ce modèle';

  @override
  String get uiMetricsSheetMeasuredOnThisDeviceNothingIs =>
      'Mesuré sur cet appareil. Rien n\'est transmis.';

  @override
  String get uiMetricsSheetSendAMessageToSeeLive =>
      'Envoyez un message pour voir les numéros en direct.';

  @override
  String get uiMetricsSheetBackend => 'Back-end';

  @override
  String get uiMetricsSheetNativeLibrary => 'Bibliothèque native';

  @override
  String get uiMetricsSheetStages => 'Étapes';

  @override
  String get uiMetricsSheetTokensSec => 'Jetons/s';

  @override
  String get uiMetricsSheetFirstToken => 'Premier jeton';

  @override
  String get uiMetricsSheetTokens => 'Jetons';

  @override
  String get uiMetricsSheetContext => 'Contexte';

  @override
  String get uiMetricsSheetPeakRSS => 'Pic RSS';

  @override
  String get uiMetricsSheetTemplate => 'Modèle';

  @override
  String get uiMetricsSheetThinking => 'Penser';

  @override
  String get uiMetricsSheetModel => 'Modèle';

  @override
  String get uiSettingsWidgetsCancel => 'Annuler';

  @override
  String get uiSettingsWidgetsApply => 'Postuler';

  @override
  String get uiPresetSheet00Exact => '0,0 · exact';

  @override
  String get uiPresetSheet03Focused => '0,3 · concentré';

  @override
  String get uiPresetSheet07Balanced => '0,7 · équilibré';

  @override
  String get uiPresetSheet10Creative => '1.0 · créatif';

  @override
  String get uiModelsScreenHttpsHuggingfaceCo => 'https://huggingface.co/…';

  @override
  String get uiModelsScreenModelReadiness => 'Préparation du modèle';

  @override
  String get uiModelsScreenImportConfiguration => 'Importer la configuration';

  @override
  String get uiModelsScreenImportConfigurationFromClipboard =>
      'Importer la configuration depuis le presse-papiers';

  @override
  String get uiModelsScreenImportConfigurationFromAFile =>
      'Importer la configuration à partir d\'un fichier';

  @override
  String get uiModelsScreenShareOrImportAConfiguration =>
      'Partager ou importer une configuration';

  @override
  String get uiModelsScreenShareConfiguration => 'Partager la configuration';

  @override
  String get uiModelsScreenCopyAsText => 'Copier sous forme de texte';

  @override
  String get uiModelsScreenImportFromClipboard =>
      'Importer depuis le presse-papiers';

  @override
  String get uiModelsScreenImportFromAFile => 'Importer à partir d\'un fichier';

  @override
  String get uiModelCardRemoveFromList => 'Supprimer de la liste';

  @override
  String get uiModelPickerSheetRemoteConnections => 'Connexions à distance';

  @override
  String get uiModelPickerSheetAnswersComeFromTheConnectionInstead =>
      'Les réponses proviennent de la connexion au lieu d\'un modèle sur ce téléphone.';

  @override
  String get uiQrViewQRCodeWithTheConnectionDetails =>
      'Code QR avec les détails de connexion';

  @override
  String get uiChatScreenActionsTitle => 'Titre';

  @override
  String get uiChatScreenActionsDocumentType => 'Type de document';

  @override
  String get uiChatScreenActionsWordDocx => 'Mot (.docx)';

  @override
  String get uiChatScreenActionsPDF => 'PDF';

  @override
  String get uiChatScreenActionsPlainTextTxt => 'Texte brut (.txt)';

  @override
  String get uiChatScreenActionsMarkdownMd => 'Démarquage (.md)';

  @override
  String get uiChatScreenActionsHTML => 'HTML';

  @override
  String get uiChatScreenActionsSelectIndividualMessages =>
      'Sélectionnez des messages individuels';

  @override
  String get uiChatScreenActionsRedactTermsCommaSeparated =>
      'Expurger les termes (séparés par des virgules)';

  @override
  String get uiChatScreenActionsChooseMessages => 'Choisissez des messages';

  @override
  String get uiChatScreenActionsUseSelection => 'Utiliser la sélection';

  @override
  String get uiChatScreenActionsReviewDocument => 'Document de révision';

  @override
  String get uiChatBubbleChooseQuestionVersion =>
      'Choisir la version de la question';

  @override
  String get uiChatBubbleSources => 'Sources';

  @override
  String get uiChatBubbleKnowledgeLibrary => 'Bibliothèque de connaissances';

  @override
  String get uiChatBubbleSponsoredNotUsed => 'Sponsorisé (non utilisé)';

  @override
  String get uiChatBubbleOpenInBrowser => 'Ouvrir dans le navigateur';

  @override
  String get uiCodeBlockCopyCode => 'Copier le code';

  @override
  String get uiCodeBlockCodeCopied => 'Code copié';

  @override
  String get readinessUnavailable => 'Indisponible sur cet appareil';

  @override
  String readinessMemory(Object total, Object available) {
    return '$total au total · $available disponibles';
  }

  @override
  String readinessStorage(Object free, Object total) {
    return '$free libres sur $total';
  }

  @override
  String readinessInstalledWeights(Object size, Object count) {
    return '$size pour $count modèles';
  }

  @override
  String readinessContext(Object count, Object backend) {
    return '$count jetons · $backend';
  }

  @override
  String get readinessInstalled => 'Installé';

  @override
  String readinessDownload(Object size) {
    return 'Télécharger : $size';
  }

  @override
  String get readinessRamFits => 'Estimation RAM : devrait tenir';

  @override
  String get readinessRamMayNotFit => 'Estimation RAM : pourrait ne pas tenir';

  @override
  String get readinessDiskAvailable => 'Espace disque disponible';

  @override
  String get readinessDiskInsufficient => 'Espace disque peut-être insuffisant';

  @override
  String readinessMeasured(Object speed) {
    return 'Mesuré : $speed jetons/s';
  }

  @override
  String benchmarkFailed(Object error) {
    return 'Échec du banc d’essai : $error';
  }

  @override
  String benchmarkRunning(Object model, Object runs) {
    return 'Test de $model…\nChargement, puis $runs essais avec un préremplissage d’environ 380 jetons et 128 jetons déterministes (premier essai écarté, médianes affichées), puis une discussion avec l’invite système de l’app, avec et sans les outils.';
  }

  @override
  String get hfIntro =>
      'Dépôts GGUF publics uniquement, classés par nombre de téléchargements. Chaque fichier est lié à une révision et vérifié par le SHA-256 du Hub. Les projecteurs de vision (mmproj) et les fichiers divisés sont visibles, mais ne peuvent pas encore être ajoutés.';

  @override
  String hfAdded(Object model, Object size, Object template) {
    return '$model ajouté · $size · modèle $template';
  }

  @override
  String get hfFromMetadata => 'des métadonnées';

  @override
  String hfRepoStats(Object downloads, Object likes) {
    return '$downloads téléchargements · $likes mentions J’aime';
  }

  @override
  String get hfInLibrary => 'dans la bibliothèque';

  @override
  String hfLicenseRevision(Object license, Object revision) {
    return 'Licence : $license · révision $revision';
  }

  @override
  String get hfVisionProjector => 'projecteur de vision';

  @override
  String get hfSplitFile => 'fichier divisé';

  @override
  String remoteDeleteHint(Object name) {
    return '« $name » et sa clé API seront supprimés de ce téléphone.';
  }

  @override
  String get remoteOwnServer => 'Un serveur sur votre propre appareil.';

  @override
  String get remoteHostedBilling => 'API hébergée facturée à votre clé.';

  @override
  String get remoteNameHelp => 'Nom affiché pour cette connexion.';

  @override
  String remoteOwnUrlHelp(Object path) {
    return 'LM Studio : port 1234 · Ollama : 11434 · llama-server : 8080. « $path » est ajouté automatiquement.';
  }

  @override
  String remoteHostedUrlHelp(Object provider) {
    return 'Prérempli pour $provider ; ne le modifiez que pour un proxy ou un point d’accès régional.';
  }

  @override
  String get remoteInvalidUrl => 'Entrez une URL http(s).';

  @override
  String get remoteApiKey => 'Clé API';

  @override
  String get remoteApiKeyOptional => 'Clé API (facultative)';

  @override
  String remoteKeyHostedHelp(Object provider) {
    return 'Stockée dans le trousseau Android ; envoyée uniquement à $provider.';
  }

  @override
  String get remoteKeySelfHelp =>
      'Uniquement si le serveur a été lancé avec une clé. Stockée dans le trousseau Android.';

  @override
  String get remoteHideKey => 'Masquer la clé';

  @override
  String get remoteShowKey => 'Afficher la clé';

  @override
  String get remoteServerDefaultModel =>
      'Laisser vide pour utiliser le modèle par défaut du serveur';

  @override
  String get remoteModelId => 'Identifiant du modèle';

  @override
  String get remoteModelListHelp =>
      'Testez la connexion pour choisir parmi les modèles proposés.';

  @override
  String get remoteModelManualHelp =>
      'Ce fournisseur ne fournit pas de liste de modèles ; saisissez l’identifiant indiqué dans sa documentation.';

  @override
  String get remoteTestList => 'Tester et lister les modèles';

  @override
  String get remoteTestConnection => 'Tester la connexion';

  @override
  String get remoteExtraHeadersHelp =>
      'Une ligne « Nom : valeur » par en-tête, envoyée avec chaque requête. L’en-tête de la clé est ajouté automatiquement.';

  @override
  String get remoteConnectedNoList =>
      'Connecté. Ce fournisseur ne fournit pas de liste de modèles ; saisissez leur identifiant.';

  @override
  String get remoteConnectedServerNoModels =>
      'Connecté, mais le serveur ne liste aucun modèle. Chargez-en un dans LM Studio ou démarrez-en un dans Ollama.';

  @override
  String get remoteConnectedNoModels =>
      'Connecté, mais aucun modèle n’est disponible pour cette clé.';

  @override
  String get remoteCapabilities => 'Capacités';

  @override
  String get remoteRequestLimits => 'Limites de requêtes';

  @override
  String get remoteAdvanced => 'Avancé';

  @override
  String get remoteAnthropicNote =>
      'Anthropic : le mode réflexion active la réflexion adaptative avec résumés ; la température et top-p ne sont pas envoyés car les modèles actuels les refusent. Les appels d’outils, images et schémas JSON sont pris en charge.';

  @override
  String get remoteGeminiNote =>
      'Gemini : le mode réflexion affiche des résumés ; les appels de fonctions, images et sorties JSON sont pris en charge. Les signatures d’appels sont conservées pendant la session.';

  @override
  String get remoteSelfHostedNote =>
      'Connectez-vous uniquement à des machines que vous contrôlez. La confidentialité dépend du réseau : utilisez HTTPS ou un VPN sur Internet.';

  @override
  String remoteHostedNote(Object provider) {
    return 'Les requêtes sont facturées à votre compte $provider. Fixez une limite quotidienne si vous partagez cette clé avec d’autres applications.';
  }

  @override
  String get remoteNoTools => 'aucun';

  @override
  String remoteToolsDetected(Object tools) {
    return ' Outils du serveur détectés : $tools ; ils ne sont pas exécutés automatiquement.';
  }

  @override
  String remoteContextWindow(Object count) {
    return ' Fenêtre de contexte : $count jetons.';
  }

  @override
  String remoteAdvertises(
    Object model,
    Object capabilities,
    Object context,
    Object tools,
  ) {
    return '$model annonce : $capabilities.$context$tools';
  }

  @override
  String remoteContextOnly(Object model, Object count, Object tools) {
    return '$model : fenêtre de contexte de $count jetons.$tools';
  }

  @override
  String remoteNoCapabilities(Object tools) {
    return 'Ce fournisseur ne précise pas les capacités du modèle choisi. Ajustez les options de la page précédente selon le modèle utilisé.$tools';
  }

  @override
  String get remoteDefaultModel => 'le modèle par défaut';

  @override
  String remoteCapsHint(Object model) {
    return 'Limites pour $model sur cette connexion. L’application refuse les requêtes après la limite ; chaque tour d’outil compte comme une requête. Un champ vide signifie aucune limite.';
  }

  @override
  String remoteUsed(Object minute, Object day) {
    return 'Utilisé : $minute cette minute · $day aujourd’hui';
  }

  @override
  String remoteOtherCaps(Object models) {
    return 'Autres modèles avec limites ici : $models.';
  }

  @override
  String scheduleLoadFailed(Object error) {
    return 'Impossible de charger les rappels programmés : $error';
  }

  @override
  String get noticeCheckingSearch =>
      'Vérification : faut-il chercher sur le web…';

  @override
  String get noticeResearchingTools => 'Recherche avec les outils…';

  @override
  String get noticeNamingChat => 'Choix du titre de la conversation…';

  @override
  String get noticeSearchingAgain =>
      'Nouvelle recherche pour ce qui manque encore…';

  @override
  String get noticeFollowUpSearch =>
      'Les pages déjà lues ne répondent pas à cela. Nouvelle recherche…';

  @override
  String answerSourcesDated(String date) {
    return 'Sources mises à jour le $date.';
  }

  @override
  String get answerSourcesUndated =>
      'Les sources n\'indiquent pas quand elles ont été mises à jour.';

  @override
  String sourceUpdated(String date) {
    return 'mis à jour $date';
  }

  @override
  String get thinkOnSearchSetting =>
      'Réfléchir avant de répondre avec des sources';

  @override
  String get thinkOnSearchHint =>
      'Un modèle capable de raisonner pèse d\'abord les pages (jusqu\'à environ 1 000 jetons), même si le mode réflexion est désactivé.';

  @override
  String get searchAgainSetting =>
      'Chercher à nouveau si les pages ne suffisent pas';

  @override
  String get searchAgainHint =>
      'Quand les pages lues laissent une partie de la question sans réponse, une recherche de plus et jusqu\'à deux pages de plus.';

  @override
  String get wikipediaLookupSetting => 'Ajouter l\'article Wikipédia';

  @override
  String get wikipediaLookupHint =>
      'L\'article Wikipédia sur le sujet rejoint les sources, dans la langue de la question, quand il correspond.';

  @override
  String get zimSetting => 'Wikipédia hors ligne';

  @override
  String get zimHint =>
      'Importez un fichier Kiwix .zim (sur library.kiwix.org) pour répondre depuis Wikipédia sans connexion.';

  @override
  String get zimImport => 'Importer';

  @override
  String get zimRemove => 'Supprimer';

  @override
  String zimImporting(String percent) {
    return 'Copie… $percent';
  }

  @override
  String get zimNotAZim => 'Ce fichier n\'est pas un fichier .zim.';

  @override
  String get autoTitlesSetting => 'Nommer les conversations automatiquement';

  @override
  String get autoTitlesHint =>
      'Après la première réponse, le modèle donne un titre court à la conversation. Désactivé : le premier message sert de titre.';

  @override
  String get webModeNote =>
      'Le mode de recherche web (Désactivé / Auto / Toujours) se règle sur l\'écran principal des réglages ou dans la pastille du champ de saisie.';

  @override
  String get thinkingBudgetUnlimited => 'Illimité';

  @override
  String get adapterImporting => 'Vérification et copie de l\'adaptateur…';

  @override
  String get adapterEmpty =>
      'Aucun adaptateur pour l\'instant. Importez un GGUF LoRA (créé avec convert_lora_to_gguf.py de llama.cpp) avec +, puis associez-le à un modèle de la même architecture. Le modèle est rechargé avec l\'adaptateur appliqué à l\'échelle choisie.';

  @override
  String get versionPrevious => 'Version précédente';

  @override
  String get versionNext => 'Version suivante';

  @override
  String get sourceFallbackTitle => 'Source';

  @override
  String sourcePublished(String date) {
    return 'publié $date';
  }

  @override
  String get sourceReadEarlier => 'lu plus tôt';

  @override
  String get sourceMayBeOutdated => 'peut être dépassé';

  @override
  String get sourceSponsored => 'Résultat sponsorisé';

  @override
  String get sourceSponsoredDetail =>
      'Résultat sponsorisé · affiché par transparence · ni lu ni donné au modèle comme preuve';

  @override
  String sourceNewsStory(String outlet) {
    return 'Article d\'actualité · $outlet';
  }

  @override
  String get sourceNewsGiven =>
      'le titre et le résumé ci-dessous ont été donnés au modèle';

  @override
  String get sourcePageRead => 'Page lue';

  @override
  String get sourceKeptCopy =>
      'copie conservée, le site était injoignable ; peut être dépassée';

  @override
  String get sourcePassagesGiven =>
      'les passages ci-dessous ont été donnés au modèle';

  @override
  String sourceReadFailed(String error) {
    return 'La page n\'a pas pu être lue ($error) · seul l\'extrait de recherche était disponible';
  }

  @override
  String get sourceSnippetOnly =>
      'Extrait de recherche seulement · la page n\'a pas été lue';

  @override
  String get sourceHeadlineOnly =>
      'Titre et résumé seulement · article indisponible';

  @override
  String get sourceExtractedSection =>
      'Passages extraits · vérifiez le texte cité';

  @override
  String sourceArchiveSnapshot(String date, String language) {
    return 'Archive hors ligne · $date · $language';
  }

  @override
  String get sourceOfflineLimitation =>
      'Cette archive ne peut pas vérifier les faits actuels ou changeants.';

  @override
  String get sourceArchiveUnavailable =>
      'L\'archive d\'origine est indisponible. Voici l\'extrait enregistré.';

  @override
  String get sourceNoText => 'Aucun texte.';

  @override
  String get sourceGivenHeading => 'Ce que le modèle a reçu';

  @override
  String sourcePassageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count extraits',
      one: '1 extrait',
    );
    return '$_temp0';
  }

  @override
  String sourceReadAt(String time) {
    return 'Lu le $time';
  }

  @override
  String get sourceOpenArchived => 'Ouvrir l\'article hors ligne';

  @override
  String get sourceCopyLink => 'Copier le lien';

  @override
  String get sourceLinkCopied => 'Lien copié';

  @override
  String get sourceAddress => 'Adresse complète';

  @override
  String sourceFromKnowledge(String title) {
    return 'De votre bibliothèque de connaissances ($title).';
  }

  @override
  String get fitFits => 'Tient sur ce téléphone';

  @override
  String get fitTight => 'Juste en mémoire vive';

  @override
  String get fitTooLarge => 'Trop gros pour ce téléphone';

  @override
  String get configApplyNote =>
      'Appliquer remplace le profil de ce modèle. La recherche web et le matériel restent tels que vous les avez réglés.';

  @override
  String configApplied(String model) {
    return 'Appliqué à $model. Prend effet à la prochaine réponse.';
  }

  @override
  String get storageUnavailable => 'Indisponible sur cet appareil';

  @override
  String modelProfileTitle(String model) {
    return 'Profil de $model';
  }

  @override
  String get modelProfileScope => 'Profil du modèle';

  @override
  String conversationsLoadFailed(String error) {
    return 'Impossible de charger les conversations.\n$error';
  }

  @override
  String get adapterUnknownArchitecture => 'architecture inconnue';

  @override
  String adapterAppliedAt(String scale) {
    return 'Appliqué à l\'échelle $scale';
  }

  @override
  String get adapterNotApplied => 'Non appliqué';

  @override
  String get noticeUpdatingMemory => 'Mise à jour de la mémoire…';

  @override
  String noticeWeatherLoading(String place) {
    return 'Météo pour $place depuis DuckDuckGo…';
  }

  @override
  String noticeWeatherDone(String place) {
    return 'Météo pour $place depuis DuckDuckGo (Apple WeatherKit).';
  }

  @override
  String get noticeCollectingNews => 'Collecte des dernières nouvelles…';

  @override
  String get noticeWebOffUnverified =>
      'La recherche web est désactivée. Les informations actuelles n’ont pas été vérifiées.';

  @override
  String get noticeOpeningStory => 'Ouverture de cet article…';

  @override
  String get noticeStopping => 'Arrêt…';

  @override
  String get noticeSearching => 'Recherche sur DuckDuckGo…';

  @override
  String get noticeCheckingWikipedia => 'Vérification sur Wikipédia…';

  @override
  String noticeRecallArticle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources antérieures',
      one: '1 source antérieure',
    );
    return 'Article de cette nouvelle lu, plus $_temp0 de cette conversation.';
  }

  @override
  String noticeRecallPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages déjà lues',
      one: '1 page déjà lue',
    );
    return 'Réponse à partir de $_temp0 dans cette conversation.';
  }

  @override
  String get noticeImageRemoteOff =>
      'L’envoi d’images est désactivé pour le serveur distant. Activez-le dans les réglages du serveur distant si le modèle choisi gère la vision.';

  @override
  String get noticeImageNoVision =>
      'Ce modèle ne peut pas voir les photos. Ajoutez son fichier de vision dans Modèles, ou choisissez un modèle de vision.';

  @override
  String noticeKnowledgeDocs(int count, String collection) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documents',
      one: '1 document',
    );
    return '$_temp0 de « $collection »';
  }

  @override
  String noticePlusWebResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count résultats web',
      one: '1 résultat web',
    );
    return ' et $_temp0';
  }

  @override
  String noticeUsingTool(String tool, String args) {
    return 'Utilisation de $tool$args…';
  }

  @override
  String get noticeStopped =>
      'Génération arrêtée. La réponse partielle a été conservée.';

  @override
  String noticeTrimmed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages antérieurs ont été omis',
      one: '1 message antérieur a été omis',
    );
    return '$_temp0 du contexte du modèle ; ils restent dans votre historique.';
  }

  @override
  String noticeTokenLimit(int count) {
    return 'La réponse s’est arrêtée à la limite de $count jetons. Touchez Continuer, ou augmentez Jetons max dans Réglages > Échantillonnage.';
  }

  @override
  String get noticeStopSequence =>
      'La réponse s’est terminée sur une séquence d’arrêt.';

  @override
  String get noticeResearchSkipped =>
      'Le modèle a répondu sans chercher : rien n’a été vérifié pour cette réponse. Régénérez, ou désactivez la recherche pilotée par le modèle pour utiliser la recherche fixe.';

  @override
  String get noticeNoSourcesWebOff =>
      'La recherche web est désactivée, le modèle n’avait donc aucune source. Touchez la pastille Local pour l’activer.';

  @override
  String get noticeNoSourcesNoSearch =>
      'Aucune recherche n’a été faite pour ce message, le modèle n’avait donc aucune source. Passez la pastille à Web · toujours, ou demandez « cherche … ».';

  @override
  String noticeStoriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nouvelles',
      one: '1 nouvelle',
    );
    return '$_temp0';
  }

  @override
  String noticeOutletsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count médias',
      one: '1 média',
    );
    return '$_temp0';
  }

  @override
  String noticeArticlesRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles lus',
      one: '1 article lu',
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
    return '$stories de $outlets$articles en $seconds s.';
  }

  @override
  String get noticeLinkUnreadable => 'La page liée n’a pas pu être lue.';

  @override
  String get noticeNoWebResults =>
      'Aucun résultat web. Les informations actuelles n’ont pas pu être vérifiées.';

  @override
  String noticeLinkedRead(int read, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total pages liées',
      one: '1 page liée',
    );
    return '$read sur $_temp0 lue(s).';
  }

  @override
  String noticePagesRead(int read, int results, String queries) {
    String _temp0 = intl.Intl.pluralLogic(
      read,
      locale: localeName,
      other: '$read pages lues',
      one: '1 page lue',
    );
    return '$_temp0 sur $results résultats$queries.';
  }

  @override
  String noticeQueries(int count) {
    return ' ($count requêtes)';
  }

  @override
  String get noticeEvidenceNoFit =>
      'Les sources web ne tiennent pas dans le contexte. Augmentez le contexte ou réduisez la longueur de réponse.';

  @override
  String noticeWaitingServer(String client) {
    return 'Attente de la fin d’une requête de $client sur le serveur de l’appareil…';
  }

  @override
  String noticeReadingPage(int n, int limit, String host) {
    return 'Lecture $n sur $limit$host…';
  }

  @override
  String noticeToolCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coupes',
      one: '1 coupe',
    );
    return 'Des résultats d’outils ont été raccourcis pour tenir dans le contexte ($_temp0). Augmentez la taille du contexte ou réduisez le budget de sortie par outil.';
  }

  @override
  String noticeDocCut(int percent) {
    return 'Le texte joint a été raccourci pour tenir dans le contexte ($percent % conservé). Augmentez la taille du contexte pour le fichier entier.';
  }

  @override
  String noticeRefusal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources ont été fournies',
      one: '1 source a été fournie',
    );
    return 'Le modèle dit ne pas pouvoir naviguer alors que $_temp0. Régénérez, ou essayez un autre modèle.';
  }

  @override
  String noticeNoCitations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources fournies',
      one: '1 source fournie',
    );
    return 'La réponse ne cite aucune des $_temp0 ; considérez-la comme non vérifiée.';
  }

  @override
  String noticeBogusCitations(String cited, int count) {
    return 'La réponse cite la source $cited, qui n’a pas été fournie ; seules [1]–[$count] existent.';
  }

  @override
  String noticeFigures(String figures, String more) {
    return 'Introuvable dans les sources : $figures$more. Considérez ces chiffres comme non vérifiés.';
  }

  @override
  String noticeFiguresMiscited(String figures, String more) {
    return 'Absent de la source citée : $figures$more. Une autre source les donne ; vérifiez la citation.';
  }

  @override
  String get noticeCitationsMatched =>
      'Le modèle n’a cité aucune source ; les renvois [n] ont été rattachés aux sources d’après leurs mots et leurs chiffres.';

  @override
  String noticeAndMore(int count) {
    return ' et $count de plus';
  }

  @override
  String get searchChallenge =>
      'DuckDuckGo a demandé une vérification anti-robot : la recherche automatique est suspendue une minute. Les liens collés fonctionnent toujours.';

  @override
  String searchCooldown(int seconds) {
    return 'La recherche est suspendue après un blocage de DuckDuckGo ; reprise dans $seconds s. Les liens collés fonctionnent toujours.';
  }

  @override
  String get searchRateLimit =>
      'DuckDuckGo limite le nombre de recherches ; pause d’une minute. Les liens collés fonctionnent toujours.';

  @override
  String get searchMarkup =>
      'DuckDuckGo a modifié sa page de résultats, qui n’a pas pu être analysée. Les liens collés fonctionnent toujours ; une mise à jour de l’app est nécessaire pour la recherche.';

  @override
  String get searchUnavailable =>
      'Recherche web indisponible (pas de connexion ou DuckDuckGo injoignable). Les informations actuelles n’ont pas pu être vérifiées.';

  @override
  String noticeThrottle(int drop, String from, String to) {
    return 'La vitesse a baissé de $drop % ($from → $to jetons/s). Le téléphone ralentit peut-être pour limiter la chauffe ; essayez un contexte plus court, moins de couches GPU ou un modèle plus petit.';
  }

  @override
  String get outputGrammarCut =>
      'La sortie contrainte par la grammaire a été coupée à la limite de jetons.';

  @override
  String get outputSchemaMismatch =>
      'La sortie est du JSON valide, mais pas l’objet demandé par le schéma.';

  @override
  String outputJsonCut(int count) {
    return 'La sortie JSON a été coupée à la limite de $count jetons et n’est pas lisible. Augmentez Jetons max.';
  }

  @override
  String get outputNotJson => 'La sortie n’est pas du JSON valide.';

  @override
  String noticeBatterySaver(String reason, int tokens) {
    return 'Économie de batterie ($reason) : pas de réflexion, réponses de $tokens jetons au plus, moins de pages lues.';
  }

  @override
  String saverReasonBattery(int level) {
    return 'batterie $level %';
  }

  @override
  String saverReasonHot(String label) {
    return 'téléphone chaud : $label';
  }

  @override
  String newsCollecting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éditeurs',
      one: '1 éditeur',
    );
    return 'Collecte des nouvelles du jour sur DuckDuckGo News et chez $_temp0…';
  }

  @override
  String newsReadingArticles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles',
      one: '1 article',
    );
    return 'Lecture de $_temp0…';
  }

  @override
  String get chatErrorNoModel =>
      'Ajoutez un modèle dans l’onglet Modèles, puis envoyez votre message.';

  @override
  String chatErrorSave(String error) {
    return 'Impossible d’enregistrer la réponse : $error. Copiez la réponse avant de quitter cette conversation.';
  }

  @override
  String get chatErrorNoText =>
      'Le modèle n’a produit aucun texte. Essayez un autre modèle de chat ou un autre modèle.';

  @override
  String chatErrorServing(String model) {
    return 'Ce téléphone sert $model à un autre appareil. Arrêtez le serveur de l’appareil (Réglages) pour discuter avec un autre modèle.';
  }

  @override
  String chatErrorServerBusy(String client) {
    return 'Le serveur de l’appareil répond encore à $client. Réessayez quand il aura terminé.';
  }

  @override
  String get settingGroupGeneration => 'Génération';

  @override
  String get settingGroupReasoning => 'Raisonnement';

  @override
  String get settingGroupWeb => 'Recherche web';

  @override
  String get settingGroupTools => 'Outils';

  @override
  String get settingGroupOutput => 'Sortie structurée';

  @override
  String get settingGroupContext => 'Contexte';

  @override
  String get settingGroupHardware => 'Matériel';

  @override
  String get settingGroupPrompt => 'Invite';

  @override
  String get settingLabelSystemPrompt => 'Instructions personnalisées';

  @override
  String get settingLabelTemperature => 'Température';

  @override
  String get settingLabelTopP => 'Top-P';

  @override
  String get settingLabelMinP => 'Min-P';

  @override
  String get settingLabelTopK => 'Top-K';

  @override
  String get settingLabelTypicalP => 'Typical-P';

  @override
  String get settingLabelRepetitionPenalty => 'Pénalité de répétition';

  @override
  String get settingLabelPresencePenalty => 'Pénalité de présence';

  @override
  String get settingLabelFrequencyPenalty => 'Pénalité de fréquence';

  @override
  String get settingLabelRepeatLastN => 'Fenêtre de pénalité (jetons)';

  @override
  String get settingLabelMaxTokens => 'Jetons max';

  @override
  String get settingLabelSeed => 'Graine (0 = aléatoire)';

  @override
  String get settingLabelStopSequences => 'Séquences d’arrêt';

  @override
  String get settingLabelThinkingModeEnabled => 'Mode réflexion';

  @override
  String get settingLabelThinkingBudgetTokens =>
      'Budget de réflexion (0 = illimité)';

  @override
  String get settingLabelWebMode => 'Recherche web';

  @override
  String get settingLabelResearchLoop => 'Recherche pilotée par le modèle';

  @override
  String get settingLabelMaxPagesRead => 'Pages à lire';

  @override
  String get settingLabelEvidencePassages => 'Passages fournis au modèle';

  @override
  String get settingLabelKnowledgeCollection => 'Collection de connaissances';

  @override
  String get settingLabelToolsEnabled => 'Appel d’outils';

  @override
  String get settingLabelToolChoice => 'Utilisation des outils';

  @override
  String get settingLabelToolMaxRounds => 'Tours d’outils par réponse';

  @override
  String get settingLabelResponseFormat => 'Format de réponse';

  @override
  String get settingLabelJsonSchema => 'Schéma JSON';

  @override
  String get settingLabelGrammar => 'Grammaire GBNF';

  @override
  String get settingLabelContextSize => 'Taille du contexte';

  @override
  String get settingLabelPromptCache => 'Garder la conversation en contexte';

  @override
  String get settingLabelBackend => 'Moteur de calcul';

  @override
  String get settingLabelNGpuLayers => 'Couches GPU';

  @override
  String get settingLabelCpuThreads => 'Threads CPU (décodage, 0 = auto)';

  @override
  String get settingLabelBatchThreads =>
      'Threads CPU (préremplissage, 0 = auto)';

  @override
  String get settingLabelFlashAttention => 'Flash attention';

  @override
  String get settingLabelKvCacheType => 'Type de cache K';

  @override
  String get settingLabelVCacheType => 'Type de cache V (vide = comme K)';

  @override
  String get settingLabelRopeScaling => 'Mise à l’échelle RoPE';

  @override
  String get settingLabelDraftModelId =>
      'Modèle brouillon (décodage spéculatif)';

  @override
  String get hostLocalOnly => 'Réseau local et VPN uniquement';

  @override
  String get hostLocalOnlyHint =>
      'Les appareils sur ce Wi-Fi, votre point d’accès ou votre VPN (Tailscale, WireGuard…) peuvent se connecter avec le jeton. Les requêtes venant d’internet sont refusées.';

  @override
  String settingEmptyMeans(String value) {
    return 'Vide = $value';
  }

  @override
  String settingEffectiveValue(String value) {
    return 'Valeur effective : $value';
  }

  @override
  String settingInherit(String value) {
    return 'Hériter ($value)';
  }

  @override
  String get remoteScanQr => 'Scanner un code QR';

  @override
  String get remoteScanHint =>
      'Pointez la caméra vers le code QR de l’autre téléphone (Réglages > Utiliser cet appareil comme serveur).';

  @override
  String get remoteScanInvalid =>
      'Ce code QR n’est pas une connexion OnDevice LLM. Visez le code du serveur.';

  @override
  String remoteScanNoCamera(String error) {
    return 'La caméra n’est pas disponible : $error';
  }

  @override
  String get remoteNameConnection => 'Nommez cette connexion';

  @override
  String get remoteNameHint => 'Par exemple : PC du salon';

  @override
  String get answerFromMemory =>
      'Tiré de la mémoire du modèle — peut être dépassé.';

  @override
  String get searchTheWeb => 'Chercher sur le web';

  @override
  String get searchMissesTitle => 'Questions envoyées au web à la main';

  @override
  String searchMissesHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count questions. Copiez-les pour améliorer les mots-clés de recherche ; sinon elles ne quittent jamais ce téléphone.',
      one:
          '1 question. Copiez-les pour améliorer les mots-clés de recherche ; sinon elles ne quittent jamais ce téléphone.',
      zero:
          'Aucune pour l’instant. Quand une réponse venait de la mémoire et que vous avez touché Chercher sur le web, la question est gardée ici (sur ce téléphone seulement) pour améliorer les mots-clés de recherche.',
    );
    return '$_temp0';
  }

  @override
  String get commonCopied => 'Copié.';

  @override
  String get settingsSearchSection => 'Recherche';

  @override
  String searchRegionHint(String region) {
    return 'D’où viennent les nouvelles et les résultats de recherche. Automatique suit la langue de l’app et le pays du téléphone (actuellement $region).';
  }

  @override
  String get searchRegionAutomatic => 'Automatique';

  @override
  String get researchLoopHint =>
      'Les questions à rechercher sont traitées par le modèle lui-même : il cherche, choisit les pages à lire, cherche de nouveau au besoin, puis répond avec des citations. Les liens collés sont toujours lus directement. Plus lent par question ; comparez sur vos propres questions.';

  @override
  String get researchLoopNeedsTools =>
      'Nécessite l’appel d’outils activé avec les outils web (Réglages > Outils).';

  @override
  String get selectionTitle => 'Que faire du texte sélectionné ?';

  @override
  String get selectionExplain => 'L’expliquer';

  @override
  String get selectionSummarize => 'Le résumer';

  @override
  String get selectionTranslate => 'Le traduire';

  @override
  String get selectionFix => 'Corriger l’orthographe et la grammaire';

  @override
  String get selectionAsk => 'Poser une question dessus';

  @override
  String get quickDescribe => 'Décrire';

  @override
  String get quickDescribePrompt => 'Décris cette photo en détail.';

  @override
  String get quickExtractText => 'Extraire le texte';

  @override
  String get quickExtractTextPrompt =>
      'Transcris tout le texte de cette image exactement tel qu’il est écrit, en gardant la mise en page.';

  @override
  String get quickTranslate => 'Traduire';

  @override
  String get quickTranslatePrompt =>
      'Traduis tout le texte de cette image en français.';

  @override
  String get quickSolve => 'Résoudre';

  @override
  String get quickSolvePrompt =>
      'Résous le problème montré dans cette image et explique chaque étape.';

  @override
  String get quickExplain => 'Expliquer';

  @override
  String get quickExplainPrompt =>
      'Explique ce que montre cette image et pourquoi c’est important.';

  @override
  String get quickIdentify => 'Identifier';

  @override
  String get quickIdentifyPrompt =>
      'Qu’est-ce que c’est ? Identifie-le et dis-moi ce que tu en sais.';

  @override
  String get quickSummarise => 'Résumer';

  @override
  String get quickSummarisePrompt =>
      'Résume ce document : l’essentiel en une phrase, puis les points clés.';

  @override
  String get quickKeyPoints => 'Points clés';

  @override
  String get quickKeyPointsPrompt =>
      'Liste les points clés de ce document en courtes puces.';

  @override
  String get quickExplainSimply => 'Expliquer simplement';

  @override
  String get quickExplainSimplyPrompt =>
      'Explique ce document en langage simple pour quelqu’un qui découvre le sujet.';

  @override
  String get quickActionItems => 'Actions à faire';

  @override
  String get quickActionItemsPrompt =>
      'Liste chaque action à faire, échéance et décision de ce document.';

  @override
  String get quickQuestions => 'Questions';

  @override
  String get quickQuestionsPrompt =>
      'Quelles questions devrais-je me poser sur ce document avant de m’y fier ?';

  @override
  String get sectionVoice => 'Voix';

  @override
  String get sectionAutomation => 'Raccourcis et automatisation';

  @override
  String get sectionModelConnections => 'Modèle et connexions';

  @override
  String get sectionAppearanceLanguage => 'Apparence et langue';

  @override
  String get sectionData => 'Vos données';

  @override
  String get advancedNote =>
      'Les réglages par défaut conviennent. Ceux-ci servent à affiner la vitesse, la mémoire et la sortie.';

  @override
  String get remoteRowOff => 'Désactivé · le modèle tourne sur ce téléphone';

  @override
  String get backupRowHint =>
      'Sauvegarder ou restaurer conversations, pièces jointes et réglages';

  @override
  String remoteRowOn(String name) {
    return 'Activé · $name';
  }

  @override
  String get sectionCachePrecision => 'Précision du cache';

  @override
  String get sectionCapabilities => 'Capacités';

  @override
  String get sectionConnections => 'Connexions';

  @override
  String get sectionEvidence => 'Sources fournies au modèle';

  @override
  String get sectionExtraSamplers => 'Échantillonneurs supplémentaires';

  @override
  String get sectionLayers => 'Couches, de la plus basse à la plus haute';

  @override
  String get sectionPenalties => 'Pénalités';

  @override
  String get sectionRope => 'Encodage de position (RoPE / YaRN)';

  @override
  String get sectionReasoning => 'Raisonnement';

  @override
  String get sectionReproducibility => 'Reproductibilité';

  @override
  String get sectionSamplerOrder => 'Ordre des échantillonneurs';

  @override
  String get sectionSpeculative => 'Décodage spéculatif (expérimental)';

  @override
  String get sectionTools => 'Outils';

  @override
  String get chatSettingsMenu => 'Réglages de cette conversation';

  @override
  String chatSettingsMenuCount(int count) {
    return 'Réglages de cette conversation · $count';
  }

  @override
  String remoteUsingSummary(String name, String host) {
    return 'Les conversations passent par $name ($host). Les modèles locaux ne sont pas chargés.';
  }

  @override
  String get remoteNeedsConnection =>
      'Ajoutez une connexion ci-dessous pour l’activer.';

  @override
  String get remoteNeedsUrl =>
      'La connexion choisie doit avoir une adresse http(s) valide.';

  @override
  String get remoteNoUrl => 'pas d’adresse';

  @override
  String get remoteNoKey => 'pas de clé';

  @override
  String get remoteScanShort => 'Scanner QR';

  @override
  String get remotePasteShort => 'Coller';

  @override
  String get modelProfile => 'Profil';

  @override
  String modelProfileCount(int count) {
    return 'Profil · $count';
  }

  @override
  String get modelsFootnote =>
      'Les modèles plus grands répondent mieux, mais sont plus lents et utilisent plus de mémoire. Le badge de chaque modèle indique s’il convient à ce téléphone.';

  @override
  String get benchmarkRunAgain => 'Relancer';

  @override
  String benchmarkMeasuredAt(String date) {
    return 'Mesuré le $date';
  }

  @override
  String get unloadShort => 'Décharger';

  @override
  String get unsavedChanges => 'Modifications non enregistrées';

  @override
  String get savedNotice => 'Enregistré';

  @override
  String get pickerLibrary => 'Bibliothèque';

  @override
  String get pickerConnections => 'Connexions';

  @override
  String get pickerReasoning => 'raisonnement';

  @override
  String get pickerTightRam => 'RAM limite';

  @override
  String get pickerTooLarge => 'trop gros pour ce téléphone';

  @override
  String get pickerNoKey => 'pas encore de clé';

  @override
  String get goalPhaseVerifying =>
      'Vérification du rapport par rapport aux résultats';

  @override
  String get goalGuardrails => 'Garde-fous';

  @override
  String get goalSubjectTitle => 'Rester sur ces noms';

  @override
  String get goalSubjectHint =>
      'Trouvés dans votre objectif. Le modèle doit les utiliser tels quels ; les pages sur des modèles, versions ou générations voisins sont écartées.';

  @override
  String get goalSubjectNone =>
      'Aucun nom pour l’instant : les produits, personnes et lieux de votre objectif s’affichent ici pendant la saisie.';

  @override
  String get goalSubjectAdd => 'Ajouter un nom';

  @override
  String get goalSubjectExample => 'ex. Sony ZV-E10';

  @override
  String get goalSubjectReset => 'Réinitialiser';

  @override
  String get goalRulesLabel => 'Vos règles (facultatif)';

  @override
  String get goalRulesHint =>
      'Une par ligne, ex. Prix en CAD · Sources de 2026 seulement · Pas de rumeurs';

  @override
  String get goalRulesBuiltIn => 'Règles suivies par chaque objectif';

  @override
  String get goalRuleSubject =>
      'Utilise vos noms tels quels ; ne les remplace jamais par un modèle, une version ou une génération voisine.';

  @override
  String get goalRuleEvidence =>
      'N’affirme que ce que disent les sources, chaque fait avec sa citation ; rien de mémoire.';

  @override
  String get goalRuleOffTopic =>
      'Ignore les sources hors sujet et dit ce qui manque ; ne vous demande jamais de sources.';

  @override
  String get goalRuleFigures =>
      'Recopie exactement chiffres, dates et prix ; donne les deux versions quand les sources divergent.';

  @override
  String get goalRuleThinking =>
      'Réfléchit brièvement avant le plan et la vérification des preuves ; les étapes et le rapport répondent directement, pour une recherche plus rapide.';

  @override
  String get goalRuleCheck =>
      'Chaque étape et le rapport sont vérifiés automatiquement ; une vérification échouée est refaite une fois.';

  @override
  String goalCheckDrift(String names) {
    return 'Mentionne $names, qui n’est pas le sujet de l’objectif';
  }

  @override
  String goalCheckOffTarget(String names) {
    return 'A étudié $names à la place : écarté du rapport';
  }

  @override
  String get goalCheckNoSources => 'Aucune source trouvée';

  @override
  String get goalCheckNoCitations => 'Ne cite aucune source';

  @override
  String goalCheckBadCitations(String numbers) {
    return 'Cite des sources inexistantes : $numbers';
  }

  @override
  String goalCheckFigures(String figures) {
    return 'Chiffres absents des sources : $figures';
  }

  @override
  String goalCheckDroppedFigures(String figures) {
    return 'Chiffres retirés, absents des sources : $figures';
  }

  @override
  String get goalCheckAskedUser => 'Vous a demandé des informations';

  @override
  String get goalCheckRetried =>
      'Étudiée à nouveau après une vérification échouée';

  @override
  String get goalCheckRevised =>
      'Réécrit une fois pour corriger la vérification';

  @override
  String get goalReportChecked =>
      'Vérifié : noms, citations et chiffres conformes aux résultats';

  @override
  String get goalStepSearched => 'Recherches';

  @override
  String get goalStepTools => 'Appels d’outils';

  @override
  String get goalStepSources => 'Sources';

  @override
  String get goalStepReasoning => 'Raisonnement';

  @override
  String goalStepStats(int prompt, int tokens, String seconds, String tps) {
    return '$prompt jetons lus + $tokens générés · $seconds s · $tps jetons/s';
  }

  @override
  String goalStepSearchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recherches',
      one: '1 recherche',
    );
    return '$_temp0';
  }

  @override
  String goalStepToolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count appels d’outils',
      one: '1 appel d’outil',
    );
    return '$_temp0';
  }

  @override
  String get goalPlanNotes => 'Comment le plan a été fait';

  @override
  String get goalReviewNotes => 'Raisonnement de la relecture';

  @override
  String get goalCheckLeak => 'Raisonnement mêlé à la réponse retiré';

  @override
  String goalSmallModel(String model) {
    return '$model est un petit modèle : les objectifs sont bien plus fiables avec Gemma 4 E2B ou un modèle plus grand (il reste sur le sujet et cite ses sources).';
  }

  @override
  String get goalPartial =>
      'Résultat partiel — davantage de preuves nécessaires';

  @override
  String get goalCriteriaReview => 'Critères de réussite';

  @override
  String goalEvidenceSteps(String steps) {
    return 'Preuves : étapes $steps';
  }

  @override
  String get backupExportReady =>
      'Sauvegarde chiffrée transmise au menu de partage.';

  @override
  String get remoteShareMemory => 'Partager la mémoire avec cette connexion';

  @override
  String get remoteShareMemoryHint =>
      'Autoriser les notes sélectionnées dans les requêtes à ce serveur.';

  @override
  String get remoteLearnMemory => 'Mémoriser avec cette connexion';

  @override
  String get remoteLearnMemoryHint =>
      'Autoriser une requête distincte au serveur pour extraire des faits durables de vos messages. Les faits explicites simples peuvent toujours être enregistrés localement lorsque la mémoire est activée.';

  @override
  String get memoryPin => 'Toujours considérer cette note';

  @override
  String get memoryUnpin => 'Détacher la note';

  @override
  String get memoryReconfirm => 'Confirmer que ceci est toujours exact';

  @override
  String get memoryExpire => 'Expirer dans 30 jours';

  @override
  String get memoryNoExpiry => 'Retirer la date d’expiration';

  @override
  String memoryExpires(String date) {
    return 'Expire le $date';
  }

  @override
  String get settingsSearch => 'Rechercher des réglages';

  @override
  String get settingsFaster => 'Réponses plus rapides';

  @override
  String get settingsDetailed => 'Plus de détails';

  @override
  String get settingsLessMemory => 'Utiliser moins de RAM';

  @override
  String get imageTokenBudget => 'Budget de jetons par photo';

  @override
  String get imageTokenBudgetHint =>
      'Plus de détails utilise plus de mémoire et de temps. Recharge le modèle.';

  @override
  String get documentPreview => 'Aperçu';

  @override
  String get documentEdit => 'Modifier';

  @override
  String get documentDraftSaved => 'Brouillon enregistré sur cet appareil';

  @override
  String get documentVersions => 'Historique des versions';

  @override
  String get goalQuestionsTitle => 'Quelques questions d’abord';

  @override
  String get goalQuestionsHint =>
      'Vos préférences peuvent améliorer le rapport. Choisissez une réponse, écrivez la vôtre ou passez. La recherche attend votre décision.';

  @override
  String get goalYourAnswer => 'Votre réponse (facultative)';

  @override
  String get goalQuestionsLater => 'Plus tard';

  @override
  String get goalQuestionsSkip => 'Passer et continuer';

  @override
  String get goalPhaseClarifying => 'Vérification du besoin de précisions…';

  @override
  String get goalWaitingAnswers => 'En attente de vos réponses';

  @override
  String get goalAnswerQuestions => 'Répondre aux questions';

  @override
  String get goalClarificationAnswers => 'Vos précisions';

  @override
  String get goalAssumptionsAllowed =>
      'Question passée — le rapport précisera ses hypothèses.';

  @override
  String get goalSearchGuidance => 'Orientation des recherches et du rapport';

  @override
  String get goalSearchGuidanceHint =>
      'Expliquez les informations manquantes, les questions à rechercher et les points à privilégier.';

  @override
  String get goalRefineRun => 'Enregistrer et rechercher';

  @override
  String get goalCriteriaSeparate =>
      'Une exigence par ligne pour mesurer la couverture.';

  @override
  String goalCoverage(Object percent, Object target) {
    return 'Exigences étayées : $percent% · seuil $target%';
  }

  @override
  String get goalCompletionHint =>
      'Arrêter quand cette part des exigences est étayée. Les lacunes restent visibles ; les citations et vérifications restent obligatoires.';

  @override
  String get goalCompletionTarget => 'Seuil de réalisation';

  @override
  String get goalRefine => 'Modifier / orienter la recherche';

  @override
  String memoryScanResult(Object count) {
    return '$count souvenirs récupérés dans les discussions.';
  }

  @override
  String get memoryScanHistory =>
      'Rechercher les souvenirs manqués dans les discussions';

  @override
  String get goalEvidenceWorkspace => 'Comparer les preuves';

  @override
  String get goalEvidenceSnapshotHint =>
      'Comparez les extraits enregistrés avec les résultats des étapes. Ce sont les extraits utilisés par le modèle ; la page actuelle peut avoir changé. Une source ou un contrôle automatique réussi ne prouve pas à lui seul une affirmation.';

  @override
  String get goalEvidenceSupported => 'Exigence étayée';

  @override
  String get goalEvidenceGap => 'Preuves nécessaires pour cette exigence';

  @override
  String get goalEvidenceMissing =>
      'Aucun extrait récupéré enregistré pour cette source.';

  @override
  String get goalEvidenceFind => 'Rechercher du texte dans ces sources';

  @override
  String get goalEvidencePublished => 'Publié';

  @override
  String get goalEvidenceRetrieved => 'Récupéré';

  @override
  String get goalEvidenceOpen => 'Ouvrir la page';

  @override
  String get goalEvidenceCopy => 'Copier l’extrait';

  @override
  String get goalEvidenceNoMatch =>
      'Aucun résultat dans cet extrait enregistré.';

  @override
  String get goalEvidenceExcluded =>
      'Cette étape a été exclue des preuves du rapport.';

  @override
  String get contextInspector => 'Inspecteur de contexte';

  @override
  String get contextSnapshotHint =>
      'Sélection du contexte enregistrée pour cette réponse. Les extraits permettent de l’inspecter ; ils ne servent pas automatiquement de résumés pour les réponses futures.';

  @override
  String get contextSnapshotMissing =>
      'Cette ancienne réponse n’a pas de contexte enregistré.';

  @override
  String get contextTokens => 'Jetons du contexte';

  @override
  String get contextIsolated =>
      'Cette requête utilise la question actuelle sans les échanges précédents.';

  @override
  String get contextInstructions => 'Instructions fournies au modèle';

  @override
  String get contextCharacters => 'caractères';

  @override
  String get contextMessages => 'Messages de la conversation';

  @override
  String get contextIncluded => 'Inclus';

  @override
  String get contextOmittedIsolated => 'Omis pour cette requête indépendante';

  @override
  String get contextOmittedLimit =>
      'Omis pour respecter la limite du contexte ; conservé dans l’historique';

  @override
  String get contextImages => 'images';

  @override
  String get contextDocuments => 'documents';

  @override
  String get contextSnippetOnly =>
      'Extrait de recherche uniquement ; page non lue';

  @override
  String get contextStale => 'Les preuves en cache peuvent être périmées';

  @override
  String get goalModelLabel => 'Modèle';

  @override
  String get goalModelNone => 'Aucun modèle local prêt';

  @override
  String get goalModelOnStart => 'chargé au démarrage de l’objectif';

  @override
  String get contextOmitted => 'Omis';

  @override
  String get contextEarlierHidden =>
      'Aperçus des messages antérieurs non affichés';

  @override
  String contextCapTrain(String size) {
    return 'Contexte réglé à $size jetons, le maximum pour lequel ce modèle a été entraîné.';
  }

  @override
  String contextCapMemory(String size) {
    return 'Contexte réglé à $size jetons pour que le modèle tienne dans la mémoire libre.';
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

    return 'Mémoire libre insuffisante pour ce modèle : il lui faut environ $needString Mo et $freeString Mo sont libres. Fermez d’autres applications ou choisissez un modèle plus petit.';
  }

  @override
  String contextTrainedFor(String size) {
    return 'Le modèle chargé a été entraîné pour $size jetons.';
  }

  @override
  String contextTrainedForCapped(String size) {
    return 'Le modèle chargé a été entraîné pour $size jetons. Un contexte plus grand est ramené à cette taille au chargement, sauf si une mise à l’échelle RoPE est réglée dans Mémoire, RoPE et spéculation.';
  }

  @override
  String contextTrainedForStretched(String size) {
    return 'Le modèle chargé a été entraîné pour $size jetons ; la mise à l’échelle RoPE l’étend au-delà, et la qualité peut baisser.';
  }

  @override
  String get photosAndVoiceNotes => 'Photos et notes vocales';

  @override
  String photosAndVoiceNotesBody(Object mb) {
    return 'Retrouvez les photos par ce qu’elles montrent et les enregistrements par ce qu’ils disent, avec les mêmes questions que vos documents. Fonctionne sur le téléphone ; ~$mb Mo une seule fois.';
  }

  @override
  String get photosAndVoiceNotesReady =>
      'Les photos et les enregistrements sont retrouvés par ce qu’ils montrent ou disent.';

  @override
  String noticeClaimsNotInSources(String claims, String more) {
    return 'Non étayé par les sources : $claims$more. Vérifiez ces affirmations avant de vous y fier.';
  }

  @override
  String noticeClaimsNames(String details) {
    return 'noms ou dates absents des sources : $details';
  }

  @override
  String get naturalVoiceTitle => 'Voix naturelle sur l\'appareil';

  @override
  String get naturalVoiceHint =>
      'Whisper écoute et Kokoro parle, entièrement sur ce téléphone. Utilise la voix du système tant qu\'ils ne sont pas téléchargés.';

  @override
  String get talkOverTitle => 'Parler par-dessus la réponse';

  @override
  String get talkOverHint =>
      'En conversation, interrompez en parlant. La réponse sonne alors comme un appel. Désactivé : son clair, touchez pour interrompre.';

  @override
  String get spokenLengthTitle => 'Longueur des réponses parlées';

  @override
  String get spokenLengthHint =>
      'La part d\'une réponse que Conversation dit à voix haute. Les listes sont toujours lues en entier.';

  @override
  String get spokenLengthShort => 'Courte (3 phrases)';

  @override
  String get spokenLengthLonger => 'Plus longue (6 phrases)';

  @override
  String get spokenLengthFull => 'Réponse entière';

  @override
  String get voiceListeningPack => 'Écoute (Whisper)';

  @override
  String get voiceSpeakingPack => 'Parole (Kokoro)';

  @override
  String get listeningModelTitle => 'Modèle d\'écoute';

  @override
  String get listeningModelHint =>
      'Parakeet v3 a entendu toutes les phrases de test sur le téléphone et répond plus vite que Whisper ; il comprend aussi mieux le français et l\'espagnol. Il se télécharge à part et utilise plus de mémoire pendant que vous parlez. Parakeet TDT 0.6B v3 par NVIDIA, CC BY 4.0.';

  @override
  String get listeningWhisper => 'Whisper base';

  @override
  String get listeningParakeet => 'Parakeet v3';

  @override
  String get voiceUnpacking => 'Décompression…';

  @override
  String get voicePick => 'Voix';

  @override
  String get voiceTry => 'Essayer';

  @override
  String get voiceSample =>
      'Bonjour ! Voici ma voix quand je lis vos réponses à voix haute.';

  @override
  String get voiceDownloadBoth => 'Télécharger la voix sur l\'appareil';

  @override
  String get conversationTitle => 'Conversation';

  @override
  String get convListening => 'J\'écoute…';

  @override
  String get convThinking => 'Je réfléchis…';

  @override
  String get convLookingUp => 'Je cherche…';

  @override
  String get convSpeaking => 'Je parle · parlez pour m\'interrompre';

  @override
  String get convSpeakingTap => 'Je parle · touchez pour m\'interrompre';

  @override
  String get convPaused => 'Micro coupé';

  @override
  String get convNeedsVoice =>
      'Pour une conversation naturelle, mains libres, téléchargez la voix sur l\'appareil (environ 290 Mo). En attendant, la voix du système est utilisée.';

  @override
  String convModelMissing(String model) {
    return '$model n\'est pas téléchargé : un autre modèle téléchargé répond. Téléchargez-le dans Modèles, ou choisissez un modèle avec le bouton en haut à droite.';
  }

  @override
  String get convNoModel => 'Chargez d\'abord un modèle.';

  @override
  String get convModelTitle => 'Modèle de conversation';

  @override
  String get convModelHint =>
      'La conversation répond avec Qwen3.5 0.8B sur le téléphone : elle commence à parler en quelques secondes. Avec une connexion distante active, son modèle peut répondre à la place.';

  @override
  String get convModelRemote =>
      'Cherche de lui-même au besoin et se souvient de toute la conversation';

  @override
  String convRemoteFailed(String error) {
    return 'La connexion distante n\'a pas répondu ($error). Je réponds sur le téléphone.';
  }

  @override
  String get convModelFastest => 'le plus rapide';

  @override
  String get convMicDenied =>
      'Le micro n\'est pas autorisé. Autorisez-le dans les réglages du téléphone pour parler.';

  @override
  String get convEnd => 'Terminer la conversation';

  @override
  String get convStopAnswer => 'Arrêter la réponse';

  @override
  String get convMute => 'Couper le micro';

  @override
  String get convUnmute => 'Activer le micro';

  @override
  String convLoadingModel(String model) {
    return 'Chargement de $model…';
  }

  @override
  String get convHint =>
      'Parlez simplement. Je réponds à voix haute ; parlez par-dessus pour m\'interrompre.';

  @override
  String get convInterrupt => 'Interrompre';

  @override
  String get actionEvent => 'Ajouter à l\'agenda';

  @override
  String get actionReminder => 'Ajouter le rappel';

  @override
  String get actionAlarm => 'Régler l\'alarme';

  @override
  String get actionTimer => 'Lancer le minuteur';

  @override
  String get actionMessage => 'Ouvrir le brouillon';

  @override
  String get actionFile => 'Enregistrer ou partager';

  @override
  String get actionNoApp => 'Aucune app de ce téléphone ne peut le faire.';

  @override
  String get actionConfirmHint =>
      'Préparé pour vous : vous confirmez dans l\'app qui s\'ouvre.';

  @override
  String get actionConfirmDone => 'J’ai effectué cette action';

  @override
  String actionConfirmedAt(String time) {
    return 'Confirmé à $time';
  }

  @override
  String get goalAwaitingActions =>
      'En attente de votre confirmation de l’action';

  @override
  String get actionReadyAnswer =>
      'C\'est prêt. Vérifiez la carte ci-dessous et touchez son bouton pour terminer.';

  @override
  String get echoedAnswer =>
      'Le modèle a recopié ses instructions au lieu de répondre : aucune réponse n\'est affichée. Ouvrez les sources ci-dessous ou reformulez la question.';

  @override
  String get goalActionsTitle => 'Prêt à faire';

  @override
  String get goalSaveReport => 'Enregistrer le rapport';

  @override
  String get goalWatch => 'Surveiller chaque jour';

  @override
  String goalWatchSet(String time) {
    return 'Surveillance quotidienne à $time. Une recherche en arrière-plan vérifie les changements et vous avertit si un résultat est nouveau ou si une valeur change. L’objectif complet ne se relance que sur demande.';
  }

  @override
  String get goalPreparingActions => 'Préparation des actions…';

  @override
  String get goalPhaseDelivering => 'Préparation de ce que l\'objectif demande';

  @override
  String goalNotPrepared(String item, String reason) {
    return 'Non préparé : $item ($reason)';
  }

  @override
  String goalDeliverableFile(String format) {
    return 'le fichier $format';
  }

  @override
  String get goalDeliverableEvent => 'l\'événement d\'agenda';

  @override
  String get goalDeliverableReminder => 'le rappel';

  @override
  String get goalDeliverableAlarm => 'l\'alarme';

  @override
  String get goalDeliverableTimer => 'le minuteur';

  @override
  String get goalDeliverableMessage => 'le brouillon de message';

  @override
  String get goalNotPreparedStopped => 'l\'objectif a été arrêté';

  @override
  String get goalNotPreparedBudget => 'le budget de l\'objectif est épuisé';

  @override
  String get goalNotPreparedUnreadable =>
      'la réponse du modèle était illisible';

  @override
  String get goalNotPreparedTooLong =>
      'le rapport est trop long pour un seul fichier';

  @override
  String get goalNotPreparedNone => 'le modèle n\'en a proposé aucun';

  @override
  String goalNotPreparedInvalid(String problem) {
    return 'la proposition du modèle était incomplète : $problem';
  }

  @override
  String get goalWatchesTitle => 'Objectifs surveillés';

  @override
  String get goalWatchChecking => 'Vérification…';

  @override
  String get goalWatchWebOff => 'La recherche web est désactivée';

  @override
  String get goalWatchNoResults => 'La recherche n\'a rien trouvé';

  @override
  String get goalWatchOffline => 'Recherche impossible (hors ligne ?)';

  @override
  String get goalWatchNotYet => 'Pas encore vérifié';

  @override
  String goalWatchBaseline(String when) {
    return 'Premiers résultats gardés $when';
  }

  @override
  String goalWatchNoChange(String when) {
    return 'Aucun changement · $when';
  }

  @override
  String goalWatchChanged(int fresh, int figures, String when) {
    return '$fresh nouveaux, $figures chiffres changés · $when';
  }

  @override
  String goalWatchDailyAt(String time) {
    return 'chaque jour à $time';
  }

  @override
  String goalWatchNewResult(String title) {
    return 'Nouveau : $title';
  }

  @override
  String get goalWatchCheckNow => 'Vérifier maintenant';

  @override
  String get goalWatchRunAgain => 'Relancer l\'objectif';

  @override
  String get goalWatchStop => 'Arrêter la surveillance';

  @override
  String actionOpenedAt(String time) {
    return 'Ouvert à $time : confirmez-le là-bas';
  }

  @override
  String get remoteServerSettings => 'Utiliser les réglages du serveur';

  @override
  String get remoteServerSettingsHint =>
      'La température, l\'échantillonnage, la longueur des réponses et le contexte viennent du modèle de cette connexion (les valeurs par défaut de Gemini, les réglages avec lesquels LM Studio l\'a chargé…), pas des préréglages du téléphone.';

  @override
  String get sheetAttachments => 'Pièces jointes et outils';

  @override
  String get sheetNotice => 'Notification';
}
